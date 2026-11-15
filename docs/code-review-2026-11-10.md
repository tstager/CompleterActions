# CompleterActions code review — 2026-11-10

- Reviewed commit: 91a75507d81df656aa6e7c0660c203fc5e91fb0b
- Version: 3.0.0
- Scope: repository-wide, report only; no product-code or test changes
- Review team: GPT-6 Astra at max reasoning, with independent validation by the coordinating agent
- Status: **four findings fixed on branch `fix/review-2026-11-10`, not yet merged to `main` or released; four still open** (CA-2026-11-02, -03, -05, -07). See Resolution.

## Assessment

The review found an import-time file-write violation in the default strict importer, two registration-identity defects, three set/serialization defects, and two build/help defects. These are fresh reproductions against the reviewed commit, not a restatement of the September reviews.

Compilation, isolated packaging, and configured static analysis passed. The full local Pester run did not pass: 629 passed, 15 failed, and 8 skipped. The failures concern PowerShell app-alias resolution in probe tests. Focused reruns eliminated twelve failures; three nested-child WhatIf assertions remain environment-sensitive. See the validation section for exact counts and limits. Passing the existing checks would not cover the eight findings below.

| ID | Priority | Finding |
| --- | --- | --- |
| CA-2026-11-01 | P1 | Strict eager import accepts redirection inside a target-array expression |
| CA-2026-11-02 | P2 | Script text equality mistakes an external replacement for the managed block |
| CA-2026-11-03 | P2 | Native and parameter targets collide after explicit type information is discarded |
| CA-2026-11-04 | P2 | An empty filtered pipeline exports all managed script registrations |
| CA-2026-11-05 | P2 | Larger exported sets exceed the reader's data-evaluation limit |
| CA-2026-11-06 | P2 | Typographic apostrophes break generated set data and lazy stubs |
| CA-2026-11-07 | P2 | Packaged commands ignore the generated external help |
| CA-2026-11-08 | P2 | The documented Markdown_templates task fails in a fresh process |

P1 means a high-priority correction to a documented execution boundary. P2 means an actionable correctness or supported-workflow defect. Recommendations below describe remediation scope; none has been implemented by this review.

## Resolution

Four findings, including the P1, are fixed on branch `fix/review-2026-11-10`. That branch is **not merged to `main` and not released**. No version is bumped, because the owner picks the release version; the fixes are listed under `[Unreleased]` in CHANGELOG.md. Each finding went to a work package with an Opus implementer and adversarial Haiku reviewers, over repeated fix rounds. CA-2026-11-02 and CA-2026-11-03 shared one package. Four packages were accepted and merged into the branch. The other three were not accepted after three fix rounds, and their branches are not merged. The packaged module was regenerated once, after the merges (`f2c4e04`).

| ID | Status | Fix | Commits |
| --- | --- | --- | --- |
| CA-2026-11-01 | Fixed, merge `4374f6f` | The literal target-array recognizer in `StrictGrammar` returns no array when the array's pipeline runs in the background or its command expression has a redirection. The argument then gets the existing literal-string-values finding, and default `Import-CompleterScript` refuses the script before it runs. Tests assert that a marker file stays byte-identical for the `2>`, `>`, `*>`, `>>`, colon-bound, and `-ParameterName` forms. The fix commit says that `@('x' &)` started a job at import. That did not reproduce on 7.7.0, where the array yields its string and starts no job, so `cd248b7` corrects the source comment. | `83a87d2`, `cd248b7` |
| CA-2026-11-02 | Open | The fix attempt on `r11/WP02` (`49111d0`), shared with CA-2026-11-03, was not accepted and is not merged. | — |
| CA-2026-11-03 | Open | Shares the `r11/WP02` attempt above. | — |
| CA-2026-11-04 | Fixed, merge `d02a7c3` | `Export-CompleterSet` decides in `begin`, from `MyInvocation.ExpectingInput` or a bound `-InputObject`, whether input was requested. When input was requested and no record arrives, it warns and writes nothing. `-InputObject` drops `[ValidateNotNull()]`, so a null is skipped. The command help and `about_Completer_Sets` say which calls export everything. | `9698e88`, `bfd4dc5`, `8d31ca5` |
| CA-2026-11-05 | Open | The fix attempt on `r11/WP05` (`9af3ea6`), a 1 MB size bound with `-SkipLimitCheck`, was not accepted and is not merged. | — |
| CA-2026-11-06 | Fixed, merge `2cac06f` | These generators now call `ConvertTo-CompleterSingleQuotedText`, which escapes U+0027, U+2018, U+2019, U+201A, and U+201B: the set exporter's `Path`, `CommandName`, and `ParameterName` lines, `New-CompleterLazyStub`, the benchmark's `ConvertTo-SingleQuoted`, and the build's `RequiredAssemblies` line. | `b389016`, `8bf7941`, `4e5d6f3`, `a94278e` |
| CA-2026-11-07 | Open | The fix attempt on `r11/WP07` (`8e77e78`) was not accepted and is not merged. On this branch the packaged commands still show their source comment help. | — |
| CA-2026-11-08 | Fixed, merge `e9869a8` | `Markdown_templates` depends on `compile` and runs `New-MarkdownCommandHelp` in a child `pwsh -NoProfile` that imports the source manifest. The build process therefore never loads or locks the core. README describes the task. | `f4c760e`, `bcd960c` |

