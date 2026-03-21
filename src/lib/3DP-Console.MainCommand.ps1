<#
    Fragment: 3DP-Console.MainCommand.ps1
    Sourced by 3DP-Console.ps1 only (vor 3DP-Console.Main.ps1).
#>

# =============================================================================
# 13a. MAIN: -Command-Modus (einmalig, ohne Palette)
# =============================================================================

function New-3DPConsoleSerialPort {
    param([string]$PortName)
    return [System.IO.Ports.SerialPort]::new(
        $PortName,
        $Script:Config.BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
}

# Wird vom eingebetteten RunCommand-ScriptBlock aufgerufen — so greifen Pester-Mocks (kein direkter Aufruf von Invoke-SingleCommand im SB).
function Invoke-MainCommandLineModeDefaultRunSingle {
    param(
        [System.IO.Ports.SerialPort]$Port,
        [string]$CmdLine
    )
    Invoke-SingleCommand -Port $Port -Cmd $CmdLine | Out-Null
}

function Invoke-MainCommandLineModeCore {
    param(
        [string]$ChosenPort,
        [string]$CommandLine,
        [scriptblock]$NewPortScript,
        [scriptblock]$RunCommandScript
    )
    $port = $null
    try {
        $port = & $NewPortScript $ChosenPort
        $port.Open()
        Write-Host ('  Connected to ' + $ChosenPort + ' -> ' + $CommandLine.Trim()) -ForegroundColor Cyan
        & $RunCommandScript $port $CommandLine
    } catch {
        Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
        return 1
    } finally {
        if ($port -and $port.IsOpen) { try { $port.Close(); $port.Dispose() } catch { } }
    }
    return 0
}

function Invoke-MainCommandLineMode {
    param([string]$CommandLine, [string]$ConfigPath)
    $chosenPort = Get-PortOrRetry -ConfigPath $ConfigPath -ForceShowSelection:$false
    if (-not $chosenPort) {
        Write-Host '  Error: No COM port available.' -ForegroundColor Red
        return 1
    }
    # Pester: Mock greift in eingebetteten ScriptBlocks nicht zuverlässig → optionaler Hook (gleicher Prozess).
    $runSingle = if ($null -ne $global:3DPConsoleMainCommandRunSingleCommandScript) {
        $global:3DPConsoleMainCommandRunSingleCommandScript
    } else {
        { param($p, $cmd) Invoke-MainCommandLineModeDefaultRunSingle -Port $p -CmdLine $cmd }
    }
    return Invoke-MainCommandLineModeCore -ChosenPort $chosenPort -CommandLine $CommandLine `
        -NewPortScript { param($n) New-3DPConsoleSerialPort -PortName $n } `
        -RunCommandScript $runSingle
}
