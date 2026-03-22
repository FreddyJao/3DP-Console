<#
    Fragment: 3DP-Console.Commands.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# =============================================================================
# 3. UI HELPERS (Placeholders, Confirmation, Slash-Args)
# =============================================================================

# Replaces placeholders in UI strings ({ComPort}, {NozzleTemp}, {BedTemp}, {DueseLabel})
function Get-UIString {
    param([string]$Key)
    $t = $Script:Config[$Key]
    if (-not $t) { return '' }
    $t -replace '\{ComPort\}', $Script:Config.ComPort `
       -replace '\{NozzleTemp\}', [string]$Script:Config.NozzleTempCelsius `
       -replace '\{BedTemp\}', [string]$Script:Config.BettTempCelsius `
       -replace '\{DueseLabel\}', $Script:DueseLabel
}

function Invoke-Confirm {
    param([string]$Prompt = 'Continue? y/n')
    $r = Read-Host $Prompt
    return ($r.Trim().ToLower() -eq 'y' -or $r.Trim().ToLower() -eq 'j')
}

# Extracts arguments from slash commands (e.g. "/move X 10" -> @("x","10"))
function Get-SlashCommandArgs {
    param([string]$Cmd, [string]$Prefix)
    $rest = $Cmd.Trim().ToLower().Replace($Prefix.ToLower(), '').Trim()
    return ($rest -split '\s+') | Where-Object { $_ }
}

# =============================================================================
# 4. SLASH-COMMAND-HANDLER (Home, Move, Extrude, Monitor, SD, Macro, ...)
# =============================================================================

# Reine G-Code-Logik (von Pester direkt aufrufbar; gleiche Zeilen wie frueher in Invoke-*).
function Get-3DPConsoleHomeAxesGcode {
    param([string]$AxesText)
    $axes = $AxesText.Trim().ToLower()
    $cmds = @()
    if ($axes -match 'x') { $cmds += 'G28 X0' }
    if ($axes -match 'y') { $cmds += 'G28 Y0' }
    if ($axes -match 'z') { $cmds += 'G28 Z0' }
    if ($axes -match 'e') { $cmds += 'G92 E0' }
    if ($cmds.Count -eq 0) { $cmds = @('G28', 'G92 E0') }
    return ($cmds -join "`n")
}

function Invoke-HomeAxes {
    param([System.IO.Ports.SerialPort]$Port, [string]$Args)
    $gcode = Get-3DPConsoleHomeAxesGcode -AxesText $Args
    $lineCount = Send-Gcode -Port $Port -Gcode $gcode
    $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $gcode) -ExpectedOkCount $lineCount
}

# Ergebnis: gcode (string) oder Fehlercode axis|distance|syntax + ggf. axis-Name
function Get-3DPConsoleRelativeMoveGcode {
    param([string]$ArgsText)
    $parts = ($ArgsText -split '\s+') | Where-Object { $_ }
    if ($parts.Count -lt 2) { return @{ err = 'syntax' } }
    $axis = $parts[0].ToUpper()
    if ($axis -notmatch '^[XYZE]$') { return @{ err = 'axis'; axis = $axis } }
    $dist = 0.0
    $inv = [cultureinfo]::InvariantCulture
    if (-not [double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Float, $inv, [ref]$dist)) { return @{ err = 'distance' } }
    $feed = if ($axis -eq 'Z') { $Script:Config.z_feedrate } elseif ($axis -eq 'E') { $Script:Config.e_feedrate } else { $Script:Config.xy_feedrate }
    if ($parts.Count -ge 3) { $feed = [int]$parts[2] }
    $distStr = $dist.ToString($inv)
    $gcode = "G91`nG0 $axis$distStr F$feed`nG90"
    return @{ err = $null; gcode = $gcode }
}

function Invoke-3DPConsoleSendMoveGcodeOk {
    param([System.IO.Ports.SerialPort]$Port, [string]$Gcode)
    $lineCount = Send-Gcode -Port $Port -Gcode $Gcode
    $null = Read-SerialResponse -Port $Port -Ms 15000 -ExpectedOkCount $lineCount
}

