<#
    Fragment: 3DP-Console.Init.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# =============================================================================
# 2. INITIALIZATION (Encoding, System.IO.Ports, Config)
# =============================================================================
# $Script:ConsoleRoot is set by 3DP-Console.ps1 before dot-sourcing this file (not lib/).

# --- BasePath (project root) ---
if (-not [string]::IsNullOrWhiteSpace($Script:ConsoleRoot)) {
    $Script:BasePath = $Script:ConsoleRoot
} elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $Script:BasePath = $PSScriptRoot }
elseif ($MyInvocation.MyCommand.Path) { $Script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path }
elseif ($PSCommandPath) { $Script:BasePath = Split-Path -Parent $PSCommandPath }
else { $Script:BasePath = (Get-Location).ProviderPath }

# Optional sidecar scripts (e.g. PrusaMini-Macros.ps1): next to 3DP-Console.ps1; if that folder is .\src\, also repo root (parent).
function Get-3DPConsoleOptionalFile {
    param([string]$FileName)
    $p = Join-Path $Script:BasePath $FileName
    if (Test-Path -LiteralPath $p) { return $p }
    if ((Split-Path -Leaf $Script:BasePath) -eq 'src') {
        $p2 = Join-Path (Split-Path -Parent $Script:BasePath) $FileName
        if (Test-Path -LiteralPath $p2) { return $p2 }
    }
    return $null
}

# --- Encoding ---
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Encoding not available (e.g. older hosts) - continue with default
}

# --- Load System.IO.Ports (for serial port) ---
# Resolves "Assembly System.IO.Ports could not be found" on systems without preinstalled assembly.
$script:SerialPortsLoaded = $false
function Ensure-SystemIOPortsLoaded {
    if ($script:SerialPortsLoaded) { return $true }
    try {
        Add-Type -AssemblyName System.IO.Ports -ErrorAction Stop
        $script:SerialPortsLoaded = $true
        return $true
    } catch { }
    $baseDir = if ($Script:BasePath) { $Script:BasePath } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $cacheDir = Join-Path $baseDir ".serialports_cache"
    $dll = Get-ChildItem -Path $cacheDir -Recurse -Filter "System.IO.Ports.dll" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "net46|netstandard" } | Select-Object -First 1
    if ($dll -and (Test-Path $dll.FullName)) {
        try {
            Add-Type -Path $dll.FullName -ErrorAction Stop
            $script:SerialPortsLoaded = $true
            return $true
        } catch { }
    }
    try {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        $extractDir = Join-Path $cacheDir "extract_temp"
        $nupkgUrl = "https://api.nuget.org/v3-flatcontainer/system.io.ports/8.0.0/system.io.ports.8.0.0.nupkg"
        $nupkgPath = Join-Path $cacheDir "system.io.ports.nupkg"
        Write-Host "Loading System.IO.Ports from NuGet (one-time)..." -ForegroundColor Yellow
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath -UseBasicParsing
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        $zipPath = Join-Path $cacheDir "system.io.ports.zip"
        Copy-Item -Path $nupkgPath -Destination $zipPath -Force
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        $dll = Get-ChildItem -Path $extractDir -Recurse -Filter "System.IO.Ports.dll" | Where-Object { $_.FullName -match "net46|netstandard" } | Select-Object -First 1
        if ($dll) {
            Add-Type -Path $dll.FullName -ErrorAction Stop
            $script:SerialPortsLoaded = $true
            Remove-Item $nupkgPath -Force -ErrorAction SilentlyContinue
            return $true
        }
    } catch {
        Write-Host "Error loading System.IO.Ports: $_" -ForegroundColor Red
    }
    return $false
}
if (-not (Ensure-SystemIOPortsLoaded)) {
    Write-Host 'System.IO.Ports cannot be loaded.' -ForegroundColor Red
    exit 1
}

