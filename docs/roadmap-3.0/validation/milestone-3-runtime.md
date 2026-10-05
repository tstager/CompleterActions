# Milestone 3 runtime validation (WP8, spec section 12)

Run on 2026-10-04 at branch commit `5bc99e2` (`feat/milestone-3-compiled-core`), Windows pwsh 7.6.6 (.NET 10.0.12) on Microsoft Windows 11 Pro 10.0.26300, dotnet SDK 10.0.401, PSReadLine 2.4.5, ripgrep 15.2.0. The 2.2.0 build is `git archive v2.2.0 build` (tag commit `d5767e9`), never the gallery copy; its manifest reports `ModuleVersion` 2.2.0 with no `Prerelease`. The branch build reports `ModuleVersion` 2.2.0 (the release commit has not been made) and loads `CompleterActions.Core.dll` 3.0.0.0. No stamped copy was needed: no check below reads the version string `3.0.0` from the manifest. PS_Completers was read only through a scratch clone at `e4f7d6e` (`master`, 173 `*_completer.ps1` scripts): `git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers`. The clone's `git status --short` was empty after every check.

`<scratch>` is `C:\Users\Trent\AppData\Local\Temp\m3\wp8-scratch`, outside the repository; `<repo>` is the main checkout; `$module` is `<repo>\build\CompleterActions`. Every check ran in its own `pwsh -NoProfile` process and began with section 12's preamble (`Import-Module -Name "$module\CompleterActions.psd1" -Force` and the `ModuleBase` assertion), which printed `ModuleBase OK: ...`. The harness scripts were scratch files and are not committed.

Before the checks, the three run steps passed in separate processes, in order, with no `pwsh` holding the repository build: `Invoke-Build -Task build` (`Build succeeded. 4 tasks, 0 errors, 0 warnings`; `git status --short` empty afterwards, so the committed `build/` was fresh), the two `Invoke-ScriptAnalyzer` calls (no output), and `Invoke-Pester -Path ./tests -CI` with the Stop preamble (`Tests Passed: 644, Failed: 0, Skipped: 8`). CI run 37245495473 on `5bc99e2` is green on all eight legs (Windows and Ubuntu by 7.4, 7.5, 7.6, and preview), each with a successful `Compile` step.

**Isolation.** This machine has CompleterActions 2.0.0, 2.1.0, and 2.2.0 installed under `C:\Users\Trent\OneDrive\Documents\PowerShell\Modules`. In a plain `pwsh -NoProfile` with the preamble, calling a removed name makes command discovery autoload the installed 2.2.0 beside the branch build (row 1 shows the output). Every check below therefore dot-sources a scratch `isolate.ps1` first, which removes from `$env:PSModulePath` each entry that holds a `CompleterActions` folder. The removal affects only module discovery by name; `Import-Module` by path and PSReadLine are unaffected.

## Summary

| Row | Check | Result |
| --- | --- | --- |
| 1 | Checks 1 and 20, surface against the 2.2.0 build | pass |
| 2 | Check 2, public types from the prompt | pass |
| 3 | Check 5, the assembly | pass |
| 4 | Check 6, fresh process, both layouts, re-import | pass |
| 5 | Check 7, no reflection outside the compiled layer | pass |
| 6 | Check 8, grammar parity over 207 scripts | pass |
| 7 | Check 13, deprecated names | pass |
| 8 | Check 15, PSReadLine, live | pass |
| 9 | Check 18, set compatibility both ways | pass |
| 10 | Check 19, local half, PS_Completers suite against the branch build | pass |
| 11 | Section 11 spot checks | pass |

## Row 1: checks 1 and 20, surface

Branch build, isolated (`<scratch>\check1.ps1 -Isolate`):

