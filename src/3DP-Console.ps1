<#
.SYNOPSIS
    3DP-Console - Interactive G-Code console

.DESCRIPTION
    Type /, G or M - preview appears instantly below.
    Arrow keys to navigate, Enter to select.

.PARAMETER Help
    Shows short help and examples.

.PARAMETER About
    Shows script info and version.

.PARAMETER Example
    Shows examples for usage.

.PARAMETER ComPort
    COM-Port override (overrides 3DP-Config.ps1).

.PARAMETER ConfigPath
    Path to config file (relative or absolute).

.PARAMETER Command
    Execute single command and exit (no interactive console). e.g. G28, G29, home, level (G29), loop prepare, loop level_compare.

.EXAMPLE
    .\src\3DP-Console.ps1
    Starts the console interactively (from repository root).

.EXAMPLE
    .\src\3DP-Console.ps1 -Help
    Shows the help.
#>

#Requires -Version 5.1
$Script:Version = '26.3.0'

#region 00-EnvNormalize
# Tests / tooling: skip interactive Main() when THREEDP_CONSOLE_SKIP_MAIN=1 (printer-agnostic).
# Legacy env name (still honored): PRUSAMINI_SKIP_MAIN
function Sync-3DPConsoleLegacySkipMainEnv {
    if ($env:PRUSAMINI_SKIP_MAIN -eq '1') { $env:THREEDP_CONSOLE_SKIP_MAIN = '1' }
}
Sync-3DPConsoleLegacySkipMainEnv
#endregion

# =============================================================================
# INHALTSVERZEICHNIS (VS Code / Cursor: #region einklappen)
#   01-EarlyExit     Parameter, -Help / -About / -Example
#   02-LoadLib       Pfade + foreach dot-source der Fragmente unter .\lib\ (nicht aus function!)
#
# Fragmente (gleicher Ordner wie diese Datei, Unterordner lib\):
#   lib\3DP-Console.Init.ps1       Encoding, Ports, Config-Template, G/M-Palette-Daten
#   lib\3DP-Console.Commands.ps1   UI-Helfer, Slash-Handler, MaxVisible, Palette-Logik
#   lib\3DP-Console.PaletteUI.ps1  UI-Rendering, Invoke-CommandPalette
#   lib\3DP-Console.Mesh.ps1       Timeouts, Temperatur, Mesh-Parsing
#   lib\3DP-Console.Loops.ps1      Level-Compare, Temp2, Interactive, Invoke-Loop
#   lib\3DP-Console.Serial.ps1     Send-Gcode, Read-Serial*
#   lib\3DP-Console.Port.ps1       Port-Auswahl, Invoke-SingleCommand
#   lib\3DP-Console.MainCommand.ps1 Invoke-MainCommandLineMode (-Command)
#   lib\3DP-Console.Main.ps1       Main + Hauptschleife
# =============================================================================

#region 01-EarlyExit
# Manual parameter parsing (works in ConstrainedLanguage where param() fails).
# Extrahiert fuer Pester-Tests (gleicher Prozess, keine Skript-Re-Invocation).
function Invoke-3DPConsoleParseEarlyArgs {
    param([object[]]$ArgList = @())
    if ($null -eq $ArgList) { $ArgList = @() }
    $Help = $false; $About = $false; $Example = $false
    $ComPort = ''; $ConfigPath = ''; $Command = ''
    $i = 0
    while ($i -lt $ArgList.Count) {
        $a = $ArgList[$i]
        if ($a -eq '-Help' -or $a -eq '-h') { $Help = $true }
        elseif ($a -eq '-About') { $About = $true }
        elseif ($a -eq '-Example' -or $a -eq '-e') { $Example = $true }
        elseif ($a -eq '-ComPort' -and ($i + 1) -lt $ArgList.Count) { $i++; $ComPort = $ArgList[$i].ToString().Trim() }
        elseif ($a -eq '-ConfigPath' -and ($i + 1) -lt $ArgList.Count) { $i++; $ConfigPath = $ArgList[$i].ToString().Trim() }
        elseif ($a -eq '-Command' -and ($i + 1) -lt $ArgList.Count) { $i++; $Command = $ArgList[$i].ToString().Trim() }
        $i++
    }
    [pscustomobject]@{
        Help = $Help; About = $About; Example = $Example
        ComPort = $ComPort; ConfigPath = $ConfigPath; Command = $Command
    }
}