function Invoke-Move {
    param([System.IO.Ports.SerialPort]$Port, [string]$Args)
    $r = Get-3DPConsoleRelativeMoveGcode -ArgsText $Args
    if ($r.err -eq 'syntax') { Write-Host '  Syntax: /move <Axis> <Distance> [F Speed]' -ForegroundColor Yellow; return }
    if ($r.err -eq 'axis') { Write-Host ('  Unknown axis: ' + $r.axis) -ForegroundColor Red; return }
    if ($r.err -eq 'distance') { Write-Host '  Invalid distance' -ForegroundColor Red; return }
    Invoke-3DPConsoleSendMoveGcodeOk -Port $Port -Gcode $r.gcode
}

function Get-3DPConsoleExtrudeGcode {
    param([string]$ArgsText, [switch]$Reverse)
    $parts = ($ArgsText -split '\s+') | Where-Object { $_ }
    $len = if ($Reverse) { -$Script:Config.default_extrusion } else { $Script:Config.default_extrusion }
    $feed = $Script:Config.e_feedrate
    $inv = [cultureinfo]::InvariantCulture
    if ($parts.Count -ge 1) {
        if ($Reverse) {
            $x = 0.0
            if ([double]::TryParse($parts[0], [System.Globalization.NumberStyles]::Float, $inv, [ref]$x)) { $len = -$x }
        } else {
            [double]::TryParse($parts[0], [System.Globalization.NumberStyles]::Float, $inv, [ref]$len) | Out-Null
        }
    }
    if ($parts.Count -ge 2) { [int]::TryParse($parts[1], [ref]$feed) | Out-Null }
    $lenStr = $len.ToString($inv)
    return "G91`nG1 E$lenStr F$feed`nG90"
}

function Invoke-Extrude {
    param([System.IO.Ports.SerialPort]$Port, [string]$Args)
    $gcode = Get-3DPConsoleExtrudeGcode -ArgsText $Args
    $lineCount = Send-Gcode -Port $Port -Gcode $gcode
    $null = Read-SerialResponse -Port $Port -Ms 15000 -ExpectedOkCount $lineCount
}

function Invoke-Reverse {
    param([System.IO.Ports.SerialPort]$Port, [string]$Args)
    $gcode = Get-3DPConsoleExtrudeGcode -ArgsText $Args -Reverse
    $lineCount = Send-Gcode -Port $Port -Gcode $gcode
    $null = Read-SerialResponse -Port $Port -Ms 15000 -ExpectedOkCount $lineCount
}

function Get-3DPConsoleMonitorIntervalSeconds {
    param([string]$ArgsText, [double]$DefaultInterval)
    $interval = $DefaultInterval
    if ($ArgsText -match '[\d.]+') { $interval = [double]$Matches[0] }
    return $interval
}

function Invoke-Monitor {
    param([object]$Port, [string]$Args)
    $interval = Get-3DPConsoleMonitorIntervalSeconds -ArgsText $Args -DefaultInterval $Script:Config.monitor_interval
    Write-Host ('  Monitor every ' + $interval + 's. Ctrl+C to exit.') -ForegroundColor Cyan
    try {
        while ($true) {
            if ($env:THREEDP_CONSOLE_SKIP_MAIN -ne '1' -and (Test-3DPConsoleCtrlCRequestedAndReset)) { break }
            Write-3DPConsoleSessionTranscriptLine -Kind SEND -Line 'M105'
            $Port.WriteLine('M105')
            Start-Sleep -Milliseconds 800
            if ($Port.BytesToRead -gt 0) {
                $raw = $Port.ReadExisting()
                foreach ($line in ($raw -split "[\r\n]+")) {
                    $line = $line.Trim()
                    if ($line) {
                        Write-3DPConsoleSessionTranscriptLine -Kind RECV -Line $line
                        $fmt = Format-TemperatureReport -Line $line
                        if ($fmt) { $fmt | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan } }
                    }
                }
            }
            Start-Sleep -Seconds $interval
            # Pester / Headless: eine Runde reicht fuer Coverage (sonst haengen Tests an Endlosschleife).
            if ($env:THREEDP_CONSOLE_SKIP_MAIN -eq '1') { break }
        }
    } catch {
        # Ctrl+C oder Abbruch durch Benutzer erwartet
    }
    Write-Host '  Monitor beendet.' -ForegroundColor DarkGray
}

