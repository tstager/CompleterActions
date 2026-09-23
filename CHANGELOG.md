# Changelog

All notable changes to CompleterActions are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-09-23

The stable 2.0.0 release. Same code as 2.0.0-rc1, promoted after the candidate
soaked in a profile and in the PS_Completers conformance CI without a defect,
per roadmap decision 6. The 2.0.0-rc1 section below is the full record of the
breaking surface; `about_CompleterActions_Migration` walks through the move
from 1.x.

## [2.0.0-rc1] - 2026-09-21

The 2.0.0 breaking surface. Every incompatible change of the 2.x line lands
here at once, with aliases for the old names, so there is one migration to
make; `about_CompleterActions_Migration` walks through it with before and
after samples.

### Changed

- **Renamed commands** (breaking). The three commands with the
  `CompleterRegistration` noun are renamed; the old names stay as exported
  aliases until 3.0.

  | 1.x | 2.0 |
  | --- | --- |
  | `Get-CompleterRegistration` | `Get-Completer` |
  | `Register-CompleterRegistration` | `Register-Completer` |
  | `Unregister-CompleterRegistration` | `Unregister-Completer` |

  Each alias points at an exported legacy wrapper
  (`Get-CompleterRegistrationLegacy`, `Register-CompleterRegistrationLegacy`,
  `Unregister-CompleterRegistrationLegacy`) that forwards every parameter,
  pipeline input, `-WhatIf`, and `-Confirm` to the new command and shows the
  new command's help. The wrappers are exported because an exported alias
  whose target function is not exported fails at the call site, so
  `Get-Command -Module CompleterActions` lists eleven functions and three
  aliases. The first call to each old name in a process writes one warning,
  `<old name> is deprecated and will be removed in 3.0; use <new name>
  instead. See about_CompleterActions_Migration.`; later calls are silent.
- **Explicit target contract** (breaking). Keys are output-only identifiers.
  The typed `-Key` parameter is removed from `Get-Completer`,
  `Unregister-Completer`, and `Test-CompleterRegistration`, and the
  inference that read a key's shape (no colon for a native command,
  `Command:Parameter` for a parameter completer, a path separator after the
  last colon for a native command path) is deleted together with its helper.
  A target is named with `-CommandName` plus `-Native` or `-ParameterName`,
  or described by an input object that carries `CommandName` with
  `Native`/`IsNative` or `ParameterName`, or a `Key`, `RegistrationKey`, or
  `RuntimeKey` together with `IsNative`/`Native`. A bare key input object
  fails with `InputObject supplies the key '<key>' without an IsNative or
  Native property ... See about_CompleterActions_Migration.` Records piped
  back from `Get-Completer`, `Register-Completer -PassThru`,
  `Import-CompleterScript`, `Import-CompleterSet`, and
  `Test-CompleterRegistration` always carry `IsNative` and still round-trip;
  `Get-Completer` gained an `InputObject` parameter set for them, matching
  `Unregister-Completer` and `Test-CompleterRegistration`.
  `Unregister-Completer`'s default parameter set is `CommandParameter`, so a
  call without arguments reports the missing `CommandName` and
  `ParameterName`. Completer set files never carried keys, so a set exported
  by 2.0.0-preview3 imports unchanged.

  ```powershell
  # 1.x
  Get-CompleterRegistration -Key 'git:checkout', 'git:branch'
  Unregister-CompleterRegistration -Key 'git'
  # 2.0
  Get-Completer -CommandName git -ParameterName checkout, branch
  Unregister-Completer -CommandName git -Native
  ```

- **One `-State` filter** (breaking). `-ManagedOnly` and `-DiscoveredOnly`
  are removed from `Get-Completer` and replaced by `-State`, a
  `CompleterState[]` accepting `Active`, `Stale`, `Conflicted`, `Pending`,
  `Failed`, and `Discovered` with tab completion; a scalar binds, several
  values return the union, and no `-State` returns everything. The legacy
  `Get-CompleterRegistration` alias keeps both switches and translates
  `-ManagedOnly` to `-State Active, Pending, Failed, Stale` and
  `-DiscoveredOnly` to `-State Discovered, Conflicted`; it rejects either
  switch combined with `-State`. `Export-CompleterSet` uses the same managed
  state list internally.
