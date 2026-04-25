# ECC P-256 and AES-GCM

This reference covers asymmetric ECC (secp256r1 / NIST P-256) and AES-GCM together because the two pair naturally: ECC manages the keys, AES-GCM moves the bulk data. The framework lays them out across `mormot.crypt.ecc` (certificates, ECIES, ECDHE) and `mormot.crypt.core` (block cipher, GCM, key schedules).

## ECC P-256 keypair lifecycle

`TEccCertificate` and `TEccCertificateSecret` are the public-only and private+public flavours of one ECC certificate. The framework's certificate format is **not** X.509; it is a compact mORMot-specific structure (`TEccCertificateContent`) that carries the public key, issuer, validity dates, signature, and a 16-byte serial. Use it when both ends speak mORMot. Use the X.509 path (`mormot.crypt.x509`, `TCryptCertX509`, OpenSSL) when you need to interop.

```pascal
uses
  mormot.crypt.ecc;

var
  Sec: TEccCertificateSecret;
  Pub: TEccCertificate;
  Sig: TEccSignature;
begin
  Sec := TEccCertificateSecret.CreateNew(nil, 'svc@example.com');
  try
    // Sign a message with the private key.
    Sec.Sign(@Message[1], length(Message), Sig);

    // Export public key only for verifiers.
    Pub := TEccCertificate.Create;
    Pub.LoadFromBinary(Sec.SaveToBinary({publickeyonly=}true));
    try
      Assert(Pub.Verify(@Message[1], length(Message), Sig));
    finally
      Pub.Free;
    end;
  finally
    Sec.Free;
  end;
end;
```

### Persistence formats

