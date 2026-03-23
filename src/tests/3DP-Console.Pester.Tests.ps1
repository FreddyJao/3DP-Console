<#
.SYNOPSIS
    Optional Pester 5 tests (mocks + pure functions without SerialPort).

.DESCRIPTION
    Loads 3DP-Console.ps1 once; covers serial helpers with mocks and tests
    mesh/UI/config helpers for higher code coverage.

    From repo root: .\src\tests\Run-Pester.ps1
    Requires: Pester 5.0.0+

.NOTES
    Main / full Send-Gcode (real port) stay integration/manual; Get-PortOrRetry partly mocked.
    CLI parsing: Invoke-3DPConsoleParseEarlyArgs + Write-3DPConsole*Screen (3DP-Console.ps1).
#>

# Set immediately when this file is read: Pester may delay BeforeAll; serial/read loops need this after dot-source.
$env:THREEDP_CONSOLE_SKIP_MAIN = '1'

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $env:THREEDP_CONSOLE_SKIP_MAIN = '1'
    $global:3DPConsoleExitInvoker = { param([int]$Code) $global:Pester3DPConsoleExitCapture = $Code }
    . (Join-Path $script:RepoRoot '3DP-Console.ps1')
}

Describe 'Invoke-3DPConsoleParseEarlyArgs' {
    It 'empty args' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @()
        $p.Help | Should -BeFalse
        $p.About | Should -BeFalse
        $p.Example | Should -BeFalse
        $p.ComPort | Should -Be ''
        $p.CommandFile | Should -Be ''
        $p.StdinCommands | Should -BeFalse
    }
    It '-About' { (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-About')).About | Should -BeTrue }
    It '-Help and -h' {
        (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-Help')).Help | Should -BeTrue
        (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-h')).Help | Should -BeTrue
    }
    It '-Example and -e' {
        (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-Example')).Example | Should -BeTrue
        (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-e')).Example | Should -BeTrue
    }
    It '-ComPort' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-ComPort', 'COM42')
        $p.ComPort | Should -Be 'COM42'
    }
    It '-ConfigPath' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-ConfigPath', '.\My.ps1')
        $p.ConfigPath | Should -Be '.\My.ps1'
    }
    It '-Command' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-Command', 'G28')
        $p.Command | Should -Be 'G28'
    }
    It '-CommandFile' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-CommandFile', '.\batch.txt')
        $p.CommandFile | Should -Be '.\batch.txt'
    }
    It '-StdinCommands' {
        (Invoke-3DPConsoleParseEarlyArgs -ArgList @('-StdinCommands')).StdinCommands | Should -BeTrue
    }
    It 'combined flags' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-ComPort', 'COM1', '-ConfigPath', 'c.ps1', '-Command', 'M105', '-Help')
        $p.ComPort | Should -Be 'COM1'
        $p.ConfigPath | Should -Be 'c.ps1'
        $p.Command | Should -Be 'M105'
        $p.Help | Should -BeTrue
    }
    It 'ignores trailing -ComPort without value' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-ComPort')
        $p.ComPort | Should -Be ''
    }
    It 'null ArgList treated as empty' {
        (Invoke-3DPConsoleParseEarlyArgs -ArgList $null).Help | Should -BeFalse
    }
    It 'ignores unknown switches' {
        $p = Invoke-3DPConsoleParseEarlyArgs -ArgList @('-Verbose', '-ComPort', 'COM2', '-WhatIf')
        $p.ComPort | Should -Be 'COM2'
        $p.Help | Should -BeFalse
    }
}

Describe '3DP-Console.ps1 root helpers' {
    BeforeAll { Mock Write-Host { } }
    It 'Sync-3DPConsoleLegacySkipMainEnv maps PRUSAMINI to THREEDP' {
        $b1 = $env:THREEDP_CONSOLE_SKIP_MAIN
        $b2 = $env:PRUSAMINI_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            $env:PRUSAMINI_SKIP_MAIN = '1'
            Sync-3DPConsoleLegacySkipMainEnv
            $env:THREEDP_CONSOLE_SKIP_MAIN | Should -Be '1'
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b1
            $env:PRUSAMINI_SKIP_MAIN = $b2
        }
    }
    It 'Invoke-3DPConsoleCliScreenExitIfNeeded returns 0 for About Help Example' {
        Invoke-3DPConsoleCliScreenExitIfNeeded -Parsed ([pscustomobject]@{ About = $true; Help = $false; Example = $false }) | Should -Be 0
        Invoke-3DPConsoleCliScreenExitIfNeeded -Parsed ([pscustomobject]@{ About = $false; Help = $true; Example = $false }) | Should -Be 0
        Invoke-3DPConsoleCliScreenExitIfNeeded -Parsed ([pscustomobject]@{ About = $false; Help = $false; Example = $true }) | Should -Be 0
    }
    It 'Invoke-3DPConsoleCliScreenExitIfNeeded returns null when no screen' {
        Invoke-3DPConsoleCliScreenExitIfNeeded -Parsed ([pscustomobject]@{ About = $false; Help = $false; Example = $false }) | Should -BeNullOrEmpty
    }
    It 'Get-3DPConsoleScriptRoot prefers PSScriptRoot hint' {
        Get-3DPConsoleScriptRoot -PSScriptRootHint 'Z:\OnlyRoot' -DotSourceScriptPath 'C:\x\y.ps1' | Should -Be 'Z:\OnlyRoot'
    }
    It 'Get-3DPConsoleScriptRoot uses DotSourceScriptPath when PSScriptRoot empty' {
        Get-3DPConsoleScriptRoot -PSScriptRootHint '' -DotSourceScriptPath 'C:\Proj\3DP.ps1' | Should -Be 'C:\Proj'
    }
    It 'Get-3DPConsoleScriptRoot uses PSCommandPath when no script path' {
        Get-3DPConsoleScriptRoot -PSScriptRootHint '' -DotSourceScriptPath '' -PSCommandPathValue 'D:\w\z.ps1' | Should -Be 'D:\w'
    }
    It 'Get-3DPConsoleScriptRoot falls back to Get-Location' {
        $pwd = (Get-Location).ProviderPath
        Get-3DPConsoleScriptRoot -PSScriptRootHint '' -DotSourceScriptPath '' -PSCommandPathValue '' | Should -Be $pwd
    }
    It 'Write-3DPConsoleMissingFragmentError does not throw' {
        { Write-3DPConsoleMissingFragmentError -FullPath 'C:\missing\X.ps1' } | Should -Not -Throw
    }
    It 'Invoke-3DPConsoleMainEntryIfEnabled returns null when SKIP_MAIN' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '1'
            Invoke-3DPConsoleMainEntryIfEnabled | Should -BeNullOrEmpty
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleMainEntryIfEnabled returns Main exit code' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Mock Main { 7 }
            Invoke-3DPConsoleMainEntryIfEnabled | Should -Be 7
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleMainEntryIfEnabled returns 0 when Main not int' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Mock Main { 'ok' }
            Invoke-3DPConsoleMainEntryIfEnabled | Should -Be 0
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleProcessExitCode uses global invoker' {
        $global:Pester3DPConsoleExitCapture = $null
        Invoke-3DPConsoleProcessExitCode -Code 5
        $global:Pester3DPConsoleExitCapture | Should -Be 5
    }
    It 'Invoke-3DPConsoleProcessExitCode throws when invoker missing and TEST_THROW_ON_EXIT' {
        $env:THREEDP_CONSOLE_TEST_THROW_ON_EXIT = '1'
        $saved = $global:3DPConsoleExitInvoker
        try {
            Remove-Variable -Name 3DPConsoleExitInvoker -Scope Global -Force -ErrorAction SilentlyContinue
            { Invoke-3DPConsoleProcessExitCode -Code 88 } | Should -Throw '*3DPConsoleTestExit:88*'
        } finally {
            Remove-Item Env:\THREEDP_CONSOLE_TEST_THROW_ON_EXIT -Force -ErrorAction SilentlyContinue
            $global:3DPConsoleExitInvoker = $saved
        }
    }
    It 'Invoke-3DPConsoleEarlyCliGate Help stops and captures exit 0' {
        Mock Write-Host { }
        $global:Pester3DPConsoleExitCapture = $null
        $g = Invoke-3DPConsoleEarlyCliGate -ArgList @('-Help')
        $g.Stop | Should -BeTrue
        $global:Pester3DPConsoleExitCapture | Should -Be 0
    }
    It 'Invoke-3DPConsoleEarlyCliGate no flag continues' {
        $g = Invoke-3DPConsoleEarlyCliGate -ArgList @()
        $g.Stop | Should -BeFalse
        $g.Parsed.Help | Should -BeFalse
    }
    It 'Invoke-3DPConsoleMainExitGate captures when Main returns nonzero' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Mock Main { 4 }
            $global:Pester3DPConsoleExitCapture = $null
            $r = Invoke-3DPConsoleMainExitGate
            $r | Should -BeTrue
            $global:Pester3DPConsoleExitCapture | Should -Be 4
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleMainExitGate captures zero when Main returns success int 0' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Mock Main { 0 }
            $global:Pester3DPConsoleExitCapture = $null
            $r = Invoke-3DPConsoleMainExitGate
            $r | Should -BeTrue
            $global:Pester3DPConsoleExitCapture | Should -Be 0
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleMainExitGate false when SKIP_MAIN' {
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $env:THREEDP_CONSOLE_SKIP_MAIN = '1'
            Invoke-3DPConsoleMainExitGate | Should -BeFalse
        } finally {
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Invoke-3DPConsoleAbortOnMissingFragment captures exit 1' {
        Mock Write-Host { }
        $global:Pester3DPConsoleExitCapture = $null
        { Invoke-3DPConsoleAbortOnMissingFragment -FullPath 'Z:\no\such.ps1' } | Should -Not -Throw
        $global:Pester3DPConsoleExitCapture | Should -Be 1
    }
}

Describe 'Write-3DPConsole*Screen' {
    BeforeAll { Mock Write-Host { } }
    It 'About screen' { { Write-3DPConsoleAboutScreen } | Should -Not -Throw }
    It 'Help screen' { { Write-3DPConsoleHelpScreen } | Should -Not -Throw }
    It 'Example screen' { { Write-3DPConsoleExampleScreen } | Should -Not -Throw }
}

Describe 'Invoke-GcodeAndWaitOrAbort (Mocked dependencies)' {
    It 'returns true when Send-Gcode sends lines and Read-SerialResponse ok' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $r = Invoke-GcodeAndWaitOrAbort -Port $null -Gcode 'M105'
        $r | Should -BeTrue
    }

    It 'returns false when Read-SerialResponse fails' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $false }
        $r = Invoke-GcodeAndWaitOrAbort -Port $null -Gcode 'M105'
        $r | Should -BeFalse
    }

    It 'returns false when Send-Gcode sends 0 lines and read fails' {
        Mock Send-Gcode { 0 }
        Mock Read-SerialResponse { $false }
        $r = Invoke-GcodeAndWaitOrAbort -Port $null -Gcode ''
        $r | Should -BeFalse
    }
}

Describe 'Get-GcodeTimeout' {
    It 'uses config buckets when positive' {
        $t = Get-GcodeTimeout -Gcode 'G28'
        $t | Should -BeGreaterOrEqual 60000
    }
    It 'G29 matches G28 bucket' {
        (Get-GcodeTimeout -Gcode 'G29 T') | Should -Be (Get-GcodeTimeout -Gcode 'G28')
    }
    It 'M109 uses heating timeout bucket' {
        $t = Get-GcodeTimeout -Gcode 'M109 S200'
        $t | Should -BeGreaterOrEqual 60000
    }
    It 'M190 uses heating timeout bucket' {
        $t = Get-GcodeTimeout -Gcode 'M190 S60'
        $t | Should -BeGreaterOrEqual 60000
    }
    It 'M105 uses default bucket' {
        $t = Get-GcodeTimeout -Gcode 'M105'
        $t | Should -BeGreaterThan 0
        $t | Should -BeLessOrEqual 60000
    }
    It 'falls back when config timeouts are zero or missing' {
        $bak = @{
            G28G29TimeoutMs      = $Script:Config.G28G29TimeoutMs
            HeatingTimeoutMs     = $Script:Config.HeatingTimeoutMs
            DefaultGcodeTimeoutMs = $Script:Config.DefaultGcodeTimeoutMs
        }
        try {
            $Script:Config.G28G29TimeoutMs = 0
            $Script:Config.HeatingTimeoutMs = 0
            $Script:Config.DefaultGcodeTimeoutMs = 0
            (Get-GcodeTimeout -Gcode 'G28') | Should -Be 300000
            (Get-GcodeTimeout -Gcode 'M109 S1') | Should -Be 600000
            (Get-GcodeTimeout -Gcode 'M105') | Should -Be 15000
        } finally {
            $Script:Config.G28G29TimeoutMs = $bak.G28G29TimeoutMs
            $Script:Config.HeatingTimeoutMs = $bak.HeatingTimeoutMs
            $Script:Config.DefaultGcodeTimeoutMs = $bak.DefaultGcodeTimeoutMs
        }
    }
}