```text
isolated PSModulePath: 0 CompleterActions copies on PSModulePath
ModuleBase OK: <repo>\build\CompleterActions
Get-Command -Module CompleterActions | Measure-Object : 11
Get-Command -Module CompleterActions -CommandType Alias : 0 items
source FunctionsToExport (11): Export-CompleterSet, Get-Completer, Import-CompleterScript, Import-CompleterSet, New-CompleterScript, Register-Completer, Reset-Completer, Test-CompleterRegistration, Test-CompleterScript, Test-CompleterSet, Unregister-Completer
source AliasesToExport count: 0
built FunctionsToExport (11): (the same 11, in the same order)
built AliasesToExport count: 0
Get-CompleterRegistration : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
Register-CompleterRegistration : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
Unregister-CompleterRegistration : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
Get-CompleterRegistrationLegacy : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
Register-CompleterRegistrationLegacy : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
Unregister-CompleterRegistrationLegacy : System.Management.Automation.CommandNotFoundException / CommandNotFoundException
```

The same script without `-Isolate` printed the same first lines, then:

```text
WARNING: Get-CompleterRegistration is deprecated and will be removed in 3.0; use Get-Completer instead. See about_CompleterActions_Migration.
Get-CompleterRegistration : NO ERROR
Register-CompleterRegistration : System.Management.Automation.ParameterBindingException / MissingMandatoryParameter,Register-CompleterRegistrationLegacy
...
```

`(Get-Command Get-CompleterRegistration).Module.ModuleBase` in that process is `C:\Users\Trent\OneDrive\Documents\PowerShell\Modules\CompleterActions\2.2.0`, and `Get-Module CompleterActions` lists two modules: the branch build and the installed 2.2.0. The branch build exports none of the six names; the installed 2.2.0 was autoloaded beside it.

