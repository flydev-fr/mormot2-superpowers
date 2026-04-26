# greenfield-dual fixture

Both compilers must compile this fixture from the same `.pas` source. Validates that:
- `scripts/delphi-build.ps1` and `scripts/fpc-build.sh` produce identical (or compatible) outputs against the same source.
- `{$IFDEF FPC}` shims are minimal and visible.
- `compiler: auto` resolves correctly when both `.dproj`/`.dpr` and `.lpi`/`.lpr` are present.

## How CI uses this

The `build-delphi` (self-hosted) job runs the `.dpr` path; the `build-fpc` job (ubuntu) runs the `.lpr` path. Both must report `BUILD_RESULT exit=0 errors=0`.
