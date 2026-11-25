# Milestone 1 plan: authoring, second pass (3.1.0)

Drafted: 2026-11-25, revised the same day after a review of coverage, facts, collisions, and implementability against the repository
Base: main at `b0aa0be` (3.0.1 stable, release commit `820d224`, tag v3.0.1)
Spec: `docs/roadmap-4.0/milestone-1-spec.md` (accepted 2026-11-25). Section numbers below (§n) point into it.
Roadmap: `docs/roadmap-4.0.md`, milestone 1, decisions 2 and 3 (locked 2026-11-25). Ships first as `v3.1.0-preview1`, then as `v3.1.0` from the same code once the preview has soaked (§11).
Branch: `feat/3.1.0-authoring-second-pass` from main. Its first commit adds this plan, the spec, and the owner's roadmap edits (`docs(roadmap): add the 3.1.0 spec and plan`). That commit is called the docs base below, and the documents gate compares with it.

The plan implements §1 to §12 as written. The owner answered every §14 question on 2026-11-25, each as recommended; "Owner decisions" records the answers.

The spec says what the module does. This plan says how the work is split, in what order, which files each package touches, and how each package is accepted. Where the spec leaves an internal choice open, the plan picks one under "Internal design choices".

## Current-state facts the plan builds on

Read from the file named, or run, on 2026-11-25 at `b0aa0be`. `git diff --stat v3.0.1 HEAD` lists only `.github/workflows/ci.yml`.

- **Exports.** `CompleterActions.psd1` lines 75 to 87 list 11 functions; `AliasesToExport = @()`. `CompleterActions.psm1` exports every `src/Public/*.ps1` base name. The build sets `FunctionsToExport` from `src/Public`, requires each public file to define one top-level function named after the file (`CompleterActions.build.ps1` lines 161 to 165 and 270 to 274), and reads each command's help from the MAML in the built package (lines 343 to 370).
- **Tests that pin the surface.** `tests/CompleterActions.Tests.ps1` lines 1731 to 1754 ("exports exactly the eleven functions and no alias", a hard-coded array and `Should -Be 11`); `tests/CompleterClasses.Tests.ps1` lines 132 to 146 (11 output-type cases) and line 148 (assembly version 3.0.0.0); `tests/CompleterRegistration.Tests.ps1` lines 15 to 28 (manifest list equals `src/Public`) and lines 1066 to 1069 (one help page per exported function plus `CompleterActions.md`); `tests/CompleterActions.Tests.ps1` line 1987 ("describes each parameter of a packaged command in Get-Help as the command declares it"), which fails for any parameter that has no help entry.
- **Help.** `src/docs/CompleterActions/<Command>.md` is the source; the `external_help` task regenerates `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`; `Markdown_templates` would overwrite hand edits and is never run. About topics live in `en-US/`. `build/CompleterActions/**` text files are tracked and rebuilt with the source change.
- **Scaffold.** `src/Public/New-CompleterScript.ps1` (three sets: Probe, HelpText, NoProbe); private `ConvertTo-CompleterTargetName`, `ConvertTo-CompleterScriptStem`, `Resolve-CompleterHelpProbeApplication`, `Get-CompleterPESubsystem`, `Get-CompleterHelpSubcommand`, `Invoke-CompleterHelpProcess`, `ConvertFrom-CompleterHelpOutput`, `ConvertTo-CompleterCleanHelpText`, `ConvertFrom-CompleterHelpText`, `Get-CompleterScriptSkeleton`, `ConvertTo-CompleterSingleQuotedText`, `Save-CompleterScriptFile`. The skeleton's line 2 is chosen on `Subcommand.Count -eq 0` (`Get-CompleterScriptSkeleton.ps1` lines 75 to 90); the `/?` fallback on `subcommands.Count -eq 0` (`Get-CompleterHelpSubcommand.ps1` line 112); `Save-CompleterScriptFile` writes one file through a `<path>.<8 hex>.tmp` and `File.Move`.
- **Tests that pin today's scaffold output.**
  - `tests/CompleterScaffold.Tests.ps1`: `$script:CargoSkeletonTemplate` (lines 9 to 47, the old line 2 at 28), the line-2 cases (200, 206, 212), the old texts at 456 and 457, the rg empty-table test (678 to 692), the golden-file test (694 to 702), the row count by `-clike '            @{ Name = *'` (727), line 869, the verbose and comment texts (1368 to 1370, the `Wrote` assertion at 1369), and the three-line syntax (1373 to 1381). Line 1383 reads the command's comment help from the source module.
  - `tests/CompleterHelpProbe.Tests.ps1` line 848: `Get-TestProbeLinePattern` hard-codes `subcommands, \d+ ms`; the `/?` fallback tests sit near line 1036.
  - `tests/CompleterSetPackage.Tests.ps1` line 1880 asserts line 2 as `the subcommand table was read from`.
  - `tests/Fixtures/NewCompleterScript/cargo_completer.expected.ps1` is the golden file. `tests/CompleterActions.Tests.ps1` line 308 asserts three examples for `New-CompleterScript`.
