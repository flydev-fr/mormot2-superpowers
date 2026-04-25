---
name: mormot2-auth-security
description: Use when working with mORMot 2 cryptography and authentication primitives: JWT, ECC (secp256r1), AES-GCM, SHA-256/512, password hashing, session token generation, signing/verifying. Do NOT use for REST session lifecycle (use mormot2-rest-soa) or TLS/ACME (use mormot2-net).
---

# mormot2-auth-security

mORMot 2 cryptographic primitives and authentication building blocks: JWTs (`mormot.crypt.jwt`), ECC P-256 keys, certificates and ECIES encryption (`mormot.crypt.ecc`), AES-GCM authenticated encryption (`mormot.crypt.core`), HMAC and PBKDF2 key derivation (`mormot.crypt.secure.TSynSigner`), modular-crypt password hashes including BCrypt and SCrypt (`mormot.crypt.other`), and the OpenSSL backend that swaps these in when available (`mormot.crypt.openssl`). This skill covers the algorithms and the key material. Sibling skills cover what sits on top: `mormot2-rest-soa` owns the `TRestServer` session and authentication scheme that consumes JWTs and password hashes; `mormot2-net` owns TLS contexts and Let's Encrypt cert lifecycle; `mormot2-core` owns the `RawUtf8` and RTTI conventions every example below depends on.

## When to use

