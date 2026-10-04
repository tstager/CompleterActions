# Milestone 3 specification: compiled core and the engine boundary (3.0.0)

Drafted: 2026-10-03
Base: main at `550bde9` (2.2.0-preview1, release commit `5a25401`, tag v2.2.0-preview1). Stable 2.2.0 is cut from the same code (decision 7), so every "2.2.0" behaviour cited below is the behaviour of that commit. The branch is cut after the stable 2.2.0 release commit is on main (roadmap, status line).
Roadmap: `docs/roadmap-3.0.md`, milestone 3, locked decisions 4, 5, and 6, and 2.0 roadmap decision 5, which milestone 3 reopens.
Kind: behaviour spec. It states what the module does after 3.0.0 and how a reader can tell. It does not prescribe helpers, file splits, or commit order, except where a name is public surface (the assembly, the namespace, the types).
Status: accepted 2026-10-04. The owner accepted every recommendation in section 13 as written, so each question there is settled as recommended and the plan runs with its defaults. Drafted 2026-10-03 and revised the same day after six reviews (spec: source grounding and the breaking surface; .NET and PowerShell feasibility, by probe; scope fidelity and testability. Plan: spec coverage; implementability against the codebase and CI; risk and unattended execution). Section 13 lists the questions for the owner. The plan (`docs/roadmap-3.0/milestone-3-plan.md`, "Owner decisions by gate") states when each answer is due, and an unanswered question means its recommendation applies. Each carries a recommendation, and sections 1 to 11 are written as if every recommendation is accepted. That includes question 1: the engine-cmdlet path is held, so 3.0.0 ships the reflection path inside the compiled layer behind the seam that will carry the cmdlet path; the contract for that path is appendix A of the milestone 2 spec, carried forward unchanged. Questions 1, 2, 4, and 10 would change roadmap text, which only the owner edits. This spec recommends those edits and collects them in section 10, "Roadmap edits the owner would make"; it edits nothing in the roadmap.

Every claim about current behaviour cites the file it was read from. Measurements in this document were taken on 2026-10-03 on the owner's Windows machine, PowerShell 7.6.6 (.NET 10.0.12), dotnet SDK 10.0.401, against the tracked `build/CompleterActions` (2.2.0-preview1) and the PS_Completers working tree at `2c590c6` (read only, through `Get-ChildItem` and the parser; nothing was written). Upstream state was read the same day with an authenticated `gh`. Appendix A gives the commands and the probe assembly that produced the numbers.

## 1. Scope and non-goals

3.0.0 is the breaking release the 2.0 line promised. The breaking surface is exactly the roadmap's: the compiled core and public types, the engine boundary moved into typed code, the removal of the deprecated surface, and the 7.4 engine floor. Everything else behaves as in 2.2.0.

