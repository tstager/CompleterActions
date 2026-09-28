# Milestone 1 plan: faster imports and recovery (2.1.0)

Drafted: 2026-09-28
Base: main at `7bcdc01` (2.0.0 stable, release commit `b2de0be`, tag v2.0.0)
Spec: `docs/roadmap-3.0/milestone-1-spec.md` (final, accepted 2026-09-28). Section numbers below (§n) point into it.
Roadmap: `docs/roadmap-3.0.md`, milestone 1, locked decisions 1 and 2. Ships as `v2.1.0` stable. It is additive, so no rc is needed; the rc-first rule (decision 6) covers 3.0.0 only.
Branch: `feat/milestone-1-faster-imports` from main.

The spec says what the module does. This plan says how the work is split, in what order, which files each package touches, and how each package is accepted. Where the spec leaves an internal choice open, the plan picks one and says so under "Internal design choices".

## Current-state facts the plan builds on

Every fact below was read from the file named on 2026-09-28.

- **Exports.** Public functions are exported by file name. `CompleterActions.psm1` exports every `src/Public/*.ps1` base name. The build sets `FunctionsToExport = $public.BaseName` (`CompleterActions.build.ps1`). Only the source manifest lists names by hand (11 today). `tests/CompleterRegistration.Tests.ps1` "exports the same public functions defined in the manifest and src\Public" holds the manifest to `src/Public`. `tests/CompleterDeprecation.Tests.ps1` line 28 asserts exactly `11` functions. A new command therefore needs its `.ps1` file, a manifest line, and that count bumped. It needs no psm1 or build-script change.
- **Help.** The build's `external_help` task turns `src/docs/CompleterActions/*.md` (PlatyPS 1.0 schema, `Microsoft.PowerShell.PlatyPS` 1.0.3) into `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`. It then copies that file to `build/CompleterActions/en-US/CompleterActions-help.xml`. Both files are tracked. The packaged psm1 replaces comment-based help with `.EXTERNALHELP`, so the comment help in `src/Public/*.ps1` and the markdown must both be kept up to date. The `Markdown_templates` task runs `New-MarkdownCommandHelp ... -Force` over the whole module and would overwrite every hand-edited markdown file.
- **Tracked build.** `tests/CompleterRegistration.Tests.ps1` "keeps the tracked build output in sync with the module sources" rebuilds into `TestDrive` and compares the result line by line with `build/CompleterActions`. Every commit that changes `src`, the manifest, `en-US`, or the format file must therefore rebuild and commit `build/`.
- **Format and types.** `CompleterActions.Format.ps1xml` already has views for `CompleterActions.CompleterRegistration` (table) and `CompleterActions.CompleterScriptFinding` (list). The manifest has no `TypesToProcess`. Neither new command needs a new view or type.
- **Set import.** `Import-CompleterSet` → `Import-CompleterSetDefinition` (data only) → one `Get-CompleterRegistrationSnapshot` per set → `Resolve-CompleterSetEntry` per entry → one `Add-CompleterRegistration` call for the confirmed entries. `Resolve-CompleterSetEntry` does everything for one entry: static checks, `Get-CompleterScriptTarget`, record and stub construction, one `Resolve-CompleterRegistrationConflict` call (which makes one `Resolve-CompleterRegistrationState` call), duplicate check, and claiming. Its `Problems` are plain strings.
- **Write path.** `Add-CompleterRegistration` loops per registration: `Add-RuntimeCompleterRegistration` (calls `Get-CompleterRuntime`, a reflection lookup, on every call), then `Add-ManagedCompleterRegistration` (calls `Get-ManagedCompleterRegistrationTable` on every call). On failure it rolls back in reverse through `Add-/Remove-RuntimeCompleterRegistration` and `Add-/Remove-ManagedCompleterRegistration`. `Register-Completer` calls it once per target.
- **Test shims.** Seven tests in `tests/CompleterActions.Tests.ps1` and `tests/CompleterSet.Tests.ps1` replace private helpers by name with non-advanced functions, nine shims in all: `Add-ManagedCompleterRegistration` (5×), `Add-RuntimeCompleterRegistration`, `Remove-RuntimeCompleterRegistration`, `Get-CompleterRegistrationSnapshot`, `Resolve-CompleterRegistrationState`. A non-advanced function with `param($Registration)` accepts an unknown `-Table $x` into `$args` without error (verified on pwsh 7.6.6). New optional parameters on these helpers are therefore safe, but the call sites must keep calling the helpers by name.
- **Target derivation.** `Get-CompleterScriptTarget` calls `Get-CompleterScriptParseResult` (`[Parser]::ParseFile`) and returns targets in script order, one per `Key`. A repeated key keeps its first position and takes the last value.
- **Snapshot.** `Get-CompleterRegistrationSnapshot` calls `Get-CompleterRuntime` and `Get-ManagedCompleterRegistrationTable` once each, but keeps only the two dictionaries, not the runtime object. If a dictionary is `$null`, `Add-RuntimeCompleterRegistration` creates it and sets it through reflection.
- **Engine floor.** The manifest says `PowerShellVersion = '7.0'` (.NET Core 3.1). CI tests 7.4, 7.5, 7.6, and preview on Windows and Ubuntu. .NET 5+ APIs such as `[Convert]::ToHexString` and `[SHA256]::HashData` would break the stated floor, and no CI leg would catch it.
- **Line endings.** The repo has no `.gitattributes`, and the owner's machine has `core.autocrlf=true`. Tracked text is `i/lf w/crlf` on Windows and LF on the Ubuntu CI legs.
- **Remote and release.** The remote is `origin-main`. `release.yml` runs on a `v*` tag: `release_check`, Pester, build, `Publish_build`, then the GitHub release. It passes `--prerelease` only when the tag has a hyphen.
- **Benchmark.** `tools/Measure-CompleterStartup.ps1` has `-CompleterRoot`, `-Iterations` (default 5), and `-ModulePath`. It runs two legs, Eager and Lazy. The Lazy leg imports a set that the module under test exported into `%TEMP%` from `Import-CompleterScript` records.
- **PS_Completers.** `tools/Export-CompleterSetFile.ps1` pipes `Register-CompleterRegistration -LiteralPath ... -Lazy -Force -PassThru` records into `Export-CompleterSet`, with `#Requires` CompleterActions 2.0.0. `tests/Completers.Tests.ps1` has the drift `Describe` that §6 replaces. `ps_completers.psd1` has 173 entries.

## Internal design choices

These are the plan's picks where §4 and §2 say "the internals may change freely".

1. **One hash helper.** New private `Get-CompleterScriptHash` has two parameter sets:
   - `-Text <string>` hashes text that is already decoded;
   - `-LiteralPath <string>` reads the file with `[System.IO.File]::ReadAllText` and then hashes it.

   It normalises CR LF, then a lone CR, to LF. It encodes the text as UTF-8 without a BOM and hashes it with `[System.Security.Cryptography.SHA256]::Create()` (disposed). It returns `'SHA256:' + ([BitConverter]::ToString($bytes) -replace '-', '')`. These APIs exist on .NET Core 3.1.

   A second small private helper, `Test-CompleterSetHashFormat -Value <object>`, returns `$true` only for a `[string]` that matches `(?i)^SHA256:[0-9A-F]{64}$`.

   `ReadAllText` resolves a relative path against the process directory, not the PowerShell location, so every caller passes a full path.
2. **Single read at export.** `Get-CompleterScriptTarget` gains an optional `-ParseResult` parameter. The export calls `Get-CompleterScriptParseResult` once, passes the result in, and hashes `$parseResult.Ast.Extent.Text`. `-LiteralPath` stays mandatory because every error message names the path.
3. **Entry resolution split in two phases.**
   - **Static phase.** `Resolve-CompleterSetEntry` becomes session-independent. It keeps the checks from the entry itself, the path checks, target resolution (parse or, from WP3, hash), and the mismatch check. Its `-Snapshot` and `-ClaimedTargets` parameters move out.
   - **Session phase.** A new private `Resolve-CompleterSetRegistration` takes every static entry of one set, the snapshot, and `-Force`. It builds the Pending records and stubs, resolves conflicts, runs the duplicate check, and claims targets, all in set order.
   - **Typed problems.** `Problems` becomes a list of `@{ Kind; Message }`. `Kind` is one of `InvalidEntry`, `MissingScript`, `UnreadableTargets`, `TargetMismatch`, `Conflict`, or `DuplicateTarget`. The static phase produces the first four kinds, and the session phase produces `Conflict` and `DuplicateTarget`. `Import-CompleterSet` prints only `.Message`, so every problem text and its order stay exactly as in 2.0.0.
   - **Single parse.** From WP3 on, the static phase's parse step calls `Get-CompleterScriptParseResult` once and passes the result to `Get-CompleterScriptTarget -ParseResult` (choice 2), inside the same `try` that wraps the 2.0.0 call. `ParseFile` throws the same exception whether it is called directly or from `Get-CompleterScriptTarget`, and the parse-error and no-target messages come from `Get-CompleterScriptTarget` either way. The 2.0.0 path therefore stays one parse per strict entry with the same problem texts.
   - **Verify mode.** WP3 also gives the static phase a `-Verify` switch, which only `Test-CompleterSet` passes. It disables the fast path, so a strict entry is always parsed once. It adds two properties to the entry: `ActualHash`, hashed from that parse's `Ast.Extent.Text` for a strict entry and with `Get-CompleterScriptHash -LiteralPath` for a trusted one (trusted entries are still never parsed), or `$null` when the file is missing or cannot be read; and `DerivedTargets`, the parse-derived targets, empty for a trusted entry or a failed parse.
   - **What `Test-CompleterSet` reuses.** It reuses the static phase in verify mode, and so the first four kinds and their texts. It does not run the session phase, because that phase reads the session. It therefore implements §6's claiming rule itself in `Get-CompleterSetFinding`: entries in set order, an entry with no `Error` finding claims its resolved targets, and a later entry that resolves a claimed target gets `DuplicateTarget` with import's text. The 2.0.0 claim loop (`src/Private/Resolve-CompleterSetEntry.ps1`, the `$ClaimedTargets` checks after the conflict call) moves into the session phase, so the two implementations share the rule and the message, not the code.