# --- Default config (overridden by 3DP-Config.ps1) ---
$Script:Config = @{
    ComPort = "COM3"
    BaudRate = 115200
    DueseLabel = 'Nozzle'
    MaxVisibleItems = 12
    G28G29TimeoutMs = 300000
    HeatingTimeoutMs = 600000
    DefaultGcodeTimeoutMs = 15000
    NozzleTempCelsius = 170
    BettTempCelsius = 60
    PLA_Hotend = 170
    PLA_Bed = 60
    ABS_Hotend = 230
    ABS_Bed = 110
    xy_feedrate = 3000
    z_feedrate = 600
    e_feedrate = 300
    default_extrusion = 5
    monitor_interval = 5
    ConsoleTitle = "=== 3DP-Console ==="
    StatusConnected = "Connected to {ComPort}. Esc=Cancel  Arrows=Navigate  Tab=Complete  Enter=Select"
    StatusReconnecting = "Connection lost. Recovering... ({ComPort})"
    HintCommands = "Type /, G or M for commands"
    HintShortcuts = "d={DueseLabel}{NozzleTemp}  b=Bed{BedTemp}  loop [name]  quit=Exit"
    HintReconnect = "r=Reconnect  /, G, M=Commands  quit=Exit"
    HelpText = "G, M, / = Command preview   d={DueseLabel}  b=Bed  loop prepare|level_compare|cooldown  off=Heater"
    ExitMessage = "Console closed."
}
# --- Load config file (Loops, Macros, UI-Strings) ---
# If no config exists: create from embedded template (only on interactive start, not for tests).
# $configTemplateContent = fallback only when 3DP-Config.ps1 is missing; keep in sync with shipped 3DP-Config.ps1 (English loop names, LoopOrder, Temp2).
$configPath = if ($ConfigPath) {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $Script:BasePath $ConfigPath }
} else {
    Join-Path $Script:BasePath "3DP-Config.ps1"
}
$configTemplateContent = @'
<#
# Auto-generated fallback: 3DP-Config.ps1 was missing on first start.
# Prefer editing the shipped 3DP-Config.ps1 from the repo (same folder) — this block mirrors its loop names and structure.
#>
@{
    ComPort  = "COM3"
    BaudRate = 115200
    NozzleTempCelsius = 170
    BettTempCelsius   = 60
    PLA_Hotend = 170
    PLA_Bed    = 60
    ABS_Hotend = 230
    ABS_Bed    = 110
    xy_feedrate        = 3000
    z_feedrate         = 600
    e_feedrate         = 300
    default_extrusion  = 5
    monitor_interval   = 5
    DueseLabel         = "Nozzle"
    MaxVisibleItems    = 10
    ConsoleTitle       = "=== 3DP-Console ==="
    StatusConnected    = "Connected to {ComPort}. Esc=Cancel  Arrows=Navigate  Enter=Select"
    StatusReconnecting = "Connection lost. Recovering... ({ComPort})"
    HintCommands       = "Type /, G or M for commands"
    HintShortcuts      = "d={DueseLabel}{NozzleTemp}  b=Bed{BedTemp}  loop [name] [n]  quit=Exit"
    HintReconnect      = "r=Reconnect  /, G, M=Commands  quit=Exit"
    HelpText           = "G, M, / = Commands   /pla /abs /move /extrude /reverse /monitor /ls /sdprint /macro  loop  off"
    ExitMessage        = "Console closed."
    MessungenCount           = 3
    CsvOutputPath            = (Join-Path $PSScriptRoot "BedLevelResults")
    CsvFilePrefix            = "BedLevel_Measurement"
    CommandTimeoutMs         = 300
    G29MaxWaitSeconds        = 600
    G28G29TimeoutMs         = 300000
    HeatingTimeoutMs        = 600000
    DefaultGcodeTimeoutMs   = 15000
    VergleicheMitDurchschnitt = $true
    MaxTolerierteAbweichungMm = 0.05
    HeizungVorMessung        = $false
    MeshThresholdGreenMm  = 0.05
    MeshThresholdYellowMm = 0.15
    LoopOrder = @('prepare', 'cooldown', 'level_compare', 'interactive_bedlevel', 'level_rehome', 'level_rehome_once', 'temp_ramp', 'temp2_nozzle', 'temp2_bed', 'temp2_combined')
    Loops = @{
        prepare = @{
            desc = 'Heater+Bed, Home'
            cmds = @('M104 S170','M140 S60','M109 S170','M190 S60','G28')
        }
        cooldown = @{
            desc = 'Heater off, Fan off'
            cmds = @('M104 S0','M140 S0','M107')
        }
        level_rehome = @{
            desc   = '5x Bed Leveling (G28 + G29)'
            repeat = 5
            cmds   = @('G28','G29')
        }
        level_rehome_once = @{
            desc     = '4x Bed Leveling (G28 once, then G29)'
            descShort = '4x G29 (G28 once)'
            repeat  = 4
            init   = @('G28')
            cmds   = @('G29')
        }
        level_compare = @{
            desc      = 'G29 xN with CSV storage, round comparison (first measurement to each round) + Min/Max/Avg per probe point'
            descShort = 'G29 xN, CSV, round compare, Min/Max/Avg'
            action   = 'level_compare'
            repeat    = 3
            init      = @('G28')
            useG29T   = $false
        }
        interactive_bedlevel = @{
            desc                 = 'Interactive Bed Leveling: Heat, G28, G29, colored mesh, Enter=remess, Esc=exit'
            descShort            = 'Interactive Bed Leveling'
            action               = 'interactive_bedlevel'
            bedTemp              = 60
            nozzleTemp           = 170
            stabilizationSeconds = 0
        }
        temp_ramp = @{
            desc      = 'Temp ramp 170->210 + Level'
            repeat    = 5
            startTemp = 170
            stepTemp  = 10
            cmds      = @('M104 S{T}','M140 S60','M109 S{T}','M190 S60')
        }
        temp2_nozzle = @{
            desc                 = 'Temp2 Leveling: Nozzle steps, bed fixed, G28+G29 per step, CSV'
            descShort            = 'Nozzle temp steps + G29, CSV'
            action               = 'temp2_nozzle'
            startNozzle          = 170
            endNozzle            = 220
            stepNozzle           = 5
            fixedBed             = 60
            stabilizationSeconds = 60
        }
        temp2_bed = @{
            desc                 = 'Temp2 Leveling: Bed steps, nozzle fixed, G28+G29 per step, CSV'
            descShort            = 'Bed temp steps + G29, CSV'
            action               = 'temp2_bed'
            fixedNozzle          = 170
            startBed             = 60
            endBed               = 100
            stepBed              = 1
            stabilizationSeconds = 60
        }
        temp2_combined = @{
            desc                 = 'Temp2 Leveling: Nozzle + Bed steps together, G28+G29 per step, CSV'
            descShort            = 'Nozzle+Bed temp steps + G29, CSV'
            action               = 'temp2_combined'
            startNozzle          = 170
            endNozzle            = 220
            stepNozzle           = 5
            startBed             = 60
            endBed               = 100
            stepBed              = 5
            stabilizationSeconds = 60
        }
    }
    Macros = @{
        preheat = 'M104 S{0}'
        bedtemp = 'M140 S{0}'
        pla     = @('M104 S170', 'M140 S60')
        abs     = @('M104 S230', 'M140 S110')
    }
    GCommands = @(
        @{cmd="G0"; desc="Move (fast)"}, @{cmd="G1"; desc="Move (linear)"}, @{cmd="G2"; desc="Arc (CW)"}, @{cmd="G3"; desc="Arc (CCW)"},
        @{cmd="G4"; desc="Wait/Pause"}, @{cmd="G10"; desc="Retract filament"}, @{cmd="G11"; desc="Unretract filament"},
        @{cmd="G21"; desc="Unit: mm"}, @{cmd="G28"; desc="Homing"}, @{cmd="G29"; desc="Bed Leveling"},
        @{cmd="G30"; desc="Single Z probe"}, @{cmd="G90"; desc="Absolute positioning"}, @{cmd="G91"; desc="Relative positioning"}, @{cmd="G92"; desc="Set position"}
    )
    MCommands = @(
        @{cmd="M17"; desc="Enable steppers"}, @{cmd="M84"; desc="Disable steppers"}, @{cmd="M104"; desc="Set nozzle temp"}, @{cmd="M109"; desc="Set nozzle temp + wait"},
        @{cmd="M140"; desc="Set bed temp"}, @{cmd="M190"; desc="Set bed temp + wait"}, @{cmd="M105"; desc="Query temperature"}, @{cmd="M106"; desc="Fan on (S0-255)"},
        @{cmd="M107"; desc="Fan off"}, @{cmd="M112"; desc="EMERGENCY STOP"}, @{cmd="M114"; desc="Current position"}, @{cmd="M115"; desc="Firmware info"},
        @{cmd="M301"; desc="Hotend PID"}, @{cmd="M303"; desc="PID Autotune"}, @{cmd="M420"; desc="Bed Leveling Mesh"},
        @{cmd="M500"; desc="Save to EEPROM"}, @{cmd="M501"; desc="Load from EEPROM"}, @{cmd="M502"; desc="Factory reset"}
    )
    SlashCommands = @(
        @{cmd="/help"; desc="Show help"; action="help"}, @{cmd="/temp"; desc="Query temperature"; gcode="M105"},
        @{cmd="/pos"; desc="Current position"; gcode="M114"}, @{cmd="/info"; desc="Firmware info"; gcode="M115"},
        @{cmd="/home"; desc="Homing (optional: xy, z, e)"; action="home"}, @{cmd="/level"; desc="Bed Leveling (G29)"; gcode="G29"},
        @{cmd="/duese"; desc="{DueseLabel} {NozzleTemp} C"; gcode="M104 S{NozzleTemp}"}, @{cmd="/bett"; desc="Bed {BedTemp} C"; gcode="M140 S{BedTemp}"},
        @{cmd="/pla"; desc="Preset PLA (nozzle+bed)"; action="preset_pla"}, @{cmd="/abs"; desc="Preset ABS (nozzle+bed)"; action="preset_abs"},
        @{cmd="/off"; desc="Heater off"; gcode="M104 S0`nM140 S0"}, @{cmd="/fan"; desc="Fan off"; gcode="M107"},
        @{cmd="/motoren"; desc="Enable steppers (M17)"; gcode="M17"}, @{cmd="/move"; desc="Move axis (X 10, Z -1)"; action="move"},
        @{cmd="/extrude"; desc="Extrude filament (mm)"; action="extrude"}, @{cmd="/reverse"; desc="Retract filament (mm)"; action="reverse"},
        @{cmd="/monitor"; desc="Monitor temp/progress"; action="monitor"}, @{cmd="/ls"; desc="SD card: list files"; action="sd_ls"},
        @{cmd="/sdprint"; desc="SD card: start print"; action="sd_print"}, @{cmd="/macro"; desc="Run macro (macro name arg1 arg2)"; action="macro"},
        @{cmd="/g"; desc="G-commands preview"; action="g"}, @{cmd="/m"; desc="M-commands preview"; action="m"}
    )
    QuickActions = @(
        @{key="d"; gcode="M104 S{NozzleTemp}"}, @{key="dw"; gcode="M109 S{NozzleTemp}"}, @{key="b"; gcode="M140 S{BedTemp}"}, @{key="bw"; gcode="M190 S{BedTemp}"},
        @{key="off"; gcode="M104 S0`nM140 S0"}, @{key="fan"; gcode="M107"}, @{key="home"; gcode="G28"}, @{key="level"; gcode="G29"}, @{key="temp"; gcode="M105"}
    )
}
'@
$isDefaultConfigPath = -not $ConfigPath
if ($env:THREEDP_CONSOLE_SKIP_MAIN -ne '1' -and $isDefaultConfigPath -and -not (Test-Path -LiteralPath $configPath)) {
    try {
        Set-Content -Path $configPath -Value $configTemplateContent -Encoding UTF8
        Write-Host '  3DP-Config.ps1 was created from template. Please adjust ComPort.' -ForegroundColor Yellow
    } catch {
        # Ignore write error; embedded template will be merged in-memory below (Loops/palette).
    }
}