- **A runtime-only registration now reports `State` `Discovered`, not
  `Active`** (breaking). `Active` is reserved for managed records whose
  stored script is the live runtime value; a live value that no managed
  record describes is `Discovered`. A filter such as
  `Where-Object State -eq Active` that relied on runtime-only registrations
  being `Active` now returns managed records only; use
  `-State Active, Discovered` for the old meaning. `Source`, `IsManaged`, and
  `IsRuntimeRegistered` are unchanged. `Unregister-Completer -PassThru
  -AllowUnmanaged` returns the removed runtime-only record as `Discovered`.
- **A replaced target yields two records** (breaking). `Get-Completer`
  computes every candidate's state once and `-State` selects among them, so
  a managed target that was replaced outside the module returns both its
  `Stale` managed record and the `Conflicted` live value from an unfiltered
  call (1.x returned only the `Conflicted` record unless `-ManagedOnly`
  revealed the `Stale` one). The same holds for a `Failed` managed record
  whose target was re-registered externally. `Key` is unique in the output
  except for such replaced targets.
- **Promised sort order.** `Get-Completer` sorts by `CompleterType` (native
  first), `CommandName`, and `ParameterName` before `-Skip` and `-First` are
  applied, so paging across several calls neither skips nor duplicates a
  record while unrelated targets change between pages; only a target that
  sorts before the current window can shift it. 1.x returned insertion
  order.
