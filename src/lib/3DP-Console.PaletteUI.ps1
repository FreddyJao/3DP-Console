<#
    Fragment: 3DP-Console.PaletteUI.ps1
    Sourced by 3DP-Console.ps1 only.
#>

# =============================================================================
# 7. UI-RENDERING (Write-ListLines, Render-Palette, Port-Check)
# =============================================================================

# Word-wrap for palette detail lines (prevents terminal wrap from merging into next menu row).
function Split-UITextToLines {
    param([string]$Text, [int]$MaxWidth)
    if ($MaxWidth -lt 12) {
        $t0 = ($Text -replace '[\r\n]+', ' ').Trim()
        return @($t0)
    }
    $t = ($Text -replace '[\r\n]+', ' ').Trim()
    if (-not $t) { return @() }
    $out = New-Object System.Collections.ArrayList
    while ($t.Length -gt $MaxWidth) {
        $sliceLen = [Math]::Min($MaxWidth, $t.Length)
        $candidate = $t.Substring(0, $sliceLen)
        $lastSp = $candidate.LastIndexOf(' ')
        $minBreak = [Math]::Max(8, [Math]::Floor($MaxWidth / 4))
        if ($lastSp -lt 1 -or $lastSp -lt $minBreak) {
            [void]$out.Add($candidate)
            $t = $t.Substring($sliceLen).TrimStart()
        } else {
            [void]$out.Add($t.Substring(0, $lastSp))
            $t = $t.Substring($lastSp).TrimStart()
        }
    }
    if ($t) { [void]$out.Add($t) }
    return @($out)
}

function Get-DescLongLineCount {
    param([string]$LongText, [int]$LineLen)
    if (-not $LongText) { return 0 }
    $longClean = ($LongText -replace '[\r\n]', '').Trim()
    if (-not $longClean) { return 0 }
    $wrapW = [Math]::Max(12, $LineLen - 4)
    return (Split-UITextToLines -Text $longClean -MaxWidth $wrapW).Count
}

function Write-ListLines {
    param([array]$Items, [int]$SelectedIndex)
    if ($Items.Count -eq 0) { return }
    $safeSel = [Math]::Max(0, [Math]::Min($SelectedIndex, $Items.Count - 1))
    $maxShow = [Math]::Min($Items.Count, $Script:MaxVisibleItems)
    $scrollOffset = [Math]::Max(0, [Math]::Min($safeSel, $Items.Count - $maxShow))
    $win = $Host.UI.RawUI.WindowSize
    $lineLen = [Math]::Max(50, [Math]::Min(76, $win.Width - 3))
    for ($i = 0; $i -lt $maxShow; $i++) {
        $idx = $scrollOffset + $i
        $prefix = if ($idx -eq $safeSel) { $Script:ArrowRight + ' ' } else { '  ' }
        $name = $Items[$idx].cmd
        $desc = ($Items[$idx].desc -replace '[\r\n]','').Trim()
        $text = $prefix + $name + '  ' + $desc
        if ($text.Length -gt $lineLen) {
            $fixed = $prefix.Length + $name.Length + 2
            $budget = $lineLen - $fixed - 3
            if ($budget -lt 6) { $budget = 6 }
            if ($desc.Length -gt $budget) {
                $desc = $desc.Substring(0, $budget).TrimEnd() + '...'
            }
            $text = $prefix + $name + '  ' + $desc
        }
        $padded = $text.PadRight($lineLen)
        if ($idx -eq $safeSel) {
            Write-Host $padded -ForegroundColor Cyan
            # Show full description on extra line(s) when selected (descLong), wrapped to width
            $long = $Items[$idx].descLong
            if ($long) {
                $longClean = ($long -replace '[\r\n]','').Trim()
                if ($longClean) {
                    $wrapW = [Math]::Max(12, $lineLen - 4)
                    foreach ($seg in (Split-UITextToLines -Text $longClean -MaxWidth $wrapW)) {
                        $row = ('    ' + $seg).PadRight($lineLen)
                        Write-Host $row -ForegroundColor DarkGray
                    }
                }
            }
        } else {
            Write-Host $padded -ForegroundColor Gray
        }
    }
    if ($Items.Count -gt $Script:MaxVisibleItems) {
        $first = $scrollOffset + 1
        $last = [Math]::Min($scrollOffset + $maxShow, $Items.Count)
        $hint = '  Arrow up/down to scroll (' + $first + '-' + $last + '/' + $Items.Count + ')'
        Write-Host $hint -ForegroundColor DarkGray
    }
}