- **Captures.** `tests/Fixtures/NewCompleterScript/` holds 14 tools (`7z`, `bcdedit`, `cargo`, `docker`, `gh`, `git`, `go`, `kubectl`, `pip`, `rg`, `rustup`, `sc`, `schtasks`, `winget`), each as `<tool>.txt` and `<tool>.names.txt`, with provenance in `CAPTURES.md`. `rg.txt` has 104 option lines at indent 4 under seven column-0 headings and 41 dash lines at indent 8 and 12 that are prose. There is no `du` capture.
- **Sets.** `src/Private/Resolve-CompleterSetModule.ps1` is the only by-name resolver and takes `-Name` only; it returns `Name`, `Version`, `ModuleBase`, `ManifestPath`, `Manifest`, `SetPath`. `Import-CompleterDataFile.ps1` reads at most 131073 bytes, decodes with BOM detection, and returns `OverLimit`, `Data`, `Ast`; it discards the bytes and the encoding. `Resolve-CompleterSetEntry -Verify` reads each script itself and returns the private entry record with `Index`, `DeclaredPath`, `Path`, `DeclaredHash`, `ActualHash`, `Problems`; its problem kinds do not include `DuplicateTarget`. `Get-CompleterSetEntryExtent.ps1` gives each entry's `HashExtent`, the value token. `Get-CompleterSetFinding.ps1` maps problems to findings, makes the duplicate-target check inline with state that spans entries (lines 118 to 139), and scans for `UnlistedScript`. `Import-CompleterDataFile` and `Import-CompleterSetDefinition` take only `-LiteralPath`; the over-limit text for a file on disk is at `Import-CompleterSetDefinition.ps1` line 72, and the text for a set that would be written over the limit is at `Export-CompleterSet.ps1` line 376. `Get-CompleterSetPackage.ps1` lines 86 to 124 loop over the manifests in the folder above the set and return the first whose declaration resolves to it. Nothing in `src` rewrites part of a set file; `Export-CompleterSet` writes with `Set-Content -Encoding utf8`, not atomically.
- **By-name test isolation.** `tests/CompleterSetPackage.Tests.ps1`: `New-TestCompleterSetPackage -Root -Name -Version` (from line 56) and `Join-TestModulePath` (from line 144) build package folders under `$TestDrive` and set `$env:PSModulePath` in `try`/`finally`.
- **Core.** `src/Core/CompleterActions.Core.csproj`: `net8.0`, `TreatWarningsAsErrors`, `GenerateDocumentationFile`, `AssemblyVersion` 3.0.0.0, no `AllowUnsafeBlocks`. Folders `Engine/`, `Grammar/`, `Types/`. No `DllImport` or `LibraryImport` anywhere in `src`. One AnyCPU dll serves every platform.
- **Grammar.** `StrictGrammar.cs` `TestIsSupportedRegisterArgumentAst` (lines 124 to 158) validates `-CommandName` and `-ParameterName` values in one branch; messages live in `GrammarMessages.cs`.
- **The array form in tests.** `tests/Fixtures/ImportCompleterScript/ArrayExpressionCompleter.ps1` line 1 uses `-ParameterName @('Name', 'Path')` and is used at `tests/CompleterAuthorTooling.Tests.ps1` line 74 and `tests/CompleterImporter.Tests.ps1` line 521; `CompleterAuthorTooling.Tests.ps1` line 677 uses the same form inline; lines 633 there and 1142 in `CompleterImporter.Tests.ps1` use it with a redirection.
- **Tests that find `pwsh` by name.** `tests/CompleterHelpProbe.Tests.ps1` `Resolve-TestPwshApplication` (about line 819) and the six tests from line 857; `tests/CompleterScaffold.Tests.ps1` `$script:PwshApplicationPath` (line 455), `Invoke-TestWhatIfChild` (line 623, `& pwsh -NoProfile ...`), and the tests at 858, 884, 1054, 1076, 1150, 1258, and 1347; `tests/CompleterSetPackage.Tests.ps1` lines 1041, 1077, 1248, and 1846. `New-CompleterScript -CommandName` refuses a path, so those tests cannot pass a full path; `Resolve-CompleterHelpProbeApplication -Name` accepts one. `CompleterHelpProbe.Tests.ps1` line 4 already defines `$script:PwshPath = Join-Path $PSHOME pwsh.exe`, the idiom `tests/CompleterRegistration.Tests.ps1` also uses. Six other test files start a plain child `pwsh` by bare name, 21 times; those run correctly through the alias and are out of scope (§8).
- **Suite.** 529 `It` blocks in 13 files (static count). On the owner's machine with the Store alias first on `PATH`, the last recorded full run was 753 passed, 15 failed, 12 skipped; a focused rerun with the real PowerShell directory first left 3 failures, the scaffold `-WhatIf` child tests (`docs/code-review-2026-11-18.md` lines 70 and 71, at the commit before the 18 review fixes).
- **Line endings.** `core.autocrlf` is on and there is no `.gitattributes`; `git ls-files --eol` shows the captures as LF in the index and CR LF in the working tree.
- **CI.** `.github/workflows/ci.yml`: eight legs (Windows and Ubuntu by 7.4, 7.5, 7.6, preview); steps Checkout, Install PowerShell, Show version, Install modules (InvokeBuild 5.14.23, Pester 6.1.0, PSScriptAnalyzer 1.25.0, Microsoft.PowerShell.PlatyPS 1.0.3), Compile, Lint (`./src`, `./tests`), Test, Upload test results, Build. `on:` is lines 3 to 11; only `pull_request` has `paths-ignore`. `release.yml` runs on `v*` tags and runs its own tests.
- **Release check.** The `release_check` task compares only a tag on HEAD (`CompleterActions.build.ps1` lines 489 to 495) and passes silently when HEAD has none.

## Internal design choices

