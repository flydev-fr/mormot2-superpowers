```yaml
positive:
  - prompt: "Add a TOrm class for users with email and role fields"
    expected: mormot2-orm
    forbidden: [mormot2-rest-soa, mormot2-db]
  - prompt: "Generate a TOrmModel that maps three tables across two databases"
    expected: mormot2-orm
  - prompt: "Use a virtual table to expose an in-memory CSV file as a TOrm"
    expected: mormot2-orm
  - prompt: "Add a unique index on the user email column via TOrm attribute"
    expected: mormot2-orm

negative:
  - prompt: "Run a raw SELECT JOIN across three SQL tables without ORM"
    must_not_trigger: mormot2-orm
    expected: mormot2-db
  - prompt: "Expose the user table as a REST endpoint with auth"
    must_not_trigger: mormot2-orm
    expected: mormot2-rest-soa
```