Documented behaviour changes:

- A strict script whose literal target array carries any redirection or a trailing `&` is now refused even when the array writes nothing, as with `@('tool' 2>&1)` or `@('tool' 2> $null)`. This applies under `Register-Completer -Lazy` too. None of the 175 PS_Completers scripts uses such an array.
- `Export-CompleterSet` called after a pipe or with `-InputObject` no longer falls back to every managed registration. A forwarding wrapper called with no input now warns and writes nothing.
- `-InputObject @($null, $record)` now exports the record instead of failing parameter binding.

Integration checks were run on the branch head, on Windows with PowerShell 7.7.0 and Pester 6.1.0, each in a fresh profile-free process:

- `Invoke-Build -Task build`: 4 tasks, 0 errors, 0 warnings. The MAML under `src/docs` needed no change.
- Full suite, with the PowerShell directory first on `PATH`: 689 passed, 3 failed, 8 skipped (700). The three failures are the known CompleterScaffold WhatIf cases, which also fail on `bf653d8`.
- PSScriptAnalyzer: 0 findings in each of `src`, `tests`, and `tools`.
- The built package imports with 11 functions, loads the core from its own `lib/`, and keeps 11 functions on a repeated import.
- PS_Completers conformance gate (`357587c`) against the built package: 322 passed, 0 failed.
- Each fixed finding's reproduction was run against the built package, or for CA-2026-11-08 against an archive copy of the head. Each is fixed there, and each still reproduces on the `bf653d8` package.

How the gate was run matters. It re-imports CompleterActions by name with `-MinimumVersion`, which resolves through `PSModulePath` instead of reusing a copy imported by path. The run therefore put the package's parent folder first on `PSModulePath`. Without that, the installed 3.0.0 loads beside the package. With this branch's changed core, that load fails with `A different copy of assembly 'CompleterActions.Core' is already loaded`, and every `Completers.Tests.ps1` case fails. With an identical core, the gate silently tests the installed copy instead.

Not run here: PowerShell 7.4, 7.5, 7.6, preview, and Linux. CI on the pull request is the first run on those legs.

## Method and coverage

The working tree was clean at the start. GitHub's main branch was independently checked and matched the reviewed SHA. AI Memory context was assembled from workspace completeractions with document retrieval enabled: memories, graph, and documents all reported OK, with reranking applied. Retrieved historical reviews and roadmap decisions were context only; current source and new runtime evidence determined findings.

Six Astra Max agents were launched across runtime/types, strict import/grammar, sets/lazy loading, authoring, packaging/CI, and adversarial validation. Five completed their reviews. The first import reviewer ended with an automated content-risk error; the adversarial reviewer completed that scope and independently reproduced its candidate using only disposable local fixtures. The coordinating agent independently reproduced export, size-limit, quoting, template-task, and packaged-help findings and ran integrated validation.

| Area | Coverage |
| --- | --- |
| Runtime and C# core | Engine access, public record/enumeration types, target normalization, managed/runtime tables, reconciliation, conflict detection, registration transactions, query/removal/reset, and completion testing |
| Import | StrictGrammar and messages, public import/test commands, parse/conformance/target extraction, capture module, source-location binding, and trusted/default tier contracts |
| Sets and lazy loading | Public import/export/drift commands; definition, entry, hash, package and module resolution; lazy stubs, activation, sibling replacement and rollback paths |
| Authoring | Scaffold generation, help parsing, executable resolution, subprocess timeout/output handling, file writing, and startup measurement |
| Packaging and docs | Source/tracked manifests and loaders, bootstrap, format definitions, build/release scripts, CI workflows, VS Code tasks, command/about help, MAML and relevant test coverage |