1. **Options are parsed by a new private function.** `src/Private/ConvertFrom-CompleterHelpOption.ps1`, `-Text` in, `{ Name; Description }` rows out, implementing §2 "Finding option sections" and "Reading a row". `ConvertFrom-CompleterHelpText.ps1` is not edited (gate: `git diff main` prints nothing for it), which is how §12's "every capture gives the same subcommand names" is kept. The heading pattern and the commands word list are locals of that file (lines 34 to 40), so the option function carries its own copy of both, with a comment naming the source, and a test asserts the two copies agree on a list of sample headings.
2. **The probe record gains `Options`.** `Get-CompleterHelpSubcommand` keeps its name and gains an `Options` property on its record; its `/?` condition and verbose line change per §2.
3. **The skeleton gains `-Option`.** `Get-CompleterScriptSkeleton -Option <object[]>`; `SeedKind` is required when either table has rows. The 3.0.1 golden file is kept as `tests/Fixtures/NewCompleterScript/cargo_completer.3.0.1.ps1` for §13 check 7, and `cargo_completer.expected.ps1` is regenerated.
4. **One writer for both files.** `Save-CompleterScriptFile` gains optional `-DocumentationLine` and `-DocumentationLiteralPath`. It writes both temporary files, self-checks the script, moves the script, then the markdown file, and owns the §3 failure text. Each move goes through a new private `Move-CompleterScriptFile -LiteralPath -Destination -Force`, which wraps the `File.Move` call that is inline today (line 99), so a test can make the second move fail through `InModuleScope`. The markdown lines come from a new private `Get-CompleterScriptDocumentation -Name -ScriptName -Target`. The check that the `.md` file does not exist sits in `New-CompleterScript`'s `begin` block beside the script's (lines 163 to 166).
5. **The alias reader is one static class in the core.** `src/Core/Interop/AppExecutionAlias.cs`, `CompleterActions.Internal.AppExecutionAlias`, with `public static string? GetTarget(string path)`: `null` when the file is not an `APPEXECLINK` reparse point or cannot be read, the empty string when it is one with no third string, otherwise the target path.
   - `DllImport` of `CreateFileW` and `DeviceIoControl` from `kernel32.dll`, with `SafeFileHandle` and a 16384-byte managed buffer. No `unsafe`, no `AllowUnsafeBlocks`, no `LibraryImport`.
   - The method returns `null` at once when `OperatingSystem.IsWindows()` is false; the native declarations carry `[SupportedOSPlatform("windows")]`.
   - The tag is compared as `uint` (spec appendix A).
   - PowerShell reaches it through a new private `Get-CompleterAppExecutionAliasTarget -LiteralPath`, one line around the static call, so a test can count or replace it. `Resolve-CompleterHelpProbeApplication.ps1` calls that function only inside its existing `$IsWindows` branch, only after `Get-CompleterPESubsystem` returned `$null` for a `.exe`, and applies §7's rules. Its record keeps `Name`, `Path`, `CanRun`, `Warning` and gains `AliasTarget`.
   - This is the first P/Invoke in the module; the rule "no P/Invoke" of the 3.0 plan is narrowed to "none outside `src/Core/Interop/`". A scratch class of this shape built with zero warnings under the project's settings and returned the real target for the `pwsh` alias and null for `cmd.exe` (plan review, 2026-11-25).
6. **Version selection lives in the resolver.** `Resolve-CompleterSetModule` gains `-MinimumVersion` and `-RequiredVersion` (`[version]`), collects every version folder it sees for the not-found list, and is otherwise unchanged when neither is given. The two public commands validate the mutual exclusion and the one-name rule before any name resolves.
7. **`Update-CompleterSet` reads the set once and shares Test's judgement.**
   - **One read.** `Import-CompleterDataFile` gains a switch `-IncludeSource` that adds `Bytes`, `Text`, and `Encoding` (with whether a preamble was present) to its record; without the switch its output is unchanged. `Import-CompleterSetDefinition` passes it through under a parameter of its own.
   - **One classification.** The per-entry work of `Get-CompleterSetFinding.ps1`, which is `Resolve-CompleterSetEntry -Verify`, the duplicate-target check with its cross-entry state, and the unlisted-script scan, moves into a new private `Get-CompleterSetEntryState` that returns one record per entry (the entry record plus its duplicate-target problems and its extents) and the unlisted scripts. `Get-CompleterSetFinding` maps that to findings exactly as before (gate: `tests/CompleterSetDrift.Tests.ps1` unchanged and passing); `Update-CompleterSet` reads eligibility from it. An entry with a `DuplicateTarget` is therefore refused, which `-Verify` alone would not see.
   - **The splice** is a private `Set-CompleterSetHashText -Text -Replacement`, which takes extents and new values and returns the new text, last offset first. Check 11 replaces it through `InModuleScope`.
   - **The re-parse** of the new text uses `Parser.ParseInput` and the same safe evaluation the reader uses, through a `-Text` parameter set added to `Import-CompleterDataFile`.
   - **The over-limit text** is `Export-CompleterSet.ps1` line 376's, moved into a private helper both commands call, so the wording has one source.
   - **The write** goes through a private `Save-CompleterSetFile -Bytes -LiteralPath` (temporary file beside the set, then a replacing move).
8. **`-InputObject` is typed.** `[CompleterActions.CompleterScriptFinding[]]`, `ValueFromPipeline`, in its own parameter set, so a finding binds there and a string or a `FileInfo` binds to `-Path`.
9. **Bad declarations are collected, and the search goes on.** In `Get-CompleterSetPackage`, the path exception at line 113 is caught, `{ ManifestPath; Reason }` is added to a list, and the loop continues to the next manifest. The function returns the real package record with a `DeclarationProblems` list, or, when no manifest declares the set but the list is not empty, a record with a null `ManifestPath` and only the list. `Get-CompleterSetPackageFinding` emits one §8 row per list item first and runs its four existing checks only when `ManifestPath` is set, so a set that no manifest declares gains no other row. The call site in `Get-CompleterSetFinding.ps1` (line 160) needs no edit, which keeps WP2 and WP7 apart. `Resolve-CompleterSetModule` catches the same two exception types at line 217 and throws the declaration error. Both, and the `does not exist` error at line 221, show the value through one private `ConvertTo-CompleterPrintableText`.
10. **Reserved names.** `$__CompleterActionsScriptInfo` and `$script:__CompleterActionsCapturedDefinitions`, exactly as §8 gives them.
11. **Pinned `pwsh`.** The three test files use the idiom the suite already has, `$script:PwshPath = Join-Path $PSHOME 'pwsh.exe'` on Windows and `Join-Path $PSHOME 'pwsh'` elsewhere. In those files, children start as `& $script:PwshPath -NoProfile ...`. A test that must hand the bare name to `New-CompleterScript` puts `$PSHOME` first on `$env:PATH` in `try`/`finally`, and every child script that probes does the same in its first line, because a child `pwsh` re-orders `PATH` on startup (spec appendix A). Expected strings are built from the pinned path. Plain child launches in the six other test files are not touched.
12. **One new test file,** `tests/CompleterSetUpdate.Tests.ps1`. Everything else extends the existing files.
13. **Validation records** go in `docs/roadmap-4.0/validation/`: `milestone-1-benchmark.md` (WP11) and `milestone-1-runtime.md` (WP12).

