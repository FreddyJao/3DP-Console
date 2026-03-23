<#
    Fragment: 3DP-Console.Port.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# 12. PORT MANAGEMENT (config update, COM port selection)
# =============================================================================

function Update-ConfigComPort {
    param([string]$ConfigPath, [string]$NewComPort)
    if (-not (Test-Path $ConfigPath)) { return $false }
    try {
        $content = Get-Content $ConfigPath -Raw -Encoding UTF8
        $content = $content -replace '(\s*ComPort\s*=\s*")[^"]*(")', "`${1}$NewComPort`$2"
        Set-Content -Path $ConfigPath -Value $content -Encoding UTF8 -NoNewline:$false
        return $true
    } catch { return $false }
}

# For Pester: mock replaces this so WMI fallback can be tested.
function Get-3DPSerialPortNativeNames {
    return [System.IO.Ports.SerialPort]::GetPortNames()
}

function Get-ComPortsFromPnpWmi {
    $classGuid = '{4d36e978-e325-11ce-bfc1-08002be10318}'
    $devices = Get-WmiObject -Class Win32_PnPEntity -Filter "ClassGuid='$classGuid'" -ErrorAction SilentlyContinue
    $comPorts = @()
    if ($devices) {
        foreach ($d in $devices) {
            if ($d.Name -match '\((COM\d+)\)') { $comPorts += $Matches[1] }
        }
    }
    return @(if ($comPorts.Count -gt 0) { $comPorts | Sort-Object -Unique } else { @() })
}

function Get-AvailableComPorts {
    try {
        $names = Get-3DPSerialPortNativeNames
        $ports = @(if ($names) { $names | Sort-Object } else { @() })
        if ($ports.Count -gt 0) { return $ports }
    } catch { }
    try {
        return @(Get-ComPortsFromPnpWmi)
    } catch { return @() }
}

function Get-PortOrRetry {
    param([string]$ConfigPath, [switch]$ForceShowSelection)
    while ($true) {
        $ports = @(Get-AvailableComPorts)
        if ($null -eq $ports) { $ports = @() }
        if (-not $ForceShowSelection -and $ports -contains $Script:Config.ComPort) {
            return $Script:Config.ComPort
        }
        try { [Console]::Clear() } catch { Clear-Host }
        Write-Host ''
        Write-Host (Get-UIString 'ConsoleTitle') -ForegroundColor Cyan
        Write-Host ''
        if ($ForceShowSelection) {
            Write-Host ('  ' + $Script:Config.ComPort + ' could not be opened.') -ForegroundColor Red
        } else {
            Write-Host ('  COM port ' + $Script:Config.ComPort + ' not found.') -ForegroundColor Red
        }
        Write-Host ''
        if ($ports.Count -eq 0) {
            Write-Host '  No COM ports found.' -ForegroundColor Yellow
            Write-Host '  Check USB cable, turn on printer.' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  [Enter] Retry   [q] Exit' -ForegroundColor DarkGray
        } else {
            Write-Host '  Available COM ports:' -ForegroundColor Yellow
            for ($i = 0; $i -lt $ports.Count; $i++) {
                Write-Host ('    [' + ($i + 1) + '] ' + $ports[$i]) -ForegroundColor White
            }
            Write-Host ''
            $rangeHint = if ($ports.Count -eq 1) { '1' } else { ('1-' + $ports.Count) }
            Write-Host ('  [Enter] Retry   [' + $rangeHint + '] Select port   [q] Exit') -ForegroundColor DarkGray
        }
        Write-Host ''
        $input = Read-Host '  Input'
        if ($input.Trim().ToLower() -eq 'q') {
            return $null
        }
        if ([string]::IsNullOrWhiteSpace($input)) {
            continue
        }
        $num = 0
        if ([int]::TryParse($input.Trim(), [ref]$num) -and $num -ge 1 -and $num -le $ports.Count) {
            $chosen = $ports[$num - 1]
            $Script:Config.ComPort = $chosen
            if (Update-ConfigComPort -ConfigPath $ConfigPath -NewComPort $chosen) {
                Write-Host ('  Config saved: ' + $chosen) -ForegroundColor Green
                Start-Sleep -Milliseconds 800
            }
            return $chosen
        }
    }
}

