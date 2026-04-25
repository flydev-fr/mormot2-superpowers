```yaml
positive:
  - prompt: "Switch our HTTP server to async with 200 worker threads"
    expected: mormot2-net
  - prompt: "Add WebSocket upgrade handler that broadcasts to all clients"
    expected: mormot2-net
  - prompt: "Expose Swagger/OpenAPI from our interface services"
    expected: mormot2-net
  - prompt: "Set up Let's Encrypt ACME for our HTTPS endpoint"
    expected: mormot2-net

negative:
  - prompt: "Define an IInvokable for the inventory service"
    must_not_trigger: mormot2-net
    expected: mormot2-rest-soa
  - prompt: "Generate an ECC-signed JWT for session tokens"
    must_not_trigger: mormot2-net
    expected: mormot2-auth-security
```
