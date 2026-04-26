# greenfield-delphi fixture

Minimal Delphi-only project that exercises:
- `scripts/delphi-build.ps1` against a `.dpr` (no `.dproj`).
- `mormot.core.base` import (forces search-path injection).
- A `TSynTestCase` smoke test runnable via `/mormot2-test`.

## How CI uses this

The `build-delphi` job (self-hosted Windows + Delphi 12 CE) runs:

```powershell
$env:MORMOT2_PATH = "C:/path/to/mORMot2"
pwsh -File scripts/delphi-build.ps1 -Project tests/fixtures/greenfield-delphi/src/smoke.dpr
pwsh -File scripts/delphi-build.ps1 -Project tests/fixtures/greenfield-delphi/tests/smoke.test.dpr
& tests/fixtures/greenfield-delphi/tests/smoketest.exe
```

The fixture is considered green when both BUILD_RESULT lines report `exit=0 errors=0` and `smoketest.exe` exits 0.
