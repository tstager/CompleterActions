# Milestone 4 plan: breaking surface and release

Drafted: 2026-09-21
Base: main at `70142de` (2.0.0-preview3 plus roadmap decision 6)
Roadmap: `docs/roadmap-2.0.md`, milestone 4. Ships as `v2.0.0-rc1` first, then `v2.0.0` from the same code (decision 6).

## Current-state facts the plan builds on

- Eight public functions, filename-driven export (`CompleterActions.psm1`, manifest `FunctionsToExport`). `AliasesToExport` is empty and the build's `Update-ModuleManifest` data only sets `FunctionsToExport`.
- Every record is a `[pscustomobject]` stamped with a `PSTypeName` string: `CompleterActions.CompleterRegistration` (`New-CompleterRegistrationRecord`), `CompleterActions.ImportedCompleterRegistration`, `CompleterActions.CompleterScriptFinding`, `CompleterActions.CompletionMatch` (built inline in `Test-CompleterRegistration`), plus internal `CompleterTarget`, `CompleterRegistrationSnapshot`, `ResolvedInputObject`. `CompleterActions.Format.ps1xml` selects views by those strings.
- `State` is a `[ValidateSet('Active','Pending','Failed','Stale','Conflicted')]` string; `Source` (`Managed`/`Discovered`) is a separate property. A clean runtime-only registration today reads `State = Active, Source = Discovered`. There is no `Discovered` state.
- `Get-CompleterRegistration` has independent `-ManagedOnly`/`-DiscoveredOnly` switches and no sort: output order is the insertion order of an ordered hashtable. `Export-CompleterSet` calls `Get-CompleterRegistration -ManagedOnly` internally.
- Key inference lives in one helper, `Test-CompleterNativeKeyShape`, called from `Resolve-CompleterTargetList` (the `ByKey` set) and two fallback branches in `Resolve-CompleterInputObject`.
- Class loading gap: `CompleterActions.psm1` dot-sources only `Private` then `Public`; `CompleterActions.build.ps1` already unions a `src/Classes` folder but lists it last, so a class would be emitted after the functions that reference it. Both orderings must change.
- `src/Bootstrap.ps1` is the once-per-import hook. `en-US/about_*.help.txt` files are globbed into the package with no build change.
- Set import and export derive targets from the AST or the set file (`CommandName` plus `Native`/`ParameterName` literals), never from colon strings.

## Class and enum model

New folder `src/Classes`, one file per type, loaded before `Private` and `Public` in both the source psm1 and the packaged psm1.

| File | Type |
| --- | --- |
| `CompleterState.ps1` | `enum CompleterState { Active; Stale; Conflicted; Pending; Failed; Discovered }` |
| `CompleterType.ps1` | `enum CompleterType { Native; Parameter }` |
| `CompleterRegistration.ps1` | `class CompleterRegistration` |
| `ImportedCompleterRegistration.ps1` | `class ImportedCompleterRegistration` |
| `CompleterScriptFinding.ps1` | `class CompleterScriptFinding` |
| `CompletionMatch.ps1` | `class CompletionMatch` |

PowerShell classes cannot carry a dotted name, so each class keeps a bare name and its constructor inserts the existing dotted `PSTypeName` string at position 0 of `PSObject.TypeNames`. The format file, the tests that assert on `PSTypeNames`, and duck-typed private helpers need no change. The dotted string stays the only cross-boundary contract; the CLR class name is an implementation detail. Class property names match today's pscustomobject shape exactly so pipe-back-by-property-name keeps binding.

Gotchas to build against: definition before use in both load orders; classes are private to the module session state, so `-is [CompleterRegistration]` only works inside the module (document, do not work around with Add-Type); `OutputType` is metadata only, so every constructor must genuinely return the class; give reference-type properties explicit `$null` defaults; enum values that cross a remoting boundary deserialize as `Deserialized.CompleterState` (one-line caveat in the migration topic).

## Alias and deprecation mechanism

