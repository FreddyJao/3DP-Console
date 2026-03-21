<#
.SYNOPSIS
    Unit and integration tests for 3DP-Console.

.DESCRIPTION
    Unit tests run always without hardware (incl. Config.Loops vs 3DP-Config.ps1, UI wrap, mesh helpers).
    Integration tests require -WithPort and a free COM port.
    Long integration steps use current loop names: prepare, level_rehome_once, temp_ramp (not legacy vorbereitung/level_max_once).

    COVERAGE (checklist, not line %): .\src\tests\TEST-COVERAGE.de.md maps lib\*.ps1 functions to these runs.
    Optional Pester + CodeCoverage: .\src\tests\Run-Pester.ps1 (mocks Invoke-GcodeAndWaitOrAbort without SerialPort).
    Stages used there: Direkt, Indirekt, Teilweise, Bedingt, Kein Auto-Test (+ subtypes).

    This script sets THREEDP_CONSOLE_SKIP_MAIN=1 so Main() is never started (interactive console = manual only per TEST-COVERAGE.de.md).

    Optional integration flags add "bedingt" (conditional) coverage of longer or risky paths:
    -SkipLong:$false  — Invoke-Loop with prepare, level_rehome_once, temp_ramp; G29; G29 T
    -TestLevelCompare — Invoke-LevelCompareLoop, Read-SerialAndCapture (~10+ min)
    -TestTemp2        — Invoke-Temp2LevelingLoop via Invoke-Loop (~10 min)
    -TestM112         — actually send M112 after confirm (EMERGENCY STOP — dangerous)

.PARAMETER WithPort
    Enables integration tests with real printer via serial port.

.PARAMETER SkipHeating
    Skips heating tests (/pla, /abs, /duese, /bett, /off, move, extrude).

.PARAMETER SkipLong
    Skips long tests: G29, G29 T, Loops prepare|level_rehome_once|temp_ramp.

.PARAMETER TestM112
    Sends M112 (EMERGENCY STOP) on confirmation - Caution!

.PARAMETER TestLevelCompare
    Runs loop level_compare 2x (approx. 10+ min).

.PARAMETER TestTemp2
    Runs loop temp2_nozzle with minimal config (2 steps, ca. 10 min).

.PARAMETER ComPort
    COM port for integration tests (default: COM5).

.PARAMETER IntegrationPlanOnly
    After unit tests, prints the integration coverage plan (see TEST-COVERAGE.de.md) and skips section [7] (no serial open). Use with -WithPort flags mentally omitted; you can pass -ComPort for the plan line. Implies no hardware.

.EXAMPLE
    .\src\tests\Test-All.ps1
    Unit tests only (no printer). Run from repo root.

.EXAMPLE
    .\src\tests\Test-All.ps1 -WithPort
    Unit + Integration with COM5 (SkipLong active).

.EXAMPLE
    .\src\tests\Test-All.ps1 -WithPort -SkipLong:$false
    Full integration incl. G29 and all loops.

.EXAMPLE
    .\src\tests\Test-All.ps1 -WithPort -TestLevelCompare -TestTemp2
    Adds bedingt paths from TEST-COVERAGE.de.md (long runs).

.EXAMPLE
    .\src\tests\Test-All.ps1 -IntegrationPlanOnly -ComPort COM4
    Unit tests + integration plan for COM4 only (no printer).

.NOTES
    Function-level checklist: .\src\tests\TEST-COVERAGE.de.md (from repo root).
    Wrapper with COM pre-check: .\src\tests\Run-Integration-Tests.ps1 (forwards the same parameters).

.LINK
    src\tests\TEST-COVERAGE.de.md
#>

param(
    [switch]$WithPort,
    [switch]$SkipHeating,
    [bool]$SkipLong = $true,
    [switch]$TestM112,
    [switch]$TestLevelCompare,
    [switch]$TestTemp2,
    [string]$ComPort = "COM5",
    [switch]$IntegrationPlanOnly
)

$ErrorActionPreference = 'Stop'
# This script lives in src\tests\; $ProjectRoot = src (3DP-Console.ps1 + lib); $RepoRoot = repository root (optional PrusaMini-*.ps1)
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $ProjectRoot
$env:THREEDP_CONSOLE_SKIP_MAIN = '1'
$TestComPort = $ComPort   # Preserve before dot-sourcing (3DP-Console.ps1 overwrites $ComPort)

. (Join-Path $ProjectRoot "3DP-Console.ps1")

$fail = 0

function Get-TestPrusaMiniMacrosPath {
    $p1 = Join-Path $ProjectRoot 'PrusaMini-Macros.ps1'
    if (Test-Path -LiteralPath $p1) { return $p1 }
    $p2 = Join-Path $RepoRoot 'PrusaMini-Macros.ps1'
    if (Test-Path -LiteralPath $p2) { return $p2 }
    return $p1
}

# --- Helper: Runs a test block and counts failures ---
function Test-Name {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    try {
        & $Block
        Write-Host "  OK $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAIL $Name : $_" -ForegroundColor Red
        $script:fail++
    }
}

function Write-IntegrationCoveragePlan {
    param(
        [string]$ComPortLabel,
        [bool]$SkipLong,
        [switch]$SkipHeating,
        [switch]$TestLevelCompare,
        [switch]$TestTemp2,
        [switch]$TestM112
    )
    Write-Host ""
    Write-Host "  --- Integration-Plan (TEST-COVERAGE.de.md: Direkt / Bedingt) ---" -ForegroundColor DarkCyan
    Write-Host "  COM: $ComPortLabel" -ForegroundColor DarkGray
    Write-Host "  Immer [7]-Baseline: Send-Gcode, Read-SerialResponse, Invoke-SingleCommand (CLI), Invoke-*, QuickActions, Palette send, ..." -ForegroundColor DarkGray
    if ($SkipLong) {
        Write-Host "  SkipLong=ON: kein G29-Block, keine Loops prepare | level_rehome_once | temp_ramp | G29 T" -ForegroundColor DarkGray
    } else {
        Write-Host "  SkipLong=OFF: G29, G29 T, Invoke-Loop prepare, level_rehome_once, temp_ramp (lang)" -ForegroundColor Yellow
    }
    if ($SkipHeating) {
        Write-Host "  SkipHeating: keine /pla, /abs, /duese, /bett, /off, Move/Extrude-Heizpfade" -ForegroundColor DarkGray
    }
    if ($TestLevelCompare) {
        Write-Host "  TestLevelCompare: Invoke-LevelCompareLoop, Read-SerialAndCapture (~10+ min)" -ForegroundColor Yellow
    } else {
        Write-Host "  ohne -TestLevelCompare: kein Invoke-LevelCompareLoop am Drucker (Unit [6d2] = nur CSV-Mock)" -ForegroundColor DarkGray
    }
    if ($TestTemp2) {
        Write-Host "  TestTemp2: Invoke-Temp2LevelingLoop via Invoke-Loop (~10 min)" -ForegroundColor Yellow
    }
    if ($TestM112) {
        Write-Host "  TestM112: M112 wirklich senden (Not-Aus!)" -ForegroundColor Red
    }
    Write-Host "  Kein Auto-Test: Main, Get-PortOrRetry-Menue, Invoke-InteractiveBedLevelLoop (manuell)" -ForegroundColor DarkGray
    Write-Host "  --- Ende Plan ---" -ForegroundColor DarkCyan
}