Surface comparison (`<scratch>\surface.ps1`, once per build, two processes): for each of the 11 functions, `Get-Command` metadata (the default parameter set, the `OutputType` names, the parameter names, and for each parameter set its name, `IsDefault`, and each parameter's `Mandatory`, `ValueFromPipeline`, `ValueFromPipelineByPropertyName`, `Position`, and `ParameterSetName`) serialised to JSON:

```text
branch: functions: 11 aliases: 0 all: 11
2.2.0 : functions: 14 aliases: 3 all: 17
JSON lines: 4831 4831; Compare-Object -CaseSensitive: 0 lines
```

Parameter types were dumped next to the JSON and compared on their own. The one difference is the expected type rename:

```text
Get-Completer -State : CompleterActions.CompleterState[]   (branch)
Get-Completer -State : CompleterState[]                    (2.2.0)
```

Result: **pass**.

## Row 2: check 2, public types

`<scratch>\check2.ps1`: after the preamble, `Register-Completer -LiteralPath <repo>\tests\Fixtures\ImportCompleterScript\ParameterCompleter.ps1 -Lazy` (`Test-CompleterScript` finds nothing in it). The property lists come from `git show 550bde9:tests/CompleterClasses.Tests.ps1` (the `-TestCases` of its first `It`, read from the AST).

```text
Get-Completer | Select-Object -First 1 | ForEach-Object { $_ -is [CompleterActions.CompleterRegistration] } -> True
@(Get-Completer).Count -> 1
[CompleterActions.CompleterRegistration]::new(): properties 18, equal to 550bde9 list in order: True; TypeNames: CompleterActions.CompleterRegistration, System.Object
[CompleterActions.ImportedCompleterRegistration]::new(): properties 16, equal to 550bde9 list in order: True; TypeNames: CompleterActions.ImportedCompleterRegistration, System.Object
[CompleterActions.CompleterScriptFinding]::new(): properties 7, equal to 550bde9 list in order: True; TypeNames: CompleterActions.CompleterScriptFinding, System.Object
[CompleterActions.CompletionMatch]::new(): properties 12, equal to 550bde9 list in order: True; TypeNames: CompleterActions.CompletionMatch, System.Object
[enum]::GetNames([CompleterActions.CompleterState]) -> Active, Stale, Conflicted, Pending, Failed, Discovered
[int][CompleterActions.CompleterState]::Discovered -> 5
[enum]::GetNames([CompleterActions.CompleterType]) -> Native, Parameter
CompleterRegistration string properties (Key, RegistrationKey, RuntimeKey, CommandName, ParameterName, TargetType, Source, ScriptPath, LoadError, ScriptText): each -eq '' True, -eq $null False
ImportedCompleterRegistration string properties: 10, all '' and not null: True
CompleterScriptFinding string properties: 5, all '' and not null: True
CompletionMatch string properties: 8, all '' and not null: True
after $null assignment: ParameterName -eq '' True null False; ScriptPath -eq '' True; LoadError -eq '' True
ImportModule null: True; ScriptBlock null: True
hashtable conversion: x,1,Severity=''
Get-Completer -State Pending -> 1
Get-Completer | Where-Object State -eq 'Pending' -> 1
Get-Completer | Where-Object { $_.State -eq 3 } -> 1
ConvertTo-Json State: {"Key":"test-importedfixturetool:name","State":3}
ConvertTo-Json -EnumsAsStrings State: {"Key":"test-importedfixturetool:name","State":"Pending"}
OutputType: Export-CompleterSet System.IO.FileInfo; Get-Completer CompleterActions.CompleterRegistration; Import-CompleterScript CompleterActions.ImportedCompleterRegistration; Import-CompleterSet CompleterActions.CompleterRegistration; New-CompleterScript System.IO.FileInfo; Register-Completer CompleterActions.CompleterRegistration; Reset-Completer CompleterActions.CompleterRegistration; Test-CompleterRegistration CompleterActions.CompletionMatch; Test-CompleterScript CompleterActions.CompleterScriptFinding; Test-CompleterSet CompleterActions.CompleterScriptFinding; Unregister-Completer CompleterActions.CompleterRegistration
Get-Completer | Format-Table header: Command Parameter Type Source State ScriptPath LoadError
Test-CompleterScript <non-conforming> | Format-Table header: Path Line Column Severity Construct Message Hint
```

The `OutputType` names are the same as the 2.2.0 build's (row 1's JSON comparison includes them). `Get-Completer | Format-Table` and `Get-Completer` render the format file's `CompleterRegistrationTable` columns. The format file's finding view (`CompleterScriptFindingList`) is a list view grouped by `Path`, so `Test-CompleterScript <non-conforming>` renders as `Path:` groups with `Line`, `Column`, `Severity`, `Construct`, `Message`, `Hint`, and `Format-Table` on findings falls back to the property columns. The non-conforming script is `tests\Fixtures\ImportCompleterScript\UnsafeTopLevelScript.ps1`. `<scratch>\format.ps1` rendered `Get-Completer | Format-Table`, `Get-Completer`, `Test-CompleterScript <non-conforming> | Format-Table`, `Test-CompleterScript <non-conforming>`, and `Test-CompleterRegistration` under both builds in two processes. Apart from the `ModuleBase OK` line, the two outputs are identical (`Compare-Object -CaseSensitive` printed nothing). Result: **pass**.

## Row 3: check 5, the assembly

`<scratch>\check5.ps1`:

