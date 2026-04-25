#!/usr/bin/env pwsh
# tests/run-quick.ps1 - run invariants and Pester tests in <60s.
$ErrorActionPreference = 'Stop'
$PluginRoot = Split-Path -Parent $PSScriptRoot
Set-Location $PluginRoot

Write-Host "==> invariants"
$bash = $null
$candidates = @(
    'C:/Program Files/Git/bin/bash.exe',
    'C:/Program Files (x86)/Git/bin/bash.exe',
    '/usr/bin/bash',
    '/bin/bash'
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $bash = $c; break }
}
if (-not $bash) {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { $bash = $cmd.Source }
}
if (-not $bash) {
    Write-Host "[skip] bash not found; install Git for Windows or run tests/run-quick.sh directly"
    exit 0
}
& $bash 'tests/invariants.sh'
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Pester (script unit tests)"
if (Get-Module -ListAvailable -Name Pester) {
    $r = Invoke-Pester -Path 'tests/scripts/*.Tests.ps1' -PassThru
    if ($r.FailedCount -gt 0) { exit 1 }
} else {
    Write-Host "[skip] Pester not installed; install via 'Install-Module Pester'"
}

Write-Host "ALL QUICK CHECKS PASS"