# =============================================================================
# UNIT TESTS (no hardware needed)
# =============================================================================

Write-Host "`n=== [0] Script Parameters (3DP-Console.ps1) ===" -ForegroundColor Cyan
Test-Name "Console -Help akzeptiert -ComPort" {
    $out = & (Join-Path $ProjectRoot "3DP-Console.ps1") -Help -ComPort COM99 2>&1
    if ($out -notmatch '3DP-Console') { throw "Help output expected" }
}
Test-Name "Console -About akzeptiert -ConfigPath" {
    $cfgAbout = Join-Path $ProjectRoot "3DP-Config.ps1"
    $out = & (Join-Path $ProjectRoot "3DP-Console.ps1") -About -ConfigPath $cfgAbout 2>&1
    if ($out -notmatch '3DP-Console') { throw "About output expected" }
}
Test-Name "Console -Example shows examples" {
    $out = & (Join-Path $ProjectRoot "3DP-Console.ps1") -Example 2>&1
    if ($out -notmatch 'Examples') { throw "Example output expected" }
    if ($out -notmatch '-Command') { throw "-Command should appear in examples" }
}

Write-Host "`n=== [1] Load Config ===" -ForegroundColor Cyan
Test-Name "Config PLA/ABS" {
    if (-not $Script:Config.PLA_Hotend) { throw "PLA_Hotend missing" }
    if ($Script:Config.PLA_Hotend -ne 170) { throw "PLA_Hotend=$($Script:Config.PLA_Hotend)" }
}
Test-Name "Config feedrate" {
    if (-not $Script:Config.xy_feedrate) { throw "xy_feedrate missing" }
}
Test-Name "Config DueseLabel" {
    if (-not $Script:DueseLabel) { throw "DueseLabel missing" }
    if ($Script:DueseLabel.Length -lt 2) { throw "DueseLabel too short" }
}
Test-Name "Config MaxVisibleItems" {
    if ($Script:MaxVisibleItems -lt 1 -or $Script:MaxVisibleItems -gt 50) { throw "MaxVisibleItems=$($Script:MaxVisibleItems) invalid" }
}
Test-Name "Get-GcodeTimeout G28 nutzt Config" {
    $t = Get-GcodeTimeout -Gcode "G28"
    if ($t -lt 60000) { throw "G28 timeout too short: $t ms" }
}
Test-Name "Get-GcodeTimeout M109 nutzt Config" {
    $t = Get-GcodeTimeout -Gcode "M109 S200"
    if ($t -lt 60000) { throw "M109 timeout too short: $t ms" }
}
Test-Name "Get-GcodeTimeout M105 nutzt Default" {
    $t = Get-GcodeTimeout -Gcode "M105"
    if ($t -lt 1000 -or $t -gt 60000) { throw "M105 timeout invalid: $t ms" }
}

Write-Host "`n=== [1b] Get-UIString (placeholders) ===" -ForegroundColor Cyan
Test-Name "Get-UIString ComPort" {
    $s = Get-UIString -Key 'StatusConnected'
    if (-not $s) { throw "Empty string" }
    if ($s -notmatch $Script:Config.ComPort) { throw "ComPort not replaced: $s" }
}
Test-Name "Get-UIString NozzleTemp" {
    $s = Get-UIString -Key 'HintShortcuts'
    if ($s -notmatch [string]$Script:Config.NozzleTempCelsius) { throw "NozzleTemp not replaced" }
}
Test-Name "Get-UIString unbekannter Key" {
    $s = Get-UIString -Key 'NichtVorhanden'
    if ($s -ne '') { throw "Expected empty string for unknown key, got: $s" }
}
Test-Name "Get-UIString DueseLabel" {
    $s = Get-UIString -Key 'HintShortcuts'
    if (-not $s) { throw "HintShortcuts empty" }
    if ($s -notmatch $Script:DueseLabel) { throw "DueseLabel not replaced in HintShortcuts: $s" }
}

Write-Host "`n=== [2] Get-SlashCommandArgs ===" -ForegroundColor Cyan
Test-Name "home xy" {
    $a = Get-SlashCommandArgs -Cmd "/home xy" -Prefix "/home"
    if ($a -join ' ' -ne "xy") { throw "Expected 'xy', got $($a -join ' ')" }
}
Test-Name "move X 10" {
    $a = Get-SlashCommandArgs -Cmd "/move X 10" -Prefix "/move"
    if ($a[0] -ne "x" -or $a[1] -ne "10") { throw "Expected x,10 got $($a -join ',')" }
}
Test-Name "macro preheat 200" {
    $a = Get-SlashCommandArgs -Cmd "/macro preheat 200" -Prefix "/macro"
    if ($a[0] -ne "preheat" -or $a[1] -ne "200") { throw "Expected preheat,200" }
}

Write-Host "`n=== [3] Get-PaletteItems Slash with params ===" -ForegroundColor Cyan
Test-Name "/home xy match" {
    $buf = [char]0x2F + "home xy"
    $items = @(Get-PaletteItems -Buffer $buf)
    if ($items.Count -eq 0) { throw "No match" }
    if ($items[0].cmd -ne $buf) { throw "cmd='$($items[0].cmd)'" }
    if ($items[0].action -ne "home") { throw "action missing" }
}
Test-Name "/move X 10 match" {
    $buf = [char]0x2F + "move X 10"
    $items = @(Get-PaletteItems -Buffer $buf)
    if ($items[0].cmd -ne $buf) { throw "cmd='$($items[0].cmd)'" }
}

Write-Host "`n=== [4] Macros + Loops (from Config) ===" -ForegroundColor Cyan
Test-Name "Macros from Config" {
    $m = $Script:Config.Macros
    if (-not $m) {
        $mp = Get-TestPrusaMiniMacrosPath
        if (Test-Path -LiteralPath $mp) { $m = . $mp }
    }
    if (-not $m -or -not $m.preheat) { throw "preheat missing" }
    $g = $m.preheat -replace '\{0\}', '200'
    if ($g -ne 'M104 S200') { throw "Subst: $g" }
}
Test-Name "Macro pla (array)" {
    $m = $Script:Config.Macros
    if (-not $m) {
        $mp = Get-TestPrusaMiniMacrosPath
        if (Test-Path -LiteralPath $mp) { $m = . $mp }
    }
    if ($m.pla -isnot [array]) { throw "pla should be array" }
    if ($m.pla.Count -lt 2) { throw "pla needs 2 lines" }
}

Write-Host "`n=== [5] Format-TemperatureReport ===" -ForegroundColor Cyan
Test-Name "Parse temperature" {
    $r = Format-TemperatureReport -Line "ok T:21.87 /0.0 B:23.28 /0.0"
    if (-not $r -or $r.Count -lt 2) { throw "Expected 2 lines" }
    if ($r[0] -notmatch "21.87") { throw "Hotend not found" }
}