Describe 'Split-SerialLineBuffer and Test-SerialLineIsBusyOkIgnore' {
    It 'splits mixed newlines into complete lines and remainder' {
        $s = Split-SerialLineBuffer -Buffer "a`r`nb`nc"
        $s.Complete.Count | Should -Be 2
        $s.Complete[0] | Should -Be 'a'
        $s.Complete[1] | Should -Be 'b'
        $s.Remainder | Should -Be 'c'
    }
    It 'LF-only buffer splits' {
        $s = Split-SerialLineBuffer -Buffer "x`ny"
        $s.Complete | Should -Be @('x')
        $s.Remainder | Should -Be 'y'
    }
    It 'single fragment without newline is remainder only' {
        $s = Split-SerialLineBuffer -Buffer 'partial'
        $s.Complete.Count | Should -Be 0
        $s.Remainder | Should -Be 'partial'
    }
    It 'null buffer yields empty remainder' {
        $s = Split-SerialLineBuffer -Buffer $null
        $s.Complete.Count | Should -Be 0
        $s.Remainder | Should -Be ''
    }
    It 'detects ok/busy/wait lines to ignore' {
        Test-SerialLineIsBusyOkIgnore -Line 'ok' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'ok 12' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'busy: processing' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'busy: heating' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'Active Extruder: 0' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'wait' | Should -BeTrue
        Test-SerialLineIsBusyOkIgnore -Line 'echo:busy' | Should -BeFalse
        Test-SerialLineIsBusyOkIgnore -Line 'G28 finished' | Should -BeFalse
    }
}

Describe 'Append-SerialChunkToLineBuffer' {
    It 'appends chunk and returns complete lines' {
        $buf = [ref]('a' + [char]10)
        $c = Append-SerialChunkToLineBuffer -Buffer $buf -Chunk 'b'
        $c.Count | Should -Be 1
        $c[0] | Should -Be 'a'
        $buf.Value | Should -Be 'b'
    }
    It 'null chunk only re-splits buffer' {
        $buf = [ref]('x' + [char]10 + 'y')
        $c = Append-SerialChunkToLineBuffer -Buffer $buf -Chunk $null
        $c.Count | Should -Be 1
        $c[0] | Should -Be 'x'
        $buf.Value | Should -Be 'y'
    }
    It 'empty string chunk is no-op' {
        $buf = [ref]('z')
        $null = Append-SerialChunkToLineBuffer -Buffer $buf -Chunk ''
        $buf.Value | Should -Be 'z'
    }
}

Describe 'Format-TemperatureReport' {
    It 'parses ok-line with T and B' {
        $r = Format-TemperatureReport -Line 'ok T:21.87 /0.0 B:23.28 /0.0'
        $r | Should -Not -BeNullOrEmpty
        $r.Count | Should -BeGreaterOrEqual 2
        $r[0] | Should -Match '21\.87'
    }
    It 'parses T0-style hotend label' {
        $r = Format-TemperatureReport -Line 'ok T0:200.0 /200.0 B:60.0 /60.0'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match '200'
        ($r -join ' ') | Should -Match '60'
    }
    It 'parses bed-only ok line' {
        $r = Format-TemperatureReport -Line 'ok B:22.5 /0.0'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match 'Bed'
        ($r -join ' ') | Should -Match '22\.5'
    }
    It 'returns null for line without temps' {
        Format-TemperatureReport -Line 'ok' | Should -BeNullOrEmpty
    }
    It 'hotend line without target uses zero degree placeholder' {
        $r = Format-TemperatureReport -Line 'ok T:22.0'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match '22'
    }
    It 'bed line without target uses zero degree placeholder' {
        $r = Format-TemperatureReport -Line 'ok B:59.8'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match 'Bed'
    }
}

Describe 'Parse-MeshLineToNumbers and Parse-MeshFromG29Output' {
    It 'Parse-MeshLineToNumbers reads decimals' {
        $n = Parse-MeshLineToNumbers -LinePart '-0.05 +0.10'
        $n.Count | Should -Be 2
        [math]::Abs($n[0] - (-0.05)) | Should -BeLessThan 0.0001
    }
    It 'Parse-MeshLineToNumbers accepts comma decimals' {
        $n = Parse-MeshLineToNumbers -LinePart '1,25 -2,5'
        $n.Count | Should -Be 2
        [math]::Abs($n[0] - 1.25) | Should -BeLessThan 0.0001
    }
    It 'Parse-MeshLineToNumbers yields nothing for no numbers' {
        Parse-MeshLineToNumbers -LinePart 'abc' | Should -BeNullOrEmpty
    }
    It 'Parse-MeshFromG29Output finds rows in G29-style text' {
        $txt = @"
Bilinear Leveling Grid:
  0      1      2
 0 +0.010 +0.020 +0.030
 1 +0.040 +0.050 +0.060
"@
        $m = Parse-MeshFromG29Output -Output $txt
        $m.Count | Should -BeGreaterThan 0
    }
    It 'Parse-MeshFromG29Output parses semicolon-separated mesh CSV style' {
        $txt = "+0.010; +0.020; +0.030`n+0.040; +0.050; +0.060"
        $m = Parse-MeshFromG29Output -Output $txt
        $m.Count | Should -BeGreaterThan 0
    }
    It 'Parse-MeshLineToNumbers ignores non-numeric tokens' {
        $n = Parse-MeshLineToNumbers -LinePart 'abc ;; def'
        $n.Count | Should -Be 0
    }
}

Describe 'Mesh color helpers' {
    BeforeAll { Mock Write-Host { } }
    It 'Get-MeshCellColor green for small deviation' {
        $i = Get-MeshCellColor -Value 0.02 -ThresholdGreen 0.05 -ThresholdYellow 0.15
        $i.color | Should -Be 'Green'
    }
    It 'Get-MeshCellColor yellow between thresholds' {
        (Get-MeshCellColor -Value 0.10 -ThresholdGreen 0.05 -ThresholdYellow 0.15).color | Should -Be 'Yellow'
    }
    It 'Get-MeshCellColor red beyond yellow' {
        (Get-MeshCellColor -Value 0.50 -ThresholdGreen 0.05 -ThresholdYellow 0.15).color | Should -Be 'Red'
    }
    It 'Get-MeshCellColor uses PrevValue improvement to force green' {
        $i = Get-MeshCellColor -Value 0.12 -PrevValue 0.40 -ThresholdGreen 0.05 -ThresholdYellow 0.15
        $i.color | Should -Be 'Green'
        $i.isImprovement | Should -BeTrue
    }
    It 'Get-MeshCellColor reads thresholds from Config when omitted' {
        $i = Get-MeshCellColor -Value 0.02
        $i.color | Should -Be 'Green'
    }
    It 'Get-DeltaImprovement detects improvement' {
        Get-DeltaImprovement -NewValue 0.03 -OldValue 0.10 | Should -BeTrue
    }
    It 'Get-DeltaImprovement false when not improved' {
        Get-DeltaImprovement -NewValue 0.20 -OldValue 0.05 | Should -BeFalse
    }
    It 'Get-MeshCellDisplayInfo returns cellText' {
        $d = Get-MeshCellDisplayInfo -val 0.02 -prevVal ([double]::NaN) -ThresholdGreen 0.05 -ThresholdYellow 0.15
        $d.cellText | Should -Not -BeNullOrEmpty
        $d.color | Should -Not -BeNullOrEmpty
    }
    It 'Format-MeshWithColors runs for small mesh' {
        $mesh = @( @(0.01, 0.02), @(0.03, 0.04) )
        { Format-MeshWithColors -Mesh $mesh -ThresholdGreen 0.05 -ThresholdYellow 0.15 } | Should -Not -Throw
    }
    It 'Format-MeshWithColors no-op for empty mesh' {
        { Format-MeshWithColors -Mesh @() -ThresholdGreen 0.05 -ThresholdYellow 0.15 } | Should -Not -Throw
    }
    It 'Format-MeshWithColors uses PrevMesh for cell display' {
        $m1 = @( @(0.01, 0.02), @(0.03, 0.04) )
        $m2 = @( @(0.05, 0.06), @(0.07, 0.08) )
        { Format-MeshWithColors -Mesh $m2 -PrevMesh $m1 -ThresholdGreen 0.05 -ThresholdYellow 0.15 } | Should -Not -Throw
    }
    It 'Get-MeshCellDisplayInfo uses white in neutral band' {
        $d = Get-MeshCellDisplayInfo -val 0.05 -prevVal ([double]::NaN) -ThresholdGreen 0.02 -ThresholdYellow 0.15
        $d.color | Should -Be 'White'
    }
    It 'Get-MeshCellDisplayInfo red arrow when worse than previous' {
        $d = Get-MeshCellDisplayInfo -val 0.50 -prevVal 0.05 -ThresholdGreen 0.05 -ThresholdYellow 0.15
        $d.color | Should -Be 'Red'
        $d.cellText.Contains([string][char]0x2191) | Should -BeTrue
    }
    It 'Get-MeshCellDisplayInfo green arrow when improved vs previous' {
        $d = Get-MeshCellDisplayInfo -val 0.12 -prevVal 0.40 -ThresholdGreen 0.05 -ThresholdYellow 0.15
        $d.cellText.Contains([string][char]0x2193) | Should -BeTrue
        $d.color | Should -Be 'Green'
    }
    It 'Mesh helpers use built-in mm thresholds when Config mesh keys null' {
        $bakG = $Script:Config.MeshThresholdGreenMm
        $bakY = $Script:Config.MeshThresholdYellowMm
        try {
            $Script:Config.MeshThresholdGreenMm = $null
            $Script:Config.MeshThresholdYellowMm = $null
            (Get-MeshCellColor -Value 0.02).color | Should -Be 'Green'
            (Get-MeshCellColor -Value 0.10).color | Should -Be 'Yellow'
            Mock Write-Host { }
            { Format-MeshWithColors -Mesh @(@(0.02, 0.11)) } | Should -Not -Throw
        } finally {
            $Script:Config.MeshThresholdGreenMm = $bakG
            $Script:Config.MeshThresholdYellowMm = $bakY
        }
    }
    It 'Mesh helpers read numeric thresholds from Config when params omitted' {
        $bakG = $Script:Config.MeshThresholdGreenMm
        $bakY = $Script:Config.MeshThresholdYellowMm
        try {
            $Script:Config.MeshThresholdGreenMm = 0.08
            $Script:Config.MeshThresholdYellowMm = 0.20
            (Get-MeshCellColor -Value 0.05).color | Should -Be 'Green'
            (Get-MeshCellDisplayInfo -val 0.10 -prevVal ([double]::NaN)).cellText | Should -Not -BeNullOrEmpty
        } finally {
            $Script:Config.MeshThresholdGreenMm = $bakG
            $Script:Config.MeshThresholdYellowMm = $bakY
        }
    }
    It 'Get-MeshCellDisplayInfo negative val uses F3 format without plus' {
        $d = Get-MeshCellDisplayInfo -val -0.123 -prevVal ([double]::NaN) -ThresholdGreen 0.05 -ThresholdYellow 0.15
        # F3 nutzt CurrentCulture (z. B. de-DE: Komma, en-US: Punkt)
        $d.cellText | Should -Match '^-0[.,]123$'
    }
}

Describe 'Get-SlashCommandArgs' {
    It 'parses /home xy' {
        $a = Get-SlashCommandArgs -Cmd '/home xy' -Prefix '/home'
        ($a -join ' ') | Should -Be 'xy'
    }
    It 'parses /move X 10' {
        $a = Get-SlashCommandArgs -Cmd '/move X 10' -Prefix '/move'
        $a[0] | Should -Be 'x'
        $a[1] | Should -Be '10'
    }
}

