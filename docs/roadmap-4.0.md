# CompleterActions 4.0 Roadmap

Drafted: 2026-10-12
Baseline: 3.0.0, release commit `abac592`, tag v3.0.0
Live page: https://claude.ai/artifact/RbFmmJC6uMjo19eZqVTtzy
Status (2026-10-12): proposed. No decisions locked. Milestones 1 and 2 start on a trigger; milestone 3 is gated on a shipped engine with the completer cmdlets and has no date.

| Milestone | Version | Status |
| --- | --- | --- |
| 1 Authoring, second pass | 3.1.0-preview1, then 3.1.0 | Proposed, additive; starts when the next batch of completers is written by hand or PS_Completers takes a contributor |
| 2 Diagnostics and native generators | 3.2.0-preview1, then 3.2.0 | Proposed, additive; starts when a completer misbehaves without an obvious cause, or the next tools to add ship their own `completion powershell` |
| 3 Engine floor and the end of reflection | 4.0.0-rc1, then 4.0.0 | Proposed, breaking; gated on a stable engine exporting `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter`, and on 7.4 leaving support (2026-11-10) |

Three milestones from the 3.0.0 baseline. The first two are additive and ship on the 3.x line as real use calls for them. The major release has exactly one reason to exist: dropping the reflection path once a shipped engine carries the completer cmdlets. Until that engine ships, 4.0 has no date.

## Where 3.0 leaves us

Checked against the repository and the owner's machine on 2026-10-12.

| Area | State |
| --- | --- |
| Surface | 11 functions, 0 aliases. Records are public .NET types under the `CompleterActions` namespace, so nothing is left to deprecate |
| Engine access | Reflection behind one compiled seam. The engine-cmdlet path is an accepted contract (milestone 2 spec, Appendix A) with no shipped code |
| Upstream | PR #26680 (Get- and Unregister-ArgumentCompleter) is open with no milestone as of 2026-10-12. 3.0 decision 5 says to revisit the reflection path for 4.0 |
| Engine floor | Manifest requires 7.4; the core targets net8.0 against System.Management.Automation 7.4.0. 7.4 LTS leaves support on 2026-11-10; 7.6 is the current LTS |
| Set import | Every strict entry is opened and hashed on each import (174 of 174 in PS_Completers). Warm, about 50 ms for the hashing and about 1 s for the whole import in a fresh process; cold, each file pays disk, cloud-filter and antivirus latency, and the owner sees up to 10 s |
| Scaffold | `New-CompleterScript` seeds subcommands only. No option seeding, no companion markdown, and `-Name` has no version selection; each was deferred as a non-breaking addition |
| Diagnostics | The only way to exercise a registered completer is to press Tab. Nothing times it, traces its load, or shows what it returned |
| Tests and CI | 644 Pester cases across 13 files, eight CI legs (Windows and Ubuntu, 7.4, 7.5, 7.6 and preview), analyzer clean. Empty `src/Classes` and `src/DSCResources` folders remain |

Public commands: 11. Private helpers: 59. Source: about 8,500 lines of PowerShell and 1,350 lines of C# in 11 files.

## Milestone 1: Authoring, second pass (3.1.0, additive)

Milestone 2 of the 3.0 roadmap shipped the scaffold and installable sets with three deferrals written into its spec. Each was deferred as a non-breaking addition, so this milestone closes them, together with the one maintenance gap the hash scheme left open.

Trigger: the owner writes the next batch of completers by hand, or PS_Completers takes a contributor. Not scheduled on its own.

