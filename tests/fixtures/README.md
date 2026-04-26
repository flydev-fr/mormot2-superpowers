# mormot2-superpowers fixtures

Self-test fixtures exercised by CI. Each fixture is a real Pascal project laid out exactly as a downstream user's project would look.

## Fixtures

| Fixture | Compilers | mORMot 2 | TSynTestCase | Purpose |
|---|---|---|---|---|
| `greenfield-delphi/` | Delphi only | yes | yes | Delphi-only build + test path |
| `greenfield-fpc/` | FPC only | yes | yes | FPC-only build + test path; macOS portability |
| `greenfield-dual/` | Delphi + FPC | yes | yes | Single source compiles on both compilers |
| `brownfield-no-tests/` | Either | no | no | Pascal project without mORMot 2; tests the brownfield detection branch of the session-start hook |

## How they're used

Each fixture has its own README with the exact CI invocation. The CI workflow (`.github/workflows/ci.yml`) runs the full matrix across hosted and self-hosted runners.

Fixtures are also runnable locally:

```bash
export MORMOT2_PATH=/path/to/mORMot2
cd tests/fixtures/greenfield-fpc
bash ../../../scripts/fpc-build.sh --project src/smoke.lpr
bash ../../../scripts/fpc-build.sh --project tests/smoke.test.lpr
./tests/smoketest
```

## Adding a fixture

1. Create `tests/fixtures/<name>/` with the project shape.
2. Add a `README.md` listing build commands and what the fixture validates.
3. Wire a job in `.github/workflows/ci.yml`.
4. Update the table above.