function Invoke-SdLs {
    param([object]$Port)
    $Port.DiscardInBuffer()
    Write-3DPConsoleSessionTranscriptLine -Kind SEND -Line 'M20'
    $Port.WriteLine('M20')
    Start-Sleep -Milliseconds 500
    $buf = ''
    $end = $false
    $start = Get-Date
    while (-not $end -and ((Get-Date) - $start).TotalSeconds -lt 10) {
        if ($Port.BytesToRead -gt 0) {
            $buf += $Port.ReadExisting()
            if ($buf -match 'End file list') { $end = $true }
        }
        Start-Sleep -Milliseconds 50
    }
    $lines = $buf -split "[\r\n]+"
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t) { Write-3DPConsoleSessionTranscriptLine -Kind RECV -Line $t }
    }
    $files = @()
    foreach ($l in $lines) {
        $l = $l.Trim()
        if ($l -match '\.(g|gco|gcode)$') { $files += ($l -split '\s+')[0] }
    }
    if ($files.Count -eq 0) { Write-Host '  Keine G-Code-Dateien oder SD nicht bereit.' -ForegroundColor Yellow } else {
        Write-Host '  SD-Dateien:' -ForegroundColor Cyan
        $files | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor White }
    }
}

function Invoke-SdPrint {
    # [object] erlaubt echte SerialPort-Instanzen und Pester-Mock-Ports (WriteLine ohne geoeffneten COM).
    param([object]$Port, [string]$Filename)
    if (-not $Filename) { Write-Host '  Syntax: /sdprint <filename.g>' -ForegroundColor Yellow; return }
    $fn = $Filename.Trim().ToLower()
    if (-not $fn.EndsWith('.g') -and -not $fn.EndsWith('.gcode')) { $fn = $fn + '.g' }
    Write-3DPConsoleSessionTranscriptLine -Kind SEND -Line ('M23 ' + $fn)
    $Port.WriteLine('M23 ' + $fn)
    Start-Sleep -Milliseconds 300
    Write-3DPConsoleSessionTranscriptLine -Kind SEND -Line 'M24'
    $Port.WriteLine('M24')
    Write-Host ('  SD-Druck gestartet: ' + $fn) -ForegroundColor Green
}

function Invoke-3DPConsoleSendMacroGcodeOk {
    param([System.IO.Ports.SerialPort]$Port, [string]$Gcode)
    $lineCount = Send-Gcode -Port $Port -Gcode $Gcode
    $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $Gcode) -ExpectedOkCount $lineCount
}

function Get-LoopPaletteItemsBuildList {
    param([hashtable]$Loops)
    $ordered = $Script:Config.LoopOrder
    $names = if ($ordered -is [array] -and $ordered.Count -gt 0) {
        $rest = @($Loops.Keys | Where-Object { $ordered -notcontains $_ } | Sort-Object)
        @($ordered | Where-Object { $Loops.ContainsKey($_) }) + @($rest)
    } else {
        @($Loops.Keys | Sort-Object)
    }
    return @($names | ForEach-Object {
        $name = $_
        $entry = $Loops[$name]
        $c = if ($entry -is [hashtable] -and $entry.cmds) { $entry.cmds.Count } elseif ($entry -is [array]) { $entry.Count } else { 0 }
        $fullDesc = if ($entry -is [hashtable] -and $entry.desc) { $entry.desc } else { "$c commands" }
        $shortDesc = if ($entry -is [hashtable] -and $entry.descShort) { $entry.descShort } else { $fullDesc }
        $item = @{cmd="loop $name"; desc=$shortDesc}
        if ($shortDesc -ne $fullDesc) { $item.descLong = $fullDesc }
        $item
    })
}

function Invoke-Macro {
    param([System.IO.Ports.SerialPort]$Port, [string]$Args)
    $parts = ($Args -split '\s+') | Where-Object { $_ }
    $macros = $Script:Config.Macros
    if (-not $macros -or -not ($macros -is [hashtable])) {
        $macroPath = Get-3DPConsoleOptionalFile 'PrusaMini-Macros.ps1'
        if ($macroPath) { $macros = . $macroPath } else { $macros = @{} }
    }
    if ($parts.Count -lt 1) {
        if ($macros.Count -gt 0) {
            Write-Host '  Makros:' -ForegroundColor Cyan
            $macros.Keys | ForEach-Object { Write-Host ('    ' + $_ + ': ' + $macros[$_]) -ForegroundColor White }
        }
        return
    }
    $name = $parts[0].ToLower()
    $macroArgs = @($parts[1..($parts.Count-1)])
    if (-not $macros[$name]) { Write-Host ('  Macro "' + $name + '" unknown.') -ForegroundColor Yellow; return }
    $tpl = $macros[$name]
    if ($tpl -is [array]) { $tpl = $tpl -join "`n" }
    $gcode = $tpl
    for ($i = 0; $i -lt $macroArgs.Count; $i++) {
        $gcode = $gcode -replace "\{$i\}", $macroArgs[$i]
    }
    $gcode = $gcode -replace '\{\d+\}', ''
    Invoke-3DPConsoleSendMacroGcodeOk -Port $Port -Gcode $gcode
}

