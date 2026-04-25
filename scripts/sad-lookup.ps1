<#
.SYNOPSIS
sad-lookup: resolve a mORMot 2 SAD topic or chapter number to a chapter excerpt.

.DESCRIPTION
Reads MORMOT2_DOC_PATH for the docs tree and the plugin's
references/chapter-index.json for topic-to-chapter mapping.

Exit codes:
  0 success
  1 misuse (incl. invalid LIMIT)
  2 MORMOT2_DOC_PATH unset/invalid OR chapter-index file missing
  3 chapter file missing under MORMOT2_DOC_PATH
  4 unknown topic
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Query,

    # Take Limit as a string so we can validate it ourselves and emit the
    # exact error message + exit code (1) the bash version emits, rather than
    # letting PowerShell's parameter binder reject it with its own error.
    [Parameter(Position = 1)]
    [string]$Limit = '200'
)

$ErrorActionPreference = 'Stop'

# Validate Limit: must match ^[1-9][0-9]*$ (positive integer, no leading zero).
if ($Limit -notmatch '^[1-9][0-9]*$') {
    [Console]::Error.WriteLine("error: line-limit must be a positive integer, got '$Limit'")
    exit 1
}
$LimitInt = [int]$Limit

$DocPath = $env:MORMOT2_DOC_PATH
if ([string]::IsNullOrEmpty($DocPath)) {
    [Console]::Error.WriteLine('error: MORMOT2_DOC_PATH is not set; run /mormot2-init or set it manually')
    exit 2
}
if (-not (Test-Path -LiteralPath $DocPath -PathType Container)) {
    [Console]::Error.WriteLine("error: MORMOT2_DOC_PATH=$DocPath not found")
    exit 2
}

$PluginRoot = Split-Path -Parent $PSScriptRoot
$Index      = Join-Path $PluginRoot 'references/chapter-index.json'

if (-not (Test-Path -LiteralPath $Index -PathType Leaf)) {
    [Console]::Error.WriteLine("error: chapter-index lookup failed; $Index does not exist")
    exit 2
}

if ($Query -match '^\d+$') {
    $Chapter = '{0:D2}' -f [int]$Query
} else {
    try {
        $idx = Get-Content -LiteralPath $Index -Raw | ConvertFrom-Json
    } catch {
        [Console]::Error.WriteLine("error: chapter-index lookup failed; cannot parse $Index")
        exit 2
    }
    $key = $Query.ToLower()
    $val = $null
    if ($null -ne $idx.topics -and ($idx.topics.PSObject.Properties.Name -contains $key)) {
        $val = $idx.topics.$key
    }
    if ($null -eq $val) {
        [Console]::Error.WriteLine("error: unknown topic '$Query'")
        exit 4
    }
    $Chapter = '{0:D2}' -f [int]$val
}

$File = Join-Path $DocPath "mORMot2-SAD-Chapter-$Chapter.md"
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    [Console]::Error.WriteLine("error: chapter $Chapter file not found at $File")
    exit 3
}

# Header (ASCII hyphen, not em dash) + excerpt
"Chapter $Chapter - $File"
Get-Content -LiteralPath $File -TotalCount $LimitInt