- Issuing or verifying a JWT signed with HMAC (`TJwtHS256`, `TJwtHS512`), ECDSA P-256 (`TJwtEs256`), or any algorithm reachable through `TJwtCrypt` and `ICryptPublicKey` / `ICryptPrivateKey`.
- Generating an ECC P-256 key pair and certificate via `TEccCertificateSecret`, persisting it with `SaveToSecureFile`, loading it back with `LoadFromSecureFile`, and managing trust with `TEccCertificateChain`.
- Encrypting a payload at rest with `TEccCertificate.Encrypt` (the framework's ECIES envelope: ephemeral ECDH P-256 + AES-256 + HMAC tag) and decrypting with `TEccCertificateSecret.Decrypt`.
- Setting up an authenticated channel with `TEcdheProtocolClient` / `TEcdheProtocolServer`, which run an ECDHE handshake and frame the rest of the conversation with AES + HMAC.
- Symmetric authenticated encryption with `TAesGcm` (or the `TAesFast[mGcm]` lookup, which picks the fastest available implementation): set the IV, optionally feed AAD, encrypt, then read the auth tag with `AesGcmFinal`.
- Hashing, HMAC and PBKDF2 with `TSynSigner` over `TSignAlgo` (SHA-1, SHA-2 family, SHA-3 / SHAKE), and stand-alone helpers like `Sha256Hex` and `Pbkdf2HmacSha256`.
- Storing a password as a Modular Crypt Format string with `TSynSigner.Pbkdf2ModularCrypt` (PBKDF2 variants) or, after pulling in `mormot.crypt.other`, `mcfBCryptSha256` and `mcfSCrypt`. Verify with `ModularCryptVerify`.
- Deriving a session token, signing a manifest, or computing a release signature with `TSynSigner.Full` / `TSynSigner.Pbkdf2`.
- Switching the same APIs to OpenSSL primitives by registering `mormot.crypt.openssl` and gating with `OpenSslIsAvailable`.

## When NOT to use

- Wiring up a `TRestServer` authentication scheme, creating sessions, or returning tokens from `OnAuthenticate`. Use **mormot2-rest-soa**. This skill produces the JWT; that one decides who sees it.
- Issuing, renewing, or serving a TLS certificate, terminating HTTPS, or wiring `OnNetTlsAcceptServerName`. Use **mormot2-net**.
- `RawUtf8`, `TDocVariant`, RTTI, and JSON conventions used in the examples below. Use **mormot2-core**.
- Long-term certificate stores backed by X.509 / OpenSSL `TCryptStoreOpenSsl` for chain validation and CRL handling: those live here, but if your task is "make the HTTPS handshake trust this CA", route to **mormot2-net**.

## Core idioms

### 1. Issue and verify a JWT signed with ECC P-256

`TJwtEs256` (in `mormot.crypt.jwt`) signs with ECDSA over secp256r1. The same instance can issue and verify provided its `TEccCertificate` carries the private key (i.e. is actually a `TEccCertificateSecret`). Verify-only services pass a public-key-only `TEccCertificate`.

```pascal
uses
  mormot.crypt.ecc,
  mormot.crypt.jwt;

var
  Cert: TEccCertificateSecret;
  Jwt: TJwtEs256;
  Token: RawUtf8;
  Content: TJwtContent;
begin
  Cert := TEccCertificateSecret.CreateNew(nil, 'auth@example.com');
  Jwt := TJwtEs256.Create(
    Cert,
    [jrcIssuer, jrcSubject, jrcExpirationTime, jrcJwtID],
    ['api.example.com'],          // accepted audiences
    60);                           // expiration minutes
  try
    Token := Jwt.Compute([], 'auth.example.com', 'user-42', 'api.example.com');
    Jwt.Verify(Token, Content);
    Assert(Content.result = jwtValid);
  finally
    Jwt.Free;
    Cert.Free;
  end;
end;
```

For HMAC-secured tokens, swap in `TJwtHS256` and pass a high-entropy secret (>= 32 bytes). For an algorithm-agnostic flow that works with any registered asymmetric algorithm (ES256, RS256, EdDSA when OpenSSL is loaded), use `TJwtCrypt` with a `TCryptAsymAlgo`.

### 2. Generate, store and load an ECC P-256 keypair

`TEccCertificateSecret.CreateNew` produces a fresh secp256r1 keypair plus a self-signed certificate. Persist it with `SaveToSecureFile`, which AES-encrypts the private key under a PBKDF2-derived KEK, and load it with the matching `LoadFromSecureFile`.

```pascal
uses
  mormot.crypt.ecc;

var
  Sec: TEccCertificateSecret;
begin
  Sec := TEccCertificateSecret.CreateNew(nil, 'svc@example.com');
  try
    Sec.SaveToSecureFile('passphrase', '/var/lib/myapp/keys/');
    // file: /var/lib/myapp/keys/<serial>.private  (PBKDF2 + AES-CFB envelope)
  finally
    Sec.Free;
  end;

  Sec := TEccCertificateSecret.CreateFromSecureFile(
    '/var/lib/myapp/keys/', '<serial>', 'passphrase');
  try
    // Sec.HasSecret = True; Sec.Sign(...) and Sec.Decrypt(...) now work.
  finally
    Sec.Free;
  end;
end;
```

For verify-only deployments, ship `TEccCertificate` (no `Secret`) loaded via `FromBase64` or `LoadFromStream`. Group multiple trusted certs in a `TEccCertificateChain` and call `IsValid` to traverse the trust path.

### 3. AES-GCM with explicit nonce control

`TAesGcm` lives in `mormot.crypt.core`. The IV must be 12 bytes (GCM standard); only the first 12 bytes of whatever you pass are used. Never reuse an `(IV, key)` pair: GCM catastrophically loses confidentiality and authenticity when nonces repeat.

```pascal
uses
  mormot.crypt.core;

var
  Aes: TAesGcm;
  Key: THash256;
  IV: THash128;
  Plain, Cipher: RawByteString;
  Tag: TAesBlock;
begin
  RandomBytes(@Key, SizeOf(Key));
  RandomBytes(@IV,  SizeOf(IV));   // 12 of these 16 bytes will be used
  Aes := TAesGcm.Create(Key, 256);
  try
    Aes.IV := IV;
    Aes.AesGcmAad(@Header[1], length(Header));  // optional AAD
    Cipher := Aes.EncryptPkcs7(Plain, {ivAtBeginning=}false);
    if not Aes.AesGcmFinal(Tag, 16) then
      raise ESynCrypto.Create('GCM finalization failed');
  finally
    Aes.Free;
  end;
end;
```

For a faster runtime-selected backend (mORMot's hand-tuned x86_64 asm versus OpenSSL EVP), use `TAesFast[mGcm]` instead of `TAesGcm` directly.

### 4. PBKDF2 password hash in Modular Crypt Format

`TSynSigner.Pbkdf2ModularCrypt` produces a self-describing string (`$pbkdf2-sha256$<rounds>$<salt>$<hash>$`). The number of rounds comes from the `MCF_ROUNDS` global, which the framework keeps aligned with OWASP Password Storage guidance (2025: PBKDF2-SHA-256 = 600,000 rounds). `ModularCryptVerify` parses any supported format and verifies in constant time.

```pascal
uses
  mormot.crypt.secure;

var
  Sig: TSynSigner;
  Stored: RawUtf8;
begin
  Stored := Sig.Pbkdf2ModularCrypt(mcfPbkdf2Sha256, 'user-password');
  // store Stored in DB; later:
  if not ModularCryptVerify('user-password', Stored) then
    raise ESecurity.Create('bad password');
end;
```

For stronger memory-hard hashes, register `mormot.crypt.other` and pick `mcfBCryptSha256` (recommended for general use) or `mcfSCrypt`. The framework treats Argon2 as less proven for production timing and does not ship a default; if you must use it, do it through OpenSSL directly. A bare `Sha256Hex(Password)` is **not** a password hash and must not be used for storage.

### 5. HMAC, PBKDF2 and code signing with TSynSigner

`TSynSigner` is the unified HMAC / SHA / SHA-3 frontend. Same struct, switch the algorithm enum (`TSignAlgo`). Use it for cookie tampering protection, file manifest signing, and as the KDF for application-derived keys.

```pascal
uses
  mormot.crypt.secure;

var
  Sig: TSynSigner;
  Mac: RawUtf8;
  Key: THash512Rec;
begin
  // Authenticate a manifest with HMAC-SHA-256.
  Mac := Sig.Full(saSha256, 'shared-secret', ManifestBytes);

  // Derive a 32-byte session key from a passphrase + per-session salt.
  Sig.Pbkdf2(saSha256, 'passphrase', SessionSalt, 100000, Key);
end;
```

`TSynLog` calls `TSynSigner` internally for its rotated archive signing, which is also how the framework signs its own log bundles when `EchoCustom` chains a signer.

## Common pitfalls

- **Reusing an AES-GCM nonce.** `(IV, key)` pairs are the entire safety story. Repeat once and an attacker recovers the authentication subkey, forges arbitrary ciphertexts, and learns the XOR of the two plaintexts. Use a 96-bit random nonce per message **only** if you can guarantee the message rate stays well below the birthday bound (~2^32), or use a 96-bit counter you persist across restarts. Never derive nonces from the plaintext.
- **Treating SHA-256 of a password as a password hash.** `Sha256Hex(Password)` is fast on purpose. An attacker with one GPU runs through every ten-character ASCII password in hours. Always go through `mcfPbkdf2Sha256` (PBKDF2 with `MCF_ROUNDS[mcfPbkdf2Sha256]`) at minimum, and prefer `mcfBCryptSha256` or `mcfSCrypt` from `mormot.crypt.other`. The same applies to MD5, SHA-1, SHA-512, and any unsalted construction.
- **Mixing PEM, raw and "secure binary" key formats.** mORMot 2 ships three serialisations: `SaveToBinary` (raw `TEccCertificateContent`, public-key-only by default), `SaveToSecureBinary` / `SaveToSecureFile` (PBKDF2 + AES envelope, private key included), and PEM via `EccToDer` + `DerToPem`. Pick one per file format and document it. Loading a `SaveToBinary` blob through `LoadFromSecureBinary` returns `false` silently and leaves you with an unusable certificate.
- **Wide JWT clock skew tolerance.** `TJwtAbstract.VerifyTimeToleranceSeconds` defaults to 30 seconds, which forgives clock drift between the issuer and the verifier. Setting it to "a few minutes" because NTP is flaky widens the replay window for a stolen token by exactly that much. Fix the clock (NTP / chrony), do not raise the tolerance, and never set it above 60 seconds in production.
- **Picking weak HMAC secrets for `TJwtHS256`.** A 16-byte random secret is the floor; many "borrowed" secrets are 8 ASCII characters. The HMAC key must be at least as long as the digest output (32 bytes for HS256, 64 for HS512) and come from `RandomBytes`, not a config-file paste. If the secret lives in a `.env` you also commit, treat it as already leaked.
- **Logging tokens, passwords or private keys at INFO.** `TSynLog` will happily echo a `RawUtf8` into a rotating archive that ends up in your aggregator. Mask JWT bearer tokens before logging, never log a `TEccCertificateSecret` (`SaveToBinary({publickeyonly=}false)` is the dangerous path), and route any code that builds a password hash through the `sllSensitive` family with a redactor.
- **Calling `TJwtEs256.Verify` with a private-key certificate on every node.** Verifiers only need the public key. Shipping `TEccCertificateSecret` (i.e. the `.private` file) to every API node multiplies your blast radius by the number of nodes. Export with `SaveToBinary({publickeyonly=}true)` and ship that to verifiers; keep `SaveToSecureFile` only on the issuer.
- **Forgetting to register `mormot.crypt.openssl` when you expected RS256 or EdDSA.** `TJwtCrypt.Supports(caaRS256)` returns `false` until `mormot.crypt.openssl` is in the unit list **and** `OpenSslIsAvailable` returns `true`. The framework's built-in providers cover ES256 and the HMAC family; everything else needs OpenSSL. Add the unit, gate on `OpenSslIsAvailable`, and fall back to ES256 if OpenSSL is missing.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-21.md` - Security
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-23.md` - ECC Encryption
- `references/sessions-jwt.md`
- `references/ecc-aes-gcm.md`
- `references/signing.md`
- `mormot2-rest-soa` for the `TRestServer` authentication scheme that consumes these primitives
- `mormot2-net` for TLS, SNI, and ACME certificate lifecycle
- `mormot2-core` for `RawUtf8`, `TDocVariant`, and RTTI conventions used throughout the snippets above
