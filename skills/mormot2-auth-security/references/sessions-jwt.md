# JWTs and session tokens

This reference covers the JWT side of `mormot.crypt.jwt` and how it composes with whatever session model the rest of the application uses. The companion skill `mormot2-rest-soa` covers the `TRestServer` authentication scheme that holds the matching session table; here we stay below that line.

## Class hierarchy

```
TJwtAbstract                       (mormot.crypt.jwt)
  TJwtSynSignerAbstract            HMAC family backed by TSynSigner
    TJwtHS256, TJwtHS384, TJwtHS512
    TJwtSha3-* variants
  TJwtAsym                         asymmetric base
    TJwtEs256                      ECDSA P-256 via mormot.crypt.ecc
    TJwtRsa                        RSA family via mormot.crypt.rsa
  TJwtCrypt                        algorithm-agnostic, uses ICryptPublicKey / ICryptPrivateKey
```

Pick by deployment shape:
- **Single-tenant, single language**: `TJwtHS256` with a 32-byte random secret. Smallest moving piece.
- **Public verification, private issuance**: `TJwtEs256`. Public-key-only `TEccCertificate` ships to every verifier; the issuer keeps the `TEccCertificateSecret`.
- **Cross-language compatibility (Node, Python, Java consumers)**: `TJwtCrypt` with `caaES256` if you need standards-pure ES256 over OpenSSL. `caaRS256` and `caaPS256` work once `mormot.crypt.openssl` is registered.

The author of mORMot deliberately ships **one algorithm per JWT class**. Mixing algorithms on a single endpoint is the classic JWT confusion bug (RS256 token verified with HMAC against the public key as if it were a secret). Stick to one class per route.

## Construction parameters

`TJwtAbstract.Create` and its subclasses share a common shape:

| Parameter                    | Meaning                                                                                                  |
|------------------------------|----------------------------------------------------------------------------------------------------------|
| `aClaims: TJwtClaims`        | Which registered claims to require / generate. Typical: `[jrcIssuer, jrcSubject, jrcExpirationTime, jrcJwtID]`. |
| `aAudience: array of RawUtf8`| Allowed `aud` values. Pass `[]` to skip audience check.                                                  |
| `aExpirationMinutes`         | Default `exp` for `Compute`. 0 = no `exp` (avoid in production).                                         |
| `aIDIdentifier`              | If set, populates `jti` from a `TSynUniqueIdentifierGenerator` you can later reverse-engineer to a timestamp + process ID. |
| `aIDObfuscationKey`          | Optional XOR mask on the `jti` so the underlying identifier is not directly visible.                     |

`TJwtAbstract.VerifyTimeToleranceSeconds` defaults to **30** seconds. That is the grace window applied to both `nbf` and `exp`. Do not raise it casually; see "Common pitfalls" in the parent skill.

## Compute and Verify

```pascal
Token := Jwt.Compute(
  ['role', 'admin'],          // private claims, name/value pairs
  'auth.example.com',          // issuer
  'user-42',                   // subject
  'api.example.com');          // audience

Jwt.Verify(Token, Content);
case Content.result of
  jwtValid:                ; // OK
  jwtExpired:              ; // exp < now - tolerance
  jwtNotBeforeFailed:      ; // nbf > now + tolerance
  jwtUnknownAudience:      ; // aud not in the constructor list
  jwtInvalidSignature:     ; // signature does not match
end;
```

`Compute` is thread-safe. `Verify` is also thread-safe and uses `fCache` (a `TSynDictionary`) to skip re-running signature math on tokens it has already validated within `CacheTimeoutSeconds`. Set `CacheTimeoutSeconds := 0` to disable the cache for high-rotation tokens (refresh-flow JWTs, single-use tokens).

For HTTP endpoints, `VerifyAuthorizationHeader('Bearer ' + Token, Content)` skips the manual prefix strip.

## Claim conventions

Stick to RFC 7519 registered claims first; only fall back to private claims for things that genuinely do not fit:

| Claim | Purpose                                       | mORMot enum         |
|-------|-----------------------------------------------|---------------------|
| `iss` | Token issuer (your auth service)              | `jrcIssuer`         |
| `sub` | Subject (user ID; never the email)            | `jrcSubject`        |
| `aud` | Audience (the API consuming the token)        | `jrcAudience`       |
| `exp` | Expiration (Unix seconds, UTC)                | `jrcExpirationTime` |
| `nbf` | Not-before                                    | `jrcNotBefore`      |
| `iat` | Issued-at                                     | `jrcIssuedAt`       |
| `jti` | Unique token ID (for revocation, replay defense) | `jrcJwtID`       |

Private claims are pure JSON. Keep them short (3-4 chars: `rol`, `tnt`, `ver`); JWTs travel in `Authorization` headers and many proxies cap headers at 8 KB.

## Lifetimes

A common, defensible pair is:
- **Access token**: 5-15 minutes, signed JWT, sent on every API call.
- **Refresh token**: 7-30 days, opaque random string stored server-side, exchanged at `/auth/refresh` for a new access token.

Refresh tokens **should not** be JWTs. JWTs are bearer tokens that the issuer cannot revoke without help. Refresh tokens need the help: a server-side row keyed on a hash of the token, with `revoked_at`, `last_used_at`, `parent_token_id`. Theft detection: if a refresh token is presented after its rotation, revoke the entire family.

Sliding expiration on access tokens (re-issue with a fresh `exp` on every request) defeats the point of short-lived JWTs. Pair short JWTs with explicit refresh.

## Revocation

JWTs are stateless on purpose. The price is that a leaked token is valid until `exp`. Three options, in increasing operational complexity:

1. **Short `exp`, no revocation.** Simplest. Acceptable for low-stakes APIs.
2. **`jti` blacklist.** On logout / forced revocation, write the `jti` into a small table (or Redis) with a TTL equal to the token's remaining lifetime. Verifier checks the table. Cost: one O(1) lookup per request, plus N rows where N = currently-revoked tokens.
3. **Reference token.** JWT carries a session ID; verifier looks up the session in `TRestServer` (covered in `mormot2-rest-soa`). The token is effectively a signed pointer. Maximum control, requires the verifier to talk to the auth service.

Pick exactly one. Mixing 1 and 2 leaves operators wondering why a logout did not work.

## Signing key rotation

For HMAC, keep `current_secret` and `previous_secret`. Issuer signs with `current_secret`. Verifier tries `current_secret` first, then `previous_secret`. Rotate by promoting `current` to `previous` and writing a new `current`. Run two `TJwtHS256` instances in parallel during the overlap; the wrapper that picks one to verify is a few lines.

For ECC, the same pattern works with two `TJwtEs256` instances, each with its own `TEccCertificate`. The `kid` header field (set via the `aHeader` constructor argument on subclasses that expose it, or by post-Compute editing for fine control) tells the verifier which key to use.

## Server-side blacklist via session storage

If you already use `TRestServer` sessions, the cheapest revocation list is a `TOrm` like:

```pascal
type
  TOrmRevokedToken = class(TOrm)
  private
    fJti: RawUtf8;
    fExpiresUnix: TUnixTime;
  published
    property Jti: RawUtf8 read fJti write fJti;
    property ExpiresUnix: TUnixTime read fExpiresUnix write fExpiresUnix;
  end;
```

Index `Jti`. On `Verify`, after `jwtValid`, look up by `Jti`; if found, return `jwtUnknownID` (or your own `jrcData`-driven error) and reject. A small periodic job deletes rows where `ExpiresUnix < UnixTimeUtc`. The whole revocation system fits in one ORM table and one LRU.