```text
Test-Path $module\lib\CompleterActions.Core.dll: True
RequiredAssemblies: lib/CompleterActions.Core.dll
PowerShellVersion: 7.4
Test-ModuleManifest: 2.2.0
Assembly Name: CompleterActions.Core Version: 3.0.0.0
Assembly Location: <repo>\build\CompleterActions\lib\CompleterActions.Core.dll
Location under $module: True
FileVersion: 2.2.0 ProductVersion (informational): 2.2.0
Referenced: System.Collections 8.0.0.0; System.Linq 8.0.0.0; System.Management.Automation 7.4.0.0; System.Runtime 8.0.0.0
Get-Command -Module CompleterActions -CommandType Cmdlet: 0 items
CmdletsToExport: 0 items
Public types: CompleterActions.CompleterRegistration, CompleterActions.CompleterScriptFinding, CompleterActions.CompleterState, CompleterActions.CompleterType, CompleterActions.CompletionMatch, CompleterActions.ImportedCompleterRegistration, CompleterActions.Internal.EngineAccess, CompleterActions.Internal.EnginePath, CompleterActions.Internal.GrammarFinding, CompleterActions.Internal.StrictGrammar
Cmdlet subclasses in assembly: 0
git ls-files *.dll *.pdb bin/ obj/ lib/: 0 paths
```

The file and informational versions are 2.2.0 because the `compile` task takes them from the manifest, which the release commit changes. Result: **pass**.

## Row 4: check 6, fresh process, both layouts, re-import

