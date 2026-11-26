# Milestone 1 runtime validation (WP12, spec section 13)

Run on 2026-11-25 at branch commit `c2a005d` (`feat/3.1.0-authoring-second-pass`), pwsh 7.7.0 from the Microsoft Store (.NET 11.0.0) on Microsoft Windows 11 Pro 10.0.26300, not elevated, dotnet SDK 10.0.404, PSReadLine 2.4.5, Pester 6.2.0, PSScriptAnalyzer 1.25.0, InvokeBuild 5.14.23, ripgrep 15.2.0. The branch build reports `ModuleVersion` 3.0.1 (section 11: the version is stamped by the release commit) and loads `CompleterActions.Core.dll` 3.0.0.0. The 3.0.1 build is tag `v3.0.1` extracted with `git archive` into `C:\Users\Trent\AppData\Local\Temp\m31\scratch\v3.0.1\CompleterActions` and compiled there by WP11, never the gallery copy.

`<scratch>` is `C:\Users\Trent\AppData\Local\Temp\m31\scratch\followup-wp12`, outside the repository; `<repo>` is the integration worktree `C:\Users\Trent\AppData\Local\Temp\m31\INT\CompleterActions`; `$module` is `<repo>\build\CompleterActions`; `<v3.0.1>` is `C:\Users\Trent\AppData\Local\Temp\m31\scratch\v3.0.1\CompleterActions\build\CompleterActions`. Every row ran in its own `pwsh -NoProfile -File <scratch>\<row>.ps1` and began with section 13's preamble (`Import-Module -Name "$module\CompleterActions.psd1" -Force` and the `ModuleBase` assertion), which printed `ModuleBase OK: ...`, except where a row says otherwise. Every row's last line lists the loaded `CompleterActions` modules, and each listed only the build under test. The harness scripts and their logs are scratch files and are not committed.

PS_Completers was read through two scratch clones of `9db457c` (`master`, 176 `*_completer.ps1` scripts): the shared clone `C:\Users\Trent\AppData\Local\Temp\m31\scratch\PS_Completers` (rows 6 and 9, read only; `git status --short` there was empty after them), and row 4's own clone `<scratch>\PS_Completers`, made with `git clone C:\Users\Trent\AppData\Local\Temp\m31\scratch\PS_Completers <scratch>\PS_Completers`. No row wrote the real repository, the installed modules, or the PSResourceGet store. No `pwsh` held the branch build before the build step; three of the owner's shells held the installed `CompleterActions\3.0.1\lib\CompleterActions.Core.dll` and were left alone.

## Summary

| Row | Check | Result |
| --- | --- | --- |
| 1 | Run steps: build, lint, suite | pass |
| 2 | Check 1, owner form: `rg` | pass |
| 3 | Check 2, owner form: the installed PS_Completers | pass |
| 4 | Check 3, owner form: the scratch clone and `git diff` | pass |
| 5 | Check 14, owner form: `winget` | pass |
| 6 | Check 15, PS_Completers scan | pass |
| 7 | Check 19, full suite with the Store alias first on `PATH` | pass |
| 8 | Check 21, surface against the 3.0.1 build | pass |
| 9 | Check 23, PS_Completers suite and strict import | pass |
| 10 | Section 10, the two `Update-CompleterSet` times | pass (reported by WP11) |
| 11 | Section 15 amendment 1, a strict entry that fails the grammar | pass |
| 12 | Section 15 amendment 2, an unreadable candidate under a version parameter | pass |
| 13 | Section 15 amendment 3, a directory at the markdown path | pass |
| 14 | Section 15 amendment 4, the action and over-limit texts | pass |

## Row 1: run steps

Three processes, in order, from `<repo>`:

```powershell
pwsh -NoProfile -Command "Invoke-Build -Task build"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'
```

```text
Build succeeded. 4 tasks, 0 errors, 0 warnings 00:00:07.9093919
(git status --short afterwards: empty, so the committed build/ is fresh)
(the two Invoke-ScriptAnalyzer calls: no output, exit 0)
Tests completed in 746.62s
Tests Passed: 1152, Failed: 0, Skipped: 16, Inconclusive: 0, NotRun: 0
```

Row 7 gives the suite's detail. Result: **pass**.

## Row 2: check 1, `rg`

