<#
    Fragment: 3DP-Console.Loops.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# =============================================================================
# 10. LOOPS (Level-Compare, allgemeine Loops)
# =============================================================================

# Pester: $global:3DPConsoleConsolePollApi = @{ KeyAvailable = { $false }; ReadKey = { $null } }
if (-not $global:3DPConsoleConsolePollApi) {
    $global:3DPConsoleConsolePollApi = @{
        KeyAvailable = { [Console]::KeyAvailable }
        ReadKey      = { [Console]::ReadKey($true) }
    }
}
if (-not $global:3DPConsoleConsoleSleepMsForMenu) {
    $global:3DPConsoleConsoleSleepMsForMenu = { param($ms) Start-Sleep -Milliseconds $ms }
}

# Kernlogik testbar (Pester uebergibt ScriptBlocks statt [Console]::…).
function Read-3DPConsoleEscapePollCore {
    param([scriptblock]$KeyAvailable, [scriptblock]$ReadKey)
    try {
        if (-not (& $KeyAvailable)) { return $null }
        $k = $null
        try { $k = & $ReadKey } catch { }
        if ($k -and $k.Key -eq [System.ConsoleKey]::Escape) { return 'Escape' }
    } catch { }
    return $null
}

# Pester: $global:3DPConsoleEscapePollTestDelegate = { 'Escape' }
function Read-3DPConsoleEscapePoll {
    $td = $global:3DPConsoleEscapePollTestDelegate
    if ($env:THREEDP_CONSOLE_SKIP_MAIN -eq '1') {
        if ($td) { return & $td }
        return $null
    }
    $api = $global:3DPConsoleConsolePollApi
    return Read-3DPConsoleEscapePollCore -KeyAvailable $api.KeyAvailable -ReadKey $api.ReadKey
}

# Oberste Interactive-Schleife: auch bei SKIP_MAIN=1 Konsolen-Check wie zuvor.
# Pester: $global:3DPConsoleInteractiveTopEscapePollTestDelegate
function Read-3DPConsoleEscapePollInteractiveTop {
    $td = $global:3DPConsoleInteractiveTopEscapePollTestDelegate
    if ($td) { return & $td }
    $api = $global:3DPConsoleConsolePollApi
    return Read-3DPConsoleEscapePollCore -KeyAvailable $api.KeyAvailable -ReadKey $api.ReadKey
}

function Read-3DPConsoleBedLevelMenuKeyCore {
    param([scriptblock]$SleepMs, [scriptblock]$KeyAvailable, [scriptblock]$ReadKey)
    & $SleepMs 150
    try {
        if (-not (& $KeyAvailable)) { return 'Continue' }
        $k = $null
        try { $k = & $ReadKey } catch { }
        if (-not $k) { return 'Continue' }
        if ($k.Key -eq [System.ConsoleKey]::Escape) { return 'Escape' }
        if ($k.Key -eq [System.ConsoleKey]::Enter) { return 'Enter' }
    } catch { }
    return 'Continue'
}

# Pester: $global:3DPConsoleBedLevelMenuKeyTestDelegate
function Read-3DPConsoleBedLevelMenuKey {
    $td = $global:3DPConsoleBedLevelMenuKeyTestDelegate
    if ($env:THREEDP_CONSOLE_SKIP_MAIN -eq '1') {
        if ($td) { return & $td }
        return $null
    }
    $api = $global:3DPConsoleConsolePollApi
    $sleep = $global:3DPConsoleConsoleSleepMsForMenu
    return Read-3DPConsoleBedLevelMenuKeyCore -SleepMs $sleep -KeyAvailable $api.KeyAvailable -ReadKey $api.ReadKey
}

function Wait-3DPConsoleInteractiveBedLevelMenu {
    do {
        $mk = Read-3DPConsoleBedLevelMenuKey
        if ($mk -eq 'Escape') { Write-Host '  [Beendet]' -ForegroundColor Yellow; return }
        if ($mk -eq 'Enter') { break }
    } while ($true)
}

function Test-3DPConsoleEscapePollShowsAbortDuringWait {
    try {
        if ((Read-3DPConsoleEscapePoll) -eq 'Escape') {
            Write-Host '  [Beendet]' -ForegroundColor Yellow
            return $true
        }
    } catch { }
    return $false
}

