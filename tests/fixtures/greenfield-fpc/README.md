# greenfield-fpc fixture

Minimal FPC/Lazarus project that exercises:
- `scripts/fpc-build.sh` against `.lpr` (direct fpc) and `.lpi` (lazbuild) paths.
- `mormot.core.base` import on FPC (forces `-Fu`/`-Fi` injection).
- A `TSynTestCase` smoke test runnable via `/mormot2-test`.

## How CI uses this

The `build-fpc` job (ubuntu-latest with FPC 3.2) runs:

```bash
export MORMOT2_PATH="$HOME/mORMot2"
bash scripts/fpc-build.sh --project tests/fixtures/greenfield-fpc/src/smoke.lpr
bash scripts/fpc-build.sh --project tests/fixtures/greenfield-fpc/tests/smoke.test.lpr
./tests/fixtures/greenfield-fpc/tests/smoketest
```

The `build-fpc-mac` job (macos-latest) runs the same commands; it confirms macOS portability of fpc-build.sh.

The fixture is green when both BUILD_RESULT lines show `exit=0 errors=0` and `smoketest` exits 0.