`<scratch>\check1.ps1`, which runs `New-CompleterScript -CommandName rg -Path <scratch>\check1\rg_completer.ps1 -PassThru -Verbose`, then `$file | Test-CompleterScript` and `Get-Content -LiteralPath $file.FullName -TotalCount 2`. `rg` is the first application on `PATH`, `C:\Users\Trent\.pi\agent\bin\rg.exe`.

```text
rg first on PATH: C:\Users\Trent\.pi\agent\bin\rg.exe
rg --version: ripgrep 15.2.0 (rev e89fff89ac)
VERBOSE: Resolved 'rg' to the application 'C:\Users\Trent\.pi\agent\bin\rg.exe'.
VERBOSE: Performing the operation "Create completer script, running 'C:\Users\Trent\.pi\agent\bin\rg.exe --help' and, if it is rejected, '/?' to read its help" on target "<scratch>\check1\rg_completer.ps1".
VERBOSE: Probed 'C:\Users\Trent\.pi\agent\bin\rg.exe --help': exit 0, 74735 characters, 0 subcommands, 145 options, 36 ms.
VERBOSE: Wrote '<scratch>\check1\rg_completer.ps1': 2 targets, 0 subcommands, 145 options.
PassThru: 1 object(s), type System.IO.FileInfo, <scratch>\check1\rg_completer.ps1
$file | Test-CompleterScript : 0 findings
Get-Content -TotalCount 2:
  # rg tab completion for PowerShell
  # Help-seeded native completer: the tables were read from 'rg --help' when the script was generated.
Subcommands line: Subcommands = @()
Options rows: 145; contains --regexp: True; first five: -e, --regexp, -f, --file, --pre
Test-CompleterRegistration 'rg --reg' -TargetOnly: --regexp (ParameterName), --regex-size-limit (ParameterName)
```

The last line is after `Register-Completer -LiteralPath <file> -Lazy`, as an extra look at check 6's first bullet with the live script. Result: **pass**.

## Row 3: check 2, the installed PS_Completers

`<scratch>\check2.ps1`, with the real `$env:PSModulePath` unchanged. PS_Completers 1.3.1, 1.3.0, and 1.2.0 are installed under `C:\Users\Trent\OneDrive\Documents\PowerShell\Modules\PS_Completers`. Each call's verbose and warning records were counted, and its first verbose line printed; the `What if:` lines went to the host.

```text
== Import-CompleterSet -Name PS_Completers -MinimumVersion 1.1.3 -WhatIf -Verbose
verbose lines: 178; warnings: 0; output objects: 0
VERBOSE: Completer set module 'PS_Completers' 1.3.1 at 'C:\Users\Trent\OneDrive\Documents\PowerShell\Modules\PS_Completers\1.3.1': 'C:\Users\Trent\OneDrive\Documents\PowerShell\Modules\PS_Completers\1.3.1\completers\completers.psd1'.
== Import-CompleterSet -Name PS_Completers -WhatIf -Verbose (no version parameter)
verbose lines: 178; warnings: 0; output objects: 0
VERBOSE: Completer set module 'PS_Completers' 1.3.1 at '...\PS_Completers\1.3.1': '...\PS_Completers\1.3.1\completers\completers.psd1'.
== Import-CompleterSet -Name PS_Completers -RequiredVersion 1.2.0 -WhatIf -Verbose
verbose lines: 177; warnings: 0; output objects: 0
VERBOSE: Completer set module 'PS_Completers' 1.2.0 at '...\PS_Completers\1.2.0': '...\PS_Completers\1.2.0\completers\completers.psd1'.
== Import-CompleterSet -Name PS_Completers -MinimumVersion 2.0.0 -WhatIf
ERROR: Failed to import completer set. No installed module named 'PS_Completers' with version 2.0.0 or later was found in $env:PSModulePath. Installed versions: 1.3.1, 1.3.0, 1.2.0.
== Test-CompleterSet -Name PS_Completers -MinimumVersion 1.1.3
verbose lines: 0; warnings: 0; output objects: 0
Get-Completer after the WhatIf calls: 0 managed registrations
What if lines (from the log): 527, for example
What if: Performing the operation "Import completer set entry" on target "C:\Users\Trent\OneDrive\Documents\PowerShell\Modules\PS_Completers\1.3.1\completers\7z_completer\7z_completer.ps1".
```

