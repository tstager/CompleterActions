# CompleterActions main-branch code review

Date: 2026-09-12 (UTC)  
Reviewed commit: `73e68cf811d1ad669bc17b6e2ea136675d1afff8`  
Branch: `main`, verified equal to `origin-main/main` after `git fetch origin-main main`  
Release: `2.0.0-preview2` / tag `v2.0.0-preview2`  
Mode: review only; no implementation changes

## Summary

**Five verified findings: one High (P1), four Medium (P2).** The strict importer still has an import-time execution bypass through scope-qualified function names. The other findings affect script-location preservation, discovery alongside legitimate global parameter completers, duplicate lazy registrations, and set round-tripping.

The existing safety net is green: **168 Pester tests passed, zero failed or skipped; source/test lint reported zero findings; an isolated build completed with zero errors or warnings.** All five defects reproduced against the source module, the tracked package, and a freshly rebuilt package. Passing existing tests therefore does not cover these cases.

| ID | Priority | Finding |
| --- | --- | --- |
| R1 | High / P1 | Scope-qualified function overrides bypass strict import validation |
| R2 | Medium / P2 | Capturing a script block as text loses its source-file location |
| R3 | Medium / P2 | One global parameter completer breaks unfiltered runtime discovery |
| R4 | Medium / P2 | Lazy loading selects the first duplicate definition instead of the last |
| R5 | Medium / P2 | Export accepts a strict target subset that set import rejects |

Address R1 before treating the strict tier as an import-time execution boundary. Address R2–R5 before the stable 2.0 release.

## Context and method

- Loaded AI Memory context for workspace `completeractions`, including previous review/remediation history, release procedures, lazy-loading/set work, and PSReadLine neutrality requirements. Historical memories were treated as context, not proof of the current implementation.
- Read repository instructions, README, the prior review, all eight public commands, and the relevant importer/AST, lazy-loading, set, registration transaction, reconciliation, target, and runtime-discovery helpers. Reviewed CI/release workflows and the build script; examined importer/lazy regression coverage and ran all six test files.
- The repository instructions still describe six public commands; the current manifest, README, and runtime expose eight. This documentation lag is not counted among the five functional findings.
- Attempted parallel specialist review using the configured Terra agents. The launcher rejected their model name as ambiguous before starting any child. **No subagent ran, and no Astra/Sol provider was used.** The primary reviewer performed the review and validation directly.
- Used fresh `pwsh -NoProfile` processes. Live runtime mutations were confined to these disposable child sessions. Built a `git archive HEAD` copy under a temporary review directory, preserving the required `CompleterActions` directory name, rather than regenerating tracked artifacts in place.
- Retained the complete diagnostic probe in Appendix A. An initial combined run was contaminated by the scope-changing R1 probe running first; that probe was moved last. The expected R2 completion exception was then captured so the remaining checks could finish. The complete corrected probe ran successfully against all three module forms, followed by a fresh full-suite/lint validation. No conclusions below rely on the contaminated run.

## Findings

### R1 — High / P1 — Scope-qualified function overrides bypass strict validation