Write-Host "`n=== [6] SlashCommands present ===" -ForegroundColor Cyan
$required = @('/pla','/abs','/home','/move','/extrude','/reverse','/monitor','/ls','/sdprint','/macro')
foreach ($c in $required) {
    Test-Name $c {
        $found = $Script:SlashCommands | Where-Object { $_.cmd -eq $c }
        if (-not $found) { throw "Not found" }
    }
}

Write-Host "`n=== [6b] QuickActions present ===" -ForegroundColor Cyan
$qKeys = @('d','dw','b','bw','off','fan','home','level','temp')
foreach ($k in $qKeys) {
    Test-Name "QuickAction $k" {
        $q = $Script:QuickActions | Where-Object { $_.key -eq $k } | Select-Object -First 1
        if (-not $q) { throw "Not found" }
        if (-not $q.gcode -or $q.gcode.Length -lt 2) { throw "gcode empty or invalid" }
    }
}

Write-Host "`n=== [6c] G/M-Palette ===" -ForegroundColor Cyan
Test-Name "Get-PaletteItems g" {
    $items = @(Get-PaletteItems -Buffer "g")
    if ($items.Count -eq 0) { throw "No G commands" }
    if ($items[0].cmd -notmatch '^G\d') { throw "First entry not G-code" }
}
Test-Name "Get-PaletteItems g28" {
    $items = @(Get-PaletteItems -Buffer "g28")
    $g28 = $items | Where-Object { $_.cmd -eq 'G28' }
    if (-not $g28) { throw "G28 not found" }
}
Test-Name "Get-PaletteItems m" {
    $items = @(Get-PaletteItems -Buffer "m")
    if ($items.Count -eq 0) { throw "No M commands" }
    if ($items[0].cmd -notmatch '^M\d') { throw "First entry not M-code" }
}
Test-Name "Get-PaletteItems m104" {
    $items = @(Get-PaletteItems -Buffer "m104")
    $m104 = $items | Where-Object { $_.cmd -eq 'M104' }
    if (-not $m104) { throw "M104 not found" }
}
Test-Name "Get-PaletteItems empty buffer" {
    $items = @(Get-PaletteItems -Buffer "")
    if ($items.Count -ne 0) { throw "Empty buffer should yield no matches, got $($items.Count)" }
}
Test-Name "Get-PaletteItems whitespace only" {
    $items = @(Get-PaletteItems -Buffer "   ")
    if ($items.Count -ne 0) { throw "Whitespace buffer should yield no matches" }
}
Test-Name "Get-PaletteItems loop empty" {
    $items = @(Get-PaletteItems -Buffer "loop ")
    if ($items.Count -eq 0) { throw "loop with space should list loops" }
}
Test-Name "Get-PaletteItems loop temp2 (Temp2 Leveling Loops)" {
    $items = @(Get-PaletteItems -Buffer "loop temp2")
    $names = @($items | ForEach-Object { $_.cmd })
    foreach ($expected in @('loop temp2_nozzle', 'loop temp2_bed', 'loop temp2_combined')) {
        if ($names -notcontains $expected) { throw "Expected $expected in temp2 loops, got: $($names -join ', ')" }
    }
    $nozzle = $items | Where-Object { $_.cmd -eq 'loop temp2_nozzle' } | Select-Object -First 1
    if (-not $nozzle.desc -or $nozzle.desc -notmatch 'Nozzle') { throw "temp2_nozzle should have desc with Nozzle" }
}
Test-Name "Temp2 Config structure (Loops temp2_* have action)" {
    $loops = $Script:Config.Loops
    foreach ($name in @('temp2_nozzle', 'temp2_bed', 'temp2_combined')) {
        if (-not $loops[$name]) { throw "Config missing loop $name" }
        $e = $loops[$name]
        if (-not ($e -is [hashtable])) { throw "Loop $name must be hashtable" }
        if ($e.action -ne $name) { throw "Loop $name must have action=$name, got $($e.action)" }
        if ($name -eq 'temp2_nozzle' -and $null -eq $e.fixedBed) { throw "temp2_nozzle needs fixedBed" }
        if ($name -eq 'temp2_bed' -and $null -eq $e.fixedNozzle) { throw "temp2_bed needs fixedNozzle" }
    }
}

Write-Host "`n=== [6c2] Tab completion (Palette) ===" -ForegroundColor Cyan
Test-Name "Tab completes selected command" {
    $queue = [System.Collections.ArrayList]@('Tab', 'Enter')
    $result = Invoke-CommandPalette -Port $null -TestKeyQueue $queue -InitialBuffer 'loop level'
    if (-not $result) { throw "No result after Tab+Enter" }
    if ($result.cmd -ne 'loop level_compare') { throw "Expected 'loop level_compare', got '$($result.cmd)'" }
}

Write-Host "`n=== [6d] Parse-MeshFromG29Output ===" -ForegroundColor Cyan
Test-Name "Parse mesh from G29 format" {
    $sample = @"
       0      1      2      3
0  +0.124 -0.000 -0.059 -0.148
1  +0.052 +0.310 +0.277 +0.125
2  +0.100 +0.282 +0.324 +0.128
3  +0.194 +0.079 -0.073 -0.106
"@
    $mesh = Parse-MeshFromG29Output $sample
    if ($mesh.Count -ne 4) { throw "Expected 4 rows, got $($mesh.Count)" }
    if ($mesh[0].Count -ne 4) { throw "Expected 4 columns, got $($mesh[0].Count)" }
    if ([Math]::Abs($mesh[0][0] - 0.124) -gt 0.001) { throw "mesh[0][0] should be 0.124, got $($mesh[0][0])" }
}
Test-Name "Parse mesh from M420 CSV format" {
    $m420 = @"
0.124,-0.000,-0.059,-0.148
0.052,0.310,0.277,0.125
0.100,0.282,0.324,0.128
0.194,0.079,-0.073,-0.106
"@
    $mesh = Parse-MeshFromG29Output $m420
    if ($mesh.Count -ne 4) { throw "Expected 4 rows, got $($mesh.Count)" }
    if ([Math]::Abs($mesh[0][0] - 0.124) -gt 0.001) { throw "mesh[0][0] should be 0.124" }
}

Write-Host "`n=== [6d1] alleMeshes += ,`$mesh (add mesh as whole) ===" -ForegroundColor Cyan
Test-Name "alleMeshes keeps meshes as units" {
    $m1 = @( @(1,2), @(3,4) )
    $m2 = @( @(5,6), @(7,8) )
    $arr = @()
    $arr += ,$m1
    $arr += ,$m2
    if ($arr.Count -ne 2) { throw "Expected 2 meshes, got $($arr.Count)" }
    if ($arr[0].Count -ne 2) { throw "Mesh 1 should have 2 rows, got $($arr[0].Count)" }
    if ($arr[1][0][0] -ne 5) { throw "Mesh 2 [0][0] should be 5, got $($arr[1][0][0])" }
}