`-MinimumVersion 1.1.3` names the highest installed version, 1.3.1, and nothing was registered or written. The rows for `-RequiredVersion 1.2.0` and `-MinimumVersion 2.0.0` are extra looks at the same rule with the installed copies. Result: **pass**.

## Row 4: check 3, the scratch clone

`<scratch>\check3.ps1 -Clone <scratch>\PS_Completers`. The clone's working tree has CR LF line endings (`core.autocrlf` is `true` globally). The script appends the line `# WP12 runtime validation change` to `rg_completer\rg_completer.ps1`, which changes its hash and not its targets, then runs the spec's two lines.

```text
set bytes before: 67589
Test-CompleterSet before the change: 0 findings
Test-CompleterSet after the change: 1 findings: HashMismatch Warning
> Test-CompleterSet <clone>\ps_completers.psd1 | Update-CompleterSet
VERBOSE: Performing the operation "Update 1 Hash value" on target "<scratch>\PS_Completers\ps_completers.psd1".
VERBOSE: Updated the Hash of entry 111 ('rg_completer/rg_completer.ps1') in '<scratch>\PS_Completers\ps_completers.psd1'.
VERBOSE: Updated 1 of 176 entries in '<scratch>\PS_Completers\ps_completers.psd1'.
warnings: 0
> Test-CompleterSet <clone>\ps_completers.psd1
findings: 0
set bytes after: 67589; length unchanged: True
differing byte offsets: 63, first 42626, last 42689
all differing bytes inside one single-quoted SHA256 value: True (value at offset 42618, length 73)
```

(`-Verbose` was added to the `Update-CompleterSet` call to show the action; 63 of the 64 hex digits differ.)

`git -C <scratch>\PS_Completers diff --stat`:

```text
 ps_completers.psd1            | 2 +-
 rg_completer/rg_completer.ps1 | 1 +
 2 files changed, 2 insertions(+), 1 deletion(-)
```

`git -C <scratch>\PS_Completers diff`:

```diff
diff --git a/ps_completers.psd1 b/ps_completers.psd1
index ce10746..1d42b37 100644
--- a/ps_completers.psd1
+++ b/ps_completers.psd1
@@ -1007,7 +1007,7 @@
         @{
             Path    = 'rg_completer/rg_completer.ps1'
             Trusted = $false
-            Hash    = 'SHA256:5C616B8D2892F21BDB20289F20805D72413AAA6FF0FBAE2A054D416D3638FF22'
+            Hash    = 'SHA256:160A88BE36B0AFA6310C96D74653F60EF2148E3FD39E7ADDD4E087E96BF3A206'
             Targets = @(
                 @{ CommandName = 'rg'; Native = $true }
                 @{ CommandName = 'rg.exe'; Native = $true }
diff --git a/rg_completer/rg_completer.ps1 b/rg_completer/rg_completer.ps1
index 1a9025b..1b95d24 100644
--- a/rg_completer/rg_completer.ps1
+++ b/rg_completer/rg_completer.ps1
@@ -1070,3 +1070,4 @@ Register-ArgumentCompleter -Native -CommandName 'rg', 'rg.exe' -ScriptBlock {
 
     @(Get-RgPositionalCompletions -CurrentWord $currentToken -Context $context)
 }
+# WP12 runtime validation change
```

The set file has one line changed, and in it only the `Hash` value; the second file is the script change itself. Result: **pass**.

## Row 5: check 14, `winget`

`<scratch>\check14.ps1`, which runs `New-CompleterScript -CommandName winget -Path <scratch>\check14\winget_completer.ps1 -Verbose`. `winget` is an app execution alias here, so the row ran.

