# Sessions and Authentication

mORMot 2's REST layer ships several authentication schemes plug-compatible with the same `TRestServer`. This reference covers session creation, the schemes, and where the line lives between this skill and `mormot2-auth-security` (which owns JWT, ECC, and crypto primitives).

## Built-in schemes

| Class                                  | Scheme                                | Strength | Best for             |
|----------------------------------------|---------------------------------------|----------|----------------------|
| `TRestServerAuthenticationDefault`     | mORMot signed-URI challenge (HMAC)    | strong   | Delphi/FPC clients   |
| `TRestServerAuthenticationSignedUri`   | abstract base for signed-URI variants | -        | extending the above  |
| `TRestServerAuthenticationSspi`        | Windows SSPI / Kerberos               | strong   | Windows domain       |
| `TRestServerAuthenticationHttpBasic`   | RFC 7617 HTTP Basic                   | weak     | Browsers (over HTTPS only) |
| `TRestServerAuthenticationNone`        | username only, no challenge           | none     | Tests, dev only      |

JWT and key-pair primitives belong to `mormot2-auth-security`. This skill covers plugging an authentication object into a REST server and reading the resulting session.

## Registering authentication

```pascal
uses
  mormot.rest.server;

// Default mORMot challenge
Server.AuthenticationRegister(TRestServerAuthenticationDefault);

// HTTP Basic for browsers (do this only over HTTPS, see mormot2-net for TLS)
Server.AuthenticationRegister(TRestServerAuthenticationHttpBasic);
```

Multiple schemes can coexist; the client picks the one it understands.

## Session creation flow

1. Client sends `POST /root/auth?UserName=alice` (or `Authorization: Basic ...`).
2. The registered authentication object validates credentials against `TAuthUser` rows.
3. On success, the server creates a `TAuthSession`, returns the session ID and signing key.
4. The client signs subsequent URIs (Default scheme) or sets the `Authorization` header (Basic).
5. Each request reaches the URI handler with `Ctxt.Session`, `Ctxt.SessionID`, and `Ctxt.SessionUser` populated.

## Reading the session inside a method-based service

```pascal
procedure TAppServer.WhoAmI(Ctxt: TRestServerUriContext);
var
  User: TAuthUser;
begin
  if Ctxt.SessionUser = 0 then
  begin
    Ctxt.Error('not authenticated', HTTP_UNAUTHORIZED);
    exit;
  end;
  Ctxt.Returns(['SessionID', Ctxt.SessionID,
                'UserName',  Ctxt.SessionUserName]);
  // Full user record:
  User := Server.SessionGetUser(Ctxt.SessionID);
  // ... use and Free User ...
end;
```

`Ctxt.Session`, `Ctxt.SessionID`, `Ctxt.SessionUser`, and `Ctxt.SessionUserName` are populated only when an authentication scheme has accepted the request. Sign-out is `Client.SessionClose` (or server-side `Server.SessionDelete(SessionID)`).

## Customizing the signing parameters

```pascal
var
  Auth: TRestServerAuthenticationSignedUri;
begin
  Auth := Server.AuthenticationRegister(TRestServerAuthenticationDefault) as
    TRestServerAuthenticationSignedUri;
  Auth.Algorithm := suaSHA256;          // upgrade signing to SHA-256
  Auth.TimestampCoherencySeconds := 10; // tolerate 10s clock skew
end;
```

`NoTimestampCoherencyCheck := true` disables the replay window entirely - only useful for tests, never in production.

## Authentication hooks

Override `TRestServerAuthentication` to implement a custom scheme (LDAP lookup, bearer-token validation, etc.):

```pascal
type
  TRestServerAuthenticationCustom = class(TRestServerAuthentication)
  protected
    function Auth(Ctxt: TRestServerUriContext): boolean; override;
  end;

// Inside Auth: validate the request, then call Sender.SessionCreate(...)
Server.AuthenticationRegister(TRestServerAuthenticationCustom);
```

For JWT-bearer flows specifically, lean on `mormot2-auth-security` for the token machinery and bridge into a custom `TRestServerAuthentication` here.

## Where this skill stops

- JWT, ECC, AES, password hashing: `mormot2-auth-security`.
- TLS, per-route rate limiting, CORS preflight: `mormot2-net`.
- This skill: register an auth object, read the session, tune signing/coherency.
