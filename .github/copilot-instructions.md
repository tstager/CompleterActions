# CompleterActions repository instructions

## Module shape

- `CompleterActions` is a PowerShell 7+ / Core-only script module rooted at `CompleterActions.psd1` and `CompleterActions.psm1`.
- The public surface is exactly six functions: `Get-CompleterRegistration`, `Import-CompleterScript`, `Register-CompleterRegistration`, `Test-CompleterRegistration`, `Test-CompleterScript`, and `Unregister-CompleterRegistration`.
- `CompleterActions.psm1` dot-sources `src\Private\*.ps1` and `src\Public\*.ps1`, initializes module state with `Get-CompleterActionState`, and exports the public function filenames.
- The manifest explicitly exports the same six functions and loads `CompleterActions.Format.ps1xml`.

## Domain behavior

- The module manages PowerShell argument completer registrations for native commands and command parameters.
- `Import-CompleterScript` converts standalone completer scripts into `Register-CompleterRegistration -InputObject` payloads without mutating the live runtime during import. The strict tier (default) validates the script against a closed grammar first; `-Trusted` dot-sources it as-is inside the same capture module and marks the records `Trusted`.
- `Test-CompleterScript` runs the strict grammar without executing the script and returns `CompleterActions.CompleterScriptFinding` records (line, column, construct, message, hint); `Import-CompleterScript` builds its strict-tier error text from the same findings. `Test-CompleterRegistration` runs `TabExpansion2` against a registered target and returns `CompleterActions.CompletionMatch` records; it must never alter PSReadLine state.
- Managed registrations are tracked in module-owned state; runtime-only registrations can also be discovered from the live session.
- Runtime discovery and removal rely on PowerShell runtime internals, not a public API. Keep any related changes aligned across discovery, reconciliation, and tests.
- `Get-CompleterRegistration` merges managed and discovered registrations, prefers managed records for duplicate targets only while they still match the live runtime value (otherwise records carry a `Stale`/`Conflicted` `State`), and supports `SupportsPaging`.
- `Register-CompleterRegistration` updates each target transactionally and restores the previous runtime and managed state when a write fails; a stale managed record requires `-Force`, and `Unregister-CompleterRegistration` requires `-AllowUnmanaged` before removing a live value that replaced a managed registration.
- Public commands support array inputs; `Get-*` supports pipeline-by-property-name target lookup; `Import-*` supports path input; `Register-*` and `Unregister-*` support `InputObject` pipeline input where appropriate.
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
