# Milestone 2 plan: authoring and distribution (2.2.0)

Drafted: 2026-10-02, revised the same day after three reviews (spec coverage and consistency; implementability against the codebase and CI; risk and unattended execution)
Base: main at `5473022` (2.1.0 stable, release commit `2086f7f`, tag v2.1.0)
Spec: `docs/roadmap-3.0/milestone-2-spec.md` (final draft after review, 2026-10-02, amended with this revision as listed under "Departures from the spec"). Section numbers below (§n) point into it.
Roadmap: `docs/roadmap-3.0.md`, milestone 2, locked decisions 3 and 7. Ships first as `v2.2.0-preview1` (PSGallery prerelease label `preview1`), then as `v2.2.0` stable from the same code once the preview has soaked (decision 7, carried forward by §6).
Branch: `feat/milestone-2-authoring-distribution` from main, after this plan and the spec are committed to main.

The plan implements §1 to §8 as written, including the amendments listed under "Departures from the spec", which the spec now carries as behaviour. It treats every open question in §9 as answered by its recommendation until the owner answers it; "Owner decisions by gate" says when each answer is due and which package changes if it goes against the recommendation.

Appendix A (engine cmdlet detection) is out of scope. If the owner answers question 1 against the recommendation, it becomes its own package, WPA, between WP6 and WP9: `src/Bootstrap.ps1`, `Get-CompleterRegistrationSnapshot`, `Find-RuntimeCompleterRegistration`, `Remove-RuntimeCompleterRegistration`, `Get-Completer`, `Unregister-Completer`, and a cmdlet double under `tests/Fixtures/EngineCmdletDouble/`, verified by checks A1 to A3 in place of check 3.

The spec says what the module does. This plan says how the work is split, in what order, which files each package touches, and how each package is accepted. Where the spec leaves an internal choice open, the plan picks one and says so under "Internal design choices".

## Current-state facts the plan builds on

Every fact below was read from the file named, or checked by running the command named, on 2026-10-02.