4. **Fast path only for a clean static phase.** The hash is compared only when the entry has no problem so far: a strict entry that declares `Targets`, whose file exists and is a `.ps1`, and whose `Trusted` and targets are valid. An invalid entry therefore always gets 2.0.0's problem list. This guard is not in §3's table, but it follows from §1: nothing that 2.0.0 reports may change.
5. **One state pass, per-entry conflict decisions.** `Resolve-CompleterRegistrationConflict` gains an optional `-RegistrationState`, the rows already resolved and aligned to `-Registration`. When that is supplied it skips its own `Resolve-CompleterRegistrationState` call. The session phase calls `Resolve-CompleterRegistrationState` once with every key of the set, in set order. It then calls the conflict function once per entry with that entry's slice. A single call over the whole set would change the problem text for a target that two entries share (the second entry would see the first as a "managed registration already exists"). Slicing keeps 2.0.0's per-entry planning exactly.

   **Empty-key guard.** `Resolve-CompleterRegistrationState` declares `-Key` as `[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]]`, so `-Key @()` throws a parameter-validation error. The key list is the keys of every entry's `Registrations`, in set order, and it is empty when no entry resolved any target, for example when every entry fails its static checks. The session phase then skips the state call and every conflict call. That is what 2.0.0 does implicitly: `Resolve-CompleterRegistrationConflict` returns early when `$Registration.Count -eq 0`, before it calls the state function. The import then reaches the 2.0.0 `Completer set '<path>' has <n> invalid entries and nothing was registered.` error, or the `-SkipInvalid` warnings, unchanged.
6. **Batch writes through the same helpers.**
   - The snapshot gains a `RuntimeContext` property, the `Get-CompleterRuntime` object it already builds.
   - `Add-CompleterRegistration` always writes in two passes. The runtime pass writes every registration that is not `IsExisting` through `Add-RuntimeCompleterRegistration`. The managed pass then writes every such record through `Add-ManagedCompleterRegistration`. Both helpers are still called by name for each record, so the test shims keep working.
   - `Add-CompleterRegistration` gains an optional `-Snapshot`. It only supplies what the helpers would otherwise look up: `-Runtime $Snapshot.RuntimeContext` and `-Table $Snapshot.Managed`. It does not change the write order.
   - With one registration, which is how `Register-Completer` (`src/Public/Register-Completer.ps1`, one `Add-CompleterRegistration -Registration $registration` per target) and `Reset-Completer` call it, two passes are exactly 2.0.0's runtime-then-managed order for that one target, and the rollback is the same. There is no second code path for single-target callers.
   - When `Add-RuntimeCompleterRegistration -Runtime` creates a missing dictionary, it writes the new dictionary back onto the runtime object, so the next write in the batch reuses it.

   **Rollback contract.** The 2.0.0 loop cannot be kept as written. It tracks one `$writeIndex`, rolls back `for ($index = $writeIndex; $index -ge 0; $index--)`, and names `$Registration[$writeIndex]` (`src/Private/Add-CompleterRegistration.ps1`). In a two-pass write, a managed failure at record k has already written the runtime value of every record, so that loop would restore runtime values only for 0..k and leave k+1..n-1 behind. The batch therefore tracks the passes separately:

   - `$runtimeIndex` is the last index whose runtime write was started, and `$managedIndex` the last index whose managed write was started. Both start at -1, and each is set before its helper is called, as 2.0.0 sets `$writeIndex`, so the record whose write threw is included in the rollback.
   - `$failedIndex` is the index whose write threw: `$managedIndex` if the managed pass had started, otherwise `$runtimeIndex`. It is used only to name the target in the message.
   - The rollback is the 2.0.0 loop unchanged, except that it starts at `$runtimeIndex` instead of `$writeIndex`: for each index from `$runtimeIndex` down to 0, skipping `IsExisting` records, one `try` restores the runtime value from the conflict row (or removes the new one) and then the managed record (or removes the new one), through the same per-target `Add-*` and `Remove-*` helpers. A failed step is collected and the loop goes on to the next index.
   - A runtime-pass failure at record k therefore rolls back records k..0. A managed-pass failure at record k rolls back every record, n-1..0, because every runtime value has been written. That removes the runtime values of k+1..n-1 that the 2.0.0 loop would have left behind.
   - For a record whose managed write has not happened, the managed step puts back a record that was never replaced, or removes a key that was never added, which changes nothing. 2.0.0 already does this for the record whose runtime write threw. Keys are independent, so the end state does not depend on the order in which the records are undone.
   - With one registration the loop, the helper calls, and their order are exactly 2.0.0's, so the existing `tests/CompleterActions.Tests.ps1` rollback tests and their shims see no difference.
   - The message is 2.0.0's: `Failed to register the completer '<RuntimeKey of $Registration[$failedIndex]>'. <reason>`, with ` Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: <errors>` appended when a rollback step threw. `Import-CompleterSet` wraps it as `Failed to import completer set. ...`, unchanged.

   WP4 pins this contract with the batch rollback tests listed there.
7. **Reset reuses the write transaction.** For each target, `Reset-Completer` builds the Pending record: `New-CompleterRegistrationRecord` with a fresh `New-CompleterLazyStub`, `State Pending`, and the old `ScriptPath` and `Trusted`. It also builds a conflict row: `IsExisting = $false`, the current managed record, and the current runtime record (or `$null` for Failed). It hands both to `Add-CompleterRegistration`, which gives the §5 restore-on-failure for free. The error text is then `Failed to reset the completer '<RuntimeKey>'. Failed to register the completer '<RuntimeKey>'. <reason>`. That wording is listed under open items.
8. **Set-file positions.** New private `Get-CompleterSetEntryExtent` parses the set file with `[Parser]::ParseFile` and finds the `Entries` key and its array. For each element it returns the `@{` extent and the `Path`, `Hash`, and `Targets` key or value extents.
   - It skips `$null` elements exactly as `Import-CompleterSetDefinition` does, so entry numbers line up.
   - It handles both `@( @{..} @{..} )` (statements) and `@( @{..}, @{..} )` (a comma array).

## Work packages

Each package is its own commit or small group of commits on `feat/milestone-1-faster-imports`. After every package, run these three steps in this order, each in its own process:

1. `pwsh -NoProfile -Command "Invoke-Build -Task build"`. The build comes first because "keeps the tracked build output in sync with the module sources" (`tests/CompleterRegistration.Tests.ps1`) rebuilds into `TestDrive` and compares the result with the committed `build/CompleterActions`. Running Pester before the build would fail that test on the first run after any `src` change. The release recipe uses the same order.
2. `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"`, in a new process.
3. PSScriptAnalyzer over `./src` and `./tests` with `./PSScriptAnalyzerSettings.psd1`, in a new process. This is the CI Lint scope (`.github/workflows/ci.yml` lints only `./src` and `./tests`) and it is the pass criterion. Linting `./tools` as well is a local extra for WP7, not a CI gate.

Commit `build/` and the regenerated help XML together with the source change they come from. Never run Pester in the same process as Invoke-Build or PSScriptAnalyzer. Both register completers, and that breaks the paging tests. Keep CRLF in every edited file. Commits carry only the `Co-Authored-By` trailer.

### WP1 Set schema and hash in Export-CompleterSet

Files:
- new `src/Private/Get-CompleterScriptHash.ps1`;
- new `src/Private/Test-CompleterSetHashFormat.ps1`;
- `src/Private/Get-CompleterScriptTarget.ps1` (optional `-ParseResult`);
- `src/Public/Export-CompleterSet.ps1` (comment help too);
- `src/docs/CompleterActions/Export-CompleterSet.md`;
- new fixtures under `tests/Fixtures/CompleterSet/`:
  - `HashFixture.ps1`: a strict native completer with one non-ASCII character in a comment, saved as UTF-8 without a BOM;
  - `NoHash/completers.psd1`: a set exactly as 2.0.0's export writes it, `Version = 1`, two strict entries with relative forward-slash paths and no `Hash`. It is produced once, when the fixture is created, by running `Export-CompleterSet` from the 2.0.0 package (the `git archive v2.0.0 build` extraction described in WP9, imported by full path) over the two fixture scripts' `Register-Completer -Lazy -PassThru` records, and checked in as written. It is therefore the 2.0.0 export text byte for byte, apart from line endings;
  - `NoHash/alpha_completer/alpha_completer.ps1`: native `setfixturealpha`, `setfixturealpha.exe`;
  - `NoHash/beta_completer/beta_completer.ps1`: `Test-SetFixtureBeta -Name`;
- `tests/CompleterSet.Tests.ps1`.

Change:
- **Strict entries.** The export parses each strict script once, derives its targets from that parse, and hashes the parse's text (choice 2). It keeps the strict-subset refusal against the derived keys, then writes the derived targets. So `Targets` come in script order and with script casing.
- **Trusted entries.** They keep record order. They are hashed with `Get-CompleterScriptHash -LiteralPath`. If that read fails, the entry is written without `Hash` and the export writes the §2 warning once per such entry, then succeeds.
- **Layout.** `Hash    = 'SHA256:<64 hex>'` is written between `Trusted` and `Targets` with the existing padding. Nothing else in the output changes.

