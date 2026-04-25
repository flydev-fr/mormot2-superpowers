# Pester 5 tests for scripts/sad-lookup.ps1
# Mirrors tests/scripts/sad-lookup.bats one-for-one.

BeforeAll {
    $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Script     = Join-Path $script:PluginRoot 'scripts\sad-lookup.ps1'
    $script:Pwsh       = (Get-Command pwsh).Source

    # Invoke the script in a child pwsh process so $LASTEXITCODE propagates
    # cleanly (mirrors how the script is called from /mormot2-doc etc.).
    function Invoke-SadLookup {
        param(
            [string]$DocPath,        # if $null, do not set MORMOT2_DOC_PATH
            [bool]$UnsetDocPath = $false,
            [string[]]$ScriptArgs
        )
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $argList = @('-NoProfile', '-NonInteractive', '-File', $script:Script) + $ScriptArgs
            if ($UnsetDocPath) {
                # Spawn a child process with MORMOT2_DOC_PATH explicitly removed.
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $script:Pwsh
                foreach ($a in $argList) { $psi.ArgumentList.Add($a) }
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                # Copy current env, then drop MORMOT2_DOC_PATH
                foreach ($k in [System.Environment]::GetEnvironmentVariables().Keys) {
                    if ($k -ne 'MORMOT2_DOC_PATH') {
                        $psi.Environment[$k] = [System.Environment]::GetEnvironmentVariable($k)
                    }
                }
                $proc = [System.Diagnostics.Process]::Start($psi)
                $stdout = $proc.StandardOutput.ReadToEnd()
                $stderr = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()
                return [pscustomobject]@{
                    ExitCode = $proc.ExitCode
                    StdOut   = $stdout
                    StdErr   = $stderr
                    Output   = $stdout + $stderr
                }
            } else {
                $prev = $env:MORMOT2_DOC_PATH
                try {
                    if ($null -ne $DocPath) {
                        $env:MORMOT2_DOC_PATH = $DocPath
                    }
                    $stdout = & $script:Pwsh @argList 2>$tmp
                    $exit = $LASTEXITCODE
                    $stderr = if (Test-Path $tmp) { Get-Content $tmp -Raw } else { '' }
                    if ($null -eq $stdout) { $stdoutText = '' }
                    else { $stdoutText = ($stdout -join "`n") }
                    return [pscustomobject]@{
                        ExitCode = $exit
                        StdOut   = $stdoutText
                        StdErr   = $stderr
                        Output   = $stdoutText + "`n" + $stderr
                    }
                } finally {
                    $env:MORMOT2_DOC_PATH = $prev
                }
            }
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'sad-lookup.ps1' {
    BeforeEach {
        $script:FakeDocs = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()))).FullName
        foreach ($n in @('01', '05', '10', '25')) {
            $path = Join-Path $script:FakeDocs "mORMot2-SAD-Chapter-$n.md"
            "# Chapter $n`nbody body body" | Set-Content -Path $path -Encoding ascii
        }
    }

    AfterEach {
        if (Test-Path $script:FakeDocs) {
            Remove-Item $script:FakeDocs -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exits 2 when MORMOT2_DOC_PATH is unset' {
        $r = Invoke-SadLookup -UnsetDocPath $true -ScriptArgs @('torm')
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'MORMOT2_DOC_PATH'
    }

    It 'exits 2 when MORMOT2_DOC_PATH does not exist' {
        $r = Invoke-SadLookup -DocPath '/no/such/path' -ScriptArgs @('torm')
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'not found'
    }

    It 'resolves topic to chapter number' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'Chapter 05'
    }

    It 'accepts a chapter number directly' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('10')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'Chapter 10'
    }

    It 'exits 3 when chapter file is missing' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('99')
        $r.ExitCode | Should -Be 3
        $r.Output   | Should -Match 'not found'
    }

    It 'exits 4 when topic is unknown' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('not-a-topic')
        $r.ExitCode | Should -Be 4
        $r.Output   | Should -Match 'unknown topic'
    }

    It 'default excerpt limit is 200 lines' {
        # Pad chapter 5 with 500 lines
        $chapter5 = Join-Path $script:FakeDocs 'mORMot2-SAD-Chapter-05.md'
        $lines = 1..500 | ForEach-Object { 'line' }
        Add-Content -Path $chapter5 -Value $lines -Encoding ascii
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm')
        $r.ExitCode | Should -Be 0
        $count = ($r.StdOut -split "`r?`n" | Where-Object { $_ -ne '' }).Count
        # 1 header + up to 200 body = 201 max
        $count | Should -BeLessOrEqual 201
    }

    It 'respects custom line limit' {
        $chapter5 = Join-Path $script:FakeDocs 'mORMot2-SAD-Chapter-05.md'
        $lines = 1..500 | ForEach-Object { 'line' }
        Add-Content -Path $chapter5 -Value $lines -Encoding ascii
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm', '5')
        $r.ExitCode | Should -Be 0
        $count = ($r.StdOut -split "`r?`n" | Where-Object { $_ -ne '' }).Count
        # 1 header + 5 body = 6 max
        $count | Should -BeLessOrEqual 6
    }

    It 'exits 1 on non-numeric limit' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm', 'abc')
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'line-limit must be a positive integer'
    }

    It 'exits 1 on zero limit' {
        $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm', '0')
        $r.ExitCode | Should -Be 1
    }

    It 'exits 2 with clear message when chapter-index file missing' {
        $index = Join-Path $script:PluginRoot 'references\chapter-index.json'
        $backup = "$index.bak"
        Move-Item -Path $index -Destination $backup -Force
        try {
            $r = Invoke-SadLookup -DocPath $script:FakeDocs -ScriptArgs @('torm')
        } finally {
            Move-Item -Path $backup -Destination $index -Force
        }
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'chapter-index lookup failed'
    }
}