function Test-PortConnected {
    param([System.IO.Ports.SerialPort]$Port)
    if (-not $Port) { return $false }
    try {
        if (-not $Port.IsOpen) { return $false }
        $available = @([System.IO.Ports.SerialPort]::GetPortNames())
        if ($available -notcontains $Script:Config.ComPort) { return $false }
        $Port.DiscardInBuffer()
        $Port.DiscardOutBuffer()
        $prevRead = $Port.ReadTimeout
        $Port.ReadTimeout = 500
        $Port.WriteLine('M105')
        $deadline = (Get-Date).AddMilliseconds(180)
        $gotOk = $false
        while ((Get-Date) -lt $deadline) {
            if ($Port.BytesToRead -gt 0) {
                $line = $Port.ReadLine()
                if ($line -match 'ok|T:') { $gotOk = $true; break }
            }
            Start-Sleep -Milliseconds 15
        }
        $Port.ReadTimeout = $prevRead
        return $gotOk
    } catch { return $false }
}

# Renders the command palette (title, status, input line, item list, hint line).
# Clear nur wenn verkleinert (last > currentLines), um Flackern zu vermeiden.
function Render-Palette {
    param(
        [string]$Buffer,
        [array]$Items,
        [int]$SelectedIndex,
        [ref]$LastLineCount,
        [string]$ConnectionStatus = 'connected'
    )
    $raw = $Host.UI.RawUI
    $win = $raw.WindowSize
    $wasVisible = $true
    try { $wasVisible = [Console]::CursorVisible } catch { }
    try { [Console]::CursorVisible = $false } catch { }

    $last = $LastLineCount.Value
    $currentLines = 8
    if ($Items.Count -gt 0) {
        $lineLenForCount = [Math]::Max(50, [Math]::Min(76, $win.Width - 3))
        $safeSel = [Math]::Max(0, [Math]::Min($SelectedIndex, $Items.Count - 1))
        $longLines = Get-DescLongLineCount -LongText $Items[$safeSel].descLong -LineLen $lineLenForCount
        $currentLines = 8 + [Math]::Min($Items.Count, $Script:MaxVisibleItems) + 1 + $longLines
        if ($Items.Count -gt $Script:MaxVisibleItems) { $currentLines++ }
    } else {
        $currentLines = 10
    }
    if ($last -gt 0 -and $last -gt $currentLines) {
        try { [Console]::Clear() } catch { Clear-Host }
    }
    $startY = 0
    $coord = New-Object System.Management.Automation.Host.Coordinates(0, $startY)
    try {
        $raw.CursorPosition = $coord
    } catch {
        # z.B. Pester/CI/IDE: kein gueltiges Konsolen-Handle ("Handle ungueltig")
        try { [Console]::CursorVisible = $wasVisible } catch { }
    }

    Write-Host ''
    Write-Host (Get-UIString 'ConsoleTitle') -ForegroundColor Cyan
    $statusLine = switch ($ConnectionStatus) {
        'connected'   { Get-UIString 'StatusConnected' }
        'reconnecting' { Get-UIString 'StatusReconnecting' }
        'lost'       { Get-UIString 'StatusReconnecting' }
        default      { Get-UIString 'StatusConnected' }
    }
    $statusColor = if ($ConnectionStatus -eq 'connected') { 'DarkGray' } else { 'Yellow' }
    $padLen = [Math]::Max(76, $win.Width - 2)
    Write-Host ($statusLine.PadRight($padLen)) -ForegroundColor $statusColor
    $frameLen = [Math]::Max(40, [Math]::Min(76, $win.Width - 2))
    $frameLine = $Script:BoxH.ToString() * $frameLen
    Write-Host $frameLine -ForegroundColor DarkGray
    Write-Host -NoNewline ($Script:ArrowRight + ' ')
    Write-Host -NoNewline $Buffer -ForegroundColor White
    Write-Host '_' -ForegroundColor Yellow -NoNewline
    Write-Host ''
    Write-Host $frameLine -ForegroundColor DarkGray
    $lineLen = [Math]::Max(50, [Math]::Min(76, $win.Width - 2))
    if ($Items.Count -gt 0) {
        Write-ListLines -Items $Items -SelectedIndex $SelectedIndex
        Write-Host ('  Tab=Complete  Enter=Select').PadRight($lineLen) -ForegroundColor DarkGray
    } else {
        $hintLine = if ($ConnectionStatus -eq 'lost' -or $ConnectionStatus -eq 'reconnecting') {
            '  ' + (Get-UIString 'HintReconnect')
        } else {
            '  ' + (Get-UIString 'HintCommands')
        }
        Write-Host $hintLine.PadRight($lineLen) -ForegroundColor DarkGray
        Write-Host ('  ' + (Get-UIString 'HintShortcuts')).PadRight($lineLen) -ForegroundColor DarkGray
    }
    Write-Host ''

    for ($i = $currentLines; $i -lt $last; $i++) {
        Write-Host (' ' * [Math]::Max(0, [Math]::Min(76, $win.Width - 1)))
    }
    $LastLineCount.Value = [Math]::Max($last, $currentLines)

    $inputLineY = 4
    $inputLineX = [Math]::Max(2, [Math]::Min(3 + $Buffer.Length, $win.Width - 2))
    try {
        $cursorCoord = New-Object System.Management.Automation.Host.Coordinates($inputLineX, $inputLineY)
        $raw.CursorPosition = $cursorCoord
        [Console]::CursorVisible = $true
    } catch {
        try { [Console]::CursorVisible = $wasVisible } catch { }
    }
}

