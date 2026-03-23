<#
.SYNOPSIS
    Run Pester with code coverage and show the largest gaps (files + lines).

.DESCRIPTION
    Uses the same coverage paths as Run-Pester.ps1 (excluding Main/PaletteUI/Init/Serial).
    Useful to plan new tests — not blindly chasing 100%.

.PARAMETER TopMissedLines
    Number of detailed "missed" commands (file:line) shown at the end.

.PARAMETER ExportCsv
    Optional: full list of missed commands as CSV (UTF-8).

.PARAMETER NoCodeCoverage
    Tests only without measurement (fast — no gap list).

.EXAMPLE
    .\src\tests\Show-PesterCoverageGaps.ps1
.EXAMPLE
    .\src\tests\Show-PesterCoverageGaps.ps1 -TopMissedLines 40 -ExportCsv "$env:TEMP\pester-missed.csv"
#>

param(
    [int]$TopMissedLines = 25,
    [string]$ExportCsv,
    [switch]$NoCodeCoverage
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here

$pesterMod = Get-Module -ListAvailable -Name Pester | Sort-Object { $_.Version } -Descending | Select-Object -First 1
if (-not $pesterMod -or $pesterMod.Version -lt [version]'5.0.0') {
    Write-Host 'Pester 5+ fehlt. Z. B.: .\src\tests\install-pester.ps1' -ForegroundColor Red
    exit 1
}
Import-Module Pester -MinimumVersion 5.0.0

$testFile = Join-Path $here '3DP-Console.Pester.Tests.ps1'
if (-not (Test-Path -LiteralPath $testFile)) {
    Write-Host "Fehlt: $testFile" -ForegroundColor Red
    exit 1
}

$cov = @(
    (Join-Path $root '3DP-Console.ps1')
) + @(Get-ChildItem -Path (Join-Path $root 'lib') -Filter '*.ps1' -File | ForEach-Object { $_.FullName } | Where-Object {
        $_ -notmatch '3DP-Console\.Main\.ps1$' -and $_ -notmatch '3DP-Console\.PaletteUI\.ps1$' -and
        $_ -notmatch '3DP-Console\.Init\.ps1$' -and $_ -notmatch '3DP-Console\.Serial\.ps1$'
    })

if ($NoCodeCoverage) {
    $configuration = [PesterConfiguration]@{
        Run = @{ Path = @($testFile); PassThru = $true }
    }
} else {
    $configuration = [PesterConfiguration]@{
        Run          = @{ Path = @($testFile); PassThru = $true }
        CodeCoverage = @{ Enabled = $true; Path = $cov }
    }
}

$result = Invoke-Pester -Configuration $configuration

$failed = if ($null -ne $result.FailedCount) { $result.FailedCount } else { $result.Failed }
if ($failed -gt 0) {
    Write-Host ('Pester: ' + $failed + ' Test(s) fehlgeschlagen - Coverage kann unvollstaendig sein.') -ForegroundColor Yellow
}

if ($NoCodeCoverage -or -not $result.CodeCoverage) {
    exit $(if ($failed -gt 0) { 1 } else { 0 })
}

$cc = $result.CodeCoverage
$pct = [math]::Round([double]$cc.CoveragePercent, 2)
Write-Host ''
Write-Host '=== Pester CodeCoverage: Luecken-Uebersicht ===' -ForegroundColor Cyan
Write-Host "Gesamt: $pct%  |  analysiert: $($cc.CommandsAnalyzedCount) Befehle in $($cc.FilesAnalyzedCount) Dateien" -ForegroundColor White
Write-Host ''

$missByFile = foreach ($g in ($cc.CommandsMissed | Group-Object -Property File)) {
    $leaf = [System.IO.Path]::GetFileName($g.Name)
    [pscustomobject]@{ Datei = $leaf; Verpasst = $g.Count }
}
$hitByFile = foreach ($g in ($cc.CommandsExecuted | Group-Object -Property File)) {
    $leaf = [System.IO.Path]::GetFileName($g.Name)
    [pscustomobject]@{ Datei = $leaf; Ausgefuehrt = $g.Count }
}

$allLeaves = @(@($missByFile).Datei) + @(@($hitByFile).Datei) | Select-Object -Unique
$rows = foreach ($leaf in $allLeaves) {
    $m = ($missByFile | Where-Object { $_.Datei -eq $leaf }).Verpasst
    if (-not $m) { $m = 0 }
    $h = ($hitByFile | Where-Object { $_.Datei -eq $leaf }).Ausgefuehrt
    if (-not $h) { $h = 0 }
    $sum = $m + $h
    $filePct = if ($sum -gt 0) { [math]::Round(100.0 * $h / $sum, 1) } else { 0 }
    [pscustomobject]@{
        Datei              = $leaf
        'Verpasst (n)'     = $m
        'Ausgefuehrt (n)'  = $h
        'Schaetzung %'     = $filePct
    }
}
$rows | Sort-Object { $_['Verpasst (n)'] } -Descending | Format-Table -AutoSize

Write-Host 'Hinweis: Ausgefuehrt = Treffer-Eintraege (kann dieselbe Zeile mehrfach zaehlen). Schaetzung % = grobe Orientierung.' -ForegroundColor DarkGray
Write-Host ''
Write-Host ('Top ' + $TopMissedLines + ' verpasste Befehle (neue Tests am meisten lohnen sich hier):') -ForegroundColor Cyan

$detail = @(
    foreach ($cmd in $cc.CommandsMissed) {
        [pscustomobject]@{
            Datei   = [System.IO.Path]::GetFileName($cmd.File)
            Zeile   = $cmd.Line
            Befehl  = if ($cmd.Command) { ($cmd.Command -replace '\s+', ' ').Trim() } else { '' }
        }
    }
) | Sort-Object Datei, Zeile | Select-Object -First $TopMissedLines

$detail | Format-Table -AutoSize -Wrap

if ($ExportCsv) {
    @(
        foreach ($cmd in $cc.CommandsMissed) {
            [pscustomobject]@{
                File    = $cmd.File
                Line    = $cmd.Line
                Command = $cmd.Command
            }
        }
    ) | Export-Csv -LiteralPath $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host ('CSV exportiert: ' + $ExportCsv) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Nicht gemessen (Absicht): Main, PaletteUI, Init, Serial - siehe Run-Pester.ps1 / README.md' -ForegroundColor DarkGray
# -WithPort inside double quotes would be parsed as a Write-Host parameter
Write-Host ('Integration am Drucker: src\tests\Test-All.ps1 -WithPort') -ForegroundColor DarkGray

exit $(if ($failed -gt 0) { 1 } else { 0 })