## Work packages

### Rules for every package

These rules go verbatim into every implementer and validator prompt. Reviewers check each one.

- **Documents.** Implementers never edit `docs/roadmap-4.0.md`, `docs/roadmap-4.0/milestone-1-spec.md`, or `docs/roadmap-4.0/milestone-1-plan.md`, and never restate a roadmap exit criterion anywhere: not in the docs, the changelog, the pull request, or a commit message. A spec or plan defect is reported to the orchestrator, not fixed. Gate, in every package review: `git diff <docs base> -- docs/roadmap-4.0.md docs/roadmap-4.0/milestone-1-spec.md docs/roadmap-4.0/milestone-1-plan.md` prints nothing, where the docs base is the feature branch's first commit. §11's roadmap edits are the owner's and are in that commit.
- **Worktrees and merges.** Each package runs in its own git worktree on its own branch `m31/<wp>`, cut from the feature branch after the packages it depends on are merged there. The orchestrator merges into the feature branch in the order given under "Order and parallelism". After every merge, conflict or not, it takes the feature branch's side of the generated files (`git checkout --ours -- build src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml` when they conflict), re-runs the build, and commits the result as `chore(build): rebuild after merging <wp>`. A conflict anywhere else goes back to the later package. The build script takes the module name from its folder leaf, so a worktree is reached through a junction named `CompleterActions`, and `git -c core.longpaths=true worktree add` is needed for deep paths. A junction is removed without following it before any recursive delete.
- **Run steps.** Invoke-Build, PSScriptAnalyzer, and Pester are three separate processes, in this order. No `pwsh` on the machine may hold the repository build imported before step 1, because a loaded `CompleterActions.Core.dll` is locked.
  1. `pwsh -NoProfile -Command "Invoke-Build -Task build"`. It compiles first.
  2. `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"` prints nothing.
  3. `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes.

  During work an implementer may run only the package's own test file after step 1. Reviewers run the three steps, in order, on the package branch.
- **Help with the parameter.** A package that adds a parameter or a command adds its entry to that command's page under `src/docs/CompleterActions/` and to the command's comment help in `src/Public/`, in the same package: the parameter-help test fails without the first, and the source layout serves the second. WP9 writes the prose, examples, and about topics.
- **C#.** `dotnet build` with zero warnings. Every public member has a doc comment. No `unsafe`. No P/Invoke outside `src/Core/Interop/`. The `System.Management.Automation` reference stays 7.4.0 and `AssemblyVersion` stays 3.0.0.0.
- **Linux.** Every package's tests pass locally on Windows. Linux is proven under WSL or by the first CI run on a draft pull request; the review note records which.
- **Commits.** Conventional commits with a parenthesised scope and an imperative summary (`feat(scaffold): ...`, `feat(sets): ...`, `fix(grammar): ...`, `test(probe): ...`, `docs(help): ...`, `chore(ci): ...`). Each message ends with exactly one trailer line, `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`, and nothing else. No `Claude-Session` trailer. A harness suggestion naming another model is ignored; a branch that arrives with another line is normalised by the orchestrator before it is merged. Pre-PR check:

  ```powershell
  git log main..HEAD --format=%B | Select-String -Pattern '^Co-Authored-By:' | ForEach-Object Line | Sort-Object -Unique   # exactly one line
  @(git log main..HEAD --format=%B | Select-String -Pattern 'Claude-Session').Count                                      # 0
  ```
- **Files.** Commit `build/` text files and the regenerated help XML with the source change they come from; never commit `lib/`, `bin/`, `obj/`, or a `.dll`. Keep CR LF and UTF-8 without a BOM in every edited text file. No scratch file in the repository.
- **Tests.** Every test that reads the error stream passes `-ErrorAction Continue` to the command under test, because CI runs Pester with `$ErrorActionPreference = 'Stop'`. No test reads or writes the real PS_Completers repository or the PSResourceGet store. A test that asserts bytes, line endings, or a byte-order mark writes its input with `[System.IO.File]::WriteAllBytes` into the test drive, because `core.autocrlf` rewrites checked-in fixtures. Every platform skip uses `-Skip:` or `Set-ItResult -Skipped -Because '<reason>'` with the reason the spec's check gives, word for word. No new test hands the bare name `pwsh` to the probe, or starts a child that does, without the pin of choice 11.
- **Unchanged files.** Where a package says a file is unchanged, its gate is `git diff main -- <file>` printing nothing.

### WP1 Grammar and capture fixes

Owns §8 "An array given to -ParameterName" and "Names in the capture scope". Day one.

Files: `src/Core/Grammar/StrictGrammar.cs` (the array check for `ParameterName` in `TestIsSupportedRegisterArgumentAst`, after the existing literal-value check, per §8 "Order"), `src/Core/Grammar/GrammarMessages.cs` (the new message and hint, and the `-ParameterName` variant of the literal-string hint), `src/Private/Import-CompleterScriptDefinition.ps1` (choice 10; the function's `[string[]] $ParameterName` stays), `src/docs/CompleterActions/Import-CompleterScript.md` lines 84 to 86 and the matching comment help in `src/Public/Import-CompleterScript.ps1` (line 32), `tests/Fixtures/ImportCompleterScript/ArrayExpressionCompleter.ps1` (its array moves to `-CommandName`, so the tests that used it for the array shape keep their intent), a new fixture for the refused form, two new fixtures for check 18, `tests/CompleterAuthorTooling.Tests.ps1`, `tests/CompleterImporter.Tests.ps1`.

Done when: check 15 and check 18 pass as Pester tests; the two redirection tests (lines 633 and 1142) pass with their expected message unchanged; `Get-ChildItem src -Recurse -File | Select-String -Pattern '\$ScriptInfo\b|CapturedCompleterDefinitions'` matches only the reserved names.

### WP2 Set path fixes

Owns §8 "The output path of Export-CompleterSet" and "A bad path in PrivateData.CompleterSet". Day one.

Files: `src/Public/Export-CompleterSet.ps1` (the `begin` block only), `src/Private/Resolve-CompleterSetModule.ps1` (lines 217 and 221), `src/Private/Get-CompleterSetPackage.ps1` (the loop at lines 86 to 124), `src/Private/Get-CompleterSetPackageFinding.ps1`, new `src/Private/ConvertTo-CompleterPrintableText.ps1` (choice 9), `tests/CompleterSet.Tests.ps1`, `tests/CompleterSetPackage.Tests.ps1`. `src/Private/Get-CompleterSetFinding.ps1` is not edited by this package.

Done when: checks 16 and 17 pass as Pester tests, with the platform skips and reasons those checks give; on Windows the registry is unchanged after the provider test (the test reads the key before and after); every existing `PackageLayout` test passes unchanged.

### WP3 Pinned tests, then the alias probe

Owns §8 "Tests that find pwsh by name" and §7. Day one. Two commits at least, in this order, so the pin is reviewable without the feature.

Step 1, tests only: choice 11 across `tests/CompleterHelpProbe.Tests.ps1`, `tests/CompleterScaffold.Tests.ps1`, `tests/CompleterSetPackage.Tests.ps1`, and their child scripts. Done when the three files pass on the owner's machine with the Store alias first on `PATH`, with no `src` change.

Step 2, the feature: new `src/Core/Interop/AppExecutionAlias.cs` and new `src/Private/Get-CompleterAppExecutionAliasTarget.ps1` (choice 5), `src/Private/Resolve-CompleterHelpProbeApplication.ps1`, `src/Public/New-CompleterScript.ps1` (the one new verbose line after line 204), `tests/CompleterHelpProbe.Tests.ps1` (a test helper that writes an `APPEXECLINK` reparse point with `FSCTL_SET_REPARSE_POINT`, compiled with `Add-Type` inside the test file, and removes it in `AfterEach`).

Done when: check 14 passes on Windows and skips nothing there but the `winget` case where `winget` is not an alias; on Ubuntu the crafted-alias cases skip with the check's reason and the wrapper's call count is 0; check 19 holds for the three files.

### WP4 Option parser and captures

Owns §2 "Finding option sections" and "Reading a row". Day one.

The package first takes the `du` capture (§14 question 2): `wsl gnudu --help` on the owner's machine, GNU coreutils 9.5, stored as `du.txt` with its version and command in `CAPTURES.md`, and an empty `du.names.txt`. Plain `du` there is the uutils rewrite and is not what is captured. If `gnudu` is missing, the package stops and reports it.

Files: new `src/Private/ConvertFrom-CompleterHelpOption.ps1` (choice 1), fifteen new `tests/Fixtures/NewCompleterScript/<tool>.options.txt` files (one name per line, in order; empty for a tool with no rows), `tests/Fixtures/NewCompleterScript/du.txt` and `du.names.txt`, `tests/Fixtures/NewCompleterScript/CAPTURES.md`, `tests/CompleterHelpText.Tests.ps1`.

The expected-options files are written by hand from the help, before the parser is run against them, as `CAPTURES.md` records for the names files. The spec's table gives the name counts the review's prototype found, as a cross-check. A capture where the §2 rules give a row that is not an option, or miss an option the rules were meant to reach, is reported to the orchestrator as a spec question before any rule is bent; the report lists the lines.

Done when: check 5 passes; the parser half of check 4 passes (names equal each `.options.txt`); `git diff main -- src/Private/ConvertFrom-CompleterHelpText.ps1` prints nothing; the existing names test passes unchanged.

### WP5 Scaffold: tables, completion, and -Documentation

Owns §2 "The generated script" and "Probe and messages", and §3. After WP3, WP4, and WP8 (check 6 uses `-TargetOnly`).

Files: `src/Private/Get-CompleterScriptSkeleton.ps1` (choice 3), `src/Private/Get-CompleterHelpSubcommand.ps1` (choice 2), `src/Private/Save-CompleterScriptFile.ps1`, new `src/Private/Move-CompleterScriptFile.ps1` and `src/Private/Get-CompleterScriptDocumentation.ps1` (choice 4), `src/Public/New-CompleterScript.ps1` (`-Documentation`, the wiring, the `.md` exists check, the action texts, the two verbose lines, and the comment help), `src/docs/CompleterActions/New-CompleterScript.md` (the parameter entry), `tests/Fixtures/NewCompleterScript/cargo_completer.expected.ps1` and the kept `cargo_completer.3.0.1.ps1`, `tests/CompleterScaffold.Tests.ps1` (every pinned line the facts list), `tests/CompleterHelpProbe.Tests.ps1` (line 848's pattern and the `/?` fallback tests), `tests/CompleterSetPackage.Tests.ps1` (line 1880), `tests/CompleterActions.Tests.ps1` line 308 if the example count changes here.

Done when: checks 1 (Pester form), 4, 6, 7, 8, and 9 pass; every capture's output passes `Test-CompleterScript`.

### WP6 Version selection

Owns §4. After WP2, which edits the same resolver.

Files: `src/Private/Resolve-CompleterSetModule.ps1` (choice 6, including §4's rule that the unversioned layout is a candidate beside the version folders when a version parameter is given), `src/Public/Import-CompleterSet.ps1`, `src/Public/Test-CompleterSet.ps1`, their two help pages and comment help (parameter entries), `tests/CompleterSetPackage.Tests.ps1`.

Done when: check 2 passes in its Pester form, every bullet of it; every existing resolution test (lines 273 to 543) passes unchanged.

### WP7 Update-CompleterSet

Owns §5. Day one.

Files: new `src/Public/Update-CompleterSet.ps1`, `src/Private/Import-CompleterDataFile.ps1` and `Import-CompleterSetDefinition.ps1` (choice 7; default output unchanged), `src/Private/Get-CompleterSetFinding.ps1` (its per-entry work moves to `Get-CompleterSetEntryState`; findings unchanged), new `src/Private/Get-CompleterSetEntryState.ps1`, `Set-CompleterSetHashText.ps1`, `Save-CompleterSetFile.ps1`, and the over-limit text helper, `src/Public/Export-CompleterSet.ps1` (line 376 only, to call that helper; the text is unchanged), `CompleterActions.psd1` (`FunctionsToExport`), new `src/docs/CompleterActions/Update-CompleterSet.md` and the list in `CompleterActions.md`, new `tests/CompleterSetUpdate.Tests.ps1`, `tests/CompleterActions.Tests.ps1` (the export test becomes twelve), `tests/CompleterClasses.Tests.ps1` (a twelfth output-type case).

WP2 edits the `begin` block of `Export-CompleterSet.ps1` and this package edits one line near 376; the hunks are apart.

Done when: checks 3 (Pester form), 10, 11, and 12 pass, including the `DuplicateTarget` and trusted rows of check 10; `tests/CompleterSetDrift.Tests.ps1` passes unchanged; `git diff main -- src/Private/Resolve-CompleterSetEntry.ps1` prints nothing for this package.

### WP8 -TargetOnly

Owns §6. Day one.

Files: `src/Public/Test-CompleterRegistration.ps1`, its help page (the parameter entry and example 3), `tests/CompleterAuthorTooling.Tests.ps1`.

Done when: check 13 passes.

### WP9 Documentation and the cross-feature test

Owns §9 and checks 20 and 22. After every code package is merged.

Files: the help pages of §9 and the matching comment help, `en-US/about_Completer_Sets.help.txt`, `en-US/about_Import_Completers.help.txt` (including the "leaves nothing at the path" qualifier at line 269 and its two twins in the `New-CompleterScript` help), `README.md`, `.github/copilot-instructions.md` (lines 6 and 8, eleven becomes twelve), `CHANGELOG.md` (Unreleased), `docs/roadmap-3.0/milestone-2-spec.md` lines 130 and 139 with a dated note, `tests/CompleterActions.Tests.ps1` (help-content assertions), `tests/CompleterSetPackage.Tests.ps1` (the PSReadLine test).

Done when: checks 20 and 22 pass; the changelog lists the four changes of §1 under Changed; `Get-Help` for all twelve commands resolves from the build.

### WP10 CI trigger

Owns §8 "CI on docs-only pushes". Day one. One file, `.github/workflows/ci.yml`: the `paths-ignore` list under `push:` and the comment above it.

Done when: the file is valid YAML and the two triggers carry the same list. Check 26's first half is the first CI run on the feature pull request; its second half is seen after the merge.

### WP11 Import-time non-regression (validator step)

Owns §10 and check 24. After WP9. Commits only `docs/roadmap-4.0/validation/milestone-1-benchmark.md`, on the feature branch. The baseline is `git archive v3.0.1 | tar -x -C <scratch>\v3.0.1\CompleterActions` (the folder must be named `CompleterActions`, because the build script takes the module name from it), then `Invoke-Build -Task compile` there, which fills `build\CompleterActions\lib`; the baseline path is `<scratch>\v3.0.1\CompleterActions\build\CompleterActions`. A `LazyNoHash` median above 1.05 across four runs stops the milestone before the pull request.

### WP12 Runtime validation (validator step)

After WP9, with the `powershell-runtime-validator` agent. Commits only `docs/roadmap-4.0/validation/milestone-1-runtime.md`. It runs, in fresh `pwsh -NoProfile` processes against the branch build and under the run rules of §13:

- the owner forms of checks 1, 2, 3, and 14 (ripgrep, the installed PS_Completers, the scratch clone, `winget`);
- check 19, the full suite on the owner's machine with the Store alias first on `PATH`;
- check 21's parameter comparison against the 3.0.1 build;
- check 23, the PS_Completers suite and strict import under the branch build;
- the two reported `Update-CompleterSet` times of §10.

A row that fails as specified is recorded as a failure and reported; the validator does not change a check to make it pass.

### WP13 Pull request and release 3.1.0 (owner-run, agent-assisted)

See "Release recipe for 3.1.0". The pull request body carries the WP11 table, the WP12 row list with a link to the validation file, any departures from this plan, and a pointer to "Owner decisions". It does not restate an exit criterion.

## Order and parallelism

```text
Day one, in parallel:  WP1  WP2  WP3  WP4  WP7  WP8  WP10
Then:                  WP5 (after WP3, WP4, and WP8)   WP6 (after WP2)
Then:                  WP9
Then:                  WP11, WP12
Then:                  WP13
```

Merge order into the feature branch: WP10, WP1, WP2, WP8, WP3, WP4, WP7, WP6, WP5, WP9. WP11 and WP12 commit on the feature branch itself.

Files touched by more than one package, and why the order is safe:

| File | Packages | Note |
| --- | --- | --- |
| `tests/CompleterAuthorTooling.Tests.ps1` | WP1, WP8 | different `Describe` blocks |
| `tests/CompleterSetPackage.Tests.ps1` | WP2, WP3, WP5, WP6, WP9 | WP2 and WP3 edit different hunks; WP5, WP6, and WP9 are cut after them |
| `tests/CompleterScaffold.Tests.ps1` | WP3, WP5 | WP5 is cut after WP3 |
| `tests/CompleterHelpProbe.Tests.ps1` | WP3, WP5 | WP5 is cut after WP3 |
| `tests/CompleterActions.Tests.ps1` | WP5, WP7, WP9 | different tests |
| `src/Public/New-CompleterScript.ps1` | WP3, WP5 | WP5 is cut after WP3 |
| `src/Public/Export-CompleterSet.ps1` | WP2, WP7 | the `begin` block against one line near 376 |
| `src/Private/Resolve-CompleterSetModule.ps1` | WP2, WP6 | WP6 is cut after WP2 |
| `src/Core/` | WP1, WP3 | different folders, no project-file edit |
| The command help pages and comment help | each code package, then WP9 | WP9 is cut after every code package |
| `build/`, the help XML | all | regenerated after each merge |

## Verification checklist

- [ ] The documents gate prints nothing on the feature branch.
- [ ] The pre-PR commit check gives exactly one trailer line and no `Claude-Session`.
- [ ] Every §13 check below has passed where it is marked.

| §13 check | Where it is verified |
| --- | --- |
| 1 An option-only tool is seeded | WP5 Pester; WP12 (owner form) |
| 2 A set is selected by version | WP6 Pester; WP12 (installed PS_Completers) |
| 3 Drift is repaired in place | WP7 Pester; WP12 (scratch clone, `git diff`) |
| 4 Captures | WP4 (names), WP5 (outputs, golden file) |
| 5 Option rules | WP4 Pester |
| 6 Every output conforms and works | WP5 Pester |
| 7 Probe and messages; 3.0.1 script still works | WP5 Pester |
| 8 Self-check | WP5 Pester |
| 9 `-Documentation` files | WP5 Pester |
| 10 What is updated | WP7 Pester |
| 11 Bytes | WP7 Pester |
| 12 Binding and surface of `Update-CompleterSet` | WP7 Pester |
| 13 `-TargetOnly` | WP8 Pester |
| 14 Alias resolution | WP3 Pester; WP12 (`winget`) |
| 15 `-ParameterName` arrays | WP1 Pester; WP12 (PS_Completers scan, with check 23) |
| 16 Export output path | WP2 Pester |
| 17 Bad declaration | WP2 Pester |
| 18 Capture names | WP1 Pester |
| 19 Tests are pinned | WP3 step 1; WP12 (full suite on the owner's machine) |
| 20 Help content | WP9 Pester |
| 21 Surface | WP7 Pester (12 functions); WP12 (comparison with 3.0.1); release recipe (version lines) |
| 22 PSReadLine | WP9 Pester |
| 23 PS_Completers under the branch build | WP12 |
| 24 Performance | WP11 |
| 25 Suite, lint, zero compiler warnings, eight CI legs | every package's run steps; PR CI |
| 26 CI trigger | WP10 (pull-request half); after the merge (push half) |

### Traceability: spec section to work package

| Spec section | Owner WP | Verified by |
| --- | --- | --- |
| §1 scope | none (summary) | WP12 (check 21) |
| §2 finding sections, reading a row | WP4 | WP5 |
| §2 the generated script, probe and messages | WP5 | WP12 |
| §3 `-Documentation` | WP5 | |
| §4 version selection | WP6 | WP12 |
| §5 `Update-CompleterSet` | WP7 | WP12 |
| §6 `-TargetOnly` | WP8 | |
| §7 app execution aliases | WP3 | WP12 |
| §8 `-ParameterName` array, capture names | WP1 | WP12 |
| §8 export output path, bad declaration | WP2 | |
| §8 tests that find `pwsh` by name | WP3 | WP12 |
| §8 stems that differ only by case | WP9 (help only) | |
| §8 CI on docs-only pushes | WP10 | after the merge |
| §9 documentation | WP9 (parameter entries in each code package) | |
| §10 performance | WP11 | |
| §11 release | WP13 | |
| §11 roadmap edits the owner would make | owner (not an agent) | |
| §12 what stays | none (constraint on every package) | existing suite, WP12 |
| §13 acceptance criteria | checklist above | |
| §14 questions | answered | "Owner decisions" |

Every one of the 26 checks has a row, and no spec section is without a package.

## Release recipe for 3.1.0

The branch keeps `ModuleVersion = '3.0.1'` until the preview release commit. Release commits reach main through a pull request, as 3.0.1 did; the tag is pushed after the merge. Steps marked **owner** are the owner's; the agent prepares them and stops. Dependent steps are joined with `&&`. The remote is `origin`.

### Preview

1. Run the pre-PR commit check and the documents gate. Open the pull request from `feat/3.1.0-authoring-second-pass` to `main`. **Owner:** review and merge after the checklist is complete and CI is green on all eight legs.
2. On a branch `release/3.1.0-preview1` from the merged main:
   - in `CompleterActions.psd1`, set `ModuleVersion = '3.1.0'` and `Prerelease = 'preview1'`, keeping CR LF;
   - in `CHANGELOG.md`, move the Unreleased entries under `## [3.1.0-preview1] - <date>`, leaving `## [Unreleased]` empty above it;
   - in the link block, `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v3.1.0-preview1...HEAD` and a new `[3.1.0-preview1]: https://github.com/tstager/CompleterActions/compare/v3.0.1...v3.1.0-preview1`.