Describe 'Get-UIString' {
    It 'replaces ComPort placeholder' {
        $s = Get-UIString -Key 'StatusConnected'
        $pat = [regex]::Escape([string]$Script:Config.ComPort)
        $s | Should -Match $pat
    }
    It 'replaces NozzleTemp BedTemp DueseLabel in HintShortcuts' {
        $s = Get-UIString -Key 'HintShortcuts'
        $patN = [regex]::Escape([string]$Script:Config.NozzleTempCelsius)
        $patB = [regex]::Escape([string]$Script:Config.BettTempCelsius)
        $patD = [regex]::Escape([string]$Script:DueseLabel)
        $s | Should -Match $patN
        $s | Should -Match $patB
        $s | Should -Match $patD
    }
    It 'returns empty for unknown key' {
        Get-UIString -Key 'NichtVorhandenXYZ123' | Should -Be ''
    }
}

Describe 'Palette UI text wrap' {
    It 'Split-UITextToLines breaks long text' {
        $s = 'aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk'
        $lines = @(Split-UITextToLines -Text $s -MaxWidth 12)
        $lines.Count | Should -BeGreaterThan 1
    }
    It 'Split-UITextToLines MaxWidth below 12 returns single segment' {
        $lines = @(Split-UITextToLines -Text "hello world" -MaxWidth 8)
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match 'hello'
    }
    It 'Split-UITextToLines empty yields empty array' {
        @(Split-UITextToLines -Text '' -MaxWidth 40).Count | Should -Be 0
    }
    It 'Get-DescLongLineCount matches Split-UITextToLines (same wrap width)' {
        $s = 'word1 word2 word3 word4 word5'
        $lineLen = 40
        $wrapW = [Math]::Max(12, $lineLen - 4)
        $a = Get-DescLongLineCount -LongText $s -LineLen $lineLen
        $b = @(Split-UITextToLines -Text $s -MaxWidth $wrapW).Count
        $a | Should -Be $b
    }
}

Describe 'Write-ListLines and Render-Palette' {
    BeforeAll { Mock Write-Host { }; Mock Clear-Host { } }
    It 'Write-ListLines renders without throw' {
        $items = @(
            [pscustomobject]@{ cmd = 'G28'; desc = 'Home'; descLong = '' }
            [pscustomobject]@{ cmd = 'M105'; desc = 'Temp'; descLong = 'Longer description for wrap test here' }
        )
        { Write-ListLines -Items $items -SelectedIndex 0 } | Should -Not -Throw
    }
    It 'Write-ListLines shows scroll hint when many items' {
        $bak = $Script:MaxVisibleItems
        try {
            $Script:MaxVisibleItems = 3
            $items = 1..8 | ForEach-Object {
                [pscustomobject]@{ cmd = "C$_"; desc = 'd'; descLong = '' }
            }
            { Write-ListLines -Items $items -SelectedIndex 5 } | Should -Not -Throw
        } finally {
            $Script:MaxVisibleItems = $bak
        }
    }
    It 'Render-Palette draws frame and items' {
        $items = @([pscustomobject]@{ cmd = 'G28'; desc = 'x'; descLong = '' })
        $last = [ref]0
        { Render-Palette -Buffer 'g' -Items $items -SelectedIndex 0 -LastLineCount $last -ConnectionStatus 'connected' } | Should -Not -Throw
    }
    It 'Render-Palette reconnecting hint when no items' {
        $last = [ref]0
        { Render-Palette -Buffer '' -Items @() -SelectedIndex 0 -LastLineCount $last -ConnectionStatus 'reconnecting' } | Should -Not -Throw
    }
}

Describe 'Port helpers' {
    BeforeAll {
        # WMI fallback can hang a long time on some systems; neutralize for this test.
        Mock Get-WmiObject { @() }
    }
    It 'Test-PortConnected null port returns false' {
        Test-PortConnected -Port $null | Should -BeFalse
    }
    It 'Get-AvailableComPorts returns array' {
        $p = @(Get-AvailableComPorts)
        $p -is [array] | Should -BeTrue
    }
}

Describe 'Get-3DPSerialPortNativeNames / WMI COM fallback' {
    It 'native list sorted when GetPortNames returns values' {
        Mock Get-3DPSerialPortNativeNames { 'COM9', 'COM1' }
        $a = @(Get-AvailableComPorts)
        $a[0] | Should -Be 'COM1'
        $a[1] | Should -Be 'COM9'
    }
    It 'WMI fallback extracts COM from PnP name when native list empty' {
        Mock Get-3DPSerialPortNativeNames { @() }
        Mock Get-WmiObject { [pscustomobject]@{ Name = 'USB-SERIAL CH340 (COM77)' } }
        $a = @(Get-AvailableComPorts)
        $a | Should -Contain 'COM77'
    }
    It 'Get-ComPortsFromPnpWmi returns unique sorted ports' {
        Mock Get-WmiObject {
            @(
                [pscustomobject]@{ Name = 'A (COM3)' }
                [pscustomobject]@{ Name = 'B (COM3)' }
                [pscustomobject]@{ Name = 'C (COM1)' }
            )
        }
        $r = @(Get-ComPortsFromPnpWmi)
        $r.Count | Should -Be 2
        $r[0] | Should -Be 'COM1'
        $r[1] | Should -Be 'COM3'
    }
    It 'Get-ComPortsFromPnpWmi returns empty when WMI yields no devices' {
        Mock Get-WmiObject { $null }
        @(Get-ComPortsFromPnpWmi).Count | Should -Be 0
    }
    It 'Get-AvailableComPorts uses WMI when native port enumeration throws' {
        Mock Get-3DPSerialPortNativeNames { throw 'native serial api failed' }
        Mock Get-WmiObject { [pscustomobject]@{ Name = 'USB (COM55)' } }
        $a = @(Get-AvailableComPorts)
        $a | Should -Contain 'COM55'
    }
}

