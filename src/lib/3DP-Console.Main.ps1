<#
    Fragment: 3DP-Console.Main.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# =============================================================================
# 13. MAIN (Hauptschleife, Action-Dispatch)
# =============================================================================
# Hinweis: -Command-Pfad liegt in 3DP-Console.MainCommand.ps1 (Invoke-MainCommandLineMode).

function Main {
    $configPath = Join-Path $Script:BasePath "3DP-Config.ps1"

    # -Command: Execute once and exit (no interactive console)
    if ($Command -and $Command.Trim()) {
        return (Invoke-MainCommandLineMode -CommandLine $Command -ConfigPath $configPath)
    }

    $port = $null
    while ($true) {
        $chosenPort = Get-PortOrRetry -ConfigPath $configPath
        if ($null -eq $chosenPort) {
            Write-Host ''
            Write-Host (Get-UIString 'ExitMessage') -ForegroundColor Cyan
            return 1
        }

        $port = $null
        $comPort = if ($Script:Config.ComPort) { $Script:Config.ComPort.Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($comPort)) {
            Write-Host '  Error: ComPort not set in config.' -ForegroundColor Red
            Read-Host '  [Enter] back to port selection'
            continue
        }
        try {
            $port = New-Object System.IO.Ports.SerialPort $comPort, $Script:Config.BaudRate, None, 8, One
            $port.Open()
        } catch {
            try { [Console]::Clear() } catch { Clear-Host }
            Write-Host ''
            Write-Host (Get-UIString 'ConsoleTitle') -ForegroundColor Cyan
            Write-Host ''
            Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
            Write-Host ''
            Write-Host '  Port could not be opened.' -ForegroundColor Yellow
            Write-Host '  Check USB cable, close other programs (Pronterface, PrusaSlicer).' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  [Enter] Reconnect   [p] Port selection' -ForegroundColor DarkGray
            Write-Host ''
            $key = $null
            try {
                try { $key = [Console]::ReadKey($true) } catch { $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
            } catch {
                $input = Read-Host '  Input'
                if ($input.Trim().ToLower() -eq 'p') {
                    $chosenPort = Get-PortOrRetry -ConfigPath $configPath -ForceShowSelection
                    if ($null -eq $chosenPort) { Write-Host ''; Write-Host (Get-UIString 'ExitMessage') -ForegroundColor Cyan; return 1 }
                }
                continue
            }
            if ($port) { try { if ($port.IsOpen) { $port.Close() }; $port.Dispose() } catch { } }
            if ($key -and ($key.KeyChar -eq 'p' -or $key.KeyChar -eq 'P')) {
                $chosenPort = Get-PortOrRetry -ConfigPath $configPath -ForceShowSelection
                if ($null -eq $chosenPort) {
                    Write-Host ''
                    Write-Host (Get-UIString 'ExitMessage') -ForegroundColor Cyan
                    return 1
                }
            }
            continue
        }

        try {
        while ($true) {
            try { [Console]::Clear() } catch { Clear-Host }
            $chosen = Invoke-CommandPalette -PortRef ([ref]$port)
            if ($null -eq $chosen) { continue }

            $trimmed = $chosen.cmd.Trim().ToLower()
            if ($trimmed -in 'quit','exit','q') {
                if ($port -and $port.IsOpen) {
                    Write-Host '  Turn off heater, close connection?' -ForegroundColor Yellow
                    if (Invoke-Confirm -Prompt '  y/n') {
                        Send-Gcode -Port $port -Gcode "M104 S0`nM140 S0" | Out-Null
                        Start-Sleep -Milliseconds 500
                    }
                }
                break
            }

            if ($trimmed -match '^loop\s+(.+)$') {
                $rest = $Matches[1].Trim()
                $parts = $rest -split '\s+'
                $loopName = $rest
                $loopCount = 0
                if ($parts.Count -ge 2) {
                    $last = $parts[-1]
                    $num = 0
                    if ([int]::TryParse($last, [ref]$num) -and $num -ge 1) {
                        $loopCount = $num
                        $loopName = ($parts[0..($parts.Count - 2)] -join ' ').Trim()
                    }
                }
                if ($port) {
                    try { [Console]::Clear() } catch { Clear-Host }
                    Invoke-Loop -Port $port -LoopName $loopName -RepeatCount $loopCount
                } else { Write-Host '  No connection.' -ForegroundColor Red }
                Write-Host ''
                Read-Host '  [Enter] to continue'
                continue
            }

            $q = $Script:QuickActions | Where-Object { $_.key -eq $trimmed } | Select-Object -First 1
            if ($q) {
                if (-not $port) { Write-Host '  No connection. Back to palette (r=Reconnect)' -ForegroundColor Red; Read-Host '  [Enter]'; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $lineCount = Send-Gcode -Port $port -Gcode $q.gcode
                $null = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $q.gcode) -ExpectedOkCount $lineCount
                Write-Host ''
                Read-Host '  [Enter] to continue'
                continue
            }

            if ($chosen.direct) {
                if (-not $port) { Write-Host '  No connection. Back to palette (r=Reconnect)' -ForegroundColor Red; Read-Host '  [Enter]'; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $lineCount = Send-Gcode -Port $port -Gcode $chosen.cmd
                $null = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $chosen.cmd) -ExpectedOkCount $lineCount
                Write-Host ''
                Read-Host '  [Enter] to continue'
                continue
            }

            if ($chosen.action -eq 'help') {
                Write-Host ('  ' + (Get-UIString 'HelpText')) -ForegroundColor Cyan
                Read-Host '  [Enter] to continue'
                continue
            }
            if ($chosen.action -eq 'home') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/home'
                Invoke-HomeAxes -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'preset_pla') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                $g = "M104 S$($Script:Config.PLA_Hotend)`nM140 S$($Script:Config.PLA_Bed)"
                try { [Console]::Clear() } catch { Clear-Host }
                $lc = Send-Gcode -Port $port -Gcode $g
                $null = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'preset_abs') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                $g = "M104 S$($Script:Config.ABS_Hotend)`nM140 S$($Script:Config.ABS_Bed)"
                try { [Console]::Clear() } catch { Clear-Host }
                $lc = Send-Gcode -Port $port -Gcode $g
                $null = Read-SerialResponse -Port $port -Ms 5000 -ExpectedOkCount $lc
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'move') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/move'
                Invoke-Move -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'extrude') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/extrude'
                Invoke-Extrude -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'reverse') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/reverse'
                Invoke-Reverse -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'monitor') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/monitor'
                Invoke-Monitor -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'sd_ls') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                Invoke-SdLs -Port $port
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'sd_print') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/sdprint'
                Invoke-SdPrint -Port $port -Filename ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'macro') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $args = Get-SlashCommandArgs -Cmd $chosen.cmd -Prefix '/macro'
                Invoke-Macro -Port $port -Args ($args -join ' ')
                Write-Host ''; Read-Host '  [Enter] to continue'; continue
            }
            if ($chosen.action -eq 'g' -or $chosen.action -eq 'm') {
                $subBuffer = if ($chosen.action -eq 'g') { 'g' } else { 'm' }
                $subChosen = Invoke-CommandPalette -PortRef ([ref]$port) -InitialBuffer $subBuffer
                if ($subChosen -and $subChosen.cmd -match '^[GM]\d') {
                    $toSend = $subChosen.cmd
                    if ($subChosen.cmd -match '^M(104|109|140|190)$') {
                        try { [Console]::Clear() } catch { Clear-Host }
                        Write-Host ('  ' + $subChosen.cmd + ' - Temperature parameter') -ForegroundColor Cyan
                        Write-Host ''
                        $param = Read-Host '  Enter parameter (e.g. S170 for temperature)'
                        if ($param) { $toSend = $subChosen.cmd + ' ' + $param.Trim() }
                    }
                    if ($port) {
                        try { [Console]::Clear() } catch { Clear-Host }
                        $lineCount = Send-Gcode -Port $port -Gcode $toSend
                        $null = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $toSend) -ExpectedOkCount $lineCount
                    } else { Write-Host '  No connection.' -ForegroundColor Red; Read-Host '  [Enter]' }
                }
                Write-Host ''
                Read-Host '  [Enter] to continue'
                continue
            }
            if ($chosen.gcode) {
                if (-not $port) { Write-Host '  No connection. Back to palette (r=Reconnect)' -ForegroundColor Red; Read-Host '  [Enter]'; continue }
                try { [Console]::Clear() } catch { Clear-Host }
                $lineCount = Send-Gcode -Port $port -Gcode $chosen.gcode
                $null = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $chosen.gcode) -ExpectedOkCount $lineCount
                Write-Host ''
                Read-Host '  [Enter] to continue'
                continue
            }
            if ($chosen.cmd -match '^[GM]\d') {
                if (-not $port) { Write-Host '  No connection.' -ForegroundColor Red; Read-Host '  [Enter]'; continue }
                $toSend = $chosen.cmd
                if ($chosen.cmd -match '^M(104|109|140|190)$') {
                    try { [Console]::Clear() } catch { Clear-Host }
                    Write-Host ('  ' + $chosen.cmd + ' - Temperature parameter') -ForegroundColor Cyan
                    Write-Host ''
                    $param = Read-Host '  Enter parameter (e.g. S170 for temperature)'
                    if ($param) { $toSend = $chosen.cmd + ' ' + $param.Trim() }
                }
                try { [Console]::Clear() } catch { Clear-Host }
                $lineCount = Send-Gcode -Port $port -Gcode $toSend
                $null = Read-SerialResponse -Port $port -Ms (Get-GcodeTimeout $toSend) -ExpectedOkCount $lineCount
                Write-Host ''
                Read-Host '  [Enter] to continue'
            }
        }

        Write-Host ''
        Write-Host (Get-UIString 'ExitMessage') -ForegroundColor Cyan
        break
        } catch {
            $msg = $_.Exception.Message
            try { [Console]::Clear() } catch { Clear-Host }
            Write-Host ''
            Write-Host (Get-UIString 'ConsoleTitle') -ForegroundColor Cyan
            Write-Host ''
            Write-Host ('  Fehler: ' + $msg) -ForegroundColor Red
            Write-Host ''
            if ($msg -match 'verweigert|denied|Zugriff') {
                Write-Host '  COM-Port wird bereits verwendet. Schliesse Pronterface, PrusaSlicer.' -ForegroundColor Yellow
            } else {
                Write-Host '  Der Anschluss konnte nicht geoeffnet werden.' -ForegroundColor Yellow
            }
            Write-Host ''
            Read-Host '  [Enter] back to port selection'
            if ($port -and $port.IsOpen) { try { $port.Close(); $port.Dispose() } catch { } }
            continue
        } finally {
            if ($port -and $port.IsOpen) { try { $port.Close(); $port.Dispose() } catch { } }
        }
    }
}