- **Exports.** `CompleterActions.psm1` dot-sources `src/Private` and `src/Public` and exports every `src/Public/*.ps1` base name. The build sets `FunctionsToExport = $public.BaseName` (`CompleterActions.build.ps1`). The source manifest lists 13 names by hand (`CompleterActions.psd1` lines 75 to 89; the `'Test-CompleterSet'` line is indented four spaces, the others five). `tests/CompleterRegistration.Tests.ps1` "exports the same public functions defined in the manifest and src\Public" (line 15) holds the manifest to `src/Public`, and `tests/CompleterDeprecation.Tests.ps1` line 28 asserts `13`. A new public command therefore needs its file, the manifest line, and the pin in one commit, and no psm1 or build-script change.
- **Help.** The `external_help` task turns `src/docs/CompleterActions/*.md` (PlatyPS 1.0 schema, `Microsoft.PowerShell.PlatyPS` 1.0.3) into `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`; the `build` task depends on `clean` and `external_help` and copies the XML to `build/CompleterActions/en-US/CompleterActions-help.xml`. The about topics live in `en-US/` at the repository root, not under `src/`, and the build copies every `en-US/about_*.help.txt` into `build/CompleterActions/en-US/`. The packaged psm1 replaces comment-based help with `.EXTERNALHELP`, so the comment help in `src/Public/*.ps1` and the markdown are both kept current. The `Markdown_templates` task runs `New-MarkdownCommandHelp -ModuleInfo ... -WithModulePage -Force` and would overwrite every hand-edited markdown file and the module page; it is never run (risk 11). `New-MarkdownCommandHelp -CommandInfo <cmd> -OutputFolder <scratch>` writes `<scratch>\CompleterActions\<Name>.md` with the module's front matter already filled in.
- **Tracked build.** "keeps the tracked build output in sync with the module sources" (`tests/CompleterRegistration.Tests.ps1` line 89) rebuilds into `TestDrive` and compares line by line with `build/CompleterActions`. Every commit that changes `src`, `en-US`, the manifest, or the format file rebuilds and commits `build/`. CI runs Pester before its own build step, against the committed `build/`; locally the build therefore runs first, so the committed copy is current.
- **Test conventions.** Test files import the source manifest in `BeforeEach` with `-Force`, so a re-import discards any shim. Private helpers are shimmed in module scope with `& (Get-Module -Name 'CompleterActions') { function script:<Helper> { ... } }` (`tests/CompleterSet.Tests.ps1` lines 563 to 592, 989, 1045), or through `InModuleScope` (`tests/CompleterActions.Tests.ps1`, 16 uses). Each test file carries its own `Invoke-TestRuntimeCompleterCleanup`. The PSReadLine snapshot idiom is `@(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })` (`tests/CompleterReset.Tests.ps1` line 662, in the `It` at line 654), skipped when PSReadLine is not loaded. Ten test files exist; the suite is 337 tests (roadmap, milestone 1 shipped line), from 247 `It` blocks.
- **`What if:` output.** A `-WhatIf` line goes to the host, not to a stream: `$r = <command> -WhatIf 6>&1` and `*>&1` both left `$r` empty, and a Pester 6.1.0 assertion on it got 0 lines (lens B experiment, 7.6.6 and 7.6.5). The repository's idiom runs the call in a child process and reads its standard output: `@(& pwsh -NoProfile -NoLogo -NonInteractive -File $script:TwinProbePath -Mode WhatIf 2>&1)` (`tests/CompleterActions.Tests.ps1` line 800).
- **Set import (2.1.0).** `Import-CompleterSet` resolves `-Path`/`-LiteralPath`, then per set: `Import-CompleterSetDefinition` (data only; returns `Path`, `Directory`, `Entries`), `Get-CompleterRegistrationSnapshot`, `Resolve-CompleterSetEntry -Entry -Index -SetDirectory [-Verify]` per entry (the static phase), `Resolve-CompleterSetRegistration` (the session phase), the invalid-entry report (`Entry <n> ('<path>'): <message>`, thrown as one error or written as `Completer set '<path>' skipped ...` warnings under `-SkipInvalid`), the per-entry verbose lines and summary, `ShouldProcess` per entry, and one `Add-CompleterRegistration -Snapshot`. Everything is wrapped as `Failed to import completer set. <reason>`. Problems are `@{ Kind; Message }` and only `.Message` is printed. The static phase resolves `[System.IO.Path]::GetFullPath($declaredPath.Replace('\', '/'), $SetDirectory)`, then checks existence and extension in an `if`/`elseif`/`else` chain.
- **Set drift.** `Test-CompleterSet` resolves paths the same way and calls `Get-CompleterSetFinding -SetDefinition -Filter` per set, wrapped as `Failed to test completer set. <reason>`. `Get-CompleterSetFinding` emits each entry's findings inside its entry loop and the `UnlistedScript` findings after it; it keeps only the current `$entry` per iteration and retains no list of resolved entries. Findings are built by `New-CompleterScriptFinding -Path -Extent -Construct -Message -Hint [-Severity]` at extents from `Get-CompleterSetEntryExtent` (`EntriesExtent`; per entry `Extent`, `PathExtent`, `HashExtent`, `TargetsExtent`). No helper returns a line 1, column 1 extent.
- **Grammar and targets.** `Get-CompleterScriptFinding -LiteralPath` parses with `Get-CompleterScriptParseResult` (`[Parser]::ParseFile`), reports parse errors as `ParseError` findings, and otherwise runs `Test-CompleterScriptAst -Ast -LiteralPath`. That is the path `Test-CompleterScript` and `Assert-CompleterScriptConformance` share. No grammar `Message` contains the script's path (`src/Private/Test-CompleterScriptAst.ps1`). `Get-CompleterScriptTarget -LiteralPath [-ParseResult]` derives targets without the grammar.
- **Texts the spec reuses.** `Resolve-CompleterScriptPath` throws `Completer scripts must be .ps1 files. Received '<path>'.` and `Completer scripts must be file paths. '<path>' is a directory.`; `Export-CompleterSet` throws `The directory '<directory>' does not exist.` from `begin`, resolves with `GetUnresolvedProviderPathFromPSPath`, and writes with `Set-Content -Encoding utf8`.
- **Module state.** `src/Bootstrap.ps1` (dot-sourced by the source psm1, appended to the packaged psm1 by the build) runs the capability probe, initialises `Get-CompleterActionState`, two `HashSet` variables, and the three aliases. A new module-state value belongs there.
- **Engine floor.** `PowerShellVersion = '7.0'` (.NET Core 3.1); the lowest CI leg is 7.4. `[System.Text.Encoding]::Latin1` is .NET 5 and must not be used; `[System.Text.Encoding]::GetEncoding(28591)` decodes `63 61 66 82` to `caf` plus U+0082, and `GetEncoding(437)` decodes it to `café` in `pwsh -NoProfile` 7.6.6 on Windows and 7.6.5 under WSL without registering a provider. `TextInfo.OEMCodePage` is 437 on the owner's machine. `[System.IO.Path]::IsPathFullyQualified` (2.1) and the public `ScriptPosition`/`ScriptExtent` constructors work.
- **Parameter binding.** A prototype with the §2 parameter sets bound `'Commands:', '', '  build    Compile' | T fx .\fx.ps1` to the `HelpText` set with all three lines; `$PSCmdlet.ParameterSetName` was already `HelpText` in `begin`. A mandatory `[string[]]` rejects a blank element at binding, before `begin`, unless it carries `[AllowEmptyString()]`.
- **Probe facts on the owner's machine.** All fourteen capture tools of check 4 resolve through `Get-Command -CommandType Application`. `pwsh` resolves to the MSIX path `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.6.0_x64__8wekyb3d8bbwe\pwsh.exe`, which `OpenRead` reads with `Subsystem` 3; `rg` resolves to the WinGet link `...\WinGet\Links\rg.exe` (3); `calc.exe`, `C:\WINDOWS\system32\calc.exe`, reads 2, and `cmd.exe` 3. The offsets hold on calc, pwsh, cmd, and notepad: `e_lfanew` at 0x3C, the `PE\0\0` signature there, magic 0x20B, `Subsystem` at `e_lfanew + 24 + 68`. `[System.IO.File]::OpenRead` on the winget app execution alias throws "The file cannot be accessed by the system", and on a file another handle holds with `FileShare.None` it throws as well. A single `ArgumentList` element `'/c echo x'` reaches `cmd.exe` as `"/c echo x"` and runs `echo x"`, so `-HelpArgument` cannot drive `cmd /c` or `sh -c` cleanly. A child `pwsh` that runs `Start-Process -NoNewWindow ping.exe -ArgumentList '-n','4','127.0.0.1'; exit 0` exited in 316 ms while its standard output stayed open until 3315 ms. `Get-Command -CommandType Application` honours a scratch `PATH` set in the same process, with no stale cache.
- **Package isolation.** On Linux (WSL Ubuntu, `/snap/bin/pwsh`, PSResourceGet 1.2.0), a child started with `XDG_DATA_HOME` pointing at an existing folder wrote `PSResourceGet/PSResourceRepository.xml` there; when the folder did not exist, `GetFolderPath('LocalApplicationData')` returned an empty string. Registering, publishing, saving, and unregistering `CaLocal-<guid>` there left the user's store unchanged. On Windows, a child started with `LOCALAPPDATA` redirected still reported `C:\Users\Trent\AppData\Local` and listed the user's real repositories: .NET reads the known folder, not the variable, so the first draft's redirect does not isolate the Windows store (§8 now says so).
- **PSResourceGet.** `Compress-PSResource` exists from PSResourceGet 1.1.0 (absent from 1.0.0 and 1.0.1; checked by importing each installed version on the owner's machine) and has `-SkipModuleManifestValidate` from 1.1.0. Bundled versions: 7.4.10 and later 1.1.0, 7.5.0 1.1.0, 7.6.0 1.2.0, 7.7.0-preview.5 1.3.0-preview2; CI's 7.4 leg resolves to 7.4.20, so every CI leg has it. With a manifest requiring CompleterActions 2.2.0, which is not installed, `Compress-PSResource` and `Publish-PSResource` fail manifest validation ("RequiredModules entry 'CompleterActions' ... is invalid") and `Save-PSResource` fails ("version range [2.2.0, ) could not be found"). With `Compress-PSResource -SkipModuleManifestValidate`, `Publish-PSResource -SkipModuleManifestValidate -SkipDependenciesCheck`, and `Save-PSResource -SkipDependencyCheck` all three succeed, and the saved layout is `<path>/<Name>/<version>/...`. `Compress-PSResource` fails a folder holding `aaa.psd1` beside `ZzPk.psd1` with "No author was provided in the module manifest"; on Linux the folder's listing order decides which `.psd1` it takes (WSL tmpfs listed in reverse creation order).
- **The owner's PSResourceGet store** holds `PSGallery` and `MyGallery` only. The six repositories the spec's probes left (`CaL`, `CaLocal`, `CaLocal2` to `CaLocal5`) were unregistered by the orchestrator on 2026-10-02. No agent touches the store.
- **CI.** `.github/workflows/ci.yml` runs Lint (`Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` and the same for `./tests`, two calls), then `Invoke-Pester -Path ./tests -CI`, then `Invoke-Build -Task build`, each in a `shell: pwsh` step, which sets `$ErrorActionPreference = 'Stop'`. The matrix is Windows and Ubuntu by 7.4, 7.5, 7.6, and preview (7.4.20 and 7.7.0-preview.5 today). `-CI` writes `testResults.xml`, which `.gitignore` lists. `release.yml` triggers on a tag push and runs `release_check`, Pester, build, `Publish_build`, and the GitHub release with `--prerelease` when the tag has a hyphen.
- **Release shape.** `2086f7f` changed `CHANGELOG.md`, `CompleterActions.psd1`, and `build/CompleterActions/CompleterActions.psd1`; all three are tracked, so `git commit -am` picks them up. The source manifest carries `# Prerelease = ''` between releases.
- **Remote.** `origin` (`https://github.com/tstager/CompleterActions.git`).
- **Benchmark tool.** `tools/Measure-CompleterStartup.ps1` takes `-CompleterRoot` (default: the real PS_Completers folder), `-Iterations` (default 10), `-ModulePath`, and `-BaselineModulePath`, and prints Eager, Baseline, Lazy, and LazyNoHash with `RatioToBaseline`. Its input guard throws unless the module under test writes one `Hash` per entry. Milestone 1's numbers are in `docs/roadmap-3.0/validation/benchmark.md`.
- **PS_Completers at `2c590c6`** (read only). `tests/Completers.Tests.ps1` has the conformance `Describe` (`-MinimumVersion 2.0.0`) and `ps_completers.psd1 matches the repository` (`-MinimumVersion 2.1.0`, `keeps every entry on the strict tier`, `has no drift`). `.github/workflows/conformance.yml` installs CompleterActions with `-Prerelease`. `tools/Export-CompleterSetFile.ps1` has `#Requires` CompleterActions 2.1.0. `ps_completers.psd1` sits at the repository root beside the `*_completer` folders and `docs`, `tests`, and `tools`.
- **This plan and the spec are untracked** on main at `5473022` (`git status`: `?? docs/roadmap-3.0/milestone-2-plan.md`, `?? docs/roadmap-3.0/milestone-2-spec.md`). Until they are committed, `git diff main -- <them>` cannot detect an edit on the branch.

## Internal design choices

1. **The probe runner is a polling loop over `ReadAsync`, in PowerShell.** New private `Invoke-CompleterHelpProcess -FilePath <string> -ArgumentList <string[]> -TimeoutSeconds <double>` starts the process as §2 "The run itself" says, closes standard input, and issues one `BaseStream.ReadAsync($buffer, 0, 65536)` per stream. It then loops on `[System.Threading.Tasks.Task]::WaitAny(<pending reads>, <ms to the next deadline>)`. Each finished read appends to that stream's `MemoryStream` until 1 MiB (1048576 bytes) is held and is discarded after that, then the next read is issued, until both reads return 0. Every step runs on the PowerShell thread; no callback runs PowerShell code. The deadline is fixed at start. When `HasExited` first turns true, a grace deadline of the earlier of 1 s later and the main deadline applies to the reads. It returns `@{ Status; ExitCode; StandardOutput; StandardError; ElapsedMilliseconds; ProcessId; StartError }` with `Status` one of `Exited`, `TimedOut`, `HeldOutput`, `StartFailed`. `ArgumentList` is an array so tests can drive the runner directly; the public command always passes one argument.
   - Rejected: a capped `Stream` subclass compiled with `Add-Type` (188 to 349 ms on first use per §2, and compiled code belongs to 3.0); `BeginOutputReadLine` events (text, not bytes, and handlers on pool threads); `ReadToEndAsync` (no cap, so a chatty tool grows memory until the deadline).
2. **One seam per probe concern.** The probe is split so every test double replaces exactly one helper by name:
   - `Resolve-CompleterHelpProbeApplication -Name <string>`: `Get-Command -Name <name> -CommandType Application -ErrorAction Ignore`, first match; on Windows the PE check. Returns `@{ Name; Path; CanRun; Warning }`, where `Warning` is the §2 not-found or not-run text, or `$null`.
   - `Get-CompleterPESubsystem -LiteralPath <string>`: returns the `Subsystem` value as `[int]`, or `$null` when the header is unreadable. It opens with `[System.IO.File]::OpenRead` and reads at most 4096 bytes. It checks `MZ`, reads `e_lfanew` (Int32 at 0x3C), checks `PE\0\0` there, checks the optional-header magic (0x10B or 0x20B), and reads `Subsystem` (UInt16 at `e_lfanew + 24 + 68`; offset 68 is the same in PE32 and PE32+). It returns `$null` when `e_lfanew + 94` exceeds the bytes read, and catches every exception from opening or reading (an app execution alias, a locked file) and returns `$null`.
   - `Invoke-CompleterHelpProcess` (choice 1): the one helper tests replace to count runs (check 10, `-WhatIf`) and to fake results (check 9, the `/?` rule; check 11, the race).
   - `ConvertFrom-CompleterHelpOutput -Bytes <byte[]>`: the §2 decoding steps 1 to 4 only.
   - `ConvertTo-CompleterCleanHelpText -Text <string>`: the §2 cleaning rules only, shared by the probe and `-HelpText`.
   - `ConvertFrom-CompleterHelpText -Text <string>`: the §2 parser, returning `[pscustomobject] @{ Name; Description }` rows in help order.
   - `Get-CompleterHelpSubcommand -Application <psobject> [-HelpArgument <string>] -TimeoutSeconds <double>`: the orchestration that owns "Choosing the probe" (the `/?` rule), the run-outcome warnings (including the start-failure text), and the probe verbose line. For an application whose `CanRun` is `$false` it runs nothing and returns the application's `Warning`. It returns `@{ Subcommands; Argument; Warnings; VerboseLines }`.

   Rejected: one probe function. It could not be tested on the Ubuntu legs for Windows-only branches without running real Windows tools.
3. **Messages are returned as data and written once.** The helpers return warning and verbose text; only `New-CompleterScript` calls `Write-Warning` and `Write-Verbose`. Unit tests assert the text without capturing streams, and the command's stream tests assert it once more end to end.
4. **The self-check runs on the temporary file.** New private `Save-CompleterScriptFile -Line <string[]> -LiteralPath <string> -ExpectedTarget <string[]> [-Force]` writes `<path>.<8 hex>.tmp` with `Set-Content -Encoding utf8`. It then runs `Get-CompleterScriptFinding -LiteralPath <tmp>` (the exact `Test-CompleterScript` path, parse errors included) and `Get-CompleterScriptTarget -LiteralPath <tmp>`, and compares the derived native `CommandName` list with `-ExpectedTarget` in order, ordinal. On any problem it deletes the temporary file and throws the §2 self-check text. Otherwise it calls `[System.IO.File]::Move(<tmp>, <path>, [bool] $Force)` and returns `Get-Item -LiteralPath <path>`. Without `-Force`, an `IOException` from the move while `<path>` exists becomes step 1's `already exists` text. A `finally` deletes the temporary file if it still exists.
   - §2 steps 6 and 7 now say this order: write the temporary file, check it, move it (departure 5). The only visible difference from checking text is a `.tmp` file in the target folder while the check runs; a failure still leaves nothing at `<path>` and no `.tmp`. No grammar message names the file, so the self-check text is the same.
   - Rejected: `[Parser]::ParseInput` on the composed text, which checks text rather than bytes and needs a hand-built parse-result object.
5. **The probe limit lives in module state.** `src/Bootstrap.ps1` gains `$script:CompleterHelpProbeTimeoutSeconds = 5`. Tests lower it in module scope; the `BeforeEach` re-import restores it. Rejected: a hidden parameter, which §2 rules out.
6. **One module resolver for both commands.** New private `Resolve-CompleterSetModule -Name <string>` implements §3 "Resolution" steps 1 to 6 with `[System.IO.Directory]::EnumerateDirectories` and `Import-PowerShellDataFile`, never `Get-Module`. It returns `@{ Name; Version; ModuleBase; ManifestPath; Manifest; SetPath }`, where `Name` is the installed folder's spelling, `ModuleBase` is `[System.IO.Path]::GetFullPath` of the chosen folder, and `Version` is the display text (`ModuleVersion`, plus `-<Prerelease>` when set). On failure it throws the bare §3 reason text, which `Import-CompleterSet` and `Test-CompleterSet` wrap with their own prefix. The wildcard check runs in each caller before resolution, because its text names the caller.
7. **Containment is a static-phase problem.** `Resolve-CompleterSetEntry` gains optional `-ModuleName <string>` and `-ModuleBase <string>`. When `-ModuleBase` is given, the resolved path is tested right after `GetFullPath` and before the existence check, as a new first branch of the existing `if`/`elseif`/`else` chain: compare with `ModuleBase` plus a trailing separator, `OrdinalIgnoreCase` when `$IsWindows -or $IsMacOS`, `Ordinal` on Linux. An outside path adds `@{ Kind = 'OutsideModule'; Message = "the script '<path>' is outside the module '<Name>' at '<ModuleBase>'" }` and is not stat'ed, read, or hashed. The problem then flows through the existing invalid-entry path unchanged. Without the parameters nothing changes, so `-Path`, `-LiteralPath`, and `Test-CompleterSet` (which never passes them) behave as in 2.1.0. Rejected: filtering in `Import-CompleterSet` after the static phase, which would duplicate the invalid-entry report and hash an outside file first.
8. **`Import-CompleterSet` resolves a list of sets, then runs the 2.1.0 body.** The `process` block first builds `@(@{ SetPath; Module })` for the bound set (`Module = $null` for `-Path` and `-LiteralPath`), resolving every `-Name` before any import (§3). The per-set body is moved, not rewritten. Under `-Name` it adds, in this order, the module verbose line, the trusted-entry warning (counted from the definition's raw entries whose `Trusted` is `[bool] $true`, written after `Import-CompleterSetDefinition` and before entry resolution), and `-ModuleName`/`-ModuleBase` on each `Resolve-CompleterSetEntry` call.
9. **Package findings are one helper behind an optional parameter.** New private `Get-CompleterSetPackage -SetPath <string> [-Module <psobject>]` returns `@{ Name; ManifestPath; ModuleBase; Manifest }` or `$null`. Under `-Name` it uses the module record. For a path, it lists `*.psd1` in the set folder's parent in ordinal order and takes the first that reads as data and whose `PrivateData.CompleterSet` resolves to the set file; a parent that cannot be listed gives `$null`. New private `Get-CompleterSetPackageFinding -SetDefinition -Package -Entry` builds the three §3 rows. `Get-CompleterSetFinding` gains optional `-Package` and a `List[object]` of resolved entries, filled inside its entry loop; after the loop and before the `UnlistedScript` scan it passes that list to `Get-CompleterSetPackageFinding`. The line 1, column 1 extent is built with `[ScriptExtent]::new($position, $position)` over `[ScriptPosition]::new(<set path>, 1, 1, <line 1 text>)`, so `Get-CompleterSetEntryExtent` is not changed.
10. **Package tests pack everywhere and install only where the store is isolated** (§8 "Package isolation", question 14). Every package test carries `-Skip:(-not (Get-Command Compress-PSResource -ErrorAction Ignore))` with the reason `PSResourceGet 1.1.0 or later is required`. No test matches PSResourceGet's own message text; the preview leg bundles a 1.3.0 preview.
    - **Pack.** `Compress-PSResource -Path <package> -DestinationPath <TestDrive folder> -SkipModuleManifestValidate` builds the `.nupkg` on every leg; it needs no repository and exercises the one-`.psd1` rule.
    - **Register, publish, save.** These run in a child `pwsh -NoProfile` started with a unique repository name, `CaLocal-<8 hex>`, `Unregister-PSResourceRepository -Name <that name>` in `finally`, and an assertion in the test that `Get-PSResourceRepository` names are the same before and after. The child runs `Register-PSResourceRepository -Name <name> -Uri <TestDrive repo> -Trusted`, `Publish-PSResource -Path <package> -Repository <name> -SkipModuleManifestValidate -SkipDependenciesCheck`, and `Save-PSResource -Name <package name> -Repository <name> -Path <TestDrive modules> -SkipDependencyCheck`. All three skip flags are required: without them every fixture that requires CompleterActions 2.2.0 fails on a machine without 2.2.0, which is every machine until the release. The child runs:
      - on Linux and macOS, with `XDG_DATA_HOME` set to a folder created in `TestDrive` before the child starts (verified);
      - on Windows only when `$env:GITHUB_ACTIONS -eq 'true'`, where the runner's store is disposable. Everywhere else on Windows the step is skipped with the reason `the PSResourceGet store cannot be redirected on Windows`.
    - **Side effects.** On a Windows CI runner, a job killed between register and `finally` leaves one runner-store entry, which dies with the runner. On the owner's machine the step is skipped, so the store is never written. `$env:GITHUB_ACTIONS -eq 'true'` is the only switch: no local override, no environment variable of the module's own, and no parameter. Forbidden: any change that lets the register step run on a developer's Windows machine.

    The import side of check 2 then runs against the saved folder, prepended to `$env:PSModulePath` in the test's own process only and restored in `finally`.
11. **Four new test files, split so parallel packages do not share one at the same time.** `tests/CompleterHelpProbe.Tests.ps1` (WP1, then WP4a), `tests/CompleterHelpText.Tests.ps1` (WP2), `tests/CompleterScaffold.Tests.ps1` (WP3, then WP4b), and `tests/CompleterSetPackage.Tests.ps1` (WP5, then WP6, then WP7). Fixtures go under `tests/Fixtures/NewCompleterScript/` and `tests/Fixtures/CompleterSetPackage/`. Inputs with NUL, lone CR, or binary headers are built in code at test time, never checked in.

## Departures from the spec

Each item below is a place where the first draft of the spec was silent, wrong, or looser than this plan. The spec now carries each one as behaviour, at the line given (line numbers of the amended spec). Item 1 also carries an owner question, §9 question 14; the others are gap-fills the owner accepts with this plan and the spec.

1. **Windows PSResourceGet isolation.** Plan: choice 10, lines 65 and 69. Spec: §8 "Package isolation", lines 613 to 615; question 14, line 794. Text: "on Windows the register, publish, and save steps run only when `$env:GITHUB_ACTIONS` is `true`, where the runner's store is disposable, and are skipped everywhere else with the reason `the PSResourceGet store cannot be redirected on Windows`". The first draft redirected `$env:LOCALAPPDATA`, which leaves the real store in use. The repository name becomes `CaLocal-<8 hex>` (spec check 2, line 640).
2. **PSResourceGet flags and version floor.** Plan: choice 10, lines 65 and 66. Spec: §8, lines 616 and 617. Text: "`Compress-PSResource -SkipModuleManifestValidate` builds the `.nupkg` on every leg" and "A check skips with the reason `PSResourceGet 1.1.0 or later is required` where `Compress-PSResource` is missing". The first draft named the `Publish-PSResource` and `Save-PSResource` flags only.
3. **The PE reader's magic check and the other-subsystem reason.** Plan: choice 2 and WP1, lines 48 and 137. Spec: §2 "What 'read safely' means", lines 161 to 163. Text: "checks the optional-header magic (`0x10B` for PE32, `0x20B` for PE32+)" and "`it is not a Windows console program (subsystem <n>)` when `Subsystem` is any value other than 2 or 3". The first draft gave no reason for subsystems other than 2 and 3.
4. **The extension in the not-run reason is lower-cased.** Plan: WP1, line 137. Spec: line 164. Text: "`<ext>` is the extension with its dot, in lower case ... a file named `TOOL.BAT` gives `it is a .bat file`".
5. **The self-check reads the temporary file (§2 steps 6 and 7).** Plan: choice 4, line 57. Spec: lines 121 and 122. Text: "Write the composed text to `<path>.<random>.tmp` in the same directory ... then parse that file" and "Move the checked temporary file of step 6 into place". Not observable except for the `.tmp` file during the check.
6. **The self-check tail for a target mismatch.** Plan: WP3, line 246. Spec: line 121. Text: "`<detail>` is the first finding's `Message`, or, when there is no finding and the targets differ, `The script registers <derived list>, not <expected list>.`, each list written as the registration line writes it (`'rg', 'rg.exe'`)".
7. **`<Name>` spelling in `-Name` messages.** Plan: choice 6 and WP5, lines 61 and 391. Spec: §3, line 417. Text: "`<Name>` in the not-found reason is the value as given ... Everywhere else ... `<Name>` is the installed module folder's spelling, so `-Name cafixtureset` reports `CaFixtureSet`."
8. **Trusted-entry warning order.** Plan: choice 8, line 63. Spec: line 422. Text: "The warning is written after the set file is read and before its entries are validated, so a set that then fails still announces its trusted entries."
9. **Containment before existence.** Plan: choice 7, line 62. Spec: line 421. Text: "an entry outside the module gets this problem and no other, whether or not its file exists, and the file is never opened, read, or hashed."
10. **Wildcard texts and their wrapping.** Plan: WP5 and WP6, lines 388 and 438. Spec: lines 392 and 440. Text: "`Failed to import completer set. Import-CompleterSet -Name does not accept wildcards. Received '<name>'.`" and "`Failed to test completer set. Test-CompleterSet -Name does not accept wildcards. Received '<name>'.`", each before any value is resolved. The first draft gave the `Import-CompleterSet` text unwrapped and no `Test-CompleterSet` text.
11. **Which manifest, and the order of `PackageLayout` rows.** Plan: choice 9 and WP6, lines 64 and 446. Spec: lines 442 and 452. Text: "When more than one `.psd1` in that folder declares the set, the first in ordinal order of file name is the manifest." and "The second row gives one finding per extra `.psd1`, in ordinal order of file name."
12. **`.github/copilot-instructions.md`.** Plan: WP7, line 493. Spec: §4, line 541. Text: "'ten commands' becomes 'eleven commands', with `New-CompleterScript` added to the list, and both 'thirteen functions' mentions become 'fourteen functions'."
13. **A patched GUI copy of `cmd.exe` replaces `calc.exe` in checks 9 and 10.** Plan: WP1 and WP4b, lines 146 and 346. Spec: lines 678 and 682. Text: "a copy of `cmd.exe` written to the test drive with its `Subsystem` field set to 2 reads as 2. The patched copy replaces `calc.exe`, which a runner image need not have."
14. **The OEM decoding expectation is locale-independent (check 7).** Plan: WP2, line 206. Spec: line 670. Text: "decode on Windows exactly as `[System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)` decodes them, which is `café` under code page 437".
15. **The `-WhatIf` check runs in a child process (check 10).** Plan: WP4b, line 336. Spec: line 685. Text: "The call runs in a child `pwsh -NoProfile -File`, because the `What if:` line goes to the host and cannot be captured in the calling process."
16. **The local Pester gate is CI's form (check 22).** Plan: "Rules for every package", line 110. Spec: line 744. Text: "`pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes locally".
17. **Check 15's installed copy.** Plan: WP6, line 453. Spec: line 719. Text: "`Test-CompleterSet -Name CaFixtureSet` returns nothing on an installed copy: a package folder in a scratch module root on every leg, and the copy check 2 saved, where check 2's save step runs." The first draft named only check 2's copy, which the owner's Windows machine skips.

Not departures: the empty `-CommandName` element is not tested, because binding rejects it before `begin` (fact "Parameter binding") and check 11 does not list it; the plan adds no `[AllowEmptyString()]` to `-CommandName`.

## Work packages

### Rules for every package

These rules go verbatim into every implementer and validator prompt. Reviewers check each one.

- **Documents.** Implementers never edit `docs/roadmap-3.0.md` (its criteria, its status lines, or anything else), `docs/roadmap-3.0/milestone-2-spec.md`, or `docs/roadmap-3.0/milestone-2-plan.md`, and never restate a roadmap exit criterion anywhere: not in the docs, the CHANGELOG, the pull request, or a commit message. A spec or plan defect is reported to the orchestrator, not fixed. The milestone 1 retrospective recorded an agent restating a criterion without sign-off. Gate, in every package review: `git diff main -- docs/roadmap-3.0.md docs/roadmap-3.0/milestone-2-spec.md docs/roadmap-3.0/milestone-2-plan.md` prints nothing. The gate is meaningful only because this plan and the spec are committed to main before the branch is cut (fact "This plan and the spec are untracked"). §6's "Roadmap edits the owner would make" and the release status lines are the owner's.
- **Worktrees and merges.** Each package runs in its own git worktree, on its own branch `m2/<wp>` (for example `m2/wp4a`) cut from `feat/milestone-2-authoring-distribution` after the packages it depends on are merged there. The orchestrator merges into the feature branch, each when it is accepted, in this order: WP1, WP3, WP5, WP2 code, WP2 corpus, WP4a, WP6, WP4b, WP7. WP8 and WP9 commit their validation files on the feature branch itself. After each merge the orchestrator discards both sides of any conflict in `build/` and in `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml` (`git checkout --ours -- build src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`), re-runs `pwsh -NoProfile -Command "Invoke-Build -Task build"`, and commits the result as `chore(build): rebuild after merging <wp>`. A conflict anywhere else goes back to the later package. WP1 owns `src/Bootstrap.ps1`; no other package edits it. The build script takes the module name from its folder leaf, so a worktree must be reached through a junction named `CompleterActions`, and `git -c core.longpaths=true worktree add` is needed under the scratchpad.
- **Run steps.** Invoke-Build, PSScriptAnalyzer, and Pester are three separate processes, in this order. Never run Pester in the same process as Invoke-Build or PSScriptAnalyzer: both register completers, and that breaks the paging tests.
  1. `pwsh -NoProfile -Command "Invoke-Build -Task build"`. The build comes first locally because the tracked-build test compares a fresh build with the committed `build/` (CI can lint and test first only because its `build/` is already committed).
  2. `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"` prints nothing. These are CI's two Lint calls; a single call over both paths is not equivalent. `./tests` includes the `.ps1` files under `tests/Fixtures/`.
  3. `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes. This is CI's Test step under `shell: pwsh` and every package's final gate; `testResults.xml` is ignored by git.

  During work an implementer may run only the package's own test file, `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests/<File>.Tests.ps1 -Output Detailed'`, after step 1. Reviewers run the three steps above, in order, on the package branch.
- **Linux.** Every package's tests pass locally on Windows. Linux is proven either under WSL (`/snap/bin/pwsh -NoProfile`, same three steps) or by the first CI run. The orchestrator may push the feature branch and open a draft pull request early to get the Ubuntu legs; a draft is not the WP11 pull request. The package's review note records which of the two proved Linux.
- **Commits.** Conventional commits with a parenthesised scope and an imperative summary: `feat(probe): ...`, `feat(scaffold): ...`, `feat(sets): ...`, `test(probe): ...`, `test(scaffold): ...`, `test(sets): ...`, `docs(help): ...`, `chore(build): ...`, `chore(release): ...`. Each commit message ends with exactly one trailer line: the `Co-Authored-By:` line the harness provides (in the session that reviewed this plan, `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`), and nothing else. No `Claude-Session` trailer, no second `Co-Authored-By`. The branch carries one distinct trailer line: every package uses the line of the feature branch's first commit. Pre-PR check, in `pwsh -NoProfile`:

  ```powershell
  git log main..HEAD --format=%B | Select-String -Pattern '^Co-Authored-By:' | ForEach-Object Line | Sort-Object -Unique   # exactly one line
  @(git log main..HEAD --format=%B | Select-String -Pattern 'Claude-Session').Count                                      # 0
  ```
- **Files.** Commit `build/` and the regenerated help XML with the source change they come from. Keep CR LF and UTF-8 without a BOM in every edited text file. No scratch file in the repository.
- **Tests.** Every test that reads the error stream passes `-ErrorAction Continue` to the command under test, because CI runs Pester with `$ErrorActionPreference = 'Stop'`. Any test that changes `$env:PATH` or `$env:PSModulePath` restores it in `finally`. No test reads or writes the real PS_Completers repository. Every platform skip uses `-Skip:` or `Set-ItResult -Skipped -Because '<reason>'` with the reason given in this plan, word for word.
- **Unchanged files.** Where a package says a file is unchanged, its gate is `git diff main -- <file>` printing nothing.

### WP1 Probe process mechanics (private)

Owns §2 "What 'read safely' means" for resolution, the PE check and its four reasons, the start-failure status, the run, and the deadline mechanics. The start-failure warning text, the run-outcome warnings, and the verbose line are WP4a's. Decoding and cleaning are WP2's.

Day one. No dependency.

Files:
- new `src/Private/Resolve-CompleterHelpProbeApplication.ps1`, `Get-CompleterPESubsystem.ps1`, and `Invoke-CompleterHelpProcess.ps1` (choices 1 and 2);
- `src/Bootstrap.ps1` (choice 5);
- new `tests/CompleterHelpProbe.Tests.ps1` (`Describe 'Help probe process helpers'`);
- `build/`.

Details:
- **Resolution.** On Windows, a `.exe` (`OrdinalIgnoreCase`) whose subsystem is 3 is runnable. Subsystem 2 gives `it is a Windows GUI program`; any other value gives `it is not a Windows console program (subsystem <n>)`; `$null` gives `its program header could not be read`; any other extension gives `it is a <ext> file, which only runs through cmd.exe`, with `<ext>` the extension with its dot, lower-cased (`.cmd`, `.bat`). On Linux and macOS every resolved application is runnable.
- **Runner.** `UseShellExecute = $false`, `CreateNoWindow = $true`, `RedirectStandardInput/Output/Error = $true`, `WorkingDirectory = [System.IO.Path]::GetTempPath()`, `Environment['NO_COLOR'] = '1'`, and arguments through `ArgumentList`. On timeout: `Kill($true)`, then `WaitForExit(int)` up to 1 s, output dropped, `Status = 'TimedOut'`. On held output: dispose the streams, try `Kill($true)` and ignore any failure, `Status = 'HeldOutput'`. A `Process.Start` exception gives `Status = 'StartFailed'` with `StartError = $_.Exception.Message`.
- **Floor.** No .NET 5+ API: no `Encoding.Latin1`, `WaitForExitAsync`, `Convert.ToHexString`, or `File.SetUnixFileMode` in `src`.

Test helpers in the file: `New-TestPEFile -Path -Subsystem [-Magic] [-Truncate]` writes a minimal header with `[System.IO.File]::WriteAllBytes`; `New-TestPatchedExe -Path -Subsystem` copies `$env:ComSpec` and rewrites the UInt16 at `e_lfanew + 92`.

Tests (`tests/CompleterHelpProbe.Tests.ps1`, `Describe 'Help probe process helpers'`, every helper called in module scope):
- `reads the PE subsystem of <Case>` (9; check 9): zero bytes, truncated header, wrong `MZ`, wrong `PE` signature, wrong optional-header magic, `e_lfanew` beyond the bytes read (all `$null`), subsystem 1, 2, and 3
- `returns $null for a file that cannot be opened` (Windows: a file held with `FileShare.None` by the test; Linux: a file with mode 000, skipped with the reason `root ignores file modes` when `id -u` prints 0)
- `reads pwsh.exe as 3 and a cmd.exe copy patched to subsystem 2 as 2` (check 9; skipped off Windows with the reason `PE subsystems are read on Windows only`)
- `resolves only applications, never a function or alias named like the command` (check 10)
- `returns the not-found warning without throwing when ErrorActionPreference is Stop` (check 10)
- `refuses <Case> on Windows with its reason` (5; check 10): the patched GUI copy, a `.cmd` file, a file named `TOOL.BAT` (reason `it is a .bat file`), a zero-byte `.exe` (unreadable), a subsystem 1 `.exe`; each on a scratch `PATH`; skipped off Windows with the reason `the PE and extension checks apply on Windows only`
- `treats every resolved application as runnable on Linux and macOS` (an executable `#!/bin/sh` file on a scratch `PATH`; skipped on Windows with the reason `Linux and macOS run any resolved application`)
- `returns Exited with both streams and the exit code` (a `pwsh -NoProfile -File` fixture written to `TestDrive` that writes known bytes to both streams and exits 3)
- `closes standard input so a program that reads it sees end of file`
- `runs in the temporary directory with NO_COLOR set`
- `keeps the first MiB of a stream and drains the rest`
- `returns TimedOut and kills the process at the deadline`
- `returns HeldOutput when a descendant keeps the output open after the parent exits` (Windows: the fixture runs `Start-Process -NoNewWindow ping.exe -ArgumentList '-n','15','127.0.0.1' -PassThru` and writes the child's id to `TestDrive`; `ping.exe` is in `System32` on every Windows image. Linux: an executable `#!/bin/sh` file running `sleep 30 & echo $! > <file>; exit 0`. `AfterEach` stops the recorded id.)
- `leaves no held-output descendant running after cleanup` (runs after the previous `It`; asserts `Get-Process -Id <recorded id> -ErrorAction Ignore` returns nothing)
- `returns StartFailed with the exception message for a file the loader rejects` (Windows: a synthetic console header the loader rejects; Linux: a file on a scratch `PATH` without the execute bit)

Review focus: the loop never blocks on a read without a deadline; the cap counts bytes, not reads; no .NET 5+ API; no `Write-Warning` or `Write-Verbose` in these helpers; the PE reader never throws.

Done when: the three run steps pass, Linux proven as the rules say.

### WP2 Help text: decoding, cleaning, parsing, and the fixture corpus

Owns §2 "Parsing the subcommand table", the decoding and cleaning parts of §2 "What 'read safely' means", check 7, and the check 4 corpus.

The decoder and the cleaner moved here from WP1. They are pure functions over bytes and text, tested with the same inline inputs as the parser, and the parser tests run every capture through the cleaner first. With them here, WP1 is the process package and WP2 is the text package, and the only WP1 dependency left in WP2 is the runner the captures use.

WP2 lands in two merges. **WP2 code** (the three helpers and their unit tests) starts on day one. **WP2 corpus** (captures, expected lists, and the 14 fixture tests) needs WP1's runner, so it starts after WP1 is merged.

Files:
- new `src/Private/ConvertFrom-CompleterHelpOutput.ps1`, `ConvertTo-CompleterCleanHelpText.ps1`, and `ConvertFrom-CompleterHelpText.ps1` (choice 2);
- new `tests/Fixtures/NewCompleterScript/` (corpus merge):
  - `<tool>.txt` for each of the 14 tools in check 4, holding the decoded, uncleaned text;
  - `<tool>.names.txt`, the expected names, one per line, empty for `git`, `rg`, and `schtasks`;
  - `CAPTURES.md`, one row per tool: the version line (`<tool> --version` or the tool's own form), the capture command, the date, the expected count, the §2 table count, and a note for any difference;
- new `tests/CompleterHelpText.Tests.ps1`;
- `build/`.

Details:
- **Decoder.** UTF-16 LE when the bytes start `FF FE`, or when a lenient UTF-8 decode contains U+0000. Otherwise strict UTF-8 with `[System.Text.UTF8Encoding]::new($false, $true)`, after skipping `EF BB BF`. Then, on Windows, `[System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)`, and on Linux and macOS `GetEncoding(28591)`. A leading U+FEFF is removed last.
- **Cleaner.** In this order: CSI `\e\[[0-9;?]*[ -/]*[@-~]`; OSC `\e\][^\a\e]*(?:\a|\e\\)`; other two-character escapes `\e[@-_]`; backspace overstrikes (`[^\x08]\x08` repeated until stable, then any remaining `\x08`); CR LF to LF; then each line keeps only the text after its last CR.
- **Parser shape** (a starting point; the corpus is the arbiter, and reviewers judge the parser by the 14 fixtures and the rule examples, not by regex shape):
  - Header: `^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$`, accepted when one word with `(`, `)`, and `,` trimmed is `command`, `commands`, `subcommand`, or `subcommands` (`OrdinalIgnoreCase`). The header test runs before the entry test on every line.
  - Entry: `^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$`. The `\s*:` branch covers `a : Add`.
  - Indentation is the length of the leading whitespace in characters; a tab counts as one.
  - Rules 2, 4, and 5 apply as written. Rule 5's replacement covers `\p{Cc}`, `\p{Cf}`, `\p{Zl}`, and `\p{Zp}`.

Capturing (a scratch script outside the repository, never committed). Captures are made on the owner's machine, where all 14 tools resolve (fact "Probe facts"). If any tool is missing when the implementer runs, the implementer reports the missing list and stops that tool's capture; a capture is never invented or written by hand. Import the branch build by full path. Then, for each tool except `winget`, call `Invoke-CompleterHelpProcess` with the tool's resolved path and the check 4 argument (`/?` for `bcdedit` and `schtasks`, `--help` otherwise). Write `ConvertFrom-CompleterHelpOutput` of the stream that §2 would use to `<tool>.txt` with `Set-Content -Encoding utf8`, without cleaning, so the fixture is exactly what `-HelpText` would receive. `winget` is an app execution alias that the probe refuses, so it is captured as §2 example 2 does: `winget --help | Set-Content -Encoding utf8 .\winget.txt`. `CAPTURES.md` records each command as run.

The spec's appendix B reproduces the PS_Completers counts only; it holds no capture commands. The commands above are this plan's.

Expected lists:
- `<tool>.names.txt` is written by hand from reading `<tool>.txt`, before the parser is run on it, and not by copying parser output. A second reader reviews each list against its capture.
- The parser is then run, and any difference is resolved by reading the help again.
- The count is compared with the §2 table (`cargo` 16, `docker` 65, `gh` 34, `go` 19, `7z` 11, `sc` 35, `bcdedit` 20, `rustup` 17, `pip` 18, `kubectl` 43, `winget` 19, `git`, `rg`, and `schtasks` 0).

**WP2 corpus ends in one of two states.**
- **State A.** Every count matches §2, or differs only because the tool is newer than the 2026-10-02 capture, with the version difference recorded in `CAPTURES.md`. The reviewers, not the owner, accept version-drift notes. WP4b may start.
- **State B.** A difference is caused by the rules (a name the rules miss or invent against the hand-written list, on the same tool version). The implementer stops, writes the difference to `CAPTURES.md`, and reports it. The orchestrator asks the owner for a spec amendment (§8 "Fixture provenance"); WP4b waits for the answer. WP4a and every other package carry on, because they use only the WP2 code merge.

Tests (`tests/CompleterHelpText.Tests.ps1`, `Describe 'Help text decoding, cleaning, and parsing'`, in module scope):
- `decodes UTF-16 LE without and with a byte-order mark to the same text` (check 7)
- `drops a UTF-8 byte-order mark` (check 7)
- `decodes the bytes 63 61 66 82 with the OEM code page on Windows and Latin-1 elsewhere` (check 7). On Windows the expectation is `[System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString([byte[]] (0x63, 0x61, 0x66, 0x82))`, computed in the test, so the assertion holds under any locale; on a 437 machine that is `café`. Elsewhere it is `"caf$([char] 0x82)"`.
- `removes a leading U+FEFF that a decoder leaves`
- `cleans <Case>` (6): CSI colour, OSC 8 hyperlink (only the link text remains, check 7), two-character escape, backspace overstrike, CR LF, CR progress line
- `parses the <Tool> capture to exactly its expected names in order` (14; check 4; corpus merge). Each capture is read with `Get-Content -LiteralPath <file> -Raw`, because plain `Get-Content` splits on a lone CR and alters the text before the cleaner sees it, then goes through `ConvertTo-CompleterCleanHelpText` first, as the command does.
- `matches the header <Line>` (10: the §2 rule 1 examples)
- `does not match <Line> as a header` (3: git's nine-word line, `Parameter List:`, `Options:`)
- `skips <Line> after a header` (3; rule 2: a blank line, `=======`, `-------`)
- `reads an entry with the separator <Case>` (5: `: `, `-----`, ` - `, two spaces, tab)
- `drops a trailing star and comma-separated aliases from a name`
- `skips deeper continuation lines and wrapped or unknown lines without ending the section`
- `ends a section at <Case>` (3: blank line, header, shallower entry)
- `keeps names in help order and drops case-insensitive duplicates`
- `replaces control, format, and separator characters in a description and uses the name for an empty one`
- `returns no rows for help without a commands section`

Review focus: no `Write-*` in these helpers; `CAPTURES.md` complete; every expected list reviewed by a second reader against its capture.

Done when: WP2 code: the three run steps pass with the unit tests. WP2 corpus: the 14 fixture tests pass on both OS legs and the corpus is in state A, or the state B report has gone to the orchestrator.

### WP3 Names, skeleton, self-check, and atomic write

Owns §2 "Target list", "Names in the generated script", "Skeleton", and "Encoding and line endings", and the self-check and write mechanics of "Order of work" steps 6 and 7 (choice 4).

Day one. No dependency.

Scope: WP3 never creates the public command and never touches the manifest; those are WP4b's.

Files:
- new `src/Private/ConvertTo-CompleterTargetName.ps1`: `-CommandName <string[]>` returns the target list, or throws the §2 command-name text for the first invalid name;
- new `src/Private/ConvertTo-CompleterScriptStem.ps1`: `-Name <string>` returns the stem;
- new `src/Private/ConvertTo-CompleterSingleQuotedText.ps1`: `-Value <string>` doubles U+0027, U+2018, U+2019, U+201A, and U+201B;
- new `src/Private/Get-CompleterScriptSkeleton.ps1`: `-Name <string> -Stem <string> -Target <string[]> -Subcommand <object[]> [-SeedKind Probe|HelpText] [-ProbeArgument <string>]` returns the skeleton lines. A `Get` verb keeps it clear of `PSUseShouldProcessForStateChangingFunctions`;
- new `src/Private/Save-CompleterScriptFile.ps1` (choice 4);
- new `tests/CompleterScaffold.Tests.ps1` (`Describe 'Completer script skeleton'`);
- `build/`.

Details:
- **Line 1** is `# <Name> tab completion for PowerShell` with the primary name as given.
- **Line 2.** `-SeedKind Probe` with `-ProbeArgument` gives `... read from '<Name> <Arg>' when the script was generated.`; `HelpText` gives `... read from help text passed to New-CompleterScript.`; an empty `-Subcommand` gives the skeleton line, whatever the seed kind.
- **Literal output.** The text is the §2 block character for character, with `Subcommands = @()` when the table is empty and one `@{ Name = '...'; Description = '...' }` row per entry at 12 spaces.
- **Self-check text.** `New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. <detail>`, where `<detail>` is the first finding's `Message`, or, for a target mismatch with no finding, `The script registers <derived list>, not <expected list>.` with each list in the registration line's form (`'rg', 'rg.exe'`) (§2 step 6).
- **`already exists` text.** `The file '<path>' already exists. Use -Force to overwrite it.` is thrown here (the move) and by WP4b's step 1. The tests of both packages compare against one format string kept at the top of `tests/CompleterScaffold.Tests.ps1`, so the two texts cannot drift apart.

Tests (`tests/CompleterScaffold.Tests.ps1`, `Describe 'Completer script skeleton'`, in module scope):
- `builds the target list <Expected> from <CommandName>` (9: `rg`; `rg, rg.exe`; `python3.12`; `npm.cmd`; `rg.exe`; `RG, rg`; `tool.COM`; `x.bat`; `y.ps1`)
- `rejects the command name <Name>` (9: `_`, `__`, `foo.`, `-x`, `a b`, `C:\tools\rg`, `rg*`, `.x`, `x-`)
- `derives the stem <Stem> from <Name>` (10: `rg`, `rg.exe`, `cargo-binstall`, `oh-my-posh`, `DSC`, `7z`, `npm.cmd`, `TOOL.BAT`, `x.ps1`, `y.com`)
- `doubles every single-quote character the tokenizer accepts`
- `writes line 1 with the primary name as given for rg.exe`
- `writes line 2 for <Case>` (3: probe, help text, empty table)
- `writes an empty table as Subcommands = @()`
- `writes a skeleton that Get-CompleterScriptFinding accepts and Get-CompleterScriptTarget reads back for <Case>` (3: empty table, `7z` stem, a tooltip containing all five quote characters)
- `writes UTF-8 without a byte-order mark, platform newlines, and a final newline, identically twice`
- `fails without -Force when the file appeared before the move, and leaves it unchanged`
- `deletes the temporary file and throws the self-check text for a non-conforming line list`
- `reports a target mismatch through the self-check text` (asserts the full `The script registers 'rg', 'rg.exe', not 'rg'.` form)

Review focus: the skeleton matches §2 to the character (four-space indent, braces on the same line); only 7.0 APIs in the generated code; `File.Move` with overwrite; no `.tmp` survives any path.

Done when: the three run steps pass, Linux proven as the rules say.

### WP4a Probe decisions (private)

Owns §2 "Choosing the probe", the run-outcome warnings (did not exit, exited but left a process, and the start-failure text), the text-selection rule (standard output, else standard error), and the probe verbose line. Carries checks 8, 9, and 10 at the helper level; WP4b repeats the command-level forms.

Depends on WP1 and the WP2 code merge.

Scope: WP4a adds no public command and does not touch the manifest. It never edits a WP1 helper, except to fix a defect a WP4a reviewer reports, in a separate commit.

Files:
- new `src/Private/Get-CompleterHelpSubcommand.ps1` (choice 2);
- `tests/CompleterHelpProbe.Tests.ps1` (`Describe 'Probe decisions'`, after WP1's `Describe`);
- `build/`.

Change:
- **The argument** is `-HelpArgument`, or `--help`. On Windows, without `-HelpArgument`, `/?` runs once only when the `--help` run has `Status = 'Exited'`, yields no subcommand, and its cleaned text has fewer than five non-blank lines; the `/?` result is then used and `Argument` is `/?`.
- **Outcomes.** A `TimedOut`, `HeldOutput`, or `StartFailed` run gives its §2 warning (`<limit>` formatted with `[System.Globalization.CultureInfo]::InvariantCulture`) and an empty table, and runs nothing more. An application with `CanRun = $false` runs nothing and returns its `Warning`.
- **Text.** Standard output, or standard error when standard output is empty or whitespace after decoding; then cleaned and parsed with the WP2 helpers.
- **Verbose.** Each run adds `Probed '<path> <arg>': exit <code>, <n> characters, <m> subcommands, <ms> ms.`

Tests (`tests/CompleterHelpProbe.Tests.ps1`, `Describe 'Probe decisions'`, in module scope; real runs use fixtures written to `TestDrive`, and every test that runs `pwsh` as the application skips with the reason `pwsh is not an application on PATH` when it does not resolve):
- `probes pwsh --help once and returns one probe line with exit 0` (check 8; skipped with the reason `pwsh is not an application on PATH` when `Get-Command pwsh -CommandType Application -ErrorAction Ignore` returns nothing). Only the exit code and the line's shape are asserted, because `pwsh --help` differs between legs (§8 check 8).
- `uses help that a probe writes only to standard error with exit 2` (check 8; `-HelpArgument <fake.ps1>` with `pwsh` as the application)
- `decodes UTF-16 LE probe output` (check 8)
- `cuts standard output at 1 MiB and still parses the table` (check 8)
- `warns did not exit within 0.05 seconds and leaves no direct child running` (check 8; `-TimeoutSeconds 0.05`; a pass-through runner shim records `ProcessId`)
- `returns within 3 seconds with the held-output warning and an empty table` (check 8; the WP1 descendant fixture; `AfterEach` stops the descendant). This is the suite's one timing assertion. If it flakes on a loaded runner, the bound is raised to 5 s in a reviewed commit; the test is never skipped or removed.
- `applies the /? rule to <Case>` (check 9; runner replaced; 7 cases): on Windows, two lines runs `/?` once and uses its table with `Argument` `/?`; five lines runs no `/?`; a timeout, a start failure, and held output each run no `/?` (skipped off Windows with the reason `the /? fallback runs on Windows only`); on every leg, `-HelpArgument` given runs exactly one probe; on Linux and macOS, two lines still runs no `/?` (skipped on Windows with the reason `this case asserts the Linux and macOS rule`)
- `runs an executable shell script and warns was not run for the same file without the execute bit` (check 9; `chmod` from the test; skipped on Windows with the reason `execute bits exist on Linux and macOS only`)
- `warns was not run for a console header the loader rejects` (check 9; skipped off Windows with the reason `the PE loader exists on Windows only`)
- `runs nothing for <Case> and returns its warning` (check 10; 3; a counting runner shim counts 0): not found (every leg); the patched GUI copy and a `.cmd` file (skipped off Windows with the reason `the PE and extension checks apply on Windows only`)
- `formats the limit with the invariant culture under a comma-decimal culture` (`[System.Threading.Thread]::CurrentThread.CurrentCulture` set to `de-DE` in the test and restored in `finally`; the warning reads `0.05`)

Review focus: no `/?` after a failed or refused first run; one warning at most per call; `Get-Command` always carries `-ErrorAction Ignore`; no `Write-*`.

Done when: the three run steps pass, Linux proven as the rules say.

### WP4b New-CompleterScript

Owns §2 SYNOPSIS, SYNTAX, PARAMETERS, "Order of work" steps 1 to 5 and the error wrapper, "Output and messages", and EXAMPLES; §1's export count; the golden file; and checks 1, 3, 4 (golden), 5, 6, 11, 12, and 20 (count and syntax), with the command-level forms of checks 8 and 10.

Depends on WP2 corpus in state A (or the owner's answer to state B), WP3, and WP4a.

Scope: WP4b never edits a WP3 or WP4a helper, except to fix a defect a WP4b reviewer reports, in a separate commit.

Files:
- new `src/Public/New-CompleterScript.ps1`, with full comment help mirroring `Export-CompleterSet.ps1`;
- new `src/docs/CompleterActions/New-CompleterScript.md`. Generate it with `New-MarkdownCommandHelp -CommandInfo (Get-Command New-CompleterScript) -OutputFolder <scratch>`, which writes `<scratch>\CompleterActions\New-CompleterScript.md` with the front matter already filled in, copy it into `src/docs/CompleterActions/`, and fill it from §2, with the three examples and the residual-risk paragraph in `NOTES`. Never run `Markdown_templates`;
- `src/docs/CompleterActions/CompleterActions.md` (module page entry);
- `CompleterActions.psd1` (`'New-CompleterScript'` between `'Import-CompleterSet'` and `'Register-Completer'`; the `'Test-CompleterSet'` line keeps its indentation);
- `tests/CompleterDeprecation.Tests.ps1` line 28: `13` becomes `14`;
- `tests/CompleterRegistration.Tests.ps1`: the check 3 alarm test (open item 1);
- new `tests/Fixtures/NewCompleterScript/cargo_completer.expected.ps1` (the golden file, below);
- `tests/CompleterScaffold.Tests.ps1` (`Describe 'New-CompleterScript'`);
- the regenerated help XML and `build/`.

The golden file is written by hand from §2's literal block, and only then compared with the command's output; the command's output is never copied into it. It equals the block except in two places. Line 2 is `# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.`, because the test drives the `HelpText` set with `cargo.txt`, where §2 shows the probe form. The `Subcommands` rows are all 16 rows of `cargo.names.txt`, in order, with each description read from `cargo.txt` and treated as rule 5 and the quoting rule say, where §2 shows two. A difference found on comparison is resolved by reading §2, not by editing the file to match. The name does not match `*_completer.ps1`, and PSScriptAnalyzer lints it with `./tests` (risk 9).

Change:
- **Attributes.** `[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Probe', ConfirmImpact = 'Low')]` and `[OutputType([System.IO.FileInfo])]`. `-HelpText` carries `ValueFromPipeline`, `[AllowEmptyString()]`, and `[AllowEmptyCollection()]`. `-CommandName` carries neither.
- **`begin`.** Step 1 inside `try`/`catch`, wrapped as `Failed to create completer script. <reason>`. `-Path` is resolved with `GetUnresolvedProviderPathFromPSPath`.
- **`process`.** Only appends `-HelpText` lines to a `List[string]`.
- **`end`.** Everything else, inside one `try`/`catch` with the same wrapper:
  - step 2 (Probe set, also under `-WhatIf`): `Resolve-CompleterHelpProbeApplication`; its verbose line names the resolved application or the reason it was not run;
  - step 3: `ShouldProcess(<path>, <action>)` with the §2 action texts; a decline returns nothing;
  - step 4: `Get-CompleterHelpSubcommand -TimeoutSeconds $script:CompleterHelpProbeTimeoutSeconds`, or `ConvertFrom-CompleterHelpText (ConvertTo-CompleterCleanHelpText ($lines -join "`n"))`, or an empty table;
  - step 5: `Get-CompleterScriptSkeleton`;
  - steps 6 and 7: `Save-CompleterScriptFile`;
  - the `Wrote` verbose line, then the `FileInfo` under `-PassThru`.

Child-process tests. The `-WhatIf` and action-text tests write a script to `TestDrive` and run it as `@(& pwsh -NoProfile -NoLogo -NonInteractive -File <script> -Case <case> 2>&1)`, the idiom of `tests/CompleterActions.Tests.ps1` line 800 (fact "`What if:` output"). The script imports the source manifest by full path, installs a counting pass-through shim over `Invoke-CompleterHelpProcess` in module scope, runs the call, and prints `COUNT=<n>` and `EXISTS=<Test-Path target>`. The test computes the expected application path in its own process with `(Get-Command -Name pwsh -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source`; the child inherits the same `PATH`.

Tests (`tests/CompleterScaffold.Tests.ps1`, `Describe 'New-CompleterScript'`; scripts are written to `TestDrive`, and each test unregisters what it registered):
- `writes a conforming rg skeleton from the rg capture with an empty table, the skeleton line 2, and no warning` (check 1, CI form, HelpText set)
- `writes the cargo golden file from the cargo capture` (check 4; line endings normalised to LF on both sides)
- `writes a conforming script for the <Tool> capture that imports and registers lazily with the same targets and writes no warning` (14; check 5; the `sc` case is the partial table, which passes silently as §2 says)
- `offers build and bench for cargo b and no subcommand after cargo build` (check 5, `Test-CompleterRegistration -Native -InputText`)
- `round-trips quotes and cleans control, format, separator, and escape characters in every tooltip` (check 6; the input is built in code with `[char]` values, never checked in, because it holds a NUL)
- `writes a conforming pwsh script from a real probe` (check 8; skipped with the reason `pwsh is not an application on PATH` when it does not resolve; asserts the probe verbose line's exit 0 and conformance only)
- `writes the skeleton line after <Outcome> with its warning` (check 8; 2: timeout with the limit lowered in module scope, held output; `AfterEach` stops the descendant)
- `warns it is a Windows GUI program for the patched GUI copy on PATH and still writes the file` (check 10; skipped off Windows with the reason `the PE and extension checks apply on Windows only`)
- `never runs a .cmd fixture and leaves its marker absent` (check 10; skipped off Windows with the same reason)
- `never runs a global function or alias named like the command` (check 10)
- `warns was not found as an application, writes the skeleton, and does not throw under ErrorActionPreference Stop` (check 10)
- `runs nothing, writes nothing, and names the path and program under -WhatIf` (check 10; child process; `COUNT=0`, `EXISTS=False`, a marker the `-HelpArgument` fixture would create is absent, and exactly one line equals `What if: Performing the operation "Create completer script, running '<pwsh path> <fixture path>' to read its help" on target "<target>".`)
- `asks ShouldProcess with the action for <Case>` (6; child process; each asserts the whole `What if:` line): the default probe on Windows, `running '<pwsh path> --help' and, if it is rejected, '/?' to read its help` (skipped off Windows with the reason `the /? fallback runs on Windows only`); the default probe on Linux and macOS, `running '<pwsh path> --help' to read its help` (skipped on Windows with the reason `this case asserts the Linux and macOS text`); `-HelpArgument`; the HelpText set and the NoProbe set, `without running a program`; and a not-found command, `without running a program`
- `fails step 1 under -WhatIf before anything is resolved` (an existing file without `-Force`; a counting shim over `Resolve-CompleterHelpProbeApplication` counts 0; in process, since only the error is read)
- `refuses an existing file without -Force and replaces it with -Force` (check 11; the text is the shared format string of WP3)
- `fails when the file appears during the probe and leaves no .tmp file` (check 11; the runner shim creates the file)
- `fails <Case> with its section 2 text wrapped in Failed to create completer script` (8; check 11: missing directory, non-`.ps1`, directory path, `_`, `foo.`, `-x`, `a b`, `C:\tools\rg`)
- `returns a FileInfo only with -PassThru` (check 11)
- `pipes the -PassThru FileInfo into Import-CompleterScript`
- `resolves a relative -Path against the current location` (`Push-Location` into `TestDrive`, `Pop-Location` in `finally`)
- `joins piped help lines before parsing` (check 11, including a blank line)
- `fails with the self-check text and leaves no file when the composer emits a top-level assignment` (check 12; `Get-CompleterScriptSkeleton` replaced in module scope)
- `writes the resolved-application, probe, and wrote verbose lines` (§2 "Output and messages")
- `shows the three parameter sets of section 2` (check 20, `Get-Command -Syntax`)
- `declares ConfirmImpact Low, SupportsShouldProcess, and OutputType FileInfo` (`Get-Command` metadata: the `CmdletBindingAttribute` on `ScriptBlock.Attributes`, and `OutputType.Type`)
- In `tests/CompleterRegistration.Tests.ps1`: `finds no Get-ArgumentCompleter or Unregister-ArgumentCompleter on this engine` (check 3, open item 1)
- Modified: `tests/CompleterDeprecation.Tests.ps1` `exports the three legacy names as aliases alongside the functions` asserts 14.

Review focus: every failure is wrapped once; nothing runs before `ShouldProcess`; the golden file was written before the comparison (its first commit precedes or equals the command's); the `What if:` line names both the file and the program.

Done when: the three run steps pass, Linux proven as the rules say; `Get-Command New-CompleterScript -Syntax` shows three sets; `Get-Help New-CompleterScript -Full` resolves from a fresh build in a separate process; the suite passes with 14 exported functions.

### WP5 Import-CompleterSet -Name

Owns §3 "`Import-CompleterSet -Name`" in full, and the automated part of check 2 (§3 "The package layout" as tested behaviour; the prose is WP7's).

Day one. No dependency on WP1 to WP4b.

Files:
- new `src/Private/Resolve-CompleterSetModule.ps1` (choice 6);
- `src/Private/Resolve-CompleterSetEntry.ps1` (choice 7);
- `src/Public/Import-CompleterSet.ps1` (choice 8; comment help: the `Name` set, one example, the two package rules, and the trust sentence);
- `src/docs/CompleterActions/Import-CompleterSet.md` (the same, by hand);
- new `tests/Fixtures/CompleterSetPackage/` with `cafixalpha_completer/cafixalpha_completer.ps1`, `cafixbeta_completer/cafixbeta_completer.ps1`, and `cafixgamma_completer/cafixgamma_completer.ps1`. These are strict native completers for `cafixalpha`, `cafixbeta`, and `cafixgamma`, each with its `.exe` target. Manifests and sets are written at test time with `New-ModuleManifest` and `Export-CompleterSet`;
- new `tests/CompleterSetPackage.Tests.ps1` (`Describe 'Import-CompleterSet -Name'`), with a `New-TestCompleterSetPackage -Root -Name -Version [-PrivateData] [-RequiredModules] [-RootModule]` helper that builds a package folder in `TestDrive`;
- the regenerated help XML and `build/`.

Change:
- **Parameter.** `[Parameter(Mandatory, ParameterSetName = 'Name')] [ValidateNotNullOrEmpty()] [string[]] $Name`, with no position and no pipeline binding. The default set stays `Path`.
- **Wildcards.** A value matching `[*?\[\]]` throws `Import-CompleterSet -Name does not accept wildcards. Received '<name>'.` inside the existing wrapper, so the error reads `Failed to import completer set. Import-CompleterSet -Name does not accept wildcards. Received '<name>'.`, before any resolution.
- **Resolution.** Every name goes through `Resolve-CompleterSetModule`. The first failure fails the call with `Failed to import completer set. <reason>`.
- **Per module set.** The verbose line `Completer set module '<Name>' <version> at '<ModuleBase>': '<file>'.`, the trusted-entry warning when the count is above 0, and the containment parameters. Everything else is the 2.1.0 body.
- **Names.** `<Name>` is the value as given in the not-found reason and the installed folder's spelling everywhere else (§3).

Tests (`tests/CompleterSetPackage.Tests.ps1`; module roots are `TestDrive` folders joined with `[System.IO.Path]::PathSeparator` and set as `$env:PSModulePath` inside the test):
- `uses the first root that has the module over a higher version in a later root` (check 13)
- `uses the highest version folder within a root` (check 13)
- `skips a version folder that differs from its manifest's ModuleVersion for <Case>` (check 13; 2: folder `9.0.0` with `1.0.0`; folder `1.0.0.0` with `1.0.0`)
- `uses the unversioned layout only when the root has no versioned candidate`
- `finds a module folder spelled CaFixtureSet by -Name cafixtureset and names it CaFixtureSet in the verbose line` (check 13; this is the Linux assertion)
- `finds a manifest whose base name differs from its folder only by case`
- `skips empty and missing PSModulePath entries`
- `fails with the section 3 text for <Case>` (check 13; 8: missing module, whose text carries the name as given; no `CompleterSet`; a value directly in `ModuleBase`; a value with `..`; a rooted value; a value two folders deep; a non-`.psd1` value; a missing set file)
- `accepts a backslash as the separator in PrivateData.CompleterSet`
- `uses the highest version even when it is broken and never falls back`
- `fails a wildcard name before resolving anything` (check 13; asserts the wrapped text)
- `never runs a RootModule, a ScriptsToProcess script, a NestedModules entry, or a RequiredModules module` (check 13; each would write a marker file; the required module is a fixture module in the same root whose root module writes a marker)
- `resolves every name before importing any set`
- `returns ModuleBase as a full path when a root carries a .. segment` (module scope, `Resolve-CompleterSetModule`)
- `fails a set whose entry resolves outside the module, and skips it under -SkipInvalid` (check 14; 2 cases)
- `reports only the outside-module problem for an outside entry whose file is missing` (exactly one problem; a shim over the hash helper in module scope counts 0 calls for that entry)
- `treats a sibling folder whose name extends the module's as outside` (`CaFixtureSet2` beside `CaFixtureSet`)
- `compares containment with the platform's case rule` (an entry that reaches the module folder through a differently cased spelling: inside on Windows and macOS; on Linux, outside, with the one outside problem)
- `writes one trusted-entry warning naming CaFixtureSet for a package with two trusted entries, and none through -LiteralPath` (check 14; called with `-Name cafixtureset`)
- `writes the trusted-entry warning even when the set then fails`
- `writes the module verbose line before the set's own lines`
- `shows the version with its prerelease label`
- `keeps Path as the default set and binds no pipeline input to -Name`
- `packs the fixture package with Compress-PSResource` (choice 10; every leg where PSResourceGet 1.1.0 or later is present)
- `refuses to pack a second .psd1 beside the manifest` (choice 10; asserts that an exception is thrown, not its text; skipped off Windows with the reason `Linux lists the folder unsorted, so which .psd1 is taken depends on the file system`; the module-side rule is WP6's row 2 test on every leg)
- `imports by name from a saved package exactly as -LiteralPath does in a second process` (check 2; the child per choice 10, with its two skip reasons; the CSV of `Key, RuntimeKey, State, Trusted, ScriptPath` is compared with the CSV from a `pwsh -NoProfile` second process that imports with `-LiteralPath`; every `ScriptPath` is under the saved `ModuleBase`; no warning and no error)

Unchanged: `git diff main -- tests/CompleterSet.Tests.ps1` prints nothing, and every test in it passes, including the verbose-line and summary tests.

Review focus: `git diff` of `Import-CompleterSet.ps1` shows the per-set body moved, not changed; no new text on the `-Path` and `-LiteralPath` paths; containment uses a trailing separator and the platform comparison; no test can register a repository on a developer's Windows machine.

Done when: the three run steps pass, Linux proven as the rules say; on the owner's Windows machine the save step reports skipped with the choice 10 reason, and on the Windows CI legs it runs.

### WP6 Test-CompleterSet -Name and PackageLayout (questions 8 and 9)

Owns §3 "`Test-CompleterSet` and the package layout" and check 15. It is isolated so that a "no" to question 8 or 9 removes only its part. A "no" to question 9 drops the `-Name` set and its tests. A "no" to question 8 drops choice 9, `Get-CompleterSetPackage`, `Get-CompleterSetPackageFinding`, and the mutation tests.

Depends on WP5 (`Resolve-CompleterSetModule`, the fixture package helper).

Scope: WP6 reuses WP5's wildcard rule with the cmdlet name changed and calls `Resolve-CompleterSetModule` as it is; it does not edit WP5 helpers.

Files:
- new `src/Private/Get-CompleterSetPackage.ps1` and `src/Private/Get-CompleterSetPackageFinding.ps1` (choice 9);
- `src/Private/Get-CompleterSetFinding.ps1` (optional `-Package`, the list of resolved entries);
- `src/Public/Test-CompleterSet.ps1` (the `Name` set, the wildcard rule with the text `Test-CompleterSet -Name does not accept wildcards. Received '<name>'.` inside `Failed to test completer set. <reason>`, resolution, package detection for every set; comment help: `PackageLayout`, the `Name` set, one example);
- `src/docs/CompleterActions/Test-CompleterSet.md` (the same);
- `tests/CompleterSetPackage.Tests.ps1` (`Describe 'Test-CompleterSet package checks'`);
- the regenerated help XML and `build/`.

Change:
- **Rows.** The three §3 rows with their texts, severities, and positions.
  - Row 1 runs per entry in set order, when `[System.IO.Path]::IsPathFullyQualified(<declared path>)` or the resolved path is outside `ModuleBase` (the choice 7 comparison).
  - Row 2 gives one finding per other `.psd1` in `ModuleBase`, in ordinal order of file name.
  - Row 3 is satisfied by a `RequiredModules` element that is a hashtable whose `ModuleName` is `CompleterActions` and whose `ModuleVersion` or `RequiredVersion`, compared as `[version]`, is 2.2.0 or later. A bare string or a lower version warns.
- **Order.** The `PackageLayout` findings come after every entry's findings and before `UnlistedScript`: row 1 in entry order, then row 2, then row 3.
- **Plain sets.** No manifest declares a plain set, so it never calls the package finding helper, and its findings, order, and texts are 2.1.0's.

Tests:
- `reports <Mutation> and nothing after reverting it` (check 15; 5: fully qualified `Path`; script moved to `<ModuleBase>\..\outside_completer.ps1` with the set regenerated; second `.psd1` beside the manifest; `RequiredModules` emptied; manifest deleted, which gives none). The fixture is copied into `TestDrive` before its set is generated.
- `returns nothing for an installed copy tested by -Name for <Case>` (check 15; 2: a package folder built by `New-TestCompleterSetPackage` in a scratch module root, on every leg; the copy saved by `Save-PSResource`, with choice 10's two skip reasons)
- `reports one PackageLayout error for a script on another drive than the set` (check 15). Runs only on Windows CI, where the workspace is on D: and `TestDrive` on C:; skipped with the reason `the repository and TestDrive share a drive` wherever their roots match, which includes the owner's machine, and with the reason `drive letters exist on Windows only` off Windows.
- `fails with Failed to test completer set for <Case>` (3: missing module, wildcard with the full `Test-CompleterSet -Name does not accept wildcards` text, no `CompleterSet`)
- `treats a parent .psd1 that is not data as no manifest`
- `treats a parent folder that cannot be listed as holding no manifest` (mode `a-r` on the parent, keeping `x`, restored in `finally`; skipped on Windows with the reason `denying a folder listing needs an ACL edit; the Linux legs cover the rule`, and with the reason `root ignores file modes` when `id -u` prints 0)
- `reports no finding for a manifest with a RootModule`
- `accepts RequiredModules <Case>` (4: hashtable 2.2.0 passes; `RequiredVersion` 2.3.0 passes; hashtable 2.1.0 warns; bare string warns)
- `writes PackageLayout findings after the entry findings and before UnlistedScript`
- `writes one finding per extra .psd1 in ordinal order`
- `uses the first declaring .psd1 in ordinal order as the manifest`
- `tests every set named by -Name in order`

Unchanged (check 16, first half): `git diff main -- tests/CompleterSetDrift.Tests.ps1` prints nothing, and every test in it passes.

Review focus: no new finding on any set that 2.1.0 tests; `Path` is the set file on every finding; the line-1 extent has a valid `StartColumnNumber` of 1.

Done when: the three run steps pass, Linux proven as the rules say, and the drift file is untouched.

### WP7 Documentation and the cross-feature test

Owns §4 in full and §3's layout and manifest prose; adds the check 18 tests and the check 19 snapshot test, which needs `New-CompleterScript` (WP4b) and both `-Name` sets (WP5, WP6).

Starts once WP4b and WP6 are merged. It can run in parallel with WP8.

Scope: WP7 does not rewrite `src/docs/CompleterActions/New-CompleterScript.md`, `Import-CompleterSet.md`, or `Test-CompleterSet.md`, or their comment help; it checks them against §4 and reports a gap to the orchestrator.

Files: `en-US/about_Import_Completers.help.txt`, `en-US/about_Completer_Sets.help.txt`, `README.md`, `CHANGELOG.md`, `.github/copilot-instructions.md`, `tests/CompleterActions.Tests.ps1`, `tests/CompleterSetPackage.Tests.ps1` (`Describe 'Completer authoring and packages leave PSReadLine alone'`), and `build/`.

Change:
- **`about_Import_Completers`.**
  - A new `SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT` section before `THE STRICT GRAMMAR` (line 205 today), covering the seven §4 bullets. The examples are `cargo` and `pip` (works), `git` (does not), and `sc` (a partial table that passes every check and draws no warning, so the author compares it with the help).
  - `BASIC WORKFLOW` (line 592) gains step 0 and the `Export-CompleterSet`, then `Test-CompleterSet`, step.
  - A short `DISTRIBUTING COMPLETERS AS A MODULE` paragraph points to `about_Completer_Sets`.
  - `SEE ALSO` (line 690) gains `Get-Help New-CompleterScript -Full`.
- **`about_Completer_Sets`.**
  - `THE HASH AND THE FAST PATH`, `CHECKING FOR DRIFT WITH TEST-COMPLETERSET` (every `Construct` with severity and fix, `PackageLayout` included), and `COMPLETER SETS AS MODULES` (layout tree, manifest sample, the one-`.psd1` rule and why, `New-ModuleManifest -PrivateData @{ CompleterSet = ... }` with `-Tags`, `-Name` resolution and its two package rules, the trust statement, `Test-CompleterSet -Name`, and staging before `Publish-PSResource`), each with the §4 bullets.
  - Existing paragraphs that the new sections supersede are moved into them, not duplicated: the fast-path paragraph under `VALIDATION BEFORE REGISTRATION` (lines 178 to 190) and the `Test-CompleterSet` paragraph under `WORKFLOW` (lines 283 to 295).
  - `WORKFLOW` gains `Import-CompleterSet -Name <module>`, and `SEE ALSO` gains `Get-Help New-CompleterScript -Full`.
- **`README.md`.** A command-map row between `Import-CompleterSet` and `Register-Completer`: "`New-CompleterScript` | Writes a completer script skeleton for a native command, with a subcommand table read from its help, that passes `Test-CompleterScript` as written". A "Scaffold a completer" line in "Typical flow".
- **`CHANGELOG.md` `## [Unreleased]`.** `### Added`: `New-CompleterScript`; `Import-CompleterSet -Name` with the two package rules; `Test-CompleterSet -Name`; `PackageLayout`; with the module now exporting fourteen functions and the same three aliases. `### Documentation`: the third edition of both about topics. The headings are cut at release.
- **`.github/copilot-instructions.md`** (§4, departure 12). Line 6: "ten commands" becomes "eleven commands", with `New-CompleterScript` added to the list, and "thirteen functions" becomes "fourteen functions"; line 8: "thirteen functions" becomes "fourteen functions".
- **Not edited:** `en-US/about_CompleterActions_Migration.help.txt`, under §7 (open item 2).

Tests:
- In `tests/CompleterActions.Tests.ps1`, next to the existing about-topic tests at line 145:
  - `has the third-edition headings in <Topic>` (2; check 18): `about_Completer_Sets` with its three headings, and `COMPLETER SETS AS MODULES` containing `PrivateData.CompleterSet` and `Import-CompleterSet -Name`; `about_Import_Completers` with `SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT` before `THE STRICT GRAMMAR`, and `DISTRIBUTING COMPLETERS AS A MODULE`
  - `gives New-CompleterScript the section 2 synopsis and three examples` (check 18)
  - `resolves help for Import-CompleterSet -Name` (check 18)
- In `tests/CompleterSetPackage.Tests.ps1`: `leaves PSReadLine key handlers unchanged across New-CompleterScript with a probe, Import-CompleterSet -Name, and Test-CompleterSet -Name` (check 19; the snapshot idiom; skipped with the existing reason `PSReadLine is not loaded in this session` where it cannot load; the probe runs a `pwsh -File` fixture through `-HelpArgument`)

Review gate for wording: in a `pwsh -NoProfile`, `Select-String -Path en-US/*.txt, src/Public/*.ps1, src/docs/CompleterActions/*.md, README.md, .github/copilot-instructions.md -Pattern 'thirteen', 'ten commands', '13 functions', 'Test-CompleterSet'`, with each hit listed in the review note as kept or changed and why. The one expected count hit is `about_CompleterActions_Migration.help.txt` line 65 (open item 2). The `Test-CompleterSet` hits (22 across these paths today) are each read for a statement that §3 now contradicts, such as a set test that never looks at a manifest.

Done when: the three run steps pass, Linux proven as the rules say; the wording gate's hits are all accounted for; the documents gate of the rules prints nothing.

### WP8 Import-time non-regression (validator step)

Owns §5 and check 21. A validator step, not an implementer package: its done-when is the committed validation file, and reviewers check that file, not code.

Runs after WP4b, WP5, and WP6 are merged on the branch, because they fix the import path. It needs no tool change.

Prerequisites: the owner's machine (Windows, pwsh 7.6.6), `git` with `tar` on `PATH`, and read access to `C:\Users\Trent\OneDrive\Documents\PowerShell\Completers` for the clone. Every `<scratch>` folder is under the session scratchpad, never in the repository.

Steps, each in its own `pwsh -NoProfile`:
1. `git clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers`, then `New-Item -ItemType Directory -Path <scratch>\v2.1.0 -Force | Out-Null`, then `git archive v2.1.0 build | tar -x -C <scratch>\v2.1.0` (tar fails with "could not chdir" when the folder is missing).
2. Gate run: `.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v2.1.0\build\CompleterActions -Iterations 10`. `-ModulePath` stays the default, the branch's `build/CompleterActions`. Never omit `-CompleterRoot`: the default is the real repository.
3. Run rule (§5): run once; a `LazyNoHash` `RatioToBaseline` of 1.05 or lower passes on that run. Over 1.05, run up to three more; the gate is the median of all runs taken, and every run is reported. A median above 1.05 is a regression: it goes back to the package that changed the import path, and the runs are repeated after the fix.
4. Information run: the same command with `-ModulePath <scratch>\v2.1.0\build\CompleterActions` and no baseline, for 2.1.0's `Lazy` median, reported beside 2.2.0's.
5. Spot cost, with its own throwaway staged package (no dependency on WP9 or WP10):
   - copy the clone's `ps_completers.psd1` and every `*_completer` folder into `<scratch>\modules\PS_Completers\1.0.0\completers\`;
   - `New-ModuleManifest -Path <scratch>\modules\PS_Completers\1.0.0\PS_Completers.psd1 -ModuleVersion 1.0.0 -PrivateData @{ CompleterSet = 'completers/ps_completers.psd1' }`;
   - ten fresh `pwsh -NoProfile` processes, each with the §8 preamble and `$env:PSModulePath = "<scratch>\modules;$env:PSModulePath"`, time `Import-CompleterSet -Name PS_Completers` with `Measure-Command`; ten more time `Import-CompleterSet -LiteralPath <scratch>\modules\PS_Completers\1.0.0\completers\ps_completers.psd1`. The difference of medians must be at most 20 ms. The harness is a scratch script, not committed.

Recording: `docs/roadmap-3.0/validation/milestone-2-benchmark.md`, in the shape of `benchmark.md`: the command lines, the tool's full output per run, the spot-cost samples, the pwsh version, the OS, the branch commit, the PS_Completers commit, a criteria table (`LazyNoHash` at most 1.05 by the run rule; spot cost at most 20 ms), and the two `Lazy` medians marked "reported, not gated". Commit: `docs(validation): record the milestone 2 import-time check`. The same numbers go into the pull request body.

Done when: `milestone-2-benchmark.md` is committed on the branch and its criteria table shows a pass.

### WP9 Runtime validation (powershell-runtime-validator; validator step)

Owns §7 as verified behaviour, and the parts of checks 1, 2, 16, 17, 19, 20, and 22 that Pester does not cover. A validator step, not an implementer package: its done-when is the committed validation files, and reviewers check those files.

Runs after WP1 to WP8 are on the branch and `build/` is fresh.

Prerequisites: the owner's machine; ripgrep 15.2.0 on `PATH` (check 1, owner form); WSL Ubuntu with `/snap/bin/pwsh` and PSResourceGet 1.1.0 or later (checks 2 and 17); PSReadLine loadable (check 19); the WP8 scratch clone.

Every check runs in its own `pwsh -NoProfile` with §8's preamble, against `$module` = the branch's `build/CompleterActions`, asserting `ModuleBase` first. PS_Completers is read only through the WP8 scratch clone.

**Module sources.**
- 2.1.0 build: `git archive v2.1.0 build`, as WP8 step 1, never the gallery copy.
- Branch build: reports 2.1.0 until the release commit.
- Stamped branch build: `Copy-Item build\CompleterActions <scratch>\stamped\CompleterActions -Recurse`, then `ModuleVersion = '2.2.0'` in the copy's `.psd1` only. It is used where a by-name import must satisfy `-MinimumVersion 2.2.0` (the PS_Completers gate of check 17), with `$env:PSModulePath = "<scratch>\stamped;$env:PSModulePath"` and a `ModuleBase` assertion in the same process.

Checks:
- **Check 1, owner form.** `New-CompleterScript -CommandName rg -Path <scratch>\rg_completer.ps1 -PassThru | Test-CompleterScript` is empty through the Probe set with ripgrep 15.2.0, `Test-CompleterScript -LiteralPath` is empty, line 1 is `# rg tab completion for PowerShell`, line 2 is the skeleton line, and the targets are `'rg', 'rg.exe'`.
- **Check 2, owner's machine.** Run under WSL (`/snap/bin/pwsh -NoProfile`, `XDG_DATA_HOME` pre-created), because the Windows store cannot be redirected (choice 10). The Windows side is covered by the Windows CI legs. Attach the CSV pair as `docs/roadmap-3.0/validation/milestone-2-check2-import-name.csv`.
- **Check 3.** `Get-Command Get-ArgumentCompleter, Unregister-ArgumentCompleter -ErrorAction Ignore` is empty on 7.6.6, and the full suite passes unchanged on all eight CI legs.
- **Check 16, second half.** `Test-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1` returns nothing under the branch build and under the 2.1.0 build.
- **Check 17.** In the scratch clone, prototype WP10 step 1 uncommitted: the manifest at `package/PS_Completers.psd1`, a staging script, and the package gate in `tests/Completers.Tests.ps1`. Then:
  - `Test-CompleterSet -LiteralPath <staging>\PS_Completers\completers\ps_completers.psd1` returns nothing;
  - the clone's Pester run passes with its previous count plus one, under the stamped build;
  - the staged folder, published and saved under WSL with the XDG redirect, gives `Import-CompleterSet -Name PS_Completers` with the same `Pending` count and `Key` list as `-LiteralPath <scratch>\PS_Completers\ps_completers.psd1` in a second process (173 entries and 362 targets at `2c590c6`, appendix B; the assertion is equality). Attach the result as `milestone-2-check17-import-name.csv`.

  The prototypes are handed to the owner as WP10's starting point.
- **Check 19, live.** A `Get-PSReadLineKeyHandler -Bound -Unbound` snapshot is identical before and after `New-CompleterScript` (with a probe), `Import-CompleterSet -Name`, and `Test-CompleterSet -Name`.
- **Check 20.** 14 functions and 3 aliases. For each of the 13 functions of the 2.1.0 build, the parameter names and parameter sets from `Get-Command` metadata are identical, except the new `Name` sets of `Import-CompleterSet` and `Test-CompleterSet`. The version lines are checked on the release commits (release recipe steps 5 and 14).
- **Check 22.** `Get-Help New-CompleterScript -Full`, `Get-Help Import-CompleterSet -Parameter Name`, and both about topics resolve from the build in a fresh process.
- **§7 spot checks.** One `Import-CompleterSet -LiteralPath` over the scratch clone's set under the branch build and the 2.1.0 build gives the same CSV, the same verbose lines, and no trusted-entry warning. `Reset-Completer -Verbose` output is unchanged. This comparison is a pull request gate for risk 14.

Recording: `docs/roadmap-3.0/validation/milestone-2-runtime.md`, one row per check above with the command, the output or a link to the attached CSV, and pass or fail; plus the two CSV files. Commit: `docs(validation): record the milestone 2 runtime checks`.

Acceptance: every check matches §8. Any miss goes back to its package before the pull request is opened.

Done when: `milestone-2-runtime.md` and both CSV files are committed on the branch and every row reads pass.

### WP10 PS_Completers follow-up (owner, outside this repository)

Owns §3 "PS_Completers as the reference package". Described here, NOT made by an implementer agent; the owner makes it in the §3 "Order":

1. After `2.2.0-preview1` is on PSGallery, on a PS_Completers branch:
   - add `package/PS_Completers.psd1`, shaped as §3, with `PrivateData.CompleterSet = 'completers/completers.psd1'`, `RequiredModules` CompleterActions 2.2.0, and empty export lists;
   - add a staging tool (for example `tools/Build-Package.ps1`) that builds `<staging>/PS_Completers/` with the manifest, `LICENSE`, and `README.md` at its root and, under `completers/`, `ps_completers.psd1` copied byte for byte as `completers.psd1` with every `*_completer` folder, leaving out `tests`, `tools`, `.github`, `docs`, `package`, and `.claude`. The set moves to `completers/completers.psd1` in the package because its base name must differ from the module name (§3, WP12);
   - add the package gate to `tests/Completers.Tests.ps1`: stage into `$TestDrive`, then assert that `Test-CompleterSet -LiteralPath <staging>/PS_Completers/completers/completers.psd1` is empty, importing CompleterActions with `-MinimumVersion 2.2.0`, which the preview satisfies because its `ModuleVersion` is 2.2.0.

   The CI there installs with `-Prerelease`, so a green branch is part of the soak. WP9's check 17 prototypes are the starting point.
2. Any time before the publish: `Find-PSResource PS_Completers -Repository PSGallery` still finds nothing (question 11).
3. After `2.2.0` stable is on PSGallery: merge the branch, stage, and publish with the owner's key (checklist below). Then add the `README.md` install section (§3 step 4).
4. Optionally switch the profile line to `Import-CompleterSet -Name PS_Completers` on machines that install the package.

Nothing in the set, its paths, or the files that name it changes in the repository (§3 "What does not change"); only the staged copy is named `completers.psd1`.

**Owner checklist for the publish (step 3).** Each item is checked off in order; an agent may prepare the commands but never runs the publish or holds the key.
1. The PS_Completers branch CI is green with the preview installed by `-Prerelease`, and its run log shows `2.2.0-preview1` installed.
2. `Test-CompleterSet -LiteralPath <staging>/PS_Completers/completers/completers.psd1` prints nothing, under 2.2.0 stable.
3. `Find-PSResource PS_Completers -Repository PSGallery` returns nothing.
4. Dry run: `Compress-PSResource -Path <staging>/PS_Completers -DestinationPath <scratch>` succeeds, and the `.nupkg` holds the manifest at its root and `completers/` with the set and every `*_completer` folder, and no `tests`, `tools`, `.github`, `docs`, `package`, or `.claude`. Then `Publish-PSResource -Path <staging>/PS_Completers -Repository PSGallery -ApiKey <key>`.
5. On a clean session, run the roadmap's exit criterion 2 line exactly as `docs/roadmap-3.0.md` line 71 states it:

   ```powershell
   Install-PSResource PS_Completers; Import-CompleterSet -Name PS_Completers               # one line, no path
   ```

   The result goes to the owner's roadmap edit (§6 edit 5, question 10).

### WP11 Pull request and release 2.2.0 (owner-run, agent-assisted)

A release procedure, not an implementer package: no `It` blocks and no source change beyond the release commits. The owner runs it; an agent may prepare each command, run the checks, and draft the pull request body and release notes, and stops at every step marked as the owner's. Steps are in "Release recipe for 2.2.0" below. The documents rule applies: the pull request body and the commits report results and never restate an exit criterion.

### WP12 Follow-up decisions after WP9 (owner ruling 2026-10-03)

Goal: three fixes the owner decided on 2026-10-03 after WP9's findings, made on the feature branch itself, after WP9 and before WP11.
- **Set-file name rule.** WP9 row 5 found that PSResourceGet 1.2.0 `Save-PSResource` reads a `.psd1` whose base name equals the module name, case-insensitively, as the manifest, even in a subfolder. `Test-CompleterSet` gains a `PackageLayout` Error for a set file whose base name equals the module name (§3 row 3; the `RequiredModules` warning, WP6's row 3, is row 4 since). It fires only for a set a manifest declares. `Import-CompleterSet -Name` is unchanged. WP10 stages the PS_Completers set as `completers/completers.psd1`.
- **Empty stem.** `_.exe` and `__.cmd` match the §2 pattern but give an empty stem. `New-CompleterScript` rejects them in step 1 with `The command name '<name>' has no letter or digit outside its suffix, so no function name can be derived from it.`
- **Line break in `-HelpArgument`.** A CR or LF would end the line 2 comment. Step 1 rejects it with `-HelpArgument must not contain a line break.`

Both rejections are wrapped in `Failed to create completer script.` and happen before `ShouldProcess` and before any probe.

Documents: the owner authorised this package, and only it, to edit the spec (§2 target list, stem, step 1, and `-HelpArgument`; §3 package layout, row 3, and the PS_Completers section; §8 checks 15 and 17), this plan (WP10, this section, the traceability table, the verification checklist, and the worktree rule), and one line of `validation/milestone-2-benchmark.md`. `docs/roadmap-3.0.md` stays untouched.

Files:
- `src/Private/ConvertTo-CompleterTargetName.ps1` (the spec pattern, then the empty-stem check) and `src/Public/New-CompleterScript.ps1` (the `-HelpArgument` check), with `src/docs/CompleterActions/New-CompleterScript.md`;
- `src/Private/Get-CompleterSetPackageFinding.ps1` (row 3), `src/Public/Test-CompleterSet.ps1`, and `src/docs/CompleterActions/Test-CompleterSet.md`;
- `en-US/about_Completer_Sets.help.txt` (the rule and its reason, and the examples renamed to `completers.psd1`) and `CHANGELOG.md`;
- `tests/CompleterScaffold.Tests.ps1` and `tests/CompleterSetPackage.Tests.ps1`;
- the regenerated help XML and `build/`.

Tests:
- `rejects the command name <Name>, whose stem would be empty` (`_.exe`, `__.cmd`, `_+.COM`) and the `_.exe` and `__.cmd` cases of `fails <Case> with its section 2 text wrapped in Failed to create completer script`, which also assert that nothing is written;
- `writes Complete-A for the name _a, whose letter is outside any suffix`;
- `fails a -HelpArgument that holds <Case>, before anything runs or is written` (CR, LF, CR LF; the counting runner shim records no run);
- `applies the set-file name rule to the module <ModuleName> through -<Source>` (`Completers` and `completers` fire, `CaFixtureSet` does not, through `-LiteralPath` and `-Name`, on every leg);
- the mutation `a manifest renamed to the set file's base name` in `reports <Mutation> and nothing after reverting it`, and row 3 in `writes PackageLayout findings after the entry findings and before UnlistedScript`.

Done when: the three run steps pass, the branch keeps one distinct trailer line, and `git diff main -- docs/roadmap-3.0.md` prints nothing.

## Order and parallelism

```text
WP1 (process helpers) ─────────┬──> WP2 corpus ──────────────┐
                                └─┐                           │
WP2 code (decode, clean, parse) ──┴──> WP4a (probe decisions) ┤
WP3 (skeleton, write) ────────────────────────────────────────┴──> WP4b (New-CompleterScript) ─┐
WP5 (Import -Name) ──> WP6 (Test -Name, PackageLayout) ────────────────────────────────────────┤
                                                                                               ├──> WP7 (docs, check 19) ─┐
                                                                                               └──> WP8 (import time) ────┴──> WP9

WP9 ──> WP11 preview ──> WP10 step 1 (owner) ──> soak ──> WP11 stable ──> WP10 steps 2 to 4 (owner)
```

WP1 feeds WP2 corpus (the runner) and WP4a; WP2 code feeds WP2 corpus as well as WP4a; WP4b needs WP2 corpus, WP4a, and WP3; WP7 and WP8 each need both WP4b and WP6.

- **Day one, in parallel:** WP1, WP2 code, WP3, and WP5. Their files do not overlap. Each has its own test file (choice 11).
- **After WP1:** WP2 corpus.
- **After WP1 and WP2 code:** WP4a.
- **After WP2 corpus (state A, or the owner's answer to state B), WP3, and WP4a:** WP4b. It is the only package that touches the manifest, the function-count pin, and the module page.
- **After WP5:** WP6. It is the only package that touches `Test-CompleterSet` and `Get-CompleterSetFinding`; WP5 is the only one that touches `Import-CompleterSet` and `Resolve-CompleterSetEntry`.
- **After WP4b and WP6:** WP7 and WP8, in parallel.
- **After WP1 to WP8:** WP9, then WP11 to the preview, then WP10 step 1 (owner), the soak, WP11 to stable, and WP10 steps 2 to 4 (owner).
- **Shared files:** `tests/CompleterHelpProbe.Tests.ps1` (WP1, then WP4a), `tests/CompleterScaffold.Tests.ps1` (WP3, then WP4b), and `tests/CompleterSetPackage.Tests.ps1` (WP5, then WP6, then WP7). Each later package adds its own `Describe` after the earlier ones. `build/` and the help XML are rebuilt after every merge (rules, "Worktrees and merges").

## Verification checklist

Before the pull request:

- [ ] This plan and the spec were committed to main before the branch was cut, and `git diff main -- docs/roadmap-3.0.md docs/roadmap-3.0/milestone-2-spec.md docs/roadmap-3.0/milestone-2-plan.md` prints nothing, apart from the WP12 edits of the next item.
- [ ] WP12: its tests pass on every leg; `git diff main -- docs/roadmap-3.0.md` prints nothing; and `git log main..HEAD --format=%s -- docs/roadmap-3.0/milestone-2-spec.md docs/roadmap-3.0/milestone-2-plan.md` prints only `docs(roadmap): record the WP12 follow-up decisions in the milestone 2 spec and plan`.
- [ ] `pwsh -NoProfile -Command "Invoke-Build -Task build"` succeeds in its own process, first; `build/` and both help XML files are committed.
- [ ] The two `Invoke-ScriptAnalyzer` calls of the rules print nothing, in a process separate from Pester.
- [ ] `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes in a new process, including the tracked-build test. The count is reported, not gated (see the estimate).
- [ ] `git ls-files --eol` shows every new or edited text file as `w/crlf` on Windows, and none as `i/crlf`.
- [ ] The pre-PR commit check of the rules prints one trailer line and a `Claude-Session` count of 0.
- [ ] `milestone-2-benchmark.md`, `milestone-2-runtime.md`, and both CSV files are committed under `docs/roadmap-3.0/validation/`.
- [ ] Every §8 check below has passed where it is marked.

| §8 check | Where it is verified |
| --- | --- |
| 1 Scaffold passes the grammar as written | WP4b Pester (HelpText set, rg capture); WP9 owner run (Probe set, ripgrep 15.2.0) |
| 2 Package installs and imports by name | WP5 Pester (Linux legs and Windows CI legs); WP9 under WSL, CSV in `validation/` |
| 3 Engine cmdlets absent, reflection path unchanged | WP4b alarm test on all eight legs (open item 1); WP9 |
| 4 Parser fixtures and cargo golden | WP2 Pester (names); WP4b Pester (golden) |
| 5 Every output conforms and works | WP4b Pester |
| 6 Quoting and cleaning | WP4b Pester (end to end); WP2 and WP3 unit tests |
| 7 Decoding | WP2 Pester, every leg |
| 8 Probe mechanics | WP4a Pester, every leg; WP1 runner tests; WP4b end to end |
| 9 Probe decisions | WP1 Pester (PE reader); WP4a Pester (`/?` rule, start failures) |
| 10 Probe safety | WP1 resolution tests; WP4a (refused applications run nothing); WP4b end to end, `-WhatIf` in a child process |
| 11 Files, errors, pipeline input | WP4b Pester; WP3 write tests; WP12 Pester (empty-stem names, `-HelpArgument` line breaks) |
| 12 Self-check | WP4b Pester; WP3 unit tests |
| 13 Resolution rule | WP5 Pester |
| 14 Package rules for `-Name` | WP5 Pester |
| 15 `Test-CompleterSet` package checks | WP6 Pester (cross-drive case on Windows CI only); WP12 Pester (set-file name row) |
| 16 Plain sets untouched | WP6 (drift file unchanged and passing); WP9 scratch clone |
| 17 PS_Completers as a package | WP9 scratch clone (prototype of WP10 step 1); release recipe step 3 (real preview build) |
| 18 Help content | WP7 Pester; WP9 from the build |
| 19 PSReadLine | existing three snapshot tests; WP7 new test; WP9 live |
| 20 Surface | WP4b Pester (14, syntax, metadata); WP9 (2.1.0 parameter comparison); release recipe steps 5 and 14 (version lines) |
| 21 Performance | WP8, recorded in `validation/milestone-2-benchmark.md` and the PR |
| 22 Suite, lint, eight CI legs, help from the build | every package's run steps; PR CI; WP9 |

After the pull request: all eight CI legs are green (Windows and Ubuntu by 7.4, 7.5, 7.6, and preview), and the owner has reviewed it.

### Traceability: spec section to work package

Every behaviour statement lands in exactly one package. "Verified by" packages only test it.

| Spec section | Owner WP | Verified by |
| --- | --- | --- |
| §1 scope, additivity, 14 functions, 7.0 floor, PSReadLine neutrality | WP4b (count, pin) | WP7 (check 19), WP9 (check 20); floor in every package's review |
| §1 non-goals | none (nothing to build) | WP9 §7 spot checks |
| §2 SYNOPSIS, SYNTAX, PARAMETERS, EXAMPLES | WP4b | WP7 (help text) |
| §2 Order of work, steps 1 to 5 and the error wrapper | WP4b | |
| §2 Order of work, steps 6 and 7 (self-check, atomic write) | WP3 | WP4b (check 12) |
| §2 Target list; Names in the generated script | WP3 | WP4b |
| §2 Choosing the probe (`/?` rule), run-outcome warnings, start-failure text | WP4a | WP4b |
| §2 What "read safely" means: resolution, PE, start-failure status, run, deadline | WP1 | WP4a, WP4b |
| §2 What "read safely" means: decoding, cleaning | WP2 | WP4a, WP4b |
| §2 Parsing the subcommand table | WP2 | WP4b (check 5) |
| §2 Skeleton; Encoding and line endings | WP3 | WP4b (checks 4, 11) |
| §2 Output and messages | WP4b | |
| §3 The package layout and manifest (prose) | WP7 | WP5 (pack test), WP9 |
| §3 `Import-CompleterSet -Name` | WP5 | WP9 |
| §3 `Test-CompleterSet -Name` and `PackageLayout` | WP6 | WP9 |
| §3 `Export-CompleterSet` and the package layout (no change) | none (nothing to build) | existing tests, WP6 (row 1 on another drive) |
| §3 PS_Completers as the reference package | WP10 (owner) | WP9 (check 17 prototype) |
| §2 empty-stem and `-HelpArgument` line-break rejections; §3 set-file name rule (row 3) | WP12 | |
| §4 Documentation, including `.github/copilot-instructions.md` | WP7 | |
| §5 Performance | WP8 | |
| §6 Release | WP11 | |
| §6 Roadmap edits the owner would make | owner (not an agent) | |
| §7 What stays exactly as in 2.1.0 | none (constraint on WP4b to WP6) | existing suite unchanged, WP9 |
| §8 Acceptance criteria, run rules, package isolation | checklist above; choice 10 | |
| §9 question 14 | choice 10 | WP5, WP6 skip reasons |
| Appendix A | out of scope (WPA if question 1 flips) | |
| Appendix B | none (reference counts) | WP9 check 17 (173 entries, 362 targets in the clone) |

No spec section is without a package, and every one of the 22 acceptance checks has a row in the checklist.

## Release recipe for 2.2.0

Decision 7 carried forward: the milestone ships twice from the same code, first `2.2.0-preview1`, then `2.2.0` after a soak without a defect; a defect means `preview2`. The branch keeps `ModuleVersion = '2.1.0'` until the preview release commit, so the release-policy test holds throughout.

Lessons carried over from milestone 1 and the 2.0 releases: join dependent steps with `&&`; check the CHANGELOG heading and the link block before tagging (the rc1 and preview3 gotchas); run Pester in its own process with the Stop preamble; run `release_check` on the tagged HEAD; the remote is `origin`; commits follow the commit rule (one `Co-Authored-By` trailer, no `Claude-Session`). Steps marked **owner** are the owner's; the agent prepares them and stops.

### Preview

1. Run the pre-PR commit check and the documents gate. Open the pull request from `feat/milestone-2-authoring-distribution` to `main` with `gh pr create`. The body carries the WP8 table and spot cost, the WP9 check list with links to the validation files, the departures list, and the owner's answers by gate. It does not restate an exit criterion. **Owner:** review and merge after the checklist is complete and CI is green on all eight legs.
2. On `main` (`git pull origin main`), make the release edits:
   - in `CompleterActions.psd1`, set `ModuleVersion = '2.2.0'` and `Prerelease = 'preview1'`, keeping CR LF;
   - in `CHANGELOG.md`, move the Unreleased entries under `## [2.2.0-preview1] - <date>`, leaving `## [Unreleased]` empty above it;
   - update the link block: `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v2.2.0-preview1...HEAD` and a new `[2.2.0-preview1]: https://github.com/tstager/CompleterActions/compare/v2.1.0...v2.2.0-preview1`.
3. `pwsh -NoProfile -Command "Invoke-Build -Task build"`, then in a separate process `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'`. Then, in the WP9 scratch clone, in its own `pwsh -NoProfile`, run the prototyped package gate with `$env:PSModulePath = "<repo>\build;$env:PSModulePath"`, asserting that `ModuleBase` is `<repo>\build\CompleterActions`. This is check 17's gate against the real preview build.
4. `git commit -am "chore(release): bump module version to 2.2.0-preview1"` with the trailer, then `git status --short` prints nothing (the tracked `build/CompleterActions/CompleterActions.psd1` is in the commit, as in `2086f7f`).
5. Version line, on the release commit and before the tag (check 20): in a new `pwsh -NoProfile`, `Import-Module ./build/CompleterActions/CompleterActions.psd1 -PassThru` reports `Version` 2.2.0 and `PrivateData.PSData.Prerelease` `preview1`.
6. `Select-String -Path CHANGELOG.md -Pattern '^## \[2\.2\.0-preview1\]', '^\[2\.2\.0-preview1\]: .*v2\.1\.0\.\.\.v2\.2\.0-preview1$'` matches both.
7. `git tag v2.2.0-preview1 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`.
8. **Owner:** `git push origin main v2.2.0-preview1`, then `gh run watch` on the Release run. The tag has a hyphen, so the GitHub release is marked as a prerelease.
9. Confirm:
   - `Find-PSResource CompleterActions -Repository PSGallery -Prerelease` lists `2.2.0-preview1`;
   - `gh release view v2.2.0-preview1` shows a prerelease with the preview notes;
   - `Install-PSResource CompleterActions -Prerelease -Repository PSGallery` installs it beside 2.1.0.
10. **Owner:** the roadmap's milestone 2 status row and status line read "Preview shipped <date> as v2.2.0-preview1" (an edit to `docs/roadmap-3.0.md`, which the documents rule keeps from implementers; an agent makes it only on the owner's explicit go-ahead). Update the live roadmap page and its RAG source in place, as for 2.1.0. The §6 roadmap edits stay with the owner.
11. Hand WP10 step 1 to the owner. The soak runs in the owner's profile and on the PS_Completers branch CI.

### Stable

12. After the soak passes without a defect (a defect: fix it on a branch, merge, and repeat steps 2 to 11 as `preview2`), make the release edits on `main`:
    - in `CompleterActions.psd1`, restore `# Prerelease = ''` (commented);
    - in `CHANGELOG.md`, add `## [2.2.0] - <date>` above the preview section with a promotion note in the shape of the 2.1.0 one;
    - the link block: `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v2.2.0...HEAD` and a new `[2.2.0]: https://github.com/tstager/CompleterActions/compare/v2.1.0...v2.2.0`.
13. Build, then Pester with the Stop preamble in a separate process.
14. `git commit -am "chore(release): bump module version to 2.2.0"` with the trailer; `git status --short` prints nothing. Then, before the tag: the built manifest reports 2.2.0 with no `Prerelease` (check 20, stable version line), and `Select-String -Path CHANGELOG.md -Pattern '^## \[2\.2\.0\]', '^\[2\.2\.0\]: .*v2\.1\.0\.\.\.v2\.2\.0$'` matches both.
15. `git tag v2.2.0 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`; then, **owner:** `git push origin main v2.2.0` and `gh run watch`. There is no hyphen, so the GitHub release becomes Latest.
16. Confirm: `Find-PSResource CompleterActions -Repository PSGallery` lists 2.2.0 without a label; `gh release view v2.2.0` shows Latest; `Install-PSResource CompleterActions -Version 2.2.0 -Reinstall` succeeds.
17. **Owner:** the status row reads "2.2.0 released <date>". Milestone 2 is marked shipped only after the owner has published PS_Completers and run the literal exit criterion 2 on PSGallery (WP10 checklist item 5, question 10). Update the live page and RAG source.
18. Hand WP10 steps 2 to 4 to the owner.

## Risks

1. **The probe runs third-party programs.** The residual risks are listed in §2 and documented in WP7: a console shim that starts a GUI program, `--help` read as an operand, `/dev/tty`, and detached descendants. `-WhatIf` names the program, and `-NoProbe` and `-HelpText` avoid all of them.
2. **Windows package isolation does not work as the first draft of the spec wrote it.** A `LOCALAPPDATA` redirect leaves the real store in use (verified). Choice 10 limits registration to Linux and the disposable Windows CI store; question 14.
3. **The plan and the spec are uncommitted.** Until they are on main, the documents gate cannot see an edit. They are committed to main before the branch is cut (owner decisions, "Branching").
4. **.NET 5+ APIs break the 7.0 floor unnoticed.** `Encoding.Latin1`, `WaitForExitAsync`, and `File.SetUnixFileMode` are the likely slips. Every package's review checks `src`. Tests may use 7.4 APIs.
5. **The runner can deadlock or leak.** Choice 1 never blocks without a deadline. WP1 tests the cap, the timeout, held output, and stdin on both OS legs, and asserts afterwards that the held-output descendant is gone.
6. **Timing tests flake on loaded runners.** Assert outcomes and warnings, not durations, except the 3 s held-output bound in WP4a, which leaves about 1.5 s of margin over the measured 0.3 s exit plus 1 s grace. If it flakes, the bound is raised to 5 s in a reviewed commit; it is never skipped or removed. Descendants are stopped in `AfterEach`.
7. **The parser is graded by its own output.** Expected lists are written by hand before the parser runs (WP2), checked by a second reader, and compared with the §2 table; a rule-caused difference stops at state B.
8. **Line endings and binary content.** There is no `.gitattributes`, and autocrlf rewrites checked-in text. Inputs with NUL, lone CR, CR LF variants, or PE headers are built in code at test time, captures are read with `-Raw`, and the golden comparison normalises newlines.
9. **The golden file is linted.** `tests/Fixtures/**/*.ps1` is in the CI Lint scope. The spec's cargo skeleton saved as a `.ps1` gives zero analyzer findings and zero parse errors (lens B check); WP4b runs the linter over the golden file before committing.
10. **Pester in the same process as Invoke-Build or PSScriptAnalyzer** breaks the paging tests. The run steps keep them apart.
11. **`Markdown_templates` overwrites hand-edited help** with `-Force`. New pages are generated one command at a time into scratch.
12. **Runner images differ from the owner's machine.** No test depends on `calc.exe`: the GUI case uses a patched copy of `$env:ComSpec`. `ping.exe` (Windows held-output fixture) is in `System32` on every image. The real `pwsh --help` probe skips with a reason when `pwsh` is not an application on `PATH`, and asserts only the exit code and conformance.
13. **The branch build reports 2.1.0.** Checks that need 2.2.0 by name use the stamped copy and assert `ModuleBase` (WP9).
14. **`Import-CompleterSet` refactor drift.** Choice 8 moves the body. `tests/CompleterSet.Tests.ps1` must pass with an empty `git diff`, and WP9's `-LiteralPath` comparison under both builds is a pull request gate.
15. **The self-check rejects valid help in the field.** The composer escapes every quote form, and parsing rule 5 strips control and format characters. The 14-capture corpus runs through the self-check, and the error text asks for a report.
16. **Module-root enumeration cost on large `PSModulePath` entries.** The spot cost (at most 20 ms) is measured in WP8.
17. **The check 3 alarm turns the preview leg red** the day an engine preview carries the cmdlets. That is the signal for appendix A; open item 1.
18. **The cross-drive test runs only on Windows CI.** Locally the repository and `TestDrive` share a drive, so the test skips; the runner's D: workspace and C: temp make it run there. A green local run does not prove it.
19. **The package-refusal pack test depends on directory order on Linux.** It runs on Windows only; the module-side row 2 test covers every leg.

## Owner decisions by gate

An unanswered item means its default applies. Implementers never stop for an unanswered item; the orchestrator asks the owner before the gate and proceeds with the default when no answer has come. The one exception is the first row: the owner's go-ahead on the plan and the spec is the start signal. The only planned mid-run stop is WP2 state B.

| Due before | Item | Default if unanswered | An answer against the default changes |
| --- | --- | --- | --- |
| Branching | Commit this plan and the spec to main (`docs(roadmap): add the milestone 2 spec and plan`), and confirm the branch name `feat/milestone-2-authoring-distribution` | none: this is the start signal | nothing starts |
| WP1 starts | §9 question 1, engine detection | hold; no WPA | adds WPA after WP6; WPA edits `src/Bootstrap.ps1` after WP1's edit is merged; questions 12 and 13 become due before WPA |
| WP3 starts | §9 question 4, `.exe` added to bare names | the five-suffix rule | WP3's target-list helper and its 9 cases |
| WP5 starts | §9 question 14, package tests on Windows | as §8 and choice 10 | choice 10's Windows condition and WP5's and WP6's skip reasons |
| WP5 starts | §9 question 7, where the set file sits | one subfolder below `ModuleBase` | WP5's resolution step 6 and its failure cases; WP6 row 2 |
| WP4b starts | §9 question 2, output without `-PassThru` | keep `-PassThru` | WP4b's output tests and §2 examples |
| WP4b starts | §9 question 5, probe by default | probe by default | WP4b's parameter sets and default; WP1 and WP4a unchanged |
| WP4b starts | WP2 state B, a rule-caused count difference | no default: WP4b waits for the amendment | the parser rules and the expected lists |
| WP6 starts | §9 questions 8 and 9 | add both | WP6 shrinks as its header says |
| WP7 starts | §9 question 6, where the package layout is documented | `about_Completer_Sets` | WP7's two topics swap the full section and the pointer |
| WP7 starts | Open item 2, `about_CompleterActions_Migration` | leave it | a one-word edit in WP7 |
| Pull request | Open item 1, check 3 as a test | keep the alarm test | the test is removed from WP4b's file before the PR; WP9 checks by hand |
| Release | §6 roadmap edits 1 to 7; §9 questions 3, 10, and 11 | as recommended | the owner's roadmap edits and WP10's timing |
| WP10 step 3 | The PSGallery API key | none: the owner holds it | not applicable |

## Open items for the owner

The plan picks a default for each; "Owner decisions by gate" says when each is due. The first draft's items on the PE subsystem reason, the self-check tail, `-Name` spellings, the trusted-warning order, containment before existence, and the second `.psd1` row are now spec text (departures 3 to 11); Windows package isolation is §9 question 14; the leftover repositories were removed on 2026-10-02.

1. **Check 3 as a test.** Default: a Pester test in `tests/CompleterRegistration.Tests.ps1` asserts that neither cmdlet exists and, when one appears, fails with a message that names appendix A. That turns the preview leg red on the day it matters. Alternative: WP9 checks it by hand and CI runs nothing.
2. **`about_CompleterActions_Migration`** says "thirteen functions (eleven in 2.0.0)", which goes stale at 14. §7 says the topic is unchanged. Default: leave it, per §7, until 3.0 rewrites it. Alternative: a one-word edit.
3. **§9 questions 1 to 14.** The plan follows every recommendation. Question 1 held means no WPA. A "no" to question 8 or 9 removes its part of WP6.

## Estimated new Pester tests

| Package | File | New `It` blocks | Test cases |
| --- | --- | --- | --- |
| WP1 | `tests/CompleterHelpProbe.Tests.ps1` | 15 | 27 |
| WP2 | `tests/CompleterHelpText.Tests.ps1` | 16 | 53 |
| WP3 | `tests/CompleterScaffold.Tests.ps1` | 12 | 41 |
| WP4a | `tests/CompleterHelpProbe.Tests.ps1` | 11 | 19 |
| WP4b | `tests/CompleterScaffold.Tests.ps1`, `tests/CompleterRegistration.Tests.ps1` | 26 (plus 1 modified) | 52 |
| WP5 | `tests/CompleterSetPackage.Tests.ps1` | 26 | 35 |
| WP6 | `tests/CompleterSetPackage.Tests.ps1` | 12 | 22 |
| WP7 | `tests/CompleterActions.Tests.ps1`, `tests/CompleterSetPackage.Tests.ps1` | 4 | 5 |
| Total | | about 122 | about 254 |

That takes the suite from 337 test cases to about 591, across fourteen test files, ten of which exist today. The number is an estimate, not a gate: milestone 1 landed at about 1.6 times its `It` estimate, so a larger count is expected and is not a defect.

591 counts every case across all legs. A single leg reports fewer as Passed and the rest as Skipped:
- **Ubuntu legs** skip the Windows-only cases: WP1 (the pwsh and patched-copy read, five refusals), WP4a (five `/?` cases, the loader-rejected header, two refused-application cases), WP4b (the GUI copy, the `.cmd` marker, the Windows action text), WP5 (the pack refusal), and WP6 (the cross-drive case).
- **Windows legs** skip the Linux-only cases: WP1 (runnable on Linux), WP4a (the execute-bit case and the Linux `/?` case), WP4b (the Linux action text), and WP6 (the unlistable folder). WP6's cross-drive case runs only where the workspace and `TestDrive` are on different drives, which is the Windows runner.
- **The owner's Windows machine** also skips the choice 10 save step (WP5's check 2 test and WP6's saved-copy case) and the cross-drive case.
- **Any leg without PSReadLine** skips the snapshot tests, as the existing three do; **any leg without PSResourceGet 1.1.0** would skip the package tests, which no CI leg lacks today.