# =============================================================================
# 5. DATEN (MaxVisibleItems, UI-Symbole - G/M/Slash/Quick kommen aus Config)
# =============================================================================

$Script:MaxVisibleItems = if ($null -ne $Script:Config.MaxVisibleItems -and $Script:Config.MaxVisibleItems -gt 0) { [int]$Script:Config.MaxVisibleItems } else { 12 }
$Script:ArrowRight = [char]0x2192
$Script:ArrowDown = [char]0x2193
$Script:BoxH = [char]0x2500

# =============================================================================
# 6. PALETTE LOGIC (Get-PaletteItems, Loops, /-commands, G/M-filter)
# =============================================================================

function Get-LoopPaletteItems {
    $loops = $Script:Config.Loops
    if (-not $loops -or -not ($loops -is [hashtable])) {
        $loopsPath = Get-3DPConsoleOptionalFile 'PrusaMini-Loops.ps1'
        if (-not $loopsPath) { return @() }
        try { $loops = . $loopsPath } catch { return @() }
    }
    try {
        return Get-LoopPaletteItemsBuildList -Loops $loops
    } catch { return @() }
}

# Filters palette entries by buffer (/, G, M, loop with Tab completion)
function Get-PaletteItems {
    param([string]$Buffer)
    $b = $Buffer.Trim().ToLower()
    if ($b -match '^/(.*)$') {
        $f = $Matches[1].Trim()
        $base = if ($f) { ($f -split '\s+')[0] } else { '' }
        $prefix = if ($base) { "/$($base.ToLower())" } else { '/' }
        $matched = @($Script:SlashCommands | Where-Object { $_.cmd -and $_.cmd.ToLower().StartsWith($prefix) })
        if ($matched.Count -eq 1 -and $f -and $f -ne $base) {
            $m = $matched[0]
            $synth = @{cmd=("/" + $f); desc=$m.desc}
            if ($m.action) { $synth.action = $m.action }
            if ($m.gcode) { $synth.gcode = $m.gcode }
            return @($synth)
        }
        return $matched
    }
    if ($b -match '^g(\d*)$') {
        $pre = if ($Matches[1]) { "G$($Matches[1])" } else { "G" }
        return @($Script:GCommands | Where-Object { $_.cmd -like "${pre}*" })
    }
    if ($b -match '^m(\d*)$') {
        $pre = if ($Matches[1]) { "M$($Matches[1])" } else { "M" }
        return @($Script:MCommands | Where-Object { $_.cmd -like "${pre}*" })
    }
    if ($b -match '^loop\s*(.*)$') {
        $f = $Matches[1].Trim()
        $all = Get-LoopPaletteItems
        $parts = $f -split '\s+'
        $baseFilter = $f
        $namePart = $f
        $numPart = $null
        if ($parts.Count -ge 2) {
            $lastNum = 0
            if ([int]::TryParse($parts[-1], [ref]$lastNum) -and $lastNum -ge 1) {
                $numPart = $parts[-1]
                $namePart = ($parts[0..($parts.Count - 2)] -join ' ').Trim()
                $baseFilter = $namePart
            }
        }
        $matched = @($all | Where-Object { $_.cmd.Trim().ToLower() -like "loop $($baseFilter.Trim().ToLower())*" })
        if ($matched.Count -eq 1 -and $numPart) {
            $m0 = $matched[0]
            $synth = @{cmd=("loop " + $namePart + " " + $numPart); desc=($m0.desc + " ($numPart`x)")}
            if ($m0.descLong) { $synth.descLong = $m0.descLong + " ($numPart`x)" }
            return @($synth)
        }
        return @($all | Where-Object { $_.cmd.Trim().ToLower() -like "loop $($f.Trim().ToLower())*" })
    }
    return @()
}
