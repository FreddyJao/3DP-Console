<#
    Fragment: 3DP-Console.Serial.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# 11. SERIAL-KOMMUNIKATION (Send-Gcode, Read-Serial)
# =============================================================================

# Zeilenpuffer nach CR/LF in fertige Zeilen + Rest (fuer Tests + gemeinsame Logik).
function Split-SerialLineBuffer {
    param([string]$Buffer)
    if ($null -eq $Buffer) { $Buffer = '' }
    $lines = $Buffer -split "[\r\n]+"
    if ($lines.Count -le 1) {
        $rem = if ($lines.Count -eq 1) { $lines[0] } else { '' }
        return @{ Complete = [string[]]@(); Remainder = $rem }
    }
    $complete = @($lines[0..($lines.Count - 2)])
    return @{ Complete = $complete; Remainder = $lines[-1] }
}

# ok/busy/wait-Zeilen nicht als Nutzer-Feedback ausgeben (wie in Read-Serial*).
function Test-SerialLineIsBusyOkIgnore {
    param([string]$Line)
    return [bool]($Line -match '^ok\s*\d*$|busy:\s*processing|busy:\s*heating|Active Extruder:\s*\d*$|^wait')
}

# Chunk an Zeilenpuffer anhaengen und fertige Zeilen zurueckgeben (Read-Serial* + Unit-Tests).
function Append-SerialChunkToLineBuffer {
    param(
        [ref]$Buffer,
        [string]$Chunk
    )
    if ($null -ne $Chunk -and $Chunk.Length -gt 0) {
        $Buffer.Value += $Chunk
    }
    $split = Split-SerialLineBuffer -Buffer $Buffer.Value
    $Buffer.Value = $split.Remainder
    return , @($split.Complete)
}

function Send-Gcode {
    param([System.IO.Ports.SerialPort]$Port, [string]$Gcode, [scriptblock]$HostCommandCallback)
    if ($Gcode -match '\bM112\b') {
        Write-Host '  EMERGENCY STOP (M112) - really execute?' -ForegroundColor Red
        if (-not (Invoke-Confirm -Prompt '  y/n')) { return 0 }
    }
    $lineCount = 0
    foreach ($line in ($Gcode -split "`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith(';@')) {
            $hostCmd = $line.Substring(2).Trim()
            Write-Host ('  Host command: ' + $hostCmd) -ForegroundColor DarkCyan
            if ($HostCommandCallback) { & $HostCommandCallback $hostCmd } else {
                if ($hostCmd -eq 'pause') { Read-Host '  [Enter] to continue' }
            }
            continue
        }
        if ($line.StartsWith(';')) { continue }
        Write-Host ('SENDING: ' + $line) -ForegroundColor Green
        $Port.WriteLine($line)
        $lineCount++
        Start-Sleep -Milliseconds 150
    }
    return $lineCount
}

function Invoke-GcodeAndWaitOrAbort {
    param(
        [System.IO.Ports.SerialPort]$Port,
        [string]$Gcode,
        [string]$AbortMessage = '  [Abgebrochen]'
    )
    $lineCount = Send-Gcode -Port $Port -Gcode $Gcode
    $ok = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $Gcode) -ExpectedOkCount $lineCount -AllowAbort -Silent
    if (-not $ok) {
        Write-Host $AbortMessage -ForegroundColor Red
        return $false
    }
    return $true
}

