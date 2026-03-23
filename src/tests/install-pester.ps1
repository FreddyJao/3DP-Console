# Install Pester 5+ (CurrentUser scope).
#
# From repository root:
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1"
#
# With a downloaded .nupkg (e.g. from browser):
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1" -NupkgPath "C:\Users\XYZ\Downloads\pester.5.6.1.nupkg"
#
# Optional: -UseInstallModule — use Install-Module instead of .nupkg (can take a long time).

param(
    [string]$NupkgPath,
    [switch]$UseInstallModule
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-PesterModuleUsable {
    param($ModuleInfo)
    if (-not $ModuleInfo -or -not $ModuleInfo.ModuleBase) { return $false }
    $bin = Join-Path $ModuleInfo.ModuleBase 'bin'
    if (-not (Test-Path -LiteralPath $bin)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $bin -Filter 'Pester.dll' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# Broken installs (manifest present, Pester.dll missing) cause import errors — remove that folder.
Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | ForEach-Object {
    if (-not (Test-PesterModuleUsable $_)) {
        Write-Warning "Unvollstaendiges Pester $($_.Version) entfernen: $($_.ModuleBase)"
        Remove-Item -LiteralPath $_.ModuleBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$have5 = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
if ($have5 -and (Test-PesterModuleUsable $have5) -and -not $NupkgPath) {
    Write-Host "Pester $($have5.Version) ist bereits installiert: $($have5.ModuleBase)" -ForegroundColor Green
    Get-Module -ListAvailable -Name Pester | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 5 Name, Version | Format-Table -AutoSize
    exit 0
}

if ($UseInstallModule) {
    Write-Host 'Versuche Install-Module (PowerShellGet)...' -ForegroundColor Cyan
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Scope CurrentUser `
            -Force -SkipPublisherCheck -AllowClobber
        Write-Host 'Install-Module: OK' -ForegroundColor Green
    } catch {
        Write-Host "Install-Module fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    $version = '5.6.1'
    if ($NupkgPath) {
        $nupkg = (Resolve-Path -LiteralPath $NupkgPath).Path
        if (-not (Test-Path -LiteralPath $nupkg)) { throw "Datei nicht gefunden: $nupkg" }
        $leaf = Split-Path -Leaf $nupkg
        if ($leaf -match '(?i)pester\.(\d+\.\d+\.\d+)\.nupkg$') {
            $version = $Matches[1]
        } else {
            Write-Warning "Konnte Version nicht aus '$leaf' lesen - verwende $version als Zielordner."
        }
        Write-Host "Verwende lokale Datei: $nupkg (Version $version)" -ForegroundColor Cyan
    } else {
        $url = "https://www.powershellgallery.com/api/v2/package/Pester/$version"
        $nupkg = Join-Path $env:TEMP "Pester.$version.nupkg"
        Write-Host "Lade Pester $version von PowerShell Gallery …" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $nupkg -TimeoutSec 180 -UseBasicParsing
    }

    $zip = Join-Path $env:TEMP "Pester.$version.install.zip"
    $extract = Join-Path $env:TEMP "pester_extract_$version"
    Copy-Item -LiteralPath $nupkg -Destination $zip -Force
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $extract -Force

    if (-not (Test-Path (Join-Path $extract 'Pester.psd1'))) {
        throw "Nach dem Entpacken wurde Pester.psd1 nicht gefunden - ist die .nupkg korrupt oder kein Pester-Paket?"
    }

    $bases = @(
        (Join-Path $HOME 'Documents\WindowsPowerShell\Modules'),
        (Join-Path $HOME 'Documents\PowerShell\Modules')
    )
    foreach ($base in $bases) {
        $dest = Join-Path (Join-Path $base 'Pester') $version
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Get-ChildItem -Path $extract -File | Where-Object {
            $_.Name -notmatch '^\[Content' -and $_.Name -ne 'Pester.nuspec'
        } | Copy-Item -Destination $dest -Force
        foreach ($d in @('bin', 'en-US', 'schemas')) {
            $p = Join-Path $extract $d
            if (Test-Path $p) { Copy-Item -Path $p -Destination $dest -Recurse -Force }
        }
        Write-Host "Kopiert nach: $dest" -ForegroundColor Green
    }
}

Get-Module -ListAvailable -Name Pester | Sort-Object { [version]$_.Version } -Descending |
    Select-Object -First 6 Name, Version, ModuleBase | Format-Table -AutoSize

$check = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
if (-not $check -or -not (Test-PesterModuleUsable $check)) {
    Write-Host 'FEHLER: Pester 5+ wurde nicht gefunden oder ist unvollstaendig (fehlt bin\...\Pester.dll).' -ForegroundColor Red
    exit 1
}
Write-Host "OK: Pester $($check.Version) nutzbar." -ForegroundColor Green