- **Typed output** (breaking). Registration, import, finding, and
  completion-match records are PowerShell classes (`CompleterRegistration`,
  `ImportedCompleterRegistration`, `CompleterScriptFinding`,
  `CompletionMatch`) backed by the `CompleterState` and `CompleterType`
  enums, and every command declares its record type in `OutputType`. A class
  cannot carry a dotted name, so each keeps a bare class name and inserts the
  existing dotted `PSTypeName` (`CompleterActions.CompleterRegistration` and
  so on) at the front of its `PSTypeNames` in the constructor; the dotted
  name remains the contract for format views and type checks, and the
  classes are private to the module's session state, so `-is
  [CompleterRegistration]` only resolves inside the module. Property names
  and order are unchanged, except that `CompletionMatch` gained `IsNative`
  after `ParameterName` so a native match resolves as a target when it is
  piped back. `State` and `CompleterType` are enum values that
  still compare equal to their names (`-eq 'Failed'`, `-in Pending, Failed`).
  String properties that were `$null` on the 1.x records are `''` on the
  class records: `ParameterName` on a native record, `ScriptPath` and
  `LoadError` on a record without a script, and `ToolTip` on a completion
  match; a `-eq $null` test no longer matches. `State` and `CompleterType`
  serialize as integers through `ConvertTo-Json` and `Export-Clixml`, where
  1.x wrote the name strings; pass `-EnumsAsStrings` or store
  `[string] $_.State` when persisting records (`ConvertTo-Csv` and the format
  views still write the names). Across a remoting or job
  boundary the records arrive as
  `Deserialized.CompleterActions.CompleterRegistration` with `State` as a
  plain string, as in 1.x.
- The `InputObject` parameter of `Get-Completer`, `Register-Completer`,
  `Unregister-Completer`, `Test-CompleterRegistration`, and
  `Export-CompleterSet` is typed `[object[]]` instead of `[psobject[]]`, so a
  piped class record binds by value instead of falling through to
  property-name binding. Because every piped object binds there,
  `Get-Completer` no longer declares property-name binding on `-CommandName`,
  `-ParameterName`, and `-Native`; an input object describes one target, and
  one whose `CommandName` or `ParameterName` holds several values is rejected
  with an error instead of being joined into one name (pass arrays to
  `-CommandName` and `-ParameterName` for several targets).
- The source module loads `src\Classes` before `src\Private` and
  `src\Public`, as one script block, and the packaged module defines the
  classes before the first function.

### Documentation

- New `about_CompleterActions_Migration` topic: the rename table and alias
  mechanics, the explicit target contract, the `-State` consolidation with
  the `Discovered` change, the sort order, the typed records with the
  class-versus-`PSTypeName` note and the deserialization caveat, and a
  checklist for a profile. The deprecation warning and the bare-key error
  name it.
- README, `about_Import_Completers`, `about_Completer_Sets`, the command help,
  and `.github/copilot-instructions.md` use the new names and `-State`.

## [2.0.0-preview3] - 2026-09-12

Fixes for the five findings in `docs/code-review-2026-09-12.md`.

### Fixed

- The strict import grammar rejects a scope-qualified definition of an
  allow-listed command. `function script:Get-Variable`, and the `local:`,
  `global:`, `private:`, and module-qualified forms, passed validation because
  the definition's name kept its qualifier, and the body ran at import time
  when the allow-listed `Get-Variable` call executed. Definitions are now
  compared by their unqualified name; command calls stay exact-match, so a
  qualified call is still rejected as an unsupported top-level command (R1).
- Imported completer blocks keep their source file. The capture module rebuilt
  each block from its text, which dropped the file association, so
  `$PSScriptRoot` and `$PSCommandPath` were empty inside an imported completer
  and a location-dependent completer failed once registered. The original
  block is now rebound to the capture module, under the strict, trusted, and
  lazy paths alike (R2).
- A completer registered with `Register-ArgumentCompleter -ParameterName`
  alone, without `-CommandName`, no longer makes `Get-CompleterRegistration`
  throw for the whole session. The engine stores that shape under the bare
  parameter name; discovery skips it with a verbose message, key lookups never
  match it, and the registration snapshot leaves it out, so it is never
  resolved as a native target of the same name (R3).
- A lazily loaded script that registers the same target more than once now
  loads the last definition, as `Register-ArgumentCompleter` does when the
  script is dot-sourced; the first definition used to win on the first press
  and stay in place (R4).
- `Export-CompleterSet` refuses a strict entry that lists only some of the
  targets its script registers, naming the missing targets and writing
  nothing, because `Import-CompleterSet` compares a strict entry's `Targets`
  with the parsed script and rejects the mismatch. Trusted entries are written
  with the targets the records carry (R5).

### Documentation

- `about_Import_Completers` names scope-qualified shadows of allow-listed
  commands as findings and states that imported blocks keep `$PSScriptRoot`
  and `$PSCommandPath`; `about_Completer_Sets` covers last-wins lazy loading
  and the strict-entry export rule; `Get-CompleterRegistration` help and the
  README describe how parameter-only registrations are skipped.
- `.github/copilot-instructions.md` lists the eight public commands, lazy
  registration with the `Pending` and `Failed` states, completer sets, and the
  own-process rule for running the tests.

## [2.0.0-preview2] - 2026-09-11

### Fixed

- Completer set files are portable across platforms. `Export-CompleterSet`
  writes relative paths with forward slashes, and `Import-CompleterSet`
  accepts either separator, so a set exported on Windows imports on Linux
  and macOS instead of failing every entry with a missing file.

## [2.0.0-preview1] - 2026-09-11

### Added

- Lazy registration. `Register-CompleterRegistration -Path` or `-LiteralPath`
  with `-Lazy` registers a completer script without running it: the runtime
  entry for each target is a stub that imports the script through
  `Import-CompleterScript` on the first tab press, replaces itself with the
  real completer, and delegates that first call to it. Under the default strict
  tier the targets are read from the script's literal
  `Register-ArgumentCompleter` arguments, so the file is parsed but never
  executed at registration time; `-Trusted` selects the trusted tier for the
  load and requires the targets to be named with `-CommandName` and `-Native`
  or `-ParameterName`. A script that registers several targets is executed once
  and every Pending sibling is swapped from the same import.
- `Pending` and `Failed` registration states. A lazy record reports `Pending`
  until its script loads and `Active` afterwards. If the load fails, the tab
  press returns no completions, the runtime entry is removed so the completion
  engine's default completion applies exactly as with no completer registered,
  and the record moves to `Failed` with the message in `LoadError`; nothing is
  written to the host. `Register-CompleterRegistration -Force` retries the
  load. `Get-CompleterRegistration` returns both states by default and with
  `-ManagedOnly`; `Unregister-CompleterRegistration` removes a Pending stub with
  its record and a Failed record on its own.
- `ScriptPath`, `Trusted`, and `LoadError` properties on
  `CompleterActions.CompleterRegistration` records. Registrations made from
  `Import-CompleterScript` records carry the script's path and tier too, so an
  eager session exposes the same file information as a lazy one.
- Lazy loading never hooks PSReadLine key handlers, replaces `TabExpansion2`,
  or changes PSReadLine options; the tests snapshot
  `Get-PSReadLineKeyHandler` around registration, first tab, and removal.
- `Import-CompleterSet`. Reads a completer set, a `.psd1` data file that lists
  completer scripts with a per-entry trust tier and their targets, through
  `Import-PowerShellDataFile` so the set itself can never run code. Every
  entry is validated before anything registers: the file exists and is a
  `.ps1`, `Trusted` entries declare their `Targets`, strict entries expose
  literal targets that are derived from the parsed script and compared
  against any the entry declares, no target is listed by two entries, and
  without `-Force` no target already carries a managed or runtime
  registration for a different completer, the same rules
  `Register-CompleterRegistration` applies. One terminating error lists every
  problem;
  `-SkipInvalid` writes them as warnings and registers the valid entries.
  Paths that are not fully qualified, drive-relative ones included, resolve
  against the set file's directory, `-Force` passes through to the
  registration, and the command returns the registration records.
- `Export-CompleterSet`. Writes a completer set from registration records
  piped from `Get-CompleterRegistration` or `Import-CompleterScript`, or from
  every managed registration that records a `ScriptPath`, one entry per
  script with its `Trusted` flag and targets, and script paths relative to the
  set file when they share a root.
- `tools/Measure-CompleterStartup.ps1`. Startup benchmark that times the eager
  `Get-ChildItem | Import-CompleterScript | Register-CompleterRegistration`
  pipeline against `Import-CompleterSet` of a set exported from the same
  scripts, each sample in a fresh `pwsh -NoProfile` process, and reports the
  median, minimum, maximum, and ratio per leg. On the 169-script, 355-target
  repository with five samples per leg: eager median 7063.3 ms, lazy median
  1315.5 ms, ratio 0.19, under the roadmap target of 0.25; against the
  highest eager median recorded on this machine, 7427.7 ms, the same lazy
  figure is 0.18. The remaining lazy cost is one parse per strict script,
  about a third of the leg, plus record creation and the runtime and managed
  writes.

### Changed

- The default table view for registration records adds `ScriptPath` and
  `LoadError` columns after `State`.
- `Import-CompleterScript` runs its strict conformance gate through
  `Assert-CompleterScriptConformance`. A lazily registered strict script goes
  through that gate when it loads rather than at registration, so
  `Register-CompleterRegistration -Lazy` and `Import-CompleterSet` each cost
  one parse per strict script with no conformance walk; a script that fails
  the grammar moves to `Failed` on its first tab press with the findings in
  `LoadError`.
- `Import-CompleterSet` registers each entry from the targets its validation
  derived instead of calling `Register-CompleterRegistration -Lazy`, which
  parsed every strict script a second time. Both paths write registrations
  through one shared transactional helper, so conflict rules, record shapes,
  and rollback are unchanged. On the 169-script repository the lazy startup
  median dropped from 2566.2 ms to 1806.1 ms.
- `Import-CompleterSet` registers a set as one batch. Validation and
  registration share one snapshot of the managed table and the runtime
  completer dictionaries, each entry's targets are reconciled in one pass
  against that snapshot instead of once per target during validation and
  again during registration, and the whole set is written through one call
  that rolls back every runtime and managed change of the set, replaced
  registrations included, if any write fails. `Register-CompleterRegistration`
  resolves conflicts and writes through the same helpers one target at a time,
  so each target of a call is still its own transaction: a failed write or a
  conflict on a later target leaves the earlier targets of that call
  registered, and a target repeated within one call is resolved against what
  the earlier occurrence wrote, exactly as before. On the 169-script
  repository the lazy startup median dropped from 1806.1 ms to 1315.5 ms.
- `Find-RuntimeCompleterRegistration -Key` compares the stored dictionary
  keys directly instead of normalizing every key on each lookup, which removed
  a quadratic cost from registering many targets: the eager 169-script import
  dropped from about 9.0 s to 6.6 s per fresh `pwsh -NoProfile` session.

### Documentation

- `about_Completer_Sets` describes the set file schema, the trust tier per
  entry, up-front validation, the `Pending` and `Failed` lifecycle of lazily
  loaded completers, and the PSReadLine neutrality promise.
- README command map, examples, and architecture notes cover the two set
  commands, and a lazy-loading section explains the set format and lifecycle.

## [1.4.0] - 2026-09-10

### Added

- `Test-CompleterScript`. Runs the strict import grammar over completer scripts
  without executing them and returns one
  `CompleterActions.CompleterScriptFinding` per unsupported construct, with
  `Path`, `Line`, `Column`, `Severity`, `Construct`, `Message`, and a `Hint`
  that says how to fix it. A conforming script produces no output, so
  `Get-ChildItem | Test-CompleterScript` doubles as a conformance test for a
  completer repository.
- `Test-CompleterRegistration`. Runs `TabExpansion2` for an `-InputText`
  against a registered target and returns `CompleterActions.CompletionMatch`
  records carrying `CompletionText`, `ListItemText`, `ResultType`, and
  `ToolTip`, so completion behaviour can be asserted on instead of checked by
  hand. Targets follow the `Get-CompleterRegistration` contract, including
  piped registration records, and exactly one target must resolve per call
  because one input text invokes one completer; `-CursorPosition` defaults to
  the end of the input. The command never touches PSReadLine.
- `Import-CompleterScript -Trusted`. Skips the grammar and dot-sources the
  script as-is inside the same capture module, for completer repositories you
  own. Strict stays the default. Imported records carry a `Trusted` property
  that records the tier.
- Default views for findings (a list grouped by script path) and completion
  matches (a table grouped by target key).

### Changed

- `Import-CompleterScript` reports every strict-grammar finding, each with its
  line, column, construct, and hint, instead of the first one only. The error
  text is built from the same findings `Test-CompleterScript` returns, so the
  two cannot drift.
- A single-element `@('name')` array expression is accepted for `-CommandName`
  and `-ParameterName`; the previous shape check rejected it.

### Documentation

- `about_Import_Completers` rewritten around the two tiers, with the three
  import-safe shapes as worked examples, `Test-CompleterScript` as the
  conformance step, and `Test-CompleterRegistration` as the verification step.
- README command map, examples, and architecture notes cover the two new
  commands and the trusted switch.

## [1.3.0] - 2026-09-09

### Added

- Capability probe at import. `Assert-CompleterRuntimeCapability` resolves every
  reflected engine member once and throws a single terminating error naming the
  running PowerShell version and the members that could not be resolved, instead
  of failing deep inside a later `Get` or `Register` call.
- Import bootstrap in the packaged module. The built `.psm1` contained function
  definitions only, so installed copies never ran the `Get-CompleterActionState`
  initialization; the import-time work now lives in `src/Bootstrap.ps1` and the
  build appends it to the package.
- Continuous integration on `windows-latest` and `ubuntu-latest` across
  PowerShell 7.4 LTS, 7.5, 7.6, and preview, running the build, the analyzer, and
  the Pester suite on each leg.
- Tag-triggered release workflow. A pushed `v` tag runs `release_check`, the
  build, and the tests, publishes to the PowerShell Gallery using the
  `GALLERY_API_KEY` repository secret, and creates the GitHub release with the
  matching section of this file as its notes.
- This changelog.

### Fixed

- The build copied the generated MAML help under a lowercase file name that only
  resolves on a case-insensitive filesystem, so `Invoke-Build -Task build` failed
  on Linux. Only the source path casing changed; the packaged help file name is
  unchanged.

### Documentation

- 2.0 roadmap in `docs/roadmap-2.0.md`, covering four milestones from the 1.2.0
  baseline and the design decisions locked on 2026-09-08.
- README gains a CI badge and a `Releasing` section describing the tag-triggered
  flow.

## [1.2.0] - 2026-09-09

Hardening release covering the findings in `docs/code-review-2026-09-08.md`.

### Security

- Completer script validation rejects executable top-level constructs and
  `#requires -Modules` / `-Assembly`, so importing a script can no longer load
  types or run code as a side effect of validation (CA-001).

