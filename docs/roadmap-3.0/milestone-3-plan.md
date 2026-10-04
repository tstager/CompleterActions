# Milestone 3 plan: compiled core and the engine boundary (3.0.0)

Drafted: 2026-10-03, revised the same day after three reviews (spec coverage and consistency; implementability against the codebase and CI; risk and unattended execution) and the three spec reviews
Base: main at `550bde9` (2.2.0-preview1, release commit `5a25401`, tag v2.2.0-preview1). The branch is cut after the stable 2.2.0 release commit is on main; nothing in this plan depends on which of the two commits the branch starts from, because they differ only in the manifest's `Prerelease` line and the changelog.
Spec: `docs/roadmap-3.0/milestone-3-spec.md` (draft, 2026-10-03). Section numbers below (§n) point into it.
Roadmap: `docs/roadmap-3.0.md`, milestone 3, locked decisions 4, 5, and 6. Ships first as `v3.0.0-rc1` (PSGallery prerelease label `rc1`), then as `v3.0.0` from the same code once the candidate has soaked (decision 6, §10).
Branch: `feat/milestone-3-compiled-core` from main, after this plan and the spec are committed to main.

The plan implements §1 to §11 as written. It treats every open question in §13 as answered by its recommendation until the owner answers it; "Owner decisions by gate" says when each answer is due and which package changes if it goes against the recommendation.

The engine-cmdlet path (§13 question 1) is out of scope. If the owner answers against the recommendation, it becomes its own package, WPA, after WP3 and before WP7: a `CmdletEngine` path inside `src/Core/Engine/`, the detection rule and verbose line of the milestone 2 spec's appendix A, a cmdlet double under `tests/Fixtures/EngineCmdletDouble/`, and checks A1 to A3 of that appendix.

The spec says what the module does. This plan says how the work is split, in what order, which files each package touches, and how each package is accepted. Where the spec leaves an internal choice open, the plan picks one and says so under "Internal design choices".

## Current-state facts the plan builds on

Every fact below was read from the file named, or checked by running the command named, on 2026-10-03 at `550bde9`.

- **Exports.** `CompleterActions.psm1` dot-sources `src/Classes/*.ps1` as one script block, then `src/Private` and `src/Public`, then `src/Bootstrap.ps1`, and exports every `src/Public/*.ps1` base name plus the three aliases (`Export-ModuleMember -Function $publicFunctions -Alias ...`). The source manifest lists 14 functions by hand (`CompleterActions.psd1` lines 75 to 89, the `'Test-CompleterSet'` line indented four spaces against five for the others) and 3 aliases (the `AliasesToExport` block from line 95); `PowerShellVersion` is line 36 and the commented `RequiredAssemblies` line 51, so WP1's and WP2's manifest edits are line-disjoint. The psm1's export line is line 32. The build sets `FunctionsToExport = $public.BaseName` and `AliasesToExport = @($sourceManifestData.AliasesToExport)` (`CompleterActions.build.ps1`). `tests/CompleterRegistration.Tests.ps1` "exports the same public functions defined in the manifest and src\Public" holds the manifest to `src/Public`, and `tests/CompleterDeprecation.Tests.ps1` line 28 asserts `14`.
- **Classes.** `src/Classes/CompleterTypes.ps1` holds the two enums and four classes. `tests/CompleterClasses.Tests.ps1` (7 `It` blocks) pins the property lists, `TypeNames[0]` and `[1]`, the enum names, privacy (`{ [CompleterRegistration]::new() } | Should -Throw` from the test scope), that each `src/Classes/*.ps1` parses alone, that the packaged psm1 defines every class before the first function, and that both layouts import in a fresh process. Type literals outside `src/Classes`: `[CompleterState]` in `src/Private/New-CompleterRegistrationRecord.ps1` line 81, `src/Public/Get-Completer.ps1` line 120, and `src/Public/Get-CompleterRegistrationLegacy.ps1` lines 29, 53, and 57 (the wrapper WP2 deletes; until then the module cannot import without them resolving); `[CompleterRegistration]::new()` at `New-CompleterRegistrationRecord.ps1` line 101; `[CompleterScriptFinding] @{...}` at `New-CompleterScriptFinding.ps1` line 66; `[CompletionMatch] @{...}` at `New-CompletionMatch.ps1` line 57; `[ImportedCompleterRegistration] @{...}` at `New-ImportedCompleterRegistration.ps1` line 56. `[OutputType('CompleterActions.<Type>')]` strings appear in 12 public files.
- **Engine access.** Four private helpers reflect: `Assert-CompleterRuntimeCapability.ps1` (probe; parameters `-EngineIntrinsics`, `-EngineIntrinsicsType`, `-RuntimeExecutionContext`), `Resolve-CompleterRuntimeExecutionContext.ps1` (`GetField('_context', ...)`; parameters `-EngineIntrinsics`, `-EngineIntrinsicsType`), `Get-CompleterRuntime.ps1` (`GetProperty` for the two dictionaries; returns the `CompleterActions.CompleterRuntime` pscustomobject with `ExecutionContext`, `CustomProperty`, `CustomArgumentCompleters`, `NativeProperty`, `NativeArgumentCompleters`), and `Add-RuntimeCompleterRegistration.ps1`, which does not resolve anything but calls `GetValue` and `SetValue` on the `PropertyInfo` the runtime object carries. `Get-CompleterRegistrationSnapshot.ps1`, `Find-RuntimeCompleterRegistration.ps1`, and `Remove-RuntimeCompleterRegistration.ps1` call `Get-CompleterRuntime` and never reflect. `src/Bootstrap.ps1` line 2 is the literal `Assert-CompleterRuntimeCapability`, which "runs the capability probe from the tracked build output" (`tests/CompleterRegistration.Tests.ps1`) asserts, together with the packaged psm1 ending in the Bootstrap lines.
- **Tests that build a runtime object by hand.** `tests/CompleterRegistration.Tests.ps1` "creates a missing runtime dictionary once ..." and "keeps a runtime dictionary created after the snapshot ..." construct a `CompleterActions.CompleterRuntime` pscustomobject whose `NativeProperty` is `$context.GetType().GetProperty('NativeArgumentCompleters')` on an `Add-Type` probe class `CompleterActionsTests.RuntimeContextProbe`, replace `Get-CompleterRuntime` in module scope with a function that throws, and drive `Add-RuntimeCompleterRegistration -Runtime $runtime`. "throws a clear error when runtime execution context internals are unavailable" calls `Resolve-CompleterRuntimeExecutionContext -EngineIntrinsicsType ([pscustomobject]) -EngineIntrinsics ([pscustomobject]@{})` and asserts the message. The three "Runtime capability probe" tests pass the same substitutes to `Assert-CompleterRuntimeCapability` and match the message against `$PSVersionTable.PSVersion`, `_context`, `CustomArgumentCompleters`, and `NativeArgumentCompleters`. `tests/CompleterSet.Tests.ps1` lines 1051, 1095, 1215, 1259, 1403, and 1422 and `tests/CompleterSetDrift.Tests.ps1` line 933 replace `Get-CompleterRegistrationSnapshot`, `Get-CompleterRuntime`, `Add-RuntimeCompleterRegistration`, and `Remove-RuntimeCompleterRegistration` in module scope; `tests/CompleterActions.Tests.ps1` lines 1237 and 1266 do the same for the last two.
- **Grammar.** `src/Private/Test-CompleterScriptAst.ps1` (746 lines) is the walk: a nested `Add-Finding` calls `New-CompleterScriptFinding -Path -Extent -Construct -Message -Hint`, always with the default `Severity` `'Error'` (`New-CompleterScriptFinding.ps1` line 63; the walk never passes `-Severity`). It has 40 `Add-Finding` calls (`grep -c 'Add-Finding -Extent'`), several sharing one text (the three `TrapStatementAst` calls, for example), some with interpolated values (`$commandName`, `$($ExpressionAst.TokenKind)`, `$($ExpressionAst.Operator)`, `$($StatementAst.Operator)`, `$($usingStatement.UsingStatementKind...)`, `$($functionOverride.Name)`, `$unqualifiedName`). `Get-CompleterScriptFinding -LiteralPath` parses with `Get-CompleterScriptParseResult`, emits `ParseError` findings and returns, else calls `Test-CompleterScriptAst -Ast -LiteralPath`. `Assert-CompleterScriptConformance -LiteralPath` filters `Error` findings and throws the one error with the `Line {0}, column {1} ({2}): {3} {4}` lines. `Get-CompleterScriptTarget -LiteralPath [-ParseResult]` derives targets without the grammar. `tests/CompleterSet.Tests.ps1` lines 569 and 1644 and `tests/CompleterSetDrift.Tests.ps1` line 338 replace `Get-CompleterScriptParseResult` in module scope; no test replaces `Test-CompleterScriptAst`, `Get-CompleterScriptFinding`, or `Assert-CompleterScriptConformance`.
- **Where strict scripts are parsed without the grammar.** `src/Public/Register-Completer.ps1` lines 237 to 254: `$derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath)` inside `process`, in a `try` with no `catch` (the derivation errors propagate unwrapped; only the conflict error at line 311 has the `Failed to register the completer` prefix), before the `ShouldProcess` at line 314. `src/Private/Resolve-CompleterSetEntry.ps1` lines 295 to 312: the parse branch after the fast path (`$targetSource = 'Parsed'`, `Get-CompleterScriptParseResult`, then `Get-CompleterScriptTarget -ParseResult`), in a `try` whose `catch` adds `UnreadableTargets`. Problems are `@{ Kind; Message }` with `Kind` one of `InvalidEntry`, `MissingScript`, `OutsideModule`, `UnreadableTargets`, `TargetMismatch`. `Get-CompleterSetFinding.ps1` calls `Resolve-CompleterSetEntry -Verify` and maps only `MissingScript`, `InvalidEntry`, `UnreadableTargets`, and `TargetMismatch` (lines 108 to 110; `OutsideModule` is not mapped either), and the walk of choice 7 runs only without `-Verify`, so `NonConforming` is kept out of `Test-CompleterSet` twice over.
- **A non-conforming fixture with derivable targets.** `tests/Fixtures/ImportCompleterScript/UnsafeTopLevelScript.ps1`: `Get-Date | Out-Null` at the top, then a literal `Register-ArgumentCompleter -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -ScriptBlock { ... }`. `Test-CompleterScript` on it today gives two `CommandAst` findings, line 1 column 1 (`Get-Date`) and line 1 column 12 (`Out-Null`). Two existing tests already use it for the grammar-at-first-tab behaviour: `tests/CompleterSet.Tests.ps1` line 712 "registers a strict entry that breaks the grammar as Pending and fails it with the findings on first tab" (an unhashed entry, which question 2 changes) and line 1984 "never executes a non-conforming script whose entry took the fast path" (a hash-matched entry, which question 2 keeps); `tests/CompleterLazyRegistration.Tests.ps1` line 388 "marks a strict registration Failed when the script no longer conforms at first tab" registers a conforming script and breaks it afterwards, which question 2 also keeps.
- **Deprecated surface.** `src/Public/Get-CompleterRegistrationLegacy.ps1`, `Register-CompleterRegistrationLegacy.ps1`, `Unregister-CompleterRegistrationLegacy.ps1`, `src/Private/Write-CompleterDeprecationWarning.ps1`, `src/Bootstrap.ps1` lines 5 and 7 to 9, `CompleterActions.psm1`'s `-Alias`, the manifest's three `Legacy` entries and `AliasesToExport`, `tests/CompleterDeprecation.Tests.ps1` (9 `It`), the `Get-CompleterRegistrationLegacy` case at `tests/CompleterActions.Tests.ps1` line 780, `README.md` lines 50, 360, and 371, `.github/copilot-instructions.md` lines 6, 8, and 24, and `en-US/about_CompleterActions_Migration.help.txt`. No `src/docs/CompleterActions/*.md` page names a legacy command (`ls`; the wrappers use `.ForwardHelpTargetName`), and `CompleterActions.md` does not list the aliases.
- **Floor.** `PowerShellVersion = '7.0'` in the manifest; `README.md` line 19; `tests/CompleterRegistration.Tests.ps1` "Passes Test-ModuleManifest" asserts `'7.0'`. CI matrix 7.4, 7.5, 7.6, preview on Windows and Ubuntu; the legs resolve to 7.4.20, 7.5.11, 7.6.6, 7.7.0-preview.5.
- **Build.** `CompleterActions.build.ps1`: `clean`, `build` (depends on `clean`, `external_help`; concatenates `Classes`, `Public`, `Private` into the psm1, appends `Bootstrap.ps1`, copies the manifest, format files, help XML, and about topics, then `Update-ModuleManifest` with `CompatiblePSEditions`, `PowerShellVersion`, `Copyright`, `FunctionsToExport`, `AliasesToExport`, `ProjectUri`, `IconUri`), `Markdown_templates`, `external_help`, `release_check`, `Publish_build`. The module name is the folder leaf. `git ls-files build` lists seven text files; there is no `.gitattributes`; `.gitignore` holds `justfile`, `.justfile`, `testResults.xml`.
- **Tracked-build test.** `tests/CompleterRegistration.Tests.ps1` "keeps the tracked build output in sync with the module sources" copies `CompleterActions.build.ps1`, `CompleterActions.psd1`, `CompleterActions.Format.ps1xml`, `en-US`, and `src` into `$TestDrive/CompleterActions`, runs `Invoke-Build -File <staging>/CompleterActions.build.ps1 build` in a child `pwsh`, then asserts the relative file lists are equal and every file matches line by line except the manifest's `Generated on` comment.
- **CI.** `.github/workflows/ci.yml`: Checkout (full history), Install PowerShell (per channel), Show version, Install modules (InvokeBuild 5.14.23, Pester 6.1.0, PSScriptAnalyzer 1.25.0, PlatyPS 1.0.3), Lint, Test (`Invoke-Pester -Path ./tests -CI`), Upload test results, Build. `release.yml`: Checkout, Install modules, `release_check`, Test, Build, `Publish_build`, release assets and notes, `gh release create` with `--prerelease` when the tag has a hyphen. Both use `shell: pwsh`, which sets `$ErrorActionPreference = 'Stop'`.
- **dotnet.** `dotnet --list-sdks` on the owner's machine: 9.0.318, 10.0.112, 10.0.204, 10.0.302, 10.0.303, 10.0.400, 10.0.401. The `ubuntu-24.04` and `windows-2025` runner images list .NET SDK 8.0.131 to 10.0.401 (`actions/runner-images` readmes). A `net8.0` library referencing `System.Management.Automation` 7.4.0 built in 5 s with SDK 10.0.401 and loaded on pwsh 7.6.6 (spec appendix A).
- **Measured costs** (spec appendix A): `Test-CompleterScript` 25.9 ms per script over 173 scripts (4477 ms), parse 2.1 ms; compiled walk 0.203 ms per script; toy module import 22.5 ms median with a dll against 35 ms with PowerShell classes.
- **Benchmark tool.** `tools/Measure-CompleterStartup.ps1` takes `-CompleterRoot`, `-Iterations`, `-ModulePath`, `-BaselineModulePath`, prints Eager, Baseline, Lazy, LazyNoHash with `RatioToBaseline`; its help's example 2 extracts a baseline with `git archive`. Milestone 2's record: `docs/roadmap-3.0/validation/milestone-2-benchmark.md`, `LazyNoHash` 1281.1 ms, `Lazy` 761.0 ms on the branch build.
- **PS_Completers at `2c590c6`** (read only): no old name anywhere outside the `*_completer` folders; tests import with `-MinimumVersion 2.0.0` and `2.1.0`; CI installs CompleterActions `-Prerelease` on pushes to `master` and pull requests; branch `feat/completer-set-package` holds `package/PS_Completers.psd1` requiring `2.2.0`.
- **Help.** `external_help` turns `src/docs/CompleterActions/*.md` into the MAML XML; the about topics live in `en-US/`; `Markdown_templates` would overwrite the hand-edited pages and is never run.
- **This plan and the spec are untracked** on main at `550bde9`. Until they are committed, `git diff main -- <them>` cannot detect an edit on the branch.