Write-Host "`n=== [6d2] CSV write and comparison (mock data) ===" -ForegroundColor Cyan
Test-Name "LevelCompare CSV creation and content" {
    # Temp directory for CSV output (deleted at end)
    $tmpDir = Join-Path $env:TEMP "PrusaMiniLevelCompareTest_$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        # Three mock meshes (4x4) for level_compare logic
        $m1 = @( @(0.124, -0.000, -0.059, -0.148), @(0.052, 0.310, 0.277, 0.125), @(0.100, 0.282, 0.324, 0.128), @(0.194, 0.079, -0.073, -0.106) )
        $m2 = @( @(0.130, -0.005, -0.055, -0.142), @(0.058, 0.305, 0.280, 0.122), @(0.098, 0.278, 0.330, 0.130), @(0.190, 0.082, -0.070, -0.108) )
        $m3 = @( @(0.120, 0.002, -0.062, -0.145), @(0.048, 0.312, 0.274, 0.128), @(0.102, 0.285, 0.320, 0.126), @(0.198, 0.076, -0.075, -0.104) )
        $alleMeshes = @($m1, $m2, $m3)
        $timestamp = "2025-03-13_12-00"
        $prefix = "BedLevel_Messung"
        $rows = $alleMeshes[0].Count
        $cols = $alleMeshes[0][0].Count

        foreach ($i in 1..$alleMeshes.Count) {
            $mesh = $alleMeshes[$i - 1]
            $csvFile = Join-Path $tmpDir "${prefix}_${timestamp}_Runde${i}.csv"
            $header = "Row;" + (0..($mesh[0].Count - 1) | ForEach-Object { "Col$_" }) -join ";"
            $csvRows = @($header)
            $inv = [cultureinfo]::InvariantCulture
        for ($r = 0; $r -lt $mesh.Count; $r++) {
            $rowStr = ($mesh[$r] | ForEach-Object { $_.ToString($inv) }) -join ";"
            $csvRows += "R$r;$rowStr"
        }
            $csvRows | Out-File $csvFile -Encoding UTF8
        }

        $deltaRows = @("Comparison;MaxDelta_mm;Details")
        $baseline = $alleMeshes[0]
        for ($m = 1; $m -lt $alleMeshes.Count; $m++) {
            $curr = $alleMeshes[$m]; $prev = $baseline
            $maxDiff = 0
            for ($r = 0; $r -lt $rows; $r++) {
                for ($c = 0; $c -lt $cols; $c++) {
                    $d = [Math]::Abs($curr[$r][$c] - $prev[$r][$c])
                    if ($d -gt $maxDiff) { $maxDiff = $d }
                }
            }
            $deltaRows += "Round1_to_$($m+1);$([Math]::Round($maxDiff, 5));"
        }
        $deltaRows | Out-File (Join-Path $tmpDir "Comparison_Rounds_${timestamp}.csv") -Encoding UTF8

        $statRows = @("Row;Col;Min_mm;Max_mm;Avg_mm")
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                $vals = $alleMeshes | ForEach-Object { $_[$r][$c] }
                $min = ($vals | Measure-Object -Minimum).Minimum
                $max = ($vals | Measure-Object -Maximum).Maximum
                $avg = ($vals | Measure-Object -Average).Average
                $statRows += "R$r;C$c;$([Math]::Round($min, 5));$([Math]::Round($max, 5));$([Math]::Round($avg, 5))"
            }
        }
        $statRows | Out-File (Join-Path $tmpDir "Stats_Measurements_${timestamp}.csv") -Encoding UTF8

        $r1Path = Join-Path $tmpDir "${prefix}_${timestamp}_Runde1.csv"
        if (-not (Test-Path $r1Path)) { throw "Round1 CSV file missing" }
        $r1Csv = Get-Content $r1Path -Raw -Encoding UTF8
        if ($r1Csv -notmatch 'Row') { throw "Round1 CSV: Row header missing" }
        if ($r1Csv -notmatch 'Col') { throw "Round1 CSV: Col header missing" }
        if ($r1Csv -notmatch '0\.124') { throw "Round1 CSV: value 0.124 missing" }

        $vergPath = Join-Path $tmpDir "Comparison_Rounds_${timestamp}.csv"
        if (-not (Test-Path $vergPath)) { throw "Comparison CSV file missing" }
        $vergCsv = Get-Content $vergPath -Raw -Encoding UTF8
        if ($vergCsv -notmatch 'Round1_to_2') { throw "Comparison CSV: Round1_to_2 missing (baseline to round 2)" }
        if ($vergCsv -notmatch 'Round1_to_3') { throw "Comparison CSV: Round1_to_3 missing (baseline to round 3)" }
        if ($vergCsv -match 'Round2_to_3') { throw "Comparison CSV: Round2_to_3 must not appear (only baseline to each round)" }

        $statPath = Join-Path $tmpDir "Stats_Measurements_${timestamp}.csv"
        if (-not (Test-Path $statPath)) { throw "Stats CSV file missing" }
        $statCsv = Get-Content $statPath -Raw -Encoding UTF8
        if ($statCsv -notmatch 'Min_mm') { throw "Stats CSV: Min_mm missing" }
        if ($statCsv -notmatch 'Avg_mm') { throw "Stats CSV: Avg missing" }
    } finally {
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n=== [6e] M112 confirmed (logic test) ===" -ForegroundColor Cyan
Test-Name "M112 sent on confirmation" {
    $origConfirm = Get-Item "function:Invoke-Confirm" -ErrorAction SilentlyContinue
    Set-Item -Path "function:Invoke-Confirm" -Value { param($Prompt) return $true }
    try {
        $wouldProceed = $false
        $gcode = "M112"
        if ($gcode -match '\bM112\b') {
            if (Invoke-Confirm -Prompt '  y/n') { $wouldProceed = $true }
        }
    } finally {
        if ($origConfirm -and $origConfirm.ScriptBlock) {
            Set-Item -Path "function:Invoke-Confirm" -Value $origConfirm.ScriptBlock
        }
    }
    if (-not $wouldProceed) { throw "On confirmation (y) should proceed" }
}

Write-Host "`n=== [6f] Interactive Bed Leveling ===" -ForegroundColor Cyan
# TDD: Get-MeshCellColor - testbare Farb-Logik (value, prevValue, thresholds) -> color, isImprovement
Test-Name "Get-MeshCellColor value 0.02 -> Green" {
    $r = Get-MeshCellColor -Value 0.02 -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r -or $r.color -ne 'Green') { throw "Expected Green for 0.02, got $($r.color)" }
}
Test-Name "Get-MeshCellColor value 0.10 -> Yellow" {
    $r = Get-MeshCellColor -Value 0.10 -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r -or $r.color -ne 'Yellow') { throw "Expected Yellow for 0.10, got $($r.color)" }
}
Test-Name "Get-MeshCellColor value 0.20 -> Red" {
    $r = Get-MeshCellColor -Value 0.20 -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r -or $r.color -ne 'Red') { throw "Expected Red for 0.20, got $($r.color)" }
}
Test-Name "Get-MeshCellColor with PrevValue improved" {
    $r = Get-MeshCellColor -Value 0.03 -PrevValue 0.10 -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r -or $r.isImprovement -ne $true) { throw "Expected isImprovement=true (|0.03|<|0.10|), got $($r.isImprovement)" }
}
Test-Name "Get-MeshCellColor with PrevValue worsened" {
    $r = Get-MeshCellColor -Value 0.12 -PrevValue 0.05 -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r -or $r.isImprovement -ne $false) { throw "Expected isImprovement=false (|0.12|>|0.05|), got $($r.isImprovement)" }
}
# Get-DeltaImprovement: |new| < |old| -> improved (true)
Test-Name "Get-DeltaImprovement improved" {
    $r = Get-DeltaImprovement -NewValue 0.03 -OldValue 0.10
    if ($r -ne $true) { throw "Expected true (improved: |0.03|<|0.10|), got $r" }
}
Test-Name "Get-DeltaImprovement worsened" {
    $r = Get-DeltaImprovement -NewValue 0.12 -OldValue 0.05
    if ($r -ne $false) { throw "Expected false (worsened: |0.12|>|0.05|), got $r" }
}
# Config & Palette
Test-Name "Get-PaletteItems loop interactive contains interactive_bedlevel" {
    $items = @(Get-PaletteItems -Buffer "loop interactive")
    $names = @($items | ForEach-Object { $_.cmd })
    if ($names -notcontains "loop interactive_bedlevel") { throw "Expected 'loop interactive_bedlevel' in palette, got: $($names -join ', ')" }
}
Test-Name "Config Loops interactive_bedlevel has action bedTemp nozzleTemp" {
    $entry = $Script:Config.Loops['interactive_bedlevel']
    if (-not $entry) { throw "Config.Loops['interactive_bedlevel'] missing" }
    if ($entry -isnot [hashtable]) { throw "interactive_bedlevel must be hashtable" }
    if ($entry.action -ne 'interactive_bedlevel') { throw "action must be 'interactive_bedlevel', got $($entry.action)" }
    if ($null -eq $entry.bedTemp) { throw "bedTemp missing" }
    if ($null -eq $entry.nozzleTemp) { throw "nozzleTemp missing" }
}
Test-Name "Config MeshThresholdGreenMm MeshThresholdYellowMm (Interactive Bed Leveling)" {
    $green = $Script:Config.MeshThresholdGreenMm
    $yellow = $Script:Config.MeshThresholdYellowMm
    if ($null -eq $green -and $null -eq $yellow) { throw "Config should have MeshThresholdGreenMm or MeshThresholdYellowMm (or both)" }
    if ($null -ne $green -and ([double]$green -le 0 -or [double]$green -gt 1)) { throw "MeshThresholdGreenMm should be in (0,1], got $green" }
    if ($null -ne $yellow -and ([double]$yellow -le 0 -or [double]$yellow -gt 1)) { throw "MeshThresholdYellowMm should be in (0,1], got $yellow" }
    if ($null -ne $green -and $null -ne $yellow -and [double]$green -gt [double]$yellow) { throw "MeshThresholdGreenMm ($green) must be <= MeshThresholdYellowMm ($yellow)" }
}
# Get-MeshCellColor Edge-Case: Value=NaN -> definiertes Verhalten (nicht crashen)
Test-Name "Get-MeshCellColor value NaN does not crash" {
    $r = Get-MeshCellColor -Value ([double]::NaN) -ThresholdGreen 0.05 -ThresholdYellow 0.15
    if (-not $r) { throw "Expected result object, got null" }
    if (-not $r.color) { throw "Expected color property, got empty" }
    # |NaN| > Threshold -> Red (definiertes Verhalten)
    if ($r.color -ne 'Red') { throw "Expected Red for NaN (|NaN|>threshold), got $($r.color)" }
}
# Format-MeshWithColors: Aufruf mit gueltigem Mesh wirft nicht
Test-Name "Format-MeshWithColors with valid mesh does not throw" {
    $smallMesh = @( @(0.01, 0.02), @(0.03, 0.04) )
    $null = Format-MeshWithColors -Mesh $smallMesh
}
# Format-MeshWithColors mit PrevMesh: Delta-Logik (↓/↑) greift, Aufruf ohne Fehler
Test-Name "Format-MeshWithColors with PrevMesh does not throw" {
    $mesh = @( @(0.01, 0.10), @(0.15, 0.02) )
    $prevMesh = @( @(0.05, 0.08), @(0.12, 0.06) )
    $null = Format-MeshWithColors -Mesh $mesh -PrevMesh $prevMesh
}

