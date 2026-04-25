```yaml
positive:
  - prompt: "Expose a service that returns user profiles via REST"
    expected: mormot2-rest-soa
    forbidden: [mormot2-net, mormot2-auth-security]
  - prompt: "Define an IInvokable for an order-processing service"
    expected: mormot2-rest-soa
  - prompt: "Wire TRestServerDB to expose a TOrm model over HTTP"
    expected: mormot2-rest-soa

negative:
  - prompt: "Switch the HTTP server to async mode with WebSocket upgrade"
    must_not_trigger: mormot2-rest-soa
    expected: mormot2-net
  - prompt: "Generate a JWT signed with ECC for our auth flow"
    must_not_trigger: mormot2-rest-soa
    expected: mormot2-auth-security
```