| Method                    | What is in the file                                            | Use when                                |
|---------------------------|----------------------------------------------------------------|-----------------------------------------|
| `SaveToBinary(true)`      | Public key + cert metadata, raw                                | Shipping a verifier                     |
| `SaveToBinary(false)`     | Public + private + metadata, **unencrypted**                   | Almost never; only inside a vault       |
| `SaveToSecureBinary`      | Same as above, AES-encrypted under PBKDF2(passphrase)          | Embedding the keypair in another blob   |
| `SaveToSecureFile`        | Same, written to `<folder>/<serial>.private`                   | Standard at-rest storage                |
| `EccToDer` + `DerToPem`   | Standard DER / PEM of the bare key (SEC1, SPKI, PKCS#8)        | Interop with non-mORMot tools           |
| `JwkToEcc` (decode only)  | JWK -> internal `TEccPublicKey`                                | Consuming a JWKS endpoint               |

`SaveToSecureFile` runs PBKDF2-HMAC-SHA-256 with a default of 60,000 rounds (`Pbkdf2Round` parameter) over the passphrase, derives an AES-256 key, and encrypts in CFB mode with an integrity tag. Tune `Pbkdf2Round` upward (200,000+) for keys that protect very long-lived secrets.

## TEccCertificateChain

`TEccCertificateChain` is a thread-safe in-memory store of trusted `TEccCertificate` instances. Its `IsValid(cert)` method walks parent serials until it hits a self-signed root or a certificate already in the chain. Use it to express "these N CAs are trusted" without dragging in OpenSSL.

```pascal
var
  Chain: TEccCertificateChain;
begin
  Chain := TEccCertificateChain.Create;
  try
    Chain.LoadFromFile('/etc/myapp/trust.chain');  // JSON of base64 certs
    if Chain.IsValid(IncomingCert) <> ecvValidSelfSigned then
      raise ESecurity.Create('untrusted issuer');
  finally
    Chain.Free;
  end;
end;
```

Save the same chain with `SaveToFile`. The serialization is a JSON array of base64-encoded certs.

## ECIES: encryption-at-rest with TEccCertificate.Encrypt

The framework ships its own ECIES envelope (Elliptic Curve Integrated Encryption Scheme):

1. Generate an ephemeral ECC P-256 keypair.
2. Run ECDH between the ephemeral private key and the recipient's public key. The shared secret is hashed (SHA-256) into a 32-byte AES key plus a 32-byte HMAC key.
3. Encrypt the payload with AES-256-CFB.
4. HMAC-SHA-256 the ciphertext.
5. Output: ephemeral public key || ciphertext || HMAC tag.

`TEccCertificate.Encrypt` does all five steps. `TEccCertificateSecret.Decrypt` reverses them, fails closed on a tag mismatch, and raises `EEccException` when the ephemeral public key does not pair with the recipient certificate.

```pascal
var
  Pub: TEccCertificate;
  Sec: TEccCertificateSecret;
  Plain, Cipher: RawByteString;
begin
  Cipher := Pub.Encrypt(Plain, ecaPBKDF2_HMAC_SHA256_AES256CFB, '');
  // ... store, ship, archive ...
  Plain := Sec.Decrypt(Cipher);  // raises on tampering
end;
```

The `ecaXxx` algorithm enum picks the AES mode and HMAC. `ecaPBKDF2_HMAC_SHA256_AES256CFB` is the default and the right choice unless you have a specific reason to deviate. `EncryptFile` / `DecryptFile` stream the same envelope to disk for files larger than RAM.

## ECDHE handshake: TEcdheProtocol

For an authenticated channel rather than file encryption, use `TEcdheProtocolClient` and `TEcdheProtocolServer`. They run an ECDHE handshake inside three messages, derive AES + HMAC session keys, and present `IProtocol.Encrypt` / `Decrypt` to whatever transport sits on top (WebSocket, custom TCP, file pipe).

```pascal
var
  ClientCert, ServerCert: TEccCertificateSecret;
  Trust: TEccCertificateChain;
  Cli: TEcdheProtocolClient;
  Srv: TEcdheProtocolServer;
begin
  // Both sides agree on TEcdheAuth (mutual / server-only / none) and the cipher set.
  Cli := TEcdheProtocolClient.Create(authMutual, Trust, ClientCert, []);
  Srv := TEcdheProtocolServer.Create(authMutual, Trust, ServerCert, []);
  // Application drives ProcessHandshake on each side until both Authenticated.
end;
```

When both peers run mORMot, this is a smaller-attack-surface alternative to TLS: no X.509, no OCSP, no cipher suite negotiation. When you need browser interop, route to TLS via `mormot2-net`.

## AES-GCM: nonce strategy

`TAesGcm` (in `mormot.crypt.core`) implements AES-GCM. Pick a key size at construction: 128, 192, or 256. For runtime-fastest selection, use `TAesFast[mGcm]` instead of `TAesGcm` directly; it falls back through hardware AES-NI, mORMot's hand-tuned x86_64 asm, and OpenSSL EVP.

GCM needs a unique `(key, IV)` per message. The IV must be 12 bytes (`GCM_IV_SIZE`). Three nonce strategies, in order of preference:

1. **Counter, persisted across restarts.** Initialize at boot from a stable counter table. Increment for each message. The counter never repeats for the lifetime of the key. Use this for any high-throughput encryption (logs, metrics, message queues).
2. **Random 96-bit IV.** Safe up to ~2^32 messages per key (NIST SP 800-38D bound). After that, rotate the key. Good for key-wrapping and request/response patterns where the message count is bounded.
3. **Derived from a session ID + counter.** Use this when you have many parallel sessions sharing one master key: the session ID disambiguates, the counter prevents replay within the session.

```pascal
var
  Aes: TAesAbstract;
  Iv: array[0..11] of byte;  // 96 bits
begin
  Aes := TAesFast[mGcm].Create(MasterKey, 256);
  try
    PCardinal(@Iv[0])^ := SessionId;
    PInt64(@Iv[4])^   := MessageCounter; inc(MessageCounter);
    Aes.IV := PHash128(@Iv)^;
    Cipher := Aes.EncryptPkcs7(Plain, false);
    if not (Aes as TAesGcmAbstract).AesGcmFinal(Tag, 16) then
      raise ESynCrypto.Create('GCM tag write failed');
  finally
    Aes.Free;
  end;
end;
```

## AAD: associated authenticated data

GCM authenticates the ciphertext **and** any AAD you feed in. AAD is not encrypted; it is bound. Use it for headers that must travel in cleartext but must not be tamperable: routing keys, content-type, version numbers.

```pascal
Aes.IV := IV;
(Aes as TAesGcmAbstract).AesGcmAad(@Header[1], length(Header));
Cipher := Aes.EncryptPkcs7(Plain, false);
(Aes as TAesGcmAbstract).AesGcmFinal(Tag, 16);
```

The same `AesGcmAad` call must run on the decrypt side with the same bytes, before `AesGcmFinal(Tag)` checks. Mismatched AAD fails the tag verification.

## Combining ECC and AES-GCM

The "natural" envelope when ECIES is too coarse:
- Recipient publishes a public ECC key.
- Sender generates an ephemeral keypair, runs ECDH, derives a 256-bit AES key and a 96-bit base IV via HKDF (`TSynSigner.KdfSP800`).
- Sender encrypts the payload with AES-256-GCM, base IV plus per-message counter.
- Sender ships: ephemeral public key, ciphertext, GCM tag.

If you find yourself writing this pattern more than once, wrap it. The framework's `TEccCertificate.Encrypt` already does it for the single-message case; for streaming, write your own helper around `TEcdheProtocol` instead of recreating the math.