function Invoke-LevelCompareLoop {
    param([System.IO.Ports.SerialPort]$Port, [int]$RepeatCount, [array]$InitCmds, [bool]$UseG29T = $false)
    $outputDir = $Script:Config.CsvOutputPath
    if (-not $outputDir) { $outputDir = Join-Path $Script:BasePath "BedLevelResults" }
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $prefix = if ($Script:Config.CsvFilePrefix) { $Script:Config.CsvFilePrefix } else { "BedLevel_Messung" }
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"

    foreach ($ic in $InitCmds) {
        $ic = $ic.Trim(); if (-not $ic) { continue }
        try {
            if ((Read-3DPConsoleEscapePoll) -eq 'Escape') { Write-Host '  [Abgebrochen]' -ForegroundColor Yellow; return }
        } catch { }
        $lineCount = Send-Gcode -Port $Port -Gcode $ic
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $ic) -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Loop stopped]' -ForegroundColor Red; return }
    }

    $alleMeshes = @()
    for ($i = 1; $i -le $RepeatCount; $i++) {
        Write-Host ('  --- G29 round ' + $i + '/' + $RepeatCount + ' ---') -ForegroundColor DarkCyan
        try {
            if ((Read-3DPConsoleEscapePoll) -eq 'Escape') { Write-Host '  [Abgebrochen]' -ForegroundColor Yellow; return }
        } catch { }

        $lineCount = Send-Gcode -Port $Port -Gcode "G29"
        $g29Out = Read-SerialAndCapture -Port $Port -Ms 300000 -ExpectedOkCount $lineCount -AllowAbort
        if ($null -eq $g29Out) { Write-Host '  [Cancelled or error]' -ForegroundColor Red; return }

        $fullOut = $g29Out
        if ($UseG29T) {
            $lineCount = Send-Gcode -Port $Port -Gcode "G29 T"
            $g29tOut = Read-SerialAndCapture -Port $Port -Ms 15000 -ExpectedOkCount $lineCount -AllowAbort
            if ($g29tOut) { $fullOut = $fullOut + "`n" + $g29tOut }
        }

        $mesh = Parse-MeshFromG29Output $fullOut
        if ($mesh.Count -eq 0) {
            $lineCount = Send-Gcode -Port $Port -Gcode "M420 V1 T1"
            $m420Out = Read-SerialAndCapture -Port $Port -Ms 10000 -ExpectedOkCount $lineCount -AllowAbort
            if ($m420Out) { $fullOut = $fullOut + "`n" + $m420Out; $mesh = Parse-MeshFromG29Output $fullOut }
        }
        if ($mesh.Count -eq 0) {
            Write-Host '  WARNING: No mesh data found.' -ForegroundColor Yellow
            $rawFile = Join-Path $outputDir "${timestamp}_Runde${i}_raw.txt"
            $fullOut | Out-File $rawFile -Encoding UTF8
        } else {
            $alleMeshes += ,$mesh
            $csvFile = Join-Path $outputDir "${prefix}_${timestamp}_Runde${i}.csv"
            $header = "Zeile;" + (0..($mesh[0].Count - 1) | ForEach-Object { "Spalte$_" }) -join ";"
            $inv = [cultureinfo]::InvariantCulture
            $rows = @($header)
            for ($r = 0; $r -lt $mesh.Count; $r++) {
                $rowStr = ($mesh[$r] | ForEach-Object { $_.ToString($inv) }) -join ";"
                $rows += "R$r;$rowStr"
            }
            $rows | Out-File $csvFile -Encoding UTF8
            Write-Host ('  CSV: ' + $csvFile) -ForegroundColor Green
        }

        if ($i -lt $RepeatCount) { Start-Sleep -Seconds 3 }
    }

    if ($alleMeshes.Count -lt 2) {
        Write-Host '  At least 2 rounds needed for comparison.' -ForegroundColor Yellow
        Write-Host '  [Loop done]' -ForegroundColor Green
        return
    }

    $rows = $alleMeshes[0].Count
    $cols = $alleMeshes[0][0].Count

    Write-Host ''
    Write-Host '  === Round comparison (Delta: First measurement to each round) ===' -ForegroundColor Cyan
    $inv = [cultureinfo]::InvariantCulture
    $deltaRows = @("Comparison;MaxDelta_mm;Details")
    $baseline = $alleMeshes[0]
    for ($m = 1; $m -lt $alleMeshes.Count; $m++) {
        $curr = $alleMeshes[$m]
        $prev = $baseline
        $maxDiff = 0
        $dets = @()
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                $d = [Math]::Abs($curr[$r][$c] - $prev[$r][$c])
                if ($d -gt $maxDiff) { $maxDiff = $d }
                $dets += "[$r,$c] Delta=$([Math]::Round($curr[$r][$c] - $prev[$r][$c], 4).ToString($inv))"
            }
        }
        $label = "Runde1_zu_$($m+1)"
        $deltaRows += "$label;$([Math]::Round($maxDiff, 5).ToString($inv));$($dets -join ' | ')"
        $color = if ($maxDiff -gt 0.1) { 'Yellow' } elseif ($maxDiff -gt 0.05) { 'DarkYellow' } else { 'Green' }
        Write-Host ("  Round 1 " + [char]0x2192 + " Round $($m+1) : max. Delta = " + [Math]::Round($maxDiff, 3) + " mm") -ForegroundColor $color
    }
    $deltaCsv = Join-Path $outputDir "Comparison_Rounds_${timestamp}.csv"
    $deltaRows | Out-File $deltaCsv -Encoding UTF8
    Write-Host ('  CSV: ' + $deltaCsv) -ForegroundColor Gray

    $statRows = @("Zeile;Spalte;Min_mm;Max_mm;Durchschnitt_mm")
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $vals = $alleMeshes | ForEach-Object { $_[$r][$c] }
            $min = ($vals | Measure-Object -Minimum).Minimum
            $max = ($vals | Measure-Object -Maximum).Maximum
            $avg = ($vals | Measure-Object -Average).Average
            $statRows += "R$r;C$c;$([Math]::Round($min, 5).ToString($inv));$([Math]::Round($max, 5).ToString($inv));$([Math]::Round($avg, 5).ToString($inv))"
        }
    }
    $statCsv = Join-Path $outputDir "Statistik_Messpunkte_${timestamp}.csv"
    $statRows | Out-File $statCsv -Encoding UTF8
    Write-Host ''
    Write-Host '  === Pro Messpunkt: Min / Max / Durchschnitt ===' -ForegroundColor Cyan
    Write-Host ('  CSV: ' + $statCsv) -ForegroundColor Gray
    $spread = $null
    if ($statRows.Count -gt 1) {
        $spread = $statRows[1..($statRows.Count-1)] | ForEach-Object {
            $p = $_ -split ';'
            if ($p.Count -ge 4) { [double]$p[3] - [double]$p[2] }
        } | Measure-Object -Maximum -ErrorAction SilentlyContinue
    }
    if ($spread -and $null -ne $spread.Maximum -and $spread.Maximum -gt 0) {
        Write-Host ("  Largest spread per point: " + [Math]::Round($spread.Maximum, 3) + " mm") -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [Loop done]' -ForegroundColor Green
}

