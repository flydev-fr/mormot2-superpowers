```yaml
positive:
  - prompt: "Run a raw SELECT JOIN across three SQL tables without ORM"
    expected: mormot2-db
  - prompt: "Configure a PostgreSQL connection pool with 8 connections"
    expected: mormot2-db
  - prompt: "Insert into a MongoDB collection via BSON"
    expected: mormot2-db
  - prompt: "Adapt a LIMIT clause for both Oracle and SQLite"
    expected: mormot2-db

negative:
  - prompt: "Define a TOrm class with email and password fields"
    must_not_trigger: mormot2-db
    expected: mormot2-orm
  - prompt: "Bundle the SQLite static library so deployment is single-binary"
    must_not_trigger: mormot2-db
    expected: mormot2-deploy
```
