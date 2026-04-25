# Pester 5 boundary tests for scripts/delphi-build.ps1
#
# Real-compile cases require Delphi installed and live in fixture-based CI
# (Plan 4, Task 7). These tests cover only boundary behaviour: missing env,
# missing project, missing compiler, and BUILD_RESULT emission on every code
# path.
#
# Implementation notes:
#   - We invoke the script through a child pwsh via the call operator (`&`)
#     so `exit N` in the child propagates to $LASTEXITCODE here.
#   - The boilerplate is intentionally inlined in each `It` block rather than
#     hoisted into a `BeforeAll` helper function. Under Pester 5.7.1 on this
#     Windows runner, native-exe invocation from a function defined in
#     `BeforeAll` triggers a dotnet-tool-shim crash (-532462766) for pwsh.exe.
#     Inlining sidesteps the issue and keeps the tests deterministic on
#     machines where dcc64.exe is on PATH (the test runner has Delphi 11+
#     installed).

BeforeAll {
    $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Script     = Join-Path $script:PluginRoot 'scripts\delphi-build.ps1'

    # Prefer the standalone PowerShell 7 install over a `dotnet tool` shim.
    # The shim re-launches via `dotnet`, so it cannot start when we strip
    # PATH for the "no Delphi compiler on PATH" boundary test.
    $candidatePwsh = @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files\PowerShell\7-preview\pwsh.exe'
    )
    $script:Pwsh = $candidatePwsh | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $script:Pwsh) { $script:Pwsh = (Get-Command pwsh).Source }
}

Describe 'delphi-build.ps1 - boundary behaviour' {

    It 'exits 2 when MORMOT2_PATH is unset' {
        $tmp = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("mp-" + [System.IO.Path]::GetRandomFileName())) -Force).FullName
        $dpr = Join-Path $tmp 'fake.dpr'
        New-Item -ItemType File -Path $dpr -Force | Out-Null
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $prevMormot = $env:MORMOT2_PATH
        try {
            Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue
            $stdout = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Project $dpr 2>$tmpErr
            $exit   = $LASTEXITCODE
            $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            $output = (($stdout -join "`n") + "`n" + $stderr)

            $exit   | Should -Be 2
            $output | Should -Match 'MORMOT2_PATH'
            $output | Should -Match 'BUILD_RESULT exit=2'
        } finally {
            if ($null -eq $prevMormot) { Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue }
            else { $env:MORMOT2_PATH = $prevMormot }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exits 2 when MORMOT2_PATH does not exist' {
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $prevMormot = $env:MORMOT2_PATH
        try {
            $env:MORMOT2_PATH = 'X:/no/such/path'
            $stdout = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Project 'fake.dpr' 2>$tmpErr
            $exit   = $LASTEXITCODE
            $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            $output = (($stdout -join "`n") + "`n" + $stderr)

            $exit   | Should -Be 2
            $output | Should -Match 'BUILD_RESULT exit=2'
        } finally {
            if ($null -eq $prevMormot) { Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue }
            else { $env:MORMOT2_PATH = $prevMormot }
            Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exits 5 when project file does not exist' {
        $tmp = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("mp-" + [System.IO.Path]::GetRandomFileName())) -Force).FullName
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $prevMormot = $env:MORMOT2_PATH
        try {
            $env:MORMOT2_PATH = $tmp
            $stdout = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Project 'no-such-project.dpr' 2>$tmpErr
            $exit   = $LASTEXITCODE
            $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            $output = (($stdout -join "`n") + "`n" + $stderr)

            $exit   | Should -Be 5
            $output | Should -Match 'BUILD_RESULT exit=5'
        } finally {
            if ($null -eq $prevMormot) { Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue }
            else { $env:MORMOT2_PATH = $prevMormot }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exits 6 when no Delphi compiler is on PATH' {
        # Override $env:PATH for the duration of this test so dcc64.exe is
        # not resolvable, even on machines that have Delphi installed.
        # We point PATH at a temp directory that has no executables in it.
        $tmp = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("mp-" + [System.IO.Path]::GetRandomFileName())) -Force).FullName
        $dpr = Join-Path $tmp 'fake.dpr'
        New-Item -ItemType File -Path $dpr -Force | Out-Null
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $prevMormot = $env:MORMOT2_PATH
        $prevPath   = $env:PATH
        try {
            $env:MORMOT2_PATH = $tmp
            $env:PATH         = $tmp
            $stdout = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Project $dpr 2>$tmpErr
            $exit   = $LASTEXITCODE
            $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            $output = (($stdout -join "`n") + "`n" + $stderr)

            $exit   | Should -Be 6
            $output | Should -Match 'BUILD_RESULT exit=6'
        } finally {
            if ($null -eq $prevMormot) { Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue }
            else { $env:MORMOT2_PATH = $prevMormot }
            $env:PATH = $prevPath
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits a BUILD_RESULT line on every code path' {
        # Same setup as the no-PATH test but only asserts the structured
        # BUILD_RESULT line is present (regardless of exit code).
        $tmp = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("mp-" + [System.IO.Path]::GetRandomFileName())) -Force).FullName
        $dpr = Join-Path $tmp 'fake.dpr'
        New-Item -ItemType File -Path $dpr -Force | Out-Null
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $prevMormot = $env:MORMOT2_PATH
        $prevPath   = $env:PATH
        try {
            $env:MORMOT2_PATH = $tmp
            $env:PATH         = $tmp
            $stdout = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Project $dpr 2>$tmpErr
            $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            $output = (($stdout -join "`n") + "`n" + $stderr)

            $output | Should -Match 'BUILD_RESULT exit='
        } finally {
            if ($null -eq $prevMormot) { Remove-Item Env:\MORMOT2_PATH -ErrorAction SilentlyContinue }
            else { $env:MORMOT2_PATH = $prevMormot }
            $env:PATH = $prevPath
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
        }
    }
}
