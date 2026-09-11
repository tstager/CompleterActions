# Changelog

All notable changes to CompleterActions are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/tstager/CompleterActions/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/tstager/CompleterActions/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/tstager/CompleterActions/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/tstager/CompleterActions/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/tstager/CompleterActions/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/tstager/CompleterActions/compare/05ebec3...v1.1.1
