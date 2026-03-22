<#
.SYNOPSIS
    Configuration for 3DP-Console.

.DESCRIPTION
    All scripts (3DP-Console.ps1, tests\Test-All.ps1) load this file on startup.
    Loops and Macros are integrated here (formerly separate files).
    The file must return a hashtable (last line).
#>

@{
    # -------------------------------------------------------------------------
    # Serial connection
    # -------------------------------------------------------------------------
    ComPort  = "COM5"
    BaudRate = 115200

    # -------------------------------------------------------------------------
    # Temperature (defaults for d=, b=, /duese, /bett)
    # -------------------------------------------------------------------------
    NozzleTempCelsius = 170
    BettTempCelsius   = 60

    # Presets for /pla and /abs
    PLA_Hotend = 170
    PLA_Bed    = 60
    ABS_Hotend = 230
    ABS_Bed    = 110

    # -------------------------------------------------------------------------
    # Motion (move, extrude, reverse)
    # -------------------------------------------------------------------------
    xy_feedrate        = 3000
    z_feedrate         = 600
    e_feedrate         = 300
    default_extrusion  = 5

    # -------------------------------------------------------------------------
    # Monitor (/monitor)
    # -------------------------------------------------------------------------
    monitor_interval = 5

    # -------------------------------------------------------------------------
    # UI (label for nozzle/hotend, palette size)
    # -------------------------------------------------------------------------
    DueseLabel         = "Nozzle"   # e.g. "Hotend", "Nozzle"
    MaxVisibleItems    = 10         # Number of visible palette entries

    # -------------------------------------------------------------------------
    # UI strings (placeholders: {ComPort}, {NozzleTemp}, {BedTemp}, {DueseLabel})
    # -------------------------------------------------------------------------
    ConsoleTitle       = "=== 3DP-Console ==="
    StatusConnected    = "Connected to {ComPort}. Esc=Cancel  Arrows=Navigate  Enter=Select"
    StatusReconnecting = "Connection lost. Recovering... ({ComPort})"
    HintCommands       = "Type /, G or M for commands"
    HintShortcuts      = "d={DueseLabel}{NozzleTemp}  b=Bed{BedTemp}  loop [name] [n]  quit=Exit"
    HintReconnect      = "r=Reconnect  /, G, M=Commands  quit=Exit"
    HelpText           = "G, M, / = Commands   /pla /abs /move /extrude /reverse /monitor /ls /sdprint /macro  loop  off"
    ExitMessage        = "Console closed."

    # -------------------------------------------------------------------------
    # Session transcript (Debug-Log: gesendeter G-Code + Rohzeilen vom Drucker)
    # Standard: aus. Nur aktivieren, wenn du eine zeitgestempelte .log-Datei brauchst.
    # -------------------------------------------------------------------------
    SessionTranscriptEnabled   = $false
    # Leer = Ordner "SessionLogs" neben 3DP-Console.ps1; sonst absoluter Pfad oder relativ zu diesem Skriptordner
    # SessionTranscriptDirectory = ""

    # -------------------------------------------------------------------------
    # BedLevel loop (level_compare - CSV storage, round comparison)
    # -------------------------------------------------------------------------
    MessungenCount           = 3
    CsvOutputPath            = (Join-Path $PSScriptRoot "BedLevelResults")
    CsvFilePrefix            = "BedLevel_Measurement"
    CommandTimeoutMs         = 300
    G29MaxWaitSeconds        = 600
    # G-Code timeouts (ms): Wait for ok from printer
    G28G29TimeoutMs         = 300000   # G28, G29 (5 min)
    HeatingTimeoutMs        = 600000   # M109, M190 (10 min)
    DefaultGcodeTimeoutMs   = 15000    # Other commands (15 sec)
    VergleicheMitDurchschnitt = $true
    MaxTolerierteAbweichungMm = 0.05
    HeizungVorMessung        = $false

    # Interactive Bed Leveling (mesh color thresholds)
    MeshThresholdGreenMm  = 0.05   # <= grün (gut ausgerichtet)
    MeshThresholdYellowMm = 0.15   # <= gelb (mittel), > rot

    # -------------------------------------------------------------------------
    # Loops (examples: loop prepare | loop level_compare 5 | loop level_rehome_once 2 | loop temp_ramp 4)
    # Placeholders: {i}=pass 1..N, {i0}=0..N-1, {T}=temp at startTemp+stepTemp
    # LoopOrder: display order in palette (optional; default: alphabetical)
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # Macros (/macro <name> [arg1] [arg2] - placeholders {0}, {1}, ...)
    # -------------------------------------------------------------------------
    Macros = @{
        preheat = 'M104 S{0}'
        bedtemp = 'M140 S{0}'
        pla     = @('M104 S170', 'M140 S60')
        abs     = @('M104 S230', 'M140 S110')
    }

    # -------------------------------------------------------------------------
    # G/M commands (palette on input g, m)
    # -------------------------------------------------------------------------
    GCommands = @(
        @{cmd="G0"; desc="Move (fast)"}
        @{cmd="G1"; desc="Move (linear)"}
        @{cmd="G2"; desc="Arc (CW)"}
        @{cmd="G3"; desc="Arc (CCW)"}
        @{cmd="G4"; desc="Wait/Pause"}
        @{cmd="G10"; desc="Retract filament"}
        @{cmd="G11"; desc="Unretract filament"}
        @{cmd="G21"; desc="Unit: mm"}
        @{cmd="G28"; desc="Homing"}
        @{cmd="G29"; desc="Bed Leveling"}
        @{cmd="G30"; desc="Single Z probe"}
        @{cmd="G90"; desc="Absolute positioning"}
        @{cmd="G91"; desc="Relative positioning"}
        @{cmd="G92"; desc="Set position"}
    )

    MCommands = @(
        @{cmd="M17"; desc="Enable steppers"}
        @{cmd="M84"; desc="Disable steppers"}
        @{cmd="M104"; desc="Set nozzle temp"}
        @{cmd="M109"; desc="Set nozzle temp + wait"}
        @{cmd="M140"; desc="Set bed temp"}
        @{cmd="M190"; desc="Set bed temp + wait"}
        @{cmd="M105"; desc="Query temperature"}
        @{cmd="M106"; desc="Fan on (S0-255)"}
        @{cmd="M107"; desc="Fan off"}
        @{cmd="M112"; desc="EMERGENCY STOP"}
        @{cmd="M114"; desc="Current position"}
        @{cmd="M115"; desc="Firmware info"}
        @{cmd="M301"; desc="Hotend PID"}
        @{cmd="M303"; desc="PID Autotune"}
        @{cmd="M420"; desc="Bed Leveling Mesh"}
        @{cmd="M500"; desc="Save to EEPROM"}
        @{cmd="M501"; desc="Load from EEPROM"}
        @{cmd="M502"; desc="Factory reset"}
    )

    # -------------------------------------------------------------------------
    # Slash commands (/...) - placeholders: {NozzleTemp}, {BedTemp}, {DueseLabel}
    # -------------------------------------------------------------------------
    SlashCommands = @(
        @{cmd="/help"; desc="Show help"; action="help"}
        @{cmd="/temp"; desc="Query temperature"; gcode="M105"}
        @{cmd="/pos"; desc="Current position"; gcode="M114"}
        @{cmd="/info"; desc="Firmware info"; gcode="M115"}
        @{cmd="/home"; desc="Homing (optional: xy, z, e)"; action="home"}
        @{cmd="/level"; desc="Bed Leveling (G29)"; gcode="G29"}
        @{cmd="/duese"; desc="{DueseLabel} {NozzleTemp} C"; gcode="M104 S{NozzleTemp}"}
        @{cmd="/bett"; desc="Bed {BedTemp} C"; gcode="M140 S{BedTemp}"}
        @{cmd="/pla"; desc="Preset PLA (nozzle+bed)"; action="preset_pla"}
        @{cmd="/abs"; desc="Preset ABS (nozzle+bed)"; action="preset_abs"}
        @{cmd="/off"; desc="Heater off"; gcode="M104 S0`nM140 S0"}
        @{cmd="/fan"; desc="Fan off"; gcode="M107"}
        @{cmd="/motoren"; desc="Enable steppers (M17)"; gcode="M17"}
        @{cmd="/move"; desc="Move axis (X 10, Z -1)"; action="move"}
        @{cmd="/extrude"; desc="Extrude filament (mm)"; action="extrude"}
        @{cmd="/reverse"; desc="Retract filament (mm)"; action="reverse"}
        @{cmd="/monitor"; desc="Monitor temp/progress"; action="monitor"}
        @{cmd="/ls"; desc="SD card: list files"; action="sd_ls"}
        @{cmd="/sdprint"; desc="SD card: start print"; action="sd_print"}
        @{cmd="/macro"; desc="Run macro (macro name arg1 arg2)"; action="macro"}
        @{cmd="/g"; desc="G-commands preview"; action="g"}
        @{cmd="/m"; desc="M-commands preview"; action="m"}
    )

    # -------------------------------------------------------------------------
    # QuickActions (type directly: d, b, off, home, ...) - placeholders: {NozzleTemp}, {BedTemp}
    # -------------------------------------------------------------------------
    QuickActions = @(
        @{key="d"; gcode="M104 S{NozzleTemp}"}
        @{key="dw"; gcode="M109 S{NozzleTemp}"}
        @{key="b"; gcode="M140 S{BedTemp}"}
        @{key="bw"; gcode="M190 S{BedTemp}"}
        @{key="off"; gcode="M104 S0`nM140 S0"}
        @{key="fan"; gcode="M107"}
        @{key="home"; gcode="G28"}
        @{key="level"; gcode="G29"}
        @{key="temp"; gcode="M105"}
    )
}
