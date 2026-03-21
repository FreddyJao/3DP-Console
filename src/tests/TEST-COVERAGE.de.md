# Test-Abdeckung (Checkliste, keine Prozent-Coverage)

**Standort:** Diese Datei liegt unter **`src\tests\TEST-COVERAGE.de.md`**. Pfade mit `.\src\…` beziehen sich auf den **Repository-Root**; **`$ProjectRoot`** im Skript ist der Ordner **`src\`** (mit `3DP-Console.ps1`, `3DP-Config.ps1`, `lib\`).

**Tests starten** (vom Repository-Root):

```powershell
.\src\tests\Test-All.ps1
.\src\tests\Run-Integration-Tests.ps1
```

`src\tests\Test-All.ps1` setzt **`$ProjectRoot`** = **`src\`** (ein Ordner über `src\tests\`) und lädt `3DP-Console.ps1` von dort — funktioniert auch, wenn das aktuelle Verzeichnis `src\tests\` ist.

---

Diese Datei ordnet **Funktionen in `src\lib\*.ps1`** den Läufen von **`src\tests\Test-All.ps1`** zu. Es geht **nicht** um Zeilen- oder Branch-Coverage (dafür bräuchte man z. B. Pester `CodeCoverage`), sondern um eine **manuelle Checkliste**: *Wird diese Funktion in einem Test überhaupt ausgeführt – und wie?*

---

## Legende (verbesserte Stufen)

Die alte Kurzform **„○ = nur indirekt / teilweise“** und **„— = nicht sinnvoll getestet“** ist zu unpräzise. Hier die **fünf klaren Stufen** plus **Unterarten** bei „kein Auto-Test“.

### 1. Direkt

Der Test ruft die Funktion **namentlich** auf **oder** das Szenario hat diese Funktion als **klares Hauptziel** (z. B. `Get-GcodeTimeout` in Unit, `Send-Gcode` in Integration).

### 2. Indirekt

Die Funktion wird **nicht** im Test genannt, läuft aber **zwangsläufig** als **Unteraufruf** einer anderen getesteten Funktion.  
*Beispiel:* `Write-ListLines` wird nur von `Render-Palette` aufgerufen, getestet wird `Invoke-CommandPalette`.

### 3. Teilweise

Die Funktion wird (direkt oder indirekt) ausgeführt, aber **nicht in der vollen Breite**: andere **Eingaben**, **Zweige** oder **Umgebungen** fehlen im Test.  
*Beispiele:* `Test-PortConnected` mit `$null`-Port statt echtem offenen Port; `Invoke-CommandPalette` nur mit Test-Key-Queue statt echter Tastatur; `Merge-HashtableIntoConfig` ohne isolierten Test nur für diese Funktion.

### 4. Bedingt

Die Funktion wird **nur** ausgeführt, wenn du **bestimmte Parameter** setzt (meist **Integration + Zusatzschalter**). Ohne diese Flags: gleiche Stufe wie bei **Kein Auto-Test · fehlendes Szenario** für genau diesen Pfad.  
Siehe Tabelle **Copy-Paste** unten.

### 5. Kein Auto-Test

In **`src\tests\Test-All.ps1`** gibt es **keinen** gezielten Nachweis für diese Funktion (oder den relevanten Pfad). Unterarten:

| Unterart | Bedeutung |
|----------|-----------|
| **Laufzeit** | Code läuft beim **Laden** des Skripts (Dot-Source), aber es gibt **keinen Assert** dazu. |
| **Manuell** | Sinnvoller Nachweis nur durch **interaktive Nutzung** (Konsole, Menüs, spezielle Loops). |
| **Absicht ausgelassen** | Testumgebung **deaktiviert** den Einstieg (z. B. `THREEDP_CONSOLE_SKIP_MAIN` → `Main` wird nicht gestartet). |
| **Szenario fehlt** | Automatisierung **wäre möglich**, ist aber **nicht** eingebaut (z. B. kein `Test-All`-Block für `Read-SerialAndCapture` ohne die bedingten Integrationsschalter). |

**Hinweis:** „Kein Auto-Test“ ist **kein Qualitätsurteil** – oft ist manuelles oder hardwarenahes Testen angemessener.

---

## Copy-Paste: Integration mit Zusatz (länger / speziell)

COM-Port anpassen (`COM5` ist Standard in `src\tests\Test-All.ps1`).

**`src\tests\Run-Integration-Tests.ps1`** macht vorher eine **COM-Freigabe-Prüfung** und ruft **`src\tests\Test-All.ps1`** mit denselben Schaltern auf. Beispiel:  
`.\src\tests\Run-Integration-Tests.ps1 -TestLevelCompare` ≡ `.\src\tests\Test-All.ps1 -WithPort -TestLevelCompare` (nach Port-Check).

- **`-DryRun`** / **`-DryRun -SkipPortCheck`**: keine Testausführung, nur geplante Parameter (siehe Hilfe in `src\tests\Run-Integration-Tests.ps1`).
- **`src\tests\Test-All.ps1 -IntegrationPlanOnly`**: alle **Unit-Tests** inkl. **[6j]** und **[6k]**, dann **Integrations-Plan** wie bei [7], aber **ohne** serielles Öffnen (kein Hardware-[7]).

| Abgedeckte Pfade (Kurz) | `src\tests\Test-All.ps1` | `src\tests\Run-Integration-Tests.ps1` (nach Port-Check) |
|-------------------------|----------------------|--------------------------------------------------------|
| **`Invoke-LevelCompareLoop`** und damit **`Read-SerialAndCapture`** (2× G29, CSV, lang) | `.\src\tests\Test-All.ps1 -WithPort -ComPort COM5 -TestLevelCompare` | `.\src\tests\Run-Integration-Tests.ps1 -ComPort COM5 -TestLevelCompare` |
| **`Invoke-Temp2LevelingLoop`** (über `Invoke-Loop` + Minimal-Config) und damit **`Read-SerialAndCapture`** | `.\src\tests\Test-All.ps1 -WithPort -ComPort COM5 -TestTemp2` | `.\src\tests\Run-Integration-Tests.ps1 -ComPort COM5 -TestTemp2` |
| **`Invoke-Loop`** inkl. **`prepare`**, **`level_rehome_once`**, **`temp_ramp`**, **`/level`** (G29), **G29 T** | `.\src\tests\Test-All.ps1 -WithPort -ComPort COM5 -SkipLong:$false` | `.\src\tests\Run-Integration-Tests.ps1 -ComPort COM5 -SkipLong:$false` |
| **`Send-Gcode`** mit **M112** wirklich zum Drucker (**Not-Aus** – Vorsicht!) | `.\src\tests\Test-All.ps1 -WithPort -ComPort COM5 -TestM112` | `.\src\tests\Run-Integration-Tests.ps1 -ComPort COM5 -TestM112` |

**Hinweis:** Standard ist `-SkipLong:$true`. Ohne `-SkipLong:$false` laufen die langen G29-/Loop-Blöcke in Abschnitt **[7]** nicht. **`src\tests\Run-Integration-Tests.ps1`** startet standardmäßig **ohne** `-TestLevelCompare` (wie `src\tests\Test-All.ps1 -WithPort`); lange Level-Compare-Integration ist **opt-in** mit `-TestLevelCompare`.

---

## Unit-Abschnitte in `src\tests\Test-All.ps1`

| Abschnitt | Inhalt (Kurz) |
|-----------|----------------|
| **[0]–[6i]** | siehe **Referenztabelle unten** (jede `Write-Host`-Überschrift 1:1) |
| **[6j]** | `Merge-HashtableIntoConfig`, `Get-AvailableComPorts`, `Test-PortConnected` (`$null`), `Update-ConfigComPort` (Temp-Datei). |
| **[6k]** | Weitere **Merge-Randfälle** (`$null`-Werte, leeres `KeysOnly @()` → volle Liste), `Update-ConfigComPort` (fehlende Datei). |

Vor **Integration [7]** (bzw. nur bei **`-IntegrationPlanOnly`**) gibt `src\tests\Test-All.ps1` einen kurzen **Integrations-Plan** aus (gleiche Schalter wie `-WithPort`).

### Referenz: Unit-Überschriften = `Write-Host` in `Test-All.ps1`

Die folgende Tabelle entspricht der **tatsächlichen Reihenfolge** der Blöcke (Zeilen ~151–698). So kannst du Doku und Skript **Zeile für Zeile** vergleichen.

| Abschnitt | Exakte Überschrift im Skript | Was geprüft wird (Stichworte) |
|-----------|------------------------------|--------------------------------|
| **[0]** | `=== [0] Script Parameters (3DP-Console.ps1) ===` | Subprozess: `3DP-Console.ps1 -Help -ComPort`, `-About -ConfigPath`, `-Example` (kein `Main`, weil auch dort typischerweise Skip/Main nicht greift wie in interaktivem Modus — hier nur CLI-Ausgabe). |
| **[1]** | `=== [1] Load Config ===` | `$Script:Config` / `$Script:DueseLabel` / `$Script:MaxVisibleItems`; **`Get-GcodeTimeout`** für G28, M109, M105. |
| **[1b]** | `=== [1b] Get-UIString (placeholders) ===` | **`Get-UIString`** (ComPort, NozzleTemp, unbekannter Key, DueseLabel). |
| **[2]** | `=== [2] Get-SlashCommandArgs ===` | **`Get-SlashCommandArgs`** (`/home xy`, `/move X 10`, `/macro preheat 200`). |
| **[3]** | `=== [3] Get-PaletteItems Slash with params ===` | **`Get-PaletteItems`** mit Slash-Puffer `/home xy`, `/move X 10`. |
| **[4]** | `=== [4] Macros + Loops (from Config) ===` | Macros aus Config bzw. `PrusaMini-Macros.ps1`; `pla` als Array. |
| **[5]** | `=== [5] Format-TemperatureReport ===` | **`Format-TemperatureReport`** an einer Beispiel-M105-Zeile. |
| **[6]** | `=== [6] SlashCommands present ===` | Vorhandensein der Slash-Befehle in `$Script:SlashCommands` (u. a. `/monitor`, `/ls`, `/sdprint`). |
| **[6b]** | `=== [6b] QuickActions present ===` | Keys **`d`, `dw`, `b`, `bw`, `off`, `fan`, `home`, `level`, `temp`** in `$Script:QuickActions`. |
| **[6c]** | `=== [6c] G/M-Palette ===` | **`Get-PaletteItems`** (g, g28, m, m104, leer, Whitespace, `loop`-Filter, **`temp2_*`**). |
| **[6c2]** | `=== [6c2] Tab completion (Palette) ===` | **`Invoke-CommandPalette`** im Testmodus (Tab → ausgewählter Befehl). |
| **[6d]** | `=== [6d] Parse-MeshFromG29Output ===` | **`Parse-MeshFromG29Output`** (G29- und M420-CSV-Format). |
| **[6d1]** | `=== [6d1] alleMeshes += ,$mesh ... ===` | Logik „Mesh als Ganzes anhängen“ (`alleMeshes`). |
| **[6d2]** | `=== [6d2] CSV write and comparison (mock data) ===` | **CSV/Vergleich/Stats** mit temporärem Verzeichnis (Mock — **nicht** `Invoke-LevelCompareLoop` am Drucker). |
| **[6e]** | `=== [6e] M112 confirmed (logic test) ===` | **`Invoke-Confirm`** = `true` → M112-Pfad „würde fortfahren“ (ohne `Send-Gcode`). |
| **[6f]** | `=== [6f] Interactive Bed Leveling ===` | **`Get-MeshCellColor`**, **`Get-DeltaImprovement`**, **`Format-MeshWithColors`**, Config/Palette für `interactive_bedlevel`, Schwellenwerte. |
| **[6g]** | `=== [6g] Config Loops + Palette (3DP-Config.ps1) ===` | **`Get-LoopPaletteItems`**, **`Get-PaletteItems`** (`loop prep`), erwartete **`Config.Loops`‑Keys** und **`LoopOrder`**. |
| **[6h]** | `=== [6h] UI text wrap (palette descLong) ===` | **`Split-UITextToLines`**, **`Get-DescLongLineCount`**. |
| **[6i]** | `=== [6i] Parse-MeshLineToNumbers ===` | **`Parse-MeshLineToNumbers`**. |
| **[6j]** | `=== [6j] Init/Port-Helfer ... ===` | **`Merge-HashtableIntoConfig`** (`$null`-Quelle, `KeysOnly`), **`Get-AvailableComPorts`**, **`Test-PortConnected`** (`$null`), **`Update-ConfigComPort`** (Temp-Datei). |
| **[6k]** | `=== [6k] Merge-Randfaelle + Update-Config ... ===` | **`Merge-HashtableIntoConfig`** (`$null`-Werte im Quell-Hashtable, leeres `KeysOnly @()`); **`Update-ConfigComPort`** (fehlende Datei → `false`). |

**Hinweis:** Am Anfang setzt `Test-All.ps1` **`$env:THREEDP_CONSOLE_SKIP_MAIN = '1'`** und dot-sourced **`3DP-Console.ps1`** — damit laufen alle obigen Tests **ohne** interaktives **`Main`**. (Veraltet, wird noch gemappt: `PRUSAMINI_SKIP_MAIN`.)

### Referenz: Integration **Abschnitt [7]**

Im Skript: ``Write-Host "`n=== [7] Integration $intComPort ==="`` (Platzhalter = gewählter COM-Port).