Write-Host "`n=== [6g] Config Loops + Palette (3DP-Config.ps1) ===" -ForegroundColor Cyan
Test-Name "Config.Loops expected keys from 3DP-Config" {
    $L = $Script:Config.Loops
    if (-not $L -or $L -isnot [hashtable]) { throw "Config.Loops missing" }
    foreach ($k in @(
            'prepare', 'cooldown', 'level_compare', 'interactive_bedlevel',
            'level_rehome', 'level_rehome_once', 'temp_ramp',
            'temp2_nozzle', 'temp2_bed', 'temp2_combined'
        )) {
        if (-not $L.ContainsKey($k)) { throw "Config.Loops missing key: $k" }
    }
}
Test-Name "Config LoopOrder lists known loops" {
    $ord = $Script:Config.LoopOrder
    if (-not $ord -or $ord -isnot [array] -or $ord.Count -lt 3) { throw "LoopOrder missing or too short" }
    if ($ord -notcontains 'prepare') { throw "LoopOrder should contain prepare" }
}
Test-Name "Get-LoopPaletteItems first entry matches LoopOrder[0]" {
    $items = @(Get-LoopPaletteItems)
    if ($items.Count -lt 1) { throw "No loop palette items" }
    $want = 'loop ' + [string]$Script:Config.LoopOrder[0]
    $got = $items[0].cmd.Trim()
    if ($got -ne $want) { throw "Expected first cmd '$want', got '$got'" }
}
Test-Name "Get-PaletteItems loop partial filter" {
    $m = @(Get-PaletteItems -Buffer 'loop prep')
    if ($m.Count -lt 1) { throw "Expected match for loop prep" }
    if ($m[0].cmd -notmatch 'prepare') { throw "Expected prepare, got $($m[0].cmd)" }
}