3. `pwsh -NoProfile -Command "Invoke-Build -Task build"`, then in a separate process the Pester run with the Stop preamble.
4. Commit as `chore(release): bump module version to 3.1.0-preview1` with the trailer; `git status --short` prints nothing.
5. Before the tag: the built manifest reports 3.1.0 with `Prerelease` `preview1`; the assembly version is 3.0.0.0; `Select-String -Path CHANGELOG.md -Pattern '^## \[3\.1\.0-preview1\]', '^\[3\.1\.0-preview1\]: .*v3\.0\.1\.\.\.v3\.1\.0-preview1$'` matches both.
6. Open the release pull request. It is not docs-only, so CI runs. **Owner:** merge.
7. After `git pull origin main`, on main at the merge commit: `git tag v3.1.0-preview1 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`. The tag must be on HEAD, because `release_check` compares only a tag on HEAD and passes silently when there is none. **Owner:** `git push origin v3.1.0-preview1`, then `gh run watch` on the Release run.
8. Confirm: `Find-PSResource CompleterActions -Repository PSGallery -Prerelease` lists `3.1.0-preview1`; `gh release view v3.1.0-preview1` shows a prerelease with the preview notes; `Install-PSResource CompleterActions -Prerelease` installs it, after closing every `pwsh` that holds the installed core assembly (`Get-Process pwsh` and its modules); the first PS_Completers CI run after the publish installed it and passed. A red run there is attributed before it counts as a defect: rerun that suite locally against the installed preview and against 3.0.1.
9. **Owner:** the roadmap's milestone 1 row reads "Preview shipped <date> as v3.1.0-preview1". Update the live roadmap page and its RAG source.
10. The soak runs in the owner's profile and on the PS_Completers CI.