Voraussetzung: **`WithPort`** und **nicht** **`IntegrationPlanOnly`**, und SerialPort lässt sich öffnen.  
Zuerst: **`Write-IntegrationCoveragePlan`** (nur Text). Dann **Reihenfolge** der Integrationstests wie im Skript (Auszug mit **Test-Name**-Titeln):

1. **CLI:** `3DP-Console.ps1 -Command temp` → **`Invoke-SingleCommand`** / Port-Pfad.  
2. **`Invoke-SingleCommand`** `temp`, **`Invoke-SingleCommand`** `M105`.  
3. **M105, M114, M115** über **`Send-Gcode`** + **`Read-SerialResponse`**.  
4. **`Invoke-SdLs`** (`/ls`).  
5. **`Send-Gcode`** mit **`HostCommandCallback`** (`;@test` + M105).  
6. **`Invoke-Macro`** `preheat 0`.  
7. Wenn **nicht** `-SkipHeating`: **`/pla`, `/abs`, `/duese`, `/bett`, `/off`** (jeweils **`Send-Gcode`** + **`Read-SerialResponse`**).  
8. **`/fan`** (M107), **`/motoren`** (M17).  
9. **`Invoke-HomeAxes`** `""` (G28+E).  
10. **`Invoke-SdPrint`** (Testdatei `__test_ni.g`).  
11. Wenn **nicht** `-SkipLong`: **`/level`** (G29), QuickAction **level**, **G29 T**, **`Invoke-Loop`** `prepare`, `level_rehome_once` (1× und 2×), `temp_ramp` (2×).  
12. **`Invoke-HomeAxes`** `e`.  
13. Wenn **nicht** `-SkipHeating`: **`Invoke-Move`**, **`Invoke-Extrude`**, **`Invoke-Reverse`**, **`Invoke-HomeAxes`** `xy`.  
14. **„Invoke-Monitor (2 Zyklen)“** — im Skript **kein** Aufruf von **`Invoke-Monitor`**: es wird **`$port.WriteLine('M105')`** + **`ReadExisting`** + **`Format-TemperatureReport`** verwendet (Monitor-**ähnlich**, anderer Codepfad).  
15. **`Invoke-Loop`** `cooldown`.  
16. QuickActions **`d`, `b`, `off`, `fan`, `home`, `temp`** (nicht `dw`/`bw`/`level` in dieser Schleife).  
17. Palette **G28** und **M105** senden.  
18. **M112** mit gemocktem **`Invoke-Confirm`** = ablehnen → **`Send-Gcode`** sendet M112 **nicht**.  
19. Optional **`-TestLevelCompare`**: **`Invoke-LevelCompareLoop`** (2×), CSV-Prüfung.  
20. Optional **`-TestTemp2`**: minimal überschriebene Config, **`Invoke-Loop`** `temp2_nozzle`, CSV-Prüfung (im Skript-Kommentar ca. **8 Min** bei einem Schritt).  
21. **Quit-Logik:** M104/M140 S0.  
22. Optional **`-TestM112`**: **`Invoke-Confirm`** = zu → **`Send-Gcode`** M112 wirklich.

