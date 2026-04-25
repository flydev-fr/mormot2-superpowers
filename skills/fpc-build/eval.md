```yaml
positive:
  - prompt: "Build the project with lazbuild against the .lpi"
    expected: fpc-build
  - prompt: "Cross-compile for aarch64 Linux from Windows"
    expected: fpc-build
  - prompt: "Add -Fu and -Fi for mORMot 2 sources in our fpc invocation"
    expected: fpc-build
  - prompt: "Run scripts/fpc-build.sh against the .dpr"
    expected: fpc-build

negative:
  - prompt: "Add a search path for mORMot 2 sources to the dproj"
    must_not_trigger: fpc-build
    expected: delphi-build
  - prompt: "Bundle the binary with SQLite static and ship a Windows service"
    must_not_trigger: fpc-build
    expected: mormot2-deploy
```
