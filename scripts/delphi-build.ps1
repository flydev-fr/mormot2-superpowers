<#
.SYNOPSIS
delphi-build: compile a Delphi project (.dpr or .dproj) with mORMot 2
search paths injected.

.DESCRIPTION
Resolves MORMOT2_PATH, picks dcc32 vs dcc64 (default dcc64), and either
calls MSBuild on a .dproj or invokes the dcc compiler on a .dpr. Emits a
trailing structured BUILD_RESULT line that downstream skills grep.

Exit codes:
  0 success
  1 misuse
  2 MORMOT2_PATH unset or invalid
  5 project file missing
  6 no Delphi compiler on PATH
  7 build failed (errors > 0)
#>
param(
    [Parameter(Mandatory = $true)] [string]$Project,
    [ValidateSet('dcc32','dcc64','msbuild','auto')] [string]$Compiler = 'auto'
)

$ErrorActionPreference = 'Continue'

function Emit-Result {
    param([int]$ExitCode, [int]$Errors = 0, [int]$Warnings = 0, [string]$First = '')
    "BUILD_RESULT exit=$ExitCode errors=$Errors warnings=$Warnings first=$First"
}

if ([string]::IsNullOrEmpty($env:MORMOT2_PATH)) {
    [Console]::Error.WriteLine('MORMOT2_PATH is not set')
    Emit-Result -ExitCode 2 -First 'MORMOT2_PATH unset'
    exit 2
}
if (-not (Test-Path $env:MORMOT2_PATH -PathType Container)) {
    [Console]::Error.WriteLine("MORMOT2_PATH=$env:MORMOT2_PATH not found")
    Emit-Result -ExitCode 2 -First "MORMOT2_PATH not found"
    exit 2
}
if (-not (Test-Path $Project -PathType Leaf)) {
    [Console]::Error.WriteLine("project file '$Project' does not exist")
    Emit-Result -ExitCode 5 -First "project missing: $Project"
    exit 5
}

# Resolve compiler
$ResolvedCompiler = $Compiler
if ($Compiler -eq 'auto') {
    if ($Project -match '\.dproj$') { $ResolvedCompiler = 'msbuild' }
    else                            { $ResolvedCompiler = 'dcc64'   }
}

$ExeName = switch ($ResolvedCompiler) {
    'dcc32'   { 'dcc32.exe'   }
    'dcc64'   { 'dcc64.exe'   }
    'msbuild' { 'msbuild.exe' }
}

$Found = Get-Command $ExeName -ErrorAction SilentlyContinue
if (-not $Found) {
    [Console]::Error.WriteLine("$ExeName not found on PATH")
    Emit-Result -ExitCode 6 -First "$ExeName missing from PATH"
    exit 6
}

# Build search-path arguments for dcc compilers
$SrcRoot = Join-Path $env:MORMOT2_PATH 'src'
$SearchPaths = @(
    $SrcRoot,
    (Join-Path $SrcRoot 'core'),
    (Join-Path $SrcRoot 'orm'),
    (Join-Path $SrcRoot 'rest'),
    (Join-Path $SrcRoot 'soa'),
    (Join-Path $SrcRoot 'db'),
    (Join-Path $SrcRoot 'crypt'),
    (Join-Path $SrcRoot 'net'),
    (Join-Path $SrcRoot 'app'),
    (Join-Path $SrcRoot 'lib')
) | Where-Object { Test-Path $_ -PathType Container }

if ($ResolvedCompiler -eq 'msbuild') {
    $output = & $Found.Path $Project /t:Build /p:Config=Debug 2>&1
} else {
    $unitArgs = $SearchPaths | ForEach-Object { "-U`"$_`"" }
    $incArgs  = $SearchPaths | ForEach-Object { "-I`"$_`"" }
    $output = & $Found.Path @unitArgs @incArgs $Project 2>&1
}
$exit = $LASTEXITCODE

# Parse errors and first error line (best-effort)
$errors = ($output | Select-String -Pattern '\bError:|\[dcc\d+ Error\]|\bF\d{4}:' -AllMatches).Matches.Count
$warns  = ($output | Select-String -Pattern '\bWarning:|\[dcc\d+ Warning\]'         -AllMatches).Matches.Count
$first  = ($output | Select-String -Pattern '\bError:|\[dcc\d+ Error\]|\bF\d{4}:'    | Select-Object -First 1).Line
if (-not $first) { $first = '' }

# Always print the build output to stdout so the caller can see it.
$output | ForEach-Object { Write-Output $_ }

if ($exit -ne 0 -or $errors -gt 0) {
    Emit-Result -ExitCode 7 -Errors $errors -Warnings $warns -First $first
    exit 7
}

Emit-Result -ExitCode 0 -Errors 0 -Warnings $warns -First ''
exit 0
