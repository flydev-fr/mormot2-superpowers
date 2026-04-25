```yaml
positive:
  - prompt: "Add a search path for mORMot 2 sources to the dproj"
    expected: delphi-build
  - prompt: "Compile with dcc64 from the command line, in release config"
    expected: delphi-build
  - prompt: "Define DEBUG and FPC_X64MM at build time via MSBuild"
    expected: delphi-build
  - prompt: "Run scripts/delphi-build.ps1 against our project file"
    expected: delphi-build

negative:
  - prompt: "Build the project with lazbuild instead"
    must_not_trigger: delphi-build
    expected: fpc-build
  - prompt: "Bundle the binary with SQLite static and ship a Windows service"
    must_not_trigger: delphi-build
    expected: mormot2-deploy
```
