<#
    Fragment: 3DP-Console.Mesh.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# 9. SERIAL + PARSING (Gcode timeouts, Temperature, Mesh)
# =============================================================================

function Get-GcodeTimeout {
    param([string]$Gcode)
    $g29 = if ($Script:Config.G28G29TimeoutMs -and $Script:Config.G28G29TimeoutMs -gt 0) { [int]$Script:Config.G28G29TimeoutMs } else { 300000 }
    $heat = if ($Script:Config.HeatingTimeoutMs -and $Script:Config.HeatingTimeoutMs -gt 0) { [int]$Script:Config.HeatingTimeoutMs } else { 600000 }
    $def = if ($Script:Config.DefaultGcodeTimeoutMs -and $Script:Config.DefaultGcodeTimeoutMs -gt 0) { [int]$Script:Config.DefaultGcodeTimeoutMs } else { 15000 }
    if ($Gcode -match 'G28|G29') { return $g29 }
    if ($Gcode -match 'M109|M190') { return $heat }
    return $def
}

function Format-TemperatureReport {
    param([string]$Line)
    if ($Line -notmatch '\b[TB]\d*:[-+]?\d*\.?\d*') { return $null }
    $deg = [char]0x00B0
    $result = @()
    $matches = [regex]::Matches($Line, '([TB]\d*):([-+]?\d*\.?\d*)(?:\s*\/)?([-+]?\d*\.?\d*)')
    $hotendCur = $hotendTgt = $bedCur = $bedTgt = $null
    foreach ($m in $matches) {
        if ($m.Groups[1].Value -match '^T') {
            $hotendCur = $m.Groups[2].Value
            $hotendTgt = $m.Groups[3].Value
        } elseif ($m.Groups[1].Value -match '^B') {
            $bedCur = $m.Groups[2].Value
            $bedTgt = $m.Groups[3].Value
        }
    }
    if ($null -ne $hotendCur) {
        $ht = if ($hotendTgt) { $hotendTgt } else { '0' }
        $result += '  Hotend: ' + $hotendCur + $deg + '/' + $ht + $deg
    }
    if ($null -ne $bedCur) {
        $bt = if ($bedTgt) { $bedTgt } else { '0' }
        $result += '  Bed:    ' + $bedCur + $deg + '/' + $bt + $deg
    }
    return $result
}

# Extrahiert Zahlen aus Zeile (Regex + InvariantCulture TryParse)
# Regex '[+-]?\d+[.,]?\d*': Optionales Vorzeichen, Ziffern, optional Dezimalpunkt/Komma
function Parse-MeshLineToNumbers {
    param([string]$LinePart)
    $numbers = [regex]::Matches($LinePart, '[+-]?\d+[.,]?\d*') | ForEach-Object {
        $v = $_.Value -replace ',', '.'
        if ([double]::TryParse($v, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$null)) { [double]$v }
    }
    return $numbers
}

function Parse-MeshFromG29Output {
    param([string]$Output)
    $mesh = @()
    $lines = $Output -split "[\r\n]+"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        # Format 1: ^\d+\s+([+\-0-9.,\s]+)$ – Zeilennummer + Leerzeichen + Zahlen (G29 Bilinear)
        if ($trimmed -match '^\d+\s+([+\-0-9.,\s]+)$') {
            $numPart = $Matches[1]
            $numPartHasDecimalOrSign = $numPart -match '[+\-]' -or $numPart -match '\.\d'
            $numbers = Parse-MeshLineToNumbers -LinePart $numPart
            if ($numbers.Count -gt 0 -and $numPartHasDecimalOrSign) { $mesh += ,@($numbers) }
        }
        # Format 2: ^([+\-0-9.,\s;]+)$ – Nur erlaubte Zeichen (M420 T1 CSV)
        else {
            $hasValidChars = $trimmed -match '^([+\-0-9.,\s;]+)$' -and $trimmed -match '\d'
            $hasDecimalOrSign = $trimmed -match '[+\-]' -or $trimmed -match '\.\d'
            $notOnlyDigits = $trimmed -notmatch '^[\d\s]+$'
            if ($hasValidChars -and $notOnlyDigits -and $hasDecimalOrSign) {
                $numbers = Parse-MeshLineToNumbers -LinePart $trimmed
                if ($numbers.Count -ge 2) { $mesh += ,@($numbers) }
            }
        }
    }
    return $mesh
}