# Keys copied from 3DP-Config.ps1 / embedded template (single list for file load + in-memory fallback)
$script:ConfigMergeKeys = @(
    'ComPort','BaudRate','DueseLabel','MaxVisibleItems','G28G29TimeoutMs','HeatingTimeoutMs','DefaultGcodeTimeoutMs',
    'MessungenCount','CommandTimeoutMs','G29MaxWaitSeconds','VergleicheMitDurchschnitt','MaxTolerierteAbweichungMm','HeizungVorMessung',
    'NozzleTempCelsius','BettTempCelsius','PLA_Hotend','PLA_Bed','ABS_Hotend','ABS_Bed','xy_feedrate','z_feedrate','e_feedrate','default_extrusion','monitor_interval',
    'ConsoleTitle','StatusConnected','StatusReconnecting','HintCommands','HintShortcuts','HintReconnect','HelpText','ExitMessage',
    'CsvOutputPath','CsvFilePrefix','MeshThresholdGreenMm','MeshThresholdYellowMm','Loops','LoopOrder','Macros','GCommands','MCommands','SlashCommands','QuickActions'
)

function Merge-HashtableIntoConfig {
    param([System.Collections.IDictionary]$Source, [string[]]$KeysOnly)
    if ($null -eq $Source) { return }
    $keys = if ($KeysOnly -and $KeysOnly.Count -gt 0) { $KeysOnly } else { $script:ConfigMergeKeys }
    foreach ($k in $keys) {
        if ($null -ne $Source[$k]) { $Script:Config[$k] = $Source[$k] }
    }
}

