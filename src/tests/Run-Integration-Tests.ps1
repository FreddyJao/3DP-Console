<#
.SYNOPSIS
    Runs integration tests with real printer via serial port.

.DESCRIPTION
    First checks if COM port is free (no PrusaSlicer, Pronterface, etc.).
    Then starts Test-All.ps1 with -WithPort and the same parameters you pass here.

    COVERAGE: .\src\tests\TEST-COVERAGE.de.md explains which lib\*.ps1 functions are exercised
    (German labels: Direct / Indirect / Partial / Conditional / No auto-test). Optional switches below
    match the conditional ("bedingt") + copy-paste table there.

    Defaults align with Test-All.ps1 -WithPort (SkipLong on, no -TestLevelCompare unless you opt in).

.PARAMETER ComPort
    COM port for tests (default: COM5).

.PARAMETER TestLevelCompare
    Switch: runs Invoke-LevelCompareLoop (2x G29, CSV, ~10+ min). Default: off (opt-in).

.PARAMETER SkipLong
    Boolean (default $true): skip long tests. Use -SkipLong:$false for full G29/loops. Pass-through to Test-All.ps1.

.PARAMETER SkipHeating
    Skip heating tests. Pass-through to Test-All.ps1.

.PARAMETER TestM112
    If set, runs optional M112 emergency-stop test (after confirmation). Dangerous – pass-through to Test-All.ps1.

.PARAMETER TestTemp2
    If set, runs optional temp2_nozzle minimal loop. Pass-through to Test-All.ps1.

.PARAMETER TestExtraQuickActions
    QuickActions dw, bw (M109/M190 wait; not with -SkipHeating). With -SkipLong still on, also QuickAction level (G29). Pass-through to Test-All.ps1.

.PARAMETER DryRun
    Does not call Test-All.ps1. Prints the parameter bundle that would be passed (and runs COM check unless -SkipPortCheck).

.PARAMETER SkipPortCheck
    With -DryRun: skip opening the COM port (e.g. no printer connected; you only want to see the planned flags).

.EXAMPLE
    .\src\tests\Run-Integration-Tests.ps1
    Same as src\tests\Test-All.ps1 -WithPort (baseline integration; see TEST-COVERAGE.de.md). Run from repo root.

.EXAMPLE
    .\src\tests\Run-Integration-Tests.ps1 -TestLevelCompare
    Adds conditional path: Invoke-LevelCompareLoop + Read-SerialAndCapture (~10+ min).

.EXAMPLE
    .\src\tests\Run-Integration-Tests.ps1 -ComPort COM4 -SkipLong:$false
    Long G29 / prepare / level_rehome_once / temp_ramp (see TEST-COVERAGE.de.md Copy-Paste).

.EXAMPLE
    .\tests\Run-Integration-Tests.ps1 -DryRun -TestLevelCompare
    Shows splat for Test-All.ps1 without running tests (still checks COM unless -SkipPortCheck).

.EXAMPLE
    .\src\tests\Run-Integration-Tests.ps1 -DryRun -SkipPortCheck -TestTemp2
    Print planned parameters only (no serial open).

.NOTES
    Function checklist: .\src\tests\TEST-COVERAGE.de.md (from repo root).
    Underlying runner: .\src\tests\Test-All.ps1

.LINK
    src\tests\TEST-COVERAGE.de.md
#>

