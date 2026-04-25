# Hashing, HMAC and signing

`TSynSigner` is the unified hash / HMAC / SHA-3 frontend in `mormot.crypt.secure`. It is a `record` (or `object` on FPC) on purpose: no allocation, lives on the stack, can be reused across calls by re-`Init`-ing. The same struct also drives PBKDF2, the modular-crypt password formats, and the SP 800-108 KDF.

## Algorithm matrix: TSignAlgo

```pascal
type
  TSignAlgo = (
    saSha1,                                  // 20-byte digest, legacy
    saSha256, saSha384, saSha512,            // SHA-2 family
    saSha3224, saSha3256, saSha3384,         // SHA-3 keccak
    saSha3512,
    saSha3S128, saSha3S256,                  // SHAKE128 / SHAKE256 XOFs
    saSha224);
```

`SIGN_SIZE[TSignAlgo]` returns the digest size in bytes. `SIGNER_TXT[TSignAlgo]` returns the canonical text identifier (`'SHA-256'`, `'SHA3-512'`, `'SHAKE128'`).

The framework's preferences:
- **Default for new HMAC code**: `saSha256`. Universally available, hardware-accelerated, RFC 6234.
- **For high-throughput application keys**: `saSha3S128` (SHAKE128) is `SIGNER_DEFAULT_ALGO` and gives you an arbitrary-output-length pseudo-random function in one shot.
- **For interop**: `saSha256` or `saSha512`. Anything else you will explain on the wire.
- **Avoid**: `saSha1`. Still useful for HMAC under specific protocol requirements (TOTP, PBKDF2-SHA1 in modular crypt format), but not for new contracts. Never use it as a content hash.

## Three usage patterns

### Hash (no key)

```pascal
var
  Sig: TSynSigner;
  Digest: RawUtf8;
begin
  Digest := Sig.Hash(saSha256, @Buffer[0], length(Buffer));   // hex string
end;
```

For one-shot SHA-256 over a `RawByteString`, the bare `Sha256Hex(Data)` helper in `mormot.crypt.core` is shorter and equally fast.

### HMAC (keyed)

```pascal
var
  Sig: TSynSigner;
  Mac: RawUtf8;
begin
  Mac := Sig.Full(saSha256, 'shared-secret', Body);
  // 64-char hex, suitable for cookie integrity, manifest signing, webhook auth.
end;
```

`Full` is shorthand for `Init` + `Update` + `Final`. For incremental work (large files, streaming), call them explicitly:

```pascal
Sig.Init(saSha512, 'secret');
while Reader.Read(Chunk, 4096) > 0 do
  Sig.Update(@Chunk[0], Reader.LastReadCount);
Mac := Sig.Final;
```

### PBKDF2 (key derivation)

```pascal
var
  Sig: TSynSigner;
  Key: THash512Rec;
begin
  Sig.Pbkdf2(saSha256, 'passphrase', Salt, 600000, Key);
  // Key.Lo holds the first 32 bytes; use Key.b for raw access.
end;
```

The 600,000-round figure for PBKDF2-SHA-256 matches `MCF_ROUNDS[mcfPbkdf2Sha256]` and is the OWASP 2025 recommendation. Lower it only when you can prove (a) the secret is high-entropy and (b) the timing budget genuinely cannot afford it.

`Pbkdf2` also accepts a `TSynSignerParams` record or a JSON config string, which is useful for "store the KDF parameters next to the wrapped key" patterns:

```json
{"algo":"sha-512","secret":"$kek","salt":"perKey16Bytes","rounds":200000}
```

## SP 800-108 KDF

`TSynSigner.KdfSP800` is the NIST SP 800-108 counter-mode KDF: derive multiple keys from one master key plus per-context labels. Use it instead of "hash the master key with a string suffix" (which is also fine in practice, but SP 800-108 is the standard answer when an auditor asks).

```pascal
Sig.KdfSP800(saSha256, 64, MasterKey, 'session-' + UserId, OutputBuffer);
```

