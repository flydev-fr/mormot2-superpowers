```yaml
positive:
  - prompt: "Convert a UnicodeString form input to RawUtf8 before saving"
    expected: mormot2-core
  - prompt: "Set the FPC_X64MM define for our build"
    expected: mormot2-core
  - prompt: "Register custom RTTI for a TPriceRow record so it serializes via mORMot JSON"
    expected: mormot2-core
  - prompt: "Pick the right string type for storing a JWT token"
    expected: mormot2-core

negative:
  - prompt: "Define a TOrmUser class with email and password fields"
    must_not_trigger: mormot2-core
    expected: mormot2-orm
  - prompt: "Set up an HTTPS endpoint that returns user JSON"
    must_not_trigger: mormot2-core
    expected: mormot2-rest-soa
```
