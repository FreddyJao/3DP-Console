# 3DP-Console

[Deutsch](doku/README.de.md)

**A personal note:** This is my first public repository. The tool was born out of necessity: I had a problematic Prusa Mini printer that needed debugging and realignment. Manual G-Code testing was too slow, and existing tools didn't fit my workflow. So I built this—and it helped me find that my sensor was defective. I'm sharing it in case it helps others in similar situations.

---

## What is it?

3DP-Console is a tool for controlling and testing G-Code-based 3D printers from a Windows PC. It is designed for simple, fast, and automated tests without complex or heavy software.

## Motivation

I had to debug and realign a Prusa Mini printer. During that process, I ran many manual tests—sensor behavior, bed leveling, temperature tests. Manually executing G-Code commands was too slow and inefficient. Existing tools didn't suit my needs, so I built my own.

With this tool, I could run automated tests, analyze sensor responses, measure the bed repeatedly, and systematically investigate printer behavior. In the end, the sensor was defective—something that would have taken much longer to discover without these automated tests.

## Features

### Interactive terminal with search-style autocomplete

Type **`/`** (slash commands), **`G`**, or **`M`** to open the palettes—similar to autocomplete. Entries are fully configurable in [`src/3DP-Config.ps1`](src/3DP-Config.ps1) (only the commands you define are shown).

### Loops

Create automated workflows that repeat tests. Useful for temperature tests, sensor analysis, or repeated bed measurements. Use predefined loops or define your own.

### Macros

Combine multiple commands into one sequence. Simplifies recurring processes like calibration or diagnostics.

### Highly configurable

Configure COM port, baud rate, macros, loops, commands, response timeouts, and material parameters (e.g. PLA temperatures). Not all options are fully documented yet—check the code and `3DP-Config.ps1` for details.

## Prusa Mini and beyond

The tool was developed for the Prusa Mini and includes a configuration for it. It is structured so you can adapt it to other G-Code printers by creating your own configs, macros, and commands.

## Testing guideline

A guideline describes how to test and analyze the Prusa Mini. It covers printer preparation, firmware handling, and test/calibration workflows. See [doku/guide.md](doku/guide.md) for the Level-Compare quick guide.

**Layout:** Entry script [`src/3DP-Console.ps1`](src/3DP-Console.ps1), printer/settings in [`src/3DP-Config.ps1`](src/3DP-Config.ps1), most logic in [`src/lib/`](src/lib/) fragments loaded by the console.

## Requirements

- **Windows** with PowerShell 5.1 or higher (Windows 10+)
- **.NET Framework** with `System.IO.Ports` (loaded automatically if needed)
- Printer connected via USB (data cable, not charge-only)
- Virtual **COM port** (e.g. COM4, COM5)

## Quick start

From the **repository root** (the folder that contains `src/`):

```powershell
.\src\3DP-Console.ps1
.\src\3DP-Console.ps1 -ComPort COM4
.\src\3DP-Console.ps1 -Help
.\src\3DP-Console.ps1 -Command "loop level_compare"
```

**Note:** `Start-Console.cmd` in the repo root launches `src\3DP-Console.ps1`.

## Tests

- **Function-level checklist (German):** direct, indirect, partial, conditional, no auto-test + subtypes — [TEST-COVERAGE.de.md](src/tests/TEST-COVERAGE.de.md)
- **Pester 5** (optional, mocks + code coverage on selected `src` files): install, coverage rules, and what is *not* measured — [src/tests/README.md](src/tests/README.md)

Run all commands from the **repository root** (folder that contains `src/`).

```powershell
.\src\tests\Test-All.ps1                          # Unit tests (no printer)
.\src\tests\Test-All.ps1 -WithPort                # + serial integration (COM from src\3DP-Config.ps1, often COM5)
.\src\tests\Test-All.ps1 -WithPort -SkipLong:$false   # Also G29, prepare, level_rehome_once, temp_ramp (long, heats)
.\src\tests\Test-All.ps1 -WithPort -TestLevelCompare  # + level_compare 2× (~10+ min, CSV)
.\src\tests\Test-All.ps1 -WithPort -TestTemp2         # + temp2_nozzle minimal run
.\src\tests\Test-All.ps1 -IntegrationPlanOnly       # Unit tests + print integration plan, skip hardware [7]

.\src\tests\Run-Pester.ps1                    # optional: Pester 5 + code coverage (Install-Module Pester)
.\src\tests\Run-Pester.ps1 -NoCodeCoverage    # Pester only, faster

.\src\tests\Run-Integration-Tests.ps1             # Checks port is free, then src\tests\Test-All.ps1 -WithPort (same defaults; no level_compare without -TestLevelCompare)
.\src\tests\Run-Integration-Tests.ps1 -TestLevelCompare   # optional: long level_compare run
.\src\tests\Run-Integration-Tests.ps1 -DryRun -SkipPortCheck   # show planned args only (no tests, no COM open)
# Same extras as src\tests\Test-All.ps1, e.g. -SkipLong:$false -TestTemp2 -TestM112
```

## Support

I'm still new to GitHub and won't be developing this every day. If you find bugs or have improvements, feel free to open issues or pull requests. I'll take a look and may merge them. The tool was built for my own use but is published in case it helps others with similar problems.

---

**Good luck and have fun with the tool.**