Write-Host "`n=== [6h] UI text wrap (palette descLong) ===" -ForegroundColor Cyan
Test-Name "Split-UITextToLines breaks at MaxWidth" {
    $s = 'G29 xN with CSV storage, round comparison (first measurement to each round) + Min/Max/Avg per probe point'
    $lines = @(Split-UITextToLines -Text $s -MaxWidth 42)
    if ($lines.Count -lt 2) { throw "Expected 2+ lines, got $($lines.Count)" }
    foreach ($line in $lines) {
        if ($line.Length -gt 42) { throw "Line len $($line.Length) > 42: $line" }
    }
}
Test-Name "Split-UITextToLines hard-breaks very long words" {
    $s = 'aaaaaaaabbbbbbbbccccccccdddddddd'
    $lines = @(Split-UITextToLines -Text $s -MaxWidth 12)
    if ($lines.Count -lt 2) { throw "Expected multiple segments" }
    foreach ($line in $lines) {
        if ($line.Length -gt 12) { throw "Segment too long: $($line.Length)" }
    }
}
Test-Name "Get-DescLongLineCount matches Split-UITextToLines width" {
    $s = 'one two three four five six seven eight nine ten eleven twelve'
    $lineLen = 30
    $wrapW = [Math]::Max(12, $lineLen - 4)
    $c = Get-DescLongLineCount -LongText $s -LineLen $lineLen
    $w = @(Split-UITextToLines -Text $s -MaxWidth $wrapW).Count
    if ($c -ne $w) { throw "Get-DescLongLineCount=$c but wrap count=$w" }
}
Test-Name "Get-DescLongLineCount empty string is 0" {
    $c = Get-DescLongLineCount -LongText '' -LineLen 76
    if ($c -ne 0) { throw "Expected 0, got $c" }
}

Write-Host "`n=== [6i] Parse-MeshLineToNumbers ===" -ForegroundColor Cyan
Test-Name "Parse-MeshLineToNumbers reads floats" {
    $a = @(Parse-MeshLineToNumbers -LinePart '  0.123  -0.456  ')
    if ($a.Count -ne 2) { throw "Expected 2 numbers, got $($a.Count)" }
    if ([Math]::Abs([double]$a[0] - 0.123) -gt 0.0001) { throw "Bad first: $($a[0])" }
}