The two NoHash fixture scripts must pass `Test-CompleterScript` and carry no `Hash`. They are the "a set without Hash imports exactly as today" fixture for WP3 and the `MissingHash` fixture for WP6. Tests copy the fixture folder into `TestDrive` before they mutate it.

Tests (`tests/CompleterSet.Tests.ps1`, Context `Export-CompleterSet`):
- `writes a Hash between Trusted and Targets for every strict and trusted entry`: every added line matches `^\s{12}Hash    = 'SHA256:[0-9A-F]{64}'$`, and the line before it is the entry's `Trusted` line and the line after it its `Targets` line.
- `writes the 2.0.0 export text once the Hash lines are removed`: the NoHash fixture folder is copied into `TestDrive`, its two scripts are exported by the branch build, every `^\s*Hash\s*=` line is removed from the output, and the rest is compared line by line with the checked-in `NoHash/completers.psd1` (line endings ignored). This pins "Nothing else in the output changes" in CI, and it is the automated side of the 2.0.0-compatibility claim: the only key the branch adds is one that 2.0.0's `Resolve-CompleterSetEntry` ignores.
- `hashes LF, CRLF, UTF-8 BOM plus CRLF, and lone-CR copies of one script to the same value`: the four copies are written at test time with `[System.IO.File]::WriteAllBytes`, never checked in, because autocrlf would rewrite them.
- `hashes the checked-in hash fixture to its recorded literal`: the literal is computed once with the helper and cross-checked independently with `git cat-file blob :tests/Fixtures/CompleterSet/HashFixture.ps1 | sha256sum`. The index blob is LF with no BOM, which is exactly the normalised form. The test runs on the Windows (CRLF checkout) and Ubuntu (LF) legs alike.
- `writes a strict entry's targets in script order and script casing when the records arrive in another order`
- `writes a trusted entry whose script is missing without Hash, warns once, and still succeeds`
- `reads each strict script once for both its targets and its hash`: a pass-through shim counts `Get-CompleterScriptParseResult`, one per strict entry.

The existing export tests compare targets after sorting and pass unchanged.

Acceptance:
- The new tests and the existing suite pass.
- A set exported by the branch build imports under the 2.0.0 build with no warning. This is a manual spot check. The 2.0.0 side is the `git archive v2.0.0 build` package in the scratch folder, imported by full path to its `.psd1`, and the check asserts `(Get-Module CompleterActions).ModuleBase` before importing. Both builds report version 2.0.0 until the release commit, so the path is the only way to tell them apart. §8 check 9 repeats it on the real set in WP9.

### WP2 Split entry resolution (no behaviour change)

Can run in parallel with WP1: the files do not overlap.

Files:
- `src/Private/Resolve-CompleterSetEntry.ps1` (static phase, typed problems);
- new `src/Private/Resolve-CompleterSetRegistration.ps1` (session phase);
- `src/Public/Import-CompleterSet.ps1` (calls the static phase per entry, then the session phase once per set, and formats `.Message`).

Change: choice 3, apart from the single-parse shape and verify mode, which WP3 adds because they need the WP1 helpers. In this package the session phase still calls `Resolve-CompleterRegistrationConflict` once per entry, exactly as today, so the state-pass count stays 3 for 3 entries and the existing test keeps asserting it. The per-entry record keeps `Index`, `DeclaredPath`, `Path`, `Trusted`, `Targets`, `Registrations`, `Conflicts`, `Problems`, and `IsValid`. It adds `DeclaredHash` and `TargetSource`, which is `Trusted` or `Parsed` for now.

Tests: no new tests. All 33 set tests pass unchanged, including "reports every invalid entry in one error and registers nothing", "reports a strict entry whose declared Targets do not match the script", and "reports a target listed by two entries before registering anything". These pin the problem text and order.

Acceptance: the full suite passes with no test edits, and `git diff` shows no change to any user-visible string.

### WP3 Import-CompleterSet fast path and its decision table

Depends on WP1 (hash helper) and WP2 (static phase).

Files:
- `src/Private/Resolve-CompleterSetEntry.ps1` (decision table, single-parse shape, `-Verify`);
- `src/Public/Import-CompleterSet.ps1` (verbose lines, comment help);
- `src/docs/CompleterActions/Import-CompleterSet.md`;
- `tests/CompleterSet.Tests.ps1`.

No fixture file is checked in for this package. The probe script and the unregistered-target script are written into `TestDrive` at test time (see the tests below), because the probe script must name a probe path inside `TestDrive`.

Change: the static phase takes the single-parse shape and gains `-Verify`, both as choice 3 describes. Without `-Verify` it applies §3's decision table in this order, and the first row that applies decides.