### Stable

11. After the soak passes without a defect (a defect: fix on a branch, merge, repeat steps 2 to 10 as `preview2`), on a branch `release/3.1.0`: restore the commented `# Prerelease = ''`; add `## [3.1.0] - <date>` above the preview section with a promotion note in the shape of the 3.0.1 one; link block `[Unreleased]: .../compare/v3.1.0...HEAD` and `[3.1.0]: .../compare/v3.0.1...v3.1.0`.
12. Build, then Pester in a separate process. Commit as `chore(release): bump module version to 3.1.0`; check the version line and the two changelog patterns as in step 5.
13. Release pull request; **owner:** merge. Then, after `git pull origin main`, on the merge commit: `git tag v3.1.0 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`; **owner:** `git push origin v3.1.0` and `gh run watch`.
14. Confirm: `Find-PSResource CompleterActions -Repository PSGallery` lists 3.1.0 without a label; `gh release list` shows it as Latest; `Install-PSResource CompleterActions -Version 3.1.0 -Reinstall` succeeds and imports.
15. **Owner:** the status row reads "3.1.0 released <date>"; make the §11 roadmap edits not yet made. Update the live page and RAG source.

## Risks

1. **The option heuristic reads prose as options, or misses options.** The rules are checked against fifteen real captures with hand-reviewed expected files before the parser is accepted, and WP4 reports a mismatch as a spec question. The rows are data in a generated file an author is expected to read; a wrong row cannot break conformance, which the self-check guards.
2. **The generated output changes for every tool with an option section.** The golden file, the template, and six pinned expectations in `tests/CompleterScaffold.Tests.ps1` change in WP5. The 3.0.1 golden file is kept as a fixture so that "an old script still works" is tested, not assumed.
3. **Rehashing hides a target change.** §5 refuses any entry with an Error problem, and check 10 has a row for it. A reviewer must see that row fail when the condition is removed.
4. **A rewrite changes bytes it should not.** The splice never splits lines, the round-trip guard refuses a file it cannot reproduce, the result is parsed again before it is written, and check 11 compares bytes for five file shapes.
5. **The first P/Invoke.** It is one class, called only on Windows, only after a header read has already failed, with no `unsafe`. A wrong buffer layout shows up in check 14's crafted aliases. The Ubuntu legs prove the declaration is inert there.
6. **Crafted reparse points left behind by a test.** `AfterEach` removes them, and the test folder is under `$TestDrive`. If Pester cannot remove one, the test fails loudly; it must not be silenced.
7. **`winget` is absent or not an alias on a CI runner.** The end-to-end alias test skips there with the given reason; the crafted-alias tests cover the decision logic on every Windows leg, and WP12 covers the real alias on the owner's machine.
8. **The array finding refuses a script that imports today.** No PS_Completers script uses the form (spec appendix A), `-Trusted` still imports one, and the owner chose the Error knowing this (§14 question 7). WP12 scans the scratch clone.
9. **A child `pwsh` re-orders `PATH`.** Choice 11 pins inside the child script, not only in the parent. Check 19 is run on the one machine where the problem shows.
10. **A package forgets a help entry.** The parameter-help test fails on that package's own branch, which is why the rule puts the entry in the code package.
11. **`Markdown_templates` overwrites hand-edited help.** It is never run.
12. **A locked assembly blocks the build.** Close the `pwsh` that holds it, then rerun; never retry in a loop.
13. **The build fails once in a fresh worktree under OneDrive** with `being used by another process` (seen 2026-11-24, cause not confirmed). One retry is allowed and is recorded in the review note; a second failure is investigated.
14. **A docs-only commit on main has no CI at all** after WP10. That is the owner's ruling. A release commit is never docs-only, and the release workflow runs the suite itself.
15. **The branch build reports 3.0.1.** Checks that need 3.1.0 by name are the release recipe's, on the release commits.

