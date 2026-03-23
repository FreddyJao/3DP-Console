<#
    Fragment: 3DP-Console.MainCommand.ps1
    Sourced by 3DP-Console.ps1 only (vor 3DP-Console.Main.ps1).
#>

# =============================================================================
# 13a. MAIN: -Command mode (one-shot, no palette)
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

# Called from the embedded RunCommand script block — Pester mocks apply (no direct Invoke-SingleCommand call in the SB).
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
        Start-3DPConsoleSessionTranscript -ComPort $ChosenPort
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
    # Pester: mock does not reliably apply inside embedded script blocks → optional hook (same process).
    $runSingle = if ($null -ne $global:3DPConsoleMainCommandRunSingleCommandScript) {
        $global:3DPConsoleMainCommandRunSingleCommandScript
    } else {
        { param($p, $cmd) Invoke-MainCommandLineModeDefaultRunSingle -Port $p -CmdLine $cmd }
    }
    return Invoke-MainCommandLineModeCore -ChosenPort $chosenPort -CommandLine $CommandLine `
        -NewPortScript { param($n) New-3DPConsoleSerialPort -PortName $n } `
        -RunCommandScript $runSingle
}

# Strip blank lines and #-comments (unit-test friendly).
function Get-3DPConsoleNormalizedBatchCommandLines {
    param([string[]]$RawLines)
    if ($null -eq $RawLines) { return [string[]]@() }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in $RawLines) {
        if ($null -eq $raw) { continue }
        $t = $raw.Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('#')) { continue }
        $out.Add($t)
    }
    return [string[]]$out.ToArray()
}

function Invoke-MainCommandBatchModeDefaultRun {
    param(
        $Port,
        [string[]]$Cmds
    )
    foreach ($c in $Cmds) {
        if (-not (Invoke-SingleCommand -Port $Port -Cmd $c)) { return 1 }
    }
    return 0
}

function Invoke-MainCommandBatchModeCore {
    param(
        [string[]]$NormalizedCommands,
        [string]$ChosenPort,
        [scriptblock]$NewPortScript,
        [scriptblock]$RunBatchScript
    )
    $port = $null
    try {
        $port = & $NewPortScript $ChosenPort
        $port.Open()
        Start-3DPConsoleSessionTranscript -ComPort $ChosenPort
        $exit = & $RunBatchScript $port $NormalizedCommands
        return [int]$exit
    } catch {
        Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
        return 1
    } finally {
        if ($port -and $port.IsOpen) { try { $port.Close(); $port.Dispose() } catch { } }
    }
}

function Invoke-MainCommandBatchMode {
    param(
        [string[]]$RawLines,
        [string]$ConfigPath
    )
    $cmds = @(Get-3DPConsoleNormalizedBatchCommandLines -RawLines $RawLines)
    if ($cmds.Count -eq 0) {
        Write-Host '  Error: No commands in batch (empty stdin/file or only blanks/comments).' -ForegroundColor Red
        return 1
    }
    $chosenPort = Get-PortOrRetry -ConfigPath $ConfigPath -ForceShowSelection:$false
    if (-not $chosenPort) {
        Write-Host '  Error: No COM port available.' -ForegroundColor Red
        return 1
    }
    $runBatch = if ($null -ne $global:3DPConsoleMainCommandBatchRunScript) {
        $global:3DPConsoleMainCommandBatchRunScript
    } else {
        { param($p, $a) Invoke-MainCommandBatchModeDefaultRun -Port $p -Cmds $a }
    }
    Write-Host ('  Batch: ' + $cmds.Count + ' command(s)') -ForegroundColor DarkGray
    return Invoke-MainCommandBatchModeCore -NormalizedCommands $cmds -ChosenPort $chosenPort `
        -NewPortScript { param($n) New-3DPConsoleSerialPort -PortName $n } `
        -RunBatchScript $runBatch
}