- Three aliases created in `src/Bootstrap.ps1` with `New-Alias`, listed in `AliasesToExport` in the source manifest, and added to the build's `Update-ModuleManifest` data.
- Each alias points at a private legacy wrapper (`Get-CompleterRegistrationLegacy`, `Register-CompleterRegistrationLegacy`, `Unregister-CompleterRegistrationLegacy`), not at the new command. The wrapper records its own name in a module-scope `HashSet[string]` initialised in Bootstrap, emits one `Write-Warning` the first time per session naming the new command and `about_CompleterActions_Migration`, then forwards to the new command. Once per process, not per call, so a profile that calls it 169 times warns once.
- The wrappers copy `SupportsShouldProcess`/`ConfirmImpact` from the commands they wrap so `-WhatIf` and `-Confirm` flow through, and take pipeline input in a `process` block.
- The legacy Get wrapper keeps `-ManagedOnly` and `-DiscoveredOnly` as deprecated parameters and translates them: `-ManagedOnly` becomes `-State Active,Pending,Failed,Stale`; `-DiscoveredOnly` becomes `-State Discovered,Conflicted`. `Get-Completer` itself never gains those switches.

## Parameter design after the contract change

- `Get-Completer`: sets `All` (default), `Native` (`-CommandName`, `-Native`), `CommandParameter` (`-CommandName`, `-ParameterName`). The `ByKey` set is removed. `Key` and `RegistrationKey` stay `ValueFromPipelineByPropertyName` so piped records bind, and a piped record always carries `IsNative`, so no inference is needed. `-State [CompleterState[]]` on every set. `SupportsPaging` unchanged.
- `Register-Completer`: unchanged sets (`Explicit`, `InputObject`, `LazyPath`, `LazyLiteralPath`); `Resolve-CompleterInputObject` stops inferring from bare `Key`/`RegistrationKey`/`RuntimeKey` and throws an explicit error naming the migration topic.
- `Unregister-Completer`: `ByKey` typed set removed; pipeline-by-property-name retained; `-AllowUnmanaged` unchanged.

## Work packages

Each package is its own commit or small commit group on `feat/milestone-4-breaking-surface`. Run the full Pester suite in its own `pwsh -NoProfile` process after every package, and `Invoke-Build -Task build` in another process before committing so the tracked build output stays in sync.

### WP1 Classes and enums foundation

Files: the six new `src/Classes` files; `CompleterActions.psm1` (add `Classes` first in the folder list); `CompleterActions.build.ps1` (order `Classes` first in `$sourceFolders`, or give it a preceding loop).
Acceptance: source manifest import and a fresh build import both succeed in separate profile-free processes; the packaged psm1 defines classes before any function.
Tests: new `tests/CompleterClasses.Tests.ps1` constructing each class, asserting property names match today's records one to one, `PSTypeNames[0]` equals the dotted name, and the enum values match the roadmap list.

### WP2 Wire classes into the constructors (no behaviour change)

Files: `New-CompleterRegistrationRecord`, `New-ImportedCompleterRegistration`, `New-CompleterScriptFinding` return class instances with `[OutputType]` updated; extract the inline match construction in `Test-CompleterRegistration` into a new private `New-CompletionMatch`.
Acceptance: the existing 187 tests pass unchanged; `Format-Table` output is visually identical.

### WP3 Explicit target contract

Files: delete `Test-CompleterNativeKeyShape`; remove the `ByKey` set from `Resolve-CompleterTargetList`; delete the two fallback branches in `Resolve-CompleterInputObject` and replace them with an actionable error; drop the typed `-Key` set from Get and Unregister while keeping the property-name bindings.
Acceptance: set import and export are untouched (verified at runtime in WP7, not by grep alone).
Tests: rewrite the colon-style `-Key` literals in the test files as explicit targets or as pipe-back round trips; add negative tests for a bare `Key` input object with no native indicator.

### WP4 Rename nouns, wrappers, aliases

Files: rename the three public files and functions; add the three private legacy wrappers; Bootstrap alias creation and warning set; manifest `FunctionsToExport` and `AliasesToExport`; build `AliasesToExport`; switch internal callers (`Export-CompleterSet`, help examples) to the new names.
Acceptance: `Get-Command -Module CompleterActions` shows eight functions and three aliases; each old name warns exactly once per process (`-WarningVariable`, called twice); `-WhatIf` through an alias behaves as through the new name.
Tests: new deprecation test file running in its own process; mechanical rename across the six existing test files except the cases that deliberately exercise the aliases.

