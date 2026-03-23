<#
.SYNOPSIS
    Example config: other G-code printer (e.g. Marlin) with minimal overrides.

.DESCRIPTION
    From repository root, PowerShell:

        .\src\3DP-Console.ps1 -ConfigPath .\3DP-Config.Marlin-Example.ps1
        .\src\3DP-Console.ps1 -ConfigPath .\src\3DP-Config.Marlin-Example.ps1 -ComPort COM5

    This file sets only ComPort and BaudRate. All other keys (loops, palettes, timeouts,
    temperatures) come from built-in defaults in 3DP-Console — same structure as when
    3DP-Config.ps1 is missing (see src\lib\3DP-Console.Init.ps1).

    Workflow for a different printer:
    1. Adjust ComPort and BaudRate here (or in a copy of this file).
    2. If homing / bed level / SD differ from Prusa: copy src\3DP-Config.ps1 to MyPrinter.ps1
       and edit loops, SlashCommands, and macros there (full 3DP-Config.ps1 remains the reference).

    Baud rate: often 115200 or 250000 (Marlin over USB). If you see garbage or timeouts, try
    another rate; a hint may also appear in the console after a command times out.
#>

@{
    ComPort  = "COM3"
    BaudRate = 115200
}