**Location:** [`src/Private/Test-CompleterScriptAst.ps1:676–688`](../src/Private/Test-CompleterScriptAst.ps1#L676); function definitions are accepted at [454–457](../src/Private/Test-CompleterScriptAst.ps1#L454).

The override check compares `FunctionDefinitionAst.Name` directly with the allowlisted bare command names. PowerShell retains a scope prefix in that name: `script:Get-Variable` is not equal to `Get-Variable`. The function body is exempt from the top-level grammar, but a subsequent allowlisted `Get-Variable` call executes that body **during import**, before any completion request.

Accepted script:

```powershell
function script:Get-Variable {
    [Environment]::SetEnvironmentVariable('CA_REVIEW_SCOPED_PROBE', 'executed', 'Process')
}
Get-Variable -Name Anything
Register-ArgumentCompleter -CommandName ca-review-scoped -Native -ScriptBlock { 'safe-body' }
```

Observed with the default, non-Trusted tier:

```text
SCOPED: findings=0 imported=1 sideEffect=executed runtime=0
```

`Test-CompleterScript` reports no findings, and `Import-CompleterScript` executes the side effect and returns a registration. The absence of a live registration does not make that import safe. This is a specific gap in the newer closed grammar, not a claim that the original broad expression-AST defect remains unfixed. It also does not depend on executing arbitrary code inside a completer body: the marker changes during import itself.

**Recommendation:** validate function scope and effective command name, not only the raw AST name. Reject scope-qualified definitions that can replace allowed import commands or escape the intended capture scope. Extend adversarial tests to `script:`, `local:`, and `global:` names, ensuring both diagnostic rejection and absence of import-time effects. The harmless process-local environment marker used here should remain a negative regression probe.

### R2 — Medium / P2 — Captured blocks lose their source-file location

**Location:** [`src/Private/Import-CompleterScriptDefinition.ps1:64`](../src/Private/Import-CompleterScriptDefinition.ps1#L64).

The capture function calls `NewScriptBlock($ScriptBlock.ToString())`. Reconstructing the block from text loses its source-file association. Binding the reconstructed block to the capture module preserves helper lookup but does not preserve `$PSScriptRoot` inside the completer.

Minimal conforming script:

```powershell
Register-ArgumentCompleter -CommandName ca-review-location -Native -ScriptBlock { $PSScriptRoot }
```

The same script produces its actual directory when dot-sourced normally. After `Import-CompleterScript | Register-CompleterRegistration`, direct invocation of the captured block returns an empty string and real completion fails:

```text
LOCATION: directHasExpected=True importedHasExpected=False directInvocation=''
Exception calling "CompleteInput" ... value of argument "completionText" is null
```

This breaks location-dependent completer logic and can turn a working standalone completer into a registered but unusable one. The recorded `SourcePath`/`ScriptPath` does not repair automatic variables inside the reconstructed block. The common capture helper also serves trusted and lazy imports; the runtime reproduction here used the strict eager path.

**Recommendation:** preserve the original block's source/AST metadata while binding the required module context, rather than round-tripping through text. Add direct-versus-imported real-completion tests for `$PSScriptRoot`, and check `$PSCommandPath` as a related regression case. Preserve existing helper-function and namespace behavior when making that change.

### R3 — Medium / P2 — Global parameter completers break discovery

**Location:** [`src/Private/Find-RuntimeCompleterRegistration.ps1:96–101`](../src/Private/Find-RuntimeCompleterRegistration.ps1#L96), calling [`Resolve-CompleterTarget.ps1:103–110`](../src/Private/Resolve-CompleterTarget.ps1#L103).

PowerShell's built-in command permits registration by parameter name without a command name. Its custom-completer dictionary then contains a parameter-only key. The unfiltered discovery path assumes every entry has the `Command:Parameter` shape and throws on this valid engine entry.

Reproduction in a fresh child session after importing CompleterActions:

```powershell
Register-ArgumentCompleter -ParameterName CAReviewGlobalParam -ScriptBlock { 'global-parameter-value' }
Get-CompleterRegistration
```

Observed:

```text
Failed to retrieve completer registrations.
Parameter completer runtime keys must use the format 'Command:Parameter'.
Received 'CAReviewGlobalParam'.
```

A legitimate registration made by a profile or another module can therefore prevent users from listing otherwise unrelated registrations. This is an existing runtime shape, not a hypothetical future reflection change.

**Recommendation:** handle the engine's parameter-only target shape explicitly in discovery and normalization, and define how the public query/removal contract represents it. A module that does not manage that target kind must at least avoid aborting discovery of every supported target. Add coexistence tests with a global parameter completer plus managed native and command-parameter registrations.

### R4 — Medium / P2 — Lazy duplicate resolution changes PowerShell semantics

**Location:** [`src/Private/Invoke-CompleterLazyStub.ps1:87–122`](../src/Private/Invoke-CompleterLazyStub.ps1#L87).

The loader chooses its own imported definition with `Select-Object -First 1`. It also installs imported definitions in forward order, changing a target to `Active` after the first one. A later definition for that key is skipped because the record is no longer `Pending`. Normal `Register-ArgumentCompleter` behavior is last registration wins.

Conforming script accepted without findings:

```powershell
Register-ArgumentCompleter -CommandName ca-review-duplicate -Native -ScriptBlock { 'first-definition' }
Register-ArgumentCompleter -CommandName ca-review-duplicate -Native -ScriptBlock { 'last-definition' }
```

Real `TabExpansion2` results:

```text
DUPLICATE: findings=0 direct=last-definition lazyFirst=first-definition lazySecond=first-definition
```

The wrong definition persists after the first tab press. This affects scripts that replace a baseline registration later in the file; lazy loading is not behaviorally equivalent to loading the script normally.

**Recommendation:** reduce captured definitions to the final definition per normalized target key before selecting the initiating target and swapping siblings. Use the same reduced collection for both operations. Test repeated targets, overlapping command-name arrays, the first press, and subsequent presses.

### R5 — Medium / P2 — Export produces a set its importer rejects

**Locations:** [`src/Public/Export-CompleterSet.ps1:144,167–179`](../src/Public/Export-CompleterSet.ps1#L144) and [`src/Private/Resolve-CompleterSetEntry.ps1:206–214`](../src/Private/Resolve-CompleterSetEntry.ps1#L206).

Strict lazy registration explicitly supports selecting a subset of a script's targets. Export serializes the supplied records' targets without checking whether they represent the whole script. Set import, however, requires exact equality between declared and derived strict targets. Consequently a valid managed record can be exported successfully but cannot be restored.

For a script declaring `ca-review-subset,ca-review-subset.exe`:

```powershell
$r = Register-CompleterRegistration -LiteralPath $scriptPath -Lazy `
    -CommandName ca-review-subset.exe -Native -PassThru
$r | Export-CompleterSet -Path $setPath
$r | Unregister-CompleterRegistration -Confirm:$false
Import-CompleterSet -LiteralPath $setPath
```

Observed:

```text
The declared Targets do not match the script.
Declared: 'ca-review-subset.exe'.
Script registers: 'ca-review-subset', 'ca-review-subset.exe'.
```

The target was deliberately removed before importing, so this is not a conflict with an existing registration. `-Force` cannot fix the schema mismatch; `-SkipInvalid` would omit the entire entry.

**Recommendation:** make export enforce the set schema before writing. Under the current exact-target contract, reject incomplete strict groups with an actionable message and leave the output untouched. If sets are intended to support restoring subsets, change and document that contract explicitly; do not silently expand the export to register targets the caller excluded. Add a round-trip test using the already-supported strict subset registration path.

## Verification results

Environment: Windows, PowerShell **7.6.6 Core**; Pester **6.1.0**; PSScriptAnalyzer **1.25.0**; InvokeBuild **5.14.23**; Microsoft.PowerShell.PlatyPS **1.0.3**.

| Check | Observed result |
| --- | --- |
| Fetch and revision comparison | `HEAD` and `origin-main/main` both `73e68cf811d1ad669bc17b6e2ea136675d1afff8` |
| Initial full Pester run | 168 passed, 0 failed, 0 skipped |
| Final full Pester rerun after isolating probes | 168 passed, 0 failed, 0 skipped; 70.25 seconds |
| Source and test lint, separate process from Pester | 0 findings; repeated in final validation |
| `Invoke-Build -Task release_check` | Tag `v2.0.0-preview2` matches manifest; 1 task, 0 errors/warnings |
| Tracked package manifest/import | Version 2.0.0, prerelease `preview2`, 8 exported commands |
| Build in isolated `git archive HEAD` copy | 3 tasks, 0 errors, 0 warnings |
| Corrected probe against source manifest | Completed; R1–R5 reproduced |
| Corrected probe against tracked package manifest | Completed; R1–R5 reproduced |
| Corrected probe against freshly rebuilt package | Completed; R1–R5 reproduced |
| Namespace control probe | Passed: imported and direct `[CompletionResult]` both worked |
| Tracked implementation diff after validation | Empty |

Core validation commands (each PowerShell invocation used `-NoProfile`):

```powershell
Invoke-Pester -Path ./tests -PassThru -Output Normal
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Build -Task release_check
Test-ModuleManifest ./build/CompleterActions/CompleterActions.psd1
# Run in the isolated archive copy, not over tracked output:
Invoke-Build -File <archive-copy>/CompleterActions/CompleterActions.build.ps1 -Task build
```

The probe's successful process exit means every diagnostic completed; it does **not** mean the reported defects passed acceptance tests. Expected exceptions were captured and their output examined. No fixes were made and no new regression tests were added to the product suite.

## Limits and qualified non-findings

- No Linux/macOS, older PowerShell, or preview-engine execution was performed in this review. CI defines broader coverage; this report does not claim those remote jobs ran or passed here.
- No Gallery publish/install, tag changes, deployment, or profile edits occurred. Remote freshness was verified at the fetch time, not continuously.
- This was a targeted correctness/safety review, not a formal security audit or exhaustive exploration of every AST form. The strict grammar is not a sandbox for code deliberately executed by completer bodies or the Trusted tier.
- The namespace-loss hypothesis did not reproduce and is not a finding. Source-file location loss did reproduce separately.
- Existing Pester coverage for transactions, stale records, lazy failure/retry, and PSReadLine neutrality passed. No speculative transaction or PSReadLine regression is reported.
- Prior review findings are not automatically reopened. R1 is a newly demonstrated scope-prefix hole in the replacement validator.

## Appendix A — Complete retained diagnostic probe

Save the following block as a disposable `.ps1` file in a writable directory and run it from the repository root in a **new process for each module path**:

```powershell
pwsh -NoProfile -File <probe.ps1> -ModulePath ./CompleterActions.psd1
pwsh -NoProfile -File <probe.ps1> -ModulePath ./build/CompleterActions/CompleterActions.psd1
# Also executed during review against the isolated fresh build's absolute manifest path.
```

The probe creates/removes its own fixture directory beside the probe file. Do not dot-source the probe in a working shell: it intentionally changes completer registrations, and the final scoped-function test can affect later commands in the same process. R1 runs last to prevent contamination. The diagnostic script used during review is preserved below; the temporary executable copy and generated fixture/build directories were removed afterward.

```powershell
param([Parameter(Mandatory)][string]$ModulePath)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath -Force
$temp = Join-Path $PSScriptRoot ('.review-fixtures-' + [guid]::NewGuid().ToString('N'))
$null = New-Item $temp -ItemType Directory
try {
    $p = Join-Path $temp 'namespace.ps1'
    @'
using namespace System.Management.Automation
Register-ArgumentCompleter -CommandName ca-review-namespace -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [CompletionResult]::new('namespace-ok', 'namespace-ok', 'ParameterValue', 'namespace-ok')
}
'@ | Set-Content -LiteralPath $p
    $f = @(Test-CompleterScript -LiteralPath $p)
    $text = 'ca-review-namespace '
    $r = @(Import-CompleterScript -LiteralPath $p)
    $r | Register-CompleterRegistration
    $imported = TabExpansion2 $text $text.Length
    $invokeError = 'none'
    try { $null = & $r[0].ScriptBlock '' $null 0 } catch { $invokeError = $_.Exception.Message }
    Unregister-CompleterRegistration -CommandName ca-review-namespace -Native -Confirm:$false
    . $p
    $direct = TabExpansion2 $text $text.Length
    Unregister-CompleterRegistration -CommandName ca-review-namespace -Native -AllowUnmanaged -Confirm:$false
    "NAMESPACE: findings=$($f.Count) directHasExpected=$($direct.CompletionMatches.CompletionText -contains 'namespace-ok') importedHasExpected=$($imported.CompletionMatches.CompletionText -contains 'namespace-ok') error=$invokeError"

    $p = Join-Path $temp 'duplicate.ps1'
    @'
Register-ArgumentCompleter -CommandName ca-review-duplicate -Native -ScriptBlock { 'first-definition' }
Register-ArgumentCompleter -CommandName ca-review-duplicate -Native -ScriptBlock { 'last-definition' }
'@ | Set-Content -LiteralPath $p
    . $p
    $text = 'ca-review-duplicate '
    $direct = TabExpansion2 $text $text.Length
    Unregister-CompleterRegistration -CommandName ca-review-duplicate -Native -AllowUnmanaged -Confirm:$false
    Register-CompleterRegistration -LiteralPath $p -Lazy
    $first = TabExpansion2 $text $text.Length
    $second = TabExpansion2 $text $text.Length
    "DUPLICATE: findings=$(@(Test-CompleterScript -LiteralPath $p).Count) direct=$($direct.CompletionMatches.CompletionText -join ',') lazyFirst=$($first.CompletionMatches.CompletionText -join ',') lazySecond=$($second.CompletionMatches.CompletionText -join ',')"

    $p = Join-Path $temp 'subset.ps1'
    @'
Register-ArgumentCompleter -CommandName ca-review-subset,ca-review-subset.exe -Native -ScriptBlock { 'subset-ok' }
'@ | Set-Content -LiteralPath $p
    $r = Register-CompleterRegistration -LiteralPath $p -Lazy -CommandName ca-review-subset.exe -Native -PassThru
    $set = Join-Path $temp 'subset.psd1'
    $r | Export-CompleterSet -Path $set
    $r | Unregister-CompleterRegistration -Confirm:$false
    try { $null = Import-CompleterSet -LiteralPath $set; 'SUBSET: imported successfully' } catch { "SUBSET: $($_.Exception.Message)" }

    $p = Join-Path $temp 'script-location.ps1'
    @'
Register-ArgumentCompleter -CommandName ca-review-location -Native -ScriptBlock { $PSScriptRoot }
'@ | Set-Content -LiteralPath $p
    . $p
    $text = 'ca-review-location '
    $direct = TabExpansion2 $text $text.Length
    Unregister-CompleterRegistration -CommandName ca-review-location -Native -AllowUnmanaged -Confirm:$false
    $r = @(Import-CompleterScript -LiteralPath $p)
    $r | Register-CompleterRegistration
    $locationError = 'none'
    try { $imported = TabExpansion2 $text $text.Length } catch { $locationError = $_.Exception.Message; $imported = $null }
    "LOCATION: directHasExpected=$($direct.CompletionMatches.CompletionText -contains $temp) importedHasExpected=$($null -ne $imported -and $imported.CompletionMatches.CompletionText -contains $temp) directInvocation='$(& $r[0].ScriptBlock)' error=$locationError"

    Register-ArgumentCompleter -ParameterName CAReviewGlobalParam -ScriptBlock { 'global-parameter-value' }
    try { $null = @(Get-CompleterRegistration); 'GLOBAL-PARAMETER: query succeeded' } catch { "GLOBAL-PARAMETER: $($_.Exception.Message)" }
    & (Get-Module CompleterActions) { $runtime = Get-CompleterRuntime; $null = $runtime.CustomArgumentCompleters.Remove('CAReviewGlobalParam') }
    $p = Join-Path $temp 'scoped-override.ps1'
    @'
function script:Get-Variable {
    [Environment]::SetEnvironmentVariable('CA_REVIEW_SCOPED_PROBE', 'executed', 'Process')
}
Get-Variable -Name Anything
Register-ArgumentCompleter -CommandName ca-review-scoped -Native -ScriptBlock { 'safe-body' }
'@ | Set-Content -LiteralPath $p
    $env:CA_REVIEW_SCOPED_PROBE = $null
    $f = @(Test-CompleterScript -LiteralPath $p)
    $r = @(Import-CompleterScript -LiteralPath $p)
    "SCOPED: findings=$($f.Count) imported=$($r.Count) sideEffect=$env:CA_REVIEW_SCOPED_PROBE runtime=$(@(Get-CompleterRegistration -CommandName ca-review-scoped -Native).Count)"
} finally {
    $env:CA_REVIEW_SCOPED_PROBE = $null
    Remove-Item -LiteralPath $temp -Recurse -Force
}
```
