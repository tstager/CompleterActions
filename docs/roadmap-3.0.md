# CompleterActions 3.0 Roadmap

Drafted: 2026-09-23
Baseline: 2.0.0, release commit `b2de0be`, tag v2.0.0
Live page: https://claude.ai/artifact/3w1YVcGxbpGYLWmaMCF1R1
Status (2026-09-23): drafted; milestone 0 done the same day, nothing else started.

| Milestone | Version | Status |
| --- | --- | --- |
| 0 Promote the candidate | 2.0.0 | Shipped 2026-09-23, tag v2.0.0, from the rc1 code |
| 1 Faster imports and recovery | 2.1.0 | Planned, additive |
| 2 Authoring and distribution | 2.2.0 | Planned, additive |
| 3 Compiled core and the engine boundary | 3.0.0-rc1, then 3.0.0 | Planned, breaking |

Three milestones from the 2.0.0 baseline to the next major release. The first two ship on the 2.x line and carry the recommendations that came out of the 2.0 retrospective. The breaking surface is deliberately small: it removes what 2.0 promised to remove, raises the engine floor to what CI has always tested, and moves the engine boundary into typed code.

## Where 2.0 leaves us

| Area | State |
| --- | --- |
| Surface | 8 commands, plus 3 legacy wrappers and 3 aliases promised for removal in 3.0 |
| Records | PowerShell classes with dotted PSTypeNames; `-is [CompleterRegistration]` resolves only inside the module |
| Engine access | Reflection into `EngineIntrinsics._context` and the `CustomArgumentCompleters` and `NativeArgumentCompleters` dictionaries, guarded by an import-time capability probe |
| Upstream | PowerShell/PowerShell #25800 asks for `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter`; PR #26680 is open and targets 7.7 with a possible 7.6.x backport; commented 2026-09-23 with the module's field report and a test offer |
| Startup | Lazy import of the 169-script set at 0.19 of the eager time; the set is still parsed once per script on every import |
| Recovery | A Failed lazy record has no re-arm path short of re-importing the set |
| Tests | 234 Pester cases across eight files, eight CI legs (Windows and Ubuntu, 7.4 to preview), PSScriptAnalyzer clean |
| Support statement | Manifest says PowerShell 7.0; CI has only ever run 7.4 and later |

Public commands: 8 (11 exported functions). Private helpers: 45. Source: about 6,000 lines.

## Milestone 0: Promote the candidate (2.0.0)

**Shipped 2026-09-23 as v2.0.0** (release commit b2de0be) from the rc1 code after the soak passed. Everything below builds on stable 2.0.0.

## Milestone 1: Faster imports and recovery (2.1.0, additive)

The two performance levers left after milestone 3 of the 2.0 roadmap, plus the one operational gap the soak has shown.

- **Content hash in the set file** (perf). `Export-CompleterSet` writes a `Hash` per entry alongside the targets it already records. `Import-CompleterSet` hashes each file and skips the parse when the hash matches, so the static checks (targets, trust, conflicts) come from the set and only a changed file is parsed. A set without hashes imports exactly as today.
- **Bulk registration path** (perf). One internal call registers every entry of a set, taking the managed-table lock and the runtime snapshot once instead of once per target. The per-target transaction and rollback stay for `Register-Completer`.
- **Reset-Completer** (feature). Returns a `Failed` or `Active` lazy record to `Pending` so a fixed script loads on the next tab press, without re-importing the set. Accepts the same target contract and pipeline input as `Unregister-Completer`.
- **Test-CompleterSet** (feature). Reports drift between a set file and the scripts on disk: entries whose file is missing, whose hash changed, whose targets no longer match the script, and scripts in the folder that the set does not list. Returns findings in the `CompleterScriptFinding` shape. Replaces the hand-written drift gate in the PS_Completers repo.
- **Startup benchmark, second edition** (perf). Same 169-script method as 2.0; the number to beat is the 2.0.0 lazy import time.

Exit criteria:

```powershell
Import-CompleterSet ~\Completers\completers.psd1   # under half the 2.0.0 lazy import time when no file changed
Get-Completer -State Failed | Reset-Completer      # records return to Pending; next tab press loads the fixed script
Test-CompleterSet ~\Completers\completers.psd1     # empty when the set matches the folder; the PS_Completers gate becomes one call
```

## Milestone 2: Authoring and distribution (2.2.0, additive)

The 169 scripts are hand-written and live in one personal repo. Make the next script cheaper to write and make a set something other people can install.

- **New-CompleterScript** (feature). Emits a strict-grammar-conformant skeleton for a native command: the `Register-ArgumentCompleter` block, the literal target list, and a subcommand table seeded from the command's `--help` or `/?` output when it can be read safely. Output passes `Test-CompleterScript` before the author touches it.
- **Installable completer sets** (feature). A documented layout for a completer-set module on PSGallery: the set file at the module root, scripts beside it, relative paths as `Export-CompleterSet` already writes them. `Import-CompleterSet -Name <module>` resolves the set from an installed module so a profile line can name a package instead of a path.
- **Engine cmdlet detection** (infra). When the engine exports `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter`, the runtime snapshot and removal go through them; otherwise the reflection path runs unchanged. Additive, so 2.x profiles gain it the day the engine does. Tracks PR #26680.
- **Author guide, third edition** (docs). `about_Import_Completers` gains the scaffold workflow and the package layout; `about_Completer_Sets` gains the hash and drift sections.