function Invoke-Temp2LevelingLoop {
    param(
        [System.IO.Ports.SerialPort]$Port,
        [string]$Mode,  # 'nozzle' | 'bed' | 'combined'
        [int]$StartNozzle,
        [int]$EndNozzle,
        [int]$StepNozzle,
        [int]$StartBed,
        [int]$EndBed,
        [int]$StepBed,
        [int]$StabilizationSeconds,
        [int]$FixedNozzle,  # Used when mode=bed
        [int]$FixedBed      # Used when mode=nozzle
    )
    $outputDir = $Script:Config.CsvOutputPath
    if (-not $outputDir) { $outputDir = Join-Path $Script:BasePath "BedLevelResults" }
    $outputDir = ($outputDir -replace '\$PSScriptRoot', $Script:BasePath).Trim()
    if (-not $outputDir -or -not [System.IO.Path]::IsPathRooted($outputDir)) {
        $outputDir = Join-Path $Script:BasePath "BedLevelResults"
    }
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $csvName = "Temp2Leveling_${Mode}_${timestamp}.csv"
    $csvPath = Join-Path $outputDir $csvName

    # Build step list: array of @{nozzle=N; bed=B}
    $steps = @()
    $stepN = [Math]::Max(1, $StepNozzle)
    $stepB = [Math]::Max(1, $StepBed)
    if ($Mode -eq 'nozzle') {
        for ($t = $StartNozzle; $t -le $EndNozzle; $t += $stepN) {
            $steps += @{nozzle = $t; bed = $FixedBed}
        }
    } elseif ($Mode -eq 'bed') {
        for ($t = $StartBed; $t -le $EndBed; $t += $stepB) {
            $steps += @{nozzle = $FixedNozzle; bed = $t}
        }
    } else {
        $nSteps = [Math]::Max(1, [Math]::Floor(($EndNozzle - $StartNozzle) / $stepN) + 1)
        $bSteps = [Math]::Max(1, [Math]::Floor(($EndBed - $StartBed) / $stepB) + 1)
        $cnt = [Math]::Min($nSteps, $bSteps)
        for ($i = 0; $i -lt $cnt; $i++) {
            $n = [Math]::Min($EndNozzle, $StartNozzle + ($i * $stepN))
            $b = [Math]::Min($EndBed, $StartBed + ($i * $stepB))
            $steps += @{nozzle = $n; bed = $b}
        }
    }
    if ($steps.Count -eq 0) {
        Write-Host '  No temperature steps to run.' -ForegroundColor Yellow
        return
    }

    Write-Host ('  Temp2 Leveling (' + $Mode + '): ' + $steps.Count + ' steps. Esc=Cancel') -ForegroundColor Cyan
    Write-Host ''

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $allRows = @()
    $meshCols = $null

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $s = $steps[$i]
        $noz = $s.nozzle
        $bed = $s.bed
        try {
            if ((Read-3DPConsoleEscapePoll) -eq 'Escape') { Write-Host '  [Cancelled]' -ForegroundColor Yellow; break }
        } catch { }

        Write-Host ('  --- Step ' + ($i + 1) + '/' + $steps.Count + ': Nozzle ' + $noz + ' C, Bed ' + $bed + ' C ---') -ForegroundColor DarkCyan

        $lineCount = Send-Gcode -Port $Port -Gcode "M104 S$noz"
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'M104') -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Stopped]' -ForegroundColor Red; break }
        $lineCount = Send-Gcode -Port $Port -Gcode "M140 S$bed"
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'M140') -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Stopped]' -ForegroundColor Red; break }

        $lineCount = Send-Gcode -Port $Port -Gcode "M109 S$noz"
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'M109') -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Stopped]' -ForegroundColor Red; break }
        $lineCount = Send-Gcode -Port $Port -Gcode "M190 S$bed"
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'M190') -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Stopped]' -ForegroundColor Red; break }

        if ($StabilizationSeconds -gt 0) {
            Write-Host ('  Stabilizing ' + $StabilizationSeconds + ' s...') -ForegroundColor DarkGray
            for ($w = 0; $w -lt $StabilizationSeconds; $w += 5) {
                $remain = [Math]::Min(5, $StabilizationSeconds - $w)
                Start-Sleep -Seconds $remain
                try {
                    if ((Read-3DPConsoleEscapePoll) -eq 'Escape') { Write-Host '  [Cancelled]' -ForegroundColor Yellow; return }
                } catch { }
            }
        }

        $lineCount = Send-Gcode -Port $Port -Gcode "G28"
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'G28') -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Stopped]' -ForegroundColor Red; break }

        $lineCount = Send-Gcode -Port $Port -Gcode "G29"
        $g29Out = Read-SerialAndCapture -Port $Port -Ms 300000 -ExpectedOkCount $lineCount -AllowAbort -Silent:$false
        if ($null -eq $g29Out) { Write-Host '  [Cancelled or error]' -ForegroundColor Red; break }

        $mesh = Parse-MeshFromG29Output $g29Out
        if ($mesh.Count -eq 0) {
            $lineCount = Send-Gcode -Port $Port -Gcode "M420 V1 T1"
            $m420Out = Read-SerialAndCapture -Port $Port -Ms 10000 -ExpectedOkCount $lineCount -AllowAbort -Silent
            if ($m420Out) { $mesh = Parse-MeshFromG29Output ($g29Out + "`n" + $m420Out) }
        }
        if ($mesh.Count -eq 0) {
            Write-Host '  WARNING: No mesh data.' -ForegroundColor Yellow
            continue
        }

        if ($null -eq $meshCols) {
            $meshCols = @()
            for ($r = 0; $r -lt $mesh.Count; $r++) {
                for ($c = 0; $c -lt $mesh[$r].Count; $c++) {
                    $meshCols += "R${r}C$c"
                }
            }
        }
        $flat = @($noz.ToString($inv), $bed.ToString($inv))
        for ($r = 0; $r -lt $mesh.Count; $r++) {
            for ($c = 0; $c -lt $mesh[$r].Count; $c++) {
                $flat += $mesh[$r][$c].ToString($inv)
            }
        }
        $allRows += ($flat -join ';')
    }

    if ($allRows.Count -gt 0 -and $meshCols) {
        $header = "NozzleTemp;BedTemp;" + ($meshCols -join ';')
        @($header) + $allRows | Out-File $csvPath -Encoding UTF8
        Write-Host ''
        Write-Host ('  CSV: ' + $csvPath) -ForegroundColor Green
    } else {
        Write-Host '  No data collected.' -ForegroundColor Yellow
    }
    Write-Host '  [Loop done]' -ForegroundColor Green
}