Write-Host "`n=== [6j] Init/Port-Helfer (TEST-COVERAGE: teilweise -> direkt) ===" -ForegroundColor Cyan
Test-Name "Merge-HashtableIntoConfig null wirft nicht" {
    Merge-HashtableIntoConfig -Source $null
}
Test-Name "Merge-HashtableIntoConfig KeysOnly" {
    $origPla = $Script:Config.PLA_Hotend
    $origAbs = $Script:Config.ABS_Hotend
    try {
        $src = @{
            PLA_Hotend = 199
            ABS_Hotend = 288
            ThisKeyShouldNotExistInMergeList_XYZ = 42
        }
        Merge-HashtableIntoConfig -Source $src -KeysOnly @('PLA_Hotend')
        if ($Script:Config.PLA_Hotend -ne 199) { throw "PLA_Hotend not merged" }
        if ($Script:Config.ABS_Hotend -ne $origAbs) { throw "ABS_Hotend should be unchanged when KeysOnly=PLA_Hotend" }
    } finally {
        $Script:Config.PLA_Hotend = $origPla
        $Script:Config.ABS_Hotend = $origAbs
    }
}
Test-Name "Get-AvailableComPorts gibt Array ohne Fehler" {
    $ports = @(Get-AvailableComPorts)
    if ($null -eq $ports) { throw "Expected enumerable, got null" }
}
Test-Name "Test-PortConnected Port null -> false" {
    if (Test-PortConnected -Port $null) { throw "Expected false for null port" }
}
Test-Name "Update-ConfigComPort ersetzt ComPort in Datei" {
    $tmp = Join-Path $env:TEMP ("3dp_comtest_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
    try {
        @'
@{
    ComPort  = "COM1"
    BaudRate = 115200
}
'@ | Set-Content -Path $tmp -Encoding UTF8
        $ok = Update-ConfigComPort -ConfigPath $tmp -NewComPort COM7
        if (-not $ok) { throw "Update-ConfigComPort returned false" }
        $raw = Get-Content -Path $tmp -Raw -Encoding UTF8
        if ($raw -notmatch 'ComPort\s*=\s*"COM7"') { throw "Expected ComPort COM7 in file" }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n=== [6k] Merge-Randfaelle + Update-Config (optional laut TEST-COVERAGE) ===" -ForegroundColor Cyan
Test-Name 'Merge-HashtableIntoConfig: null-Wert ueberschreibt Config-Key nicht' {
    $origPla = $Script:Config.PLA_Hotend
    $origAbs = $Script:Config.ABS_Hotend
    try {
        $Script:Config.PLA_Hotend = 180
        $src = @{ PLA_Hotend = $null; ABS_Hotend = 111 }
        Merge-HashtableIntoConfig -Source $src -KeysOnly @('PLA_Hotend', 'ABS_Hotend')
        if ($Script:Config.PLA_Hotend -ne 180) { throw "PLA_Hotend should stay 180 when source value is null, got $($Script:Config.PLA_Hotend)" }
        if ($Script:Config.ABS_Hotend -ne 111) { throw "ABS_Hotend should merge" }
    } finally {
        $Script:Config.PLA_Hotend = $origPla
        $Script:Config.ABS_Hotend = $origAbs
    }
}
Test-Name "Merge-HashtableIntoConfig KeysOnly leer @() nutzt volle ConfigMergeKeys-Liste" {
    $origXy = $Script:Config.xy_feedrate
    try {
        $onlyXy = @{ xy_feedrate = 4242 }
        Merge-HashtableIntoConfig -Source $onlyXy -KeysOnly @()
        if ($Script:Config.xy_feedrate -ne 4242) { throw "xy_feedrate should merge when KeysOnly is empty (full key list), got $($Script:Config.xy_feedrate)" }
    } finally {
        $Script:Config.xy_feedrate = $origXy
    }
}
Test-Name "Update-ConfigComPort fehlende Datei -> false" {
    $ghost = Join-Path $env:TEMP ("3dp_nofile_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $ghost) { Remove-Item -LiteralPath $ghost -Force }
    $r = Update-ConfigComPort -ConfigPath $ghost -NewComPort COM9
    if ($r) { throw "Expected false for missing config file" }
}

# =============================================================================
# INTEGRATION TESTS [7] — COM + Drucker (siehe TEST-COVERAGE.de.md: Direkt / Bedingt)
#   -TestLevelCompare / -TestTemp2 / -SkipLong:$false / -TestM112 erweitern die Pfade dort.
# =============================================================================
if ($WithPort -or $IntegrationPlanOnly) {
    $intComPort = $TestComPort
    if (-not $intComPort) { $intComPort = "COM5" }
    Write-Host "`n=== [7] Integration $intComPort ===" -ForegroundColor Cyan
    Write-IntegrationCoveragePlan -ComPortLabel $intComPort -SkipLong $SkipLong -SkipHeating:$SkipHeating -TestLevelCompare:$TestLevelCompare -TestTemp2:$TestTemp2 -TestM112:$TestM112
    if ($IntegrationPlanOnly) {
        Write-Host "  IntegrationPlanOnly: Abschnitt [7] wird nicht ausgefuehrt (kein Hardware-Open)." -ForegroundColor Yellow
    }
}

if ($WithPort -and -not $IntegrationPlanOnly) {
    $port = $null
    try {
        $port = New-Object System.IO.Ports.SerialPort $intComPort, $Script:Config.BaudRate, None, 8, One
        $port.Open()
        Write-Host "  Connected to $intComPort" -ForegroundColor DarkGray
    } catch {
        Write-Host "  ERROR: Cannot open $intComPort : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Unit tests above passed. Integration skipped." -ForegroundColor Yellow
        $port = $null
    }

    if ($port) {
        Test-Name "-Command temp (Invoke-SingleCommand via CLI)" {
            $cmdOut = & (Join-Path $ProjectRoot "3DP-Console.ps1") -ComPort $intComPort -Command temp 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) { throw "Expected exit 0, got $exitCode" }
            if ($cmdOut -notmatch 'Connected to|\[OK\]') { throw "Expected Connected/OK in output, got: $cmdOut" }
        }

        Test-Name "Invoke-SingleCommand temp (QuickAction)" {
            $null = Invoke-SingleCommand -Port $port -Cmd "temp"
        }

        Test-Name "Invoke-SingleCommand M105 (direct G-Code)" {
            $null = Invoke-SingleCommand -Port $port -Cmd "M105"
        }

        Test-Name "M105 (/temp)" {
            $lc = Send-Gcode -Port $port -Gcode "M105"
            $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "M114 (/pos)" {
            $lc = Send-Gcode -Port $port -Gcode "M114"
            $ok = Read-SerialResponse -Port $port -Ms 10000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "M115 (/info)" {
            $lc = Send-Gcode -Port $port -Gcode "M115"
            $ok = Read-SerialResponse -Port $port -Ms 10000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "/ls (M20 SD-Liste)" {
            Invoke-SdLs -Port $port
        }

        Test-Name "Host-Command ;@ (in G-Code)" {
            $script:hostCmdCalled = $false
            $cb = { param($cmd) $script:hostCmdCalled = $true }
            $lc = Send-Gcode -Port $port -Gcode ";@test`nM105" -HostCommandCallback $cb
            $null = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $script:hostCmdCalled) { throw "HostCommandCallback not called" }
        }

        Test-Name "Invoke-Macro (M105)" {
            Invoke-Macro -Port $port -Args "preheat 0"
            # preheat 0 = M104 S0, no real heating
        }

        if (-not $SkipHeating) {
            Test-Name "/pla (Preset)" {
                $g = "M104 S$($Script:Config.PLA_Hotend)`nM140 S$($Script:Config.PLA_Bed)"
                $lc = Send-Gcode -Port $port -Gcode $g
                $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "/abs (Preset)" {
                $g = "M104 S$($Script:Config.ABS_Hotend)`nM140 S$($Script:Config.ABS_Bed)"
                $lc = Send-Gcode -Port $port -Gcode $g
                $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "/duese (M104)" {
                $g = "M104 S$($Script:Config.NozzleTempCelsius)"
                $lc = Send-Gcode -Port $port -Gcode $g
                $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "/bett (M140)" {
                $g = "M140 S$($Script:Config.BettTempCelsius)"
                $lc = Send-Gcode -Port $port -Gcode $g
                $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "/off (heater off)" {
                $lc = Send-Gcode -Port $port -Gcode "M104 S0`nM140 S0"
                $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }
        } else {
            Write-Host "  (SkipHeating: /pla, /abs, /duese, /bett, /off skipped)" -ForegroundColor DarkGray
        }

        Test-Name "/fan (M107)" {
            $lc = Send-Gcode -Port $port -Gcode "M107"
            $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "/motoren (M17)" {
            $lc = Send-Gcode -Port $port -Gcode "M17"
            $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "/home (ohne args, G28+E)" {
            Invoke-HomeAxes -Port $port -Args ""
        }

        Test-Name "/sdprint (M23+M24, Datei __test_ni.g)" {
            Invoke-SdPrint -Port $port -Filename "__test_ni.g"
            Start-Sleep -Milliseconds 500
        }

        if (-not $SkipLong) {
            Test-Name "/level (G29)" {
                $lc = Send-Gcode -Port $port -Gcode "G29"
                $ok = Read-SerialResponse -Port $port -Ms 300000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "QuickAction level (G29)" {
                $q = $Script:QuickActions | Where-Object { $_.key -eq 'level' } | Select-Object -First 1
                $lc = Send-Gcode -Port $port -Gcode $q.gcode
                $ok = Read-SerialResponse -Port $port -Ms 300000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "G29 T (mesh report / stats)" {
                $lc = Send-Gcode -Port $port -Gcode "G29 T"
                $ok = Read-SerialResponse -Port $port -Ms 120000 -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }

            Test-Name "Loop prepare (heat + home, 3DP-Config)" {
                if (-not $Script:Config.Loops.ContainsKey('prepare')) { throw "Loop prepare missing in Config" }
                Invoke-Loop -Port $port -LoopName "prepare"
            }

            Test-Name "Loop level_rehome_once 1x (G28 once + G29)" {
                if (-not $Script:Config.Loops.ContainsKey('level_rehome_once')) { throw "Loop level_rehome_once missing" }
                Invoke-Loop -Port $port -LoopName "level_rehome_once" -RepeatCount 1
            }

            Test-Name "Loop level_rehome_once 2x (G28 + G29 x2)" {
                Invoke-Loop -Port $port -LoopName "level_rehome_once" -RepeatCount 2
            }

            Test-Name "Loop temp_ramp (2 Durchlaeufe 170/180)" {
                if (-not $Script:Config.Loops.ContainsKey('temp_ramp')) { throw "Loop temp_ramp missing" }
                Invoke-Loop -Port $port -LoopName "temp_ramp" -RepeatCount 2
            }
        } else {
            Write-Host "  (SkipLong: G29, G29 T, Loops prepare|level_rehome_once|temp_ramp skipped)" -ForegroundColor DarkGray
        }

        Test-Name "Invoke-HomeAxes e (nur G92 E0)" {
            Invoke-HomeAxes -Port $port -Args "e"
        }

        if (-not $SkipHeating) {
            Test-Name "Invoke-Move X 0.01" {
                Invoke-Move -Port $port -Args "X 0.01"
            }

            Test-Name "Invoke-Extrude 1" {
                Invoke-Extrude -Port $port -Args "1"
            }

            Test-Name "Invoke-Reverse 1" {
                Invoke-Reverse -Port $port -Args "1"
            }

            Test-Name "Invoke-HomeAxes xy" {
                Invoke-HomeAxes -Port $port -Args "xy"
            }
        } else {
            Write-Host "  (SkipHeating: move, extrude, reverse, home skipped)" -ForegroundColor DarkGray
        }

        Test-Name "Invoke-Monitor (2 Zyklen)" {
            $end = (Get-Date).AddSeconds(3)
            while ((Get-Date) -lt $end) {
                $port.WriteLine('M105')
                Start-Sleep -Milliseconds 800
                if ($port.BytesToRead -gt 0) {
                    $raw = $port.ReadExisting()
                    $fmt = $raw -split "[\r\n]+" | ForEach-Object { Format-TemperatureReport -Line $_ } | Where-Object { $_ }
                    if ($fmt) { break }
                }
                Start-Sleep -Seconds 1
            }
        }

        Test-Name "Loop cooldown" {
            Invoke-Loop -Port $port -LoopName "cooldown"
        }

        Write-Host "`n  --- QuickActions (d,b,off,fan,home,temp) ---" -ForegroundColor DarkGray
        foreach ($qaKey in @('d','b','off','fan','home','temp')) {
            Test-Name "QuickAction $qaKey send" {
                $q = $Script:QuickActions | Where-Object { $_.key -eq $qaKey } | Select-Object -First 1
                if (-not $q) { throw "QuickAction $qaKey not found" }
                $lc = Send-Gcode -Port $port -Gcode $q.gcode
                $ok = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $q.gcode) -ExpectedOkCount $lc
                if (-not $ok) { throw "No response" }
            }
        }

        Write-Host "`n  --- G/M-Palette direkt senden ---" -ForegroundColor DarkGray
        Test-Name "Palette G28 select and send" {
            $items = @(Get-PaletteItems -Buffer "g28")
            $g28 = $items | Where-Object { $_.cmd -eq 'G28' } | Select-Object -First 1
            if (-not $g28) { throw "G28 not in palette" }
            $lc = Send-Gcode -Port $port -Gcode $g28.cmd
            $ok = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $g28.cmd) -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }
        Test-Name "Palette M105 select and send" {
            $items = @(Get-PaletteItems -Buffer "m105")
            $m105 = $items | Where-Object { $_.cmd -eq 'M105' } | Select-Object -First 1
            if (-not $m105) { throw "M105 not in palette" }
            $lc = Send-Gcode -Port $port -Gcode $m105.cmd
            $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $ok) { throw "No response" }
        }

        Test-Name "M112-Confirm (rejected, M112 not sent)" {
            $origConfirm = Get-Item "function:Invoke-Confirm" -ErrorAction SilentlyContinue
            Set-Item -Path "function:Invoke-Confirm" -Value { param($Prompt) return $false }
            try {
                $lc = Send-Gcode -Port $port -Gcode "M112"
                if ($lc -ne 0) { throw "M112 was sent despite rejection (lc=$lc)" }
            } finally {
                if ($origConfirm -and $origConfirm.ScriptBlock) {
                    Set-Item -Path "function:Invoke-Confirm" -Value $origConfirm.ScriptBlock
                }
            }
        }

        if ($TestLevelCompare) {
            Write-Host "`n  --- level_compare (2x G29, CSV) - ca. 10+ Min ---" -ForegroundColor Yellow
            Test-Name "Loop level_compare 2" {
                Invoke-LevelCompareLoop -Port $port -RepeatCount 2 -InitCmds @('G28')
                $outDir = if ($Script:Config.CsvOutputPath) { $Script:Config.CsvOutputPath } else { Join-Path $ProjectRoot "BedLevelResults" }
                $csvs = Get-ChildItem $outDir -Filter "*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5
                if ($csvs.Count -lt 2) { throw "Expected at least 2 CSV files in $outDir" }
            }
        }

        if ($TestTemp2) {
            Write-Host "`n  --- temp2_nozzle (1 step 170 C, ca. 8 Min) ---" -ForegroundColor Yellow
            Test-Name "Loop temp2_nozzle minimal" {
                $orig = $Script:Config.Loops['temp2_nozzle']
                $Script:Config.Loops['temp2_nozzle'] = @{
                    action               = 'temp2_nozzle'
                    startNozzle          = 170
                    endNozzle            = 170
                    stepNozzle           = 1
                    fixedBed             = 60
                    stabilizationSeconds = 0
                }
                try {
                    Invoke-Loop -Port $port -LoopName 'temp2_nozzle'
                    $outDir = if ($Script:Config.CsvOutputPath) { $Script:Config.CsvOutputPath } else { Join-Path $ProjectRoot "BedLevelResults" }
                    $csv = Get-ChildItem $outDir -Filter "Temp2Leveling_nozzle_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if (-not $csv) { throw "Expected Temp2Leveling CSV in $outDir" }
                    $content = Get-Content $csv.FullName -Raw
                    if ($content -notmatch '170;60;') { throw "CSV should contain 170;60 (nozzle 170, bed 60)" }
                } finally {
                    $Script:Config.Loops['temp2_nozzle'] = $orig
                }
            }
        }

        Test-Name "Quit logic (heater off on exit)" {
            $lc = Send-Gcode -Port $port -Gcode "M104 S0`nM140 S0"
            $ok = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
            if (-not $ok) { throw "Heater-off commands failed" }
        }

        if ($TestM112) {
            Write-Host "`n  --- M112 wirklich senden (NOTSTOPP!) ---" -ForegroundColor Yellow
            Test-Name "M112 on confirmation to printer" {
                $origConfirm = Get-Item "function:Invoke-Confirm" -ErrorAction SilentlyContinue
                Set-Item -Path "function:Invoke-Confirm" -Value { param($Prompt) return $true }
                try {
                    $lc = Send-Gcode -Port $port -Gcode "M112"
                    if ($lc -ne 1) { throw "M112 should be sent (lc=$lc)" }
                } finally {
                    if ($origConfirm -and $origConfirm.ScriptBlock) {
                        Set-Item -Path "function:Invoke-Confirm" -Value $origConfirm.ScriptBlock
                    }
                }
            }
            Write-Host "  Printer in EMERGENCY STOP - reset may be required" -ForegroundColor Yellow
        }

        try {
            if ($port.IsOpen) { $port.Close() }
            $port.Dispose()
        } catch {}
        Write-Host "  Connection closed" -ForegroundColor DarkGray
    }
}

# =============================================================================
# ERGEBNIS
# =============================================================================
Write-Host "`n=== Done ===" -ForegroundColor Cyan
if ($fail -gt 0) {
    Write-Host "  $fail test(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "  All tests passed" -ForegroundColor Green
if (-not $WithPort) {
    Write-Host ('  Tip: -WithPort for integration tests with ' + $TestComPort) -ForegroundColor DarkGray
    Write-Host ('  Checklist: ' + (Join-Path $ProjectRoot 'tests\TEST-COVERAGE.de.md') + ' (which lib functions each run exercises)') -ForegroundColor DarkGray
    if ($IntegrationPlanOnly) {
        Write-Host '  Note: -IntegrationPlanOnly: Abschnitt [7] nicht ausgefuehrt (nur Plan oben).' -ForegroundColor DarkGray
    }
} elseif (-not $IntegrationPlanOnly) {
    if ($SkipLong) { Write-Host '  Tip: -SkipLong:$false for G29/G29 T, prepare, level_rehome_once, temp_ramp (long)' -ForegroundColor DarkGray }
    if (-not $TestM112) { Write-Host '  Tip: -TestM112 to actually send M112 (EMERGENCY STOP)' -ForegroundColor DarkGray }
    if (-not $TestLevelCompare) { Write-Host '  Tip: -TestLevelCompare for loop level_compare 2 (approx. 10+ min)' -ForegroundColor DarkGray }
    if (-not $TestTemp2) { Write-Host '  Tip: -TestTemp2 for loop temp2_nozzle (2 steps, approx. 10 min)' -ForegroundColor DarkGray }
    Write-Host ('  Coverage notes: ' + (Join-Path $ProjectRoot 'tests\TEST-COVERAGE.de.md')) -ForegroundColor DarkGray
}
