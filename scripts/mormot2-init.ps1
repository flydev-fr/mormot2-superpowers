<#
.SYNOPSIS
mormot2-init: scaffold .claude/mormot2.config.json for a Pascal project.

.DESCRIPTION
PowerShell sibling of scripts/mormot2-init.sh. Same exit codes (0/1/2/3).
#>
param(
    [string]$MormotPath,
    [string]$MormotDocPath,
    [string]$Compiler = 'auto',
    [switch]$Force,
    [switch]$Scaffold
)

$ErrorActionPreference = 'Continue'

if ($Scaffold) {
    [Console]::Error.WriteLine('mormot2-init: --scaffold is not yet implemented; Plan 4 ships project skeletons')
    exit 1
}

if ([string]::IsNullOrEmpty($MormotPath)) {
    [Console]::Error.WriteLine('mormot2-init: -MormotPath is required')
    exit 1
}

if (-not (Test-Path $MormotPath -PathType Container)) {
    [Console]::Error.WriteLine("mormot2-init: mormot2-path not found: $MormotPath")
    exit 2
}

$Cfg = Join-Path '.claude' 'mormot2.config.json'
if ((Test-Path $Cfg -PathType Leaf) -and -not $Force) {
    [Console]::Error.WriteLine("mormot2-init: $Cfg already exists (use -Force to overwrite)")
    exit 3
}

if ([string]::IsNullOrEmpty($MormotDocPath)) {
    $MormotDocPath = Join-Path $MormotPath 'docs'
}

New-Item -ItemType Directory -Path '.claude' -Force | Out-Null

$json = @"
{
  "mormot2_path": "$($MormotPath -replace '\\','/')",
  "mormot2_doc_path": "$($MormotDocPath -replace '\\','/')",
  "compiler": "$Compiler"
}
"@

Set-Content -Path $Cfg -Value $json -NoNewline

Write-Output "mormot2-init: wrote $Cfg"
exit 0
