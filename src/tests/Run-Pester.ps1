<#
.SYNOPSIS
    Optional: Pester 5 + CodeCoverage auf lib\ und 3DP-Console.ps1.

.DESCRIPTION
    Ergaenzt Test-All.ps1 (Pester ist nicht Pflicht).
    CodeCoverage-Mindestziel auf den gemessenen Dateien: 90% (siehe Code am Ende des Skripts).
    Install:  Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -SkipPublisherCheck

.PARAMETER InstallPester
    Versucht Pester per Install-Module zu installieren (CurrentUser).

.PARAMETER NoCodeCoverage
    Schneller Lauf ohne CodeCoverage.

.EXAMPLE
    .\src\tests\Run-Pester.ps1
.EXAMPLE
    .\src\tests\Run-Pester.ps1 -NoCodeCoverage
.EXAMPLE
    .\src\tests\Run-Pester.ps1 -InstallPester
#>

param(
    [switch]$InstallPester,
    [switch]$NoCodeCoverage
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here

$pesterMod = Get-Module -ListAvailable -Name Pester | Sort-Object { $_.Version } -Descending | Select-Object -First 1
if (-not $pesterMod -or $pesterMod.Version -lt [version]'5.0.0') {
    if ($InstallPester) {
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        $pesterMod = Get-Module -ListAvailable -Name Pester | Sort-Object { $_.Version } -Descending | Select-Object -First 1
    }
    if (-not $pesterMod -or $pesterMod.Version -lt [version]'5.0.0') {
        Write-Host 'Pester 5+ nicht gefunden. Optional:' -ForegroundColor Yellow
        Write-Host '  Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -SkipPublisherCheck' -ForegroundColor Gray
        Write-Host '  .\src\tests\Run-Pester.ps1 -InstallPester' -ForegroundColor Gray
        exit 1
    }
}

Import-Module Pester -MinimumVersion 5.0.0

$testFile = Join-Path $here '3DP-Console.Pester.Tests.ps1'
if (-not (Test-Path -LiteralPath $testFile)) {
    Write-Host "Fehlt: $testFile" -ForegroundColor Red
    exit 1
}

if ($NoCodeCoverage) {
    $configuration = [PesterConfiguration]@{
        Run = @{
            Path     = @($testFile)
            PassThru = $true
        }
    }
    $result = Invoke-Pester -Configuration $configuration
} else {
    # Ausgeschlossen von der Messung (weiterhin zur Laufzeit geladen):
    # - Main / PaletteUI: interaktive UI
    # - Init: NuGet/Assembly-Bootstrap, env-abhaengig
    # - Serial: Read-Serial* / echte Port-Schleifen (ohne Hardware kaum sinnvoll; Integration: Test-All -WithPort)
    $cov = @(
        (Join-Path $root '3DP-Console.ps1')
    ) + @(Get-ChildItem -Path (Join-Path $root 'lib') -Filter '*.ps1' -File | ForEach-Object { $_.FullName } | Where-Object {
            $_ -notmatch '3DP-Console\.Main\.ps1$' -and $_ -notmatch '3DP-Console\.PaletteUI\.ps1$' -and
            $_ -notmatch '3DP-Console\.Init\.ps1$' -and $_ -notmatch '3DP-Console\.Serial\.ps1$'
        })
    $configuration = [PesterConfiguration]@{
        Run          = @{
            Path     = @($testFile)
            PassThru = $true
        }
        CodeCoverage = @{
            Enabled = $true
            Path    = $cov
        }
    }
    $result = Invoke-Pester -Configuration $configuration
}

$failed = if ($null -ne $result.FailedCount) { $result.FailedCount } else { $result.Failed }
if ($failed -gt 0) {
    Write-Host "Pester: Failed=$failed" -ForegroundColor Red
    exit 1
}

$passed = if ($null -ne $result.PassedCount) { $result.PassedCount } else { $result.Passed }
Write-Host "Pester: Passed=$passed" -ForegroundColor Green

if (-not $NoCodeCoverage -and $result.CodeCoverage) {
    $cc = $result.CodeCoverage
    # Pester 5+: CoveragePercent / CoveragePercentTarget (kein NumberOfCommandsAnalyzed mehr)
    if ($null -ne $cc.CoveragePercent) {
        $pct = [math]::Round([double]$cc.CoveragePercent, 1)
        $minPct = 90
        Write-Host "CodeCoverage: $pct% (Mindestziel: ${minPct}%)" -ForegroundColor Cyan
        if ($pct -lt $minPct) {
            Write-Host "CodeCoverage liegt unter dem Mindestziel ${minPct}%." -ForegroundColor Red
            exit 1
        }
    }
}

exit 0