Bei **`-IntegrationPlanOnly`** (mit oder ohne **`-WithPort`**) erscheint nur die Überschrift **[7]** + **Integrations-Plan** + Hinweis, dass **kein** Port geöffnet wird — die Schritte 1–22 entfallen.

### Optional: Pester + CodeCoverage (`src\tests\`)

| Thema | Umsetzung |
|-------|-----------|
| **`Invoke-GcodeAndWaitOrAbort`** ohne echten `SerialPort` | `src\tests\3DP-Console.Pester.Tests.ps1`: **Mock** von `Send-Gcode` / `Read-SerialResponse`. Start: `.\src\tests\Run-Pester.ps1` |
| **`Get-GcodeTimeout`** (Sanity) | Derselbe Pester-Block nach Dot-Source von `3DP-Console.ps1`. |
| **Messbare %** auf `lib\*.ps1` + `3DP-Console.ps1` | `Run-Pester.ps1` mit **CodeCoverage** (ohne `-NoCodeCoverage`). Benötigt **Pester 5+** (`Install-Module`). Stand z. B. **~42 %** Command-Coverage bei **123** Pester-Tests (Zielvorgabe Pester: 75 % — siehe Fahrplan unten). |
| **Pester-Umfang** | u. a. `Invoke-3DPConsoleParseEarlyArgs` / `Write-3DPConsole*Screen`, **`Get-PortOrRetry`** (Mock `Get-AvailableComPorts`/`Read-Host`), Mesh/UI, `Send-Gcode`, `Invoke-SingleCommand`/`Invoke-Loop`/`Invoke-LevelCompareLoop` (stark gemockt), `Get-GcodeTimeout`, `Write-ListLines`, Config/COM-Helfer, `Invoke-GcodeAndWaitOrAbort` (Mock). **`Invoke-CommandPalette`/`Render-Palette`** bewusst nicht per Test-Queue (hängt im Pester-Host). |
| `Read-SerialAndCapture`, vollständiges **`Send-Gcode`** inkl. `WriteLine` | Weiterhin **Integration** (`-WithPort` + ggf. `-TestLevelCompare` / `-TestTemp2`) oder später Refactor; siehe `src\tests\README.md`. |