function Invoke-InteractiveBedLevelLoop {
    param(
        [System.IO.Ports.SerialPort]$Port,
        [int]$BedTemp = 60,
        [int]$NozzleTemp = 170,
        [int]$StabilizationSeconds = 0
    )
    $prevMesh = $null
    while ($true) {
        try {
            if ((Read-3DPConsoleEscapePollInteractiveTop) -eq 'Escape') { Write-Host '  [Beendet]' -ForegroundColor Yellow; return }
        } catch { }

        # --- Heizen ---
        if (-not (Invoke-GcodeAndWaitOrAbort -Port $Port -Gcode "M104 S$NozzleTemp")) { return }
        if (-not (Invoke-GcodeAndWaitOrAbort -Port $Port -Gcode "M140 S$BedTemp")) { return }
        if (-not (Invoke-GcodeAndWaitOrAbort -Port $Port -Gcode "M109 S$NozzleTemp")) { return }
        if (-not (Invoke-GcodeAndWaitOrAbort -Port $Port -Gcode "M190 S$BedTemp")) { return }

        if ($StabilizationSeconds -gt 0) {
            Write-Host ('  Stabilisierung ' + $StabilizationSeconds + ' s...') -ForegroundColor DarkGray
            for ($w = 0; $w -lt $StabilizationSeconds; $w += 5) {
                $remain = [Math]::Min(5, $StabilizationSeconds - $w)
                Start-Sleep -Seconds $remain
                if (Test-3DPConsoleEscapePollShowsAbortDuringWait) { return }
            }
        }

        # --- G28 Referenz ---
        if (-not (Invoke-GcodeAndWaitOrAbort -Port $Port -Gcode "G28")) { return }

        # --- G29 Messung ---
        $lineCount = Send-Gcode -Port $Port -Gcode "G29"
        $g29Out = Read-SerialAndCapture -Port $Port -Ms 300000 -ExpectedOkCount $lineCount -AllowAbort
        if ($null -eq $g29Out) { Write-Host '  [Abgebrochen oder Fehler]' -ForegroundColor Red; return }

        $mesh = Parse-MeshFromG29Output $g29Out
        if ($mesh.Count -eq 0) {
            $lineCount = Send-Gcode -Port $Port -Gcode "M420 V1 T1"
            $m420Out = Read-SerialAndCapture -Port $Port -Ms 10000 -ExpectedOkCount $lineCount -AllowAbort -Silent
            if ($m420Out) { $mesh = Parse-MeshFromG29Output ($g29Out + "`n" + $m420Out) }
        }
        # --- Mesh anzeigen ---
        if ($mesh.Count -gt 0) {
            Write-Host ''
            Format-MeshWithColors -Mesh $mesh -PrevMesh $prevMesh
            $prevMesh = $mesh
        } else {
            Write-Host '  WARNING: Kein Mesh gefunden.' -ForegroundColor Yellow
        }

        # --- Eingabe (Enter/Esc) ---
        Write-Host ''
        Write-Host '  [Enter] neue Messung, [Esc] beenden' -ForegroundColor Gray
        # Headless/Pester: sonst Endlosschleife ohne Tastatur
        if ($env:THREEDP_CONSOLE_SKIP_MAIN -eq '1') {
            return
        }
        Wait-3DPConsoleInteractiveBedLevelMenu
    }
}