function Get-MeshCellColor {
    param(
        [double]$Value,
        [double]$PrevValue = [double]::NaN,
        [double]$ThresholdGreen,
        [double]$ThresholdYellow
    )
    if (-not $PSBoundParameters.ContainsKey('ThresholdGreen')) { $ThresholdGreen = if ($null -ne $Script:Config.MeshThresholdGreenMm) { [double]$Script:Config.MeshThresholdGreenMm } else { 0.05 } }
    if (-not $PSBoundParameters.ContainsKey('ThresholdYellow')) { $ThresholdYellow = if ($null -ne $Script:Config.MeshThresholdYellowMm) { [double]$Script:Config.MeshThresholdYellowMm } else { 0.15 } }
    $absVal = [Math]::Abs($Value)
    $color = if ($absVal -le $ThresholdGreen) { 'Green' }
             elseif ($absVal -le $ThresholdYellow) { 'Yellow' }
             else { 'Red' }
    $isImprovement = $null
    if ($PSBoundParameters.ContainsKey('PrevValue') -and -not [double]::IsNaN($PrevValue)) {
        $isImprovement = $absVal -lt [Math]::Abs($PrevValue)
        if ($isImprovement) { $color = 'Green' }
    }
    return @{ color = $color; isImprovement = $isImprovement }
}

function Get-DeltaImprovement {
    param([double]$NewValue, [double]$OldValue)
    return [Math]::Abs($NewValue) -lt [Math]::Abs($OldValue)
}

function Get-MeshCellDisplayInfo {
    param(
        [double]$val,
        [double]$prevVal,
        [double]$ThresholdGreen,
        [double]$ThresholdYellow
    )
    if (-not $PSBoundParameters.ContainsKey('ThresholdGreen')) { $ThresholdGreen = if ($null -ne $Script:Config.MeshThresholdGreenMm) { [double]$Script:Config.MeshThresholdGreenMm } else { 0.05 } }
    if (-not $PSBoundParameters.ContainsKey('ThresholdYellow')) { $ThresholdYellow = if ($null -ne $Script:Config.MeshThresholdYellowMm) { [double]$Script:Config.MeshThresholdYellowMm } else { 0.15 } }
    $colorArgs = @{ Value = $val; ThresholdGreen = $ThresholdGreen; ThresholdYellow = $ThresholdYellow }
    if (-not [double]::IsNaN($prevVal)) { $colorArgs.PrevValue = $prevVal }
    $info = Get-MeshCellColor @colorArgs
    $fmt = if ($val -ge 0) { '+{0:F3}' } else { '{0:F3}' }
    $cellText = $fmt -f $val
    if ($null -ne $info.isImprovement) {
        $cellText += if ($info.isImprovement) { [char]0x2193 } else { [char]0x2191 }
        $color = if ($info.isImprovement) { 'Green' } else { 'Red' }
    } else {
        $color = $info.color
    }
    # Interaktives Bed Level: im Band ±0,100 mm neutral (weiß), kein Grün/Rot durch Schwellen oder Pfeile
    if ([Math]::Abs($val) -le 0.100) { $color = 'White' }
    return @{ cellText = $cellText; color = $color }
}

function Format-MeshWithColors {
    param(
        [array]$Mesh,
        [array]$PrevMesh = $null,
        [double]$ThresholdGreen,
        [double]$ThresholdYellow
    )
    if (-not $PSBoundParameters.ContainsKey('ThresholdGreen')) { $ThresholdGreen = if ($null -ne $Script:Config.MeshThresholdGreenMm) { [double]$Script:Config.MeshThresholdGreenMm } else { 0.05 } }
    if (-not $PSBoundParameters.ContainsKey('ThresholdYellow')) { $ThresholdYellow = if ($null -ne $Script:Config.MeshThresholdYellowMm) { [double]$Script:Config.MeshThresholdYellowMm } else { 0.15 } }
    if (-not $Mesh -or $Mesh.Count -eq 0) { return }
    $colCount = $Mesh[0].Count
    # Header: gleiche Breite wie Zeilenindex ({0,4}), sonst sitzen Spaltenköpfe versetzt
    Write-Host -NoNewline ('{0,4}' -f '') -ForegroundColor Gray
    for ($c = 0; $c -lt $colCount; $c++) { Write-Host -NoNewline ('{0,8}' -f $c) -ForegroundColor Gray }
    Write-Host ''
    for ($r = 0; $r -lt $Mesh.Count; $r++) {
        Write-Host -NoNewline ('{0,4}' -f $r) -ForegroundColor Gray
        for ($c = 0; $c -lt $colCount; $c++) {
            $val = $Mesh[$r][$c]
            $prevVal = [double]::NaN
            if ($PrevMesh -and $PrevMesh.Count -gt $r -and $PrevMesh[$r].Count -gt $c) {
                $prevVal = $PrevMesh[$r][$c]
            }
            $display = Get-MeshCellDisplayInfo -val $val -prevVal $prevVal -ThresholdGreen $ThresholdGreen -ThresholdYellow $ThresholdYellow
            Write-Host -NoNewline ('{0,8}' -f $display.cellText) -ForegroundColor $display.color
        }
        Write-Host ''
    }
}
