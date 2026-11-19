# CompleterActions repository review

Reviewed on November 18, 2026 at `ce5feb6da5ce1306f0cf2889db9b3ecbfa548a39` on `main`. The manifest identifies this checkout as `3.0.1-preview1`. Six GPT-6.2 Astra reviewers covered the repository. The coordinating reviewer checked each retained finding against the source and independently repeated three registration probes against a freshly compiled copy.

The review identified **18 findings: two P1, twelve P2, and four P3**. Address the two strict-import issues first. For callers that use the module to verify completers in CI, finding 5 also deserves early attention because it can make a broken registration appear to work.

Status: **all eighteen findings fixed, merged to `main` through PR #13 (`8705a1b`), and released in 3.0.1-preview2** (`4b8325c`, tag `v3.0.1-preview2`, 2026-11-18). Stable 3.0.1 follows the preview soak. See Resolution.

## Findings that affect strict import

Both P1 findings affect the isolation that callers rely on when they import an unfamiliar completer without `-Trusted`. Both follow from the source. The review did not exercise a security bypass.

1. **P1 · Strict import can execute a different revision from the one it validated.** The importer validates a file and then passes its path to the capture module. The validator parses from disk. The capture module subsequently opens the path again to run it. A concurrent save between those operations separates the conformance decision from the executed content. First-tab loading goes through the same importer. Execute the validated snapshot and preserve its source filename, `$PSScriptRoot`, and `$PSCommandPath`. A regression check should cover both eager import and first-tab loading with two benign revisions. [Importer](../src/Public/Import-CompleterScript.ps1#L112) · [Parser](../src/Private/Get-CompleterScriptParseResult.ps1#L30) · [Capture module](../src/Private/Import-CompleterScriptDefinition.ps1#L83)

2. **P1 · Strict import permits helper definitions to change caller-global function state.** The grammar accepts a function definition at script scope. Its subsequent name check protects three built-ins and allows other explicitly global helper names. Defining such a helper changes the caller's function table during import, even if its body never runs. Validate the destination scope of a definition as well as its name. Preserve ordinary helpers local to the capture module. [Statement check](../src/Core/Grammar/StrictGrammar.cs#L405) · [Name check](../src/Core/Grammar/StrictGrammar.cs#L677) · [Capture scope](../src/Private/Import-CompleterScriptDefinition.ps1#L83)

## Registration and completion

3. **P2 · Editing a query result can change module-owned state.** Active, pending, and failed records returned by `Get-Completer` share identity with objects in the managed table. Register and reset also expose stored objects through `-PassThru`. In a fresh process, changing a returned record's `State` to `Failed` caused the next query to report both `Failed/Managed` and `Conflicted/Discovered` for an untouched live registration. Changing its `ScriptPath` also changed subsequent query output. Return detached records at public output boundaries and test edits to both state and reload metadata. [Storage](../src/Private/Add-ManagedCompleterRegistration.ps1#L62) · [Query](../src/Public/Get-Completer.ps1#L203) · [Register](../src/Public/Register-Completer.ps1#L409) · [Reset](../src/Public/Reset-Completer.ps1#L240)

4. **P2 · Collection-valued flags can select the wrong target and trust tier.** Input-object binding casts every non-string flag to Boolean. A registration specifying a parameter and supplying a two-element array of false values for each of `Native` and `Trusted` returned `IsNative=True`, `Trusted=True`, and an empty parameter name. Reject collections and unsupported objects before coercion. Retain the documented scalar Boolean, numeric, text, and null forms. [Conversion](../src/Private/Resolve-CompleterInputObject.ps1#L76) · [Public contract](../src/docs/CompleterActions/Register-Completer.md#L292)

5. **P2 · Registration tests can credit the wrong completer.** After checking that the requested target exists, the command assigns its key to every match from `TabExpansion2`. In a two-parameter command, testing the first parameter with the cursor on the second returned the second parameter's unique suggestion under the first parameter's key. Even with the correct target and cursor, a fixture that only emits `alpha` and `beta` received credit for PowerShell's filesystem suggestion `.\README.md` (`ProviderItem`). Assertions against these results can pass while the requested completer contributes nothing. Distinguish observed engine results from verified contributions, and cover both mismatched parameters and provider fallback. The help should also disclose that testing a pending lazy registration can activate it, a previously documented discrepancy reconfirmed in this review. [Completion and labeling](../src/Public/Test-CompleterRegistration.ps1#L175) · [Output contract](../src/Public/Test-CompleterRegistration.ps1#L59)

6. **P2 · A failed lazy load can overwrite a newer managed registration.** A trusted loader replaced its own target through `Register-Completer -Force` and then raised an ordinary initialization error. The replacement remained live, but querying it returned the obsolete stub as failed and the working replacement as a discovered conflict. Failure cleanup checks runtime ownership before removal, then writes a failed managed record unconditionally. Check that the original managed record still owns the slot before recording failure. [Failure cleanup](../src/Private/Invoke-CompleterLazyStub.ps1#L165)

## Script and set validation

7. **P2 · Conformance accepts registrations that PowerShell cannot bind.** Duplicate `-CommandName` parameters, and a `-CommandName` immediately followed by `-Native` without a value, both produced zero findings. Eager import then failed with duplicate-parameter and missing-argument errors respectively. The grammar replaces the pending parameter and ignores the result of adding a name to the seen set. Report both conditions at the offending parameter so conformance can catch them before import. [Parameter walk](../src/Core/Grammar/StrictGrammar.cs#L502)

8. **P2 · A script containing only a named block aborts a conformance scan.** For the syntactically valid input `begin { }`, the validator records the unsupported block, then throws because the AST has no end block. The caller receives a terminating error instead of the structured finding, and later paths in the same call go unchecked. Preserve the named-block finding and skip the absent end block. [Grammar](../src/Core/Grammar/StrictGrammar.cs#L619) · [Public validation loop](../src/Public/Test-CompleterScript.ps1)

9. **P2 · Export resolves relative input paths against the wrong directory.** After `Push-Location` into a directory containing a completer, exporting a record with a relative `SourcePath` resolved it against the process working directory. A trusted export wrote a reference to the wrong tree and warned that hashing failed. Strict export can fail even though the file exists at the caller's PowerShell location. Resolve relative filesystem paths through the invoking session before grouping and hashing. [Path conversion](../src/Public/Export-CompleterSet.ps1#L185)

10. **P2 · Export can merge two scripts whose filenames differ only by case.** File grouping uses a case-insensitive ordered hashtable on every platform. Exporting trusted records for `Alpha.ps1` and `alpha.ps1` with different targets produced one entry with two targets. The grouping was reproduced on Windows using the supported missing-trusted-file case. On a case-sensitive filesystem the two names can identify different files, so a round trip can assign a target to the wrong script. Use a file-path comparer for grouping and exercise a round trip with two real case-distinct files on Linux. Lazy sibling loading also assumes Windows and macOS paths are case-insensitive. Its test skips both operating systems, leaving case-sensitive volumes there uncovered. [Export grouping](../src/Public/Export-CompleterSet.ps1#L173) · [Sibling lookup](../src/Private/Invoke-CompleterLazyStub.ps1#L119) · [Platform test](../tests/CompleterLazyRegistration.Tests.ps1#L864)

11. **P2 · One malformed path defeats per-entry recovery.** Given an entry with a null character in its path followed by a valid entry, both `Import-CompleterSet -SkipInvalid` and `Test-CompleterSet` terminated with “Null character in path.” Path normalization throws before the resolver can classify the entry. Convert path-format exceptions into an entry finding, keep diagnostic formatting safe for unresolved paths, and verify the valid peer still imports. [Entry resolver](../src/Private/Resolve-CompleterSetEntry.ps1#L155)

12. **P3 · A Boolean is accepted as the set schema version.** A fixture with `Version = $true` imported three records. PowerShell's coercive comparison treats the integer on the right as true when the left operand is Boolean. Validate the supported scalar version representation explicitly before comparing it with version 1. [Schema check](../src/Private/Import-CompleterSetDefinition.ps1#L77)

## Scaffold, build, and delivery

13. **P2 · Two generated standalone completers can share the wrong catalog.** Scaffolds for `ca-tool` and `ca_tool` with distinct subcommands generated identical helper and catalog names. After both were dot-sourced, real tab completion returned the first command's subcommand for both. Importing each file in its own capture module isolates this case. Give generated private identifiers a collision-resistant identity and test the documented standalone use with both scripts loaded. [Name normalization](../src/Private/ConvertTo-CompleterScriptStem.ps1#L41) · [Catalog generation](../src/Private/Get-CompleterScriptSkeleton.ps1#L72)

14. **P2 · The release gate can validate a different tag from the one being published.** The build checks whichever exact tag `git describe` selects. The workflow creates the release for `GITHUB_REF_NAME`. With an annotated expected tag and a differently named lightweight tag on the same commit, a disposable Git repository returned the expected tag from `git describe` for either event. Compare the actual event tag with the manifest-derived tag before publication. [Tag check](../CompleterActions.build.ps1#L460) · [Release workflow](../.github/workflows/release.yml#L115)

15. **P2 · A partial release is difficult to retry.** Gallery publication, asset preparation, and GitHub release creation occur sequentially in one job. If Gallery publication succeeds and a later step fails, retrying the job attempts to publish the same package version again before reaching the failed step. Give the two publication stages independent retry boundaries, or verify that an already published artifact matches before continuing. This finding follows from the workflow order. No publication or remote retry was performed. [Gallery publication](../.github/workflows/release.yml#L57) · [Asset preparation](../.github/workflows/release.yml#L64)

16. **P3 · Packaging can strip a literal line from a function.** The packer hoists lines that resemble `using` statements without checking their AST location. Applied to a valid function containing a here-string whose content was `using namespace System.Text`, the build's transformation changed the function's return value from that text to an empty string. This was tested with the transformation in isolation. The current module sources contain no identified triggering literal. Hoist only top-level using-statement AST extents. [Source transformation](../CompleterActions.build.ps1#L226)

17. **P3 · Release notes can come from a neighboring version.** The changelog heading regex accepts a matching prefix. Applying the stable `3.0.1` pattern to this checkout selected the existing `3.0.1-preview1` section despite the absence of a stable heading. Require the entire heading version to match before using its body. [Changelog selection](../.github/workflows/release.yml#L76)

18. **P3 · The repository quick starts omit a required compile step.** Both examples import a manifest directly. Both require a DLL excluded from Git. A fresh clone needs `Invoke-Build -Task compile` before either import example works. The build instructions farther down the README explain this prerequisite. Put it beside the first checkout import. [Quick starts](../README.md#L62) · [Compile task](../CompleterActions.build.ps1#L51)

## Coverage and interpretation

The review covered all eleven public commands, the private PowerShell helpers, the C# grammar, engine access and public types, bootstrap, formatting, tests and fixtures, help and generated package, benchmark tooling, and CI and release workflows. The checkout contained 219 tracked files. The November 10 report records the resolution of its eight findings in preview1. Those historical findings were not carried forward as open.

Two additional observations help interpret the scope. The scaffold help parser can collect `HOME` as a subcommand when an environment-variable section immediately follows the commands without a blank line. This is a limitation of the specified heuristic, which also supports wrapped descriptions. Package containment uses normalized path text, and the conceptual help explicitly states that links are not resolved. The review therefore treats this behavior as a documented boundary. [Help parser](../src/Private/ConvertFrom-CompleterHelpText.ps1#L109) · [Package contract](../en-US/about_Completer_Sets.help.txt#L665)

## Validation

Builds and tests ran in disposable, full-history local clones of the reviewed commit. The original checkout was used for source inspection and the report. The primary runtime was Windows PowerShell Core `pwsh 7.7.0`, with profile loading disabled and Pester pinned to CI's `6.1.0`.

| Check | Observed result |
| --- | --- |
| `Invoke-Build -Task compile` | Succeeded with zero compiler warnings and zero errors. |
| `Invoke-Build -Task build` in a second clone | All four tasks succeeded. The regenerated tracked package differed by one line, the manifest's generated-on date. |
| Configured PSScriptAnalyzer on `src`, `tests`, and `tools` | Zero findings. |
| Full Pester suite on Windows, PowerShell 7.7.0, inherited PATH | **753 passed, 15 failed, 12 skipped** in 646.2 seconds across 13 files. Six failures were in help probes, eight in scaffolding, and one in the package PSReadLine test. |
| Focused help-probe and scaffold rerun with the real PowerShell directory first on PATH | 153 passed, 3 failed, 4 skipped. All three remaining failures asserted the nested child's `-WhatIf` message. The child output included `COUNT=0` and `EXISTS=False` in the parameterized cases. |
| Package PSReadLine test under the same PATH adjustment | 1 passed, 0 failed. |
| Selected WhatIf and PSReadLine cases with portable PowerShell 7.6.9 | 7 passed, 0 failed, 1 skipped. The filter excluded 170 other cases. |

The Windows resolver reported `CanRun=False` for the app-execution alias because its executable header could not be read. It reported `CanRun=True` for the actual PowerShell executable. Source inspection and focused runtime checks also confirmed findings 3, 4, 5, 7, and 8 independently of the suite. Hosted CI, Linux and macOS runtimes, and actual Gallery or GitHub publication were outside this local validation.

## Resolution

All eighteen findings were fixed on branch `fix/review-2026-11-18`, one `--no-ff` merge per finding. The branch was merged to `main` through PR #13 (`8705a1b`) on 2026-11-18 after hosted CI passed on all eight jobs, and the fixes were released the same day as 3.0.1-preview2 (release commit `4b8325c`, tag `v3.0.1-preview2`), a prerelease on the PowerShell Gallery and on GitHub. Each finding had an Opus implementer and a two-round adversarial review by Haiku and Sonnet; six packages (findings 1, 3, 7, 9, 12, and 14) took a final fix after round 2 that no reviewer re-checked. The packaged module was regenerated (`6e373a0`). The behaviour changes are listed under `[3.0.1-preview2]` in CHANGELOG.md.

| Finding | Status | Merge | Residual |
| --- | --- | --- | --- |
| 1 | Fixed with a stated residual | `bc5e393` | The literal-path lookup relies on `GetCommand` resolving a pattern and then a plain path; the importer fails closed when neither finds the resolved file. Final fix not re-reviewed. |
| 2 | Fixed with a stated residual | `c03e390` | A `global:` definition inside a function or completer body runs at completion time and is still accepted. |
| 3 | Fixed | `406e9ea` | Final fix (test only) not re-reviewed. |
| 4 | Fixed with a stated residual | `2413b13` | `Int128`, `UInt128`, `Half`, `Complex`, and `IntPtr` are refused rather than read as numbers. |
| 5 | Fixed with a stated residual | `515ed34` | Attribution matches by text and records only the first engine call. |
| 6 | Fixed | `5e46aa7` | |
| 7 | Fixed with a stated residual | `3e24cfe` | `-ParameterName 'a', 'b'` is still accepted by the grammar and the strict capture, though the real cmdlet cannot bind it. Final fix not re-reviewed. |
| 8 | Fixed | `679f8c7` | |
| 9 | Fixed with a stated residual | `ead5d88` | The output `-Path` of `Export-CompleterSet` has the same provider-qualified relative-path issue. Final fix not re-reviewed. |
| 10 | Fixed with a stated residual | `1218f2e` | Case-sensitive volumes on Windows and macOS are still treated as case-insensitive; the Linux test runs only on Linux. |
| 11 | Fixed with a stated residual | `01bf66d` | A null character in a manifest's `PrivateData.CompleterSet` still ends `Test-CompleterSet` for that set. |
| 12 | Fixed | `fbaef6a` | Final fix not re-reviewed. |
| 13 | Fixed with a stated residual | `d587dbd` | `docs/roadmap-3.0/milestone-2-spec.md` still describes the old stem rule. |
| 14 | Fixed with a stated residual | `0043b42` | A local `release_check` with no tag push still compares the tag `git describe` picks. Final fix not re-reviewed. |
| 15 | Fixed with a stated residual | `18b19f4` | The rerun test skips on Windows and was not run against a server that refuses a repeat publish; a rerun on a different SDK fails on a differing DLL. |
| 16 | Fixed | `c7f9a37` | |
| 17 | Fixed | `42101cc` | |
| 18 | Fixed | `cc1c31f` | |

Integration checks on the branch, Windows, pwsh 7.7.0: `Invoke-Build -Task compile` and `-Task build` succeeded, and a second build changed no tracked file. Configured PSScriptAnalyzer on `src`, `tests`, and `tools` reported zero findings. The full Pester suite, with the real PowerShell directory first on PATH, gave **867 passed, 3 failed, 14 skipped**; the three failures are the scaffold `-WhatIf` child-process assertions, which fail identically on `main` (104 passed, 3 failed in that file). The PS_Completers conformance tests passed 322 of 322 against the built package, and strict `Import-CompleterScript` imported all 175 completer scripts (370 records). Those checks ran before the pull request; hosted CI and the release workflow have since passed. macOS was not exercised.

A final review of the whole branch (Fable, 2026-11-18) accepted it with follow-ups and found no P1 and no regression against `main`. It reproduced findings 1 to 9, 11, 12, 14, and 16 on `main` and showed them closed on the branch, and confirmed that reverting each of the six final fixes fails its test. In a Linux container (pwsh 7.4.2, Pester 5.8.0) the ten test files the fixes touch gave 724 passed, 0 failed, 26 skipped. Its follow-ups: three changelog clauses described defects `main` never had (corrected), the help did not say that returned records are copies (added to `Get-Completer`), the capture module's `ScriptInfo` parameter name can collide with a script's own state variable (open, P3), and command names that differ only by letter case still share a scaffold stem on a case-sensitive file system (open, P3).