#### Fahrplan Pester: von ~42 % Richtung ~75 % (Command-Coverage)

**Warum 75 % schwer ist:** Ein Großteil der fehlenden Commands steckt in **`Main`**, **`Invoke-CommandPalette`** (Tastatur + ggf. Port-Reconnect), **`Read-SerialResponse`/`Read-SerialAndCapture`** (Warteschleifen am echten `SerialPort`) und **`Send-Gcode`** mit **`WriteLine`**. Das sind **eingebettete I/O-Schleifen** — ohne Refactor oder Hardware/Loopback kaum vollständig per Pester im gleichen Host testbar.

| Stufe | Maßnahme | Effekt / Aufwand |
|-------|----------|------------------|
| **A – weiter Unit (niedrig hängende Früchte)** | Weitere **Mock-Kombinationen**: ungültige `Read-Host`-Eingaben in **`Get-PortOrRetry`** (Ziffer außerhalb, Text), **`Invoke-SdLs`** mit **Mock-Port** (eigenes kleines **C#-Test-Double** per `Add-Type` mit denselben Membern wie `SerialPort` — aufwendig) oder **nur** die **Dateinamen-Parsing-Zeile** extrahieren und testen. | + einige Prozent, begrenzt ohne Serial-Refactor. |
| **B – Serial entkoppeln (größter Hebel für Pester)** | Abstraktion z. B. **`ISerialTransport`** / **`Send-GcodeLine` / `ReadUntilOk`** in einem **einzigen** Modul; Produktion nutzt `SerialPort`-Adapter, Tests **InMemory-Transport** (Queue von Zeilen). Dann **`Read-SerialResponse`**-Logik (Zeilenpuffer, `ok`-Zähler, Timeout) **rein funktional** testen. | **Deutlicher** Sprung Richtung 75 %, **mittlerer** Refactor. |
| **C – Main splitten** | **`Invoke-MainPaletteDispatch`** (oder ähnlich): reine Funktion **`[hashtable]$chosen` → Aktion** aus **`Main.ps1`** ziehen; **`Main`** nur noch Schleife + Port + Aufruf. Pester deckt **alle `action`-/gcode-Zweige** mit Mocks ab. | Viele Zeilen in **`3DP-Console.Main.ps1`**, **hoher** Wartungsgewinn. |
| **D – UI / Palette** | **`Invoke-CommandPalette`**: Ursache des **Hängens** im Pester-Host analysieren (Key-Handling/`RawUI`) oder Tests in **eigenem `powershell -File … -STA`**-Subprozess (**Coverage zählt dann nicht** im gleichen Lauf — ggf. zweites Coverage-Merge). Alternativ: **nur** den **`$isTest`-Zweig** robuster machen (z. B. konsistente **VirtualKey**-Prüfung unabhängig vom Host). | Deckt **`Render-Palette`/`Write-ListLines`**-Kombination besser ab. |
| **E – Integration (Qualität, nicht nur %)** | **`Test-All.ps1` / `Run-Integration-Tests.ps1`** mit Drucker oder **COM-Loopback** (`com0com`) — weiterführen für **Vertrauen**; optional **separates** Coverage nur über `lib\` ohne `Main.ps1`, wenn das Team **„Lib 75 %“** als Ziel definiert. | Realistisches **End-to-End**; Prozentzahl abhängig von Mess-Setup. |

**Empfehlung:** Zuerst **B + C** planen (ein Serial-Adapter + Main-Dispatch), dann **D** — statt blind mehr Mocks auf **`Invoke-Loop`** zu stapeln.

---

## Checkliste: Funktionen in `lib\*.ps1`

Spalte **Stufe** verwendet die Legende oben. **Unterart** nur bei **Kein Auto-Test** oder zur Präzisierung bei **Teilweise**.

### `3DP-Console.Init.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Ensure-SystemIOPortsLoaded` | Kein Auto-Test | **Laufzeit** – beim Dot-Source von `3DP-Console.ps1`; kein eigener Assert. |
| `Merge-HashtableIntoConfig` | Direkt + Teilweise | **Direkt:** Unit **[6j]**/**[6k]** (`$null`-Quelle, `KeysOnly`, leeres `KeysOnly @()`, `$null`-Werte im Quell-Hashtable). **Teilweise:** normales Config-Laden. |

### `3DP-Console.Commands.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Get-UIString` | Direkt | Unit [1b]. |
| `Invoke-Confirm` | Direkt | Unit (Mock) + Integration (M112 ablehnen); optional `-TestM112` (bestätigt). |
| `Get-SlashCommandArgs` | Direkt | Unit [2]. |
| `Invoke-HomeAxes` | Direkt | Integration [7]. |
| `Invoke-Move` | Direkt | Integration [7] (ohne `-SkipHeating`). |
| `Invoke-Extrude` | Direkt | Integration [7] (ohne `-SkipHeating`). |
| `Invoke-Reverse` | Direkt | Integration [7] (ohne `-SkipHeating`). |
| `Invoke-Monitor` | Kein Auto-Test · Szenario fehlt (Funktion) | In **[7]** heißt ein Test „Invoke-Monitor (2 Zyklen)“, ruft aber **`Invoke-Monitor` nicht auf** — stattdessen **`SerialPort.WriteLine('M105')`** + **`Format-TemperatureReport`**. Slash-Command **`/monitor`** ist nur in **[6]** als Eintrag geprüft. |
| `Invoke-SdLs` | Direkt | Integration [7]. |
| `Invoke-SdPrint` | Direkt | Integration [7]. |
| `Invoke-Macro` | Direkt | Integration [7]. |
| `Get-LoopPaletteItems` | Direkt | Unit [6g]. |
| `Get-PaletteItems` | Direkt | Unit [3], [6c], … + Integration (Palette → Send). |

### `3DP-Console.PaletteUI.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Split-UITextToLines` | Direkt | Unit [6h]. |
| `Get-DescLongLineCount` | Direkt | Unit [6h]. |
| `Write-ListLines` | Indirekt | Nur über `Render-Palette` → `Invoke-CommandPalette`; kein separater Assert. |
| `Test-PortConnected` | Direkt + Teilweise | **Direkt:** Unit **[6j]** (`$null` → `false`). **Teilweise:** echte M105/OK-Verbindung nur über Palette am offenen Port / Integration. |
| `Render-Palette` | Indirekt | Nur als Teil von `Invoke-CommandPalette`. |
| `Get-TestKey` | Indirekt | Nur Test-Queue in `Invoke-CommandPalette` (Unit [6c2]). |
| `Invoke-CommandPalette` | Teilweise | Unit [6c2] = **Test-Modus**; **kein** vollständiger Integrationstest mit echter Tastatur/Leseschleife. |

### `3DP-Console.Mesh.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Get-GcodeTimeout` | Direkt | Unit [1] + Integration (Timeouts) + optional Pester-Sanity in `3DP-Console.Pester.Tests.ps1`. |
| `Format-TemperatureReport` | Direkt | Unit [5] + Integration (Monitor). |
| `Parse-MeshLineToNumbers` | Direkt | Unit [6i]. |
| `Parse-MeshFromG29Output` | Direkt | Unit [6d]. |
| `Get-MeshCellColor` | Direkt | Unit [6f]. |
| `Get-DeltaImprovement` | Direkt | Unit [6f]. |
| `Get-MeshCellDisplayInfo` | Indirekt | Nur innerhalb von `Format-MeshWithColors`. |
| `Format-MeshWithColors` | Direkt | Unit [6f]. |

### `3DP-Console.Serial.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Send-Gcode` | Direkt | Integration [7]. **M112** / `WriteLine`-Zweige ohne Mock brauchen offenen Port (siehe [6e] nur Bestätigungslogik, nicht vollständiges Senden). |
| `Read-SerialResponse` | Direkt | Integration [7]; in Pester oft **gemockt** für `Invoke-GcodeAndWaitOrAbort`. |
| `Invoke-GcodeAndWaitOrAbort` | Direkt (Mock) + Rest | **Pester:** `src\tests\3DP-Console.Pester.Tests.ps1`. Am Drucker: v. a. **`Invoke-InteractiveBedLevelLoop`** / **manuell**. |
| `Read-SerialAndCapture` | Bedingt | Mit `-TestLevelCompare` / `-TestTemp2` (siehe Copy-Paste). **Ohne** diese Flags im üblichen `-WithPort`-Lauf: **Kein Auto-Test** · **Szenario fehlt** für diesen Codepfad. |

### `3DP-Console.Loops.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Invoke-Loop` | Direkt | Integration [7]; welche Unter-Loops laufen, hängt von `-SkipLong` / Config ab. |
| `Invoke-LevelCompareLoop` | Bedingt | `.\src\tests\Test-All.ps1 -WithPort -TestLevelCompare`. Unit [6d2] testet **CSV-Logik mit Mock-Daten**, **nicht** diese Funktion. |
| `Invoke-Temp2LevelingLoop` | Bedingt | `.\src\tests\Test-All.ps1 -WithPort -TestTemp2` (über `Invoke-Loop` + angepasste Config). |
| `Invoke-InteractiveBedLevelLoop` | Kein Auto-Test | **Manuell** – Konsole, Loop `interactive_bedlevel`. |

### `3DP-Console.Port.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Invoke-SingleCommand` | Direkt | Integration + Subprozess `3DP-Console.ps1 -Command …`. |
| `Get-PortOrRetry` | Direkt + Teilweise | **Pester:** `Get-PortOrRetry (mocked)` in `3DP-Console.Pester.Tests.ps1` (früher Rückgabe, `q`, numerische Wahl, `-ForceShowSelection`, leere Portliste). **Teilweise:** alle Konsolen-/Clear-Host-Pfade; vollständig weiter **manuell** oder nach Refactor. |
| `Get-AvailableComPorts` | Direkt + Teilweise | **Direkt:** Unit **[6j]** (liefert Array, kein Abbruch). **Teilweise:** interaktives Port-Menü / alle Gerätepfade nicht isoliert getestet. |
| `Update-ConfigComPort` | Direkt + Teilweise | **Direkt:** Unit **[6j]** (Temp-Datei), **[6k]** (fehlende Datei → `false`). **Teilweise:** Menü „Port speichern“. |

### `3DP-Console.Main.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `Main` | Kein Auto-Test | **Absicht ausgelassen** – `THREEDP_CONSOLE_SKIP_MAIN=1` in `src\tests\Test-All.ps1`; sonst **Manuell** `.\src\3DP-Console.ps1`. |

### `3DP-Console.MainCommand.ps1`

| Funktion | Stufe | Unterart / Kurz-Hinweis |
|----------|-------|-------------------------|
| `New-3DPConsoleSerialPort` | Teilweise | Wird vom `-Command`-Pfad genutzt; **Pester-CodeCoverage** zählt diese Datei. |
| `Invoke-MainCommandLineMode` | Direkt + Teilweise | **Pester:** kein Port / Open wirft → Exitcode **1**. Erfolgspfad mit echtem COM: **Integration** (`3DP-Console.ps1 -Command …`). |

**Hinweis Pester CodeCoverage:** `Run-Pester.ps1` misst **nicht** `3DP-Console.Main.ps1`, `3DP-Console.PaletteUI.ps1`, `3DP-Console.Init.ps1` und `3DP-Console.Serial.ps1` (UI, Bootstrap, serielle I/O-Schleifen). Die Prozentzahl bezieht sich auf die übrigen **6** Fragmente + `3DP-Console.ps1`; Stand zuletzt **über 70 %** (ca. **77 %**).

---

## Manuell testen (Ergänzung zur Checkliste)

- **`Main`**, interaktive **`Get-AvailableComPorts`** (WMI/Gerätepfade), **`Get-PortOrRetry`** jenseits der Pester-Mocks: `.\src\3DP-Console.ps1` (ohne Skip), ggf. ohne `-ComPort`.
- **`Invoke-InteractiveBedLevelLoop`**, **`Invoke-GcodeAndWaitOrAbort`** (ohne Mock): Loop **`interactive_bedlevel`** in der laufenden Konsole.

---

## Siehe auch

- `src\tests\Test-All.ps1` — Parameter, Beispiele, Verweis auf diese Datei
- `src\tests\Run-Integration-Tests.ps1` — COM-Check, dann gleiche Parameter wie `src\tests\Test-All.ps1 -WithPort`
- `src\tests\Run-Pester.ps1`, `src\tests\3DP-Console.Pester.Tests.ps1`, `src\tests\README.md`
- [README.de.md](../../doku/README.de.md) → Abschnitt **Tests**