### WP5 State enum and single filter

Files: `New-CompleterRegistrationRecord` takes `[CompleterState]`; `Get-Completer` replaces the two switches with `-State [CompleterState[]]` and computes each candidate's state once before filtering.
Semantics: `Discovered` means a runtime registration with no managed record and no conflict. This is a behaviour change: a clean discovered record moves from `Active` to `Discovered`, and `Active` is reserved for managed records that match the runtime. Flag it prominently in the changelog and migration topic.
Acceptance: `Get-Completer -State Conflicted` returns typed filtered records; an array of states returns the union; no `-State` returns everything as today.
Tests: rewrite the `ManagedOnly`/`DiscoveredOnly` assertions; add a test that a bare `Register-ArgumentCompleter` registration reports `Discovered`.

### WP6 Promised sort order

Files: `Get-Completer` end block sorts by `CompleterType`, `CommandName`, `ParameterName` before paging.
Acceptance: paging with `-First` across several calls, with an unrelated target mutated between pages, neither skips nor duplicates an item. Insertion of an item that sorts before the current page is a documented limitation.
Tests: sort-order and paging-under-mutation cases.

### WP7 Runtime validation pass (powershell-runtime-validator)

All in `pwsh -NoProfile` against `build/CompleterActions`: `Get-Completer -State Conflicted` against a live conflict; each alias warning once per process; `Import-CompleterSet` over `C:\Users\Trent\OneDrive\Documents\PowerShell\Completers\ps_completers.psd1` with zero edits; `TabExpansion2` and `Test-CompleterRegistration` against class-typed records; the PSReadLine snapshot tests; the Completers repo gate `tests/Completers.Tests.ps1`, including a check that nothing there filters on `State`.

### WP8 Migration docs

Files: `CHANGELOG.md` section for 2.0.0-rc1 (rename table, target contract, State consolidation with the `Discovered` change called out, sort order, typed output); new `en-US/about_CompleterActions_Migration.help.txt` with before and after samples and the class-versus-PSTypeName note; refresh `.github/copilot-instructions.md` and the README for the new names.
Acceptance: `Get-Help about_CompleterActions_Migration` resolves after import.

### WP9 Manifest, build, release candidate

Files: manifest `Prerelease` becomes `rc1`; rebuild and commit the tracked output; PR to main; tag `v2.0.0-rc1` per the prerelease recipe (release_check on the tagged HEAD, changelog heading verified before tagging, every step joined with `&&`). After the soak, a second commit removes `Prerelease`, cuts the `## [2.0.0]` heading, and tags `v2.0.0`.

## Risks

1. Class ordering breaks only in the packaged build if just one of the two load orders is fixed. WP1 tests both in separate processes.
2. `Discovered` as a state silently changes `$_.State -eq 'Active'` checks on runtime-only records. Called out prominently, not buried under typed output.
3. Large mechanical rename surface across tests. WP4 and WP5 stay separate commits so a regression can be bisected.
4. Legacy wrappers must forward `ShouldProcess` context faithfully. Wrappers copy the attributes, and WP7 runs `-WhatIf` through the alias.
5. A set entry could in theory have leaned on the deleted inference path. WP7 imports the real 169-script set rather than trusting a grep.
6. Cross-runspace class identity surprises. Documented as a limitation; no compiled types in this milestone.

## Open decisions

| # | Question | Recommendation |
| --- | --- | --- |
| 1 | Dotted class names | Bare class names plus the dotted `PSTypeName` inserted in the constructor; format file untouched. |
| 2 | Legacy `-ManagedOnly` translation | Wrapper calls `-State Active,Pending,Failed,Stale`; `-DiscoveredOnly` calls `-State Discovered,Conflicted`. |
| 3 | `-State` scalar or array | Array; a scalar still binds. |
| 4 | Keep a typed `-Key` parameter | Drop the typed `ByKey` sets; keep property-name binding for piped records. |
| 5 | Typed output scope | All eight commands, including findings and completion matches, to avoid a second typing break later. |
| 6 | Set-related record class | None; set commands emit `CompleterRegistration` records already. |