- **Four record types and two enums become public .NET types** in the `CompleterActions` namespace, shipped in one assembly that the manifest loads. Property names and order are unchanged (section 2). `-is [CompleterActions.CompleterRegistration]` is true from any scope.
- **Engine access runs in the compiled layer**: the import-time probe, the reflection into `EngineIntrinsics._context` and the two completer dictionaries, and the one place that will choose between reflection and the engine cmdlets (section 3). Messages are unchanged.
- **The strict grammar runs in the compiled layer** with the same findings, and about a hundred times faster (section 4). Under question 2's recommendation it also runs when a strict script is parsed for its targets, at `Register-Completer -Lazy` and in `Import-CompleterSet`, so a non-conforming script is refused there instead of at its first tab; the first-tab check stays.
- **The deprecated surface is removed** (section 5). The module exports 11 functions and no aliases.
- **`PowerShellVersion = '7.4'`** (section 6). The `src` code may use .NET 8 APIs.
- **The set file schema is unchanged**: `Version = 1`, `Path`, `Trusted`, `Hash`, `Targets`. A set written by 2.2.0 imports on 3.0.0 with the same records, and a set written by 3.0.0 imports on 2.2.0 (`Export-CompleterSet` is unchanged, section 11).
- **The completer-set package layout and `Import-CompleterSet -Name` are unchanged.** PS_Completers' package requires CompleterActions `2.2.0` as a minimum (`package/PS_Completers.psd1` on its `feat/completer-set-package` branch, `RequiredModules = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' })`), which 3.0.0 satisfies.
- **PSReadLine neutrality holds**: nothing hooks key handlers, replaces `TabExpansion2`, or touches PSReadLine options or prediction. The lazy stub stays a PowerShell script block bound to the module (question 4).

In scope:

| Item | Kind | Section |
| --- | --- | --- |
| Compiled core, public types | breaking | 2 |
| Engine access in the compiled layer; the version gate as a seam | breaking | 3 |
| Strict grammar in the compiled layer; grammar at registration and import (question 2) | breaking, perf | 4 |
| Remove the deprecated surface | breaking | 5 |
| Minimum engine 7.4 | breaking | 6 |
| Build, package, and CI for the assembly | infra | 7 |
| Migration guide, fourth edition of the help | docs | 8 |
| Benchmark, third edition, and the grammar timing | perf | 9 |
| `3.0.0-rc1`, then `3.0.0` | release | 10 |

What a reader can see after 3.0.0:

| Observation | How to tell |
| --- | --- |
| The records are real types | `Get-Completer \| Select-Object -First 1 \| ForEach-Object { $_ -is [CompleterActions.CompleterRegistration] }` prints `True` at the prompt, outside the module |
| The old names are gone | `Get-CompleterRegistration` fails with `CommandNotFoundException`; `Get-Command -Module CompleterActions` lists 11 functions and 0 aliases |
| The grammar is fast | `Test-CompleterScript` over the 173 PS_Completers scripts takes at most 0.30 of the 2.2.0 time (section 9) |
| A bad script is caught at import | `Import-CompleterSet` over a set whose strict entry has a changed, non-conforming script reports `Entry <n> ('<path>'): The script does not conform to the strict import grammar: line <l>, column <c> ...` and registers nothing for it (question 2) |
| The engine floor is real | `Import-Module CompleterActions` on PowerShell 7.3 fails with the manifest's version error before any module code runs |

Non-goals:

- **No new command and no renamed command.** Every parameter name and parameter set of the 11 functions is as in 2.2.0 (acceptance check 20).
- **No property added, renamed, or removed** on the four record types, and no type change except the ones the move from PowerShell classes to .NET types forces, which section 2 lists one by one.
- **No engine-cmdlet path in 3.0.0** under question 1's recommendation. The compiled layer has one entry point that selects the path at import; in 3.0.0 only the reflection path exists behind it. The cmdlet path is the milestone 2 spec's appendix A, unchanged, and ships in the first 3.x minor after a released engine, preview or stable, carries the merged cmdlets. On 2026-10-03 PowerShell/PowerShell PR #26680 is still open, has no milestone, and was last updated 2026-08-02; the newest engine releases are 7.7.0-preview.5, 7.6.6, 7.5.11, and 7.4.20, none of which has `Get-ArgumentCompleter` (`gh pr view 26680`, `gh api repos/PowerShell/PowerShell/releases`).
- **No compiled lazy stub** under question 4's recommendation. The stub's job is to run `Import-CompleterScript`, which is PowerShell, so the stub stays a module-bound script block exactly as `src/Private/New-CompleterLazyStub.ps1` builds it today.
- **No compiled public commands.** The 11 functions stay PowerShell functions in `src/Public`. The assembly holds types and two internal services (engine access, grammar); it exports no cmdlet. `CmdletsToExport` stays `@()`.
- **No change to `Export-CompleterSet`, `Test-CompleterSet`, `New-CompleterScript`, `Reset-Completer`, or the hash fast path.** Section 11.
- **No 4.0 decisions.** Whether reflection is dropped once an engine floor has the cmdlets is decision 5's "revisit for 4.0".
- **Consequences for the roadmap** are the owner's. Section 10 lists them.

### Removal map

| 2.x | 3.0 | How a caller sees it |
| --- | --- | --- |
| `Get-CompleterRegistration` (alias) | removed | `CommandNotFoundException`; use `Get-Completer` |
| `Register-CompleterRegistration` (alias) | removed | same; use `Register-Completer` |
| `Unregister-CompleterRegistration` (alias) | removed | same; use `Unregister-Completer` |
| `Get-CompleterRegistrationLegacy`, `Register-CompleterRegistrationLegacy`, `Unregister-CompleterRegistrationLegacy` | removed | `CommandNotFoundException`; they existed only to carry the aliases (`src/Public/*Legacy.ps1`) |
| `-ManagedOnly`, `-DiscoveredOnly` | removed with the wrapper that carried them | `Get-Completer -ManagedOnly` already fails in 2.x (`tests/CompleterActions.Tests.ps1`, "no longer exposes ManagedOnly or DiscoveredOnly on Get-Completer"); use `-State` |
| The once-per-process deprecation warning | removed | nothing is written |
| `PowerShellVersion = '7.0'` | `'7.4'` | `Import-Module` on 7.0 to 7.3 fails on the manifest |
| `[CompleterRegistration]` and the other three classes, module-private | `[CompleterActions.CompleterRegistration]` and the other three, public | `-is` and `::new()` work from any scope |
| `[CompleterState]`, `[CompleterType]`, module-private enums | `[CompleterActions.CompleterState]`, `[CompleterActions.CompleterType]`, public | same values, same order |
| `PSTypeNames` of a record: `CompleterActions.CompleterRegistration`, `CompleterRegistration`, `System.Object` | `CompleterActions.CompleterRegistration`, `System.Object` | the bare class name, which only the PowerShell class carried, is gone (section 2) |
| Strict grammar at first tab only (2.0 decision 5) | at first tab, and wherever a strict script is parsed for its targets (question 2) | a non-conforming script fails `Register-Completer -Lazy` and is an invalid entry in `Import-CompleterSet` |

## 2. The compiled core and the public types

### The assembly

- One assembly, `CompleterActions.Core.dll`, built from C# with the dotnet SDK (decision 4), target framework `net8.0`, the runtime PowerShell 7.4 carries. It references the `System.Management.Automation` 7.4.0 NuGet package, the oldest engine the module supports (section 6), so nothing in it can depend on a newer engine API by accident. On 2026-10-03 the package exists at 7.4.0 through 7.4.7 on nuget.org (`dotnet package search System.Management.Automation --exact-match`), and an assembly built against 7.4.0 loaded and ran on 7.6.6 (.NET 10.0.12) and, under WSL, on 7.6.5 (.NET 10.0.11) (appendix A). That is the runtime's rule, not luck: an assembly reference resolves when the loaded assembly's version is equal to or higher than the referenced one, and a `net8.0` library runs on any newer .NET the host provides; the pin to 7.4.0 keeps the reverse case, a reference newer than the engine's own assembly, from ever being built. The CI matrix, 7.4 to preview on Windows and Ubuntu, is the running proof for every supported engine.
- The manifest loads it through `RequiredAssemblies`, so its types exist before the root module is parsed and every `[CompleterActions.<Type>]` literal in `src` resolves at parse time. Where the file sits inside the module folder is the plan's choice; its name is `CompleterActions.Core.dll`, so that `Import-Module <folder>` keeps resolving the manifest and nobody imports the assembly as a binary module by mistake (a `CompleterActions.dll` beside `CompleterActions.psm1` would invite that).
- **It exports no cmdlet.** `CmdletsToExport = @()` stays. `Get-Command -Module CompleterActions` lists the 11 functions and nothing else.
- **Cost.** Loading a small assembly through `RequiredAssemblies` is cheaper than compiling the PowerShell classes it replaces. A toy module with one function and the four types in a dll imported in 21 to 41 ms (median 22.5) over ten fresh processes; the same module with the types as PowerShell classes imported in 33 to 63 ms (median 35). `Add-Type -Path` of the same dll took 73 ms and `Assembly.LoadFrom` 2 ms in a fresh process (appendix A). Section 9 gates the real import.
- **An assembly cannot be unloaded** from a PowerShell process. `Remove-Module` followed by `Import-Module` works (checked), and a re-import in the same process uses the already loaded types. A changed `CompleterActions.Core.dll` therefore needs a new process, which the test and build rules already require (plan, "Run steps"). The version a process has loaded is `[CompleterActions.CompleterRegistration].Assembly.GetName().Version`.
- **Assembly identity.** `AssemblyVersion` is `3.0.0.0` and stays `3.0.0.0` for every 3.x release, so a type name never changes identity across a minor; `AssemblyFileVersion` and `AssemblyInformationalVersion` carry the module version and prerelease label (`3.0.0-rc1`). Not strong-named.
- **Namespaces.** The four record types and the two enums are in `CompleterActions`. Everything else the assembly holds, engine access (section 3) and the grammar (section 4), is in `CompleterActions.Internal`, is public only because PowerShell cannot call internal members, and is documented in the migration guide as not a contract: it may change in any 3.x release.

### The types

Four sealed classes with a public parameterless constructor and public read-write properties, in exactly the property order 2.2.0's classes declare (`src/Classes/CompleterTypes.ps1`), so `Select-Object *`, `Format-List`, `ConvertTo-Csv`, and `tests/CompleterClasses.Tests.ps1`'s property-order assertion see the same columns in the same order.

`CompleterActions.CompleterRegistration`:

| Property | .NET type | Note |
| --- | --- | --- |
| `Key` | `string` | |
| `RegistrationKey` | `string` | |
| `RuntimeKey` | `string` | |
| `CommandName` | `string` | |
| `ParameterName` | `string` | `''` on a native record |
| `IsNative` | `bool` | |
| `CompleterType` | `CompleterActions.CompleterType` | |
| `TargetType` | `string` | |
| `Source` | `string` | `'Managed'` or `'Discovered'` |
| `State` | `CompleterActions.CompleterState` | |
| `IsManaged` | `bool` | |
| `IsRuntimeRegistered` | `bool` | |
| `ScriptPath` | `string` | `''` without a script |
| `Trusted` | `bool` | |
| `LoadError` | `string` | `''` unless `Failed` |
| `ImportModule` | `System.Management.Automation.PSModuleInfo` | `$null` by default |
| `ScriptBlock` | `System.Management.Automation.ScriptBlock` | `$null` by default |
| `ScriptText` | `string` | |

`CompleterActions.ImportedCompleterRegistration`: `Key`, `RegistrationKey`, `RuntimeKey`, `CommandName`, `ParameterName`, `IsNative`, `Native` (`bool`), `CompleterType`, `TargetType`, `Source`, `Trusted`, `Path`, `SourcePath`, `ImportModule`, `ScriptBlock`, `ScriptText`, with the types above.

`CompleterActions.CompleterScriptFinding`: `Path` (`string`), `Line` (`int`), `Column` (`int`), `Severity` (`string`), `Construct` (`string`), `Message` (`string`), `Hint` (`string`). `Severity` and `Construct` stay strings: an enum would be a second contract change in one release that nobody asked for, and `Test-CompleterSet` adds `Construct` values by release (`PackageLayout` in 2.2.0).

`CompleterActions.CompletionMatch`: `Key`, `RuntimeKey`, `CommandName`, `ParameterName`, `IsNative`, `CompleterType`, `InputText` (`string`), `CursorPosition` (`int`), `CompletionText`, `ListItemText`, `ResultType` (`System.Management.Automation.CompletionResultType`), `ToolTip`.

Two enums, same names, same order, so the same integer values:

- `CompleterActions.CompleterState`: `Active` 0, `Stale` 1, `Conflicted` 2, `Pending` 3, `Failed` 4, `Discovered` 5.
- `CompleterActions.CompleterType`: `Native` 0, `Parameter` 1.

### What a PowerShell caller sees differently

These are the observable consequences of the move, each checked on 2026-10-03 against a probe assembly (appendix A) unless marked otherwise. The migration guide lists them (section 8).

1. **`-is` and `::new()` work everywhere.** `$record -is [CompleterActions.CompleterRegistration]` is `True` at the prompt once the module is imported. `[CompleterActions.CompleterRegistration]::new()` constructs a record from a script. In 2.x both resolve only inside the module (`en-US/about_CompleterActions_Migration.help.txt`, "TYPED OUTPUT"; `tests/CompleterClasses.Tests.ps1`, "keeps the classes private to the module session state"). The type literal resolves as long as the assembly is loaded in the process, so it works after `Import-Module` and keeps working after `Remove-Module`.
2. **`PSTypeNames` loses the bare class name.** A record's `PSObject.TypeNames` is `CompleterActions.CompleterRegistration`, `System.Object`. In 2.x it is `CompleterActions.CompleterRegistration`, `CompleterRegistration`, `System.Object`, because the PowerShell class's own name sits in the list and the constructor inserts the dotted name in front (`src/Classes/CompleterTypes.ps1`). The dotted name stays first, so `CompleterActions.Format.ps1xml` (which selects on `CompleterActions.CompleterRegistration`, `CompleterActions.CompleterScriptFinding`, and `CompleterActions.CompletionMatch`) applies unchanged, `$_.PSTypeNames[0] -eq 'CompleterActions.CompleterRegistration'` stays true, and a deserialized record is still `Deserialized.CompleterActions.CompleterRegistration`.
3. **String properties stay `''` when they have no value** (question 3). A .NET `string` property defaults to `$null`. A 2.x record the module builds has `''` because `New-CompleterRegistrationRecord` assigns every property and a PowerShell class converts an assigned `$null` to `''`; a bare `[CompleterRegistration]::new()` in 2.x leaves its strings `$null` (checked: `class X { [string] $A }; [X]::new().A` is `$null`, which is why `tests/CompleterClasses.Tests.ps1` tests `ParameterName` with `Should -BeNullOrEmpty`). The 2.0 migration guide promised `''` for records and told callers to drop `-eq $null` tests (`about_CompleterActions_Migration`, "TYPED OUTPUT", fourth detail). 3.0 keeps that promise and tightens it to constructed instances too: every `string` property of the four types is initialised to `''`, and assigning `$null` stores `''`. `ImportModule` and `ScriptBlock` stay `$null` by default, as today.
4. **Enum values serialize as integers**, as they do in 2.x: `ConvertTo-Json` writes `"State": 3` for `Pending` without `-EnumsAsStrings`, and `Export-Clixml` writes the integer. The 2.0 guidance is unchanged. `$_.State -eq 'Pending'`, `-State Pending`, and tab completion of `-State` values keep working, because the parameter is typed `[CompleterActions.CompleterState[]]` and PowerShell converts the string.
5. **`[CompleterActions.CompleterState]` is usable from a script**, including `[enum]::GetNames([CompleterActions.CompleterState])`, which in 2.x needs `& (Get-Module CompleterActions) { ... }`.
6. **Hashtable conversion works**: `[CompleterActions.CompleterScriptFinding] @{ Path = 'x'; Line = 1 }` builds a finding through the property setters, as the module's own helpers do today with the classes (`src/Private/New-CompleterScriptFinding.ps1`, `New-CompletionMatch.ps1`, `New-ImportedCompleterRegistration.ps1`).
7. **`(Get-Command Get-Completer).OutputType.Name`** stays `CompleterActions.CompleterRegistration`. Whether the attribute names the type as a string or a type literal is internal.
8. **Across a remoting or job boundary** nothing changes from 2.x: the record arrives deserialized with a string `State`.

## 3. Engine access in the compiled layer

### What moves

Everything that *resolves* a non-public engine member moves into `CompleterActions.Internal`:

- the import-time capability probe (`src/Private/Assert-CompleterRuntimeCapability.ps1`);
- resolving the execution context behind `EngineIntrinsics` (`src/Private/Resolve-CompleterRuntimeExecutionContext.ps1`, the `_context` field);
- resolving the `CustomArgumentCompleters` and `NativeArgumentCompleters` properties of that context (`src/Private/Get-CompleterRuntime.ps1`).

The compiled layer resolves the field and the two properties once per import and keeps the handles. The PowerShell side keeps the runtime object it has today, `CompleterActions.CompleterRuntime` with `ExecutionContext`, `CustomProperty`, `NativeProperty`, `CustomArgumentCompleters`, and `NativeArgumentCompleters` (`src/Private/Get-CompleterRuntime.ps1`), now filled from the compiled handles, and keeps reading and writing the dictionaries through those handles' `GetValue` and `SetValue` and through the `*-CompleterRuntimeDictionaryValue` helpers, which never reflect. That shape is a test contract: `tests/CompleterRegistration.Tests.ps1` ("creates a missing runtime dictionary once ..." and "keeps a runtime dictionary created after the snapshot ...") builds such an object by hand around a probe type and drives `Add-RuntimeCompleterRegistration` with it, and `tests/CompleterSet.Tests.ps1` and `tests/CompleterSetDrift.Tests.ps1` replace `Get-CompleterRuntime`, `Get-CompleterRegistrationSnapshot`, `Add-RuntimeCompleterRegistration`, and `Remove-RuntimeCompleterRegistration` in module scope. All of those tests pass unchanged.

After 3.0.0 no `.ps1` under `src` contains `GetField`, `GetProperty`, `BindingFlags`, or the string `_context` (acceptance check 7); `GetValue` and `SetValue` on an already resolved handle remain. The private PowerShell helpers that the rest of the module and the tests call by name stay as thin wrappers over the compiled layer, so the module's call graph is unchanged. Which wrappers stay and what their bodies call is the plan's.

### What does not change

- **The probe's message.** `CompleterActions cannot run on PowerShell <version>: the required runtime member(s) '<list>' could not be resolved. Completer discovery depends on PowerShell internals; check for a module update that supports this engine version.`, with `<list>` the same member names in the same order (`System.Management.Automation.EngineIntrinsics._context`, then `<FullName of the context's type>.CustomArgumentCompleters` and `<FullName of the context's type>.NativeArgumentCompleters`, the type name interpolated from the resolved context as `Assert-CompleterRuntimeCapability.ps1` line 83 does), thrown once at import as a terminating error, before any function runs (`src/Private/Assert-CompleterRuntimeCapability.ps1`). The three tests in `tests/CompleterRegistration.Tests.ps1` ("Runtime capability probe") pass unchanged: the probe still accepts a substitute `EngineIntrinsicsType`, `EngineIntrinsics`, and `RuntimeExecutionContext` so a test can make each member missing.
- **The two other messages**: `Unable to access the PowerShell execution context field required for completer runtime discovery.` and `Unable to resolve the current PowerShell execution context.` (`src/Private/Resolve-CompleterRuntimeExecutionContext.ps1`), and `The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.` (`Get-CompleterRuntime.ps1`).
- **Every record, warning, error, and verbose line** of the 11 commands (section 11). The parameter-only key is still skipped with its verbose text; the native fallback key is still a `Discovered` native record.
- **Rollback.** A failed registration or import restores the exact prior dictionary value, as today (`src/Private/Add-CompleterRegistration.ps1`).
- **PSReadLine neutrality.**

### The seam: version-gated access

The compiled layer has one entry point that chooses, once per import, how the engine is reached. It records its choice and the engine version. In 3.0.0, under question 1, the only path behind it is reflection, so the choice is always `Reflection`, the probe always runs, and nothing new is written to any stream. The seam exists so that the cmdlet path (milestone 2 spec, appendix A, "What routes through the cmdlets when they are present" and "Parity between the paths") can be added in a 3.x minor without touching the PowerShell side: the private wrappers call the entry point, not a path.

What "version-gated" means in 3.0.0, concretely:

- The gate is a check on the engine at import, not a version number, because no engine version has the cmdlets yet, and that stays true when the cmdlet path ships: the gate is then the module-qualified presence lookup appendix A specifies, never a `$PSVersionTable` comparison, and the verbose line appendix A specifies names the engine version. Question 1 covers this reading of "version-gated".
- The probe already names the engine version in its message, which is the roadmap item's "names the engine version" ("CompleterActions cannot run on PowerShell 7.6.6: ...").
- **The failure mode changes in where it is raised, not in what it says.** A changed engine fails inside one compiled type at import with the same message. In 2.x the same change fails in one of four PowerShell helpers at import; the message is the same, but a partial change (for example a renamed dictionary property) could pass the probe and fail later in `Add-RuntimeCompleterRegistration`, which reads the property again by name (`src/Private/Add-RuntimeCompleterRegistration.ps1`). In 3.0 the compiled layer resolves each member once and holds the `FieldInfo` and `PropertyInfo`, so a member that resolved at import cannot fail to resolve later. That is the whole of the behaviour change this item makes in 3.0.0.

If the owner answers question 1 against the recommendation, appendix A of the milestone 2 spec comes into this spec as its section 3a, with "2.x" read as "3.0", and its checks A1 to A3 join section 12's list. Nothing else in this spec changes, because appendix A was written to be additive.

## 4. The strict grammar in the compiled layer

### Same findings, faster

- `Test-CompleterScript`, `Import-CompleterScript` (strict tier), `New-CompleterScript`'s self-check, and the first-tab load all produce the findings of `src/Private/Test-CompleterScriptAst.ps1` today, through `Get-CompleterScriptFinding` and `Assert-CompleterScriptConformance`. After 3.0.0 the walk is a compiled AST visitor and **the findings are identical**: the same `Path`, `Line`, `Column`, `Severity`, `Construct`, `Message`, and `Hint`, in the same order, for every script. The texts of the 40 `Add-Finding` calls in `Test-CompleterScriptAst.ps1` (`Construct`, `Message`, `Hint`, interpolations included) are the catalogue; none is added, removed, or reworded. Parse errors are still reported as `ParseError` findings by the PowerShell side (`src/Private/Get-CompleterScriptFinding.ps1`), before the walk.
- The oracle is the 2.2.0 build. Over the 11 fixtures under `tests/Fixtures/ImportCompleterScript/`, the 14 scaffold corpus outputs, every `.ps1` under `tests/Fixtures/LazyRegistration/`, `tests/Fixtures/CompleterSet/`, and `tests/Fixtures/CompleterSetPackage/`, and the 173 PS_Completers scripts, `Test-CompleterScript` under 3.0.0 and under 2.2.0 gives the same CSV of findings (acceptance check 8). `tests/CompleterAuthorTooling.Tests.ps1`, which pins the grammar's findings in 20 `It` blocks, passes unchanged.
- **Cost.** On 2026-10-03, `Test-CompleterScript` over the 173 scripts took 4477 ms under the 2.2.0 build, 25.9 ms per script, of which parsing is 2.1 ms (355 ms for the 173). A compiled visitor shaped like the grammar (every node visited, top-level statements, command names and parameters, assignments, `using` statements, nested registrations, function overrides, traps) walked the same 173 parsed scripts in 35 ms, 0.203 ms per script; parse plus walk was 2.47 ms per script (appendix A). The roadmap's "well under 1 ms" holds with a five-fold margin. Section 9 sets the gates.
- **The AST stays the parser's.** The compiled walk consumes `System.Management.Automation.Language.Ast` produced by `[Parser]::ParseFile`, as today; no second parser, no text matching.

### Where the grammar runs (question 2; reopens 2.0 decision 5)

2.0 decision 5 moved the walk from import to first tab because it cost about 20 ms per script and would have taken the lazy import ratio from 0.19 to about 0.67 (`docs/roadmap-2.0.md`, decision 5). At 0.2 ms per script that reason is gone. Under question 2's recommendation:

- **The first-tab check stays exactly as it is.** `Invoke-CompleterLazyStub` loads through `Import-CompleterScript`, which runs `Assert-CompleterScriptConformance` for a strict script immediately before it executes (`src/Public/Import-CompleterScript.ps1`, `src/Private/Invoke-CompleterLazyStub.ps1`). A file that changes between registration and first tab is still never run unchecked. A failure still moves the record to `Failed` with the findings in `LoadError`.
- **The grammar also runs wherever a strict script is parsed for its targets.** Two places parse a strict script today without running the grammar:
  - `Register-Completer -Lazy` without `-Trusted` derives the targets from the parse (`src/Private/Get-CompleterScriptTarget.ps1`, called from `Register-Completer`). After 3.0.0 the walk runs on that parse. A non-conforming script fails the registration with the terminating error `Assert-CompleterScriptConformance` throws today, `Completer script '<path>' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is.` followed by one line per `Error` finding. It is thrown as the lazy derivation errors are thrown today, unwrapped (`src/Public/Register-Completer.ps1` throws `The script '<path>' does not register a completer for ...` the same way; only the conflict error carries the `Failed to register the completer` prefix). The check runs where the targets are derived, before `ShouldProcess`, so `-WhatIf` fails the same way. Nothing is registered for any target of that script.
  - `Import-CompleterSet` parses a strict entry whose `Hash` is absent, unrecognised, or different, to derive its targets (`src/Private/Resolve-CompleterSetEntry.ps1`, the parse branch after the fast path). After 3.0.0 the walk runs on that parse, and a non-conforming script is a new problem of the entry, `Kind = 'NonConforming'`, with the message `The script does not conform to the strict import grammar: line <l>, column <c> (<Construct>): <Message> Run Test-CompleterScript to work through the findings, or mark the entry Trusted to run it as-is.`, where `<l>`, `<c>`, `<Construct>`, and `<Message>` are the first `Error` finding's. It flows through the existing invalid-entry path: the set fails with nothing registered and the report `Entry <n> ('<path>'): <message>`, or, under `-SkipInvalid`, the entry is skipped with the existing `Completer set '<path>' skipped ...` warning and the other entries register. A `NonConforming` problem is reported alongside a `TargetMismatch` for the same entry when both apply, grammar first.
- **Entries that take the hash fast path are not parsed and not walked**, as today. Their static checks come from the set (3.0 roadmap decision 1), and the first-tab check covers them. So a fully hashed import of an unchanged set does the same work as in 2.2.0 and the hashed ratio does not move. Only a new or changed strict script pays the 0.2 ms.
- **Trusted entries and `-Trusted` registrations are never walked**, as today.
- **`Test-CompleterSet` is unchanged.** It reports drift, not grammar; the grammar gate for a repository is `Test-CompleterScript`, which the PS_Completers `tests/Completers.Tests.ps1` runs over every script.
- **`Export-CompleterSet` is unchanged.** It writes the `Hash` of the text at export time and does not run the grammar (alternative in question 2).

The consequence a 2.x user can notice: a set that today imports with a non-conforming strict script as a `Pending` record that turns `Failed` at first tab now refuses that entry at import, so the profile sees the problem on the next session start instead of at the first tab press for that tool. With `-SkipInvalid`, which the owner's profile line uses (`Microsoft.PowerShell_profile.ps1` line 157; the PS_Completers tests import without it), the rest of the set registers as before. For the 173 PS_Completers scripts nothing changes: all conform (their CI gate), so no entry gains a problem.

## 5. Removed surface

- **Exports.** `FunctionsToExport` lists exactly the 11: `Export-CompleterSet`, `Get-Completer`, `Import-CompleterScript`, `Import-CompleterSet`, `New-CompleterScript`, `Register-Completer`, `Reset-Completer`, `Test-CompleterRegistration`, `Test-CompleterScript`, `Test-CompleterSet`, `Unregister-Completer`. `AliasesToExport = @()`. `Export-ModuleMember` in the root module exports functions only (`CompleterActions.psm1` today adds `-Alias` with the three names). `Get-Command -Module CompleterActions | Measure-Object` gives 11.
- **Files.** `src/Public/Get-CompleterRegistrationLegacy.ps1`, `Register-CompleterRegistrationLegacy.ps1`, `Unregister-CompleterRegistrationLegacy.ps1`, and `src/Private/Write-CompleterDeprecationWarning.ps1` are deleted. `src/Bootstrap.ps1` loses its three `New-Alias` lines and `$script:CompleterDeprecationWarningsIssued`. `src/Classes/CompleterTypes.ps1` is deleted with its folder, and the root module and the build stop looking for a `Classes` folder (section 7).
- **Tests.** `tests/CompleterDeprecation.Tests.ps1` is deleted (9 `It` blocks, all about the aliases). `tests/CompleterClasses.Tests.ps1` is rewritten for the public types (section 12, check 2). In `tests/CompleterActions.Tests.ps1`, the `Get-CompleterRegistrationLegacy` case of "binds every piped object to the InputObject set of <Command>" goes; every other test in that file passes unchanged.
- **Help and docs.** `README.md` line 50 (the aliases paragraph), line 360 (the Bootstrap description names the three aliases), and line 371 (the wrappers) change; in `.github/copilot-instructions.md`, line 6 drops the alias and wrapper sentences and its "fourteen functions and three aliases" count, line 8 becomes "eleven functions and no aliases", and line 24 drops the wrapper sentence; the migration guide is rewritten (section 8). No command help page names a legacy command today except through `about_CompleterActions_Migration`.
- **What a caller sees.** Calling an old name fails with PowerShell's own `The term 'Get-CompleterRegistration' is not recognized as a name of a cmdlet, function, script file, or executable program.` The module adds no message of its own: a module cannot intercept a name it does not export, and a stub that exists only to throw would be an export (non-goal). The migration guide maps each name.

## 6. Minimum engine 7.4

- `PowerShellVersion = '7.4'` in `CompleterActions.psd1`; `CompatiblePSEditions = @('Core')` unchanged. `Import-Module` on an older engine fails on the manifest with PowerShell's own version message before any module file is read.
- The CI matrix is unchanged: Windows and Ubuntu by 7.4, 7.5, 7.6, and preview (`.github/workflows/ci.yml`), which has been the real support statement since 1.3.0 (roadmap, "Where 2.0 leaves us"). On 2026-10-03 the legs resolve to 7.4.20, 7.5.11, 7.6.6, and 7.7.0-preview.5.
- **The .NET floor moves with it.** `src` may use any .NET 8 API. The 2.2.0 rule that forbade `Encoding.Latin1`, `WaitForExitAsync`, `Convert.ToHexString`, and `File.SetUnixFileMode` (milestone 2 plan, WP1 "Floor") is lifted; nothing is required to change, and nothing in this milestone needs those APIs. The compiled core targets `net8.0` for the same reason.
- `README.md` line 19 ("`PowerShellVersion = '7.0'`") and `tests/CompleterRegistration.Tests.ps1` ("Passes Test-ModuleManifest", which pins `'7.0'`) change to `7.4`.

## 7. Build, package, and CI

- **A `compile` task** in `CompleterActions.build.ps1` runs `dotnet build` on the C# project in `Release` configuration and places `CompleterActions.Core.dll` where the source manifest's `RequiredAssemblies` entry finds it, so `Import-Module ./CompleterActions.psd1` from the repository root works after `Invoke-Build compile`. The `build` task depends on `compile` and copies the assembly into `build/CompleterActions` at the same relative place **before** it calls `Update-ModuleManifest`: both `Update-ModuleManifest` and `Test-ModuleManifest` reject a manifest whose `RequiredAssemblies` file is missing (`The specified RequiredAssemblies entry 'lib/CompleterActions.Core.dll' ... is invalid`, checked 2026-10-03), and `Import-Module` of the source manifest fails the same way. So from 3.0 on, `Invoke-Build compile` (or `build`) is a precondition of every Pester run and of every import of the source manifest, locally and in CI; the README says so. `dotnet` is required: 10.0.401 on the owner's machine; the `ubuntu-24.04` and `windows-2025` runner images behind `ubuntu-latest` and `windows-latest` carry .NET SDK 8.0, 9.0, and 10.0 (`actions/runner-images` readmes, read 2026-10-03), so no workflow step installs one. The project pins no SDK version; `global.json` is not added, because any SDK 8 or later builds a `net8.0` library.
- **No compiled code is tracked in git** (question 6). `.gitignore` gains the assembly's locations under the repository root and under `build/CompleterActions`, plus the project's `bin/` and `obj/`. The tracked `build/CompleterActions` keeps its seven text files (`git ls-files build`: the manifest, the psm1, the format file, the help XML, and three about topics) and gains none. The test "keeps the tracked build output in sync with the module sources" (`tests/CompleterRegistration.Tests.ps1`) compares text files line by line and asserts that the fresh build and the tracked folder hold the same files; it is changed to leave `*.dll` out of both the file list and the line comparison and to assert, separately, that the fresh build produced `CompleterActions.Core.dll`.
- **CI.** `.github/workflows/ci.yml` gains a `Compile` step (`Invoke-Build -Task compile`) between `Install modules` and `Lint`, so the `Test` step's `Import-Module` of the source manifest finds the assembly. Lint, Test, and Build keep their order and their reasons (the comments in the workflow). `release.yml` gains the same step before `Test`. The published package is the `build/CompleterActions` folder with the assembly in it, built on the release runner (`Publish_build`, unchanged).
- **Consequence for baselines.** `git archive v3.0.0 build` no longer yields an importable module. Future benchmarks take their 3.x baseline from `Save-PSResource -Name CompleterActions -Version <v> -Repository PSGallery -Path <scratch>`, which is the release build byte for byte, or from `Invoke-Build build` on a checkout of the tag. The `Measure-CompleterStartup.ps1` help's `git archive` example is updated to say so (section 8). The 2.2.0 baseline for this milestone's benchmark still comes from `git archive v2.2.0 build`, because 2.2.0 is all text.
- **PSScriptAnalyzer** does not read C#. The project builds with `TreatWarningsAsErrors` and nullable reference types enabled, and the CI `Compile` step fails on any warning. No further C# linter is added.
- **The root module.** `CompleterActions.psm1` stops reading a `Classes` folder (section 5). The build's `$sourceFolders` list drops `Classes`. The test "defines every class and enum before the first function in the packaged module" (`tests/CompleterClasses.Tests.ps1`) goes with the classes.

## 8. Documentation: migration guide and the fourth edition

- **`about_CompleterActions_Migration`** is rewritten for 2.x to 3.0 (`en-US/about_CompleterActions_Migration.help.txt`). It keeps the topic name so every error text that names it (`src/Private/Resolve-CompleterInputObject.ps1`'s "See about_CompleterActions_Migration.") stays true. It covers, in this order: the removed names with their replacements (the removal map); the public types, with the eight observable differences of section 2 as a numbered list; the engine floor; the grammar at registration and import (question 2), with what a profile sees; and a checklist for a profile. The 1.x-to-2.0 content moves to a closing section, `MOVING FROM 1.x`, shortened to the command names and the pointer that 2.x profiles were already migrated by 2.0's guide, so a reader coming from 1.x still finds the path. `SEE ALSO` unchanged.
- **`about_Completer_Sets`**: the sentence in `VALIDATION BEFORE REGISTRATION` and the paragraphs around lines 132, 263, 282, 612 (the trusted-entry warning's "at first tab"), 620, and 682 that say the grammar runs at the first tab press gain the registration and import check (question 2); the hash section states that a hash-matched entry is not re-walked and why.
- **`about_Import_Completers`**: line 24's "before the script executes" paragraph gains the same.
- **Command help** (`src/docs/CompleterActions/*.md` and the comment help): `Register-Completer.md` (lines 79, 89, 258) and `Import-CompleterSet.md` (lines 90, 110) gain one sentence each for the import-time grammar; `Get-Completer.md` and the rest are unchanged. The module page `CompleterActions.md` drops the three aliases if it lists them.
- **`README.md`**: lines 19, 50, 162, 168, 264, 278, 360, and 371 as sections 5 and 6 and question 2 require; a "Types" paragraph that shows `-is [CompleterActions.CompleterRegistration]`; the build section gains the `dotnet` requirement and the `compile` task.
- **`.github/copilot-instructions.md`**: lines 6, 8, 24, and 28 ("types in `src\Classes`" becomes the C# project's folder).
- **`tools/Measure-CompleterStartup.ps1`**: the `.PARAMETER BaselineModulePath` text and example 2 say where a 3.x baseline comes from (section 7).
- **`CHANGELOG.md`**: `## [3.0.0-rc1]` with `### Removed` (the aliases, the wrappers, the switches, the deprecation warning, the `7.0` floor), `### Changed` (public types with the eight differences, engine access in the compiled layer, grammar in the compiled layer and at registration and import, `PowerShellVersion = '7.4'`), `### Added` (the assembly, the `compile` task), and `### Documentation`; then `## [3.0.0]` as a promotion note, as 2.0.0 did.

## 9. Performance: benchmark, third edition, and the grammar timing

Two existing numbers must hold and two new ones must be met. All four are measured on the owner's machine over the PS_Completers scratch clone, each process fresh, and recorded under `docs/roadmap-3.0/validation/`.

**Import time does not regress** (`tools/Measure-CompleterStartup.ps1`, unchanged, with the 2.2.0 build as the baseline, extracted with `git archive v2.2.0 build`):

- **`LazyNoHash` `RatioToBaseline` at most 1.05.** This is the leg that pays the new work: every entry is parsed, so every strict entry is walked (question 2). Expected: 1281 ms plus 173 times about 0.2 ms, about 1.03 (milestone 2 benchmark, `LazyNoHash` 1281.1 ms; appendix A, 0.203 ms per walk). Under question 2's alternative A the expected ratio is 1.00.
- **`Lazy` at most 1.05 of 2.2.0's `Lazy` median**, measured as milestone 2 did, with a second run that puts the 2.2.0 build under test (the two runs are not interleaved, so this is a bound, not a gate; the gate is `LazyNoHash`). Expected at or below 1.00: the hash fast path does the same work, and loading the assembly replaces compiling the classes.
- A run above 1.05 is repeated up to four runs, all reported, and the median of the runs is the gate, as milestones 1 and 2 did.

**The grammar is fast** (new; both are gates):

- **`Test-CompleterScript` over the 173 scripts, in one process after a warm-up call, takes at most 0.30 of the same loop under the 2.2.0 build.** 2.2.0: 4477 ms on 2026-10-03. Expected: parse 355 ms plus walk 35 ms plus the command's own overhead per call, well under 1343 ms.
- **The compiled walk alone takes under 1 ms per script**, median over the 173 parsed scripts, timed by a stopwatch around the compiled entry point in a scratch harness. Expected about 0.2 to 0.4 ms (the shaped probe took 0.203; the real walk has more checks).

**Spot cost, reported, not gated:** `Import-Module` of the built module in ten fresh processes, 3.0.0 beside 2.2.0, medians side by side.

## 10. Release

Per decision 6, carried over from the 2.0 roadmap:

- The branch keeps `ModuleVersion = '2.2.0'` until the release-candidate commit, so the release-policy test holds throughout; checks that need `3.0.0` by name use a stamped copy, as milestones 1 and 2 did.
- The candidate commit stamps `ModuleVersion = '3.0.0'` and `Prerelease = 'rc1'`. Tag `v3.0.0-rc1`, PSGallery prerelease label `rc1`. It soaks in the owner's profile and in the PS_Completers CI, which installs CompleterActions with `-Prerelease` on every push to `master` and every pull request (`.github/workflows/conformance.yml` line 31 at `2c590c6`), so the first PS_Completers run after the candidate is on PSGallery runs the 173-script conformance gate and the set tests under 3.0.0-rc1 with no change to that repository.
- Stable `v3.0.0` is cut from the same code once the candidate has run without a defect; its release commit removes `Prerelease`. A defect means `rc2`, never a stable patch.
- **PS_Completers needs no migration.** The roadmap's "The PS_Completers tests and tools still call the old names, so that repo migrates first" is no longer true: on 2026-10-03, at `2c590c6` and on `feat/completer-set-package`, `tests/`, `tools/`, `README.md`, `.github/`, and `package/` contain no `CompleterRegistration`, `ManagedOnly`, or `DiscoveredOnly` (grep over `*.ps1`, `*.psd1`, `*.md`, `*.yml`). Its tests import with `-MinimumVersion 2.0.0` and `2.1.0`, its export tool requires `2.1.0`, and its package manifest requires `2.2.0`, all minimums that 3.0.0 satisfies. Edit 4 below records the roadmap correction.

### Roadmap edits the owner would make

This spec edits nothing in `docs/roadmap-3.0.md`. Under the recommendations, the owner would make these edits; each is conditional on the question named.

1. **The "Version-gated engine access" item** (question 1): restate as "the compiled layer owns engine access behind one seam; in 3.0.0 the seam carries the reflection path, and the engine-cmdlet path (milestone 2 spec, appendix A) ships in the first 3.x minor after a released engine carries the cmdlets". Decision 5 needs no edit: reflection stays the path for engines without the cmdlets, inside the compiled layer, which is what 3.0.0 ships.
2. **The "Compiled core" item** (question 2): its last sentence, "the grammar can run at import again without touching the ratio", becomes a new decision 8: "The strict grammar runs wherever a strict script is parsed for its targets, and at first tab. Decided <date>. Reopens 2.0 decision 5 on the strength of the compiled walk's cost (0.2 ms per script against 20 ms)." Exit criteria unchanged.
3. **The "Compiled core" item** (question 4): "and the lazy stub" is removed from the list of what the assembly holds, because the stub stays PowerShell.
4. **The "Remove the deprecated surface" item** (section 10): the sentence "The PS_Completers tests and tools still call the old names, so that repo migrates first" is replaced by "PS_Completers carries no old name (checked 2026-10-03), so nothing migrates before the candidate; its CI installs prereleases and is the soak signal".
5. **The "Where 2.0 leaves us" table and the milestone 3 introduction**: no edit is required; the owner may add the measured walk cost (25.9 ms per script on 2.2.0) beside the roadmap's "about 20 ms".
6. **When the candidate ships**: the status line and the milestone table, as for 2.2.0.

## 11. What stays exactly as in 2.2.0

- The 11 commands' parameters, parameter sets, records, warnings, errors, and verbose lines, except the one new registration error and the one new set-entry problem of question 2, each of which fires only for a non-conforming strict script that 2.2.0 would have registered and then failed at first tab.
- The set file schema, the hash rule, the fast path, the bulk registration path, `Export-CompleterSet`, `Test-CompleterSet` (including `-Name` and `PackageLayout`), `Import-CompleterSet -Name` and its two package rules, `New-CompleterScript` in full, `Reset-Completer` in full.
- The strict grammar's catalogue of findings, and the first-tab check.
- `Get-Completer`'s sort order and paging, the state model, the `Discovered` state, and the explicit target contract.
- The format file.
- The lazy stub, its neutrality, its failure path, and the `Failed` record with `LoadError`.
- Every private helper name that a test shims in module scope (section 3), so every test file not named in section 5 passes with no existing assertion changed, apart from the two line changes of section 6, the tracked-build test change of section 7, the one 2.2.0 test that imported an unhashed non-conforming entry as `Pending` (question 2, check 11), and the `Describe` blocks the plan adds.

## 12. Acceptance criteria

The commands use these values:

```powershell
$module = 'C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions'
$completers = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers'   # source of the scratch clone only
```

Run rules, carried over from milestones 1 and 2:

- Every numbered check runs in its own `pwsh -NoProfile` process against `$module` built from the branch (`Invoke-Build build`, which compiles first), and starts with this preamble:

  ```powershell
  Import-Module -Name "$module\CompleterActions.psd1" -Force
  if ((Get-Module CompleterActions).ModuleBase -ne $module) { throw 'wrong ModuleBase' }
  ```

- Pester runs in its own process, never in a process that also lints or builds. A changed assembly needs a new process (section 2).
- PS_Completers is read only through a scratch clone, `git -c core.longpaths=true clone $completers <scratch>\PS_Completers`. No check reads or writes `$completers` otherwise.
- "2.2.0 build" means `build/CompleterActions` extracted from tag v2.2.0 with `git archive`, never the gallery copy. It is all text, so the archive imports.
- A check that needs a module reporting `3.0.0` before the candidate commit uses a scratch copy of the branch build whose `.psd1` alone is stamped `3.0.0`.

### Roadmap exit criteria, expanded

1. **Surface.** `Get-Command -Module CompleterActions | Measure-Object` gives 11; `Get-Command -Module CompleterActions -CommandType Alias` gives nothing; the manifest's `FunctionsToExport` lists the 11 names of section 5 and `AliasesToExport` is `@()`. `Get-CompleterRegistration`, `Register-CompleterRegistration`, `Unregister-CompleterRegistration`, and the three `*Legacy` names each fail with `CommandNotFoundException`. For each of the 11 functions, the parameter names and parameter sets match the 2.2.0 build's.
2. **Public types.** At the prompt, outside the module, after `Import-Module` and one `Register-Completer -LiteralPath <conforming fixture> -Lazy`, so that a `Pending` record exists and no line below can pass on an empty pipeline:
   - `Get-Completer | Select-Object -First 1 | ForEach-Object { $_ -is [CompleterActions.CompleterRegistration] }` prints `True` (the roadmap's line), and `@(Get-Completer).Count` is at least 1;
   - `[CompleterActions.CompleterRegistration]::new()`, `[CompleterActions.ImportedCompleterRegistration]::new()`, `[CompleterActions.CompleterScriptFinding]::new()`, and `[CompleterActions.CompletionMatch]::new()` succeed, and each instance's `PSObject.Properties.Name` is exactly the 2.2.0 list for that type (`tests/CompleterClasses.Tests.ps1` holds the four lists), in order;
   - each instance's `PSObject.TypeNames` is `CompleterActions.<Type>`, `System.Object`;
   - `[enum]::GetNames([CompleterActions.CompleterState])` is `Active, Stale, Conflicted, Pending, Failed, Discovered` and `[int][CompleterActions.CompleterState]::Discovered` is 5; `[enum]::GetNames([CompleterActions.CompleterType])` is `Native, Parameter`;
   - on a new `CompleterRegistration`, `ParameterName`, `ScriptPath`, `LoadError`, and every other `string` property equal `''` and are not `$null` (a tightening over 2.x, where a bare `::new()` left them `$null`; section 2, difference 3); assigning `$null` to one leaves `''`; `ImportModule` and `ScriptBlock` are `$null` (question 3);
   - `Get-Completer -State Pending`, `Where-Object State -eq 'Pending'`, and `$_.State -eq 3` all select a `Pending` record; `ConvertTo-Json` writes `"State": 3` without `-EnumsAsStrings` and `"Pending"` with it;
   - `(Get-Command Get-Completer).OutputType.Name` is `CompleterActions.CompleterRegistration`, and the same for the other commands' 2.2.0 output types;
   - `Get-Completer | Format-Table` and `Test-CompleterScript <non-conforming> | Format-Table` render through the format file's views (the column headers of `CompleterActions.Format.ps1xml`).
3. **Engine floor.** `(Import-PowerShellDataFile $module\CompleterActions.psd1).PowerShellVersion` is `7.4`; `Test-ModuleManifest` passes; all eight CI legs are green.
4. **Release candidate.** `Find-PSResource CompleterActions -Repository PSGallery -Prerelease` lists `3.0.0-rc1` after the candidate release; `3.0.0` without a label is listed only after the soak (section 10). Checked on the release commits, before each tag: the built manifest reports `3.0.0` with `Prerelease` `rc1`, then `3.0.0` with no `Prerelease`.

### The compiled core

5. **The assembly.** `build/CompleterActions` holds `CompleterActions.Core.dll`; `(Import-PowerShellDataFile $module\CompleterActions.psd1).RequiredAssemblies` names it; after the preamble `[CompleterActions.CompleterRegistration].Assembly.GetName()` has `Name` `CompleterActions.Core` and `Version` `3.0.0.0`, and `.Assembly.Location` is under `$module`. The assembly's referenced `System.Management.Automation` version is 7.4.0.0 (`.Assembly.GetReferencedAssemblies()`). It exports no cmdlet: `Get-Command -Module CompleterActions -CommandType Cmdlet` is empty. `git ls-files` lists no `*.dll`, `*.pdb`, `bin/`, or `obj/` path.
6. **Fresh process, both layouts.** `Import-Module` of the source manifest after `Invoke-Build compile`, and of the built manifest, each succeed in a fresh `pwsh -NoProfile` and report the expected `ModuleBase` (the existing "imports the <Layout> module in a fresh profile-free process" test, kept). `Remove-Module` then `Import-Module -Force` in the same process succeeds.
7. **No reflection outside the compiled layer.** `Select-String -Path src\**\*.ps1 -Pattern 'GetField|GetProperty|BindingFlags|_context'` prints nothing. The three "Runtime capability probe" tests and "throws a clear error when runtime execution context internals are unavailable" in `tests/CompleterRegistration.Tests.ps1` pass unchanged, including the message assertions.

### The grammar

8. **Parity.** Under the 3.0.0 build and under the 2.2.0 build, in separate processes, `Test-CompleterScript` over this corpus gives byte-identical `ConvertTo-Csv` output of `Path, Line, Column, Severity, Construct, Message, Hint` with paths made relative: the 11 fixtures under `tests/Fixtures/ImportCompleterScript/`, every `.ps1` under `tests/Fixtures/LazyRegistration/`, `tests/Fixtures/CompleterSet/`, and `tests/Fixtures/CompleterSetPackage/`, the 14 scaffold outputs generated from `tests/Fixtures/NewCompleterScript/*.txt` through `New-CompleterScript -HelpText`, and the 173 scripts of the scratch clone. `tests/CompleterAuthorTooling.Tests.ps1` passes unchanged (`git diff main -- tests/CompleterAuthorTooling.Tests.ps1` prints nothing).
9. **Speed.** Section 9's two grammar gates: the 173-script `Test-CompleterScript` loop at most 0.30 of 2.2.0's, and the compiled walk under 1 ms per script median.
10. **Grammar at registration** (question 2). `Register-Completer -LiteralPath <non-conforming> -Lazy` fails with the terminating error `Completer script '<path>' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is.`, thrown unwrapped and followed by one line per `Error` finding, and registers nothing: `Get-Completer -CommandName <its target>` is empty afterwards. `Register-Completer -LiteralPath <the same> -Lazy -Trusted` registers it as `Pending`. Both under `-WhatIf` register nothing and the strict one still fails (the check runs where the targets are derived, before `ShouldProcess`).
11. **Grammar at import** (question 2). A set whose strict entry has no `Hash` and a non-conforming script: `Import-CompleterSet` fails with `Entry <n> ('<path>'): The script does not conform to the strict import grammar: line <l>, column <c> (<Construct>): <Message> Run Test-CompleterScript ...` and registers nothing; with `-SkipInvalid` it skips that entry with the `skipped` warning and registers the others. The same entry with a `Hash` matching its text imports as `Pending` without a problem (the fast path is not walked) and the stub fails at first tab as in 2.2.0. The same entry marked `Trusted = $true` imports without a problem. The set's verbose and summary lines for the other entries are 2.2.0's. Every test in `tests/CompleterSet.Tests.ps1` and `tests/CompleterLazyRegistration.Tests.ps1` passes, with the `Describe` blocks the plan adds, and with exactly one 2.2.0 test rewritten: "registers a strict entry that breaks the grammar as Pending and fails it with the findings on first tab" (`tests/CompleterSet.Tests.ps1` line 712), which asserted the behaviour question 2 replaces, now expects the `NonConforming` report. The fast-path case is the existing "never executes a non-conforming script whose entry took the fast path" (line 1984), unchanged.
12. **First tab unchanged.** A conforming script registered lazily, then edited into a non-conforming one before its first tab, moves to `Failed` with the findings in `LoadError` on that tab, and the press returns no completions and no error: the existing "marks a strict registration Failed when the script no longer conforms at first tab" (`tests/CompleterLazyRegistration.Tests.ps1` line 388) passes unchanged.

### The deprecated surface

13. **Nothing deprecated remains.** `Select-String -Path src\**\*.ps1, CompleterActions.psm1, CompleterActions.psd1, en-US\*.txt, README.md, .github\copilot-instructions.md, src\docs\CompleterActions\*.md -Pattern 'CompleterRegistrationLegacy|Write-CompleterDeprecationWarning|CompleterDeprecationWarningsIssued|ManagedOnly|DiscoveredOnly'` prints hits in `en-US\about_CompleterActions_Migration.help.txt` only (its removal table and its `MOVING FROM 1.x` section), each listed in the review note; `CHANGELOG.md` is outside the pattern's paths on purpose, because its history keeps the old names. `tests/CompleterDeprecation.Tests.ps1` and the three `*Legacy.ps1` files do not exist.

### Documentation

14. **Help content**, from the build: `Get-Help about_CompleterActions_Migration` resolves and its text contains `3.0`, the six removed names, `[CompleterActions.CompleterRegistration]`, `PowerShellVersion`, and `7.4`; `about_Completer_Sets` and `about_Import_Completers` state the registration and import check (question 2); `Get-Help Register-Completer -Full` and `Get-Help Import-CompleterSet -Full` resolve and mention the grammar at registration and import.

### Neutrality, surface, and gates

15. **PSReadLine.** The existing snapshot tests pass, and the `Get-PSReadLineKeyHandler -Bound -Unbound` snapshot is identical before and after `Import-Module`, `Import-CompleterSet` of the scratch clone's set, a first tab press through `TabExpansion2`, and `Test-CompleterScript` over one script, in one live session.
16. **Performance.** Section 9's four numbers are in `docs/roadmap-3.0/validation/milestone-3-benchmark.md` and the pull request body, with the pwsh version, the OS, the SDK version, and the commits.
17. **Suite and lint, in separate processes.** `pwsh -NoProfile -Command "Invoke-Build -Task build"` succeeds (and compiles); the two `Invoke-ScriptAnalyzer` calls print nothing; `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes; all eight CI legs are green, including the `Compile` step on each.
18. **Set compatibility both ways.** The scratch clone's `ps_completers.psd1` imports under 3.0.0 with the same `Key` list and `Pending` count as under 2.2.0 (173 entries and 362 registrations at `2c590c6`, the set de-duplicating the 366 script targets the benchmark's Eager leg counts; the assertion is equality). A set exported by 3.0.0 from those registrations, with `-Path` in the same clone folder as the 2.2.0 export, is byte-identical to the 2.2.0 export (`Export-CompleterSet` writes no comment header, so nothing is ignored).
19. **PS_Completers under the candidate.** After `3.0.0-rc1` is on PSGallery, the first PS_Completers CI run (any push or pull request) installs `3.0.0-rc1` through `-Prerelease` and passes its full suite with no change to that repository. Before the candidate, the same suite passes locally against the stamped branch build with `$env:PSModulePath` prepended and `ModuleBase` asserted.
20. **Surface comparison.** For each of the 11 functions, the parameter names, parameter sets, attributes relevant to binding (`Mandatory`, `ValueFromPipeline`, `ValueFromPipelineByPropertyName`, `Position`, `ParameterSetName`), and `OutputType` names are identical between the 2.2.0 build and the 3.0.0 build, read from `Get-Command` metadata in two processes.

## 13. Open questions for the owner

1. **Ship the engine-cmdlet path in 3.0.0, or hold it behind the seam?**
   - Why it is a question: the roadmap item says the cmdlets are the primary path inside the compiled layer. On 2026-10-03 PR #26680 is open, has no milestone, its last update is 2026-08-02, and no released or preview engine has the cmdlets, so the path can be built and tested only against a double of an unmerged API, in C#, invoking cmdlets that the 7.4.0 reference assembly does not know (so through `PowerShell.Create(RunspaceMode.CurrentRunspace)` and `PSObject` property reads, never a typed call). The owner held the same item in 2.2.0 for the same reason (milestone 2 spec, question 1).
   - Recommendation: hold. 3.0.0 moves all engine access into the compiled layer behind one seam that records its choice (section 3). The cmdlet path is appendix A of the milestone 2 spec, unchanged, and ships in the first 3.x minor after a released engine, preview or stable, carries the merged cmdlets. Roadmap edit 1 restates the item. Part of the same answer: the gate is cmdlet presence by module-qualified lookup, not an engine version number, now and when the path ships, because no version is known to carry the cmdlets and a presence check cannot be wrong about a backport. The preview CI leg's alarm test ("finds no Get-ArgumentCompleter or Unregister-ArgumentCompleter on this engine", `tests/CompleterRegistration.Tests.ps1`) stays and is the signal.
   - Alternative: build it now against the PR head's surface on a double, as appendix A's test strategy describes, in C#. It is invisible on every engine today and may need rework when the PR changes shape.
2. **Run the grammar at registration and import** (reopening 2.0 decision 5), **or keep it at first tab only?**
   - Recommendation: run it wherever a strict script is parsed for its targets (`Register-Completer -Lazy`, and `Import-CompleterSet` for entries that miss the hash fast path), keep the first-tab check, and leave hash-matched entries unwalked (section 4). Cost: about 0.2 ms per parsed script; zero on a fully hashed import. Benefit: a new or changed non-conforming script is refused at the point the author or the profile touches it, with the same findings `Test-CompleterScript` shows, instead of a silent `Pending` that fails at first tab.
   - Alternative A: keep decision 5 as it stands; the compiled walk then only speeds up `Test-CompleterScript`, `New-CompleterScript`, and the first tab. Roadmap edit 2 is then "decision 5 stands".
   - Alternative B: also have `Export-CompleterSet` run the grammar and write a `Hash` only for a conforming strict script, so a hash-matched entry is known to have conformed when its hash was written. It couples the hash to the grammar and changes `Export-CompleterSet` and `Test-CompleterSet`'s hash findings for non-conforming scripts; not recommended for this release.
3. **String properties default to `''` (the 2.0 promise) or `$null` (the .NET default)?**
   - Recommendation: `''`, enforced by the types (section 2, difference 3). The 2.0 migration guide told callers to replace `-eq $null` with `IsNullOrEmpty`; reverting breaks them again for no gain. `ImportModule` and `ScriptBlock` stay `$null`.
   - Alternative: `$null`, the .NET convention, documented as a 3.0 change. Every caller that followed 2.0's advice keeps working; one that tests `-eq ''` breaks.
4. **Compile the lazy stub, or leave it in PowerShell?**
   - Recommendation: leave it. The stub's only job is to call `Invoke-CompleterLazyStub`, which runs `Import-CompleterScript`, which is PowerShell; a compiled stub would be a `ScriptBlock` created from C# that calls back into a module-bound delegate, one more hop for the same work. The roadmap lists the stub among the assembly's contents; roadmap edit 3 removes it.
   - Alternative: a compiled `LazyStub` that holds the key and a delegate the module installs at import. No measurable benefit was found: creating a stub costs microseconds today.
5. **The `CompleterActions.Internal` namespace is public but not a contract.** PowerShell cannot call internal members, so the engine and grammar services must be `public`. The migration guide and the assembly's XML doc comments (the build generates them; plan, choice 1) say the namespace may change in any 3.x release.
   - Recommendation: accept. The alternative, a PowerShell-visible stable API for engine access, is a design of its own and nobody has asked for it.
6. **Track the built assembly in git, or build it in CI?**
   - Recommendation: do not track it (section 7). Binaries in git churn on every compile, byte-identical rebuilds across machines need `PathMap` and `DebugType none` and still depend on the compiler version, and the runner images carry the SDK. The tracked-build test keeps comparing text and checks only that the assembly was produced. Future benchmark baselines come from PSGallery or a rebuild of the tag.
   - Alternative: track it, keep `git archive <tag> build` importable, and accept binary diffs and a byte-comparison test that may flake across SDK versions.
7. **Target `net8.0` and reference `System.Management.Automation` 7.4.0.** Both follow from the 7.4 floor. The alternative, `netstandard2.0` with `PowerShellStandard.Library` 5.1.1, would also load on Windows PowerShell 5.1, which `CompatiblePSEditions = @('Core')` excludes anyway, and lacks the 7.x AST types the grammar visits.
   - Recommendation: `net8.0` and 7.4.0.
8. **`Severity` and `Construct` stay strings.** An enum would be cleaner but is a second contract change on `CompleterScriptFinding`, and `Construct` gains values by release.
   - Recommendation: strings in 3.0; revisit if a 4.0 ever happens.
9. **The removed names fail with PowerShell's own `CommandNotFoundException`**, not a module message, because a module cannot intercept a name it does not export. Recommendation: accept; the migration guide and the changelog carry the map.
10. **Roadmap edits 1 to 6** (section 10). Recommendation: as written, when the candidate ships.

## Appendix A. Measurements and how to reproduce them

Taken 2026-10-03 on the owner's machine, pwsh 7.6.6, .NET 10.0.12, dotnet SDK 10.0.401, Windows 11 Pro 10.0.26300. Scratch files lived under the session scratchpad and were not committed.

**Grammar cost under 2.2.0** (`build/CompleterActions` at `550bde9`, the 173 scripts of the PS_Completers working tree, read only):

```powershell
Import-Module ./build/CompleterActions -Force
$files = Get-ChildItem 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers' -Recurse -Filter *_completer.ps1
$sw = [Diagnostics.Stopwatch]::StartNew(); foreach ($f in $files) { $null = Test-CompleterScript -LiteralPath $f.FullName }; $sw.Stop()
# walk: 173 scripts, 4477 ms total, 25.9 ms/script
$sw = [Diagnostics.Stopwatch]::StartNew(); foreach ($f in $files) { $t = $null; $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $t, [ref] $e) }; $sw.Stop()
# parse only: 355 ms total, 2.1 ms/script
```

**The probe assembly.** A project with this shape built in 5 s with `dotnet build -c Release`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <AssemblyName>CompleterActions.Core</AssemblyName>
    <RootNamespace>CompleterActions</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="System.Management.Automation" Version="7.4.0" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

It held `CompleterState`, `CompleterType`, a four-property `CompleterRegistration`, and a `GrammarWalker : AstVisitor2` that visits every node, inspects the end block's top-level statements (command names against `Register-ArgumentCompleter`, `Set-StrictMode`, `Get-Variable`; command parameters; assignments), nested `Register-ArgumentCompleter` calls inside functions and script blocks, function overrides, `using` statements, and top-level traps, and collects findings with line and column.

**Compiled walk cost**, in one process after a warm-up call:

```text
compiled walk over 173 parsed scripts: 35 ms total, 0.203 ms/script, 0 findings
parse + compiled walk: 427 ms total, 2.47 ms/script
```

**Loading cost**, each in a fresh `pwsh -NoProfile`:

```text
Add-Type -TypeDefinition (one tiny class, first use): 407 ms
Add-Type -Path CompleterActions.Core.dll:              73 ms
[System.Reflection.Assembly]::LoadFrom(...):            2 ms
```

**Import cost of a toy module**, ten fresh processes each, `Import-Module <manifest>` timed with a stopwatch, sorted:

```text
21 22 22 22 22 23 24 24 24 41   RequiredAssemblies = lib/CompleterActions.Core.dll, one function using [CompleterActions.CompleterState[]]
33 33 34 34 35 35 36 48 63 63   the same function with the enum and class as PowerShell `enum`/`class` in the psm1
```

**Type behaviour from the prompt**, after importing the toy module:

```text
$r -is [CompleterActions.CompleterRegistration]   True
$r.State (bound from the string 'Pending')          Pending
$r.PSObject.TypeNames -join ','                     CompleterActions.CompleterRegistration,System.Object
(Get-Command Get-Thing).OutputType.Name             CompleterActions.CompleterRegistration
$r.Key -eq $null                                    True   (a C# string defaults to null; section 2 difference 3 initialises to '')
$r | ConvertTo-Json -Compress                       {"Key":null,"CommandName":null,"State":3,"ScriptBlock":null}
Remove-Module; Import-Module -Force                 succeeds
```

**Review probes (reviewer B, 2026-10-03)**, with a scratch assembly built with the plan's csproj flags: a `RequiredAssemblies` entry of `lib/CompleterActions.Core.dll` imports on Windows (7.6.6) and under WSL (7.6.5, .NET 10.0.11), `Location` under `lib`; a `[CompleterActions.CompleterState[]]` parameter binds `Pending` from a string and tab-completes; a setter `value ?? string.Empty` on a field initialised to `string.Empty` gives `''` after `$r.Path = $null`; `[CompleterActions.CompleterScriptFinding] @{ Path = 'x'; Line = 3; Message = 'm' }` converts; `Update-ModuleManifest` with the build task's keys preserves `RequiredAssemblies` and `PowerShellVersion = 7.4` when the dll is present, and both it and `Test-ModuleManifest` fail with `The specified RequiredAssemblies entry 'lib/CompleterActions.Core.dll' ... is invalid` when it is absent; a static-method exception reaches PowerShell as `MethodInvocationException` whose `Message` is `Exception calling "Create" with "1" argument(s): "..."`, and `$_.Exception.GetBaseException().Message` is the exact inner text; `Invoke-ScriptAnalyzer -Recurse` over a folder holding `.cs` files reports nothing and a `Release` `obj/` holds no `.ps1`; `TreatWarningsAsErrors` with `GenerateDocumentationFile` builds only when every public member, enum members included, has a doc comment; a `UnsafeTopLevelScript.ps1` run through `Test-CompleterScript` gives two `CommandAst` findings, at line 1 column 1 and line 1 column 12.

**Upstream and environment**, read the same day: `gh pr view 26680 --repo PowerShell/PowerShell --json state,mergedAt,updatedAt,milestone` gave `OPEN`, `null`, `2026-08-02T08:59:24Z`, `null`; `gh api repos/PowerShell/PowerShell/releases?per_page=6` listed `v7.7.0-preview.5`, `v7.6.6`, `v7.5.11`, `v7.4.20`, `v7.7.0-preview.4`, `v7.6.5`; `dotnet --list-sdks` listed 9.0.318 and 10.0.112 to 10.0.401; the `actions/runner-images` readmes for `ubuntu-24.04` and `windows-2025` list .NET SDK 8.0.131 to 10.0.401; `dotnet package search System.Management.Automation --exact-match` listed 7.4.0 to 7.4.7 and later.

**PS_Completers**, at `2c590c6` and `feat/completer-set-package`: `grep -rn 'CompleterRegistration\|ManagedOnly\|DiscoveredOnly' tests tools README.md .github package` printed nothing; `tests/Completers.Tests.ps1` imports with `-MinimumVersion 2.0.0` (line 31) and `2.1.0` (line 48); `tools/Export-CompleterSetFile.ps1` has `#Requires -Modules @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.1.0' }`; `.github/workflows/conformance.yml` line 31 installs `CompleterActions -Prerelease`.