```text
winget first on PATH: C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\winget.exe; Length 0; Attributes Archive, ReparsePoint
VERBOSE: Resolved 'winget' to the application 'C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\winget.exe'.
VERBOSE: 'C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\winget.exe' is an app execution alias for 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.30.310.0_x64__8wekyb3d8bbwe\winget.exe'.
VERBOSE: Performing the operation "Create completer script, running 'C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\winget.exe --help' and, if it is rejected, '/?' to read its help" on target "<scratch>\check14\winget_completer.ps1".
VERBOSE: Probed 'C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\winget.exe --help': exit 0, 2086 characters, 19 subcommands, 16 options, 127 ms.
VERBOSE: Wrote '<scratch>\check14\winget_completer.ps1': 2 targets, 19 subcommands, 16 options.
Test-Path script: True
Test-CompleterScript: 0 findings
  # Help-seeded native completer: the tables were read from 'winget --help' when the script was generated.
Subcommands rows: 19: install, show, source, search, list, upgrade, uninstall, hash ...
Options rows: 16: -v, --version, --info, -?, --help, --wait, --logs, --open-logs ...
```

A probe line with exit 0 and tables with rows; no warning. The live help gives 16 option names where the checked-in capture's prototype count in spec section 2 is 15; the capture is a different, earlier text (inferred from the counts, not compared). Result: **pass**.

## Row 6: check 15, the PS_Completers scan

`<scratch>\scan.ps1`, run once with `-Module $module` and once with `-Module <v3.0.1>`, in two processes, over every `*_completer.ps1` in the shared clone: `Test-CompleterScript -LiteralPath <all 176>`.

```text
branch: scripts: 176; Test-CompleterScript findings: 0
3.0.1 : scripts: 176; Test-CompleterScript findings: 0
```

The same as under 3.0.1. Result: **pass**.

## Row 7: check 19, the full suite

The suite run of row 1 is this check. It started 19:35:32 and ended 19:48:00 local time, exit 0:

```text
Running tests from 14 files.
[+] ...\tests\CompleterActions.Tests.ps1 145.92s (145 tests)
[+] ...\tests\CompleterAuthorTooling.Tests.ps1 47.61s (75 tests)
[+] ...\tests\CompleterClasses.Tests.ps1 4.07s (29 tests)
[+] ...\tests\CompleterHelpProbe.Tests.ps1 48.85s (66 tests)
[+] ...\tests\CompleterHelpText.Tests.ps1 1.87s (137 tests)
[+] ...\tests\CompleterImporter.Tests.ps1 61.86s (89 tests)
[+] ...\tests\CompleterLazyRegistration.Tests.ps1 25.25s (37 tests)
[+] ...\tests\CompleterRegistration.Tests.ps1 41.89s (50 tests)
[+] ...\tests\CompleterReset.Tests.ps1 22.19s (24 tests)
[+] ...\tests\CompleterScaffold.Tests.ps1 105.49s (147 tests)
[+] ...\tests\CompleterSet.Tests.ps1 93.83s (144 tests)
[+] ...\tests\CompleterSetDrift.Tests.ps1 24.63s (42 tests)
[+] ...\tests\CompleterSetPackage.Tests.ps1 90.35s (135 tests)
[+] ...\tests\CompleterSetUpdate.Tests.ps1 32.78s (48 tests)
Tests completed in 746.62s
Tests Passed: 1152, Failed: 0, Skipped: 16, Inconclusive: 0, NotRun: 0
```

The 16 skipped tests, read from `testResults.xml`, are Linux and macOS cases, case-sensitive file system cases, the named-pipe and file-size reader cases, the over-long path case for platforms where it raises no exception, the `Save-PSResource` and publish cases, and two `Test-CompleterSet` package cases (another drive, a folder that cannot be listed). None is the `winget` alias case or a pinned-`pwsh` case.

That the Store alias is first on `PATH` in a `-NoProfile` child, `<scratch>\check19-path.ps1` (no module import, so no preamble):

```text
PSHOME: C:\Program Files\WindowsApps\Microsoft.PowerShell_7.7.0.0_x64__8wekyb3d8bbwe
Get-Command pwsh -CommandType Application -All, in order:
  C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe  (Length 0; Attributes Archive, ReparsePoint)
  C:\Program Files\WindowsApps\Microsoft.PowerShell_7.7.0.0_x64__8wekyb3d8bbwe\pwsh.exe  (Length 212760; Attributes Archive)
  C:\Users\Trent\AppData\Local\Programs\pwsh7\pwsh.exe  (Length 212760; Attributes Archive)
  C:\Users\Trent\AppData\Local\Microsoft\WindowsApps\pwsh.exe  (Length 0; Attributes Archive, ReparsePoint)
first is under WindowsApps and a reparse point: True
```