$configLoadedOk = $false
if (Test-Path -LiteralPath $configPath) {
    try {
        $ext = . $configPath
        if ($ext -is [System.Collections.IDictionary]) {
            Merge-HashtableIntoConfig $ext
            $configLoadedOk = $true
        }
    } catch {
        Write-Host ('  Warning: could not load 3DP-Config.ps1: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# No usable file, or Loops missing/empty: merge embedded @{ ... } so loop palette works
$__loops = $Script:Config.Loops
$loopsOk = ($null -ne $__loops) -and ($__loops -is [System.Collections.IDictionary]) -and ($__loops.Count -gt 0)
if (-not $loopsOk) {
    try {
        $tplBody = ($configTemplateContent -replace '(?s)^\s*<#.*?#>\s*', '').Trim()
        if (-not ($tplBody.StartsWith('@{') -and $tplBody.TrimEnd().EndsWith('}'))) { throw 'Template body must be @{ ... }' }
        # Join-Path $PSScriptRoot fails inside ScriptBlock::Create when PSScriptRoot is empty — use BasePath for in-memory merge only
        $rootQ = $Script:BasePath.Replace("'", "''")
        $tplBody = $tplBody -replace '\(Join-Path \$PSScriptRoot "BedLevelResults"\)', "(Join-Path '$rootQ' 'BedLevelResults')"
        $tplHt = & ([scriptblock]::Create($tplBody))
        if ($tplHt -is [System.Collections.IDictionary]) {
            if ($configLoadedOk) {
                # Config file existed and parsed: only fill Loops/macros/palette-related keys (do not overwrite ComPort etc.)
                $paletteKeys = @(
                    'Loops','LoopOrder','Macros','GCommands','MCommands','SlashCommands','QuickActions',
                    'MeshThresholdGreenMm','MeshThresholdYellowMm',
                    'CsvOutputPath','CsvFilePrefix','MessungenCount','CommandTimeoutMs','G29MaxWaitSeconds',
                    'VergleicheMitDurchschnitt','MaxTolerierteAbweichungMm','HeizungVorMessung'
                )
                Merge-HashtableIntoConfig -Source $tplHt -KeysOnly $paletteKeys
            } else {
                Merge-HashtableIntoConfig -Source $tplHt
            }
            if ($env:THREEDP_CONSOLE_SKIP_MAIN -ne '1') {
                Write-Host '  Note: 3DP-Config.ps1 not found or has no Loops - using embedded defaults (loop palette).' -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host ('  Warning: embedded config template failed: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}
if ($ComPort -and $ComPort.Trim()) {
    $Script:Config.ComPort = $ComPort.Trim()
}
$Script:DueseLabel = if ($Script:Config.DueseLabel) { $Script:Config.DueseLabel } else { 'Nozzle' }

# G/M/Slash/Quick from Config or defaults; resolve placeholders in Slash/Quick
$Script:GCommands = if ($Script:Config.GCommands) { @($Script:Config.GCommands) } else {
    @(
        @{cmd="G0"; desc="Move (fast)"}, @{cmd="G1"; desc="Move (linear)"}, @{cmd="G2"; desc="Arc (CW)"}, @{cmd="G3"; desc="Arc (CCW)"},
        @{cmd="G4"; desc="Wait/Pause"}, @{cmd="G10"; desc="Retract filament"}, @{cmd="G11"; desc="Unretract filament"},
        @{cmd="G21"; desc="Unit: mm"}, @{cmd="G28"; desc="Homing"}, @{cmd="G29"; desc="Bed Leveling"},
        @{cmd="G30"; desc="Single Z probe"}, @{cmd="G90"; desc="Absolute positioning"}, @{cmd="G91"; desc="Relative positioning"}, @{cmd="G92"; desc="Set position"}
    )
}
$Script:MCommands = if ($Script:Config.MCommands) { @($Script:Config.MCommands) } else {
    @(
        @{cmd="M17"; desc="Enable steppers"}, @{cmd="M84"; desc="Disable steppers"}, @{cmd="M104"; desc="Set nozzle temp"}, @{cmd="M109"; desc="Set nozzle temp + wait"},
        @{cmd="M140"; desc="Set bed temp"}, @{cmd="M190"; desc="Set bed temp + wait"}, @{cmd="M105"; desc="Query temperature"}, @{cmd="M106"; desc="Fan on (S0-255)"},
        @{cmd="M107"; desc="Fan off"}, @{cmd="M112"; desc="EMERGENCY STOP"}, @{cmd="M114"; desc="Current position"}, @{cmd="M115"; desc="Firmware info"},
        @{cmd="M301"; desc="Hotend PID"}, @{cmd="M303"; desc="PID Autotune"}, @{cmd="M420"; desc="Bed Leveling Mesh"},
        @{cmd="M500"; desc="Save to EEPROM"}, @{cmd="M501"; desc="Load from EEPROM"}, @{cmd="M502"; desc="Factory reset"}
    )
}
$slashRaw = if ($Script:Config.SlashCommands) { @($Script:Config.SlashCommands) } else {
    @(
        @{cmd="/help"; desc="Show help"; action="help"}, @{cmd="/temp"; desc="Query temperature"; gcode="M105"},
        @{cmd="/pos"; desc="Current position"; gcode="M114"}, @{cmd="/info"; desc="Firmware info"; gcode="M115"},
        @{cmd="/home"; desc="Homing (optional: xy, z, e)"; action="home"}, @{cmd="/level"; desc="Bed Leveling (G29)"; gcode="G29"},
        @{cmd="/duese"; desc="{DueseLabel} {NozzleTemp} C"; gcode="M104 S{NozzleTemp}"}, @{cmd="/bett"; desc="Bed {BedTemp} C"; gcode="M140 S{BedTemp}"},
        @{cmd="/pla"; desc="Preset PLA (nozzle+bed)"; action="preset_pla"}, @{cmd="/abs"; desc="Preset ABS (nozzle+bed)"; action="preset_abs"},
        @{cmd="/off"; desc="Heater off"; gcode="M104 S0`nM140 S0"}, @{cmd="/fan"; desc="Fan off"; gcode="M107"},
        @{cmd="/motoren"; desc="Enable steppers (M17)"; gcode="M17"}, @{cmd="/move"; desc="Move axis (X 10, Z -1)"; action="move"},
        @{cmd="/extrude"; desc="Extrude filament (mm)"; action="extrude"}, @{cmd="/reverse"; desc="Retract filament (mm)"; action="reverse"},
        @{cmd="/monitor"; desc="Monitor temp/progress"; action="monitor"}, @{cmd="/ls"; desc="SD card: list files"; action="sd_ls"},
        @{cmd="/sdprint"; desc="SD card: start print"; action="sd_print"}, @{cmd="/macro"; desc="Run macro (macro name arg1 arg2)"; action="macro"},
        @{cmd="/g"; desc="G-commands preview"; action="g"}, @{cmd="/m"; desc="M-commands preview"; action="m"}
    )
}
$quickRaw = if ($Script:Config.QuickActions) { @($Script:Config.QuickActions) } else {
    @(
        @{key="d"; gcode="M104 S{NozzleTemp}"}, @{key="dw"; gcode="M109 S{NozzleTemp}"}, @{key="b"; gcode="M140 S{BedTemp}"}, @{key="bw"; gcode="M190 S{BedTemp}"},
        @{key="off"; gcode="M104 S0`nM140 S0"}, @{key="fan"; gcode="M107"}, @{key="home"; gcode="G28"}, @{key="level"; gcode="G29"}, @{key="temp"; gcode="M105"}
    )
}
$n = [string]$Script:Config.NozzleTempCelsius
$b = [string]$Script:Config.BettTempCelsius
$d = $Script:DueseLabel
$Script:SlashCommands = @($slashRaw | ForEach-Object {
    $c = $_.cmd; $desc = if ($_.desc) { $_.desc -replace '\{NozzleTemp\}',$n -replace '\{BedTemp\}',$b -replace '\{DueseLabel\}',$d } else { '' }
    $gcode = if ($_.gcode) { $_.gcode -replace '\{NozzleTemp\}',$n -replace '\{BedTemp\}',$b } else { $null }
    $out = @{cmd=$c}
    if ($desc) { $out.desc = $desc }
    if ($null -ne $_.action) { $out.action = $_.action }
    if ($null -ne $gcode) { $out.gcode = $gcode }
    $out
})
$Script:QuickActions = @($quickRaw | ForEach-Object {
    $gcode = if ($_.gcode) { $_.gcode -replace '\{NozzleTemp\}',$n -replace '\{BedTemp\}',$b } else { $null }
    @{key=$_.key; gcode=$gcode}
})