## Owner decisions

All made on 2026-11-25. Nothing is open before the pull request.

| Item | Decision | Package it binds |
| --- | --- | --- |
| §14 question 1, an off switch for option seeding | none | WP5 |
| §14 question 2, the `du` capture | add it, from GNU `du` | WP4 |
| §14 question 3, the markdown content | title, `## What it completes`, one sentence | WP5 |
| §14 question 4, version parameters on `Test-CompleterSet` | both commands | WP6 |
| §14 question 5, entries without a `Hash` | warn, do not add | WP7 |
| §14 question 6, the command's output | `-PassThru` files only, no new type | WP7 |
| §14 question 7, the array finding's severity | Error | WP1 |
| §14 question 8, a bad declaration | the declaration error by name, a `PackageLayout` row by path | WP2 |
| §14 question 9, `AssemblyVersion` | stays 3.0.0.0 | every package |
| §14 question 10, the roadmap edits | made now, in the docs base commit | none (owner's edits) |
| §14 question 11, trusted entries | rehash, with a warning each | WP7 |
| The branch name | `feat/3.1.0-authoring-second-pass` | all |
| Who implements | a workflow: one Opus implementer per package in its own worktree, adversarial review by Sonnet and by Haiku, a fix round, an orchestrated merge, and one final review of the whole branch by Fable | all |

Left for the owner after the workflow: the review and merge of the pull request, and every release step marked **owner**.

## Estimated new Pester tests

| Package | File | New `It` blocks (estimate) |
| --- | --- | --- |
| WP1 | `CompleterAuthorTooling`, `CompleterImporter` | 6, plus 3 modified |
| WP2 | `CompleterSet`, `CompleterSetPackage` | 8 |
| WP3 | `CompleterHelpProbe`, `CompleterScaffold`, `CompleterSetPackage` | 8, plus about 15 modified |
| WP4 | `CompleterHelpText` | 10 |
| WP5 | `CompleterScaffold` | 16, plus 6 modified |
| WP6 | `CompleterSetPackage` | 9 |
| WP7 | `CompleterSetUpdate` (new), `CompleterActions`, `CompleterClasses` | 24, plus 2 modified |
| WP8 | `CompleterAuthorTooling` | 4 |
| WP9 | `CompleterActions`, `CompleterSetPackage` | 5 |
| Total | | about 90 |

That takes the suite from 529 `It` blocks in 13 files to about 620 in 14. The number is an estimate, not a gate; the earlier milestones all landed above theirs.