## Internal design choices

1. **One C# project at `src/Core/`, assembly `CompleterActions.Core`.** `src/Core/CompleterActions.Core.csproj`: `TargetFramework` `net8.0`, `AssemblyName` `CompleterActions.Core`, `RootNamespace` `CompleterActions`, `Nullable` `enable`, `TreatWarningsAsErrors` `true`, `GenerateDocumentationFile` `true` (so every public member, enum members included, needs a doc comment, or the build fails with CS1591), `DebugType` `none` and `GenerateDependencyFile` `false` in `Release` (the dll and its `.xml` are the only outputs; only the dll is copied), `IncludeSourceRevisionInInformationalVersion` `false` (otherwise the SDK appends `+<commit>` and the release recipe's version check cannot match), `PackageReference` `System.Management.Automation` `7.4.0` with `PrivateAssets="all"`. `AssemblyVersion` `3.0.0.0`; `FileVersion` and `InformationalVersion` are passed by the `compile` task from the manifest (`ModuleVersion` and `Prerelease`), so the release commits need no edit in the project. Folders: `Types/` (§2), `Engine/` (§3), `Grammar/` (§4). No `global.json`: any SDK 8 or later builds a `net8.0` library, and the runner images carry three majors.
   - Rejected: `netstandard2.0` with `PowerShellStandard.Library` (no 7.x AST types; §13 question 7); `Add-Type -TypeDefinition` at import (407 ms, and decision 4 says built in CI).