| Order | Condition | Outcome | `TargetSource` | Verbose |
| --- | --- | --- | --- | --- |
| 1 | Entry has a problem so far, or its file is missing or not a `.ps1` | As 2.0.0; nothing is hashed | (as 2.0.0) | none (the problem is reported) |
| 2 | `Trusted` | Declared targets; no read, no hash | `Trusted` | `trusted; targets read from the set.` |
| 3 | Strict, no `Targets` | Parse and derive | `Parsed` | `no Targets; parsed the script.` |
| 4 | Strict, `Targets`, `Hash` absent | Parse, derive, compare | `Parsed` | `no hash; parsed the script.` |
| 5 | Strict, `Targets`, `Hash` fails `Test-CompleterSetHashFormat` | Parse, derive, compare; no problem | `Parsed` | `hash not recognised; parsed the script.` |
| 6 | Strict, `Targets`, reading the file for the hash throws | Parse, derive, compare (2.0.0's problem wins) | `Parsed` | `hash differs; parsed the script.` |
| 7 | Strict, `Targets`, hash differs | Parse, derive, compare | `Parsed` | `hash differs; parsed the script.` |
| 8 | Strict, `Targets`, hash matches | **Fast path**: declared targets, in declared order, de-duplicated by `Key`, with the first occurrence and its casing kept; no parse | `Hash` | `hash matches; targets read from the set.` |

- **Verbose format.** Each line is written as `Entry <n> ('<declared path>'): <text>`. After the entries, one summary line per set: `Completer set '<path>': <h> entries from the hash, <p> parsed, <t> trusted.`
- **Wording.** The spec fixes only rows 4, 7, and 8 and the summary. The wording for rows 2, 3, 5, and 6 is this plan's pick (open item 1).
- **Unchanged.** Stale hashes are not warnings, and nothing is written to the set.
- **Repeated keys.** A hand-edited entry that lists one key twice keeps the first occurrence's casing on the fast path (row 8), and the last occurrence's casing on the parse path, because `Get-CompleterScriptTarget` fills an ordered dictionary with `$targetsByKey[[string] $target.Key] = $target`, which keeps the first position and takes the last value. That is a documented divergence (§3, "Records on the fast path"), not a defect, and it cannot arise for a set that `Export-CompleterSet` wrote, because the export keys each entry's targets by `Key`. The comment help, `Import-CompleterSet.md`, and the WP8 `about_Completer_Sets` paragraph each say so in one sentence.
- **Docs that go stale.** Three passages say an import parses every strict script, which is false once the fast path exists. Each becomes "parses each strict script once, unless its `Hash` matches":
  - `src/Public/Import-CompleterSet.ps1` comment help, "Validating a strict entry parses its script once ... so a set import parses each strict script once and walks none of them";
  - the same sentence in `src/docs/CompleterActions/Import-CompleterSet.md`.
  - WP8 makes the same edit in `about_Completer_Sets` and the README.
- **Retry wording.** The comment help and `Import-CompleterSet.md` each say twice that `-Force` retries `Failed` records: in the description ("`-Force` replaces existing registrations for the set's targets and retries `Failed` ones") and under `-Force` ("including `Failed` lazy records whose load should be retried"). Both stay true and each gains "; `Reset-Completer` retries them without re-importing the set". This package lands the sentence. If WP5 has not merged yet, the new sentence references a command that does not exist yet, which is acceptable on the branch, because nothing ships until WP10.

Tests (`tests/CompleterSet.Tests.ps1`, new Context `Import-CompleterSet fast path`). Each hashed set is written by `Export-CompleterSet` into `TestDrive`, so declared order is script order.

Counting. Wherever a parse count is asserted, both `Get-CompleterScriptTarget` and `Get-CompleterScriptParseResult` are replaced in module scope with pass-through shims. Each shim records the call and then invokes the original, captured before replacement, with the same arguments, so the records stay real and "records identical" comparisons stay meaningful. Both counts are asserted: 0 each on the fast path, and exactly 1 each for a parsed entry. A parse through any other route (`-ParseResult` built upstream, or a direct `ParseFile` call) is caught by the `Get-CompleterScriptParseResult` count. Every counting test also asserts the entry's verbose line (`hash matches` or `hash differs`), so that a silent fall-through, for example `ReadAllText` resolving a relative path against the process directory (risk 6) and throwing into row 6, cannot pass as a fast-path run.
- `imports the checked-in set without Hash with the records 2.0.0 produced`: expected `Key`, `RuntimeKey`, `State`, `ScriptPath`, and `Trusted` are written as literals. `Get-CompleterScriptTarget` and `Get-CompleterScriptParseResult` are each invoked once per entry. The import writes no warning and no error (`-WarningVariable` and `-ErrorVariable` both empty, and `$?` is `$true`), and the verbose line of each entry is `no hash; parsed the script.`
- `skips the parse for every strict entry whose Hash matches` (0 invocations of each; every entry's verbose line is `hash matches`)
- `parses only the strict entry whose script changed since export` (exactly 1 of each; that entry's verbose line is `hash differs`)
- `parses every strict entry of the same set once its Hash lines are removed`
- `returns the same records from the hashed, edited, and unhashed runs`
- `follows declared order and first casing for a hand-edited entry whose Hash still matches` (targets reversed, one repeated, one recased)
- `treats a <Case> Hash as absent and parses the script without a problem`, with TestCases `SHA512:abc`, `SHA256:` plus 63 digits, and the non-string `42`
- `still reports <Case> on the fast path`, with TestCases missing file, malformed target, target listed by two entries, and existing registration without `-Force`
- `falls through to the parse path when the script cannot be read for the hash` (`Get-CompleterScriptHash` mocked to throw)
- `writes one verbose line per entry and one summary line per set`
- `ignores Hash on a trusted entry and never reads its script` (`Get-CompleterScriptHash` invoked 0 times)
- `never executes a non-conforming script whose entry took the fast path`: the test writes `probe_completer.ps1` into `TestDrive` with a literal `Register-ArgumentCompleter -Native -CommandName setfixtureprobe`, plus a top-level `New-Item` of a probe file under `TestDrive`, which the strict grammar rejects. `Export-CompleterSet` writes a matching `Hash` for it, because the export only derives targets through `Get-CompleterScriptTarget` (`src/Public/Export-CompleterSet.ps1`) and never runs the grammar walk, so a script with literal targets exports even when its body fails the grammar. The import takes the fast path (verbose `hash matches`), the first tab moves the record to `Failed` with the grammar findings in `LoadError`, and the probe file is still absent.
- `fails a target the script does not register on its first press when a hand-written Hash matches` (ends `did not register a completer for`): the test writes a conforming script into `TestDrive`, computes its hash in module scope with `Get-CompleterScriptHash -LiteralPath`, and writes the set text by hand with that `Hash` and a `Targets` list holding one extra target the script does not register.

Acceptance:
- The existing test "reads the set through Import-PowerShellDataFile only and never evaluates set content" still passes.
- Every 2.0.0 test passes unchanged.
- The new counts hold on every CI leg.

### WP4 Bulk registration path

Depends on WP2 and WP3 (same files). Run it after WP3, not in parallel with it.

Files:
- `src/Private/Get-CompleterRegistrationSnapshot.ps1` (adds `RuntimeContext`);
- `src/Private/Resolve-CompleterRegistrationConflict.ps1` (optional `-RegistrationState`);
- `src/Private/Resolve-CompleterSetRegistration.ps1` (one state pass per set, per-entry slices);
- `src/Private/Add-CompleterRegistration.ps1` (optional `-Snapshot`, two passes, rollback over both);
- `src/Private/Add-RuntimeCompleterRegistration.ps1` (optional `-Runtime`, writes a created dictionary back);
- `src/Private/Add-ManagedCompleterRegistration.ps1` (optional `-Table`);
- `src/Public/Import-CompleterSet.ps1` (passes `-Snapshot`);
- `tests/CompleterSet.Tests.ps1`;
- `tests/CompleterRegistration.Tests.ps1`.

Which helpers gain a batch entry point:

| Helper | After 2.1.0 |
| --- | --- |
| `Resolve-CompleterRegistrationState` | Already takes `-Key [string[]]` and `-Snapshot`. Called once per set with every key. No signature change. |
| `Resolve-CompleterRegistrationConflict` | Gains `-RegistrationState`. Still called per entry slice (choice 5). |
| `Add-CompleterRegistration` | Always a runtime pass, then a managed pass, with the choice 6 rollback contract. Gains `-Snapshot`, which only supplies the runtime object and the managed table. With one registration the behaviour is 2.0.0's. |
| `Add-RuntimeCompleterRegistration` | Gains optional `-Runtime`. Still one call per target. |
| `Add-ManagedCompleterRegistration` | Gains optional `-Table`. Still one call per record, so the shims keep working. |
| `Get-CompleterRegistrationSnapshot` | Adds `RuntimeContext`. |
| `Remove-RuntimeCompleterRegistration`, `Remove-ManagedCompleterRegistration` | Stay per-target. Rollback only. |
| `New-CompleterRegistrationRecord`, `New-CompleterLazyStub` | Stay per-target. Built once per target in the session phase, as today. |
| `Register-Completer`, `Unregister-Completer`, `Invoke-CompleterLazyStub` | Unchanged. They keep their per-target transactions and call the helpers without the new parameters. |

Change: choices 5 and 6.
- **Measure first.** Before and after, run a scratch harness (not committed) that times `Import-CompleterSet` over the hashed PS_Completers set in a child `pwsh -NoProfile`. It also times the entry-resolution and write phases through pass-through shims in module scope. Compare against the §7 budget: at most 550 ms total, 300 ms resolution, and 120 ms write.
- **If the budget is missed.** Candidate reductions, in order of measured payoff: replace `Test-Path` with `[System.IO.File]::Exists` in the static phase; remove pipeline cmdlets (`ForEach-Object`, `Where-Object`) from the per-target loops; build each record with one `New-CompleterRegistrationRecord` call and no intermediate objects. None of these may change a record.

Tests:
- Modified, `tests/CompleterSet.Tests.ps1`: `reads the session registrations once and resolves each entry against that snapshot` changes `$counts.States` from 3 to 1, with the new reason "the set resolves every target in one state pass". The `It` name is unchanged.
- New, `tests/CompleterSet.Tests.ps1`: `resolves the runtime dictionaries and the managed table once per set`. Pass-through shims count exactly one `Get-CompleterRuntime` call and one `Get-ManagedCompleterRegistrationTable` call per set, both made by the snapshot.
- New, `tests/CompleterSet.Tests.ps1`: `imports only the confirmed entries as one transaction under -Confirm` (§8 check 12). The test runs `Import-CompleterSet -Confirm` in a runspace whose host answers `PromptForChoice` from a queue (Yes, No, Yes). That host is a test-only C# `PSHost` compiled with `Add-Type` in `BeforeAll`. Pester cannot otherwise answer a ShouldProcess prompt (see risk 12).
- New, `tests/CompleterSet.Tests.ps1`: `treats each set of one call as its own transaction`. A later set fails to write, and the earlier set stays registered.
- New, `tests/CompleterSet.Tests.ps1`: `rolls back the set when a runtime write fails partway through the batch`. A shim on `Add-RuntimeCompleterRegistration` throws for the second entry. The test asserts the 2.0.0 message and that no runtime or managed change remains.
- New, `tests/CompleterSet.Tests.ps1`: `rolls back every runtime write of the set when the managed write of the first record fails`. A shim on `Add-ManagedCompleterRegistration` throws on the first record of a three-entry set. The test asserts that no runtime value remains for any key of the set, including the later records whose runtime writes had succeeded, that no managed record was added, and that the message names the first record's `RuntimeKey`.
- New, `tests/CompleterSet.Tests.ps1`: `rolls back both passes when the managed write of the second of three entries fails`. Every runtime value and managed record of the set is back to its state before the import, and the message names the second record.
- New, `tests/CompleterSet.Tests.ps1`: `restores the replaced runtime values and managed records when a forced re-import fails partway through`. A set is imported, its first entry's first target is pressed so that the record is `Active`, and the same set is imported again with `-Force` while the managed shim throws on the second record. The `Active` record and its live script block are restored exactly (compared by reference), and the other records are the `Pending` records from the first import.
- New, `tests/CompleterSet.Tests.ps1`: `reports a rollback failure of the batch after the registration failure`. The managed shim throws on the second record and a shim on `Remove-RuntimeCompleterRegistration` throws. The error is `Failed to import completer set. Failed to register the completer '<RuntimeKey>'. <reason> Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: <reason>`.
- New, `tests/CompleterSet.Tests.ps1`: `writes every runtime value of the set before the first managed record`. Pass-through shims on both write helpers append to one event log, and the test asserts that the last runtime add comes before the first managed add.
- New, `tests/CompleterSet.Tests.ps1`: `reports a set whose entries are all invalid without a state pass`, with TestCases for no switch and `-SkipInvalid`. Every entry fails a static check (a missing file and a non-`.ps1` path). Without the switch the error is 2.0.0's `Failed to import completer set. Completer set '<path>' has 2 invalid entries and nothing was registered. ...`. With `-SkipInvalid` the output is 2.0.0's two `Completer set '<path>' skipped ...` warnings and no records, and the two-pass `Add-CompleterRegistration` receives empty arrays and writes nothing, as today. A counting shim shows `Resolve-CompleterRegistrationState` invoked 0 times in both cases (choice 5, empty-key guard).
- New, `tests/CompleterRegistration.Tests.ps1`, Describe `Private completer registration helpers`: `creates a missing runtime dictionary once and reuses it for every write of a batch`. It uses a test class with a settable dictionary property as the runtime object.
- Unchanged and must pass: the five tests listed in §8 check 11, and `tests/CompleterActions.Tests.ps1` `keeps the earlier targets of one call when a later target fails to write`, `rolls back a fresh registration when the managed store write fails`, `restores the previous registration when a forced replacement fails to update the managed store`, and `reports a rollback failure separately from the registration failure`.

Acceptance:
- §8 checks 11 to 13 pass.
- The scratch harness shows the resolution and write phase numbers. They go into the pull request next to the benchmark table.

### WP5 Reset-Completer

Independent of WP1 to WP4, so it can start on day one in its own worktree. It calls `Add-CompleterRegistration` without `-Snapshot`, so the WP4 signature change does not affect it.

Files:
- new `src/Public/Reset-Completer.ps1`, with full comment help mirroring `Unregister-Completer.ps1`;
- new `src/docs/CompleterActions/Reset-Completer.md`, PlatyPS 1.0 schema with the front matter copied from `Unregister-Completer.md`. Generate a skeleton with `New-MarkdownCommandHelp -CommandInfo (Get-Command Reset-Completer) -OutputFolder <scratch>` and copy it in. Never run the `Markdown_templates` task (risk 9);
- `src/docs/CompleterActions/CompleterActions.md` (module page entry);
- `CompleterActions.psd1` (`FunctionsToExport` gains `'Reset-Completer'` after `'Register-CompleterRegistrationLegacy'`);
- `src/Public/Register-Completer.ps1` and `src/docs/CompleterActions/Register-Completer.md`: example 4 becomes `Get-Completer -State Failed | Reset-Completer`, and the "Registering the same target again with -Force retries the load" sentence gains "or use Reset-Completer";
- `src/Public/Unregister-Completer.ps1` and `src/docs/CompleterActions/Unregister-Completer.md`: the description gains one sentence, "To reload a Failed or Active script-backed registration instead of removing it, use Reset-Completer.", and the markdown's RELATED LINKS gains `[Reset-Completer](Reset-Completer.md)`. No `.LINK` is added to the comment help: no `src/Public/*.ps1` file uses `.LINK`, and the packaged psm1 replaces comment help with `.EXTERNALHELP`, so RELATED LINKS in the markdown is what `Get-Help` shows. The help XML is rebuilt in the same commit;
- new `tests/CompleterReset.Tests.ps1`, carrying its own copy of the runtime cleanup helper, as each test file does;
- `tests/CompleterDeprecation.Tests.ps1` line 28: `11` becomes `12`;
- the regenerated help XML and `build/`.

Format and type updates: none. The output is `CompleterActions.CompleterRegistration`, which already has the table view. No build-script change: the build derives `FunctionsToExport` from `src/Public`, and the psm1 exports by file name.

Change:
- **Parameters.** `[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]` and `[OutputType('CompleterActions.CompleterRegistration')]`. The parameter sets, types, and pipeline bindings are copied from `Unregister-Completer`, minus `-AllowUnmanaged`.
- **Per target.**
  - An `OrdinalIgnoreCase` `HashSet` skips a key already decided in the same call.
  - `Resolve-CompleterRegistrationState -Key` runs once for the target.
  - §5's precedence runs in order: managed record exists; `Pending` is a no-op; `Stale` removed; `Stale` or `Failed` with an outside live value; empty `ScriptPath`; the script file exists (`Test-Path -LiteralPath -PathType Leaf`).
  - Then `ShouldProcess(<RuntimeKey>, 'Reset completer registration')`, and the write through choice 7.
- **Input objects.** They are resolved one at a time in a `foreach`, not through one pipeline, so a bad element of an array-bound `-InputObject` does not strand the rest.
- **Errors.** Every per-target failure goes through `$PSCmdlet.WriteError` with `Failed to reset the completer '<RuntimeKey>'. <reason>` and category `InvalidOperation`. The call then continues. A rejected input object has no key yet, so its text is `Failed to reset the completer. <reason>` (open item 3). `-ErrorAction Stop` turns these into stop-on-first-error.

Tests (`tests/CompleterReset.Tests.ps1`):
- `returns a Failed record to Pending and loads the fixed script on the next tab press` (§8 check 2, first run)
- `resets every resettable record piped from Get-Completer -State Failed and reports the rest` (§8 check 2, second run: two errors, the resettable record `Pending` even though an error came before it, and exactly two left `Failed`)
- `returns an Active lazily loaded record to Pending with LoadError and ImportModule cleared` (check 14)
- `prints the WhatIf line and changes nothing` (check 15)
- `leaves a Pending target alone without ShouldProcess and returns it with -PassThru`
- `writes a non-terminating error for <Case>`, with TestCases for Discovered, script-block Active, Stale with the runtime removed, Stale with an outside value, Failed re-registered outside, nothing registered, and missing script (check 16). Each asserts the exact §5 message, that the next target still runs, and that `$?` is `$false`.
- `leaves a Pending record whose script was deleted alone without an error` (precedence)
- `resets only the named targets and leaves an Active sibling loaded`
- `decides a key once per call`
- `restores the previous runtime value and managed record when the reset write fails` (shim on `Add-ManagedCompleterRegistration`)
- `reports an input object it cannot resolve and continues with the next`
- `stops at the first error with -ErrorAction Stop`
- `mirrors the parameter sets of Unregister-Completer apart from -AllowUnmanaged` (check 17, comparing `Get-Command` metadata: set names, parameter types, mandatory flags, pipeline flags)
- `reloads a trusted record under the trusted tier`

Acceptance:
- `Get-Command Reset-Completer -Syntax` shows the three sets.
- `Get-Help Reset-Completer -Full` resolves from a fresh build in a separate process.
- The suite passes with 12 exported functions.

### WP6 Test-CompleterSet

Depends on WP1 (hash helper, NoHash fixture), WP2 (static phase, typed problems), and WP3 (the static phase's single-parse shape and `-Verify`, choice 3). It can run in parallel with WP4 and WP5. WP6 does not edit `src/Private/Resolve-CompleterSetEntry.ps1`; it only calls it with `-Verify`.

Files:
- new `src/Public/Test-CompleterSet.ps1`, with comment help;
- new `src/Private/Get-CompleterSetEntryExtent.ps1` (choice 8);
- new `src/Private/Get-CompleterSetFinding.ps1`, the per-set logic, mirroring how `Test-CompleterScript` delegates to `Get-CompleterScriptFinding`;
- new `src/docs/CompleterActions/Test-CompleterSet.md`, generated as in WP5;
- `src/docs/CompleterActions/CompleterActions.md`;
- `CompleterActions.psd1` (`'Test-CompleterSet'` after `'Test-CompleterScript'`);
- new `tests/CompleterSetDrift.Tests.ps1`;
- `tests/CompleterDeprecation.Tests.ps1`: `12` becomes `13`, or `11` becomes `13` if WP6 lands before WP5;
- the regenerated help XML and `build/`.

Format and type updates: none. The output is `CompleterActions.CompleterScriptFinding`, which already has the list view.

Change:
- **Parameters.** `[CmdletBinding(DefaultParameterSetName = 'Path')]`, `[OutputType('CompleterActions.CompleterScriptFinding')]`. `-Path` and `-LiteralPath` bind exactly as in `Import-CompleterSet`. `-Filter` defaults to `*_completer.ps1`. There is no `ShouldProcess`.
- **Paths and reading.** Every path is resolved first. Each set is then read through `Import-CompleterSetDefinition`. Any failure is thrown as `Failed to test completer set. <reason>`.
- **Per entry.** The command calls the static phase with `-Verify` (added in WP3, choice 3), so there is no fast path: a strict entry is always parsed, once, and `ActualHash` comes from that parse's text. A trusted entry is never parsed; `ActualHash` comes from `Get-CompleterScriptHash -LiteralPath`. `Get-CompleterSetFinding` maps the typed problems to `MissingScript`, `InvalidEntry`, `UnreadableTargets`, and `TargetMismatch`, and compares `ActualHash` with the declared `Hash` for the three hash kinds.
- **Duplicates.** The session phase is not run, so `Get-CompleterSetFinding` implements §6's claiming rule itself over the resolved targets (choice 3), ignoring the session.
- **Unlisted scan.** A recursive `Get-ChildItem -LiteralPath <set dir> -Filter $Filter -File` is compared case-insensitively on Windows and case-sensitively elsewhere. Listed paths include absolute paths outside the directory.
- **Findings.** Built with `New-CompleterScriptFinding` using the extents of choice 8. `Path` is the set file.
- **Order.** Entries come in set order. Within an entry, findings follow the §6 table order: MissingScript, InvalidEntry, UnreadableTargets, TargetMismatch, DuplicateTarget, HashMismatch, MissingHash, InvalidHash (open item 2). Unlisted scripts follow, sorted by path.
- **Session.** The command never touches the session.

Tests (`tests/CompleterSetDrift.Tests.ps1`). The fixture folder is copied into `TestDrive` and the set regenerated with `Export-CompleterSet` in `BeforeEach`.
- `returns nothing and leaves $? true for a set that matches its folder`
- `reports <Mutation> and nothing else`, with TestCases for the seven §8 check 18 mutations. Each asserts `Construct`, `Severity`, `Path` equal to the set file, `Line` at the §6 extent, and that `Import-CompleterSet` without `-SkipInvalid` rejects the set exactly when an `Error` is present. Reverting the mutation yields no findings.
- `reports MissingHash for every entry of the checked-in 2.0.0 set` (NoHash fixture)
- `reports InvalidHash as a Warning for an unrecognised Hash` (§8 check 10, second half)
- `reports InvalidEntry with the import problem text word for word for <Case>`, with TestCases for: not a hashtable, no Path, not a .ps1, Trusted not a bool, malformed target, trusted without Targets
- `reports UnreadableTargets for a strict script that <Case>`, with TestCases for: does not parse, uses a non-literal target, registers no literal targets
- `never parses a trusted entry`
- `reports <Kind> for a trusted entry without parsing it`, with TestCases `HashMismatch` (the trusted script is edited after export) and `MissingHash` (its `Hash` line is removed). `Get-CompleterScriptParseResult` is invoked 0 times in both.
- `counts a script listed by an absolute path outside the set directory as listed`
- `treats a listed path that differs only in case as <Expected>`: an entry's `Path` is recased in the set text. The expectation is platform-gated: listed, with no finding, on Windows; `UnlistedScript` for the file, plus the entry's `MissingScript`, on Linux, where the recased path does not exist.
- `scans with -Filter and ignores files that do not match it`
- `binds <Parameter> like Import-CompleterSet`, with TestCases: `-Path` with a wildcard (`*.psd1` in a folder holding two sets) tests both sets; `-LiteralPath` with a set file named `set[1].psd1` tests that file and does not expand the brackets.
- `throws Failed to test completer set for a set without Version = 1 and never executes a script`: the probe script is written into `TestDrive` at test time, exactly as in the WP3 probe test, and the probe file stays absent. No checked-in fixture is used.
- `writes the findings of an earlier set before throwing for a later unreadable set`
- `throws before writing anything when a path does not resolve`
- `never reads or writes the session registrations`: `Get-CompleterRegistrationSnapshot`, `Get-CompleterRuntime`, and `Get-ManagedCompleterRegistrationTable` are invoked 0 times, and `Get-Completer` output is unchanged.
- `points findings at the right extents in <Shape> Entries arrays`, with TestCases for comma-separated, newline-separated, and newline-separated with a `$null` element between two entries. In the `$null` case, a finding on the entry after the `$null` has the `Line` of that entry's extent, and the `Entry <n>` in its `Message` equals the number `Import-CompleterSet` gives the same entry in its problem text (`Import-CompleterSetDefinition` drops `$null` elements before numbering, `src/Private/Import-CompleterSetDefinition.ps1`).
- `accepts set files piped from Get-ChildItem`
- In `tests/CompleterReset.Tests.ps1`, added here because both commands must exist: `leaves PSReadLine key handlers unchanged across Reset-Completer, the reloading tab press, and Test-CompleterSet` (§8 check 20, new test)

**PS_Completers follow-up.** This is described here but NOT made. The owner makes it after release, in the order that §6 "Adopting 2.1.0" sets:
1. Upgrade the module. The CI there installs the latest with `-Prerelease`, so it moves to 2.1.0 on release day. The old gate keeps passing.
2. Regenerate the set: `pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1`. Expect one `Hash` line per entry, 173 insertions and 0 deletions. Commit.
3. In `tests/Completers.Tests.ps1`, replace the `Describe 'ps_completers.psd1 matches the repository'` block with the §6 block verbatim:
   - `Import-Module -MinimumVersion 2.1.0`;
   - `keeps every entry on the strict tier` stays as it is;
   - `imports lazily and lists exactly the completer scripts in the repository` is replaced by `has no drift`;
   - the `AfterAll` is removed.

   The conformance `Describe` stays.
4. Optionally, in `tools/Export-CompleterSetFile.ps1`, change `Register-CompleterRegistration` to `Register-Completer` and raise `#Requires` to 2.1.0.

Steps 2 and 3 may share one commit. Step 3 must never land before step 2, because `MissingHash` is a `Warning` and the gate asserts empty output. The test count of that run stays the same.

Acceptance:
- §8 checks 18 and 19 pass in Pester.
- §8 check 3 passes in the WP9 scratch clone, run as WP9's four-run gate step. The branch build reports 2.0.0, so the replaced gate's `Import-Module -MinimumVersion 2.1.0` cannot load it. WP9 runs the gate against a version-stamped scratch copy of the branch build, and the release recipe runs the replaced gate once more against the release commit's build before tagging (WP9, "Module sources").
- The suite passes with 13 exported functions.

### WP7 Startup benchmark, second edition, and its recorded number

The tool changes can start after WP1. The recorded number needs WP3 and WP4 merged.

Files: `tools/Measure-CompleterStartup.ps1` (comment help too); `CHANGELOG.md` (the Performance bullet); `README.md` (the benchmark sentences in "Lazy loading and completer sets").

Change, the five §7 edits:
1. The Lazy leg imports the set exported by the module under test, which now carries `Hash`.
2. A new `LazyNoHash` leg imports a copy with every `^\s*Hash\s*=` line removed. The copy is written next to the hashed set, so relative paths resolve the same way.
3. A new `-BaselineModulePath` runs a `Baseline` leg with the 2.0.0 package over the no-Hash copy, which is what a 2.0.0 profile imports. That makes `LazyNoHash` against `Baseline` a same-input comparison. The samples are interleaved per iteration: Eager, Baseline, Lazy, LazyNoHash. The baseline package comes from `git archive v2.0.0 build | tar -x -C <scratch>`, with no worktree.
4. `-Iterations` defaults to 10, up from the tool's current `[int] $Iterations = 5`. Ten is the §7 figure and the CHANGELOG wording ("ten samples each"). It deliberately replaces the five samples per leg that the 2.0 numbers used (README, "five samples per leg"), so the 2.0 and 2.1 tables are not a like-for-like comparison. The PR and the CHANGELOG bullet compare only against the same-run `Baseline`, never against the 2.0 figures.
5. Each row gains `RatioToBaseline`, which is empty when there is no baseline.

Unchanged: every sample still runs in a fresh child `pwsh -NoProfile -NonInteractive -EncodedCommand`, and the Eager and Lazy legs remain.

**Input guard.** Before the first sample, the tool counts the entries (`^\s*Path\s*=` lines) and the `^\s*Hash\s*=` lines of the hashed set and of the `LazyNoHash` copy, and prints both counts through `Write-Verbose` and as a line of the output header. It throws, and takes no sample, unless the hashed set has exactly one `Hash` line per entry and the copy has none. This catches a `-ModulePath` that points at a 2.0.0 build (which writes no `Hash`, so `Lazy` and `LazyNoHash` would be the same input) and a strip regex that misses, either of which would otherwise print a meaningless ratio.

The run uses PS_Completers as it is on the day, and `-ModulePath` points at the branch's `build/CompleterActions`.

Recording:
- **Pull request.** The tool's full table, the pwsh version, the OS, the script and target counts, the commit, and the WP4 phase numbers.
- **CHANGELOG, under `### Changed`.** A bullet that opens with "**Performance.**" and uses the §7 wording: `Startup benchmark over the 173-script set, ten samples each: 2.0.0 lazy median <n> ms, 2.1.0 lazy median <n> ms, ratio <r> against the 0.50 target; an unhashed set <n> ms.` The roadmap is updated at release (see the release recipe).
- **Miss.** A `RatioToBaseline` of 0.50 or higher follows the §7 fallback: ship with the measured ratio, restate the roadmap exit criterion in the same pull request, state the miss plainly, and get the owner's sign-off before merging. It is never relabelled as a pass.

Acceptance:
- §8 check 1, where `Lazy` `RatioToBaseline` is below 0.50 and `LazyNoHash` is within 10 percent of `Baseline`.
- A dry run with `-Iterations 1` and `-BaselineModulePath` prints all four legs, the two hash counts (one per entry and zero), and a `RatioToBaseline` on every row.
- A dry run with `-Iterations 1` and no `-BaselineModulePath` prints no `Baseline` row and an empty `RatioToBaseline` on every row.
- A dry run with `-ModulePath` pointing at the 2.0.0 package throws from the input guard before any sample.
- The tool lints clean. This is a local check: CI lints only `./src` and `./tests`, and no Pester test covers the tool, so these dry runs are its verification. Their output goes into the pull request.

### WP8 Documentation

Starts once WP5 and WP6 have fixed the surface. It can run in parallel with WP7.

Files: `CHANGELOG.md`, `en-US/about_Completer_Sets.help.txt`, `README.md`, `.github/copilot-instructions.md`, `en-US/about_CompleterActions_Migration.help.txt`.

Change:
- **CHANGELOG `## [Unreleased]`.**
  - `### Added`:
    - `Reset-Completer`, with its target contract, its non-terminating errors, and the difference from `Unregister-Completer`;
    - `Test-CompleterSet`, with the drift kinds and the empty-when-clean shape;
    - the optional per-entry `Hash` key in the set schema, written by `Export-CompleterSet`, with `Version` still `1` and 2.0.0 ignoring the key.
  - `### Changed`:
    - `Import-CompleterSet` skips the parse for a strict entry whose `Hash` matches, and a set without `Hash` imports exactly as before;
    - a set is written as one bulk batch with the same rollback;
    - `Export-CompleterSet` writes a strict entry's `Targets` in script order and casing, and hashes trusted scripts, warning when one cannot be read;
    - the `Register-Completer` retry example now uses `Reset-Completer`;
    - the WP7 Performance bullet.
- **`about_Completer_Sets`** (§9 question 7 recommendation):
  - `Hash` joins THE SET FILE SCHEMA list and the sample;
  - one paragraph on the fast path under VALIDATION BEFORE REGISTRATION. It includes the WP3 repeated-key sentence: a hand-edited entry that lists a key twice keeps the first occurrence's casing on the fast path and the last occurrence's casing on the parse path;
  - in the same section, the existing sentence "it parses each strict script once, to validate the entry, registers the targets that parse derived" becomes "it parses each strict script once, unless the entry's `Hash` matches, to validate the entry, ...";
  - one paragraph on `Test-CompleterSet` under WORKFLOW;
  - `Reset-Completer` replaces "Registering the script again with `-Force` ... retries the load" in LAZY LOADING, PENDING, AND FAILED;
  - EXAMPLE 5 is `Get-Completer -State Failed | Reset-Completer`;
  - SEE ALSO gains both commands.

  The full hash and drift sections stay deferred to 2.2.0.
- **README.** The command map gains two rows, in alphabetical position:
  - `Reset-Completer`: "Returns a Failed or Active script-backed completer to Pending so its script loads again on the next tab press"
  - `Test-CompleterSet`: "Reports drift between a completer set file and the scripts on disk as findings; empty when the set matches"

  The "Lazy loading and completer sets" section gains one sentence on `Hash` and one on `Reset-Completer`, and its existing "importing a set parses each strict script once, to validate the entry" becomes "importing a set parses each strict script once, unless the entry's `Hash` matches, to validate the entry". The `State` paragraph's "`Register-Completer -Force` retries" gains "or `Reset-Completer`".
- **`.github/copilot-instructions.md`.** "eight commands" becomes ten, "eleven functions" becomes thirteen, and both new commands go into the command list.
- **`about_CompleterActions_Migration`.** "lists eleven functions and three aliases" becomes "lists thirteen functions (eleven in 2.0.0) and three aliases".

Acceptance:
- `Get-Help about_Completer_Sets` resolves after import. The existing test "loads the about help topic for completer sets" passes.
- A search for `parses each strict script once` and `retries` across `en-US`, `src/Public`, `src/docs`, and `README.md` finds no sentence that still says an import always parses, and every sentence that tells the reader how to retry a `Failed` load names `Reset-Completer` alongside `-Force`.
- The CHANGELOG has no 2.1.0 heading yet; that is cut at release.

### WP9 Runtime validation pass (powershell-runtime-validator)

Runs after WP1 to WP8 are on the branch and `build/` is fresh. Every check runs in its own `pwsh -NoProfile`. Checks that touch PS_Completers run in a scratch clone (`git clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers`). The real Completers repo is not touched.

**Module sources.** Three module packages are used, and none is ever the gallery copy installed on the owner's machine (also version 2.0.0):

- **2.0.0 package:** `git archive v2.0.0 build | tar -x -C <scratch>\v2.0.0`, the same extraction WP7 uses.
- **Branch build:** `<repo>\build\CompleterActions`. Until the release commit it reports `ModuleVersion = '2.0.0'`, like the 2.0.0 package.
- **Stamped branch build:** `Copy-Item <repo>\build\CompleterActions <scratch>\stamped\CompleterActions -Recurse`, then set `ModuleVersion = '2.1.0'` in the copy's `.psd1` only. The content is the branch build's. It exists only because the replaced PS_Completers gate says `Import-Module -Name CompleterActions -MinimumVersion 2.1.0`, and the live gate already pins `-MinimumVersion 2.0.0` (`tests/Completers.Tests.ps1`), so a by-name import is unavoidable there.

Rules:
- Checks outside the gate import a package by the full path of its `.psd1`, never by name, and assert `(Get-Module CompleterActions).ModuleBase` before they run. The two unstamped packages report the same version, so the path is the only way to tell them apart.
- The gate runs (check 3) and the regeneration tool (checks 3, 5, 7, 9) import by name. The spec's §8 run rules were revised with this plan to say the same. They run with `$env:PSModulePath = "<scratch>\stamped;$env:PSModulePath"`, so the stamped copy is found first and satisfies both `-MinimumVersion 2.0.0` and `2.1.0` as well as the tool's `#Requires` 2.0.0. Each such run ends with `(Get-Module CompleterActions).ModuleBase` in the same process, and the step fails unless it is the stamped path.
- The version line of check 21 (`(Get-Module CompleterActions).Version` is `2.1.0`) is verifiable only on the release commit, so it is checked in release recipe step 3, not here.

It runs §8 checks 1 (benchmark, from WP7), 2, 3, 4, 5, 7 (the real-set CSV comparison, 2.1.0 hashed against 2.0.0 unhashed), 9, 14, 15, 20 (a live `Get-PSReadLineKeyHandler -Bound -Unbound` snapshot), 21 (13 functions, 3 aliases, 2.0.0's 11 functions with identical parameter names and sets compared through `Get-Command` metadata from the branch build and the 2.0.0 package), and 22 (`Get-Help Reset-Completer -Full` and `Get-Help Test-CompleterSet -Full` from the build). Check 12 runs here as a manual check only if risk 12's fallback was taken and the WP4 `-Confirm` test was dropped with the owner's sign-off: `Import-CompleterSet -LiteralPath $fixtureSet -Confirm` in an interactive `pwsh -NoProfile`, declining the second of three entries, returns the first and third records and registers nothing for the second.

**PS_Completers gate step (check 3, with checks 5, 7, and 9).** In the scratch clone, in this order, each run in its own `pwsh -NoProfile`:

1. **Old gate, unregenerated set.** `Invoke-Pester -Path ./tests -Output Detailed` passes (adoption step 1: the unmodified gate still passes under 2.1.0). Record the test count.
2. **Replaced gate, unregenerated set.** Replace the drift `Describe` of `tests/Completers.Tests.ps1` with the §6 block, uncommitted. The same Pester run fails exactly in `has no drift`, and `Test-CompleterSet -LiteralPath ./ps_completers.psd1` returns 173 findings, all `MissingHash`, one per entry, and nothing else. This is why the adoption order matters.
3. **Regenerate.** `pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1`. Then check 5, as a hard gate: `git diff --numstat ps_completers.psd1` is exactly `173 0`, and every added line matches `^\s{12}Hash    = 'SHA256:[0-9A-F]{64}'$` between its entry's `Trusted` and `Targets` lines. A reorder or recase from the WP1 export change would show up here as deletions. If this gate fails, the pull request is not opened: the owner decides between keeping record order for strict entries whose record order already matches their derived keys (which breaks check 7's record equality for those entries) and shipping the reorder with a CHANGELOG `### Changed` note naming it. The plan's default is to ship the reorder, because script order is what lets the fast path reproduce 2.0.0's records (§2).
4. **Replaced gate, regenerated set.** `Test-CompleterSet -LiteralPath ./ps_completers.psd1` writes nothing and `$?` is `$true`, and the Pester run passes, with the same test count as run 1.

Checks 7 and 9 then use the regenerated set from run 3.

Acceptance: every check matches the §8 expected output. Any miss goes back to the owning package before the pull request is opened. The pull request carries the CSV that check 4 produced under the 2.0.0 package, as the record of the 2.0.0 side.

### WP10 Pull request and release 2.1.0

See "Release recipe" below.

## Order and parallelism

```text
WP1 (hash, export) ─┐
                    ├─> WP3 (fast path, -Verify) ─┬─> WP4 (bulk) ───────────┐
WP2 (split)  ───────┘                             │                         ├─> WP7 number ─┐
                                                  └─> WP6 (Test-CompleterSet) ─┐            ├─> WP9 ─> WP10
WP5 (Reset-Completer) ─────────────────────────────────────────────────────────┴─> WP8 (docs) ┘
WP7 tool edits may start after WP1.
```

- **Day one, in parallel:** WP1, WP2, and WP5. Their files do not overlap.
- **After WP1 and WP2:** WP3. It owns every edit to `Resolve-CompleterSetEntry`, including `-Verify`.
- **After WP3:** WP4 and WP6 in parallel. WP4 edits `Resolve-CompleterSetRegistration`, `Import-CompleterSet`, and the write helpers; WP6 adds new files and only calls the static phase. The one shared file is the manifest and function count, which WP6 shares with WP5 as well.
- **After WP5 and WP6:** WP8. The WP7 tool edits run in parallel from WP1 onward. The recorded number waits for WP4.
- **Merge conflicts to expect:** WP5 and WP6 both add one manifest line and both bump the function count in `tests/CompleterDeprecation.Tests.ps1`. WP5 and WP8 both touch the `Register-Completer` retry wording. Resolve each in favour of the later package, and rebuild `build/` after every merge.

## Verification checklist

Before the pull request:

- [ ] `pwsh -NoProfile -Command "Invoke-Build -Task build"` succeeds in its own process, first. `build/` and both help XML files are committed.
- [ ] Then `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"` passes in a new process (target: about 326 tests; see the estimate), including "keeps the tracked build output in sync with the module sources".
- [ ] PSScriptAnalyzer over `./src` and `./tests` returns nothing, in a process separate from Pester. That is the CI Lint scope and the pass criterion. `./tools` is linted too, as a local extra for the WP7 tool; CI does not lint it.
- [ ] `git ls-files --eol` shows every edited or new text file as `w/crlf` on Windows, and no file shows `i/crlf`.
- [ ] Every §8 check below has passed where it is marked.

| §8 check | Where it is verified |
| --- | --- |
| 1 Hashed import under 0.50 of Baseline | WP7 run, WP9 |
| 2 Reset of Failed records, error continuation | WP5 Pester, WP9 live |
| 3 Test-CompleterSet empty on the regenerated set, gate passes | WP9 gate step (four runs, stamped copy); release recipe step 3 (real 2.1.0 build) |
| 4 Untouched set imports identically on 2.0.0 and 2.1.0 | WP9 (2.0.0 package and branch build, by path; CSV attached to the PR) |
| 5 Export adds one `Hash` per entry; script order; trusted missing file | WP1 Pester, WP9 gate step run 3 (`173 0` numstat and the line regex, a hard gate) |
| 6 Hash independent of line endings | WP1 Pester, on both OS legs |
| 7 Fast path skips the parse only | WP3 Pester, WP9 real-set CSV |
| 8 A wrong hash never runs unchecked code | WP3 Pester |
| 9 A hashed set imports on 2.0.0 | WP9 |
| 10 Unrecognised `Hash` falls back; `InvalidHash` reported | WP3 and WP6 Pester |
| 11 Bulk-path tests unchanged, counts 1 per set | WP4 Pester |
| 12 `-Confirm` declines one entry | WP4 Pester (scripted host); WP9 manual check only under risk 12's fallback |
| 13 Register-Completer per-target transaction | existing Pester |
| 14 to 17 Reset-Completer | WP5 Pester |
| 18, 19 Test-CompleterSet mutations and failures | WP6 Pester |
| 20 PSReadLine snapshots | existing and WP6 Pester, WP9 live |
| 21 Surface (13 functions, 3 aliases, 2.0.0 parameters identical) | WP9; the version line on the release commit |
| 22 Suite, lint (`./src` and `./tests`), eight CI legs, help from the build | pull request CI, WP9 |

After the pull request: all eight CI legs are green (Windows and Ubuntu × 7.4, 7.5, 7.6, preview), and the owner has reviewed it. If the WP7 ratio missed 0.50, the owner has also signed off on the miss.

## Release recipe for 2.1.0

The version is bumped only at release time. The branch keeps `ModuleVersion = '2.0.0'`, so "declares a module version that satisfies the release policy" holds throughout. That is why WP9 runs the 2.1.0-floored PS_Completers gate against a stamped scratch copy, and why step 3 repeats it against the real build before tagging. Join every step with `&&`, and check the changelog heading before tagging (the preview3 lesson).

1. Open the pull request from `feat/milestone-1-faster-imports` to `main` with `gh pr create`. Its body carries the WP7 table and the WP4 phase numbers. Merge it after the checklist is complete.
2. On `main`, make the release commit:
   - in `CompleterActions.psd1`, set `ModuleVersion = '2.1.0'` and leave `# Prerelease = ''` commented, keeping CRLF;
   - in `CHANGELOG.md`, move the Unreleased entries under a new `## [2.1.0] - <date>` heading and leave `## [Unreleased]` empty above it;
   - update the link block: `[Unreleased]: https://github.com/tstager/CompleterActions/compare/v2.1.0...HEAD` and a new `[2.1.0]: https://github.com/tstager/CompleterActions/compare/v2.0.0...v2.1.0`. Check the link block as well as the heading (the rc1 gotcha).
3. Run `pwsh -NoProfile -Command "Invoke-Build -Task build"`, then in a separate process `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -CI"`. Then, each in its own `pwsh -NoProfile`:
   - confirm `(Import-Module ./build/CompleterActions/CompleterActions.psd1 -PassThru).Version` is `2.1.0` (§8 check 21, version line);
   - in the WP9 scratch clone, which still holds the regenerated set and the replaced gate, run `Invoke-Pester -Path ./tests -Output Detailed` with `$env:PSModulePath = "<repo>\build;$env:PSModulePath"` and assert that `(Get-Module CompleterActions).ModuleBase` is `<repo>\build\CompleterActions`. This is check 3's gate against the real 2.1.0 build, not the stamped copy. It must pass before tagging.
4. `git commit -am "chore(release): bump module version to 2.1.0"` with only the `Co-Authored-By` trailer.
5. Verify the heading: `Select-String -Path CHANGELOG.md -Pattern '^## \[2\.1\.0\]'` must match.
6. `git tag v2.1.0`, then `pwsh -NoProfile -Command "Invoke-Build -Task release_check"` on the tagged HEAD.
7. `git push origin-main main v2.1.0`, then `gh run watch` on the Release run. `release.yml` runs `release_check`, Pester, build, `Publish_build`, and the GitHub release. There is no hyphen in the tag, so the release is not marked as a prerelease.
8. Confirm the release:
   - `Find-PSResource CompleterActions -Repository PSGallery` lists 2.1.0 without a prerelease label;
   - `gh release view v2.1.0` shows it as Latest, with the 2.1.0 notes;
   - `Install-PSResource CompleterActions -Version 2.1.0 -Reinstall` succeeds locally.
9. Make a follow-up docs commit to `docs/roadmap-3.0.md`:
   - milestone 1's status row becomes "Shipped <date>, tag v2.1.0";
   - add a "Shipped" line with the benchmark numbers;
   - milestone 3's exit criterion becomes "10 functions, 0 aliases" (§1).

   Update the live roadmap page and its RAG source in place, as was done for 2.0.
10. Hand the PS_Completers follow-up (WP6) to the owner.

## Risks

1. **The 0.50 ratio may not be reached.** §7 puts the hash alone near 0.62. WP4 measures each phase against the 550/300/120 ms budget before and after. The §7 fallback (ship the measured ratio with the owner's sign-off) is the only fallback, and `Import-Module` stays in the measurement.
2. **Test shims replace private helpers by name.** If the batch stopped calling `Add-ManagedCompleterRegistration` or `Add-RuntimeCompleterRegistration` per record, the rollback tests would pass or fail for the wrong reason. Choice 6 keeps those per-record calls, and every new parameter is optional.
3. **A null runtime dictionary created twice in one batch** would silently drop the first half of the writes. `Add-RuntimeCompleterRegistration -Runtime` writes the created dictionary back, and WP4 has a unit test for it.
4. **.NET 5+ APIs would break the stated 7.0 floor** without any CI leg noticing. Choice 1 names the APIs to use. The WP1 review checks for `ToHexString` and `HashData`.
5. **Line endings.** With no `.gitattributes`, checked-in CRLF or BOM variants would be rewritten on checkout. The variants are generated at test time. The literal hash is cross-checked against the LF index blob, and both OS legs assert it.
6. **`ReadAllText` resolves relative paths against the process directory.** Every caller passes the full path that `GetFullPath(path, setDir)` already produces. This also covers the Windows-runner D: versus C: gotcha.
7. **Set-file position mapping** could drift from `Import-CompleterSetDefinition`'s entry numbering: `$null` elements are filtered, and arrays can be comma- or newline-separated. WP6's extents test has a TestCase for each array shape and one with a `$null` element between two entries.
8. **The fast path could change problem lists for invalid hashed entries.** Choice 4 takes the fast path only after a clean static phase.
9. **The `Markdown_templates` task overwrites every hand-edited help file** (`-Force`). New pages are generated one command at a time into scratch and copied in.
10. **Parallel packages conflict** on the manifest and the function-count assertion (WP5, WP6). Expected and small; rebuild `build/` after each merge.
11. **Pester in the same process as Invoke-Build or PSScriptAnalyzer** registers completers and breaks the paging tests. The run rules keep them in separate processes.
12. **A scripted `-Confirm` host** (a C# `PSHost` via `Add-Type`) adds compile time to one test file and is new test infrastructure. If it proves flaky on a CI leg, dropping the Pester test needs the owner's sign-off. With that sign-off, §8 check 12 becomes the conditional manual check listed in WP9, and the Pester test is dropped rather than skipped.
13. **The PS_Completers gate fails if it is switched before the set is regenerated.** WP6 spells out the order, and the owner makes the change after release. WP9's gate step shows both sides: the replaced gate fails with 173 `MissingHash` findings before regeneration and passes after it.
14. **Benchmark noise from OneDrive cold reads and machine load.** Samples are interleaved, run 10 per leg, and each leg's median is compared with the Baseline median from the same run.
15. **A two-pass batch write leaves runtime values behind if the rollback is not pass-aware.** Choice 6 tracks the runtime and managed passes separately, and WP4 has a test that fails the managed write of the first record and asserts that no later runtime value remains.
16. **The branch build and the 2.0.0 package report the same version.** A by-name import could load either one, or the installed gallery copy. WP9 imports by full path and asserts `ModuleBase` before every check, and uses a stamped scratch copy only where a by-name import cannot be avoided.

## Open items for the owner

The plan picks a default for each. The owner accepted every default on 2026-09-28, so none is open; they stay here as the record.

1. **Verbose wording the spec does not fix.** For trusted entries, strict entries without `Targets`, an unrecognised `Hash`, and an unreadable file, the plan uses the WP3 table text. For entries with a problem, no per-entry line is written and the entry is not counted in the summary.
2. **Order of findings within one entry.** The plan follows the §6 table order.
3. **Reset-Completer error texts.** The `<state>` in the outside-live-value message is lower case, as in `Unregister-Completer`. A rejected input object reads `Failed to reset the completer. <reason>`. A failed write nests `Failed to register the completer ...` inside the reset message (choice 7).
4. **Where the benchmark line goes in the CHANGELOG.** §7 asks for "a Performance entry". The plan keeps the Keep a Changelog section names and writes it as a bullet under `### Changed` that opens with "**Performance.**".
5. **§9 questions 1 to 5, 7, and 8.** The plan follows each recommendation as written. Question 6 is already resolved in §7.

## Estimated new Pester tests

| Package | File | New `It` blocks | Test cases |
| --- | --- | --- | --- |
| WP1 | `tests/CompleterSet.Tests.ps1` | 7 | 7 |
| WP3 | `tests/CompleterSet.Tests.ps1` | 13 | 18 |
| WP4 | `tests/CompleterSet.Tests.ps1`, `tests/CompleterRegistration.Tests.ps1` | 11 (plus 1 modified) | 12 |
| WP5 | `tests/CompleterReset.Tests.ps1` | 14 | 20 |
| WP6 | `tests/CompleterSetDrift.Tests.ps1`, `tests/CompleterReset.Tests.ps1` | 19 | 35 |
| Total | | about 64 | about 92 |

That takes the suite from 234 test cases to about 326, across ten test files, eight of which exist today.