## Modular Crypt Format for password storage

`TSynSigner.Pbkdf2ModularCrypt` produces a self-describing string. The format is `$<scheme>$<rounds>$<base64 salt>$<base64 hash>$`.

```pascal
var
  Sig: TSynSigner;
  Stored: RawUtf8;
begin
  Stored := Sig.Pbkdf2ModularCrypt(mcfPbkdf2Sha256, 'user-password');
  //  $pbkdf2-sha256$600000$<salt>$<hash>$
end;
```

Rounds come from `MCF_ROUNDS`, which the framework keeps current (PBKDF2-SHA-1 = 1,300,000; PBKDF2-SHA-256 = 600,000; PBKDF2-SHA-512 = 210,000 as of 2025). The global is mutable; tune it once at boot if you need different policy.

`ModularCryptVerify('user-password', Stored)` parses any supported scheme and verifies in constant time, so the same call sites work regardless of which scheme produced the stored hash. Use that to migrate from one scheme to another: verify with the legacy scheme, then on success rewrite the row with the new one.

`mcfBCryptSha256` and `mcfSCrypt` require `mormot.crypt.other.pas` in the unit list. They are the recommended schemes for new password storage; PBKDF2 stays in the list for compatibility and for environments where the additional unit is unwelcome.

## Manifest and code signing

For "this artifact came from us, untampered" use cases that do not need asymmetric verification, an HMAC over the artifact plus a pinned key is enough:

```pascal
var
  Sig: TSynSigner;
  Key, Mac: RawUtf8;
begin
  Key := GetEnvVariable('RELEASE_HMAC_KEY');           // 32+ bytes random, base64 in env
  Mac := Sig.Full(saSha256, Key, FileBytes);
  WriteFile('release.tar.gz.mac', Mac);                // ship alongside
end;
```

Verifier reproduces the HMAC and rejects mismatches. The shared key is the weak point: if it leaks, attackers forge releases. Rotate on a schedule, not just on incident.

For asymmetric signing (consumers verify with a public key only), use `TEccCertificateSecret.Sign` and ship `TEccCertificate` to verifiers. The signature is a raw `TEccSignature` (64 bytes); convert to PEM with `EccToDer` + DER-to-PEM if you need text format.

```pascal
Sec.Sign(@FileBytes[0], length(FileBytes), Sig);
// Verifier:
if not Pub.Verify(@FileBytes[0], length(FileBytes), Sig) then
  raise ESecurity.Create('release tampered');
```

## TSynLog archive signing

`TSynLog` can chain a `TSynSigner` into its rotation pipeline so each rotated archive carries an HMAC (or a chain HMAC, where each archive's MAC includes the previous one's, making single-file deletion detectable). Configure via the `EchoCustom` event or the family-level `OnRotate` hook; the signer's `Init` runs at rotation, `Update` over the buffered file, `Final` writes the tag into the rotation index.

Pair this with append-only storage (object lock, immutable bucket) and the resulting log stream is forensically useful: tampering or deletion shows up as a broken chain.

## Common errors

- **`Pbkdf2(saSha3S128, ..., DestLen=...)` raises `ESynCrypto`.** SHAKE algorithms produce arbitrary-length output natively; the framework refuses to wrap them in PBKDF2 because the construction is non-standard. Use `saSha256` or `saSha512` for PBKDF2 or `KdfSP800` with a SHAKE algorithm if you actually want a SHAKE-based KDF.
- **`MAX_PBKDF2_ROUNDS` (5,000,000) accepted at runtime but blocking the request loop.** The hard cap is there to flag "I copy-pasted from a Stack Overflow answer that lost a zero" mistakes, not as a recommendation. 600,000 SHA-256 rounds is the right ballpark for interactive auth.
- **Hex output where you expected raw.** `TSynSigner.Final: RawUtf8` returns hex. For raw bytes, use `Final(@Buf, NoInit)` and read `SIGN_SIZE[Algo]` bytes from `Buf`.