2. **The assembly sits at `lib/CompleterActions.Core.dll` under the module folder**, in both layouts. The source manifest and the built manifest carry `RequiredAssemblies = @('lib/CompleterActions.Core.dll')` (forward slash, which `RequiredAssemblies` resolves on every platform relative to `ModuleBase`). The `compile` task runs `dotnet build src/Core/CompleterActions.Core.csproj -c Release -nologo -v q -p:FileVersion=<v> -p:InformationalVersion=<v-label>` and copies `src/Core/bin/Release/net8.0/CompleterActions.Core.dll` to `lib/`. `build` depends on `compile` (after `clean`, before `external_help`) and copies `lib/CompleterActions.Core.dll` to `build/CompleterActions/lib/` **before** its `Update-ModuleManifest` call, because `Update-ModuleManifest` (and `Test-ModuleManifest`) reject a manifest whose `RequiredAssemblies` file is missing (verified 2026-10-03: `The specified RequiredAssemblies entry 'lib/CompleterActions.Core.dll' ... is invalid`; with the dll present the call preserves `RequiredAssemblies` and `PowerShellVersion = 7.4`, and the built module imports). `.gitignore` gains the anchored patterns `/lib/`, `/build/CompleterActions/lib/`, `/src/Core/bin/`, `/src/Core/obj/` (an unanchored `lib/` would hide any future `lib` folder, a fixture's included).
   - Rejected: the dll beside the manifest at the module root (a dll at the repository root, and `Import-Module ./CompleterActions.Core.dll` would import an empty binary module); tracking the dll (§13 question 6).
3. **Public record types are sealed classes with `''`-defaulting string properties.** Each `string` property is backed by a field initialised to `string.Empty` with a setter `value ?? string.Empty` (§2, difference 3). `ImportModule` and `ScriptBlock` are plain nullable auto-properties. Enum members are declared in the 2.2.0 order with no explicit values. The classes carry no constructor logic, no `PSTypeNames` insertion (the full type name is first by itself), and no methods.
4. **Type literals in `src` are fully qualified.** `[CompleterActions.CompleterState]`, `[CompleterActions.CompleterRegistration]::new()`, and so on, in the six files the facts list. No `using namespace` line, so the build's `using`-hoisting path stays unused and nothing depends on parse-time namespace resolution. `[OutputType('CompleterActions.<Type>')]` strings stay as they are; nothing observable changes.
5. **Engine access: `CompleterActions.Internal.EngineAccess`, one instance per import in `$script:CompleterEngine`.**
   - `public static EngineAccess Create(object engineIntrinsics, Type engineIntrinsicsType, object? runtimeExecutionContext, Version engineVersion)` performs the probe: resolve `_context` on `engineIntrinsicsType` (skipped when `runtimeExecutionContext` is given), then the two properties on the context's type, collect the missing member names in the 2.2.0 order, and throw `InvalidOperationException` with the exact 2.2.0 message (§3), `<version>` being `engineVersion`, which the wrapper passes from `$PSVersionTable.PSVersion`; `EngineVersion` keeps that value.
   - `public static object ResolveExecutionContext(object engineIntrinsics, Type engineIntrinsicsType)` throws the two `Unable to ...` messages of `Resolve-CompleterRuntimeExecutionContext.ps1` as `InvalidOperationException`.
   - Instance members: `object ExecutionContext`, `PropertyInfo CustomProperty`, `PropertyInfo NativeProperty`, `EnginePath Path` (enum `{ Reflection }` in 3.0.0), `Version EngineVersion`.
   - The wrappers: `Assert-CompleterRuntimeCapability` keeps its three parameters, calls `Create` inside `try`, and in `catch` throws `$_.Exception.GetBaseException().Message`: a static-method exception reaches PowerShell as a `MethodInvocationException` whose own `Message` is `Exception calling "Create" with "4" argument(s): "..."`, so `$_.Exception.Message` would break every `Should -Throw '<message>'` in the existing tests, while the base exception's message is the exact text (verified by probe, spec appendix A). On success it stores the instance in `$script:CompleterEngine`. `Resolve-CompleterRuntimeExecutionContext` keeps its two parameters and calls `ResolveExecutionContext` the same way. `Get-CompleterRuntime` stays parameterless (`tests/CompleterSet.Tests.ps1` line 1095 captures and re-invokes the original function with no arguments), builds the 2.2.0 pscustomobject from `$script:CompleterEngine` (`ExecutionContext`, the two `PropertyInfo` handles, and `GetValue` of each), and keeps its `does not expose the completer dictionaries` throw for a missing handle. `Add-RuntimeCompleterRegistration`, `Get-CompleterRegistrationSnapshot`, `Find-`/`Remove-RuntimeCompleterRegistration`, and the dictionary helpers are untouched (`git diff main` prints nothing for them).
   - Rejected: a compiled `EnsureDictionary` that the PowerShell side calls (it would change `Add-RuntimeCompleterRegistration` and the two hand-built-runtime tests, for no 3.0.0 behaviour); invoking `$PSVersionTable` from C# (the wrapper has it).
6. **Grammar: `CompleterActions.Internal.StrictGrammar` with one static `Test` method returning findings.** `public static IReadOnlyList<GrammarFinding> Test(ScriptBlockAst ast)`; `GrammarFinding` carries `IScriptExtent Extent`, `string Construct`, `string Message`, `string Hint`. The walk is a port of `Test-CompleterScriptAst.ps1` onto `AstVisitor2`, kept structurally parallel (one method per nested function of the PowerShell walk: the top-level statement checks, the import-safe expression checks, the command checks, the `Register-ArgumentCompleter` argument checks, `using` and `#requires` checks, function overrides, dot-sourcing, the missing-registration check) so a reviewer can read them side by side. Every message and hint string lives in `src/Core/Grammar/GrammarMessages.cs` as a constant or a `static string` format method, copied character for character from `Test-CompleterScriptAst.ps1`. Findings are returned in the order the PowerShell walk emits them. `Test-CompleterScriptAst.ps1` becomes a wrapper with the same parameters that maps each `GrammarFinding` through `New-CompleterScriptFinding -Path $LiteralPath -Extent -Construct -Message -Hint`, so `Severity`, `Line`, and `Column` are derived exactly as today.
   - Parity is proven against the 2.2.0 build, not against the deleted PowerShell walk: a scratch harness (not committed) runs `Test-CompleterScript` over the §12 check 8 corpus under both builds and diffs the CSVs; WP8 records the result. During WP4 the implementer may keep a copy of the PowerShell walk under a scratch name in the worktree for side-by-side diffing, but the package's final commits delete it.
   - Rejected: a text or token-based checker (the spec says the parser's AST); regenerating the message catalogue from the PowerShell file at build time (two sources of truth at run time would be none).
7. **Grammar at registration and import reuses one parse.** `Get-CompleterScriptFinding` and `Assert-CompleterScriptConformance` gain an optional `-ParseResult <psobject>`; when given, no second parse happens. `Register-Completer`'s strict lazy branch becomes: `$parseResult = Get-CompleterScriptParseResult -LiteralPath $scriptPath`, `Assert-CompleterScriptConformance -LiteralPath $scriptPath -ParseResult $parseResult`, `$derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath -ParseResult $parseResult)`, in that order, inside the existing `try`, so a non-conforming script throws the Assert text unwrapped before any target is derived and before `ShouldProcess`. `Resolve-CompleterSetEntry`'s parse branch, when `-Verify` is not set, does this after the parse: if `$parseResult.ParseErrors.Count -gt 0`, it skips the walk and lets `Get-CompleterScriptTarget` throw `UnreadableTargets` as today (an AST with parse errors would give spurious findings); otherwise it runs `Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $resolvedPath`, adds `@{ Kind = 'NonConforming'; Message = <§4 text from the first Error finding> }` when any finding comes back, and then derives the targets as today, so a `TargetMismatch` for the same entry is reported in the same pass, grammar first. Under `-Verify` nothing changes, so `Test-CompleterSet` is untouched (§11).
   - Rejected: running the grammar inside `Get-CompleterScriptTarget` (it is called from `Export-CompleterSet` paths and from `Test-CompleterSet -Verify`, where the grammar must not run).
8. **`tests/CompleterClasses.Tests.ps1` is rewritten in place** for the public types: it keeps the four property lists (now the assertion for §12 check 2), drops the privacy test, the parse-alone test, and the packaged-psm1-order test (their subjects are gone), and adds the public-type checks of §12 check 2. The two "imports the <Layout> module in a fresh profile-free process" cases stay.
9. **The tracked-build test leaves binaries out.** In "keeps the tracked build output in sync with the module sources": the staging copy excludes `src/Core/bin` and `src/Core/obj`; the file lists and the line comparison filter out `lib/*.dll`; one new assertion checks `Test-Path <staging>/build/CompleterActions/lib/CompleterActions.Core.dll`. The child build compiles (`dotnet build` with no `obj/` and a warm NuGet cache took about 1 s on the owner's machine; the first build on a fresh machine or runner also restores `System.Management.Automation` 7.4.0 over the network, which the CI `Compile` step has already done by the time Test runs), which lengthens this one test; that is accepted.
10. **CI compiles before it lints.** A `Compile` step (`Invoke-Build -Task compile`) goes after `Install modules` in both workflows. Lint (`./src -Recurse` still finds only `.ps1` files; `src/Core/obj` holds none), Test, and Build keep their order and comments. The `Build` step at the end still proves the whole build runs on each leg.
11. **One new validation record per validator step**, in the shape of milestone 2's: `docs/roadmap-3.0/validation/milestone-3-benchmark.md` (WP7), `milestone-3-runtime.md`, `milestone-3-grammar-parity-2.2.0.csv`, `milestone-3-grammar-parity-3.0.0.csv`, and `milestone-3-set-import.csv` (WP8).

## Departures from the spec

None at this draft. Reviewers add rows here when a package finds the spec silent, wrong, or looser than the plan; each row names the spec line the amended spec carries.

## Work packages

### Rules for every package

These rules go verbatim into every implementer and validator prompt. Reviewers check each one.

- **Documents.** Implementers never edit `docs/roadmap-3.0.md`, `docs/roadmap-3.0/milestone-3-spec.md`, or `docs/roadmap-3.0/milestone-3-plan.md`, and never restate a roadmap exit criterion anywhere: not in the docs, the CHANGELOG, the pull request, or a commit message. A spec or plan defect is reported to the orchestrator, not fixed. Gate, in every package review: `git diff main -- docs/roadmap-3.0.md docs/roadmap-3.0/milestone-3-spec.md docs/roadmap-3.0/milestone-3-plan.md` prints nothing. This is meaningful only because this plan and the spec are committed to main before the branch is cut. §10's "Roadmap edits the owner would make" and the release status lines are the owner's.
- **Worktrees and merges.** Each package runs in its own git worktree, on its own branch `m3/<wp>` cut from `feat/milestone-3-compiled-core` after the packages it depends on are merged there. The orchestrator merges into the feature branch, each when it is accepted, in this order: WP1, WP2, WP3, WP4, WP5, WP6. WP7 and WP8 commit their validation files on the feature branch itself. After each merge the orchestrator discards both sides of any conflict in `build/` and in `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml` (`git checkout --ours -- build src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`), re-runs `pwsh -NoProfile -Command "Invoke-Build -Task build"`, and commits the result as `chore(build): rebuild after merging <wp>`. A modify/delete conflict on a file one package edited and a later package deleted (WP1 qualifies the type literals in `Get-CompleterRegistrationLegacy.ps1`; WP2 deletes it) is resolved by taking the deletion (`git rm`). A conflict anywhere else goes back to the later package. The build script takes the module name from its folder leaf, so a worktree must be reached through a junction named `CompleterActions`, and `git -c core.longpaths=true worktree add` is needed under the scratchpad. `dotnet build` runs through the same junction path.
- **Run steps.** Invoke-Build, PSScriptAnalyzer, and Pester are three separate processes, in this order. Never run Pester in the same process as Invoke-Build or PSScriptAnalyzer: both register completers, and that breaks the paging tests. A changed assembly needs a new process in every case (an assembly cannot be unloaded). Before step 1, no `pwsh` on the machine may hold the repository's `CompleterActions.psd1` or `build/CompleterActions` imported: a process that has loaded `CompleterActions.Core.dll` locks the file, and `clean` (`Remove-Item build/CompleterActions -Recurse -Force`), the `compile` copy into `lib/`, and the tracked-build test then fail on Windows with `being used by another process`. The owner's profile imports the installed module, so an ordinary interactive session is safe; a dev session that imported the repository build, or a hung test child, is not (`Get-Process pwsh` finds it).
  1. `pwsh -NoProfile -Command "Invoke-Build -Task build"`. It compiles first. The build comes first locally because the tracked-build test compares a fresh build with the committed `build/`.
  2. `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"` prints nothing. These are CI's two Lint calls.
  3. `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes. This is CI's Test step and every package's final gate.

  During work an implementer may run only the package's own test file after step 1. Reviewers run the three steps above, in order, on the package branch.
- **C#.** `dotnet build` with zero warnings (`TreatWarningsAsErrors`). Every public member has a doc comment. No `unsafe`, no P/Invoke, no reflection outside `src/Core/Engine/`. The `System.Management.Automation` reference stays 7.4.0.
- **Linux.** Every package's tests pass locally on Windows. Linux is proven either under WSL (`/snap/bin/pwsh -NoProfile`, with `dotnet` available there, same three steps) or by the first CI run. The orchestrator may push the feature branch and open a draft pull request early to get the Ubuntu legs; a draft is not the WP9 pull request. The package's review note records which of the two proved Linux.
- **Commits.** Conventional commits with a parenthesised scope and an imperative summary: `feat(core): ...`, `feat(engine): ...`, `feat(grammar): ...`, `refactor(surface): ...`, `test(core): ...`, `docs(help): ...`, `chore(build): ...`, `chore(ci): ...`, `chore(release): ...`. Each commit message ends with exactly one trailer line, the `Co-Authored-By:` line the harness provides (in the session that drafted this plan, `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`), and nothing else. No `Claude-Session` trailer. Pre-PR check, in `pwsh -NoProfile`:

  ```powershell
  git log main..HEAD --format=%B | Select-String -Pattern '^Co-Authored-By:' | ForEach-Object Line | Sort-Object -Unique   # exactly one line
  @(git log main..HEAD --format=%B | Select-String -Pattern 'Claude-Session').Count                                      # 0
  ```
- **Files.** Commit `build/` text files and the regenerated help XML with the source change they come from; never commit `lib/`, `bin/`, `obj/`, or a `.dll`. Keep CR LF and UTF-8 without a BOM in every edited text file, `.cs` and `.csproj` included. No scratch file in the repository.
- **Tests.** Every test that reads the error stream passes `-ErrorAction Continue` to the command under test, because CI runs Pester with `$ErrorActionPreference = 'Stop'`. No test reads or writes the real PS_Completers repository. Every platform skip uses `-Skip:` or `Set-ItResult -Skipped -Because '<reason>'` with the reason given in this plan, word for word.
- **Unchanged files.** Where a package says a file is unchanged, its gate is `git diff main -- <file>` printing nothing.

### WP1 Assembly, public types, build, and floor

Owns §2 in full, §6, §7, and the type-literal consequences in `src`. It is the foundation: every other package needs the assembly to exist and the types to be public.

Day one. No dependency.

Files:
- new `src/Core/CompleterActions.Core.csproj` (choice 1);
- new `src/Core/Types/CompleterState.cs`, `CompleterType.cs`, `CompleterRegistration.cs`, `ImportedCompleterRegistration.cs`, `CompleterScriptFinding.cs`, `CompletionMatch.cs` (choice 3);
- delete `src/Classes/CompleterTypes.ps1` and the folder;
- `CompleterActions.psm1` (drop the Classes block, lines 4 to 9);
- `CompleterActions.build.ps1` (`compile` task; `build` depends on `clean`, `compile`, `external_help`; `$sourceFolders` loses `Classes`; copy `lib/CompleterActions.Core.dll` into `build/CompleterActions/lib/`);
- `CompleterActions.psd1` (`RequiredAssemblies = @('lib/CompleterActions.Core.dll')`, `PowerShellVersion = '7.4'`);
- `.gitignore` (choice 2);
- `src/Private/New-CompleterRegistrationRecord.ps1`, `New-CompleterScriptFinding.ps1`, `New-CompletionMatch.ps1`, `New-ImportedCompleterRegistration.ps1`, `src/Public/Get-Completer.ps1`, and `src/Public/Get-CompleterRegistrationLegacy.ps1` lines 29, 53, and 57 (choice 4; the wrapper's three `[CompleterState[]]` literals must be qualified too, or the module does not import once `src/Classes` is gone; WP2 deletes the file afterwards, and the merge rule takes the deletion);
- `CHANGELOG.md` is not edited by WP1; WP6 records the floor and the assembly under `### Changed` and `### Added`;
- `tests/CompleterClasses.Tests.ps1` (choice 8);
- `tests/CompleterRegistration.Tests.ps1` ("Passes Test-ModuleManifest": `'7.4'`; the tracked-build test per choice 9);
- `.github/workflows/ci.yml` and `release.yml` (choice 10);
- `README.md` line 19, the "Build" subsection (the `dotnet` SDK 8 or later requirement, `Invoke-Build -Task compile`, where the assembly lands), and the "Tests" subsection (`Invoke-Build -Task compile` or `build` must run first: `Import-Module` of the source manifest and `Test-ModuleManifest` both fail without `lib/CompleterActions.Core.dll`);
- `build/`.

Scope: WP1 does not touch `src/Bootstrap.ps1` or the export lists (WP2's), and does not touch the engine or grammar helpers (WP3's and WP4's). Its only edit to a Legacy file is the three type literals above. WP1 may not change any message text.

Details:
- **Property order** is the 2.2.0 order of `src/Classes/CompleterTypes.ps1`, which `tests/CompleterClasses.Tests.ps1` already lists; the C# files declare the properties in that order, and the test's lists stay the oracle.
- **Enums**: `CompleterState { Active, Stale, Conflicted, Pending, Failed, Discovered }`, `CompleterType { Native, Parameter }`.
- **`compile` task**: fails the build when `dotnet` is not on `PATH` with `compile: the dotnet SDK (8.0 or later) is required to build CompleterActions.Core.dll.`; reads `ModuleVersion` and `Prerelease` from the source manifest for the version properties; copies the dll only (no `.pdb`, no `.deps.json`, no `.xml`).
- **Manifest round trip**: after `Invoke-Build build`, `(Import-PowerShellDataFile build/CompleterActions/CompleterActions.psd1).RequiredAssemblies` is `lib/CompleterActions.Core.dll` and `PowerShellVersion` is `7.4` (verified on a scratch copy 2026-10-03 with the build task's exact `Update-ModuleManifest` keys; choice 2).
- **Compile is a precondition of Pester from this package on.** `tests/CompleterRegistration.Tests.ps1` "Passes Test-ModuleManifest" and every `Import-Module` of the source manifest fail without `lib/CompleterActions.Core.dll` (`Test-ModuleManifest` writes a non-terminating error that CI's `$ErrorActionPreference = 'Stop'` turns fatal). The run steps already build first; WP1's done-when and the README say it.
- **Hashtable conversion** (`[CompleterActions.CompleterScriptFinding] @{ ... }`) must keep working in the three `New-*` helpers; `tests/CompleterAuthorTooling.Tests.ps1` and `tests/CompleterActions.Tests.ps1` exercise them.

Tests (`tests/CompleterClasses.Tests.ps1`, rewritten; every assertion runs in the test's own scope, not in module scope, because that is the point):
- `constructs <TypeName> with the record property names in order and the full type name first` (4; §12 check 2; `PSObject.TypeNames` is `<TypeName>, System.Object`)
- `defaults every string property of <TypeName> to an empty string and keeps it so when $null is assigned` (4; question 3)
- `defaults ImportModule and ScriptBlock to null`
- `defines the CompleterState and CompleterType enums with the roadmap values and integer order`
- `is a CompleterActions.CompleterRegistration by -is from outside the module for a Get-Completer record` (the roadmap's line, with one registration made in the test and removed in `AfterEach`)
- `binds -State from a string, compares to a string and to an integer, and serializes as an integer unless -EnumsAsStrings` (§12 check 2)
- `declares the 2.2.0 output type name on <Command>` (11)
- `renders a registration and a finding through the format file's views`
- `loads CompleterActions.Core 3.0.0.0 from under ModuleBase referencing System.Management.Automation 7.4.0.0 and exports no cmdlet` (§12 check 5)
- `imports the <Layout> module in a fresh profile-free process` (2; kept)
- `re-imports with -Force in the same process after Remove-Module`
- In `tests/CompleterRegistration.Tests.ps1`: the manifest test asserts `7.4`; the tracked-build test per choice 9.

Review focus: property order against the 2.2.0 lists; `''` semantics on every string property; nothing in `src` still spells a bare `[CompleterState]`, `[CompleterType]`, or class name (`Select-String -Path src\**\*.ps1 -Pattern '\[(CompleterState|CompleterType|CompleterRegistration|ImportedCompleterRegistration|CompleterScriptFinding|CompletionMatch)[\]\[]'` prints nothing); `git ls-files` lists no binary; both workflows compile before Lint.

Done when: the three run steps pass with the Legacy files still present (WP2 removes them; `tests/CompleterDeprecation.Tests.ps1` still asserts 14 and still passes here), after `Invoke-Build build` in a fresh process, Linux proven as the rules say, and `git status --short` shows no `lib/`, `bin/`, or `obj/` path.

### WP2 Remove the deprecated surface

Owns §5 and the manifest export lists.

Day one, in parallel with WP1. Its files do not overlap WP1's except `CompleterActions.psd1` (WP1 edits `RequiredAssemblies` and `PowerShellVersion`; WP2 edits `FunctionsToExport` and `AliasesToExport`) and `CompleterActions.psm1` (WP1 deletes lines 4 to 9; WP2 edits the `Export-ModuleMember` line), and `README.md` (WP1: line 19 and the Build subsection; WP2: lines 50, 360, 371). The merge order WP1 then WP2 resolves these as line-disjoint edits.

Files:
- delete `src/Public/Get-CompleterRegistrationLegacy.ps1`, `Register-CompleterRegistrationLegacy.ps1`, `Unregister-CompleterRegistrationLegacy.ps1`, `src/Private/Write-CompleterDeprecationWarning.ps1`, `tests/CompleterDeprecation.Tests.ps1`;
- `src/Bootstrap.ps1` (drop line 5 and lines 7 to 9; line 2 stays the literal `Assert-CompleterRuntimeCapability`);
- `CompleterActions.psd1` (`FunctionsToExport` the 11 of §5, `AliasesToExport = @()`);
- `CompleterActions.psm1` (`Export-ModuleMember -Function $publicFunctions`);
- `tests/CompleterActions.Tests.ps1` (drop the `Get-CompleterRegistrationLegacy` case at line 780);
- `README.md` lines 50, 360, 371; `.github/copilot-instructions.md` lines 6, 8, 24;
- `CHANGELOG.md` `## [Unreleased]` `### Removed` (the three aliases, the three wrappers, `-ManagedOnly` and `-DiscoveredOnly`, the once-per-process warning; the `7.0` floor line is WP1's and goes under `### Changed`, added by WP6);
- the regenerated help XML and `build/`.

Tests:
- In `tests/CompleterActions.Tests.ps1`, a new `Describe 'Removed surface'`:
  - `exports exactly the eleven functions and no alias` (§12 check 1; compares `Get-Command -Module` with the manifest's `FunctionsToExport` and asserts `AliasesToExport` is empty)
  - `fails <Name> with CommandNotFoundException` (6; the three aliases and the three wrappers)
  - `has no deprecated name left in the sources` (§12 check 13's `Select-String`, with the migration guide and the README's history sentence as the only allowed hits, each by file)

Review focus: `git diff main -- tests/CompleterActions.Tests.ps1` shows only the dropped case and the new `Describe`; no other test file changes; the manifest's 11 names are sorted as the file lists them, with the `FunctionsToExport` block's indentation normalised to one width (today the `'Test-CompleterSet'` line differs).

Done when: the three run steps pass; `Get-Command -Module CompleterActions | Measure-Object` prints 11 in a fresh process.

### WP3 Engine access in the compiled layer

Owns §3 in full and §12 check 7.

Depends on WP1.

Files:
- new `src/Core/Engine/EngineAccess.cs`, `EnginePath.cs` (choice 5);
- `src/Private/Assert-CompleterRuntimeCapability.ps1`, `Resolve-CompleterRuntimeExecutionContext.ps1`, `Get-CompleterRuntime.ps1` (wrappers, choice 5);
- `tests/CompleterRegistration.Tests.ps1` (`Describe 'Compiled engine access'`, added after "Runtime capability probe");
- `build/`.

Unchanged: `src/Bootstrap.ps1`, `Add-RuntimeCompleterRegistration.ps1`, `Get-CompleterRegistrationSnapshot.ps1`, `Find-RuntimeCompleterRegistration.ps1`, `Remove-RuntimeCompleterRegistration.ps1`, the four `*-CompleterRuntimeDictionaryValue`/`Test-CompleterRuntimeDictionaryKey` helpers, and every existing test (`git diff main -- tests` shows only the new `Describe`).

Details:
- The probe message is byte-identical to `Assert-CompleterRuntimeCapability.ps1` line 92, with the member list joined by `', '` inside the quotes as today. The wrapper passes `$PSVersionTable.PSVersion` in.
- The wrapper re-throws with `throw $_.Exception.GetBaseException().Message` (choice 5) so `Should -Throw '<message>'` in the existing tests matches; `$_.Exception.Message` would carry the `Exception calling "Create" with "4" argument(s)` prefix.
- `$script:CompleterEngine` is set only on success and read by `Get-CompleterRuntime`; `Get-CompleterRuntime` reads `GetValue` on every call, so a dictionary the engine creates after import is seen, as today.

Tests (`Describe 'Compiled engine access'`):
- `holds one EngineAccess in module state after import, on the Reflection path, with the engine version` (`& $module { $script:CompleterEngine }`; `Path` `Reflection`; `EngineVersion` equals `$PSVersionTable.PSVersion`)
- `throws the 2.2.0 probe message from the compiled layer for a missing <Member>` (3; calls `[CompleterActions.Internal.EngineAccess]::Create` directly with the substitutes the existing tests use, asserts the full message)
- `resolves the live dictionaries through the handles and sees one the engine creates later` (register a completer with `Register-ArgumentCompleter` in the test after import, then `Get-CompleterRuntime` shows it; cleaned up)
- `contains no member resolution outside src/Core` (§12 check 7's `Select-String` over `src\**\*.ps1`)

Review focus: the existing probe and runtime tests pass without edits; message texts diffed against main; no `GetProperty`/`GetField` left in `.ps1`.

Done when: the three run steps pass, Linux proven as the rules say.

### WP4 The strict grammar in the compiled layer

Owns §4 "Same findings, faster" and §12 check 8's implementation side (the recorded parity run is WP8's).

Depends on WP1. Runs in parallel with WP3 (different C# folders; the csproj globs `*.cs`, so neither edits it).

Files:
- new `src/Core/Grammar/StrictGrammar.cs`, `GrammarFinding.cs`, `GrammarMessages.cs` (choice 6);
- `src/Private/Test-CompleterScriptAst.ps1` (becomes the wrapper; same parameters, same output);
- `build/`.

Unchanged: `Get-CompleterScriptFinding.ps1`, `Assert-CompleterScriptConformance.ps1`, `Get-CompleterScriptTarget.ps1`, `New-CompleterScriptFinding.ps1`, every public command, and every test file. `git diff main -- tests` prints nothing for WP4.

Details:
- **Catalogue first.** `GrammarMessages.cs` is written before the visitor by copying every `-Construct`, `-Message`, and `-Hint` literal of `Test-CompleterScriptAst.ps1`, interpolations becoming format methods; the reviewer diffs the catalogue against the PowerShell file literal by literal.
- **Order.** Findings come back in the order the PowerShell walk emits them: it walks `$Ast.EndBlock.Statements` in order, descending as its nested functions do, then the `using`/`#requires` checks, the trap check, function overrides, dot-sourcing, and the missing-registration check. The C# visitor reproduces that order; `Test-CompleterScriptAst` does not sort.
- **Extents.** Each finding's `Extent` is the same AST node's extent the PowerShell walk passes (`$ExpressionAst.Extent`, `$CommandAst.Extent`, `$commandElement.Extent`, `$Ast.Extent`, `Traps[0].Extent`, and so on), so `Line` and `Column` match.
- **Parity harness** (scratch, not committed): for every file of the §12 check 8 corpus, run `Test-CompleterScript -LiteralPath` under the 2.2.0 build (`git archive v2.2.0 build`) in one process and under the branch build in another, `Select-Object Path, Line, Column, Severity, Construct, Message, Hint` with `Path` made relative, `ConvertTo-Csv`, and compare. The 14 scaffold outputs are generated once from `tests/Fixtures/NewCompleterScript/*.txt` through `New-CompleterScript -HelpText` under the branch build and fed to both. WP4's done-when includes a zero-difference run on the owner's machine; WP8 repeats and records it.

Tests: none added; the oracle is `tests/CompleterAuthorTooling.Tests.ps1` (20 `It`, unchanged), `tests/CompleterImporter.Tests.ps1`, `tests/CompleterLazyRegistration.Tests.ps1`, and `tests/CompleterScaffold.Tests.ps1`'s self-check cases, all unchanged and passing.

Review focus: the catalogue diff; the visitor's structure mirrors the PowerShell walk; the parity harness output is attached to the review note with zero differences; no `.ps1` under `src` still contains a grammar message literal other than the wrapper's parameters.

Done when: the three run steps pass, Linux proven as the rules say, and the parity harness shows zero differences over the full corpus.

### WP5 Grammar at registration and import (question 2)

Owns §4 "Where the grammar runs" and §12 checks 10, 11, and 12, with the command help sentences of §8 for `Register-Completer` and `Import-CompleterSet`. It is isolated so a "no" to question 2 drops it whole.

Depends on WP4.

Files:
- `src/Private/Get-CompleterScriptFinding.ps1`, `Assert-CompleterScriptConformance.ps1` (optional `-ParseResult`, choice 7);
- `src/Public/Register-Completer.ps1` (choice 7; comment help gains one sentence on the strict lazy check);
- `src/Private/Resolve-CompleterSetEntry.ps1` (choice 7; the `NonConforming` kind in its help);
- `src/Public/Import-CompleterSet.ps1` (comment help: one sentence) and `src/docs/CompleterActions/Import-CompleterSet.md`, `Register-Completer.md` (the same sentences);
- `tests/CompleterLazyRegistration.Tests.ps1` (`Describe 'Grammar at registration'`), `tests/CompleterSet.Tests.ps1` (`Describe 'Grammar at import'`, and one existing test rewritten: line 712 "registers a strict entry that breaks the grammar as Pending and fails it with the findings on first tab" asserted the behaviour question 2 replaces, so it becomes "reports a NonConforming problem for an unhashed strict entry and registers nothing", the first test of the new `Describe`);
- the regenerated help XML and `build/`.

Unchanged: `Export-CompleterSet.ps1`, `Test-CompleterSet.ps1`, `Get-CompleterSetFinding.ps1`, `Invoke-CompleterLazyStub.ps1`, `Import-CompleterScript.ps1`, `tests/CompleterSetDrift.Tests.ps1`, and every other existing test in the two edited test files, including line 1984 "never executes a non-conforming script whose entry took the fast path" (the hash-match case) and `tests/CompleterLazyRegistration.Tests.ps1` line 388 "marks a strict registration Failed when the script no longer conforms at first tab" (§12 check 12's oracle).

Details:
- `NonConforming` message: `The script does not conform to the strict import grammar: line <l>, column <c> (<Construct>): <Message> Run Test-CompleterScript to work through the findings, or mark the entry Trusted to run it as-is.` from the first `Error` finding. It is added before `Get-CompleterScriptTarget` runs, and the targets are still derived, so a `TargetMismatch` for the same entry follows it.
- The existing invalid-entry report (`Entry <n> ('<path>'): <message>`), the `-SkipInvalid` warning, the per-entry verbose lines, and the summary are untouched.
- The fixture for the tests is `tests/Fixtures/ImportCompleterScript/UnsafeTopLevelScript.ps1` copied into `TestDrive` (its target `Test-UnsafeTool:Name` derives; its top level has a pipeline the grammar rejects).

Tests:
- `tests/CompleterLazyRegistration.Tests.ps1`, `Describe 'Grammar at registration'`:
  - `fails a strict lazy registration of a non-conforming script with the conformance text and registers nothing` (§12 check 10; `-ErrorAction Continue`; asserts the first line and a finding line that begins `Line 1, column 1 (CommandAst)`, the fixture giving two `CommandAst` findings; `Get-Completer -CommandName Test-UnsafeTool -ParameterName Name` is empty)
  - `fails the same way under -WhatIf`
  - `registers the same script as Pending with -Trusted`
  - `parses the script once on the registration path` (a counting shim over `Get-CompleterScriptParseResult` in module scope, modelled on `tests/CompleterSet.Tests.ps1` line 569, counts 1)
- `tests/CompleterSet.Tests.ps1`, `Describe 'Grammar at import'`:
  - `reports a NonConforming problem for an unhashed strict entry and registers nothing` (§12 check 11; the rewritten line 712 test; the full `Entry 1 ('...'): The script does not conform ...` text)
  - `skips that entry with the skipped warning under -SkipInvalid and registers the others`
  - `imports the same entry without a problem when it is Trusted`
  - `reports NonConforming before TargetMismatch for one entry with both`
  - `leaves Test-CompleterSet's findings unchanged for the same set` (the set's `Test-CompleterSet` output equals the 2.2.0 kinds; no `NonConforming` construct appears)
  - `parses each unhashed strict entry once on the import path` (the same counting shim; one call per entry)
- Existing: the hash-match case is line 1984, unchanged; §12 check 12 is `tests/CompleterLazyRegistration.Tests.ps1` line 388, unchanged; every other test in both files passes unchanged.

Review focus: the two counting tests show one parse per script on each path (the existing counting shims at `tests/CompleterSet.Tests.ps1` lines 569 and 1644 and `tests/CompleterSetDrift.Tests.ps1` line 338 cover `Export-CompleterSet` and `Test-CompleterSet -Verify`, which gain no parse, and must still pass); nothing runs under `-Verify`; the first-tab path is untouched (`git diff main -- src/Private/Invoke-CompleterLazyStub.ps1 src/Public/Import-CompleterScript.ps1` prints nothing).

Done when: the three run steps pass, Linux proven as the rules say.

### WP6 Documentation: migration guide and the fourth edition

Owns §8 in full except the two command-help sentences WP5 owns, and §12 check 14.

Depends on WP2 (the removed names) and WP5 (the grammar wording). It can run in parallel with WP7.

Files: `en-US/about_CompleterActions_Migration.help.txt` (rewritten), `en-US/about_Completer_Sets.help.txt`, `en-US/about_Import_Completers.help.txt`, `README.md` (lines 162, 168, 264, 278, the "Types" paragraph; the `Releasing` snippet is unchanged because `build` compiles), `.github/copilot-instructions.md` line 28, `tools/Measure-CompleterStartup.ps1` (help text only: `.PARAMETER BaselineModulePath` and example 2 say that a 3.x baseline comes from `Save-PSResource` or a rebuilt tag and that `git archive` works for 2.x tags), `CHANGELOG.md` (`### Changed`, `### Added`, `### Documentation` under `## [Unreleased]`), `src/docs/CompleterActions/CompleterActions.md` (checked: it lists no alias today; it gains one sentence on the public types), `tests/CompleterActions.Tests.ps1` (check 14 tests next to the about-topic tests at line 145), and `build/`.

Change:
- **`about_CompleterActions_Migration`**, sections in this order: `SYNOPSIS` (2.x to 3.0), `LONG DESCRIPTION` (the four changes), `REMOVED COMMANDS` (the removal map with before/after blocks), `PUBLIC TYPES` (the eight differences of §2 as a numbered list, with `-is`, `::new()`, `PSTypeNames`, `''`, enums, `[enum]::GetNames`, hashtable conversion, `OutputType`, remoting), `ENGINE FLOOR`, `THE GRAMMAR AT REGISTRATION AND IMPORT` (what a profile sees; `-SkipInvalid`; the hash fast path), `CHECKLIST FOR A PROFILE`, `MOVING FROM 1.x` (the 1.x to 2.0 command table and a pointer that 2.0's guide covered the target contract, the state filter, and the typed output), `SEE ALSO`. The topic keeps its name.
- **`about_Completer_Sets`** and **`about_Import_Completers`**: the first-tab paragraphs the spec lists gain the registration and import check; the hash section states that a hash-matched entry is not re-walked and why.
- **`README.md`** as §8; the "Architecture notes" section replaces the `src\Classes` and Bootstrap alias sentences with the assembly, `lib/`, and the `compile` task.
- **`CHANGELOG.md`**: `### Changed` (public types with the eight differences, engine access in the compiled layer, grammar in the compiled layer and at registration and import, `PowerShellVersion = '7.4'`), `### Added` (`CompleterActions.Core.dll`, the `compile` task, the `dotnet` requirement), `### Documentation` (the migration guide's rewrite, the about-topic edits). WP2 already wrote `### Removed`.

Tests (`tests/CompleterActions.Tests.ps1`):
- `has the 3.0 migration guide` (check 14: contains `3.0`, the six removed names, `[CompleterActions.CompleterRegistration]`, `PowerShellVersion`, `7.4`)
- `states the registration and import grammar check in <Topic>` (2)
- `mentions the grammar at registration and import in the help of <Command>` (2: `Register-Completer`, `Import-CompleterSet`)

Review gate for wording: in a `pwsh -NoProfile`, `Select-String -Path en-US/*.txt, src/Public/*.ps1, src/docs/CompleterActions/*.md, README.md, .github/copilot-instructions.md -Pattern 'fourteen', 'thirteen', 'three aliases', 'Legacy', '7\.0', 'src\\Classes', 'first tab'`, with each hit listed in the review note as kept or changed and why.

Done when: the three run steps pass, Linux proven as the rules say; the wording gate's hits are all accounted for; the documents gate of the rules prints nothing.

### WP7 Benchmark, third edition, and the grammar timing (validator step)

Owns §9 and §12 checks 9 and 16. A validator step, not an implementer package: its done-when is the committed validation file, and reviewers check that file.

Runs after WP1 to WP5 are merged on the branch, because they fix the import path and the grammar. It needs no tool change. It can run in parallel with WP6.

Prerequisites: the owner's machine (Windows, pwsh 7.6.6, dotnet SDK), `git` with `tar` on `PATH`, and read access to `C:\Users\Trent\OneDrive\Documents\PowerShell\Completers` for the clone. Every `<scratch>` folder is under the session scratchpad, never in the repository.

Steps, each in its own `pwsh -NoProfile`:
1. `git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers`, then `New-Item -ItemType Directory -Path <scratch>\v2.2.0 -Force | Out-Null`, then `git archive v2.2.0 build | tar -x -C <scratch>\v2.2.0` (the 2.2.0 package is all text, so the archive imports; the branch is cut after the stable tag exists).
2. Gate run: `.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v2.2.0\build\CompleterActions -Iterations 10`. `-ModulePath` stays the default, the branch's `build/CompleterActions`. Never omit `-CompleterRoot`.
3. Run rule (§9): one run; a `LazyNoHash` `RatioToBaseline` of 1.05 or lower passes. Over 1.05, run up to three more; the gate is the median of all runs taken, and every run is reported. A median above 1.05 is a regression: it goes back to WP5 (the only package that adds import-time work), and the runs are repeated after the fix.
4. Information run: the same command with `-ModulePath <scratch>\v2.2.0\build\CompleterActions` and no baseline, for 2.2.0's `Lazy` median, reported beside 3.0.0's with their ratio (bound 1.05, not a gate).
5. Grammar loop: a scratch script that imports a module by path, warms up with one `Test-CompleterScript` call, then times `foreach ($f in $files) { $null = Test-CompleterScript -LiteralPath $f.FullName }` over the clone's 173 scripts with a `Stopwatch`; run three times under the branch build and three times under the 2.2.0 build, alternating, each in a fresh process. Gate: the median branch time is at most 0.30 of the median 2.2.0 time.
6. Compiled walk: a scratch script that parses the 173 scripts once, warms up, then times `[CompleterActions.Internal.StrictGrammar]::Test($ast)` per script with a `Stopwatch`; the median per-script time is under 1 ms. Three runs, fresh processes.
7. Spot cost: `Import-Module` of the branch build and of the 2.2.0 build, ten fresh processes each, medians reported.

Recording: `docs/roadmap-3.0/validation/milestone-3-benchmark.md`, in the shape of `milestone-2-benchmark.md`: the command lines, the tool's full output per run, the grammar loop and walk samples, the pwsh version, the OS, the SDK version, the branch commit, the PS_Completers commit, a criteria table (`LazyNoHash` at most 1.05 by the run rule; grammar loop at most 0.30; walk under 1 ms; `Lazy` bound 1.05 reported), and the spot cost marked "reported, not gated". Commit: `docs(validation): record the milestone 3 benchmark and grammar timing`. The same numbers go into the pull request body.

Done when: `milestone-3-benchmark.md` is committed on the branch and its criteria table shows a pass on every gate.

### WP8 Runtime validation (powershell-runtime-validator; validator step)

Owns §11 as verified behaviour, and the parts of §12 checks 1, 2, 5, 6, 7, 8, 13, 15, 18, 19, and 20 that Pester does not cover. A validator step: its done-when is the committed validation files.

Runs after WP1 to WP7 are on the branch and `build/` is fresh.

Prerequisites: the owner's machine; WSL Ubuntu with `/snap/bin/pwsh` and a dotnet SDK (check 6 on Linux, optional when CI has proven it); PSReadLine loadable (check 15); the WP7 scratch clone and `v2.2.0` extract.

Every check runs in its own `pwsh -NoProfile` with §12's preamble, against `$module` = the branch's `build/CompleterActions`, asserting `ModuleBase` first. PS_Completers is read only through the scratch clone.

**Module sources.** 2.2.0 build: the WP7 extract. Branch build: reports `2.2.0` until the release commit, which already satisfies PS_Completers' `-MinimumVersion 2.0.0` and `2.1.0`, so check 19's local half needs no stamped copy. Stamped branch build (`Copy-Item build\CompleterActions <scratch>\stamped\CompleterActions -Recurse`, then `ModuleVersion = '3.0.0'` in the copy's `.psd1` only) is used only where a check wants the version string `3.0.0` itself.

Checks:
- **Check 1.** 11 functions, 0 aliases, the six removed names each `CommandNotFoundException`; for each of the 11, parameter names and sets equal the 2.2.0 build's (check 20's comparison, two processes, `Get-Command` metadata serialised to JSON and diffed).
- **Check 2.** After one `Register-Completer -LiteralPath <conforming fixture> -Lazy`: the roadmap's `-is` line at the prompt; `::new()` of the four types with the property names compared with the four lists in `tests/CompleterClasses.Tests.ps1` as of `550bde9` (`git show 550bde9:tests/CompleterClasses.Tests.ps1`); `PSTypeNames`; enums; `''` defaults; the `-State` bindings; `ConvertTo-Json` with and without `-EnumsAsStrings`; `OutputType` names; `Format-Table` headers. Each as a transcript line in the record.
- **Checks 5 and 6.** Assembly name, version, location, referenced SMA version, no cmdlets; fresh-process imports of both layouts; `Remove-Module` then `Import-Module -Force`.
- **Check 7.** The `Select-String` over `src\**\*.ps1` prints nothing.
- **Check 8.** The WP4 parity harness, run again on the final branch: the two CSVs are attached as `milestone-3-grammar-parity-2.2.0.csv` and `milestone-3-grammar-parity-3.0.0.csv`, and `Compare-Object` over them prints nothing. The corpus count is stated (11 import fixtures, the lazy and set fixtures, 14 scaffold outputs, 173 clone scripts).
- **Check 13.** The deprecated-name `Select-String` with its allowed hits listed.
- **Check 15.** A `Get-PSReadLineKeyHandler -Bound -Unbound` snapshot before and after `Import-Module`, `Import-CompleterSet -LiteralPath <clone>\ps_completers.psd1 -SkipInvalid`, one `TabExpansion2('git ch', 6)` call, and `Test-CompleterScript` over one script, in one live session.
- **Check 18.** `Import-CompleterSet -LiteralPath <clone>\ps_completers.psd1 | Select-Object Key, RuntimeKey, State, Trusted | ConvertTo-Csv` under the branch build and under the 2.2.0 build, in two processes, byte-identical; attached as `milestone-3-set-import.csv`. Then `Export-CompleterSet` from those registrations under both builds into `<scratch>`, and the two files are identical.
- **Check 19, local half.** In the scratch clone, `pwsh -NoProfile -Command '$env:PSModulePath = "<repo>\build;$env:PSModulePath"; Invoke-Pester -Path ./tests -Output Detailed'` passes with the clone's full count, and `(Get-Module CompleterActions).ModuleBase` printed first is `<repo>\build\CompleterActions`. The PSGallery half runs after the candidate release (release recipe step 9).
- **§11 spot checks.** `Reset-Completer -Verbose` output unchanged against the 2.2.0 build; `New-CompleterScript -CommandName rg -Path <scratch>\rg_completer.ps1 -PassThru | Test-CompleterScript` empty under both builds; `Test-CompleterSet -LiteralPath <clone>\ps_completers.psd1` empty under both.

Recording: `docs/roadmap-3.0/validation/milestone-3-runtime.md`, one row per check with the command, the output or a link to the attached CSV, and pass or fail; plus the three CSV files. Commit: `docs(validation): record the milestone 3 runtime checks`.

Acceptance: every check matches §12. Any miss goes back to its package before the pull request is opened.

Done when: `milestone-3-runtime.md` and the CSV files are committed on the branch and every row reads pass.

### WP9 Pull request and release 3.0.0 (owner-run, agent-assisted)

A release procedure, not an implementer package: no `It` blocks and no source change beyond the release commits. The owner runs it; an agent may prepare each command, run the checks, and draft the pull request body and release notes, and stops at every step marked as the owner's. Steps are in "Release recipe for 3.0.0" below. The documents rule applies: the pull request body and the commits report results and never restate an exit criterion.

### WPA Engine-cmdlet path (conditional on question 1)

Only if the owner answers question 1 against the recommendation. After WP3, before WP7. Files: new `src/Core/Engine/CmdletEngine.cs` and the detection in `EngineAccess.Create` (module-qualified lookup through the `SessionState` the wrapper passes), `EnginePath` gains `Cmdlets`, the wrappers `Get-CompleterRegistrationSnapshot`, `Find-RuntimeCompleterRegistration`, `Remove-RuntimeCompleterRegistration`, `Get-Completer`, and `Unregister-Completer` gain the appendix A behaviour and verbose line, a cmdlet double under `tests/Fixtures/EngineCmdletDouble/`, and a new `tests/CompleterEngineCmdlets.Tests.ps1` with appendix A's test strategy items 1 to 6. Verified by checks A1 to A3 of that appendix. Everything in it is written against PR #26680's head `fc26c434` and is re-checked against the merged PR before any release that ships it.

## Order and parallelism

```text
WP1 (assembly, types, build, floor) ──┬──> WP3 (engine access) ──────────────────────────┐
                                      └──> WP4 (grammar) ──> WP5 (grammar at reg/import) ┤
WP2 (remove deprecated surface) ─────────────────────────────────────────────────────────┼──> WP6 (docs) ──┐
                                                                                         └──> WP7 (bench) ─┴──> WP8 (runtime) ──> WP9 rc1 ──> soak ──> WP9 stable
```

- **Day one, in parallel:** WP1 and WP2. Their edits to the manifest, the psm1, and the README are line-disjoint; WP1 merges first.
- **After WP1:** WP3 and WP4, in parallel.
- **After WP4:** WP5.
- **After WP2 and WP5:** WP6; **after WP1 to WP5:** WP7; in parallel.
- **After WP1 to WP7:** WP8, then WP9 to the candidate, the soak, and WP9 to stable.
- **Shared files:** `tests/CompleterRegistration.Tests.ps1` (WP1, then WP3), `tests/CompleterActions.Tests.ps1` (WP2, then WP6), `tests/CompleterSet.Tests.ps1` and `tests/CompleterLazyRegistration.Tests.ps1` (WP5 only). Each later package adds its own `Describe` after the earlier ones. `build/` and the help XML are rebuilt after every merge (rules, "Worktrees and merges").

## Verification checklist

Before the pull request:

- [ ] This plan and the spec were committed to main before the branch was cut, and `git diff main -- docs/roadmap-3.0.md docs/roadmap-3.0/milestone-3-spec.md docs/roadmap-3.0/milestone-3-plan.md` prints nothing.
- [ ] `pwsh -NoProfile -Command "Invoke-Build -Task build"` succeeds in its own process, first, compiling with zero warnings; `build/`'s text files and both help XML files are committed; no `.dll`, `bin/`, or `obj/` path is tracked.
- [ ] The two `Invoke-ScriptAnalyzer` calls of the rules print nothing, in a process separate from Pester.
- [ ] `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes in a new process, including the tracked-build test. The count is reported, not gated (see the estimate).
- [ ] `git ls-files --eol` shows every new or edited text file as `w/crlf` on Windows, `.cs` and `.csproj` included, and none as `i/crlf`.
- [ ] The pre-PR commit check of the rules prints one trailer line and a `Claude-Session` count of 0.
- [ ] `milestone-3-benchmark.md`, `milestone-3-runtime.md`, and the three CSV files are committed under `docs/roadmap-3.0/validation/`.
- [ ] Every §12 check below has passed where it is marked.

| §12 check | Where it is verified |
| --- | --- |
| 1 Surface: 11 functions, 0 aliases, old names fail, parameters unchanged | WP2 Pester; WP8 (2.2.0 parameter comparison) |
| 2 Public types from the prompt | WP1 Pester; WP8 transcript |
| 3 Engine floor 7.4 | WP1 Pester (manifest test); PR CI |
| 4 Release candidate on PSGallery | release recipe steps 9 and 16 |
| 5 The assembly | WP1 Pester; WP8 |
| 6 Fresh process, both layouts; re-import | WP1 Pester; WP8 |
| 7 No reflection outside the compiled layer | WP3 Pester; WP8 |
| 8 Grammar parity | WP4 done-when (harness); WP8 (recorded CSVs) |
| 9 Grammar speed | WP7 |
| 10 Grammar at registration | WP5 Pester |
| 11 Grammar at import | WP5 Pester |
| 12 First tab unchanged | `tests/CompleterLazyRegistration.Tests.ps1` line 388 "marks a strict registration Failed when the script no longer conforms at first tab", unchanged |
| 13 Nothing deprecated remains | WP2 Pester; WP8 |
| 14 Help content | WP6 Pester |
| 15 PSReadLine | existing snapshot tests; WP8 live |
| 16 Performance recorded | WP7 |
| 17 Suite, lint, eight CI legs with Compile | every package's run steps; PR CI |
| 18 Set compatibility both ways | WP8 |
| 19 PS_Completers under the candidate | WP8 (local half, stamped build); release recipe step 9 (PSGallery half) |
| 20 Surface comparison | WP8 |

After the pull request: all eight CI legs are green (Windows and Ubuntu by 7.4, 7.5, 7.6, and preview), each with the `Compile` step, and the owner has reviewed it.

### Traceability: spec section to work package

Every behaviour statement lands in exactly one package. "Verified by" packages only test it.

| Spec section | Owner WP | Verified by |
| --- | --- | --- |
| §1 scope, removal map | none (summary) | WP8 |
| §2 the assembly | WP1 | WP8 (check 5) |
| §2 the types and the eight differences | WP1 | WP6 (migration guide text), WP8 |
| §3 what moves, what does not, the seam | WP3 | WP8 (check 7) |
| §4 same findings, faster | WP4 | WP7 (check 9), WP8 (check 8) |
| §4 where the grammar runs | WP5 | WP8 (§11 spot checks) |
| §5 removed surface | WP2 | WP8 (checks 1, 13) |
| §6 minimum engine 7.4 | WP1 | PR CI |
| §7 build, package, CI | WP1 | every package's run steps; PR CI |
| §8 migration guide and the fourth edition | WP6 (and WP5 for two command-help sentences) | |
| §9 performance | WP7 | |
| §10 release | WP9 | |
| §10 roadmap edits the owner would make | owner (not an agent) | |
| §11 what stays exactly as in 2.2.0 | none (constraint on WP1 to WP5) | existing suite unchanged, WP8 |
| §12 acceptance criteria, run rules | checklist above | |
| §13 questions | this plan's defaults | "Owner decisions by gate" |
| Appendix A measurements | none (reference) | WP7 repeats the two grammar numbers |

No spec section is without a package, and every one of the 20 acceptance checks has a row in the checklist.

## Release recipe for 3.0.0

Decision 6: the milestone ships twice from the same code, first `3.0.0-rc1`, then `3.0.0` after a soak without a defect; a defect means `rc2`. The branch keeps `ModuleVersion = '2.2.0'` until the candidate commit, so the release-policy test holds throughout.

Lessons carried over from milestones 1 and 2 and the 2.0 releases: join dependent steps with `&&`; check the CHANGELOG heading and the link block before tagging; run Pester in its own process with the Stop preamble; run `release_check` on the tagged HEAD; the remote is `origin`; commits follow the commit rule. New for 3.0: the release runner compiles the assembly, so the `Compile` step in `release.yml` is part of what the tag push runs, and the published package is the only 3.0 package that exists (nothing is tracked), which is why step 9 installs it back. Steps marked **owner** are the owner's; the agent prepares them and stops.

### Candidate

1. Run the pre-PR commit check and the documents gate. Open the pull request from `feat/milestone-3-compiled-core` to `main` with `gh pr create`. The body carries the WP7 criteria table, the WP8 check list with links to the validation files, the departures list, and the owner's answers by gate. It does not restate an exit criterion. **Owner:** review and merge after the checklist is complete and CI is green on all eight legs.
2. On `main` (`git pull origin main`), make the release edits:
   - in `CompleterActions.psd1`, set `ModuleVersion = '3.0.0'` and `Prerelease = 'rc1'`, keeping CR LF;
   - in `CHANGELOG.md`, move the Unreleased entries under `## [3.0.0-rc1] - <date>`, leaving `## [Unreleased]` empty above it;
   - update the link block: `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v3.0.0-rc1...HEAD` and a new `[3.0.0-rc1]: https://github.com/tstager/CompleterActions/compare/v2.2.0...v3.0.0-rc1`.
3. `pwsh -NoProfile -Command "Invoke-Build -Task build"` (compiles with `FileVersion` 3.0.0 and `InformationalVersion` 3.0.0-rc1), then in a separate process `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'`. Then, in the WP7 scratch clone, in its own `pwsh -NoProfile`, run the PS_Completers suite with `$env:PSModulePath = "<repo>\build;$env:PSModulePath"`, asserting that `ModuleBase` is `<repo>\build\CompleterActions`. This is check 19 against the real candidate build.
4. `git commit -am "chore(release): bump module version to 3.0.0-rc1"` with the trailer, then `git status --short` prints nothing (the tracked `build/CompleterActions/CompleterActions.psd1` is in the commit; `lib/` is ignored).
5. Version line, on the release commit and before the tag (check 4): in a new `pwsh -NoProfile`, `Import-Module ./build/CompleterActions/CompleterActions.psd1 -PassThru` reports `Version` 3.0.0 and `PrivateData.PSData.Prerelease` `rc1`, and `[CompleterActions.CompleterRegistration].Assembly.GetName().Version` is `3.0.0.0`.
6. `Select-String -Path CHANGELOG.md -Pattern '^## \[3\.0\.0-rc1\]', '^\[3\.0\.0-rc1\]: .*v2\.2\.0\.\.\.v3\.0\.0-rc1$'` matches both.
7. `git tag v3.0.0-rc1 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`.
8. **Owner:** `git push origin main v3.0.0-rc1`, then `gh run watch` on the Release run. The tag has a hyphen, so the GitHub release is marked as a prerelease. The run's `Compile` step must show zero warnings.
9. Confirm:
   - `Find-PSResource CompleterActions -Repository PSGallery -Prerelease` lists `3.0.0-rc1`;
   - `gh release view v3.0.0-rc1` shows a prerelease with the candidate notes;
   - `Install-PSResource CompleterActions -Prerelease -Repository PSGallery` installs it beside 2.2.0, and the installed folder holds `lib/CompleterActions.Core.dll`;
   - in a fresh `pwsh -NoProfile`, `Import-Module CompleterActions -RequiredVersion 3.0.0` imports the installed candidate (a prerelease module's folder is its `ModuleVersion`, `3.0.0`), `(Get-Module CompleterActions).ModuleBase` is under the user module path, and the roadmap's `-is` line prints `True`;
   - the first PS_Completers CI run after the publish (`gh run list --repo tstager/PS_Completers`) installed `3.0.0-rc1` and passed (check 19, PSGallery half); if no run is scheduled, the owner pushes an empty commit or opens a draft pull request there to trigger one. A red run there is attributed before it counts as a candidate defect: the suite is rerun locally in the scratch clone against the installed `3.0.0-rc1` and against 2.2.0; only a failure that disappears under 2.2.0 is a 3.0 defect (a tool's `--help` change or a runner change is not).
10. **Owner:** the roadmap's milestone 3 status row and status line read "Candidate shipped <date> as v3.0.0-rc1" (an edit to `docs/roadmap-3.0.md`, which the documents rule keeps from implementers; an agent makes it only on the owner's explicit go-ahead). Update the live roadmap page and its RAG source in place, as for 2.2.0. The §10 roadmap edits stay with the owner.
11. The soak runs in the owner's profile (`Install-PSResource -Prerelease`, or the stamped build on `PSModulePath`) and on the PS_Completers CI.

### Stable

12. After the soak passes without a defect (a defect: fix it on a branch, merge, and repeat steps 2 to 11 as `rc2`), make the release edits on `main`:
    - in `CompleterActions.psd1`, restore `# Prerelease = ''` (commented);
    - in `CHANGELOG.md`, add `## [3.0.0] - <date>` above the candidate section with a promotion note in the shape of the 2.0.0 one;
    - the link block: `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v3.0.0...HEAD` and a new `[3.0.0]: https://github.com/tstager/CompleterActions/compare/v2.2.0...v3.0.0`.
13. Build, then Pester with the Stop preamble in a separate process.
14. `git commit -am "chore(release): bump module version to 3.0.0"` with the trailer; `git status --short` prints nothing. Then, before the tag: the built manifest reports 3.0.0 with no `Prerelease` (check 4, stable version line), and `Select-String -Path CHANGELOG.md -Pattern '^## \[3\.0\.0\]', '^\[3\.0\.0\]: .*v2\.2\.0\.\.\.v3\.0\.0$'` matches both.
15. `git tag v3.0.0 && pwsh -NoProfile -Command "Invoke-Build -Task release_check"`; then, **owner:** `git push origin main v3.0.0` and `gh run watch`. There is no hyphen, so the GitHub release becomes Latest.
16. Confirm: `Find-PSResource CompleterActions -Repository PSGallery` lists 3.0.0 without a label; `gh release view v3.0.0` shows Latest; `Install-PSResource CompleterActions -Version 3.0.0 -Reinstall` succeeds and imports.
17. **Owner:** the status row reads "3.0.0 released <date>"; the 3.0 roadmap is complete. Update the live page and RAG source.

## Risks

1. **The grammar port drifts from the PowerShell walk.** The catalogue is copied literal by literal and diffed in review (WP4); findings are proven identical over the whole corpus against the 2.2.0 build (WP4 done-when, WP8 record); the 20 authoring tests pin the messages. A difference found later is a defect against §4, fixed in the compiled walk, never by editing a test expectation.
2. **A C# string defaults to `null`.** Choice 3 enforces `''` in the types; the WP1 test asserts it per property, including after a `$null` assignment. A forgotten property shows up there.
3. **The assembly fails to load on one engine.** Built against 7.4.0 and `net8.0`; the eight CI legs are the proof, and the `Compile` step runs on each. A load failure on a leg is a stop for WP1.
4. **`RequiredAssemblies` with a relative path.** `lib/CompleterActions.Core.dll` resolves relative to `ModuleBase` on Windows and under WSL (verified 2026-10-03), and `Update-ModuleManifest` preserves the entry when the dll is present (verified); it rejects the manifest when the dll is absent, which is why `build` copies the dll before updating the manifest (choice 2). CI covers Linux on every leg.
5. **The tracked-build test gets slow and network-dependent.** It now compiles in `TestDrive`; restore uses the local NuGet cache after the first build (about 1 s), and on CI the cache is warm from the `Compile` step. The first `compile` on a fresh machine, a reviewer's WSL included, needs network to fetch `System.Management.Automation` 7.4.0, so an offline proof fails at restore, not in the module. If the test exceeds a minute on a runner, the plan accepts copying `src/Core/bin` and `src/Core/obj` into the staging folder so `dotnet build` is incremental; that is a reviewed change to choice 9, not a skip.
6. **An assembly cannot be unloaded.** A developer who rebuilds the dll and re-imports in the same session runs old code without an error. The rules say every run step is a fresh process; README's development notes say so too (WP6).
7. **PSReadLine neutrality.** Nothing in this milestone touches the stub, key handlers, or `TabExpansion2`; the existing snapshot tests and WP8's live snapshot stand guard.
8. **Pester in the same process as Invoke-Build or PSScriptAnalyzer** breaks the paging tests. The run steps keep them apart.
9. **`Markdown_templates` overwrites hand-edited help** with `-Force`. It is never run; WP5 and WP6 edit the pages by hand.
10. **The release runner builds the only package.** A compiler difference between the owner's machine and `ubuntu-latest` cannot change behaviour of a `net8.0` library built from the same sources, but the published dll is the runner's. Step 9 installs the gallery copy back and runs the `-is` line and the PS_Completers suite on it.
11. **Question 2 changes profile behaviour for a non-conforming set entry.** Only for scripts that would have failed at first tab anyway; `-SkipInvalid` keeps the rest of the set. PS_Completers' 173 scripts all conform (its CI gate), so the owner's profile sees no change. The migration guide says what changes.
12. **The engine-cmdlet seam is untested against a real path.** In 3.0.0 the seam has one path; `EnginePath` and the recorded version are asserted. The design cost is one enum and one property; the risk of shipping speculative cmdlet code is the reason question 1 recommends holding.
13. **PSResourceGet and a module with a dll.** `Publish-PSResource` packs any file in the folder; `Install-PSResource` restores the layout. Nothing special is needed, and step 9 verifies the installed `lib/` folder.
14. **Binary line endings.** `.cs` and `.csproj` are text and follow the CR LF rule; the dll is never committed, so `.gitattributes` is still not needed.
15. **The branch build reports 2.2.0.** Checks that need 3.0.0 by name use the stamped copy and assert `ModuleBase` (WP8).
16. **A newer SDK on the runner adds a warning.** `TreatWarningsAsErrors` with no `global.json` means a runner image that moves to a newer SDK can fail `Compile` with no source change. Response: fix the warning, or add `global.json` with the current major and `rollForward: latestFeature`, as a reviewed change to choice 1.
17. **A locked assembly blocks the build.** A `pwsh` that imported the repository build holds `CompleterActions.Core.dll`; `clean`, the `compile` copy, and the tracked-build test then fail with `being used by another process`. The run-steps rule says no such process may exist before step 1; the response is `Get-Process pwsh`, close the holder, rerun.
18. **The PS_Completers CI turns red for an unrelated reason** the day it installs `3.0.0-rc1`. Release step 9 attributes a red run before it counts as a candidate defect.

## Owner decisions by gate

An unanswered item means its default applies. Implementers never stop for an unanswered item; the orchestrator asks the owner before the gate and proceeds with the default when no answer has come. The one exception is the first row: the owner's go-ahead on the plan and the spec is the start signal.

| Due before | Item | Default if unanswered | An answer against the default changes |
| --- | --- | --- | --- |
| Branching | Commit this plan and the spec to main (`docs(roadmap): add the milestone 3 spec and plan`), and confirm the branch name `feat/milestone-3-compiled-core` | none: this is the start signal | nothing starts |
| WP1 starts | §13 question 3, `''` string defaults | `''` | choice 3's setters and the WP1 default tests |
| WP1 starts | §13 question 6, tracking the assembly | not tracked | choice 2's `.gitignore`, choice 9's test, and the `git archive` wording in §7 and WP6 |
| WP1 starts | §13 question 7, `net8.0` and SMA 7.4.0 | as recommended | the csproj and the loading proof |
| WP1 starts | §13 question 8, `Severity`/`Construct` as strings | strings | the finding type and every test that reads them |
| WP1 starts | Open item 2, where the dll sits | `lib/` under the module folder | choice 2's paths, the `.gitignore` patterns, and `RequiredAssemblies` |
| WP1 starts | Open item 3, the `Compile` step's position in CI | before Lint | choice 10's step order in both workflows |
| WP3 starts | §13 question 1, the engine-cmdlet path | hold; no WPA | adds WPA after WP3; `EnginePath` gains `Cmdlets`; appendix A's checks join §12 |
| WP3 starts | §13 question 5, the `Internal` namespace is not a contract | accept | a stable API design, out of this plan's scope |
| WP4 starts | §13 question 4, the lazy stub stays PowerShell | stays | a compiled stub in WP4 and a change to `New-CompleterLazyStub` |
| WP5 starts | §13 question 2, grammar at registration and import | run it | WP5 is dropped whole (alternative A), or gains `Export-CompleterSet` work (alternative B, which needs a spec amendment first) |
| WP6 starts | §13 question 9, removed names fail with PowerShell's own error | accept | not applicable (a module cannot intercept a name it does not export) |
| Pull request | The alarm test for the engine cmdlets stays | stays | removed before the PR |
| Release | §10 roadmap edits 1 to 6; §13 question 10 | as recommended | the owner's roadmap edits |

## Open items for the owner

1. **§13 questions 1 to 10.** The plan follows every recommendation.
2. **Where the dll sits** (choice 2, `lib/`). An internal choice the owner may overrule before WP1 starts; nothing else depends on it.
3. **The `Compile` step's position in CI** (choice 10, before Lint). Lint does not need it; Test does. Putting it first keeps a compile failure the first red step.

## Estimated new Pester tests

| Package | File | New `It` blocks | Removed `It` blocks | Test cases |
| --- | --- | --- | --- | --- |
| WP1 | `tests/CompleterClasses.Tests.ps1`, `tests/CompleterRegistration.Tests.ps1` | 11 (plus 2 modified) | 3 | about 30 |
| WP2 | `tests/CompleterActions.Tests.ps1`, `tests/CompleterDeprecation.Tests.ps1` (deleted) | 3 | 9 (plus 1 case) | 8 new, about 20 removed |
| WP3 | `tests/CompleterRegistration.Tests.ps1` | 4 | 0 | 6 |
| WP4 | none | 0 | 0 | 0 |
| WP5 | `tests/CompleterLazyRegistration.Tests.ps1`, `tests/CompleterSet.Tests.ps1` | 9 (plus 1 rewritten) | 0 | 10 |
| WP6 | `tests/CompleterActions.Tests.ps1` | 3 | 0 | 5 |
| Total | | about 31 | 12 | about 59 new, about 25 removed |

That takes the suite from 615 test cases (the 2.2.0-preview1 count, roadmap) to about 650, across thirteen test files (fourteen today, less `CompleterDeprecation.Tests.ps1`). The number is an estimate, not a gate: milestones 1 and 2 both landed above their `It` estimates, so a larger count is expected and is not a defect. The platform skips of 2.2.0 are unchanged; WP1 to WP6 add no platform-specific test.