function Read-SerialAndCapture {
    param([System.IO.Ports.SerialPort]$Port, [int]$Ms = 10000, [int]$ExpectedOkCount = 1, [switch]$AllowAbort, [switch]$Silent)
    $ExpectedOkCount = [Math]::Max(1, $ExpectedOkCount)
    $prevReadTimeout = $Port.ReadTimeout
    $Port.ReadTimeout = 5000
    $start = Get-Date
    $okCount = 0
    $lastDataTime = $start
    $lineBuffer = ''
    $collected = [System.Text.StringBuilder]::new()
    $hadError = $false
    while (((Get-Date) - $start).TotalMilliseconds -lt $Ms) {
        # Ohne diese Abfrage: in IDE/Headless faellt KeyAvailable+ReadKey oft falsch aus (Abgebrochen / Haenger).
        if ($AllowAbort -and $env:THREEDP_CONSOLE_SKIP_MAIN -ne '1') {
            $key = $null
            try { if ([Console]::KeyAvailable) { try { $key = [Console]::ReadKey($true) } catch { } } } catch { }
            if ($key -and $key.Key -eq 'Escape') {
                $Port.ReadTimeout = $prevReadTimeout
                if (-not $Silent) { Write-Host '  [Abgebrochen]' -ForegroundColor Yellow }
                return $null
            }
        }
        try {
            $chunk = $null
            if ($Port.BytesToRead -gt 0) {
                $chunk = $Port.ReadExisting()
                $lastDataTime = Get-Date
            }
            $completeLines = Append-SerialChunkToLineBuffer -Buffer ([ref]$lineBuffer) -Chunk $chunk
            foreach ($lineRaw in $completeLines) {
                $line = $lineRaw.Trim()
                if ($line) {
                    [void]$collected.AppendLine($line)
                    if ($line -match 'Error|!!') { $hadError = $true }
                    if ($line -match '^ok') { $okCount++ }
                    if (-not $Silent -and $okCount -lt $ExpectedOkCount) {
                        $ignore = Test-SerialLineIsBusyOkIgnore -Line $line
                        if (-not $ignore) {
                            $tempFormatted = Format-TemperatureReport -Line $line
                            if ($tempFormatted -and $tempFormatted.Count -gt 0) {
                                foreach ($t in $tempFormatted) { Write-Host $t -ForegroundColor Cyan }
                            } else {
                                $display = if ($line -match '^echo:') { $line -replace '^echo:\s*','' } else { $line }
                                $color = if ($line -match 'Error|!!') { 'Red' } elseif ($line -match '^ok') { 'Cyan' } else { 'DarkGray' }
                                Write-Host ('  ' + $display) -ForegroundColor $color
                            }
                        }
                    }
                    if ($okCount -ge $ExpectedOkCount) {
                        $Port.ReadTimeout = $prevReadTimeout
                        return $collected.ToString()
                    }
                }
            }
            if ($hadError) { $Port.ReadTimeout = $prevReadTimeout; return $null }
        } catch {
            $Port.ReadTimeout = $prevReadTimeout
            throw
        }
        if ($Port.BytesToRead -eq 0 -and (((Get-Date) - $lastDataTime).TotalMilliseconds -gt 500) -and $okCount -gt 0) {
            $Port.ReadTimeout = $prevReadTimeout
            return $collected.ToString()
        }
        Start-Sleep -Milliseconds 20
    }
    $Port.ReadTimeout = $prevReadTimeout
    return $collected.ToString()
}

function Read-SerialResponse {
    param([System.IO.Ports.SerialPort]$Port, [int]$Ms = 10000, [int]$ExpectedOkCount = 1, [switch]$AllowAbort, [switch]$Silent)
    $ExpectedOkCount = [Math]::Max(1, $ExpectedOkCount)
    $prevReadTimeout = $Port.ReadTimeout
    $Port.ReadTimeout = 5000
    $start = Get-Date
    $okCount = 0
    $lastDataTime = $start
    $lineBuffer = ''
    $hadError = $false
    while (((Get-Date) - $start).TotalMilliseconds -lt $Ms) {
        if ($AllowAbort -and $env:THREEDP_CONSOLE_SKIP_MAIN -ne '1') {
            $key = $null
            try {
                if ([Console]::KeyAvailable) {
                    try { $key = [Console]::ReadKey($true) } catch { }
                }
            } catch { }
            if ($key -and $key.Key -eq 'Escape') {
                $Port.ReadTimeout = $prevReadTimeout
                if (-not $Silent) { Write-Host '  [Abgebrochen]' -ForegroundColor Yellow }
                return $false
            }
        }
        try {
            $chunk = $null
            if ($Port.BytesToRead -gt 0) {
                $chunk = $Port.ReadExisting()
                $lastDataTime = Get-Date
            }
            $completeLines = Append-SerialChunkToLineBuffer -Buffer ([ref]$lineBuffer) -Chunk $chunk
            foreach ($lineRaw in $completeLines) {
                $line = $lineRaw.Trim()
                if ($line) {
                    if ($line -match 'Error|!!') { $hadError = $true }
                    if ($line -match '^ok') {
                        $okCount++
                        if ($okCount -ge $ExpectedOkCount) {
                            $Port.ReadTimeout = $prevReadTimeout
                            return (-not $hadError)
                        }
                    }
                    $ignore = Test-SerialLineIsBusyOkIgnore -Line $line
                    if (-not $ignore) {
                        $tempFormatted = Format-TemperatureReport -Line $line
                        if ($tempFormatted -and $tempFormatted.Count -gt 0) {
                            foreach ($t in $tempFormatted) { Write-Host $t -ForegroundColor Cyan }
                        } else {
                            $display = if ($line -match '^echo:') { $line -replace '^echo:\s*','' } else { $line }
                            $color = if ($line -match 'Error|!!') { 'Red' } elseif ($line -match '^ok') { 'Cyan' } else { 'DarkGray' }
                            Write-Host ('  ' + $display) -ForegroundColor $color
                        }
                    }
                }
            }
            if ($hadError) {
                $Port.ReadTimeout = $prevReadTimeout
                return $false
            }
        } catch {
            $Port.ReadTimeout = $prevReadTimeout
            throw
        }
        if ($Port.BytesToRead -eq 0 -and (((Get-Date) - $lastDataTime).TotalMilliseconds -gt 500) -and $okCount -gt 0) {
            $Port.ReadTimeout = $prevReadTimeout
            return (-not $hadError)
        }
        Start-Sleep -Milliseconds 20
    }
    $Port.ReadTimeout = $prevReadTimeout
    return (-not $hadError)
}