# Executes a single command (for -Command, no interactive console)
function Invoke-SingleCommand {
    param([System.IO.Ports.SerialPort]$Port, [string]$Cmd)
    $t = $Cmd.Trim().ToLower()
    if (-not $t) { Write-Host '  -Command is empty.' -ForegroundColor Yellow; return $false }

    # QuickActions (home, level, off, temp, fan, d, b, dw, bw)
    $q = $Script:QuickActions | Where-Object { $_.key -eq $t } | Select-Object -First 1
    if ($q) {
        $lineCount = Send-Gcode -Port $Port -Gcode $q.gcode
        $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $q.gcode) -ExpectedOkCount $lineCount
        Write-Host ('  [OK] ' + $Cmd) -ForegroundColor Green
        return $true
    }

    # loop <name> [n]
    if ($t -match '^loop\s+(.+)$') {
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
        Invoke-Loop -Port $Port -LoopName $loopName -RepeatCount $loopCount
        return $true
    }

    # Slash-Commands
    if ($t -match '^/home(\s+(.*))?$') {
        $axes = if ($Matches[2]) { $Matches[2].Trim() } else { 'xyz' }
        Invoke-HomeAxes -Port $Port -Args $axes
        return $true
    }
    if ($t -eq '/level') {
        $lc = Send-Gcode -Port $Port -Gcode 'G29'
        $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout 'G29') -ExpectedOkCount $lc
        Write-Host '  [OK] G29' -ForegroundColor Green
        return $true
    }
    if ($t -eq '/temp') {
        $lc = Send-Gcode -Port $Port -Gcode 'M105'
        $null = Read-SerialResponse -Port $Port -Ms 5000 -ExpectedOkCount $lc
        return $true
    }
    if ($t -match '^/pla$') {
        $g = "M104 S$($Script:Config.PLA_Hotend)`nM140 S$($Script:Config.PLA_Bed)"
        $lc = Send-Gcode -Port $Port -Gcode $g
        $null = Read-SerialResponse -Port $Port -Ms 5000 -ExpectedOkCount $lc
        Write-Host '  [OK] /pla' -ForegroundColor Green
        return $true
    }
    if ($t -match '^/abs$') {
        $g = "M104 S$($Script:Config.ABS_Hotend)`nM140 S$($Script:Config.ABS_Bed)"
        $lc = Send-Gcode -Port $Port -Gcode $g
        $null = Read-SerialResponse -Port $Port -Ms 5000 -ExpectedOkCount $lc
        Write-Host '  [OK] /abs' -ForegroundColor Green
        return $true
    }
    if ($t -eq '/off') {
        $lc = Send-Gcode -Port $Port -Gcode "M104 S0`nM140 S0"
        $null = Read-SerialResponse -Port $Port -Ms 5000 -ExpectedOkCount $lc
        Write-Host '  [OK] Heater off' -ForegroundColor Green
        return $true
    }
    if ($t -match '^/move\s+(.+)$') {
        Invoke-Move -Port $Port -Args $Matches[1].Trim()
        return $true
    }
    if ($t -match '^/extrude\s+(.+)$') {
        Invoke-Extrude -Port $Port -Args $Matches[1].Trim()
        return $true
    }
    if ($t -match '^/reverse\s+(.+)$') {
        Invoke-Reverse -Port $Port -Args $Matches[1].Trim()
        return $true
    }

    # Raw G/M-Code
    if ($Cmd.Trim() -match '^[GM]\d') {
        $lineCount = Send-Gcode -Port $Port -Gcode $Cmd.Trim()
        $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $Cmd) -ExpectedOkCount $lineCount
        Write-Host ('  [OK] ' + $Cmd.Trim()) -ForegroundColor Green
        return $true
    }

    # Fallback: als G-Code senden
    $lineCount = Send-Gcode -Port $Port -Gcode $Cmd.Trim()
    $null = Read-SerialResponse -Port $Port -Ms (Get-GcodeTimeout $Cmd) -ExpectedOkCount $lineCount
    Write-Host ('  [OK] ' + $Cmd.Trim()) -ForegroundColor Green
    return $true
}