All runtime mutations were confined to fresh profile-free child processes. Temporary fixture directories were removed. An isolated archive build preserved the tracked package in the working tree. No live user profile, PSReadLine configuration, gallery release, installed completer repository, or other service was changed.

## Findings

### CA-2026-11-01 — P1 — Strict eager import admits nested redirection

**Location:** [StrictGrammar.cs, lines 158–181](../src/Core/Grammar/StrictGrammar.cs#L158), particularly the unchecked command-expression node at lines 171–181. Compare the ordinary redirection check at [lines 289–298](../src/Core/Grammar/StrictGrammar.cs#L289).

The literal target-array recognizer unwraps an array-expression pipeline and accepts its string expression without checking the command expression's redirections. The main command validator delegates registration arguments to that recognizer, so this nested redirection escapes both checks.

A disposable completer script containing the following was accepted:

    Register-ArgumentCompleter -Native -CommandName @('review-redirect' 2> '<temporary marker file>') -ScriptBlock { 'ok' }

The marker was an existing, disposable 33-byte file. Independent runtime evidence:

    Test-CompleterScript findings: 0
    Marker bytes after validation: 33
    Imported records: 1
    Imported record Trusted: False
    Marker bytes after default Import-CompleterScript: 0
    Live runtime registration created during import: False

The redirection truncates the marker while the script executes inside the capture module, despite the explicit strict-tier promise that import cannot write a file in [about_Import_Completers, lines 54–58](../en-US/about_Import_Completers.help.txt#L54).

**Bounds:** Test-CompleterScript itself did not execute the script or change the marker. Ordinary top-level redirection is rejected. Ordinary strict lazy registration rejects this fixture during target extraction through SafeGetValue, before executing the script or modifying the marker. The demonstrated affected surface is eager default Import-CompleterScript; this is not evidence of a general sandbox escape.

**Remediation:** reject redirections and other unsupported pipeline attributes before accepting a literal target array. Add negative grammar/import tests that verify a disposable marker remains byte-identical.

### CA-2026-11-02 — P2 — Text equality cannot establish runtime ownership

**Location:** [Resolve-CompleterRegistrationState.ps1, lines 94–98](../src/Private/Resolve-CompleterRegistrationState.ps1#L94). Related text-only idempotence: [Resolve-CompleterRegistrationConflict.ps1, lines 122–128](../src/Private/Resolve-CompleterRegistrationConflict.ps1#L122).

Reconciliation considers a managed registration active when either its ScriptBlock reference matches the runtime block or its ScriptText compares equal. Different closures can have exactly the same text while executing with different captured values. The comparison is also case-insensitive, so even different string literals can be treated as identical.

Reproduce in a fresh process after importing the source manifest:

    function global:Test-ReviewClosure { param([string] $Name) }
    function New-ReviewClosure {
        param([string] $Value)
        { $Value }.GetNewClosure()
    }
    $old = New-ReviewClosure alpha
    $new = New-ReviewClosure beta
    Register-Completer -CommandName Test-ReviewClosure -ParameterName Name -ScriptBlock $old
    Register-ArgumentCompleter -CommandName Test-ReviewClosure -ParameterName Name -ScriptBlock $new
    $line = 'Test-ReviewClosure -Name '
    (TabExpansion2 $line $line.Length).CompletionMatches.CompletionText
    (Get-Completer -CommandName Test-ReviewClosure -ParameterName Name).State
    Unregister-Completer -CommandName Test-ReviewClosure -ParameterName Name -Confirm:$false

The runtime reviewer observed completion beta. Independent validation confirmed different captured behavior, Active state, and successful removal without AllowUnmanaged. The blocks had case-sensitively equal text and different references. A separate Value/value literal reproduction produced the same gate violation. An ordinary different-text replacement correctly produced Stale and Conflicted and refused removal, confirming the narrower defect.

**Impact:** externally replaced behavior is hidden from inspection and can be overwritten or removed without the protections documented for unmanaged replacements.

**Remediation:** preserve exact block identity for ownership and account for bound context in any idempotence policy. Merely changing the comparison to case-sensitive equality does not fix the closure example.

### CA-2026-11-03 — P2 — Typed targets collapse to an ambiguous key

**Location:** [Get-Completer.ps1, lines 171–175](../src/Public/Get-Completer.ps1#L171), [Resolve-CompleterRegistrationState.ps1, lines 69–83](../src/Private/Resolve-CompleterRegistrationState.ps1#L69), and [Unregister-Completer.ps1, lines 138–182](../src/Public/Unregister-Completer.ps1#L138). Output deduplication also drops kind at [Get-Completer.ps1, line 211](../src/Public/Get-Completer.ps1#L211).

A native command named Test-ReviewCollision:Name and parameter target Test-ReviewCollision / Name share the normalized textual key. Public inputs explicitly identify the kind, but downstream lookups pass only Key and search the native dictionary first.

These were simultaneously usable Windows runtime targets, verified using an executable-backed alias:

    function global:Test-ReviewCollision { param([string] $Name) }
    Set-Alias -Scope Global -Name 'Test-ReviewCollision:Name' -Value "$PSHOME/pwsh.exe"
    Register-ArgumentCompleter -Native -CommandName 'Test-ReviewCollision:Name' -ScriptBlock { 'native-result' }
    Register-ArgumentCompleter -CommandName Test-ReviewCollision -ParameterName Name -ScriptBlock { 'parameter-result' }
    Get-Completer -CommandName Test-ReviewCollision -ParameterName Name
    Unregister-Completer -CommandName Test-ReviewCollision -ParameterName Name -AllowUnmanaged -Confirm:$false

Actual completion returned native-result for the alias and parameter-result for the function. Nevertheless, the explicit parameter query returned a Native record. Independent removal testing showed the explicit parameter removal deleted the native entry while leaving the parameter entry. A second reproduction with only a managed parameter registration showed a native lookup/removal could return and delete that parameter registration.

**Remediation:** retain kind throughout internal identity, managed storage, snapshots, reconciliation, deduplication and removal. Fixing only the final dictionary write leaves earlier lookup ambiguity intact.

### CA-2026-11-04 — P2 — Empty export input selects unrelated registrations

**Location:** [Export-CompleterSet.ps1, lines 100–119](../src/Public/Export-CompleterSet.ps1#L100).

The inputBound flag is set only when process receives an InputObject. An incoming pipeline that yields no records never sets it, so end takes the no-input fallback and selects all managed script-backed registrations.

Verified using the existing import fixture and a disposable destination:

    Import-CompleterScript -LiteralPath ./tests/Fixtures/ImportableNativeCompleter.ps1 | Register-Completer
    Get-Completer -CommandName 'review-does-not-exist' -Native |
        Export-CompleterSet -Path '<temporary existing set.psd1>'

Independent output:

    SelectedCount: 0
    ExportedEntries: 1
    ExportedTargets: importfixture,importfixture.exe

**Impact:** an empty selection silently replaces an existing set with unrelated session registrations, which may subsequently be loaded by a profile.

**Remediation:** distinguish no pipeline/input request from an empty requested selection before entering the all-records fallback. Verify that an empty filtered export leaves an existing destination unchanged and reports no selected registrations.

### CA-2026-11-05 — P2 — The reader rejects larger sets produced by the exporter

**Location:** [Import-CompleterSetDefinition.ps1, line 40](../src/Private/Import-CompleterSetDefinition.ps1#L40).

Import-PowerShellDataFile is called with its default safe-evaluation complexity limit. The exporter has no matching limit and writes valid nested data that exceeds it.

Fresh runtime tests generated ordinary strict scripts with one native target each and exported their records through Export-CompleterSet:

    384 entries: export succeeded; import returned 384; Test-CompleterSet returned 0 findings.
    385 entries: export succeeded; both Import-CompleterSet and Test-CompleterSet failed.
    Direct data read with SkipLimitCheck: all 385 entries returned.

The coordinating agent independently reproduced the 385-entry failure using public export/import/test commands. The error begins:

    Cannot generate a PowerShell object for a ScriptBlock evaluating dynamic expressions.

The full error echoes the generated data, although it contains only literal set data. Failure occurs before entries are registered. The exact boundary depends on the data shape; 385 is the measured boundary for this fixture, not a universal entry-count limit.

**Remediation:** deliberately support larger data files while retaining data-only evaluation, or enforce and document an equivalent export restriction. Consider SkipLimitCheck with appropriate resource bounds; never replace the data reader with script execution. Add a large exported-set roundtrip regression.

### CA-2026-11-06 — P2 — Generated PowerShell literals mishandle typographic apostrophes

**Location:** [Export-CompleterSet.ps1, lines 250–270](../src/Public/Export-CompleterSet.ps1#L250) and [New-CompleterLazyStub.ps1, lines 31–33](../src/Private/New-CompleterLazyStub.ps1#L31). The optional benchmark repeats the issue at [Measure-CompleterStartup.ps1, line 149](../tools/Measure-CompleterStartup.ps1#L149).

These generators double only the ASCII apostrophe. PowerShell also recognizes typographic apostrophes as string delimiters. A valid directory named author’s scripts (U+2019) therefore exports this invalid data literal:

    Path = 'author’s scripts/normal.ps1'

Both the specialist and coordinating agent confirmed that the original script imports successfully and export reports success, but re-importing the set fails with “could not be parsed as a PowerShell Data File.”

A separate, correctly escaped script target containing U+2019 passed strict validation with zero findings. Register-Completer -Lazy then failed in NewScriptBlock with “The string is missing the terminator,” because the lazy stub regenerated the key without adequate escaping.

The benchmark has the same lower-priority defect: a temporary completer folder containing U+2019 caused “The child measurement process failed,” while an ASCII-folder control completed Eager, Lazy and LazyNoHash. An independent parser check of the actual benchmark helper reproduced the unterminated string.

**Remediation:** consistently escape every delimiter recognized by PowerShell, using the policy already implemented in [ConvertTo-CompleterSingleQuotedText.ps1](../src/Private/ConvertTo-CompleterSingleQuotedText.ps1). Test legal non-ASCII paths and target names across set roundtripping and lazy loading.

### CA-2026-11-07 — P2 — Packaged external-help directives are unrecognized

**Location:** [CompleterActions.build.ps1, lines 139–148](../CompleterActions.build.ps1#L139).

The builder inserts the external-help comment between the function declaration and its opening brace. PowerShell does not associate help placed there with the function. The preceding source comment help remains active instead of the generated MAML.

Fresh packaged-module inspection:

    Import-Module ./build/CompleterActions/CompleterActions.psd1
    Get-Command -Module CompleterActions | ForEach-Object {
        $_.ScriptBlock.Ast.GetHelpContent().MamlHelpFile
    }

All eleven exported commands had null MamlHelpFile; the coordinating agent independently obtained CommandCount=11 and RecognizedExternalHelp=0. Get-Help Reset-Completer -Full returned the source description and omitted the expanded decision-order and deleted-Pending-script explanation present in the shipped XML at [lines 2366–2386](../build/CompleterActions/en-US/CompleterActions-help.xml#L2366).

**Impact:** updates to the maintained markdown/generated help can be absent from users' installed Get-Help output. Existing tests check wording shared with source comments, so they do not establish that MAML was selected.

**Remediation:** put the directive in recognized help and resolve precedence with the existing source comment. Verify packaged Get-Help using wording unique to MAML.

### CA-2026-11-08 — P2 — Help-template generation bypasses the required assembly

**Location:** [CompleterActions.build.ps1, lines 237–239](../CompleterActions.build.ps1#L237).

Markdown_templates imports the root psm1 directly. Since the compiled-core migration, the manifest's RequiredAssemblies entry loads the core DLL. Direct psm1 import bypasses that prerequisite, even if the DLL already exists.

The coordinating agent ran the actual task in a fresh process after compiling:

    CoreDllExists=True
    Invoke-Build -Task Markdown_templates
    ERROR: Unable to find type [CompleterActions.Internal.EngineAccess].
    CompleterActions.build.ps1:239
    Build FAILED. 1 tasks, 1 errors, 0 warnings

The task failed before generating templates. The specialist independently reproduced the failing direct import and successful manifest import, which exported all eleven functions. The failing task is advertised in README and wired into VS Code.

**Remediation:** import the source manifest and satisfy its compile prerequisite. Exercise the documented task in a fresh process, directing any generated output to a disposable location.

## Validation results and limits

Runtime: Windows, PowerShell 7.6.9, .NET SDK 10.0.403. Validation used the concrete installed PowerShell executable with NoProfile and NonInteractive. The command-runner wrapper itself initially used Windows PowerShell 5.1; its failed attempt was not accepted as module validation. Sandbox-denied PowerShell launches were retried through approved execution.

| Check | Observed result |
| --- | --- |
| Core compile, InvokeBuild 5.14.23 | Passed; zero compiler warnings/errors |
| Isolated git-archive build, exact reviewed commit | Passed; four tasks, zero errors/warnings; temporary tree removed |
| PSScriptAnalyzer 1.25.0, configured rules, src/tests/tools separately | Zero findings in each tree |
| Full suite, Pester 6.1.0, fresh process, inherited PATH | 629 passed, 15 failed, 8 skipped; 499.48 seconds |
| Help-probe file rerun, actual PowerShell directory first on PATH | 49 passed, 0 failed, 3 skipped |
| Scaffold file rerun, same PATH adjustment | 104 passed, 3 failed, 1 skipped |
| Affected package/PSReadLine test rerun, same PATH adjustment | 1 passed, 0 failed; other 66 tests in the file deliberately not run |

The original failures were six help-probe cases, eight scaffold cases, and one package test. The production resolver deliberately refuses app-execution aliases whose PE header cannot be read. The tests generally assume that finding an application named pwsh means it can be probed. Putting the actual executable directory first on PATH resolved twelve of the failures.

The remaining scaffold failures are the WhatIf assertion at line 1013 and two parameterized cases at line 1050. Independent diagnosis showed that the same packaged PowerShell executable, when started as a nested child, prepends its WindowsApps execution-alias directory again. Its resolver then returns CanRun=False and ShouldProcess correctly says “without running a program,” while the parent test expects the probing action. The observed child still reported COUNT=0, EXISTS=False, and exit 0. This is an identified host/test-assumption mismatch, not a demonstrated unwanted execution or file-write defect. No test files were changed to obtain a green result.

**No fully green single-run suite is claimed.** The table reports the actual full run and focused reruns; it does not combine them into a fictitious passing run. The local checks do not certify PowerShell 7.4/7.5/preview, Linux/macOS, hosted CI, gallery installation/publication, long-running profile behavior, or a live terminal session. Fresh source-manifest probes established the runtime findings; packaged-help probes established the help defect. The isolated build passed, but every finding was not repeated against that disposable rebuilt package.

## Rejected hypotheses and lower-priority observations

- Normal different-text replacement correctly reports Stale/Conflicted and enforces AllowUnmanaged. The identity finding concerns equal-text/different-context and case-only replacements.
- Strict lazy registration rejects the nested-redirection fixture; deferred/trusted execution is not itself a new strict-import defect.
- A positive strict lazy lifecycle completed Pending → Active → Reset Pending → Active with expected completions.
- Empty input to New-CompleterScript selected its HelpText path and ran no probe. Generated completion worked with script/cmd wrappers, the call operator, and a cursor before later arguments.
- No current defect was established in the compiled record types or the engine reflection seam. Exports and bootstrap were present; the intentionally untracked DLL was included by the successful build.
- A NUL-containing set path throws before per-entry problem collection, bypassing SkipInvalid. Ordinary malformed Windows path strings did not reproduce it; this rare-input diagnostic issue was not promoted into the eight findings.
- A synthetic managed-write failure during lazy activation can leave a real runtime block alongside a Failed record. No ordinary supported trigger was established; this remains a rollback robustness/test gap rather than a confirmed normal-operation finding.
- Hash fast-path trust and Test-CompleterSet's omission of grammar checking are documented contracts, not new defects.
- Secondary documentation cleanup: completion testing can activate pending lazy registrations despite its “does not change” wording; README's architecture list omits three commands; older benchmark figures need clear dating. No new performance-regression claim is made.

## Recommended follow-up

Fix and regression-test CA-2026-11-01 first. Address runtime identity and kind together so reconciliation, conflict checks and removal share one unambiguous contract. Cover set selection, larger roundtrips and all PowerShell quote delimiters before relying on exported sets as portable artifacts. Repair both help-generation paths and test the actual documented task and packaged help source. Re-run the supported CI matrix after implementation; this report-only change does not remediate any finding.