function Invoke-Loop {
    param([System.IO.Ports.SerialPort]$Port, [string]$LoopName, [int]$RepeatCount = 0)
    $loops = $Script:Config.Loops
    if (-not $loops -or -not ($loops -is [hashtable])) {
        $loopsPath = Get-3DPConsoleOptionalFile 'PrusaMini-Loops.ps1'
        if (-not $loopsPath) {
            Write-Host ('  Loop config not found (neither in Config nor PrusaMini-Loops.ps1 next to console / repo root).') -ForegroundColor Red
            return
        }
        try { $loops = . $loopsPath } catch {
            Write-Host ('  Error loading Loops: ' + $_.Exception.Message) -ForegroundColor Red
            return
        }
    }
    $entry = $loops[$LoopName]
    if ($entry -is [hashtable] -and $entry.action -eq 'level_compare') {
        $rc = if ($RepeatCount -gt 0) { $RepeatCount } elseif ($null -ne $entry.repeat) { [Math]::Max(1, [int]$entry.repeat) } else { 3 }
        $init = if ($entry.init) { @($entry.init) } else { @('G28') }
        $useG29T = if ($null -ne $entry.useG29T) { [bool]$entry.useG29T } else { $false }
        Write-Host ('  Loop "' + $LoopName + '" (' + $rc + 'x G29, CSV + round comparison + Min/Max/Avg). Esc=Cancel') -ForegroundColor Cyan
        Write-Host ''
        Invoke-LevelCompareLoop -Port $Port -RepeatCount $rc -InitCmds $init -UseG29T $useG29T
        return
    }
    if ($entry -is [hashtable] -and ($entry.action -eq 'temp2_nozzle' -or $entry.action -eq 'temp2_bed' -or $entry.action -eq 'temp2_combined')) {
        $mode = $entry.action -replace 'temp2_', ''
        $sn = if ($null -ne $entry.startNozzle) { [int]$entry.startNozzle } else { 170 }
        $en = if ($null -ne $entry.endNozzle) { [int]$entry.endNozzle } else { 220 }
        $stn = if ($null -ne $entry.stepNozzle) { [int]$entry.stepNozzle } else { 5 }
        $sb = if ($null -ne $entry.startBed) { [int]$entry.startBed } else { 60 }
        $eb = if ($null -ne $entry.endBed) { [int]$entry.endBed } else { 100 }
        $stb = if ($null -ne $entry.stepBed) { [int]$entry.stepBed } else { 5 }
        $stab = if ($null -ne $entry.stabilizationSeconds) { [int]$entry.stabilizationSeconds } else { 60 }
        $fn = if ($null -ne $entry.fixedNozzle) { [int]$entry.fixedNozzle } else { 170 }
        $fb = if ($null -ne $entry.fixedBed) { [int]$entry.fixedBed } else { 60 }
        Invoke-Temp2LevelingLoop -Port $Port -Mode $mode -StartNozzle $sn -EndNozzle $en -StepNozzle $stn -StartBed $sb -EndBed $eb -StepBed $stb -StabilizationSeconds $stab -FixedNozzle $fn -FixedBed $fb
        return
    }
    if ($entry -is [hashtable] -and $entry.action -eq 'interactive_bedlevel') {
        $bt = if ($null -ne $entry.bedTemp) { [int]$entry.bedTemp } else { 60 }
        $nt = if ($null -ne $entry.nozzleTemp) { [int]$entry.nozzleTemp } else { 170 }
        $stab = if ($null -ne $entry.stabilizationSeconds) { [int]$entry.stabilizationSeconds } else { 0 }
        Write-Host '  Interactive Bed Leveling. Esc=Exit, Enter=Remeasure' -ForegroundColor Cyan
        Write-Host ''
        Invoke-InteractiveBedLevelLoop -Port $Port -BedTemp $bt -NozzleTemp $nt -StabilizationSeconds $stab
        return
    }
    $cmds = if ($entry -is [hashtable] -and $entry.cmds) { $entry.cmds } elseif ($entry -is [array]) { $entry } else { $null }
    # String ist IEnumerable -> wuerde zeichenweise iterieren; als ein Befehl behandeln.
    if ($cmds -is [string]) { $cmds = , $cmds }
    elseif ($null -ne $cmds) { $cmds = @($cmds) }
    if (-not $cmds -or $cmds.Count -eq 0) {
        $avail = ($loops.Keys | Sort-Object) -join ', '
        Write-Host ('  Loop "' + $LoopName + '" unknown. Available: ' + $avail) -ForegroundColor Yellow
        return
    }
    if ($RepeatCount -le 0 -and $entry -is [hashtable] -and $null -ne $entry.repeat) {
        $RepeatCount = [Math]::Max(1, [int]$entry.repeat)
    }
    if ($RepeatCount -le 0) { $RepeatCount = 1 }
    $initCmds = if ($entry -is [hashtable] -and $null -ne $entry.init) {
        if ($entry.init -is [string]) { , $entry.init } else { @($entry.init) }
    } else { @() }
    $startTemp = if ($entry -is [hashtable] -and $null -ne $entry.startTemp) { [int]$entry.startTemp } else { $null }
    $stepTemp  = if ($entry -is [hashtable] -and $null -ne $entry.stepTemp)  { [int]$entry.stepTemp }  else { $null }
    $iterInfo = if ($RepeatCount -gt 1) { " $RepeatCount`x" } else { "" }
    Write-Host ('  Loop "' + $LoopName + '" (' + $cmds.Count + ' commands' + $iterInfo + '). Esc=Cancel') -ForegroundColor Cyan
    Write-Host ''
    foreach ($ic in $initCmds) {
        $ic = $ic.Trim(); if (-not $ic) { continue }
        try {
            if ((Read-3DPConsoleEscapePoll) -eq 'Escape') { Write-Host '  [Loop cancelled]' -ForegroundColor Yellow; return }
        } catch { }
        $lineCount = Send-Gcode -Port $Port -Gcode $ic
        $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $ic) -ExpectedOkCount $lineCount -AllowAbort
        if (-not $ok) { Write-Host '  [Loop stopped]' -ForegroundColor Red; return }
    }
    for ($iter = 1; $iter -le $RepeatCount; $iter++) {
        $i0 = $iter - 1
        $T = if ($null -ne $startTemp -and $null -ne $stepTemp) { $startTemp + ($i0 * $stepTemp) } else { $null }
        if ($RepeatCount -gt 1) { Write-Host ('  --- Pass ' + $iter + '/' + $RepeatCount + ' ---') -ForegroundColor DarkCyan }
        for ($j = 0; $j -lt $cmds.Count; $j++) {
            try {
                if ((Read-3DPConsoleEscapePoll) -eq 'Escape') {
                    Write-Host '  [Loop cancelled]' -ForegroundColor Yellow
                    return
                }
            } catch { }
            $cmd = $cmds[$j].Trim()
            if (-not $cmd) { continue }
            $cmd = $cmd -replace '\{i0\}', [string]$i0 -replace '\{i\}', [string]$iter
            if ($null -ne $T) { $cmd = $cmd -replace '\{T\}', [string]$T }
            $lineCount = Send-Gcode -Port $Port -Gcode $cmd
            $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $cmd) -ExpectedOkCount $lineCount -AllowAbort
            if (-not $ok) {
                Write-Host '  [Loop stopped]' -ForegroundColor Red
                return
            }
        }
    }
    Write-Host ''
    Write-Host '  [Loop done]' -ForegroundColor Green
}

