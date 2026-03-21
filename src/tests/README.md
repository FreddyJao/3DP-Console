# Optional tests (Pester)

Unit- und Mock-Tests für Teile von **`src/`** (ohne vollständige serielle Integration). Befehle unten immer vom **Repository-Root** ausführen.

## Siehe auch

| Thema | Link |
|--------|------|
| Projekt (EN) | [README.md](../../README.md) |
| Projekt (DE) | [doku/README.de.md](../../doku/README.de.md) |
| Bett-Leveling Schnellstart | [doku/guide.md](../../doku/guide.md) |
| Checkliste „was teste ich wo?“ (DE) | [TEST-COVERAGE.de.md](TEST-COVERAGE.de.md) |

## Pester 5+ installieren (einmalig, Windows PowerShell)

Falls `Run-Pester.ps1` meldet, dass Pester fehlt:

```powershell
# Empfohlen — install-pester.ps1 (lädt Pester 5.x als .nupkg von der Gallery ODER nutzt eine lokale .nupkg):
powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1" -NupkgPath "C:\Users\XYZ\Downloads\pester.5.6.1.nupkg"

# Optional — klassisch über PowerShellGet (kann auf manchen PCs sehr lange haengen):
powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1" -UseInstallModule

# Alternativ — eine Zeile:
Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber

# Oder — Test-Runner mit -InstallPester (nutzt ebenfalls Install-Module):
.\src\tests\Run-Pester.ps1 -InstallPester
```

Danach prüfen: `Get-Module -ListAvailable Pester` (Version **5.x** sollte erscheinen; alte **3.x** aus `Program Files` kann parallel existieren — `Run-Pester.ps1` importiert explizit Pester 5+).

| Datei | Zweck |
|--------|--------|
| `Run-Pester.ps1` | Startet Pester 5, optional **CodeCoverage** auf ausgewählte Dateien (**ohne** `Main`/`PaletteUI`/`Init`/`Serial` — Details im Kopfkommentar von `Run-Pester.ps1`) |
| `Show-PesterCoverageGaps.ps1` | Gleicher Coverage-Lauf wie `Run-Pester.ps1`, danach **Tabelle „wo fehlen die meisten Treffer?“** (pro Datei) + **Top N** verpasste Zeilen — sinnvoll, um **gezielt** Tests nachzurüsten (statt blind 100 % anzustreben). Optional `-ExportCsv` für die volle Miss-Liste. |
| `3DP-Console.Pester.Tests.ps1` | **Mocks** + reine Funktionen; inkl. Interactive-Bed-Level, LevelCompare/Temp2, COM-WMI-Fallback, `Invoke-MainCommandLineMode`, `Invoke-Monitor`/`Invoke-SdLs` (Mock-Port), G-Code-Helfer (`Get-3DPConsoleHomeAxesGcode`, Move/Extrude/Monitor-Intervall); **CodeCoverage** auf **6** gemessene Dateien; `Run-Pester.ps1` bricht mit Exitcode **1** ab, wenn die Quote **unter 90 %** liegt |

**Test-Hook (nur Pester / gleicher Prozess):** `$global:3DPConsoleMainCommandRunSingleCommandScript` — optionaler `scriptblock` `{ param($p,$cmd) … }` ersetzt den Standard-Runner im `-Command`-Pfad (`Invoke-MainCommandLineMode`). Produktiv läuft `Invoke-MainCommandLineModeDefaultRunSingle` → `Invoke-SingleCommand`; Pester-Mocks auf diese Aufrufe greifen in der Praxis **nicht**, sobald sie aus per `&` ausgeführtem `RunCommandScript` kommen — daher der Hook für den Erfolgstest. `Invoke-MainCommandLineModeDefaultRunSingle` direkt aufrufen (siehe Pester) deckt die Funktion trotzdem ab.

**Haupttests:** `src\tests\Test-All.ps1` und `src\tests\Run-Integration-Tests.ps1` (vom **Repository-Root** aus: `.\src\tests\...`). Kein Modul nötig.

```powershell
# Pester einmalig (CurrentUser):
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -SkipPublisherCheck

.\src\tests\Run-Pester.ps1              # mit CodeCoverage
.\src\tests\Run-Pester.ps1 -NoCodeCoverage
.\src\tests\Run-Pester.ps1 -InstallPester

# Coverage-Lücken als Tabelle + Top-Zeilen (empfohlen vor gezieltem Ausbau der Tests):
.\src\tests\Show-PesterCoverageGaps.ps1
.\src\tests\Show-PesterCoverageGaps.ps1 -TopMissedLines 40 -ExportCsv "$env:TEMP\pester-missed.csv"
```

## Pester lädt nicht („Pester.dll“ / „Handle ungültig“)

- **`Pester.dll` nicht gefunden** unter `...\Modules\Pester\...\bin\...` → Installation **unvollständig** (oft abgebrochenes Update). **Reparatur** (vom Repo-Root):

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File ".\src\tests\install-pester.ps1"
  ```

  Das Skript erkennt fehlende DLLs und entfernt kaputte Ordner, dann installiert es Pester 5.x per `.nupkg`-Download. Alternativ manuell den Ordner `Documents\WindowsPowerShell\Modules\Pester\5.7.1` (bzw. die betroffene Version) **löschen** und `Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck` erneut ausführen.

- **`CursorPosition` / ungültiges Handle** in Tests → in aktuellen `PaletteUI`-Versionen abgefangen; bei Bedarf PowerShell **nicht** über eingeschränkte Hosts starten.

## Was Pester hier *nicht* abdeckt (Absicht)

- `Read-SerialAndCapture` / `Send-Gcode` mit echten Zeilen am offenen Port → **Integration** (`.\src\tests\Test-All.ps1 -WithPort`) oder Refactor mit injizierbarem Port.
- **CodeCoverage** zählt bewusst nicht: `Main`, `PaletteUI`, **`Init`** (Bootstrap/NuGet), **`Serial`** (Port-Leseschleifen). Verhalten dort: **Integration** (`Test-All.ps1 -WithPort`) bzw. manuell. Mindestziel der Command-Coverage auf den gemessenen Dateien: **90 %** (`Run-Pester.ps1`).