function Write-3DPConsoleAboutScreen {
    Write-Host ''
    Write-Host ('3DP-Console v' + $Script:Version) -ForegroundColor Cyan
    Write-Host '  Command Palette for 3D printers' -ForegroundColor Gray
    Write-Host '  Slash-Commands, G/M-Palette, Loops, Macros' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Config: 3DP-Config.ps1 (incl. Loops + Macros)' -ForegroundColor DarkGray
    Write-Host '  Tests:  src\tests\Test-All.ps1 -WithPort' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-3DPConsoleHelpScreen {
    Write-Host ''
    Write-Host '3DP-Console - G-Code console for 3D printers' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Usage:' -ForegroundColor White
    Write-Host '  .\src\3DP-Console.ps1              Start interactive console' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -Help        This help' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -About       Info and version' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -Example     Examples' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Parameters:' -ForegroundColor White
    Write-Host '  -Help       Show short help' -ForegroundColor Gray
    Write-Host '  -About      Show script info' -ForegroundColor Gray
    Write-Host '  -Example    Show examples' -ForegroundColor Gray
    Write-Host '  -ComPort    COM-Port override (e.g. COM3)' -ForegroundColor Gray
    Write-Host '  -ConfigPath Path to config file' -ForegroundColor Gray
    Write-Host '  -Command    Execute single command (no console): G28, G29, home, level, loop prepare, loop level_compare, ...' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'In console: Type /, G or M for commands. Esc=Cancel' -ForegroundColor DarkGray
}

function Write-3DPConsoleExampleScreen {
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  # Start console (interactive):' -ForegroundColor White
    Write-Host '  .\src\3DP-Console.ps1' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -ComPort COM3    # Port Override' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -ConfigPath .\MyConfig.ps1' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  # Execute single command (no interactive console):' -ForegroundColor White
    Write-Host '  .\src\3DP-Console.ps1 -ComPort COM3 -Command G28' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -ComPort COM3 -Command "loop level_compare"' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  # Help/Info before start:' -ForegroundColor White
    Write-Host '  .\src\3DP-Console.ps1 -Help' -ForegroundColor Gray
    Write-Host '  .\src\3DP-Console.ps1 -About' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  # PowerShell help (Comment-based):' -ForegroundColor White
    Write-Host '  Get-Help .\src\3DP-Console.ps1 -Full' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  # Run tests:' -ForegroundColor White
    Write-Host '  .\src\tests\Test-All.ps1 -WithPort' -ForegroundColor Gray
    Write-Host ''
}

function Invoke-3DPConsoleCliScreenExitIfNeeded {
    param([pscustomobject]$Parsed)
    if ($Parsed.About) { Write-3DPConsoleAboutScreen; return 0 }
    if ($Parsed.Help) { Write-3DPConsoleHelpScreen; return 0 }
    if ($Parsed.Example) { Write-3DPConsoleExampleScreen; return 0 }
    return $null
}

function Get-3DPConsoleScriptRoot {
    param(
        [string]$PSScriptRootHint = $PSScriptRoot,
        [string]$DotSourceScriptPath,
        [string]$PSCommandPathValue = $PSCommandPath
    )
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRootHint)) { return $PSScriptRootHint }
    if ($DotSourceScriptPath) { return Split-Path -Parent $DotSourceScriptPath }
    if ($PSCommandPathValue) { return Split-Path -Parent $PSCommandPathValue }
    return (Get-Location).ProviderPath
}