Result: **pass**.

## Row 8: check 21, surface

`<scratch>\surface.ps1`, once per build in two processes, then `<scratch>\compare-surface.ps1` over the two JSON files. For each of the 11 functions 3.0.1 exports, the dump holds the default set, the `OutputType` names, the parameter names, and for each parameter set its name, `IsDefault`, and each parameter's type, `Mandatory`, `Position`, `ValueFromPipeline`, `ValueFromPipelineByPropertyName`, and aliases. For each exported type of the `CompleterActions` namespace it holds the kind and the property list in declaration order (enum names and values for an enum).

```text
branch: functions: 12 (Export-CompleterSet, Get-Completer, Import-CompleterScript, Import-CompleterSet, New-CompleterScript, Register-Completer, Reset-Completer, Test-CompleterRegistration, Test-CompleterScript, Test-CompleterSet, Unregister-Completer, Update-CompleterSet); aliases: 0
branch: assembly: CompleterActions.Core 3.0.0.0 at <repo>\build\CompleterActions\lib\CompleterActions.Core.dll
branch: other exported types: CompleterActions.Internal.AppExecutionAlias, CompleterActions.Internal.EngineAccess, CompleterActions.Internal.EnginePath, CompleterActions.Internal.GrammarFinding, CompleterActions.Internal.StrictGrammar
3.0.1 : functions: 11 (the same, without Update-CompleterSet); aliases: 0
3.0.1 : assembly: CompleterActions.Core 3.0.0.0 at <v3.0.1>\lib\CompleterActions.Core.dll
3.0.1 : other exported types: CompleterActions.Internal.EngineAccess, CompleterActions.Internal.EnginePath, CompleterActions.Internal.GrammarFinding, CompleterActions.Internal.StrictGrammar
command differences: 16
  Import-CompleterSet: parameter added -MinimumVersion
  Import-CompleterSet: parameter added -RequiredVersion
  Import-CompleterSet [Name]: -MinimumVersion added (Mandatory False, Type System.Version)
  Import-CompleterSet [Name]: -RequiredVersion added (Mandatory False, Type System.Version)
  New-CompleterScript: parameter added -Documentation
  New-CompleterScript [HelpText]: -Documentation added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  New-CompleterScript [NoProbe]: -Documentation added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  New-CompleterScript [Probe]: -Documentation added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  Test-CompleterRegistration: parameter added -TargetOnly
  Test-CompleterRegistration [CommandParameter]: -TargetOnly added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  Test-CompleterRegistration [InputObject]: -TargetOnly added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  Test-CompleterRegistration [Native]: -TargetOnly added (Mandatory False, Type System.Management.Automation.SwitchParameter)
  Test-CompleterSet: parameter added -MinimumVersion
  Test-CompleterSet: parameter added -RequiredVersion
  Test-CompleterSet [Name]: -MinimumVersion added (Mandatory False, Type System.Version)
  Test-CompleterSet [Name]: -RequiredVersion added (Mandatory False, Type System.Version)
CompleterActions namespace types: branch 6, 3.0.1 6; Compare-Object -CaseSensitive -SyncWindow 0 (names, kinds, member lists in order): 0 lines
  CompleterActions.CompleterRegistration (class): 18 members
  CompleterActions.CompleterScriptFinding (class): 7 members
  CompleterActions.CompleterState (enum): 6 members
  CompleterActions.CompleterType (enum): 2 members
  CompleterActions.CompletionMatch (class): 13 members
  CompleterActions.ImportedCompleterRegistration (class): 16 members
```

Every difference is one of section 1's additions, each optional, in the sets section 1 names; no parameter, set, default set, or output type of 3.0.1 changed or went away. The one new exported type is in `CompleterActions.Internal`, as section 1 allows. The version line of check 21 belongs to the release commits (release recipe) and is not part of this row; the branch still reports 3.0.1. Result: **pass**.

## Row 9: check 23, PS_Completers under the branch build

The suite, `<scratch>\check23.ps1 -Clone C:\Users\Trent\AppData\Local\Temp\m31\scratch\PS_Completers`. It puts `<repo>\build` first on `$env:PSModulePath` and imports by name rather than by path, so in place of the preamble it asserts that `Import-Module CompleterActions -MinimumVersion 3.0.0` resolves to `$module`, then runs the clone's suite from the clone root:

