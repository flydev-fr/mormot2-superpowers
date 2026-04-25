```yaml
positive:
  - prompt: "Generate a JWT signed with ECC (secp256r1)"
    expected: mormot2-auth-security
  - prompt: "Encrypt a payload with AES-GCM and a derived key"
    expected: mormot2-auth-security
  - prompt: "Hash a user password with strong PBKDF2 parameters"
    expected: mormot2-auth-security
  - prompt: "Verify an ECC signature on an upgrade manifest"
    expected: mormot2-auth-security

negative:
  - prompt: "Add a TRestServer authentication scheme via SHA-256 password hash"
    must_not_trigger: mormot2-auth-security
    expected: mormot2-rest-soa
  - prompt: "Renew the Let's Encrypt cert before expiry"
    must_not_trigger: mormot2-auth-security
    expected: mormot2-net
```
