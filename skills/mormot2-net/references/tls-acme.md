# TLS and ACME

mORMot 2's `mormot.net.acme` is a complete ACMEv2 client built on the framework's own ECC and HTTP primitives. It speaks the Let's Encrypt and ZeroSSL directories, requires OpenSSL for the actual TLS work, and ships a ready-made HTTP-01 challenge listener. You do not need certbot or acme.sh; the cert lifecycle lives inside your binary.

## Components

- **`TAcmeLetsEncryptClient`** - one ACME account + one domain, with the JOSE handshake, order creation, challenge fulfillment, and certificate retrieval.
- **`TAcmeLetsEncrypt`** - holds a folder of `TAcmeLetsEncryptClient` (one per domain), runs the renewal loop in the background, and exposes the SNI callback your HTTPS server attaches to its TLS context.
- **`TAcmeLetsEncryptServer`** - same as above plus a small `THttpServer` on port 80 that answers HTTP-01 challenges and 301-redirects everything else to HTTPS.

For most deployments, use `TAcmeLetsEncryptServer`. It is the smallest moving piece that does the right thing.

## Folder layout

`TAcmeLetsEncrypt` reads and writes one folder, the `KeyStoreFolder`. Per domain it stores four files:

```text
keystore/
  example.com.json        # account + order metadata
  example.com.acme.pem    # account ECC private key
  example.com.crt.pem     # current certificate chain
  example.com.key.pem     # current cert private key (optionally password-protected)
```

The folder is the source of truth. Back it up; lose it and you start from a fresh ACME account on next renewal.

## Endpoints

| Provider           | Production directory                                             | Staging / debug directory                                                  |
|--------------------|------------------------------------------------------------------|----------------------------------------------------------------------------|
| Let's Encrypt      | `ACME_LETSENCRYPT_URL` (`https://acme-v02.api.letsencrypt.org/directory`) | `ACME_LETSENCRYPT_DEBUG_URL` (`https://acme-staging-v02.api.letsencrypt.org/directory`) |
| ZeroSSL            | `ACME_ZEROSSL_URL`                                               | `ACME_ZEROSSL_DEBUG_URL`                                                   |

Always start on the staging directory. Production rate-limits are real (Let's Encrypt: 50 certs per registered domain per week, 5 duplicate certs per week); a deploy loop hitting production while you debug your code will get you blocked. The staging certs are not browser-trusted; that is fine for end-to-end testing of issuance and renewal logic.

## Minimal wiring

```pascal
uses
  mormot.net.acme,
  mormot.net.async,
  mormot.core.log;

var
  Acme: TAcmeLetsEncryptServer;
  Https: THttpAsyncServer;
begin
  // 1. Construct the ACME server. It binds port 80 by default.
  Acme := TAcmeLetsEncryptServer.Create(
    TSynLog,
    '/var/lib/myapp/acme/',     // KeyStoreFolder
    ACME_LETSENCRYPT_URL,        // start with the DEBUG_URL while testing
    'x509-es256',                // ECC P-256; default and recommended
    '');                         // optional private-key password

  // 2. Read existing certs (if any) into memory.
  Acme.LoadFromKeyStoreFolder;

  // 3. Wire the SNI callback into the HTTPS server *before* it starts accepting.
  Https.SetTlsServerNameCallback(Acme.OnNetTlsAcceptServerName);

  // 4. Kick off the renewal loop in a background thread.
  Acme.CheckCertificatesBackground;
end;
```

`CheckCertificatesBackground` is a `TLoggedWorkThread`. It runs `CheckCertificates` immediately, then schedules itself twice a day. Each run iterates every domain, checks expiry against `RenewBeforeEndDays`, and renews if needed.

## Tuning

| Property                  | Default     | Tune when                                                                       |
|---------------------------|-------------|---------------------------------------------------------------------------------|
| `RenewBeforeEndDays`      | 30          | You operate behind aggressive caches and need a bigger margin                   |
| `RenewWaitForSeconds`     | 30          | DNS or HTTP challenge round-trip is slow on your network                        |
| `KeyAlgo` (constructor)   | `x509-es256`| Compliance requires RSA; prefer ECC unless forced otherwise                     |
| `OnChallenge`             | nil         | You answer challenges via DNS-01 or a non-built-in HTTP listener                |

Setting `RenewBeforeEndDays <= 0` disables the renewal loop entirely; useful when a build orchestrator owns renewal and you want the running server to do nothing on its own.

## SNI dispatch

When a TLS handshake arrives, the OpenSSL context calls `OnNetTlsAcceptServerName` with the SNI hostname. `TAcmeLetsEncrypt` looks up the matching `TAcmeLetsEncryptClient`, returns its `SSL_CTX`, and the handshake completes with the right cert. This is how a single port-443 listener can serve dozens of domains.

If a request arrives without SNI (rare but possible for non-browser clients), the server falls back to the first registered context. Keep your "default" domain first in the folder (or set up a fallback explicitly).

## HTTP-01 vs DNS-01

`TAcmeLetsEncryptServer` implements HTTP-01 only. That is fine for the common case but has two caveats:

1. You must own port 80 publicly. Behind a load balancer that terminates HTTP at L7, forward `/.well-known/acme-challenge/*` to your origin or terminate the challenge at the LB.
2. HTTP-01 cannot validate wildcard certificates. ACME requires DNS-01 for wildcards.

For wildcards or for environments where port 80 is impossible (corporate DMZ, internal-only services with public certs), wire your own DNS-01 flow through `TAcmeLetsEncrypt.OnChallenge`. The callback receives the challenge token and must place a TXT record at `_acme-challenge.<domain>`; the framework polls until ACME confirms.

## Renewal observability

The renewal loop writes to the `TSynLog` class you passed to the constructor. At minimum, log lines mention:

- `CheckCertificates` start and end per domain.
- `Renew` decisions (skip, renew, fail).
- ACME directory responses on error.

Pipe the log to your aggregator and alert on consecutive renewal failures. A single failure is normal (network blip); three in a row means the cert is going to expire and a human needs to look.

## Failure modes that bite

- **Port 80 blocked** by firewall or already used by an old web server: `CheckCertificates` raises and the cert never renews. The HTTPS server keeps serving the existing cert until expiry, then everything breaks at once.
- **Time skew** on the host: ACME nonces are time-bound. If `date` on the host is more than a few minutes off, every order fails. Run NTP.
- **Folder permissions** wrong after an OS package update or container rebuild: the renewal thread cannot write the new cert. Verify the process user owns `KeyStoreFolder` and it is mode 0700 / 0600 for files.
- **Production rate limit** hit during a deploy loop: account is blocked for 7 days. Always use staging until you have a clean run end to end.