function Invoke-3DPConsoleProcessExitCode {
    param([int]$Code)
    $inv = $global:3DPConsoleExitInvoker
    if ($null -eq $inv) {
        # Pester: ohne Invoker wuerde exit den Host beenden — Testmodus wirft stattdessen.
        if ($env:THREEDP_CONSOLE_TEST_THROW_ON_EXIT -eq '1') {
            throw "3DPConsoleTestExit:$Code"
        }
        exit $Code
    }
    & $inv $Code
}

function Invoke-3DPConsoleEarlyCliGate {
    param([object[]]$ArgList = @())
    $early = Invoke-3DPConsoleParseEarlyArgs -ArgList $ArgList
    $cliExit = Invoke-3DPConsoleCliScreenExitIfNeeded -Parsed $early
    if ($null -ne $cliExit) {
        Invoke-3DPConsoleProcessExitCode -Code ([int]$cliExit)
        return @{ Stop = $true; Parsed = $early }
    }
    return @{ Stop = $false; Parsed = $early }
}

$_gate = Invoke-3DPConsoleEarlyCliGate -ArgList $args
if ($_gate.Stop) { return }
$_early = $_gate.Parsed
$Help = $_early.Help
$About = $_early.About
$Example = $_early.Example
$ComPort = $_early.ComPort
$ConfigPath = $_early.ConfigPath
$Command = $_early.Command
#endregion 01-EarlyExit

#region 02-LoadLib
# Root of THIS entry script (not lib\); required before sourcing fragments.
$_dotSourcePath = $MyInvocation.MyCommand.Path
$Script:ConsoleRoot = Get-3DPConsoleScriptRoot -PSScriptRootHint $PSScriptRoot -DotSourceScriptPath $_dotSourcePath -PSCommandPathValue $PSCommandPath

$Script:LibPath = Join-Path $Script:ConsoleRoot 'lib'
# WICHTIG: Fragmente NICHT aus einer function heraus dot-sourcen — sonst landen
# Funktionen im Funktions-Scope und sind nach dem Return weg (Tests schlagen fehl).
$Script:3DPConsoleFragmentNames = @(
    '3DP-Console.Init.ps1'
    '3DP-Console.Commands.ps1'
    '3DP-Console.PaletteUI.ps1'
    '3DP-Console.Mesh.ps1'
    '3DP-Console.Loops.ps1'
    '3DP-Console.Serial.ps1'
    '3DP-Console.Port.ps1'
    '3DP-Console.MainCommand.ps1'
    '3DP-Console.Main.ps1'
)

function Write-3DPConsoleMissingFragmentError {
    param([string]$FullPath)
    Write-Host "  ERROR: Missing fragment: $FullPath" -ForegroundColor Red
}

function Invoke-3DPConsoleAbortOnMissingFragment {
    param([string]$FullPath)
    Write-3DPConsoleMissingFragmentError -FullPath $FullPath
    Invoke-3DPConsoleProcessExitCode -Code 1
}

foreach ($fragName in $Script:3DPConsoleFragmentNames) {
    $full = Join-Path $Script:LibPath $fragName
    if (-not (Test-Path -LiteralPath $full)) {
        Invoke-3DPConsoleAbortOnMissingFragment -FullPath $full
        return
    }
    . $full
}

#endregion 02-LoadLib

#region 99-EntryPoint
function Invoke-3DPConsoleMainEntryIfEnabled {
    if ($env:THREEDP_CONSOLE_SKIP_MAIN -eq '1') { return $null }
    $mainExit = & Main
    if ($mainExit -is [int] -and $mainExit -ne 0) { return $mainExit }
    return 0
}

function Invoke-3DPConsoleMainExitGate {
    $mainExit = Invoke-3DPConsoleMainEntryIfEnabled
    if ($null -ne $mainExit) {
        $exitCode = if ($mainExit -is [int] -and $mainExit -ne 0) { [int]$mainExit } else { 0 }
        Invoke-3DPConsoleProcessExitCode -Code $exitCode
        return $true
    }
    return $false
}

# ENTRY POINT (skipped when THREEDP_CONSOLE_SKIP_MAIN=1, e.g. tests\Test-All.ps1)
if (Invoke-3DPConsoleMainExitGate) { return }
#endregion 99-EntryPoint