- **Option seeding in New-CompleterScript** (feature). The scaffold reads option lines from the same help probe that feeds the subcommand table and seeds a literal option table for them: `-x, --long <ARG>`, `--long=VALUE`, and `/X` layouts. Option-only tools such as rg and du stop getting an empty table. The milestone 2 spec deferred this with "revisit with real use"; its help-probe corpus is the test fixture.
- **New-CompleterScript -Documentation** (feature). Writes the companion markdown beside the script with the one heading the PS_Completers corpus already shares, "What it completes", and nothing else. Off by default.
- **Version selection for Import-CompleterSet -Name** (feature). `-MinimumVersion` and `-RequiredVersion`, with the same first-root-then-highest-version rule when neither is given. A pinned profile stops needing `-LiteralPath`.
- **Update-CompleterSet** (feature). Rehashes the entries `Test-CompleterSet` reports as changed and rewrites only those `Hash` lines, leaving the rest of the file byte-identical. Today the fix for drift is a full `Export-CompleterSet`. Open question: should it also add entries for unlisted scripts, or only report them? Recommendation: report only; adding an entry is an authoring decision.

Exit criteria:

```powershell
New-CompleterScript -CommandName rg -Path .\rg_completer.ps1 -PassThru | Test-CompleterScript   # empty, and the script carries an option table
Import-CompleterSet -Name PS_Completers -MinimumVersion 1.1.3                                # resolves the installed 1.1.3 or newer; errors below it
Test-CompleterSet .\completers.psd1 | Update-CompleterSet; Test-CompleterSet .\completers.psd1   # second call empty; git diff shows only Hash lines
```

## Milestone 2: Diagnostics and native generators (3.2.0, additive)

Two gaps that only show up once a set is large: nothing in the module can tell the owner which completer is slow or broken, and a growing class of tools can generate their own completion script, which the module cannot yet manage.

Trigger: a completer in the owner's profile misbehaves and the cause is not obvious from `Get-Completer`, or the next ten tools to add all ship a `completion powershell` subcommand.

- **Measure-Completer** (feature). Invokes a registered completer with a synthetic word and AST for a given command line, the way the engine would, and returns one record per target: elapsed time, result count, the load path taken (Active, or Pending with the load time shown separately), and any error the completer threw. Same target contract as `Unregister-Completer` and `Reset-Completer`. Never hooks key handlers or touches PSReadLine.
- **Register-Completer -FromGenerator** (feature). Runs a tool's own completion generator, for example `rustup completions powershell` or `gh completion -s powershell`, captures the script block it defines, and registers it as a managed record with the generator command recorded on it. Rollback, `Get-Completer`, and `Unregister-Completer` treat it like any other registration. The generated script is not held to the strict grammar, so it registers in the trusted tier. Open question: lazy or eager? Recommendation: eager only in the first cut.
- **Opt-in unverified import** (perf). `Import-CompleterSet -SkipHashCheck` takes each entry's `Hash` and `Targets` at face value and opens no script file, so a cold import stops paying per-file latency. The first-tab grammar check stays as the safety net (3.0 decision 8), and a changed script is caught there. Off by default. Open question: is this wanted at all? The owner said on 2026-10-12 that the current cold import is acceptable. Recommendation: carry it as a candidate and ship it only if the benchmark shows the cold case drops by more than half.

Exit criteria:

```powershell
Measure-Completer -CommandName git | Sort-Object ElapsedMilliseconds -Descending   # one record per target with elapsed, count, state, and error
Register-Completer -CommandName rustup -FromGenerator 'rustup completions powershell' -PassThru   # Active managed record; Unregister-Completer removes it
Import-CompleterSet -Name PS_Completers -SkipHashCheck   # opens no *_completer.ps1 (Process Monitor or strace shows none); only if the item ships
```

## Milestone 3: Engine floor and the end of reflection (4.0.0-rc1 then 4.0.0, breaking)

The one breaking change this roadmap proposes. 3.0 moved engine access behind a compiled seam and kept reflection as the path for engines without the cmdlets. 4.0 removes that path and makes the engine that has the cmdlets the floor. Nothing in the public command surface changes.

Gate: both must hold before the branch is cut. A released engine, stable not preview, exports `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter`; and 7.4 has left support (2026-11-10) so the floor can rise without dropping a supported LTS. Until then the engine-cmdlet path ships additively in a 3.x minor the day an engine has it, per 3.0 decision 3.