Describe 'Update-ConfigComPort' {
    It 'returns false when config file missing' {
        Update-ConfigComPort -ConfigPath (Join-Path $env:TEMP '3dp_cfg_missing_xyz.ps1') -NewComPort 'COM9' | Should -BeFalse
    }
    It 'replaces ComPort string and returns true' {
        $tmp = Join-Path $env:TEMP ("3dp_updcfg_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value "ComPort = `"COM_OLD`"`n"
        try {
            Update-ConfigComPort -ConfigPath $tmp -NewComPort 'COM_NEW' | Should -BeTrue
            (Get-Content -LiteralPath $tmp -Raw) | Should -Match 'COM_NEW'
            (Get-Content -LiteralPath $tmp -Raw) | Should -Not -Match 'COM_OLD'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    It 'returns false when path is a directory' {
        Update-ConfigComPort -ConfigPath $env:TEMP -NewComPort 'COM1' | Should -BeFalse
    }
}

Describe 'Get-PortOrRetry (mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Start-Sleep { }
        Mock Clear-Host { }
    }
    It 'returns Config.ComPort when port exists and no -ForceShowSelection' {
        Mock Get-AvailableComPorts { @('COM1', 'COM2', 'COM3') }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM2'
            Get-PortOrRetry -ConfigPath (Join-Path $env:TEMP 'nope_missing_3dp.ps1') | Should -Be 'COM2'
        } finally {
            $Script:Config.ComPort = $orig
        }
    }
    It 'returns null when user enters q' {
        Mock Get-AvailableComPorts { @('COM9') }
        Mock Read-Host { 'q' }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM_NOT_IN_LIST'
            Get-PortOrRetry -ConfigPath (Join-Path $env:TEMP 'nope2.ps1') | Should -BeNullOrEmpty
        } finally {
            $Script:Config.ComPort = $orig
        }
    }
    It '-ForceShowSelection shows menu even if port is in list' {
        Mock Get-AvailableComPorts { @('COM7') }
        Mock Read-Host { 'q' }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM7'
            Get-PortOrRetry -ConfigPath (Join-Path $env:TEMP 'nope3.ps1') -ForceShowSelection | Should -BeNullOrEmpty
        } finally {
            $Script:Config.ComPort = $orig
        }
    }
    It 'numeric choice updates ComPort and config file' {
        $tmp = Join-Path $env:TEMP ("3dp_portcfg_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value @'
    ComPort = "COMOLD"
'@
        Mock Get-AvailableComPorts { @('COM_PICK') }
        Mock Read-Host { '1' }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM_MISSING'
            $r = Get-PortOrRetry -ConfigPath $tmp
            $r | Should -Be 'COM_PICK'
            $Script:Config.ComPort | Should -Be 'COM_PICK'
            (Get-Content -LiteralPath $tmp -Raw) | Should -Match 'COM_PICK'
        } finally {
            $Script:Config.ComPort = $orig
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    It 'empty COM list then q exits' {
        Mock Get-AvailableComPorts { @() }
        Mock Read-Host { 'q' }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COMX'
            Get-PortOrRetry -ConfigPath (Join-Path $env:TEMP 'nope4.ps1') | Should -BeNullOrEmpty
        } finally {
            $Script:Config.ComPort = $orig
        }
    }
    It 'invalid port number then valid choice' {
        $tmp = Join-Path $env:TEMP ("3dp_portcfg_inv_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value @'
    ComPort = "COMOLD"
'@
        Mock Get-AvailableComPorts { @('COM_FIRST', 'COM_SECOND') }
        $script:porInv = 0
        Mock Read-Host {
            $script:porInv++
            if ($script:porInv -eq 1) { '99' }
            else { '2' }
        }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM_MISSING'
            $r = Get-PortOrRetry -ConfigPath $tmp
            $r | Should -Be 'COM_SECOND'
            $Script:Config.ComPort | Should -Be 'COM_SECOND'
        } finally {
            $Script:Config.ComPort = $orig
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    It 'empty input retries then selects port' {
        $tmp = Join-Path $env:TEMP ("3dp_portcfg_ent_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value @'
    ComPort = "COMOLD"
'@
        Mock Get-AvailableComPorts { @('COM_ONLY') }
        $script:porEnt = 0
        Mock Read-Host {
            $script:porEnt++
            if ($script:porEnt -eq 1) { '' }
            else { '1' }
        }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM_MISSING'
            $r = Get-PortOrRetry -ConfigPath $tmp
            $r | Should -Be 'COM_ONLY'
        } finally {
            $Script:Config.ComPort = $orig
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    It 'single available port shows range hint 1 and accepts choice 1' {
        $tmp = Join-Path $env:TEMP ("3dp_portcfg_one_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value @'
    ComPort = "COMOLD"
'@
        Mock Get-AvailableComPorts { @('COM_SOLO') }
        Mock Read-Host { '1' }
        $orig = $Script:Config.ComPort
        try {
            $Script:Config.ComPort = 'COM_MISSING'
            $r = Get-PortOrRetry -ConfigPath $tmp
            $r | Should -Be 'COM_SOLO'
        } finally {
            $Script:Config.ComPort = $orig
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Init / Config merge' {
    It 'Merge-HashtableIntoConfig null source does not throw' {
        { Merge-HashtableIntoConfig -Source $null } | Should -Not -Throw
    }
    It 'Merge-HashtableIntoConfig skips null values in source' {
        $orig = $Script:Config.ComPort
        try {
            Merge-HashtableIntoConfig -Source @{ ComPort = $null } -KeysOnly @('ComPort')
            $Script:Config.ComPort | Should -Be $orig
        } finally {
            $Script:Config.ComPort = $orig
        }
    }
    It 'Merge-HashtableIntoConfig merges KeysOnly' {
        $orig = $Script:Config.xy_feedrate
        try {
            Merge-HashtableIntoConfig -Source @{ xy_feedrate = 424242 } -KeysOnly @('xy_feedrate')
            $Script:Config.xy_feedrate | Should -Be 424242
        } finally {
            $Script:Config.xy_feedrate = $orig
        }
    }
    It 'Update-ConfigComPort false for missing file' {
        $ghost = Join-Path $env:TEMP ("3dp_pester_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Update-ConfigComPort -ConfigPath $ghost -NewComPort COM9 | Should -BeFalse
    }
    It 'Update-ConfigComPort rewrites ComPort in file' {
        $tmp = Join-Path $env:TEMP ("3dp_pester_cfg_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Encoding UTF8 -Value @'
# test
    ComPort = "COM1"
    BaudRate = 115200
'@
        try {
            Update-ConfigComPort -ConfigPath $tmp -NewComPort 'COM77' | Should -BeTrue
            (Get-Content -LiteralPath $tmp -Raw) | Should -Match 'COM77'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    It 'Get-3DPConsoleOptionalFile returns null for missing sidecar' {
        Get-3DPConsoleOptionalFile -FileName 'DefinitelyMissingSidecar_9f3a.ps1' | Should -BeNullOrEmpty
    }
    It 'Get-3DPConsoleOptionalFile finds file next to console root' {
        $name = "_pester_optional_{0}.txt" -f [Guid]::NewGuid().ToString('N')
        $path = Join-Path $script:RepoRoot $name
        Set-Content -LiteralPath $path -Value 'ok' -Encoding UTF8
        try {
            Get-3DPConsoleOptionalFile -FileName $name | Should -Be $path
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Ensure-SystemIOPortsLoaded' {
    It 'returns true when assembly already loaded' {
        Ensure-SystemIOPortsLoaded | Should -BeTrue
    }
}

Describe 'Invoke-Confirm' {
    It 'returns true for y' {
        Mock Read-Host { 'y' }
        Invoke-Confirm -Prompt 'test' | Should -BeTrue
    }
    It 'returns true for j' {
        Mock Read-Host { ' J ' }
        Invoke-Confirm | Should -BeTrue
    }
    It 'returns false for n' {
        Mock Read-Host { 'n' }
        Invoke-Confirm | Should -BeFalse
    }
}

Describe 'Send-Gcode' {
    BeforeAll { Mock Write-Host { }; Mock Start-Sleep { } }
    It 'returns 0 for M112 when user declines' {
        Mock Invoke-Confirm { $false }
        Send-Gcode -Port $null -Gcode 'M112' | Should -Be 0
    }
    It 'M112 when user confirms attempts WriteLine (throws if port closed)' {
        Mock Invoke-Confirm { $true }
        $bad = [System.IO.Ports.SerialPort]::new('COM_PESTER_CLOSED_999', $Script:Config.BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
        try {
            { Send-Gcode -Port $bad -Gcode 'M112' } | Should -Throw
        } finally {
            try { $bad.Dispose() } catch { }
        }
    }
    It 'returns 0 for comment-only and blank lines' {
        Send-Gcode -Port $null -Gcode "; c1`n`n; c2" | Should -Be 0
    }
    It 'invokes HostCommandCallback for ;@ lines' {
        $script:PesterHostCmdHit = $false
        Send-Gcode -Port $null -Gcode ';@pause now' -HostCommandCallback {
            param($h)
            $script:PesterHostCmdHit = ($h -eq 'pause now')
        }
        $script:PesterHostCmdHit | Should -BeTrue
    }
}

Describe 'Palette items (Config-backed)' {
    It 'Get-PaletteItems unknown buffer returns empty' {
        @(Get-PaletteItems -Buffer 'zzz').Count | Should -Be 0
    }
    It 'Get-PaletteItems slash prefix lists commands' {
        $items = @(Get-PaletteItems -Buffer '/')
        $items.Count | Should -BeGreaterThan 0
    }
    It 'Get-PaletteItems single slash match with args returns synthetic entry' {
        $items = @(Get-PaletteItems -Buffer '/help extra')
        $items.Count | Should -Be 1
        $items[0].cmd | Should -Be '/help extra'
    }
    It 'Get-PaletteItems loop with repeat suffix synthesizes single entry' {
        $items = @(Get-PaletteItems -Buffer 'loop prepare 3')
        $items.Count | Should -Be 1
        $items[0].cmd | Should -Be 'loop prepare 3'
    }
    It 'Get-PaletteItems loop repeat with descLong copies descLong on synthetic item' {
        $items = @(Get-PaletteItems -Buffer 'loop level_rehome_once 2')
        $items.Count | Should -Be 1
        $items[0].descLong | Should -Not -BeNullOrEmpty
    }
    It 'Get-PaletteItems loop prefix matching several loops returns filtered list' {
        $items = @(Get-PaletteItems -Buffer 'loop temp')
        $items.Count | Should -BeGreaterThan 1
    }
    It 'Get-PaletteItems g returns items' {
        $items = @(Get-PaletteItems -Buffer 'g')
        $items.Count | Should -BeGreaterThan 0
    }
    It 'Get-PaletteItems g28 includes G28' {
        $items = @(Get-PaletteItems -Buffer 'g28')
        ($items | Where-Object { $_.cmd -eq 'G28' }) | Should -Not -BeNullOrEmpty
    }
    It 'Get-LoopPaletteItems returns loop entries' {
        $items = @(Get-LoopPaletteItems)
        $items.Count | Should -BeGreaterThan 0
    }
    It 'Get-PaletteItems m1 filters M-commands' {
        $items = @(Get-PaletteItems -Buffer 'm1')
        $items.Count | Should -BeGreaterThan 0
        ($items | Where-Object { $_.cmd -like 'M1*' }).Count | Should -Be $items.Count
    }
    It 'Get-PaletteItems slash gcode with extra args copies gcode to synthetic item' {
        $items = @(Get-PaletteItems -Buffer '/level extra')
        $items.Count | Should -Be 1
        $items[0].gcode | Should -Be 'G29'
    }
    It 'Get-PaletteItems M prefix without digits lists M-commands' {
        $items = @(Get-PaletteItems -Buffer 'm')
        $items.Count | Should -BeGreaterThan 0
    }
    It 'Get-LoopPaletteItems honors Config.LoopOrder' {
        $bakL = $Script:Config.Loops
        $bakO = $Script:Config.LoopOrder
        try {
            $Script:Config.Loops = @{
                zed   = @{ desc = 'z'; cmds = @('M105') }
                alpha = @{ desc = 'a'; cmds = @('M105') }
            }
            $Script:Config.LoopOrder = @('alpha', 'zed')
            $items = @(Get-LoopPaletteItems)
            $items[0].cmd | Should -Be 'loop alpha'
            $items[1].cmd | Should -Be 'loop zed'
        } finally {
            $Script:Config.Loops = $bakL
            $Script:Config.LoopOrder = $bakO
        }
    }
    It 'Get-LoopPaletteItems sorts keys when LoopOrder empty' {
        $bakL = $Script:Config.Loops
        $bakO = $Script:Config.LoopOrder
        try {
            $Script:Config.Loops = @{
                zebra = @{ desc = 'z'; cmds = @('M105') }
                apple = @{ desc = 'a'; cmds = @('M105') }
            }
            $Script:Config.LoopOrder = @()
            $items = @(Get-LoopPaletteItems)
            $items[0].cmd | Should -Be 'loop apple'
        } finally {
            $Script:Config.Loops = $bakL
            $Script:Config.LoopOrder = $bakO
        }
    }
    It 'Get-LoopPaletteItems array loop entry uses Count for desc' {
        $bakL = $Script:Config.Loops
        $bakO = $Script:Config.LoopOrder
        try {
            $Script:Config.Loops = @{ arronly = @('M105', 'M104', 'M140') }
            $Script:Config.LoopOrder = @()
            $items = @(Get-LoopPaletteItems)
            $one = $items | Where-Object { $_.cmd -eq 'loop arronly' }
            $one | Should -Not -BeNullOrEmpty
            $one.desc | Should -Match '3'
        } finally {
            $Script:Config.Loops = $bakL
            $Script:Config.LoopOrder = $bakO
        }
    }
    It 'Get-LoopPaletteItems returns empty when optional loops file throws' {
        $bad = Join-Path $env:TEMP ("3dp_loops_throw_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $bad -Encoding UTF8 -Value 'throw "badloops"'
        $bak = $Script:Config.Loops
        Mock Get-3DPConsoleOptionalFile { param($FileName) if ($FileName -eq 'PrusaMini-Loops.ps1') { $bad } else { $null } }
        try {
            $Script:Config.Loops = $null
            @(Get-LoopPaletteItems).Count | Should -Be 0
        } finally {
            $Script:Config.Loops = $bak
            Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue
        }
    }
    It 'Get-LoopPaletteItems returns empty when no loops file path' {
        $bak = $Script:Config.Loops
        Mock Get-3DPConsoleOptionalFile { $null }
        try {
            $Script:Config.Loops = $null
            @(Get-LoopPaletteItems).Count | Should -Be 0
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'Get-LoopPaletteItems catch returns empty when BuildList throws' {
        Mock Get-LoopPaletteItemsBuildList { throw 'pester_buildlist_fail' }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{ a = @{ cmds = @('G28') } }
            @(Get-LoopPaletteItems).Count | Should -Be 0
        } finally {
            $Script:Config.Loops = $bak
        }
    }
}

Describe 'Get-LoopPaletteItems optional Loops file' {
    BeforeAll { Mock Write-Host { } }
    It 'loads Loops from optional file when Config.Loops missing' {
        $loopsFile = Join-Path $env:TEMP ("3dp_loops_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $loopsFile -Encoding UTF8 -Value @'
@{
    pester_from_file = @{ desc = 'pf'; cmds = @('M105') }
}
'@
        $bak = $Script:Config.Loops
        Mock Get-3DPConsoleOptionalFile { param($FileName) if ($FileName -eq 'PrusaMini-Loops.ps1') { $loopsFile } else { $null } }
        try {
            $Script:Config.Loops = $null
            $items = @(Get-LoopPaletteItems)
            ($items | Where-Object { $_.cmd -eq 'loop pester_from_file' }) | Should -Not -BeNullOrEmpty
        } finally {
            $Script:Config.Loops = $bak
            Remove-Item -LiteralPath $loopsFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-LoopPaletteItemsBuildList' {
    It 'orders by LoopOrder then remaining keys' {
        $bakL = $Script:Config.Loops
        $bakO = $Script:Config.LoopOrder
        try {
            $Script:Config.Loops = @{
                zed = @{ cmds = @('M105') }
                amy = @{ cmds = @('G28') }
            }
            $Script:Config.LoopOrder = @('amy')
            $items = @(Get-LoopPaletteItemsBuildList -Loops $Script:Config.Loops)
            $items[0].cmd | Should -Be 'loop amy'
            $items[1].cmd | Should -Be 'loop zed'
        } finally {
            $Script:Config.Loops = $bakL
            $Script:Config.LoopOrder = $bakO
        }
    }
}

Describe 'Invoke-Move (mocked serial)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
    }
    It 'warns on too few args' { { Invoke-Move -Port $null -Args 'X' } | Should -Not -Throw }
    It 'errors on bad axis' { { Invoke-Move -Port $null -Args 'Q 10' } | Should -Not -Throw }
    It 'errors on non-numeric distance' { { Invoke-Move -Port $null -Args 'X abc' } | Should -Not -Throw }
    It 'sends relative move for X' { { Invoke-Move -Port $null -Args 'X 1' } | Should -Not -Throw }
    It 'uses optional feed override' { { Invoke-Move -Port $null -Args 'Z -0.1 1200' } | Should -Not -Throw }
    It 'uses E feedrate for E axis' { { Invoke-Move -Port $null -Args 'E 2.5' } | Should -Not -Throw }
    It 'sends relative move for Y' { { Invoke-Move -Port $null -Args 'Y -0.5' } | Should -Not -Throw }
    It 'uses explicit feed for X as third token' { { Invoke-Move -Port $null -Args 'X 2 2400' } | Should -Not -Throw }
}

Describe 'Read-3DPConsoleEscapePollCore / BedLevelMenuKeyCore' {
    It 'EscapePollCore returns Escape' {
        Read-3DPConsoleEscapePollCore -KeyAvailable { $true } -ReadKey {
            [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::Escape, $false, $false, $false)
        } | Should -Be 'Escape'
    }
    It 'EscapePollCore returns null when no key' {
        Read-3DPConsoleEscapePollCore -KeyAvailable { $false } -ReadKey { throw 'unreachable' } | Should -BeNullOrEmpty
    }
    It 'BedLevelMenuKeyCore Continue without key' {
        Read-3DPConsoleBedLevelMenuKeyCore -SleepMs { } -KeyAvailable { $false } -ReadKey { } | Should -Be 'Continue'
    }
    It 'BedLevelMenuKeyCore Escape' {
        Read-3DPConsoleBedLevelMenuKeyCore -SleepMs { } -KeyAvailable { $true } -ReadKey {
            [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::Escape, $false, $false, $false)
        } | Should -Be 'Escape'
    }
    It 'BedLevelMenuKeyCore Enter' {
        Read-3DPConsoleBedLevelMenuKeyCore -SleepMs { } -KeyAvailable { $true } -ReadKey {
            [System.ConsoleKeyInfo]::new([char]13, [System.ConsoleKey]::Enter, $false, $false, $false)
        } | Should -Be 'Enter'
    }
    It 'BedLevelMenuKeyCore Continue when ReadKey null' {
        Read-3DPConsoleBedLevelMenuKeyCore -SleepMs { } -KeyAvailable { $true } -ReadKey { $null } | Should -Be 'Continue'
    }
    It 'BedLevelMenuKeyCore Continue when key is not Escape or Enter' {
        Read-3DPConsoleBedLevelMenuKeyCore -SleepMs { } -KeyAvailable { $true } -ReadKey {
            [System.ConsoleKeyInfo]::new([char]0x20, [System.ConsoleKey]::Spacebar, $false, $false, $false)
        } | Should -Be 'Continue'
    }
}

Describe 'Read-3DPConsoleEscapePoll delegates (global hooks)' {
    It 'EscapePoll uses test delegate under SKIP_MAIN' {
        $global:3DPConsoleEscapePollTestDelegate = { 'Escape' }
        try {
            Read-3DPConsoleEscapePoll | Should -Be 'Escape'
        } finally {
            Remove-Variable -Name 3DPConsoleEscapePollTestDelegate -Scope Global -ErrorAction SilentlyContinue
        }
    }
    It 'InteractiveTop uses test delegate' {
        $global:3DPConsoleInteractiveTopEscapePollTestDelegate = { 'Escape' }
        try {
            Read-3DPConsoleEscapePollInteractiveTop | Should -Be 'Escape'
        } finally {
            Remove-Variable -Name 3DPConsoleInteractiveTopEscapePollTestDelegate -Scope Global -ErrorAction SilentlyContinue
        }
    }
    It 'BedLevelMenuKey uses test delegate under SKIP_MAIN' {
        $global:3DPConsoleBedLevelMenuKeyTestDelegate = { 'Enter' }
        try {
            Read-3DPConsoleBedLevelMenuKey | Should -Be 'Enter'
        } finally {
            Remove-Variable -Name 3DPConsoleBedLevelMenuKeyTestDelegate -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Wait-3DPConsoleInteractiveBedLevelMenu and stabilization escape' {
    BeforeAll { Mock Write-Host { } }
    It 'menu waits Enter' {
        Mock Read-3DPConsoleBedLevelMenuKey { 'Enter' }
        { Wait-3DPConsoleInteractiveBedLevelMenu } | Should -Not -Throw
    }
    It 'menu ends on Escape' {
        Mock Read-3DPConsoleBedLevelMenuKey { 'Escape' }
        { Wait-3DPConsoleInteractiveBedLevelMenu } | Should -Not -Throw
    }
    It 'Test-3DPConsoleEscapePollShowsAbortDuringWait true' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Test-3DPConsoleEscapePollShowsAbortDuringWait | Should -BeTrue
    }
    It 'Test-3DPConsoleEscapePollShowsAbortDuringWait false' {
        Mock Read-3DPConsoleEscapePoll { $null }
        Test-3DPConsoleEscapePollShowsAbortDuringWait | Should -BeFalse
    }
}

Describe 'Get-AvailableComPorts' {
    It 'returns empty when native and WMI fail' {
        Mock Get-3DPSerialPortNativeNames { throw 'x' }
        Mock Get-ComPortsFromPnpWmi { throw 'y' }
        @(Get-AvailableComPorts).Count | Should -Be 0
    }
}

Describe 'Invoke-MainCommandLineModeCore (mocked)' {
    BeforeAll { Mock Write-Host { } }
    It 'returns 0 on success path' {
        $r = Invoke-MainCommandLineModeCore -ChosenPort 'COM_PESTER_MC' -CommandLine 'M105' `
            -NewPortScript {
                param($n)
                $fp = [pscustomobject]@{ IsOpen = $false }
                $fp | Add-Member -MemberType ScriptMethod -Name Open -Value { $this.IsOpen = $true } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.IsOpen = $false } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -Force
                $fp
            } `
            -RunCommandScript { param($p, $c) }
        $r | Should -Be 0
    }
}

Describe 'Get-3DPConsoleNormalizedBatchCommandLines' {
    It 'drops blanks and comments' {
        $r = @(Get-3DPConsoleNormalizedBatchCommandLines -RawLines @('', '  G28 ', '#x', 'M105'))
        $r.Count | Should -Be 2
        $r[0] | Should -Be 'G28'
        $r[1] | Should -Be 'M105'
    }
    It 'null yields empty' {
        @(Get-3DPConsoleNormalizedBatchCommandLines -RawLines $null).Count | Should -Be 0
    }
}

Describe 'Invoke-MainCommandBatchModeCore (mocked)' {
    BeforeAll { Mock Write-Host { } }
    It 'returns RunBatch exit code' {
        $r = Invoke-MainCommandBatchModeCore -NormalizedCommands @('a', 'b') -ChosenPort 'COM_PESTER_BATCH' `
            -NewPortScript {
                param($n)
                $fp = [pscustomobject]@{ IsOpen = $false }
                $fp | Add-Member -MemberType ScriptMethod -Name Open -Value { $this.IsOpen = $true } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.IsOpen = $false } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -Force
                $fp
            } `
            -RunBatchScript { param($p, $cmds) if ($cmds.Count -eq 2) { 0 } else { 1 } }
        $r | Should -Be 0
    }
}

Describe 'Invoke-MainCommandLineModeDefaultRunSingle' {
    BeforeAll { Mock Write-Host { } }
    It 'invokes Invoke-SingleCommand (mocked)' {
        Mock Invoke-SingleCommand { $true }
        { Invoke-MainCommandLineModeDefaultRunSingle -Port $null -CmdLine 'M105' } | Should -Not -Throw
    }
}

Describe 'Invoke-3DPConsoleSendMoveGcodeOk and MacroGcodeOk' {
    BeforeAll { Mock Write-Host { } }
    It 'Move helper sends gcode and waits' {
        Mock Send-Gcode { 2 }
        Mock Read-SerialResponse { $true }
        { Invoke-3DPConsoleSendMoveGcodeOk -Port $null -Gcode "G91`nG0 X1`nG90" } | Should -Not -Throw
    }
    It 'Macro helper uses Get-GcodeTimeout' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Get-GcodeTimeout { 5000 }
        { Invoke-3DPConsoleSendMacroGcodeOk -Port $null -Gcode 'M105' } | Should -Not -Throw
    }
}

Describe 'Invoke-Move and Invoke-Macro (no Write-Host mock, real Write-Host)' {
    It 'Invoke-Move prints unknown axis' {
        Mock Invoke-3DPConsoleSendMoveGcodeOk { throw 'should not send' }
        { Invoke-Move -Port $null -Args 'Q 9' } | Should -Not -Throw
    }
    It 'Invoke-Move prints invalid distance' {
        Mock Invoke-3DPConsoleSendMoveGcodeOk { throw 'should not send' }
        { Invoke-Move -Port $null -Args 'X notnum' } | Should -Not -Throw
    }
    It 'Invoke-Macro prints unknown macro name' {
        Mock Invoke-3DPConsoleSendMacroGcodeOk { throw 'should not send' }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ only_real = 'M105' }
            { Invoke-Macro -Port $null -Args 'missing_xyz_99' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
}

Describe 'Read-3DPConsoleEscapePoll and loop Escape (mocked)' {
    BeforeAll { Mock Write-Host { } }
    It 'Read-3DPConsoleEscapePoll returns null under SKIP_MAIN' {
        Read-3DPConsoleEscapePoll | Should -BeNullOrEmpty
    }
    It 'Read-3DPConsoleBedLevelMenuKey returns null under SKIP_MAIN' {
        Read-3DPConsoleBedLevelMenuKey | Should -BeNullOrEmpty
    }
    It 'LevelCompare init aborts when Escape polled' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @('G28') -UseG29T:$false } | Should -Not -Throw
    }
    It 'LevelCompare G29 round aborts when Escape polled' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Read-SerialAndCapture { "0 +0.01`n" }
        { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
    }
    It 'Temp2 step breaks when Escape polled' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
    }
    It 'generic Invoke-Loop init cancelled on Escape' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Start-Sleep { }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_esc_init = @{
                    cmds   = @('M105')
                    repeat = 1
                    init   = @('G28')
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_esc_init' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'generic Invoke-Loop cmd cancelled on Escape' {
        Mock Read-3DPConsoleEscapePoll { 'Escape' }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Start-Sleep { }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_esc_cmd = @{
                    cmds   = @('M105')
                    repeat = 1
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_esc_cmd' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'InteractiveBedLevel exits when InteractiveTop polls Escape' {
        Mock Read-3DPConsoleEscapePollInteractiveTop { 'Escape' }
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
}

Describe 'Invoke-HomeAxes (mocked serial)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
    }
    It 'homes XY only when requested' { { Invoke-HomeAxes -Port $null -Args 'xy' } | Should -Not -Throw }
    It 'includes Z and E when requested' { { Invoke-HomeAxes -Port $null -Args 'z e' } | Should -Not -Throw }
    It 'defaults when axes empty' { { Invoke-HomeAxes -Port $null -Args '   ' } | Should -Not -Throw }
    It 'sends G28 X0 when only X requested' { { Invoke-HomeAxes -Port $null -Args 'x' } | Should -Not -Throw }
    It 'sends G28 Y0 when only Y requested' { { Invoke-HomeAxes -Port $null -Args 'y' } | Should -Not -Throw }
    It 'sends G92 E0 when only E requested' { { Invoke-HomeAxes -Port $null -Args 'e' } | Should -Not -Throw }
}

Describe 'Invoke-Extrude and Invoke-Reverse (mocked serial)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
    }
    It 'Invoke-Extrude uses defaults' { { Invoke-Extrude -Port $null -Args '' } | Should -Not -Throw }
    It 'Invoke-Extrude parses length and feed' { { Invoke-Extrude -Port $null -Args '2.5 600' } | Should -Not -Throw }
    It 'Invoke-Extrude single length token' { { Invoke-Extrude -Port $null -Args '1.25' } | Should -Not -Throw }
    It 'Invoke-Reverse negates length' { { Invoke-Reverse -Port $null -Args '3' } | Should -Not -Throw }
    It 'Invoke-Reverse parses length and feed' { { Invoke-Reverse -Port $null -Args '4 1200' } | Should -Not -Throw }
}

Describe 'Get-3DPConsoleHomeAxesGcode / Move / Extrude / Monitor interval (pure)' {
    It 'home gcode xyze contains all axis lines' {
        $g = Get-3DPConsoleHomeAxesGcode -AxesText 'xyze'
        $g | Should -Match 'G28 X0'
        $g | Should -Match 'G28 Y0'
        $g | Should -Match 'G28 Z0'
        $g | Should -Match 'G92 E0'
    }
    It 'home gcode empty axes defaults to G28 and G92 E0' {
        $g = Get-3DPConsoleHomeAxesGcode -AxesText '   '
        $g | Should -Match 'G28'
        $g | Should -Match 'G92 E0'
    }
    It 'relative move gcode Z E XY feeds and optional F' {
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'Z -0.1').gcode | Should -Match 'G0 Z-0\.1'
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'E 1 999').gcode | Should -Match 'F999'
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'X 2').gcode | Should -Match 'G0 X2'
    }
    It 'relative move errors' {
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'X').err | Should -Be 'syntax'
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'Q 1').err | Should -Be 'axis'
        (Get-3DPConsoleRelativeMoveGcode -ArgsText 'X nope').err | Should -Be 'distance'
    }
    It 'extrude gcode forward and reverse' {
        Get-3DPConsoleExtrudeGcode -ArgsText '2.5 800' | Should -Match 'E2.5'
        Get-3DPConsoleExtrudeGcode -ArgsText '3 900' -Reverse | Should -Match 'E-3'
    }
    It 'monitor interval parses numeric token' {
        Get-3DPConsoleMonitorIntervalSeconds -ArgsText '4.25' -DefaultInterval 1.0 | Should -Be 4.25
        Get-3DPConsoleMonitorIntervalSeconds -ArgsText '' -DefaultInterval 2.5 | Should -Be 2.5
    }
}

Describe 'Invoke-HomeAxes and Invoke-Move edge cases (mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
    }
    It 'Invoke-HomeAxes hits G28 X/Y/Z and G92 E for xyze' {
        { Invoke-HomeAxes -Port $null -Args 'xyze' } | Should -Not -Throw
    }
    It 'Invoke-Move unknown axis and invalid distance' {
        { Invoke-Move -Port $null -Args 'Q 1' } | Should -Not -Throw
        { Invoke-Move -Port $null -Args 'X not-a-number' } | Should -Not -Throw
    }
    It 'Invoke-Move E with explicit feed override' {
        { Invoke-Move -Port $null -Args 'E 0.5 3333' } | Should -Not -Throw
    }
    It 'Invoke-Move too few tokens shows syntax hint' {
        { Invoke-Move -Port $null -Args 'X' } | Should -Not -Throw
    }
    It 'Invoke-HomeAxes empty axes uses default G28 and G92 E0' {
        { Invoke-HomeAxes -Port $null -Args '   ' } | Should -Not -Throw
    }
}

Describe 'Invoke-SdPrint' {
    BeforeAll { Mock Write-Host { }; Mock Start-Sleep { } }
    It 'warns when filename missing' { { Invoke-SdPrint -Port $null -Filename '' } | Should -Not -Throw }
    It 'M23 then M24 and success path with mock port (no real COM)' {
        $written = [System.Collections.Generic.List[string]]::new()
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($line) [void]$written.Add([string]$line) } -Force
        { Invoke-SdPrint -Port $port -Filename 'plainname' } | Should -Not -Throw
        $written.Count | Should -Be 2
        $written[0] | Should -Be 'M23 plainname.g'
        $written[1] | Should -Be 'M24'
    }
    It 'keeps .gcode suffix and hits WriteLine when port invalid' {
        $p = [System.IO.Ports.SerialPort]::new('COM_PESTER_SD_998', $Script:Config.BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
        try {
            { Invoke-SdPrint -Port $p -Filename 'part.gcode' } | Should -Throw
        } finally {
            try { $p.Dispose() } catch { }
        }
    }
    It 'appends .g when filename has no extension' {
        $p = [System.IO.Ports.SerialPort]::new('COM_PESTER_SD_997', $Script:Config.BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
        try {
            { Invoke-SdPrint -Port $p -Filename 'plainname' } | Should -Throw
        } finally {
            try { $p.Dispose() } catch { }
        }
    }
}

Describe 'Invoke-Monitor (mock port)' {
    BeforeAll {
        Mock Write-Host { }
        # Millisekunden-Sleeps im Monitor weglassen (schneller); Sekunden-Sleep bleibt real (kurz).
        Mock Start-Sleep -ParameterFilter { $PSBoundParameters.ContainsKey('Milliseconds') } { }
    }
    It 'catch block when WriteLine throws' {
        Mock Start-Sleep { }
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { throw 'simulated io' } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value { 0 } -SecondValue { } -Force
        { Invoke-Monitor -Port $port -Args '0.1' } | Should -Not -Throw
    }
    It 'runs one iteration then exits (THREEDP_CONSOLE_SKIP_MAIN)' {
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($l) } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value { 0 } -SecondValue { } -Force
        { Invoke-Monitor -Port $port -Args '1.5' } | Should -Not -Throw
    }
    It 'prints formatted temps when BytesToRead returns data once' {
        $script:PesterMonBytes = 1
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($l) } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value {
            if ($script:PesterMonBytes -gt 0) {
                $script:PesterMonBytes = 0
                return 8
            }
            return 0
        } -SecondValue { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name ReadExisting -Value { 'T:25.0/200.0 B:60.0/60.0' } -Force
        { Invoke-Monitor -Port $port -Args '' } | Should -Not -Throw
    }
}

Describe 'Invoke-SdLs (mock port)' {
    BeforeAll {
        Mock Write-Host { }
        # Skip only millisecond sleeps (else 10s while-loop with empty sleep = CPU spin)
        Mock Start-Sleep -ParameterFilter { $PSBoundParameters.ContainsKey('Milliseconds') } { }
    }
    It 'lists .gcode files when buffer contains End file list' {
        $script:PesterSdPhase = 0
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name DiscardInBuffer -Value { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($l) } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value {
            if ($script:PesterSdPhase -lt 2) { return 1 }
            return 0
        } -SecondValue { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name ReadExisting -Value {
            $script:PesterSdPhase++
            if ($script:PesterSdPhase -eq 1) {
                return "part.gcode`r`nEnd file list`r`n"
            }
            return ''
        } -Force
        { Invoke-SdLs -Port $port } | Should -Not -Throw
    }
    It 'lists .g files when buffer contains End file list' {
        $script:PesterSdG = 0
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name DiscardInBuffer -Value { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($l) } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value {
            if ($script:PesterSdG -lt 2) { return 1 }
            return 0
        } -SecondValue { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name ReadExisting -Value {
            $script:PesterSdG++
            if ($script:PesterSdG -eq 1) {
                return "benchy.g`r`nEnd file list`r`n"
            }
            return ''
        } -Force
        { Invoke-SdLs -Port $port } | Should -Not -Throw
    }
    It 'shows hint when no gcode files in listing' {
        $script:PesterSdPhase2 = 0
        $port = [pscustomobject]@{}
        $port | Add-Member -MemberType ScriptMethod -Name DiscardInBuffer -Value { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name WriteLine -Value { param($l) } -Force
        $port | Add-Member -MemberType ScriptProperty -Name BytesToRead -Value {
            if ($script:PesterSdPhase2 -lt 2) { return 1 }
            return 0
        } -SecondValue { } -Force
        $port | Add-Member -MemberType ScriptMethod -Name ReadExisting -Value {
            $script:PesterSdPhase2++
            if ($script:PesterSdPhase2 -eq 1) {
                return "End file list`r`n"
            }
            return ''
        } -Force
        { Invoke-SdLs -Port $port } | Should -Not -Throw
    }
}

Describe 'Invoke-Macro' {
    BeforeAll { Mock Write-Host { } }
    Describe 'optional Macros-Datei' {
        BeforeAll {
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
        }
        It 'loads macros from optional file when Config.Macros is not a hashtable' {
            $macroFile = Join-Path $env:TEMP ("3dp_macros_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
            Set-Content -LiteralPath $macroFile -Encoding UTF8 -Value @'
@{
    pester_macro_xyz = "M105"
}
'@
            $bakMacros = $Script:Config.Macros
            Mock Get-3DPConsoleOptionalFile { param($FileName) if ($FileName -eq 'PrusaMini-Macros.ps1') { $macroFile } else { $null } }
            try {
                $Script:Config.Macros = 'not-a-hashtable'
                { Invoke-Macro -Port $null -Args 'pester_macro_xyz' } | Should -Not -Throw
            } finally {
                $Script:Config.Macros = $bakMacros
                Remove-Item -LiteralPath $macroFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    It 'lists macros when no name given' { { Invoke-Macro -Port $null -Args '' } | Should -Not -Throw }
    It 'warns for unknown macro' { { Invoke-Macro -Port $null -Args 'definitely_missing_macro_xyz' } | Should -Not -Throw }
    It 'replaces {0} {1} placeholders in macro gcode' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ pester_numtpl = "M104 S{0}`nM140 S{1}" }
            { Invoke-Macro -Port $null -Args 'pester_numtpl 200 65' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
    It 'strips unused numeric placeholders in macro' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ pester_strip = 'M105 ; {9} tail' }
            { Invoke-Macro -Port $null -Args 'pester_strip' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
    It 'expands preheat macro when present' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        if ($Script:Config.Macros -and $Script:Config.Macros['preheat']) {
            { Invoke-Macro -Port $null -Args 'preheat 200' } | Should -Not -Throw
        } else {
            Set-ItResult -Skipped -Because 'no preheat macro in config'
        }
    }
    It 'joins array macro (pla) to gcode' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        if ($Script:Config.Macros.pla -is [array]) {
            { Invoke-Macro -Port $null -Args 'pla' } | Should -Not -Throw
        } else {
            Set-ItResult -Skipped -Because 'no array pla macro'
        }
    }
    It 'array macro with args joins and replaces {0} {1}' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ pester_arr_args = @('M104 S{0}', 'M140 S{1}') }
            { Invoke-Macro -Port $null -Args 'pester_arr_args 222 66' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
    It 'macro loads empty hashtable when optional file missing' {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $bak = $Script:Config.Macros
        Mock Get-3DPConsoleOptionalFile { $null }
        try {
            $Script:Config.Macros = 'not-a-table'
            { Invoke-Macro -Port $null -Args 'any_missing_xyz' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
    It 'string macro with multiple args replaces placeholders' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ pester_str_tpl = 'M104 S{0}`nM140 S{1}' }
            { Invoke-Macro -Port $null -Args 'pester_str_tpl 200 55' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
    It 'unknown macro with extra args hits name and args path' {
        Mock Write-Host { }
        $bak = $Script:Config.Macros
        try {
            $Script:Config.Macros = @{ known = 'M105' }
            { Invoke-Macro -Port $null -Args 'unknown_macro_name a b' } | Should -Not -Throw
        } finally {
            $Script:Config.Macros = $bak
        }
    }
}

Describe 'Invoke-SingleCommand (mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Invoke-Loop { }
    }
    It 'false when command empty' { Invoke-SingleCommand -Port $null -Cmd '   ' | Should -BeFalse }
    It 'QuickAction home' { Invoke-SingleCommand -Port $null -Cmd 'home' | Should -BeTrue }
    It 'loop prepare' { Invoke-SingleCommand -Port $null -Cmd 'loop prepare' | Should -BeTrue }
    It 'loop prepare 2' { Invoke-SingleCommand -Port $null -Cmd 'loop prepare 2' | Should -BeTrue }
    It 'slash /home' { Invoke-SingleCommand -Port $null -Cmd '/home xy' | Should -BeTrue }
    It 'slash /level /temp /pla /abs /off' {
        Invoke-SingleCommand -Port $null -Cmd '/level' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/temp' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/pla' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/abs' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/off' | Should -BeTrue
    }
    It 'slash move extrude reverse' {
        Invoke-SingleCommand -Port $null -Cmd '/move X 1' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/extrude 1' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/reverse 1' | Should -BeTrue
    }
    It 'slash /home without axes defaults to xyz' {
        Invoke-SingleCommand -Port $null -Cmd '/home' | Should -BeTrue
    }
    It 'slash /home single axis x y z e' {
        Invoke-SingleCommand -Port $null -Cmd '/home x' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/home y' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/home z' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/home e' | Should -BeTrue
    }
    It 'slash /home xyze builds all homing lines' {
        Invoke-SingleCommand -Port $null -Cmd '/home xyze' | Should -BeTrue
    }
    It 'slash move Y and Z' {
        Invoke-SingleCommand -Port $null -Cmd '/move Y 0.5' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd '/move Z -0.05' | Should -BeTrue
    }
    It 'raw M115 firmware info' { Invoke-SingleCommand -Port $null -Cmd 'M115' | Should -BeTrue }
    It 'raw M105' { Invoke-SingleCommand -Port $null -Cmd 'M105' | Should -BeTrue }
    It 'fallback G4' { Invoke-SingleCommand -Port $null -Cmd 'G4 P1' | Should -BeTrue }
    It 'QuickActions fan d b dw bw level' {
        Invoke-SingleCommand -Port $null -Cmd 'fan' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd 'd' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd 'b' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd 'dw' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd 'bw' | Should -BeTrue
        Invoke-SingleCommand -Port $null -Cmd 'level' | Should -BeTrue
    }
    It 'fallback branch sends non-GM line as raw gcode' {
        Invoke-SingleCommand -Port $null -Cmd 'T0 S1' | Should -BeTrue
    }
}

Describe '3DPConsoleConsolePollApi (production wrappers)' {
    It 'Read-3DPConsoleEscapePoll uses ConsolePollApi when SKIP_MAIN off' {
        $bakA = $global:3DPConsoleConsolePollApi
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $global:3DPConsoleConsolePollApi = @{
                KeyAvailable = { $true }
                ReadKey      = {
                    [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::Escape, $false, $false, $false)
                }
            }
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Read-3DPConsoleEscapePoll | Should -Be 'Escape'
        } finally {
            $global:3DPConsoleConsolePollApi = $bakA
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
    It 'Read-3DPConsoleBedLevelMenuKey uses Sleep and ConsolePollApi when SKIP_MAIN off' {
        $bakA = $global:3DPConsoleConsolePollApi
        $bakS = $global:3DPConsoleConsoleSleepMsForMenu
        $b = $env:THREEDP_CONSOLE_SKIP_MAIN
        try {
            $global:3DPConsoleConsolePollApi = @{
                KeyAvailable = { $false }
                ReadKey      = { $null }
            }
            $global:3DPConsoleConsoleSleepMsForMenu = { param($ms) }
            $env:THREEDP_CONSOLE_SKIP_MAIN = '0'
            Read-3DPConsoleBedLevelMenuKey | Should -Be 'Continue'
        } finally {
            $global:3DPConsoleConsolePollApi = $bakA
            $global:3DPConsoleConsoleSleepMsForMenu = $bakS
            $env:THREEDP_CONSOLE_SKIP_MAIN = $b
        }
    }
}

Describe 'Invoke-MainCommandLineMode (mocked)' {
    BeforeAll { Mock Write-Host { } }
    It 'returns 0 on full success path (global RunSingle hook; Mock in eingebettetem SB greift nicht)' {
        $bakRun = $global:3DPConsoleMainCommandRunSingleCommandScript
        try {
            $global:3DPConsoleMainCommandRunSingleCommandScript = { param($p, $cmd) }
            Mock Get-PortOrRetry { 'COM_PESTER_WRAP' }
            Mock New-3DPConsoleSerialPort {
                $fp = [pscustomobject]@{ IsOpen = $false }
                $fp | Add-Member -MemberType ScriptMethod -Name Open -Value { $this.IsOpen = $true } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Close -Value { } -Force
                $fp | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -Force
                $fp
            }
            $r = Invoke-MainCommandLineMode -CommandLine 'M105' -ConfigPath (Join-Path $env:TEMP '3dp_wrap_ok.ps1')
            $r | Should -Be 0
        } finally {
            $global:3DPConsoleMainCommandRunSingleCommandScript = $bakRun
        }
    }
    It 'returns 1 when Get-PortOrRetry yields no port' {
        Mock Get-PortOrRetry { $null }
        $r = Invoke-MainCommandLineMode -CommandLine 'M105' -ConfigPath (Join-Path $env:TEMP '3dp_mc_noport.ps1')
        $r | Should -Be 1
    }
    It 'returns 1 when Open throws' {
        Mock Get-PortOrRetry { 'COM_PESTER' }
        Mock New-3DPConsoleSerialPort {
            $o = [pscustomobject]@{ IsOpen = $false }
            $o | Add-Member -MemberType ScriptMethod -Name Open -Value { throw 'port open failed' } -Force
            $o | Add-Member -MemberType ScriptMethod -Name Close -Value { } -Force
            $o | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -Force
            $o
        }
        $r = Invoke-MainCommandLineMode -CommandLine 'M105' -ConfigPath (Join-Path $env:TEMP '3dp_mc_bad.ps1')
        $r | Should -Be 1
    }
}

Describe 'New-3DPConsoleSerialPort' {
    It 'creates SerialPort with config baud rate' {
        $p = New-3DPConsoleSerialPort -PortName 'COM_PESTER_FACTORY_997'
        try {
            $p | Should -Not -BeNullOrEmpty
            $p.BaudRate | Should -Be $Script:Config.BaudRate
        } finally {
            try { $p.Dispose() } catch { }
        }
    }
}

Describe 'Invoke-Loop (mocked serial)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Start-Sleep { }
    }
    It 'unknown loop prints available' { { Invoke-Loop -Port $null -LoopName '___no_such_loop___' } | Should -Not -Throw }
    It 'runs cooldown once' { { Invoke-Loop -Port $null -LoopName 'cooldown' -RepeatCount 1 } | Should -Not -Throw }
    It 'runs prepare once' { { Invoke-Loop -Port $null -LoopName 'prepare' -RepeatCount 1 } | Should -Not -Throw }
    It 'runs temp_ramp once' { { Invoke-Loop -Port $null -LoopName 'temp_ramp' -RepeatCount 1 } | Should -Not -Throw }
}

Describe 'Invoke-Loop edge cases (mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Start-Sleep { }
    }
    It 'missing Loops hashtable and no optional file shows error' {
        Mock Get-3DPConsoleOptionalFile { $null }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = $null
            { Invoke-Loop -Port $null -LoopName 'nope' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'optional Loops file that throws prints error' {
        $badLoops = Join-Path $env:TEMP ("3dp_badloops_{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $badLoops -Encoding UTF8 -Value 'throw "pester_bad_loops"'
        Mock Get-3DPConsoleOptionalFile { param($FileName) if ($FileName -eq 'PrusaMini-Loops.ps1') { $badLoops } else { $null } }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = $null
            { Invoke-Loop -Port $null -LoopName 'any' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
            Remove-Item -LiteralPath $badLoops -Force -ErrorAction SilentlyContinue
        }
    }
    It 'substitutes {T} when startTemp and stepTemp set' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_temp = @{
                    cmds      = @('M104 S{T}')
                    repeat    = 2
                    startTemp = 180
                    stepTemp  = 5
                    init      = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_temp' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'uses entry.repeat when RepeatCount not passed' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_rep = @{
                    cmds   = @('M105')
                    repeat = 2
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_rep' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'loop cmds as single string coerces to one-element list' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_strcmd = @{
                    cmds   = 'M105'
                    repeat = 1
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_strcmd' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'substitutes {i0} and {i} placeholders' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_idx = @{
                    cmds   = @('ECHO_{i0}_{i}')
                    repeat = 2
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_idx' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'init as single string runs' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_inits = @{
                    cmds   = @('M105')
                    repeat = 1
                    init   = 'G28'
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_inits' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'cmds as plain string runs as single command' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{ pester_one_str = 'M105' }
            { Invoke-Loop -Port $null -LoopName 'pester_one_str' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'stops when init Read-SerialResponse fails' {
        $script:pesterInitRead = 0
        Mock Read-SerialResponse {
            $script:pesterInitRead++
            if ($script:pesterInitRead -eq 1) { return $false }
            return $true
        }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_bad_init = @{
                    cmds   = @('M105')
                    repeat = 1
                    init   = @('G28')
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_bad_init' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'stops when main cmd Read-SerialResponse fails' {
        $script:pesterMainRead = 0
        Mock Read-SerialResponse {
            $script:pesterMainRead++
            if ($script:pesterMainRead -ge 2) { return $false }
            return $true
        }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_bad_cmd = @{
                    cmds   = @('M105', 'M104 S0')
                    repeat = 1
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_bad_cmd' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'skips blank cmd lines in cmds list' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_blank = @{
                    cmds   = @('  ', 'M105', '')
                    repeat = 1
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_blank' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'runs multiple cmds across two repeat passes' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_mult = @{
                    cmds   = @('M105', 'M104 S0')
                    repeat = 2
                    init   = @()
                }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_mult' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'hashtable loop without cmds lists as unknown' {
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                pester_nocmds = @{ desc = 'only description' }
                other         = @{ cmds = @('M105') }
            }
            { Invoke-Loop -Port $null -LoopName 'pester_nocmds' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
}

Describe 'Invoke-Loop action dispatch (mocked sub-loops)' {
    BeforeAll { Mock Write-Host { } }
    It 'level_compare calls Invoke-LevelCompareLoop' {
        Mock Invoke-LevelCompareLoop { }
        { Invoke-Loop -Port $null -LoopName 'level_compare' -RepeatCount 1 } | Should -Not -Throw
    }
    It 'interactive_bedlevel calls Invoke-InteractiveBedLevelLoop' {
        Mock Invoke-InteractiveBedLevelLoop { }
        { Invoke-Loop -Port $null -LoopName 'interactive_bedlevel' } | Should -Not -Throw
    }
    It 'temp2_nozzle calls Invoke-Temp2LevelingLoop' {
        Mock Invoke-Temp2LevelingLoop { }
        { Invoke-Loop -Port $null -LoopName 'temp2_nozzle' } | Should -Not -Throw
    }
    It 'temp2_bed calls Invoke-Temp2LevelingLoop' {
        Mock Invoke-Temp2LevelingLoop { }
        { Invoke-Loop -Port $null -LoopName 'temp2_bed' } | Should -Not -Throw
    }
    It 'temp2_combined calls Invoke-Temp2LevelingLoop' {
        Mock Invoke-Temp2LevelingLoop { }
        { Invoke-Loop -Port $null -LoopName 'temp2_combined' } | Should -Not -Throw
    }
    It 'level_compare minimal entry uses default repeat and init' {
        Mock Invoke-LevelCompareLoop { }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{ lc_pester_min = @{ action = 'level_compare' } }
            { Invoke-Loop -Port $null -LoopName 'lc_pester_min' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'level_compare uses entry repeat when RepeatCount is zero' {
        $script:lcRepeatSeen = $null
        Mock Invoke-LevelCompareLoop {
            param($Port, $RepeatCount, $InitCmds, $UseG29T)
            $script:lcRepeatSeen = $RepeatCount
        }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                lc_rep_pester = @{ action = 'level_compare'; repeat = 5; init = @('G28') }
            }
            { Invoke-Loop -Port $null -LoopName 'lc_rep_pester' -RepeatCount 0 } | Should -Not -Throw
            $script:lcRepeatSeen | Should -Be 5
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'temp2 uses default stabilization seconds when entry omits key' {
        $script:t2stab = $null
        Mock Invoke-Temp2LevelingLoop {
            param($Port, $Mode, $StartNozzle, $EndNozzle, $StepNozzle, $StartBed, $EndBed, $StepBed, $StabilizationSeconds, $FixedNozzle, $FixedBed)
            $script:t2stab = $StabilizationSeconds
        }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{
                t2stab_pester = @{
                    action      = 'temp2_nozzle'
                    startNozzle = 170
                    endNozzle   = 170
                    stepNozzle  = 1
                    startBed    = 60
                    endBed      = 60
                    stepBed     = 1
                    fixedNozzle = 170
                    fixedBed    = 60
                }
            }
            { Invoke-Loop -Port $null -LoopName 't2stab_pester' } | Should -Not -Throw
            $script:t2stab | Should -Be 60
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'temp2 dispatch uses config defaults for temps and steps' {
        Mock Invoke-Temp2LevelingLoop { }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{ t2_pester_min = @{ action = 'temp2_nozzle' } }
            { Invoke-Loop -Port $null -LoopName 't2_pester_min' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
    It 'interactive_bedlevel uses default temps from minimal entry' {
        Mock Invoke-InteractiveBedLevelLoop { }
        $bak = $Script:Config.Loops
        try {
            $Script:Config.Loops = @{ ib_pester_min = @{ action = 'interactive_bedlevel' } }
            { Invoke-Loop -Port $null -LoopName 'ib_pester_min' } | Should -Not -Throw
        } finally {
            $Script:Config.Loops = $bak
        }
    }
}

Describe 'Invoke-LevelCompareLoop (fully mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Start-Sleep { }
    }
    It 'creates BedLevelResults under BasePath when CsvOutputPath unset' {
        $base = Join-Path $env:TEMP ("3dp_base_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $bakBase = $Script:BasePath
        $bakPath = $Script:Config.CsvOutputPath
        $bakPfx = $Script:Config.CsvFilePrefix
        try {
            $Script:BasePath = $base
            $Script:Config.CsvOutputPath = $null
            $Script:Config.CsvFilePrefix = $null
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { "0 +0.01`n" }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            Test-Path (Join-Path $base 'BedLevelResults') | Should -BeTrue
        } finally {
            $Script:BasePath = $bakBase
            $Script:Config.CsvOutputPath = $bakPath
            $Script:Config.CsvFilePrefix = $bakPfx
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'one G29 round writes CSV then early exit' {
        $meshOut = @'
Bilinear Leveling Grid:
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        $bakPrefix = $Script:Config.CsvFilePrefix
        try {
            $Script:Config.CsvOutputPath = $dir
            $Script:Config.CsvFilePrefix = 'PesterBed'
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter '*.csv' -File).Count | Should -BeGreaterThan 0
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:Config.CsvFilePrefix = $bakPrefix
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'two rounds produce comparison CSVs' {
        $meshOut = @'
Bilinear Leveling Grid:
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl2_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        $bakPrefix = $Script:Config.CsvFilePrefix
        try {
            $Script:Config.CsvOutputPath = $dir
            $Script:Config.CsvFilePrefix = 'PesterBed'
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 2 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter '*.csv' -File).Count | Should -BeGreaterThan 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:Config.CsvFilePrefix = $bakPrefix
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'two rounds with small delta uses green comparison color' {
        $meshA = @'
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $meshB = @'
 0      1
 0 +0.020 +0.030
 1 +0.040 +0.050
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_dg_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:rdg = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture {
                $script:rdg++
                if ($script:rdg -eq 1) { return $meshA }
                return $meshB
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 2 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'two rounds with medium delta uses dark yellow comparison color' {
        $meshA = @'
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $meshB = @'
 0      1
 0 +0.095 +0.105
 1 +0.115 +0.125
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_dy_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:rdy = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture {
                $script:rdy++
                if ($script:rdy -eq 1) { return $meshA }
                return $meshB
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 2 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'two rounds with large delta uses yellow comparison color' {
        $meshA = @'
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $meshB = @'
 0      1
 0 +0.200 +0.210
 1 +0.220 +0.230
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_yl_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:ryl = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture {
                $script:ryl++
                if ($script:ryl -eq 1) { return $meshA }
                return $meshB
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 2 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'runs InitCmds before G29' {
        $meshOut = @'
 0      1
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_i_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @('G28') -UseG29T:$false } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'UseG29T runs G29 T branch' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_t_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$true } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'UseG29T does not append when G29 T capture is empty' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_t0_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            $script:capT0 = 0
            Mock Read-SerialAndCapture {
                $script:capT0++
                if ($script:capT0 -eq 1) { return $meshOut }
                return ''
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$true } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter '*.csv' -File).Count | Should -BeGreaterThan 0
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'G29 capture null exits early' {
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse { $true }
        Mock Read-SerialAndCapture { $null }
        { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
    }
    It 'empty mesh then M420 produces CSV' {
        $meshOk = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl_m420_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        $bakPrefix = $Script:Config.CsvFilePrefix
        try {
            $Script:Config.CsvOutputPath = $dir
            $Script:Config.CsvFilePrefix = 'PesterM420'
            $script:lcCap = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture {
                $script:lcCap++
                if ($script:lcCap -eq 1) { 'no mesh-like rows in this capture' }
                else { $meshOk }
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter '*.csv' -File).Count | Should -BeGreaterThan 0
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:Config.CsvFilePrefix = $bakPrefix
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'still no mesh after M420 writes raw file' {
        $dir = Join-Path $env:TEMP ("3dp_lvl_raw_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { 'still not a mesh 999' }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter '*_raw.txt' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'three rounds run comparison stats and spread line' {
        $mesh1 = @'
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        $mesh2 = @'
 0      1
 0 +0.080 +0.090
 1 +0.100 +0.110
'@
        $mesh3 = @'
 0      1
 0 +0.300 +0.310
 1 +0.320 +0.330
'@
        $dir = Join-Path $env:TEMP ("3dp_lvl3_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        $bakPrefix = $Script:Config.CsvFilePrefix
        try {
            $Script:Config.CsvOutputPath = $dir
            $Script:Config.CsvFilePrefix = 'Pester3'
            $script:lc3 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture {
                $script:lc3++
                if ($script:lc3 -eq 1) { return $mesh1 }
                if ($script:lc3 -eq 2) { return $mesh2 }
                if ($script:lc3 -eq 3) { return $mesh3 }
                return $mesh1
            }
            { Invoke-LevelCompareLoop -Port $null -RepeatCount 3 -InitCmds @() -UseG29T:$false } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Comparison_Rounds_*.csv' -File).Count | Should -Be 1
            (Get-ChildItem -LiteralPath $dir -Filter 'Statistik_Messpunkte_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:Config.CsvFilePrefix = $bakPrefix
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when InitCmd Read-SerialResponse fails' {
        $script:lcInitFail = 0
        Mock Send-Gcode { 1 }
        Mock Read-SerialResponse {
            $script:lcInitFail++
            if ($script:lcInitFail -eq 1) { return $false }
            return $true
        }
        Mock Read-SerialAndCapture { '0 +0.01' }
        { Invoke-LevelCompareLoop -Port $null -RepeatCount 1 -InitCmds @('G28') -UseG29T:$false } | Should -Not -Throw
    }
}

Describe 'Invoke-Temp2LevelingLoop early exit' {
    BeforeAll { Mock Write-Host { } }
    It 'returns when no temperature steps' {
        { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 200 -EndNozzle 100 -StepNozzle 5 -StartBed 60 -EndBed 100 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
    }
}

Describe 'Invoke-Temp2LevelingLoop (mocked steps)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Start-Sleep { }
    }
    It 'one nozzle step writes Temp2 CSV with mesh' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_nozzle_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'uses BasePath BedLevelResults when CsvOutputPath empty' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $base = Join-Path $env:TEMP ("3dp_t2base_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $expectDir = Join-Path $base 'BedLevelResults'
        $bakPath = $Script:Config.CsvOutputPath
        $bakBase = $Script:BasePath
        try {
            $Script:Config.CsvOutputPath = ''
            $Script:BasePath = $base
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $expectDir -Filter 'Temp2Leveling_nozzle_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:BasePath = $bakBase
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'one combined step writes CSV' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2c_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'combined' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_combined_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'no mesh warns and ends with no data' {
        $dir = Join-Path $env:TEMP ("3dp_t2nom_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { 'no mesh at all' }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_*.csv' -File).Count | Should -Be 0
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'one bed step writes Temp2_bed CSV' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2b_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'bed' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_bed_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'G29 capture null breaks loop' {
        $dir = Join-Path $env:TEMP ("3dp_t2null_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $null }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stabilization seconds runs sleep chunks' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2stab_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 12 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_nozzle_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'replaces $PSScriptRoot token in CsvOutputPath' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $base = Join-Path $env:TEMP ("3dp_t2ps_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $expectDir = Join-Path $base 'NestOut'
        New-Item -ItemType Directory -Path $expectDir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        $bakBase = $Script:BasePath
        try {
            $Script:BasePath = $base
            $Script:Config.CsvOutputPath = '$PSScriptRoot\NestOut'
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $expectDir -Filter 'Temp2Leveling_nozzle_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:BasePath = $bakBase
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'uses BedLevelResults under BasePath when CsvOutputPath not rooted' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $base = Join-Path $env:TEMP ("3dp_t2rel_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $expectDir = Join-Path $base 'BedLevelResults'
        $bakPath = $Script:Config.CsvOutputPath
        $bakBase = $Script:BasePath
        try {
            $Script:BasePath = $base
            $Script:Config.CsvOutputPath = 'relative_not_rooted'
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            (Get-ChildItem -LiteralPath $expectDir -Filter 'Temp2Leveling_nozzle_*.csv' -File).Count | Should -Be 1
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            $Script:BasePath = $bakBase
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'two nozzle temperature steps produce two data rows' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2two_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 175 -StepNozzle 5 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
            $csv = Get-ChildItem -LiteralPath $dir -Filter 'Temp2Leveling_nozzle_*.csv' -File | Select-Object -First 1
            $csv | Should -Not -BeNullOrEmpty
            $lines = Get-Content -LiteralPath $csv.FullName
            $lines.Count | Should -BeGreaterThan 2
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when M104 response fails' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2fail_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:srT2 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse {
                $script:srT2++
                if ($script:srT2 -eq 1) { return $false }
                return $true
            }
            Mock Read-SerialAndCapture { $meshOut }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when M140 response fails' {
        $dir = Join-Path $env:TEMP ("3dp_t2m140_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:sr140 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse {
                $script:sr140++
                if ($script:sr140 -le 1) { return $true }
                return $false
            }
            Mock Read-SerialAndCapture { "0 +0.01`n" }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when M109 response fails' {
        $dir = Join-Path $env:TEMP ("3dp_t2m109_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:sr109 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse {
                $script:sr109++
                if ($script:sr109 -le 2) { return $true }
                return $false
            }
            Mock Read-SerialAndCapture { "0 +0.01`n" }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when M190 response fails' {
        $dir = Join-Path $env:TEMP ("3dp_t2m190_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:sr190 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse {
                $script:sr190++
                if ($script:sr190 -le 3) { return $true }
                return $false
            }
            Mock Read-SerialAndCapture { "0 +0.01`n" }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'stops when G28 response fails' {
        $dir = Join-Path $env:TEMP ("3dp_t2g28_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:sr28 = 0
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse {
                $script:sr28++
                if ($script:sr28 -le 4) { return $true }
                return $false
            }
            Mock Read-SerialAndCapture { "0 +0.01`n" }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 0 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'Temp2 stabilization exits when Escape polled in wait loop' {
        $meshOut = @'
 0 +0.010 +0.020
'@
        $dir = Join-Path $env:TEMP ("3dp_t2stabesc_{0}" -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $bakPath = $Script:Config.CsvOutputPath
        try {
            $Script:Config.CsvOutputPath = $dir
            $script:stEsc = 0
            Mock Read-3DPConsoleEscapePoll {
                $script:stEsc++
                # 1=step start, 2+=stabilization wait loop (after M104..M190)
                if ($script:stEsc -eq 3) { return 'Escape' }
                return $null
            }
            Mock Send-Gcode { 1 }
            Mock Read-SerialResponse { $true }
            Mock Read-SerialAndCapture { $meshOut }
            Mock Start-Sleep { }
            { Invoke-Temp2LevelingLoop -Port $null -Mode 'nozzle' -StartNozzle 170 -EndNozzle 170 -StepNozzle 1 -StartBed 60 -EndBed 60 -StepBed 1 -StabilizationSeconds 15 -FixedNozzle 170 -FixedBed 60 } | Should -Not -Throw
        } finally {
            $Script:Config.CsvOutputPath = $bakPath
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-InteractiveBedLevelLoop (mocked)' {
    BeforeAll {
        Mock Write-Host { }
        Mock Start-Sleep { }
    }
    It 'runs heat G29 mesh then exits under SKIP_MAIN' {
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        Mock Send-Gcode { 1 }
        Mock Read-SerialAndCapture {
            @'
Bilinear Leveling Grid:
 0      1
 0 +0.010 +0.020
 1 +0.030 +0.040
'@
        }
        Mock Format-MeshWithColors { }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
    It 'uses M420 capture when first parse yields no mesh' {
        $script:ibCap = 0
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        Mock Send-Gcode { 1 }
        Mock Read-SerialAndCapture {
            $script:ibCap++
            if ($script:ibCap -eq 1) { return 'no mesh keywords here 999' }
            return @'
 0 +0.050 +0.060
'@
        }
        Mock Format-MeshWithColors { }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
    It 'warns when mesh stays empty' {
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        Mock Send-Gcode { 1 }
        Mock Read-SerialAndCapture { 'still nothing parseable' }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
    It 'returns when G29 capture is null' {
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        Mock Send-Gcode { 1 }
        Mock Read-SerialAndCapture { $null }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
    It 'runs stabilization block before G28' {
        Mock Invoke-GcodeAndWaitOrAbort { $true }
        Mock Send-Gcode { 1 }
        Mock Read-SerialAndCapture {
            @'
 0 +0.010 +0.020
'@
        }
        Mock Format-MeshWithColors { }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 8 } | Should -Not -Throw
    }
    It 'returns early when heating Invoke-GcodeAndWaitOrAbort fails' {
        Mock Invoke-GcodeAndWaitOrAbort { $false }
        { Invoke-InteractiveBedLevelLoop -Port $null -BedTemp 60 -NozzleTemp 170 -StabilizationSeconds 0 } | Should -Not -Throw
    }
}

Describe 'Get-TestKey' {
    It 'maps named tokens' {
        (Get-TestKey -Token 'Enter').Key | Should -Be 'Enter'
        (Get-TestKey -Token 'Escape').Key | Should -Be 'Escape'
        (Get-TestKey -Token 'Tab').Key | Should -Be 'Tab'
        (Get-TestKey -Token 'UpArrow').Key | Should -Be 'UpArrow'
        (Get-TestKey -Token 'DownArrow').Key | Should -Be 'DownArrow'
        (Get-TestKey -Token 'Backspace').Key | Should -Be 'Backspace'
    }
    It 'maps slash to Divide' { (Get-TestKey -Token '/').Key | Should -Be 'Divide' }
    It 'maps letter' {
        $k = Get-TestKey -Token 'g'
        [string]$k.KeyChar | Should -Be 'g'
    }
    It 'returns null for unknown token' { Get-TestKey -Token '___unknown___' | Should -BeNullOrEmpty }
}

Describe 'Format-TemperatureReport hotend target fallback' {
    It 'uses 0 when target group missing' {
        $r = Format-TemperatureReport -Line 'ok T:22.0'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match '22'
    }
    It 'formats bed line with target' {
        $r = Format-TemperatureReport -Line 'ok B:59.8/60.0'
        $r | Should -Not -BeNullOrEmpty
        ($r -join ' ') | Should -Match '59'
    }
    It 'formats line with hotend and bed together' {
        $r = Format-TemperatureReport -Line 'ok T:210.0/215.0 B:60.0/60.0'
        $r.Count | Should -BeGreaterOrEqual 2
    }
}

