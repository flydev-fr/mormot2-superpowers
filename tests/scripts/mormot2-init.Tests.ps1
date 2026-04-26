BeforeAll {
    $PluginRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Script    = Join-Path $PluginRoot 'scripts/mormot2-init.ps1'
    $StandalonePwsh = 'C:/Program Files/PowerShell/7/pwsh.exe'
    $script:Pwsh = if (Test-Path $StandalonePwsh) { $StandalonePwsh } else { (Get-Command pwsh).Source }
}

Describe 'mormot2-init.ps1' {
    BeforeEach {
        $script:Work = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mi-$(Get-Random)") -Force
        Push-Location $script:Work
    }
    AfterEach {
        Pop-Location
        Remove-Item -Recurse -Force $script:Work.FullName
    }

    It 'exits 1 when -Scaffold is passed' {
        & $script:Pwsh -File $Script -Scaffold *> $null
        $LASTEXITCODE | Should -Be 1
    }

    It 'creates config with -MormotPath' {
        $mm = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mm-$(Get-Random)") -Force).FullName
        & $script:Pwsh -File $Script -MormotPath $mm *> $null
        $LASTEXITCODE | Should -Be 0
        Test-Path '.claude/mormot2.config.json' | Should -Be $true
        (Get-Content '.claude/mormot2.config.json' -Raw) | Should -Match 'mormot2_path'
        Remove-Item -Recurse -Force $mm
    }

    It 'exits 2 when -MormotPath points nowhere' {
        & $script:Pwsh -File $Script -MormotPath 'X:/no/such/path' *> $null
        $LASTEXITCODE | Should -Be 2
    }

    It 'exits 3 when config exists and -Force is absent' {
        New-Item -ItemType Directory -Path '.claude' -Force | Out-Null
        Set-Content -Path '.claude/mormot2.config.json' -Value '{"mormot2_path":"/old"}' -NoNewline
        $mm = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mm-$(Get-Random)") -Force).FullName
        & $script:Pwsh -File $Script -MormotPath $mm *> $null
        $LASTEXITCODE | Should -Be 3
        Remove-Item -Recurse -Force $mm
    }

    It 'overwrites with -Force' {
        New-Item -ItemType Directory -Path '.claude' -Force | Out-Null
        Set-Content -Path '.claude/mormot2.config.json' -Value '{"mormot2_path":"/old"}' -NoNewline
        $mm = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mm-$(Get-Random)") -Force).FullName
        & $script:Pwsh -File $Script -MormotPath $mm -Force *> $null
        $LASTEXITCODE | Should -Be 0
        $cfg = Get-Content '.claude/mormot2.config.json' -Raw
        $cfg | Should -Not -Match '/old'
        Remove-Item -Recurse -Force $mm
    }
}