- **Remove the reflection path** (breaking). The compiled seam carries only the cmdlet path. The import-time capability probe, the `EngineIntrinsics` field walk, and their tests go. The failure mode on an old engine becomes a plain manifest version error instead of a probe message.
- **Engine floor at the first version with the cmdlets** (breaking). `PowerShellVersion` in the manifest rises to that version; the CI matrix drops the legs below it and keeps preview. If that version is 7.6, the floor is the current LTS.
- **Retarget the core assembly** (breaking). The System.Management.Automation reference and the target framework move to the floor engine's runtime. Public type names and property order stay as 3.0 defined them.
- **Lazy stub in C#, measured first** (perf). The stub stays a PowerShell script block unless the fourth benchmark edition shows the stub's own dispatch, not the import it triggers, is a measurable share of first-tab latency. A candidate, not a commitment.
- **Migration guide** (docs). `about_CompleterActions_Migration` rewritten for 3.x to 4.0: the new floor and what a profile on an older engine sees. No command renames to document.
- **Release candidate** (release). Tag `v4.0.0-rc1` first; promote to `v4.0.0` only after the candidate has soaked in the owner's profile and the PS_Completers CI without a defect; a defect means rc2.

Exit criteria:

```powershell
Get-Command Get-ArgumentCompleter, Unregister-ArgumentCompleter   # both engine cmdlets, no module in the Source column
Select-String -Path src\Core\Engine\*.cs -Pattern 'GetField|BindingFlags'   # no matches
Get-Command -Module CompleterActions | Measure-Object   # 11 from 3.0 plus whatever 3.1 and 3.2 added; nothing removed
Find-PSResource CompleterActions -Repository PSGallery -Prerelease   # 4.0.0-rc1 listed; 4.0.0 stable only after the soak
```

## Considered and parked

| Idea | Status | Why |
| --- | --- | --- |
| Completion cache helper in the core assembly (typed cache with TTL for completers that call slow tools) | parked | No completer in the 174-script set asks for it yet; a set author can carry a cache in the script. Revisit when Measure-Completer shows a slow completer whose cost is the tool call |
| Anything that hooks PSReadLine, key handlers, or TabExpansion2 | out | PSReadLine neutrality is a locked 2.0 decision. Measure-Completer calls the completer directly for this reason |
| Trusted-by-default entries in PS_Completers to skip the hash check | out of scope | A set-file decision in the PS_Completers repository, not a module change. The opt-in unverified import in milestone 2 covers the same cost from the module side |
| Removing the empty `src/Classes` and `src/DSCResources` folders | any release | Housekeeping; bundle into the next branch that touches the build script |

## Proposed decisions

None are locked. Each is written the way the 2.0 and 3.0 decisions were, so accepting them is one sentence from the owner and reopening one later needs a reason worth a changelog entry.

1. **4.0 waits for its trigger and has no date.** The major exists to remove reflection. Cutting it before a stable engine has the cmdlets would mean shipping a floor nobody can run, and cutting it before 7.4 leaves support would drop a supported LTS. Affects: milestone 3 and every release between now and then.
2. **Additive work ships on 3.x minors, preview before stable.** Carries 3.0 decision 7. Milestones 1 and 2 go to PSGallery as preview1 first and soak in the owner's profile and the PS_Completers CI. Affects: milestones 1 and 2, release recipe and changelog headings.
3. **Milestones 1 and 2 start on a trigger, not a date.** Each item was deferred with "revisit with real use". A roadmap item without a user is a cost without a benefit; each milestone names what has to happen for it to start. Affects: milestones 1 and 2.
4. **The verified import stays the default.** 3.0 decisions 1 and 8 put the hash in the set file and the grammar at import. Any cheaper import is a per-call opt-in that changes nothing for a profile that does not ask for it. Affects: milestone 2, Import-CompleterSet.
5. **Generator-produced completers register in the trusted tier.** The strict grammar exists for hand-written scripts in a set. A script a tool emits for itself is the tool's contract, and holding it to the grammar would reject most of them for no gain. Affects: milestone 2, Register-Completer.
6. **4.0.0 ships as a release candidate before it ships as stable.** Carried from 3.0 decision 6 and 2.0 decision 6 without change. Affects: milestone 3, release order.