Exit criteria:

```powershell
New-CompleterScript -CommandName rg -Path .\rg_completer.ps1 | Test-CompleterScript   # empty
Install-PSResource PS_Completers; Import-CompleterSet -Name PS_Completers               # one line, no path
Get-Command Get-ArgumentCompleter -ErrorAction Ignore                                  # when present, Get-Completer no longer touches reflection
```

## Milestone 3: Compiled core and the engine boundary (3.0.0-rc1 then 3.0.0, breaking)

The breaking surface is short and every item was promised or implied by 2.0. Ships as a release candidate first, per the rule carried over from the 2.0 roadmap.

- **Compiled core** (breaking). A small C# assembly holds the record types, the enums, the engine access, the AST conformance walk, and the lazy stub. `CompleterRegistration` and friends become public .NET types under the `CompleterActions` namespace, so `-is [CompleterActions.CompleterRegistration]` works in any scope and the dotted PSTypeName stops being a workaround. The conformance walk drops from about 20 ms per script to well under 1 ms, which reopens decision 5 of the 2.0 roadmap: the grammar can run at import again without touching the ratio.
- **Version-gated engine access** (breaking). Inside the compiled layer, the engine cmdlets are the primary path and reflection is the path for engines that predate them. The import-time probe stays and names the engine version in its message. Nothing in the public surface changes; the failure mode does.
- **Remove the deprecated surface** (breaking). `Get-CompleterRegistration`, `Register-CompleterRegistration`, `Unregister-CompleterRegistration`, the three exported legacy wrappers, and the `-ManagedOnly` and `-DiscoveredOnly` translations go. The module exports eight functions and no aliases. The PS_Completers tests and tools still call the old names, so that repo migrates first.
- **Minimum engine 7.4 LTS** (breaking). `PowerShellVersion = '7.4'` in the manifest, matching the CI matrix that has been the real support statement since 1.3.0.
- **Migration guide** (docs). `about_CompleterActions_Migration` rewritten for 2.x to 3.0: the removed names, the public types, the engine floor.
- **Release candidate** (release). Tag `v3.0.0-rc1` first; promote to `v3.0.0` only after the candidate has soaked without a defect; a defect means rc2.

Exit criteria:

```powershell
Get-Command -Module CompleterActions | Measure-Object     # 8 functions, 0 aliases
Get-Completer | Select-Object -First 1 | ForEach-Object { $_ -is [CompleterActions.CompleterRegistration] }   # True from the prompt, outside the module
Get-CompleterRegistration                                 # command not found
Find-PSResource CompleterActions -Repository PSGallery -Prerelease   # 3.0.0-rc1 listed; 3.0.0 stable only after the candidate soaks
```

## Removal map

Everything 2.0 kept as an alias is removed in 3.0. Nothing else in the public surface changes name.

| 2.x | 3.0 | Notes |
| --- | --- | --- |
| `Get-CompleterRegistration` (alias) | removed | Use `Get-Completer` |
| `Register-CompleterRegistration` (alias) | removed | Use `Register-Completer` |
| `Unregister-CompleterRegistration` (alias) | removed | Use `Unregister-Completer` |
| `*-CompleterRegistrationLegacy` (3 wrappers) | removed | Existed only to carry the aliases |
| `-ManagedOnly`, `-DiscoveredOnly` | removed | Use `-State` |
| `PowerShellVersion = '7.0'` | `'7.4'` | CI has never tested below 7.4 |
| `[CompleterRegistration]` (module-private class) | `[CompleterActions.CompleterRegistration]` (public type) | Same property names and order |

## Decisions

Open as of 2026-09-23, with a recommendation on each. Lock them before milestone 1 branches.

1. **The parse cache lives in the set file, not in a per-user cache directory.** A `Hash` per entry is written by the export that already knows the targets, so the set is self-validating and a repo-tracked set stays the single artifact. A per-user cache would be a second thing to invalidate. Lean: yes. Affects: milestone 1, set schema and Import-CompleterSet.
2. **Reset-Completer is a new command, not a switch on Register-Completer.** Re-arming a record is a state change on something already registered; overloading `-Force` would hide it. Lean: new command, same target contract as Unregister. Affects: milestone 1.
3. **Engine cmdlet detection ships in 2.x as soon as the engine has the cmdlets, and does not wait for 3.0.** Additive and invisible when the cmdlets are absent. Lean: yes, milestone 2, gated on PR #26680 landing in a shipped engine. Affects: milestone 2 and the shape of milestone 3.
4. **The compiled core is C# built with the dotnet SDK in CI, and the record types become public.** The alternative, keeping PowerShell classes and accepting the module-private type problem, leaves the 2.0 wart in place for good. Lean: C#, with the assembly built in the existing build task and the CI matrix unchanged. Affects: milestone 3, build and the class model.
5. **Reflection stays as the path for engines without the cmdlets, inside the compiled layer.** The alternative, a 3.0 engine floor at the first version with the cmdlets, is not available until that version ships and is adopted. Revisit for 4.0. Lean: keep it, version-gated. Affects: milestone 3.
6. **3.0.0 ships as a release candidate before it ships as stable.** Carried over from decision 6 of the 2.0 roadmap without change. Affects: milestone 3, release order.
