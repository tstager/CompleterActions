# CompleterActions repository instructions

## Module shape

- `CompleterActions` is a PowerShell 7+ / Core-only script module rooted at `CompleterActions.psd1` and `CompleterActions.psm1`.
- The public surface is exactly three functions: `Get-CompleterRegistration`, `Register-CompleterRegistration`, and `Unregister-CompleterRegistration`.
- `CompleterActions.psm1` dot-sources `src\Private\*.ps1` and `src\Public\*.ps1`, initializes module state with `Get-CompleterActionState`, and exports the public function filenames.
- The manifest explicitly exports the same three functions and loads `CompleterActions.Format.ps1xml`.

## Domain behavior

- The module manages PowerShell argument completer registrations for native commands and command parameters.
- Managed registrations are tracked in module-owned state; runtime-only registrations can also be discovered from the live session.
- Runtime discovery and removal rely on PowerShell runtime internals, not a public API. Keep any related changes aligned across discovery, reconciliation, and tests.
- `Get-CompleterRegistration` merges managed and discovered registrations, prefers managed records for duplicate targets, and supports `SupportsPaging`.
- Public commands support array inputs; `Get-*` supports pipeline-by-property-name target lookup; `Register-*` and `Unregister-*` support `InputObject` pipeline input where appropriate.
- `Register-CompleterRegistration` and `Unregister-CompleterRegistration` are state-changing commands with `ShouldProcess` semantics.

## Implementation conventions

- Keep public functions in `src\Public` and helpers in `src\Private`; exports are filename-driven.
- Preserve the module's normalized registration contracts and object-oriented outputs (`CompleterActions.CompleterRegistration`, runtime wrapper/state helper objects).
- Prefer explicit parameter typing, validation, actionable errors, and PowerShell-friendly pipeline behavior over ad hoc convenience logic.
- When touching completer behavior, validate the real registered runtime path, not just helper functions in isolation.

## Build, test, and lint

- Build from the repo root with `Invoke-Build -Task .` or `Invoke-Build -Task build`; clean with `Invoke-Build -Task clean`.
- The build packages the module into `build\CompleterActions`, copies the format file, and emits external help into `build\CompleterActions\en-US`.
- Tests run with `Invoke-Pester`; use `Invoke-Pester -Path .\tests\CompleterActions.Tests.ps1` for the public command suite.
- Lint with `Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` and the same command for `.\tests`.
- Tests cover manifest/export alignment, module state bootstrap, runtime-internal completer discovery/removal, public command behavior, and real completion behavior via `TabExpansion2`.