param(
    [string]$ComPort = "COM5",
    [switch]$TestLevelCompare,
    [bool]$SkipLong = $true,
    [switch]$SkipHeating,
    [switch]$TestM112,
    [switch]$TestTemp2,
    [switch]$TestExtraQuickActions,
    [switch]$DryRun,
    [switch]$SkipPortCheck
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-IntegrationTestAllSplat {
    param(
        [string]$ComPort,
        [switch]$TestLevelCompare,
        [bool]$SkipLong,
        [switch]$SkipHeating,
        [switch]$TestM112,
        [switch]$TestTemp2,
        [switch]$TestExtraQuickActions
    )
    $h = @{
        WithPort    = $true
        ComPort     = $ComPort
        SkipLong    = $SkipLong
        SkipHeating = $SkipHeating
    }
    if ($TestLevelCompare.IsPresent) { $h['TestLevelCompare'] = $true }
    if ($TestM112) { $h['TestM112'] = $true }
    if ($TestTemp2) { $h['TestTemp2'] = $true }
    if ($TestExtraQuickActions) { $h['TestExtraQuickActions'] = $true }
    return $h
}

# --- Check port availability (optional for DryRun) ---
$probeBaud = 115200
$cfgForProbe = Join-Path (Split-Path -Parent $PSScriptRoot) '3DP-Config.ps1'
if (Test-Path -LiteralPath $cfgForProbe) {
    try {
        $cfgHt = . $cfgForProbe
        if ($cfgHt -is [System.Collections.IDictionary] -and $null -ne $cfgHt['BaudRate']) {
            $probeBaud = [int]$cfgHt['BaudRate']
        }
    } catch { }
}

if (-not ($DryRun -and $SkipPortCheck)) {
    Write-Host "Checking COM port $ComPort (probe baud $probeBaud)..." -ForegroundColor Cyan
    try {
        $port = New-Object System.IO.Ports.SerialPort $ComPort, $probeBaud, None, 8, One
        $port.Open()
        $port.Close()
        $port.Dispose()
        Write-Host "  Port free." -ForegroundColor Green
    }
    catch {
        if ($DryRun) {
            Write-Host "  WARN: $ComPort not available (DryRun continues)." -ForegroundColor Yellow
        } else {
            Write-Host "  ERROR: $ComPort not available." -ForegroundColor Red
            Write-Host "  Close PrusaSlicer, Pronterface, 3DP-Console or other serial programs." -ForegroundColor Yellow
            Write-Host "  Then run again." -ForegroundColor Yellow
            exit 1
        }
    }
} else {
    Write-Host "SkipPortCheck: COM probe skipped." -ForegroundColor DarkGray
}

$testParams = Get-IntegrationTestAllSplat -ComPort $ComPort -TestLevelCompare:$TestLevelCompare -SkipLong $SkipLong -SkipHeating:$SkipHeating -TestM112:$TestM112 -TestTemp2:$TestTemp2 -TestExtraQuickActions:$TestExtraQuickActions

$parts = @()
if ($TestLevelCompare.IsPresent) { $parts += 'TestLevelCompare (level_compare 2, ~10+ min)' } else { $parts += 'no TestLevelCompare (opt-in: -TestLevelCompare)' }
if (-not $SkipLong) { $parts += 'SkipLong off (G29, long loops)' } else { $parts += 'SkipLong on (default)' }
if ($SkipHeating) { $parts += 'SkipHeating' }
if ($TestM112) { $parts += 'TestM112' }
if ($TestTemp2) { $parts += 'TestTemp2' }
if ($TestExtraQuickActions) { $parts += 'TestExtraQuickActions (dw, bw[, level if SkipLong])' }
$msg = $parts -join '; '

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: would invoke src\tests\Test-All.ps1 with (see TEST-COVERAGE.de.md):" -ForegroundColor Cyan
    $testParams.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ('  ' + $_.Key + ' = ' + $_.Value) -ForegroundColor Gray }
    Write-Host "  Summary: $msg" -ForegroundColor DarkGray
    Write-Host "  Full command equivalent (example):" -ForegroundColor DarkGray
    $argList = @('-WithPort', '-ComPort', $ComPort, "-SkipLong:$SkipLong")
    if ($SkipHeating) { $argList += '-SkipHeating' }
    if ($TestLevelCompare.IsPresent) { $argList += '-TestLevelCompare' }
    if ($TestM112) { $argList += '-TestM112' }
    if ($TestTemp2) { $argList += '-TestTemp2' }
    if ($TestExtraQuickActions) { $argList += '-TestExtraQuickActions' }
    Write-Host ('  .\src\tests\Test-All.ps1 ' + ($argList -join ' ')) -ForegroundColor DarkGray
    Write-Host "  For unit tests + integration plan only (no hardware [7]): .\src\tests\Test-All.ps1 -IntegrationPlanOnly -ComPort $ComPort ..." -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "Starting integration tests ($msg)..." -ForegroundColor Cyan
Write-Host ('  Coverage: ' + (Join-Path $PSScriptRoot 'TEST-COVERAGE.de.md')) -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot "Test-All.ps1") @testParams