Windows, `<scratch>\check6.ps1`, one fresh process per layout (`<repo>\lib\CompleterActions.Core.dll` was present from the build's `compile` step):

```text
imported <repo>\CompleterActions.psd1
ModuleBase: <repo> expected: True
commands: 11; assembly: <repo>\lib\CompleterActions.Core.dll
Get-Completer runs: 0 records; engine path: Reflection

imported <repo>\build\CompleterActions\CompleterActions.psd1
ModuleBase: <repo>\build\CompleterActions expected: True
commands: 11; assembly: <repo>\build\CompleterActions\lib\CompleterActions.Core.dll
Get-Completer runs: 0 records; engine path: Reflection
```

`Remove-Module` then `Import-Module -Force` in one process (`<scratch>\check5.ps1`, built layout):

```text
after Remove-Module: loaded 0; type literal still resolves: CompleterActions.CompleterRegistration
re-import ModuleBase: <repo>\build\CompleterActions; commands: 11; same assembly instance: True
Get-Completer after re-import runs: Object[]
```

Linux: CI proved it (run 37245495473, both layouts' fresh-process tests on the four Ubuntu legs). Also checked under WSL (Ubuntu, `/snap/bin/pwsh -NoProfile`, pwsh 7.6.5), importing the Windows-compiled assembly through `/mnt/c`. Each layout was imported, then removed and imported again with `-Force` in the same process:

```text
ModuleBase /mnt/c/.../CompleterActions expected True; commands 11; assembly 3.0.0.0; Get-Completer 0
re-import /mnt/c/.../CompleterActions commands 11
ModuleBase /mnt/c/.../CompleterActions/build/CompleterActions expected True; commands 11; assembly 3.0.0.0; Get-Completer 0
re-import /mnt/c/.../CompleterActions/build/CompleterActions commands 11
```

Result: **pass**.

## Row 5: check 7, no reflection outside the compiled layer

```powershell
Select-String -Path src\**\*.ps1 -Pattern 'GetField|GetProperty|BindingFlags|_context'
```

The command printed nothing (70 files matched the path). The same pattern over `Get-ChildItem src -Recurse -Filter *.ps1` (71 files) found no hits either. The three "Runtime capability probe" tests and "throws a clear error when runtime execution context internals are unavailable" passed in the suite run above. Result: **pass**.

## Row 6: check 8, grammar parity

The scaffold outputs were generated once under the branch build (`<scratch>\generate.ps1`, `New-CompleterScript -CommandName <tool> -HelpText (Get-Content <capture> -Raw) -Force` for each `tests\Fixtures\NewCompleterScript\*.txt` that is not `*.names.txt`) into `<scratch>\scaffold`, and both builds tested the same files. Then `<scratch>\parity.ps1` ran once under the 2.2.0 build and once under the branch build, in two processes. For each file it ran `Test-CompleterScript -LiteralPath`, then `Select-Object Path, Line, Column, Severity, Construct, Message, Hint` with `Path` made relative as `<group>/<relative path>`, then `ConvertTo-Csv`:

```text
2.2.0 : files: 207 (ImportCompleterScript 11, LazyRegistration 3, CompleterSet 3, CompleterSetPackage 3, Scaffold 14, PS_Completers 173) findings: 11 exceptions: 0 module: 2.2.0 assembly loaded: False
branch: files: 207 (ImportCompleterScript 11, LazyRegistration 3, CompleterSet 3, CompleterSetPackage 3, Scaffold 14, PS_Completers 173) findings: 11 exceptions: 0 module: 2.2.0 assembly loaded: True
Compare-Object (Get-Content milestone-3-grammar-parity-2.2.0.csv) (Get-Content milestone-3-grammar-parity-3.0.0.csv) -CaseSensitive: (nothing)
bytes equal: True (3511 and 3511 bytes, SHA256 85BF4540BF4806CA42A3E0A74E22FB0787BAAA2C2AB207573B99A550EE84960B)
```

The two CSVs are [milestone-3-grammar-parity-2.2.0.csv](milestone-3-grammar-parity-2.2.0.csv) and [milestone-3-grammar-parity-3.0.0.csv](milestone-3-grammar-parity-3.0.0.csv). The corpus is the 11 import fixtures, the 9 lazy and set fixtures (3 under `LazyRegistration`, 3 under `CompleterSet`, 3 under `CompleterSetPackage`), the 14 scaffold outputs, and the clone's 173 scripts: 207 files. The 11 findings come from the import fixtures; the other 196 files have none under either build. `git diff 550bde9 -- tests/CompleterAuthorTooling.Tests.ps1` prints nothing, and the file passed in the suite run. Result: **pass**.

## Row 7: check 13, deprecated names

```powershell
Select-String -Path src\**\*.ps1, CompleterActions.psm1, CompleterActions.psd1, en-US\*.txt, README.md, .github\copilot-instructions.md, src\docs\CompleterActions\*.md -Pattern 'CompleterRegistrationLegacy|Write-CompleterDeprecationWarning|CompleterDeprecationWarningsIssued|ManagedOnly|DiscoveredOnly'
```

Every hit is in `en-US\about_CompleterActions_Migration.help.txt`:

| Line | Section | Text |
| --- | --- | --- |
| 19 | LONG DESCRIPTION | `three legacy wrappers that carried them, the -ManagedOnly and` |
| 20 | LONG DESCRIPTION | `-DiscoveredOnly switches of the Get wrapper, and the once-per-process` |
| 55 | REMOVED COMMANDS (removal table) | `Get-CompleterRegistrationLegacy` row |
| 56 | REMOVED COMMANDS (removal table) | `Register-CompleterRegistrationLegacy` row |
| 57 | REMOVED COMMANDS (removal table) | `Unregister-CompleterRegistrationLegacy` row |
| 58 | REMOVED COMMANDS (removal table) | `-ManagedOnly` row |
| 60 | REMOVED COMMANDS (removal table) | `-DiscoveredOnly` row |
| 71 | REMOVED COMMANDS | `the aliases had an exported target, and they go with them. -ManagedOnly` |
| 72 | REMOVED COMMANDS | `and -DiscoveredOnly were accepted only by the legacy Get wrapper;` |
| 79 | REMOVED COMMANDS (before block) | `Get-CompleterRegistration -ManagedOnly` |
| 80 | REMOVED COMMANDS (before block) | `Get-CompleterRegistration -DiscoveredOnly` |
| 288 | CHECKLIST FOR A PROFILE | `3. Replace -ManagedOnly with -State Active, Pending, Failed, Stale and` |
| 289 | CHECKLIST FOR A PROFILE | `-DiscoveredOnly with -State Discovered, Conflicted, or with the` |
| 325 | MOVING FROM 1.x | `- One -State filter replaced -ManagedOnly and -DiscoveredOnly, and a` |

`Test-Path` is `False` for `tests/CompleterDeprecation.Tests.ps1` and the three `src/Public/*Legacy.ps1` files. Result: **pass**. The hits fall in four sections of the guide, not only in the removal table and `MOVING FROM 1.x`; see "Notes for the orchestrator".

## Row 8: check 15, PSReadLine, live

One `pwsh -NoProfile` session (`<scratch>\check15.ps1`): `Import-Module PSReadLine`, snapshot, then the module and each step, with a snapshot after each:

```text
PSReadLine: 2.4.5
handlers in snapshot: 196
ModuleBase OK: <repo>\build\CompleterActions
after Import-Module identical: True
Import-CompleterSet -SkipInvalid records: 362 Pending: 362
after Import-CompleterSet identical: True
TabExpansion2('git ch', 6): 8 matches, first: checkout, check-attr, check-ignore; git state before: Pending after: Active
after first tab identical: True
Test-CompleterScript rg_completer.ps1: 0 findings
after Test-CompleterScript identical: True
```

The snapshot is `Get-PSReadLineKeyHandler -Bound -Unbound` as `Key|Function|Group|Description` lines, compared with `-ceq`. The set is `<scratch>\PS_Completers\ps_completers.psd1`. The existing snapshot tests passed in the suite run. Result: **pass**.

## Row 9: check 18, set compatibility both ways

`<scratch>\check18.ps1` ran under each build in its own process: `Import-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1 | Select-Object Key, RuntimeKey, State, Trusted | ConvertTo-Csv`, then `$records | Export-CompleterSet -Path <scratch>\PS_Completers\export-<build>.psd1`. Both exports were written to the clone's root folder, next to its set file.

```text
branch: records: 362 Pending: 362 distinct Key: 362 scripts: 173; exported 66465 bytes, 173 entries
2.2.0 : records: 362 Pending: 362 distinct Key: 362 scripts: 173; exported 66465 bytes, 173 entries
import CSVs byte-identical: True (14536 bytes, 363 lines, SHA256 DDB68852C6B0BAA0CD0084EB746446736BF1CFCE233913B20BBA4EDC66888A9A)
exports byte-identical: True (SHA256 2EF6D0385C6CB5DCF8251EEB7BE7B5E327D21D4C12640653265A53C5FEC94846)
each export is also byte-identical to the clone's committed ps_completers.psd1: True
```

The import CSV is [milestone-3-set-import.csv](milestone-3-set-import.csv); the two builds produced the same file. The two export files were deleted from the clone afterwards, and `git status --short` there was empty. Result: **pass**.

## Row 10: check 19, local half

In `<scratch>\PS_Completers`, one process:

```powershell
pwsh -NoProfile -Command '$env:PSModulePath = "<repo>\build;$env:PSModulePath"; "ModuleBase first: " + (Import-Module CompleterActions -MinimumVersion 2.2.0 -PassThru -ErrorAction Stop).ModuleBase; $r = Invoke-Pester -Path ./tests -Output Detailed -PassThru; "ModuleBase after: " + ((Get-Module CompleterActions).ModuleBase -join ";"); ...'
```

```text
ModuleBase first: <repo>\build\CompleterActions
Pester v6.1.0
...
Tests completed in 18.9s
Tests Passed: 178, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
ModuleBase after: <repo>\build\CompleterActions
```

This run did not use the isolation step. The build folder comes first on `PSModulePath`, so the clone's `Import-Module CompleterActions -MinimumVersion 2.0.0`, `2.1.0`, and `2.2.0` lines all resolved to the branch build, which reports 2.2.0. The PSGallery half runs after the candidate release (release recipe step 9). Result: **pass**.

## Row 11: section 11 spot checks

`<scratch>\spot.ps1` ran once under each build, in two processes, with the repository path and module path written as `<repo>` and `<module>`. Apart from the scaffold's output folder, the two runs had the same inputs. The two outputs are identical (29 lines each; `Compare-Object -CaseSensitive` printed nothing):

```text
== Reset-Completer -Verbose on a lazy Pending registration
VERBOSE: The completer registration 'Test-ImportedFixtureTool:Name' is already pending.
OUT: Test-ImportedFixtureTool:Name Pending Managed
== Reset-Completer -Verbose after first tab (Active)
first tab matches: imported-alpha
state before reset: Active
VERBOSE: Performing the operation "Reset completer registration" on target "Test-ImportedFixtureTool:Name".
OUT: Test-ImportedFixtureTool:Name Pending Managed
== Reset-Completer -Verbose on an eager registration via -InputObject
Reset-Completer: ... Failed to reset the completer 'test-eagernative'. The completer registration 'test-eagernative' was registered from a script block, not a script file, so there is nothing to reload.
Reset-Completer: ... Failed to reset the completer 'Test-EagerTool:Mode'. The completer registration 'Test-EagerTool:Mode' was registered from a script block, not a script file, so there is nothing to reload.
VERBOSE: The completer registration 'Test-ImportedFixtureTool:Name' is already pending.
OUT: Test-ImportedFixtureTool:Name Pending Managed
== New-CompleterScript rg | Test-CompleterScript
PassThru type: System.IO.FileInfo
pipeline findings: 0
== Test-CompleterSet -LiteralPath <clone>\ps_completers.psd1
findings: 0
```

`New-CompleterScript -CommandName rg -Path <scratch>\rg<build>\rg_completer.ps1 -PassThru -Force` probed the installed `rg` (15.2.0) under each build. The two generated files are byte-identical, and `$file | Test-CompleterScript` returned nothing under either build. Result: **pass**.

## Notes for the orchestrator

1. **An installed 2.x copy is autoloaded by a removed name.** Row 1 without isolation: with the branch build imported and CompleterActions 2.2.0 installed on `PSModulePath`, `Get-CompleterRegistration` autoloads the installed 2.2.0 beside the branch build. It then runs the 2.2.0 alias with its deprecation warning, so no `CommandNotFoundException` is raised. `Install-PSResource` installs side by side, so a profile that upgrades to 3.0.0 and keeps 2.x installed can hit this. The migration guide (line 66) says the old name gives `The term '...' is not recognized`, and nothing in it says to remove the 2.x copies. Section 12's run rules do not isolate `PSModulePath`. No row fails, because the branch build exports none of the names. The decision is the owner's: a migration-guide sentence that tells a profile to remove its installed 2.x copies with `Uninstall-PSResource`, or a run rule that isolates `PSModulePath`.
2. **Check 13's parenthetical is narrower than the guide.** Spec section 12 check 13 places the hits in the migration guide's "removal table and its `MOVING FROM 1.x` section". The guide WP6 wrote also names them in `LONG DESCRIPTION` (lines 19 and 20), in the `REMOVED COMMANDS` prose and before block (71, 72, 79, 80), and in `CHECKLIST FOR A PROFILE` (288 and 289). Every hit is in the migration guide, as row 7 lists.
3. **Check 19 needed no stamped copy.** Spec section 12 check 19 says the local half runs "against the stamped branch build"; the plan's WP8 says the branch build needs no stamped copy. The plan was followed. PS_Completers at `e4f7d6e` now also imports with `-MinimumVersion 2.2.0`, which the branch build's 2.2.0 satisfies.
4. **The PS_Completers commit has moved.** Spec section 12 check 18 cites `2c590c6`. The clone is at `e4f7d6e`, and it gives the same 173 entries and 362 registrations.
5. **The finding view is a list view.** Check 2 asks that `Test-CompleterScript <non-conforming> | Format-Table` render "the column headers of `CompleterActions.Format.ps1xml`". The format file has only a list view for findings, so that `Format-Table` shows the property columns. The rendering is identical to 2.2.0's (row 2).