function Get-TestKey {
    param([string]$Token)
    $map = @{
        'Enter' = [ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
        'Escape' = [ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false)
        'Tab' = [ConsoleKeyInfo]::new([char]9, [ConsoleKey]::Tab, $false, $false, $false)
        'UpArrow' = [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::UpArrow, $false, $false, $false)
        'DownArrow' = [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::DownArrow, $false, $false, $false)
        'Backspace' = [ConsoleKeyInfo]::new([char]8, [ConsoleKey]::Backspace, $false, $false, $false)
    }
    if ($map.ContainsKey($Token)) { return $map[$Token] }
    if ($Token.Length -eq 1) {
        $c = $Token[0]
        $key = if ($Token -match '^[a-zA-Z]$') {
            [ConsoleKey]([int][char]($Token.ToUpper()[0]))
        } elseif ($Token -eq '/') {
            [ConsoleKey]::Divide
        } else {
            [ConsoleKey]([int][char]$c)
        }
        return [ConsoleKeyInfo]::new([char]$c, $key, $false, $false, $false)
    }
    return $null
}

# =============================================================================
# 8. COMMAND-PALETTE (Hauptschleife: Tastatur, Rendering, Verbindungs-Check)
# Rendert nur bei Aenderung (buffer, sel, items, connection) um Flackern zu vermeiden.
# =============================================================================

function Invoke-CommandPalette {
    param(
        [System.IO.Ports.SerialPort]$Port = $null,
        [ref]$PortRef,
        [string]$InitialBuffer = '',
        [System.Collections.ArrayList]$TestKeyQueue = $null
    )
    $buffer = $InitialBuffer
    $sel = 0
    $lastLineCount = 0
    $lastLineCountRef = [ref]$lastLineCount
    $isTest = $null -ne $TestKeyQueue -and $TestKeyQueue.Count -gt 0
    $hasPortRef = $PSBoundParameters.ContainsKey('PortRef') -and $null -ne $PortRef
    $connectionStatus = 'connected'
    $checkInterval = 0
    $currentPort = if ($hasPortRef) { $PortRef.Value } else { $Port }
    $lastRender = @{ buf = ''; sel = -1; itemsKey = ''; conn = '' }

    if (-not $isTest) {
        try { [Console]::Clear() } catch { Clear-Host }
    }
    while ($true) {
        $items = @(Get-PaletteItems $buffer)
        if (-not $isTest) {
            if ($hasPortRef) {
                $currentPort = $PortRef.Value
                $interval = if ($connectionStatus -eq 'lost' -or $connectionStatus -eq 'reconnecting') { 1 } else { 6 }
                if ($checkInterval -ge $interval) {
                    $checkInterval = 0
                    if (-not (Test-PortConnected -Port $currentPort)) {
                        $connectionStatus = 'reconnecting'
                        $oldPort = $PortRef.Value
                        try {
                            if ($oldPort) { try { if ($oldPort.IsOpen) { $oldPort.Close() }; $oldPort.Dispose() } catch { } }
                            $PortRef.Value = $null
                            Start-Sleep -Milliseconds 800
                            $available = @([System.IO.Ports.SerialPort]::GetPortNames())
                            if ($available -notcontains $Script:Config.ComPort) {
                                $connectionStatus = 'lost'
                            } else {
                                foreach ($attempt in 1..3) {
                                    try {
                                        $newPort = New-Object System.IO.Ports.SerialPort $Script:Config.ComPort, $Script:Config.BaudRate, None, 8, One
                                        $newPort.Open()
                                        $PortRef.Value = $newPort
                                        $connectionStatus = 'connected'
                                        break
                                    } catch {
                                        if ($attempt -lt 3) { Start-Sleep -Milliseconds (400 * $attempt) }
                                        $PortRef.Value = $null
                                        $connectionStatus = 'lost'
                                    }
                                }
                            }
                        } catch {
                            $PortRef.Value = $null
                            $connectionStatus = 'lost'
                        }
                    } else {
                        $connectionStatus = 'connected'
                    }
                }
            }
            $itemsKey = ($items | ForEach-Object { $_.cmd }) -join '|'
            $needRender = ($buffer -ne $lastRender.buf) -or ($sel -ne $lastRender.sel) -or ($itemsKey -ne $lastRender.itemsKey) -or ($connectionStatus -ne $lastRender.conn)
            if ($needRender) {
                Render-Palette -Buffer $buffer -Items $items -SelectedIndex $sel -LastLineCount $lastLineCountRef -ConnectionStatus $connectionStatus
                $lastRender = @{ buf = $buffer; sel = $sel; itemsKey = $itemsKey; conn = $connectionStatus }
            }
        }

        if ($isTest) {
            if ($TestKeyQueue.Count -eq 0) { return @{cmd='TIMEOUT'; direct=$true} }
            $token = $TestKeyQueue[0]
            $null = $TestKeyQueue.RemoveAt(0)
            $key = Get-TestKey -Token $token
            if ($null -eq $key) { continue }
        } elseif ($hasPortRef) {
            $key = $null
            $timeout = 400
            $elapsed = 0
            $useBlockingRead = $false
            while ($elapsed -lt $timeout) {
                $ka = $false
                try { $ka = [Console]::KeyAvailable } catch { $useBlockingRead = $true; break }
                if ($ka) {
                    try { $key = [Console]::ReadKey($true) } catch { $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
                    break
                }
                Start-Sleep -Milliseconds 25
                $elapsed += 25
            }
            if ($useBlockingRead -and $null -eq $key) {
                try { $key = [Console]::ReadKey($true) } catch { $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
            }
            if ($null -eq $key) { $checkInterval++; continue }
        } else {
            try {
                $key = [Console]::ReadKey($true)
            } catch {
                $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
        }
        $k = $key.KeyChar
        $vk = [int]$key.Key

        if ($vk -eq 13 -or $key.Key -eq 'Enter' -or $key.Key -eq 'Return') {
            if ($items.Count -gt 0) {
                $chosen = $items[[Math]::Max(0, [Math]::Min($sel, $items.Count - 1))]
                return $chosen
            }
            if (-not [string]::IsNullOrWhiteSpace($buffer)) {
                return @{cmd=$buffer.Trim(); direct=$true}
            }
            continue
        }
        if ($vk -eq 27 -or $key.Key -eq 'Escape') {
            return $null
        }
        if ($vk -eq 38) {
            if ($items.Count -gt 0) { $sel = [Math]::Max(0, $sel - 1) }
            continue
        }
        if ($vk -eq 40) {
            if ($items.Count -gt 0) { $sel = [Math]::Min($items.Count - 1, $sel + 1) }
            continue
        }
        if ($key.Key -eq 'Backspace') {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                $sel = 0
            }
            continue
        }
        if (($key.Key -eq 'Tab' -or $vk -eq 9) -and $items.Count -gt 0) {
            $chosen = $items[[Math]::Max(0, [Math]::Min($sel, $items.Count - 1))]
            if ($chosen -and $chosen.cmd) {
                $buffer = $chosen.cmd.Trim()
                $sel = 0
            }
            continue
        }
        if ($hasPortRef -and ($connectionStatus -eq 'lost' -or $connectionStatus -eq 'reconnecting') -and [string]$k -eq 'r') {
            $checkInterval = 0
            continue
        }
        $char = [string]$k
        if ($char.Length -eq 1 -and $char -match '[a-zA-Z0-9/ \-]') {
            $buffer += $char
            $sel = 0
            continue
        }
    }
}