### Added

- The packaged `build/` output is tracked, and a test fails when it drifts from
  the sources it was generated from.

### Fixed

- Registration updates each target transactionally and restores the previous
  runtime and managed state when a write fails (CA-002).
- Managed records reconcile against the live runtime, so an externally replaced
  registration reports `Stale` or `Conflicted` instead of being silently
  preferred or removed (CA-003).
- Drive-qualified path keys classify as native completer targets, and the dead
  drive-letter regex was removed from key classification (CA-004).
- The build derives the module name and every constructed path portably and
  enumerates only source folders that exist (CA-005).
- The manifest tests no longer invoke the build, so a full Pester run leaves the
  working tree unchanged (CA-007).
- The hard-coded manifest version assertion is replaced by a release-policy test
  comparing the source manifest, the built manifest, and the highest local tag
  (CA-008).

### Documentation

- Key-shape help aligned with the last-colon separator rule.
- Added the code review document `docs/code-review-2026-09-08.md`.

## [1.1.2] - 2026-05-04

### Added

- Module icon assets under `src/Assets/` and an `IconUri` in the manifest, which
  the build now propagates into the packaged manifest.

### Changed

- README rewritten with a badge row and a tighter layout.
- Corrected the LICENSE text.
- `Publish_build` no longer imports SecretManagement and PSResourceGet
  explicitly.

## [1.1.1] - 2026-04-28

### Changed

- Expanded the manifest `Description` from `Interacts with PowerShell completers`
  to the two-sentence description the module ships today.
- `Publish_build` reads the gallery key from `$env:GalleryAPI` instead of
  prompting to unlock a SecretStore vault.

Version 1.1.0 (commit
[`05ebec3`](https://github.com/tstager/CompleterActions/commit/05ebec3)) is the
baseline for this file; earlier history is not documented.

[Unreleased]: https://github.com/tstager/CompleterActions/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/tstager/CompleterActions/compare/v2.0.0-rc1...v2.0.0
[2.0.0-rc1]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview3...v2.0.0-rc1
[2.0.0-preview3]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview2...v2.0.0-preview3
[2.0.0-preview2]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview1...v2.0.0-preview2
[2.0.0-preview1]: https://github.com/tstager/CompleterActions/compare/v1.4.0...v2.0.0-preview1
[1.4.0]: https://github.com/tstager/CompleterActions/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/tstager/CompleterActions/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/tstager/CompleterActions/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/tstager/CompleterActions/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/tstager/CompleterActions/compare/05ebec3...v1.1.1
