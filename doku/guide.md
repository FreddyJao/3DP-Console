# Schnell-Guide: Bett-Leveling mit 3DP-Console

> **Konfiguration:** Zentrale Datei vom Repository-Root aus: [`src/3DP-Config.ps1`](../src/3DP-Config.ps1) (COM-Port, `CsvOutputPath`, Loop-Parameter, Mesh-Schwellen, …).

Überblick: **Level-Compare** (CSV, mehrere Runden), optional **Interactive Bed Leveling** (Mesh live) und **Temp2** (Temperatur-Serien mit CSV). Alle genannten Schwellen und Pfade einstellbar in **`src/3DP-Config.ps1`**.

## 1. Firmware (einmalig, Beispiel Prusa Mini)

> Aktuelle empfohlene Version siehst du auf der Prusa-Website für dein Modell. Die folgenden Schritte gelten typisch für `.bbf`-Updates (Beispiel: ältere 4.4.1).

1. Die passende Firmware-Datei (`.bbf`) herunterladen.
2. Datei auf einen USB-Stick kopieren (nur die `.bbf`-Datei, direkt im Hauptverzeichnis).
3. Drucker ausschalten, USB-Stick einstecken.
4. Drucker mit der **Reset-Taste** neu starten.
5. **Zweimal kurz hintereinander** am Drehrad drücken (mit kurzem Abstand).
6. Der Drucker erkennt die Firmware und spielt sie automatisch aus.
7. Nach dem Update USB-Stick entfernen.

---

## 2. Konsole starten

1. Drucker mit dem Rechner per USB verbinden.
2. PrusaSlicer, Pronterface und andere Programme, die den Drucker nutzen, **schließen**.
3. Konsole starten: `Start-Console.cmd` im Repository-Root oder per PowerShell: `.\src\3DP-Console.ps1`.
4. Die serielle Abhängigkeit (System.IO.Ports) wird bei Bedarf **automatisch** installiert.

---

## 3. COM-Port einstellen (falls nötig)

- Wird der Port nicht gefunden oder verbindet die Konsole nicht, beim Fehlerbildschirm **[p]** drücken.
- Port aus der Liste wählen (z.B. COM5) und mit Enter bestätigen.

---

## 4. Heizung vorbereiten

In der Konsole eingeben:

```text
/pla
```

Warten, bis **Düse und Heizbett** die Zieltemperatur erreicht haben.

---

## 5. Level-Compare ausführen

Dann eingeben:

```text
loop level_compare 5
```

- **5** = 5 Messrunden (Zahl nach Bedarf; ohne Zahl nutzt der Loop den Default in **`src/3DP-Config.ps1`**, z. B. `repeat = 3`).
- Ergebnisse als CSV: Ordner **`CsvOutputPath`** in **`src/3DP-Config.ps1`** (Standard: `BedLevelResults/` neben den Skripten unter `src/`).

---

## 6. Interactive Bed Leveling (optional)

Interaktives Mesh nach **G29**, farblich nach Abweichung (Schwellen in **`src/3DP-Config.ps1`**: **`MeshThresholdGreenMm`**, **`MeshThresholdYellowMm`**).

```text
loop interactive_bedlevel
```

- **Enter** = erneut messen (neues G29), **Esc** = Beenden  
- Temperaturen: **`bedTemp`** / **`nozzleTemp`** im Loop-Eintrag `interactive_bedlevel` in **`src/3DP-Config.ps1`**

---

## 7. Temp2-Loops (optional, längere Läufe, CSV)

Systematisch **verschiedene Temperaturen** durchfahren, pro Schritt **G28 + G29**, Ausgabe als CSV (wie bei Level-Compare unter **`CsvOutputPath`**). **`stabilizationSeconds`** = Wartezeit nach Temperaturwechsel.

| Befehl | Kurzidee |
|--------|-----------|
| `loop temp2_nozzle` | Düsentemperatur in Schritten, Bett oft fix (`fixedBed`) |
| `loop temp2_bed` | Betttemperatur in Schritten, Düse fix (`fixedNozzle`) |
| `loop temp2_combined` | Düse und Bett gleichzeitig in Schritten |

Start/Ende/Schrittweiten: jeweils `startNozzle`/`endNozzle`/`stepNozzle`, `startBed`/`endBed`/`stepBed` in **`src/3DP-Config.ps1`** anpassen. **Laufzeit und Verschleiß** beachten (viele G29).

---

## Kurzüberblick

| Schritt              | Aktion                                           |
|----------------------|---------------------------------------------------|
| Firmware             | `.bbf` auf USB → Drucker → Reset → 2× Drehrad     |
| Konsole starten      | USB verbinden, Skript starten                     |
| COM-Port             | Bei Problemen **[p]** drücken und Port wählen     |
| Heizung              | `/pla` oder `loop prepare`, auf Temperatur warten |
| Level-Compare        | `loop level_compare 5` ausführen                  |
| Interactive Mesh     | `loop interactive_bedlevel`                       |
| Temp2-Serien         | `loop temp2_nozzle` / `temp2_bed` / `temp2_combined` |