```text
PSModulePath[0]: <repo>\build
ModuleBase first: <repo>\build\CompleterActions (ModuleVersion 3.0.1)
Pester: 6.2.0
Running tests from 3 files.
[+] ...\PS_Completers\tests\Choco.Tests.ps1 1.37s (15 tests)
[+] ...\PS_Completers\tests\Completers.Tests.ps1 14.33s (181 tests)
[+] ...\PS_Completers\tests\PathQuoting.Tests.ps1 39.67s (143 tests)
Tests completed in 55.38s
Tests Passed: 339, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
ModuleBase after: <repo>\build\CompleterActions
```

The clone's own `Import-Module -Name CompleterActions -MinimumVersion 3.0.0` lines resolved to the branch build.

Strict import, `<scratch>\scan.ps1` (row 6's script, same two processes): `Import-CompleterScript -LiteralPath <script> -ErrorAction Stop`, without `-Trusted`, one call per script, and a CSV of each record's script, `CommandName`, `ParameterName`, and `IsNative`:

```text
branch: strict Import-CompleterScript: 176 of 176 scripts imported, 372 records, 0 failures; scripts with at least one record: 176
3.0.1 : strict Import-CompleterScript: 176 of 176 scripts imported, 372 records, 0 failures; scripts with at least one record: 176
records CSV byte-identical: True (373 lines, SHA256 63239315772B865D08A5F2DE85921B47C8FF3A550A6991E94847151F2B63A7DA)
```

`git status --short` in the shared clone was empty afterwards, at `9db457c`. Result: **pass**.

## Row 10: section 10, the two `Update-CompleterSet` times

Not re-run here. WP11 measured both and recorded them in [milestone-1-benchmark.md](milestone-1-benchmark.md), section "Update-CompleterSet times (reported, not gated)": over the PS_Completers set in ten fresh processes each, a median of 1523.0 ms with no changed script and 1744.9 ms with one changed script, at `1a903db`. They are reported, not gated, so the row passes on being reported. `Update-CompleterSet` changed after `1a903db` (`8cc384e`, the section 15 rulings), so those times predate the grammar check of amendment 1 (inferred from the commit order; not re-measured).

## Row 11: section 15 amendment 1, an untrusted entry that fails the grammar

`<scratch>\amend1.ps1`: a two-entry set of conforming scripts written by `Export-CompleterSet`, then a top-level assignment appended to the first script.

```text
exported <scratch>\amend1\set\completers.psd1; Test-CompleterSet: 0 findings
appended a top-level assignment to <scratch>\amend1\set\alpha_completer\alpha_completer.ps1
Test-CompleterScript alpha: 1 Error(s); first: The script uses a top-level assignment.
Test-CompleterSet: HashMismatch Warning
set before: 682 bytes, SHA256 373BED31164C4B8C9752C03513DBB8E32FA9C247AFCCCD45586F2C2B99A1337D, LastWriteTimeUtc 2026-11-26T01:50:38.8382039Z
> Update-CompleterSet -LiteralPath $set -PassThru
PassThru: 0 files
WARNING: Entry 1 ('alpha_completer/alpha_completer.ps1') of '<scratch>\amend1\set\completers.psd1' was not updated: The script uses a top-level assignment. Regenerate the set with Export-CompleterSet.
set after:  682 bytes, SHA256 373BED31164C4B8C9752C03513DBB8E32FA9C247AFCCCD45586F2C2B99A1337D, LastWriteTimeUtc 2026-11-26T01:50:38.8382039Z
set unchanged: True
temporary files left: 0
Import-CompleterSet: ERROR: Failed to import completer set. Completer set '<scratch>\amend1\set\completers.psd1' has 1 invalid entry and nothing was registered. Fix the entries or use -SkipInvalid to register the valid ones.
Entry 1 ('alpha_completer/alpha_completer.ps1'): The script does not conform to the strict import grammar: line 14, column 1 (AssignmentStatementAst): The script uses a top-level assignment. Run Test-CompleterScript to work through the findings, or mark the entry Trusted to run it as-is.
```

The entry is skipped with the skipped-entry warning carrying the first grammar Error, the file is not written, and import still fails at import time, not at the first tab. Result: **pass**.

## Row 12: section 15 amendment 2, an unreadable candidate under a version parameter

`<scratch>\amend2.ps1 -Label branch`, then `<scratch>\amend2.ps1 -Label v301 -NoVersionOnly -Module <v3.0.1>` in a second process. In a scratch module root, `CaFixtureSet` 1.0.0 is a valid package built from `tests/Fixtures/CompleterSetPackage`, and a second copy has the manifest text `@{ ModuleVersion = '2.0.0'`, which does not parse: first as the version folder `2.0.0`, then as an unversioned manifest directly in `CaFixtureSet`. `$env:PSModulePath` is that root and `$PSHOME\Modules`. The `What if:` lines went to the host.

```text
== broken copy: VersionFolder (<root>\CaFixtureSet\2.0.0\CaFixtureSet.psd1)
> Import-CompleterSet -Name CaFixtureSet -MinimumVersion 1.0.0 -WhatIf -Verbose
  VERBOSE: Completer set module 'CaFixtureSet' 1.0.0 at '<root>\CaFixtureSet\1.0.0': '<root>\CaFixtureSet\1.0.0\completers\completers.psd1'.
> Import-CompleterSet -Name CaFixtureSet -RequiredVersion 1.0.0 -WhatIf -Verbose
  VERBOSE: Completer set module 'CaFixtureSet' 1.0.0 at '<root>\CaFixtureSet\1.0.0': '<root>\CaFixtureSet\1.0.0\completers\completers.psd1'.
> Test-CompleterSet -Name CaFixtureSet -MinimumVersion 1.0.0
  output: 1 objects
> Import-CompleterSet -Name CaFixtureSet -RequiredVersion 2.0.0 -WhatIf
  ERROR: Failed to import completer set. No installed module named 'CaFixtureSet' with version 2.0.0 was found in $env:PSModulePath. Installed versions: 1.0.0.
> Import-CompleterSet -Name CaFixtureSet -WhatIf -Verbose (no version parameter)
  ERROR: Failed to import completer set. The file '<root>\CaFixtureSet\2.0.0\CaFixtureSet.psd1' could not be parsed as a PowerShell Data File.
> Test-CompleterSet -Name CaFixtureSet (no version parameter)
  ERROR: Failed to test completer set. The file '<root>\CaFixtureSet\2.0.0\CaFixtureSet.psd1' could not be parsed as a PowerShell Data File.
== broken copy: Unversioned (<root>\CaFixtureSet\CaFixtureSet.psd1)
> Import-CompleterSet -Name CaFixtureSet -MinimumVersion 1.0.0 -WhatIf -Verbose
  VERBOSE: Completer set module 'CaFixtureSet' 1.0.0 at '<root>\CaFixtureSet\1.0.0': ...
> Import-CompleterSet -Name CaFixtureSet -RequiredVersion 1.0.0 -WhatIf -Verbose
  VERBOSE: Completer set module 'CaFixtureSet' 1.0.0 at '<root>\CaFixtureSet\1.0.0': ...
> Test-CompleterSet -Name CaFixtureSet -MinimumVersion 1.0.0
  output: 1 objects
> Import-CompleterSet -Name CaFixtureSet -RequiredVersion 2.0.0 -WhatIf
  ERROR: Failed to import completer set. No installed module named 'CaFixtureSet' with version 2.0.0 was found in $env:PSModulePath. Installed versions: 1.0.0.
> Import-CompleterSet -Name CaFixtureSet -WhatIf -Verbose (no version parameter)
  VERBOSE: Completer set module 'CaFixtureSet' 1.0.0 at '<root>\CaFixtureSet\1.0.0': ...
> Test-CompleterSet -Name CaFixtureSet (no version parameter)
  output: 1 objects
```

The 3.0.1 build, without a version parameter, gave the same results in both layouts: the same `could not be parsed` errors for the broken version folder, and 1.0.0 with one finding for the broken unversioned manifest. The one `Test-CompleterSet` finding is the fixture's own, from the 1.0.0 copy (`<scratch>\amend2-finding.ps1`): `PackageLayout Warning: The module manifest '<root>\CaFixtureSet\1.0.0\CaFixtureSet.psd1' does not require CompleterActions 2.2.0 or later, so installing the package does not install Import-CompleterSet -Name.`, because this scratch manifest has no `RequiredModules`.

With a version parameter, the unreadable copy is left out and the call works; without one, resolution and its error are as in 3.0.1. Result: **pass**.

## Row 13: section 15 amendment 3, a directory at the markdown path

`<scratch>\amend3.ps1`: an empty directory `<scratch>\amend3\rg_completer.md`, then the call without and with `-Force`, each with `-Verbose`, collecting every record written before the error.

```text
> New-CompleterScript -CommandName rg -Path <scratch>\amend3\rg_completer.ps1 -Documentation -Verbose
  records before the error: 0
  ERROR: Failed to create completer script. Documentation files must be file paths. '<scratch>\amend3\rg_completer.md' is a directory.
  script exists: False; md is still a directory: True; md directory entries: 0; files in folder:
> New-CompleterScript -CommandName rg -Path <scratch>\amend3\rg_completer.ps1 -Documentation -Verbose -Force
  records before the error: 0
  ERROR: Failed to create completer script. Documentation files must be file paths. '<scratch>\amend3\rg_completer.md' is a directory.
  script exists: False; md is still a directory: True; md directory entries: 0; files in folder:
```

No verbose record was written before the error, so neither the resolution nor the probe ran, and neither file was written. Result: **pass**.

## Row 14: section 15 amendment 4, the action and over-limit texts

`<scratch>\amend4.ps1`, on two-entry sets written by `Export-CompleterSet`:

```text
> Update-CompleterSet -LiteralPath <one>\completers.psd1 -WhatIf   (one changed script)
What if: Performing the operation "Update 1 Hash value" on target "<scratch>\amend4\one\completers.psd1".
  unchanged under -WhatIf: True
> Update-CompleterSet -LiteralPath <two>\completers.psd1 -WhatIf   (two changed scripts)
What if: Performing the operation "Update 2 Hash values" on target "<scratch>\amend4\two\completers.psd1".
  unchanged under -WhatIf: True
== over-limit text
set: <scratch>\amend4\big\completers.psd1, 131062 bytes; entry 1 Hash is 'x' (a 70-byte growth when rewritten)
Test-CompleterSet: InvalidHash Warning
> Update-CompleterSet -LiteralPath <big>\completers.psd1
  ERROR: Failed to update completer set. Completer set '<scratch>\amend4\big\completers.psd1' would be 131132 bytes after the update, which is larger than the 131072-byte limit for completer set files. Split its entries across several sets and regenerate them with Export-CompleterSet.
  unchanged: True; temporary files left: 0
> Export-CompleterSet keeps its own text: a set it would write over the limit
  ERROR: Failed to export completer set. The set would be 381649 bytes, larger than the 131072-byte limit for completer set files, so Import-CompleterSet could not read it. Export the registrations as several sets. Nothing was written.
```

The big set is the exported set with its first `Hash` value replaced by `'x'` and a padding comment line added at the top, written with `[System.IO.File]::WriteAllBytes`. The `Export-CompleterSet` text, for 1200 scratch scripts, is the 3.0.1 text (`<v3.0.1>\CompleterActions.psm1` line 269 holds the same sentence). Result: **pass**.

## Notes for the orchestrator

1. **Pester 6.2.0 locally.** The machine has Pester 6.2.0; CI pins 6.1.0. The suite and the PS_Completers suite ran under 6.2.0.
2. **Row 10 is a pointer.** The two times were measured by WP11 at `1a903db`, before `8cc384e` added the grammar check to `Update-CompleterSet` (amendment 1). They were not re-measured at `c2a005d`; if the pull request should carry times from the head commit, WP11's update harness has to run again. The same holds for WP11's import ratio: `git diff --stat 1a903db c2a005d -- src` lists `Resolve-CompleterSetModule.ps1`, `Import-CompleterSet.ps1`, and `Test-CompleterSet.ps1` among the twelve changed files, so the benchmark predates them too. Whether those changes touch the import path the `LazyNoHash` row measures was not checked here.
3. **Rows 7 and 9 do not start with the preamble.** Row 7's `PATH` probe imports no module, and row 9 imports by name with the build first on `PSModulePath`, as check 23 asks, and asserts the resolved `ModuleBase` instead.
