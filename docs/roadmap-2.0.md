# CompleterActions 2.0 Roadmap

Drafted: 2026-09-08
Baseline: 1.2.0, merge commit `4318821`
Live page: https://claude.ai/code/artifact/55cc8aca-46d5-4180-a763-c36c5505dd3a
Status (2026-09-21): all four milestones built; milestone 4 shipped as the 2.0.0-rc1 release candidate and is soaking before 2.0.0 stable.

| Milestone | Version | Status |
| --- | --- | --- |
| 1 Safety net | 1.3.0 | Shipped 2026-09-09, tag v1.3.0, PR #2 |
| 2 Author tooling and trust tiers | 1.4.0 | Shipped 2026-09-10, tag v1.4.0, PR #3 |
| 3 Lazy loading and completer sets | 2.0.0-preview1 | Shipped 2026-09-11, tag v2.0.0-preview1, PR #4; lazy 1316 ms vs eager 7063 ms, ratio 0.19 |
| 4 Breaking surface and release | 2.0.0-rc1, then 2.0.0 | Candidate shipped 2026-09-21, tag v2.0.0-rc1, PR #6; stable after soak |

Four milestones from the 1.2.0 baseline to a major release. The first two ship on the 1.x line so users get value early; the breaking surface lands last and all at once.

## Where 1.2.0 leaves us

| Area | State |
| --- | --- |
| Importer | Closed top-level grammar; 27 of 169 personal scripts had to adapt |
| State model | Managed records reconcile against the live runtime with Active, Stale, Conflicted |
| Registration | Per-target transaction with rollback |
| Engine access | Reflection into a private context field and two internal dictionaries |
| Tests | 91 Pester cases, hermetic build check, PSScriptAnalyzer clean |
| Release | Manual: tag, Publish_build from a user-scope key, GitHub release by hand |

Public commands: 4. Private helpers: 25. Source: about 3,500 lines.

## Milestone 1: Safety net (1.3.0, additive)

**Shipped 2026-09-09 as v1.3.0** (PR #2, merge f12c878, release commit 12cfd14). All four items landed; the release workflow published to PSGallery from a single tag push.

Small, low-risk work that de-risks everything after it. The reflection dependency is the module's single biggest liability and nothing else should be built on top of it until it fails loudly instead of mysteriously.

- **Capability probe at import** (infra). Verify the private context field and both completer dictionaries resolve. If the engine shape changed, throw one clear message naming the PowerShell version instead of failing deep inside a Get call.
- **CI matrix** (infra). GitHub Actions on Windows and Ubuntu across 7.4 LTS, 7.5, 7.6, and preview. The build script's path-portability fix has never actually run off Windows.
- **Tag-triggered publish** (infra). Move the gallery key to a repository secret. A pushed v-tag runs `release_check`, then `Publish_build`, then creates the GitHub release. Removes the key-expiry worry from the desk.
- **Changelog** (docs). Tracked CHANGELOG.md, backfilled from 1.1.0. The 2.0 migration notes will live here.

Exit criteria:

```powershell
# green on every matrix leg, and the release is one git push
git tag v1.3.0 && git push origin v1.3.0
Find-PSResource CompleterActions -Repository PSGallery   # 1.3.0 within minutes
```

## Milestone 2: Author tooling and trust tiers (1.4.0, additive)

**Shipped 2026-09-10 as v1.4.0** (PR #3, merge 25e9388, release commit 9e1b8b5). All four items landed. Both exit criteria were verified before tagging: zero Error findings across the 169 personal scripts, and the git completion check returned checkout, cherry, and cherry-pick. One review finding was fixed before merge: Test-CompleterRegistration accepts exactly one resolved target per call.

The strict importer is right for untrusted files and wrong for a personal completer repo. Give authors a linter so they learn about problems before an import fails, and give owners an explicit way to say "this is my code, run it".

- **Test-CompleterScript** (feature). Public wrapper over the AST validator. Returns structured findings with line, construct type, and a fix hint rather than throwing. The PS_Completers repo can run it as a Pester conformance test.
- **Test-CompleterRegistration** (feature). Run TabExpansion2 for a given input against a registered target and return the completion matches. This is the verification step every fix in September did by hand.
- **Trusted import switch** (feature). Import-CompleterScript gains an opt-in switch that skips the grammar and dot-sources the file as-is. Strict stays the default. Two documented contracts instead of one grammar that keeps growing exceptions.
- **Author guide** (docs). Rewrite about_Import_Completers around the two tiers, with the three import-safe shapes from the September script fixes as worked examples.

Exit criteria:

```powershell
Get-ChildItem ~\Completers -Recurse -Filter *.ps1 | Test-CompleterScript | Where-Object Severity -eq Error
# empty for the 169 personal scripts
Test-CompleterRegistration -CommandName git -Native -InputText 'git che'
# returns checkout, cherry, cherry-pick
```

## Milestone 3: Lazy loading and completer sets (2.0.0-preview1, additive)

**Shipped 2026-09-11 as v2.0.0-preview1** (PR #4, merge bc66619, release commit 3f6f89c). All six items landed. Startup benchmark over the 169-script set, five samples each: eager median 7063 ms, lazy 1316 ms, ratio 0.19 against the 0.25 target. Grammar timing changed per decision 5 below.

This is the reason 2.0 exists. A profile that imports 169 scripts pays parse, validate, dynamic module, and dot-source for each one on every session start. Register a stub instead and load the real completer on the first tab press.

- **Lazy registration** (feature). Register-Completer accepts a script path with a lazy switch. The runtime entry is a small stub that imports the script on first invocation, replaces itself with the real script block, then delegates. Get reports state Pending until then.
- **Completer sets** (feature). A psd1 or JSON file listing scripts and their targets. Export-CompleterSet writes one from the current managed registrations; Import-CompleterSet registers everything lazily. The profile becomes one line.
- **Set validation** (feature). Import-CompleterSet reports missing files and stale targets up front instead of failing at first tab, and honours the trust tier per entry.
- **Failed-load handling** (feature). If a stub's script fails to import on first tab, the press returns no completions, the record moves to state Failed with the error message, and Get-Completer surfaces it. The prompt is never interrupted.
- **PSReadLine neutrality** (constraint). Lazy loading must not change how PSReadLine behaves. The stub runs inside the ordinary completer call, never hooks key handlers, never replaces TabExpansion2, and never touches PSReadLine options or prediction. A Failed stub must leave PSReadLine's own fallback completion working exactly as it would with no completer registered.
- **Startup benchmark** (perf). A tracked measurement of profile import time for the 169-script set, eager versus lazy, so the win is a number in the changelog rather than a claim.

Exit criteria:

```powershell
Import-CompleterSet ~\Completers\completers.psd1     # replaces the Get-ChildItem pipeline in the profile
Measure-Command { pwsh -NoProfile -c '. $PROFILE' }   # target: under 25% of the 1.2.0 eager time
git che<Tab>   # first press loads the script, later presses hit the real completer
Get-PSReadLineKeyHandler | Where-Object Function -like '*Complete*'   # identical before and after Import-CompleterSet
Get-Completer -State Failed   # shows the broken script and its error; tab on that command still gets PSReadLine's default completion
```

## Milestone 4: Breaking surface and release (2.0.0-rc1 then 2.0.0, breaking)

Every incompatible change lands in one milestone, with aliases for the old names, so there is exactly one migration for users to make.

**Candidate shipped 2026-09-21 as v2.0.0-rc1** (PR #6, merge 92b73f2, release commit 6b29344). All six items landed plus the class model, the exported legacy wrappers, and the migration topic; 234 Pester tests, eight CI legs green, the 169-script set imports untouched, PSReadLine snapshots identical, the PS_Completers gate 174 of 174. Two adversarial review rounds confirmed 19 findings, all fixed before merge. Stable 2.0.0 waits for the soak.

The milestone ships twice. The first tag is `v2.0.0-rc1` (PSGallery prerelease label `rc1`), so the breaking surface can soak in the user's profile and in the PS_Completers conformance CI before anything is promoted. Only when the candidate has run without a defect does the same code go out as `v2.0.0` stable; a defect found in the candidate ships as `rc2`, never as a stable patch. Decided 2026-09-21.

- **Rename the nouns** (breaking). Register-Completer, Get-Completer, Unregister-Completer. The old CompleterRegistration names remain as aliases until 3.0.
- **Explicit target contract** (breaking). Drop the colon and path-separator inference for key-only input. A target is a typed object or explicit CommandName plus Native or ParameterName. Keys become output-only identifiers.
- **One filter parameter** (breaking). Replace ManagedOnly and DiscoveredOnly with a single State parameter accepting Active, Stale, Conflicted, Pending, Failed, Discovered, with tab completion.
- **Typed output** (breaking). PowerShell classes for registration and import records, with OutputType attributes on every command, so State is a real enum consumers can bind to.
- **Promised sort order** (feature). CompleterType, then CommandName, then ParameterName. Paged results become stable across runtime mutations.
- **Migration guide** (docs). Old name to new name, key-only calls to explicit targets, the two Only switches to State. Shipped in the changelog and as an about topic.
- **Release candidate** (release). Tag `v2.0.0-rc1` first; the user's profile and the PS_Completers CI run against it. Promote to `v2.0.0` stable only after the candidate has soaked with no defects; any fix means another candidate.

Exit criteria (met for the candidate; the stable tag is the last one):

```powershell
Get-Completer -State Conflicted        # typed records, stable order
Get-CompleterRegistration -ManagedOnly # alias still works, emits a one-time deprecation notice
# the 169-script set imports through Import-CompleterSet with zero edits from milestone 3
Find-PSResource CompleterActions -Repository PSGallery -Prerelease   # 2.0.0-rc1 listed; 2.0.0 stable only after the candidate soaks
```

## Command rename map

Aliases keep the old names working for the whole 2.x line. Nothing is removed until 3.0.

| Today | 2.0 | Notes |
| --- | --- | --- |
| Register-CompleterRegistration | Register-Completer | Gains a lazy switch and a path parameter set |
| Get-CompleterRegistration | Get-Completer | ManagedOnly and DiscoveredOnly fold into State |
| Unregister-CompleterRegistration | Unregister-Completer | AllowUnmanaged unchanged |
| Import-CompleterScript | Import-CompleterScript | Unchanged name; gained the trusted switch in 1.4.0 |
| Test-CompleterScript | Test-CompleterScript | Shipped in 1.4.0 |
| Test-CompleterRegistration | Test-CompleterRegistration | Shipped in 1.4.0 |
| (new) | Import-CompleterSet, Export-CompleterSet | New in 2.0 preview |

## Decisions

Locked on 2026-09-08. These settle the shape of milestones 3 and 4; reopen one only with a reason worth a changelog entry.

1. **Set files use a per-entry trust flag, strict by default.** An entry may declare `Trusted = $true` to be dot-sourced without the grammar. Entries without it go through the strict importer. A set that points at a script from elsewhere stays safe. Affects: milestone 3, set file schema and Import-CompleterSet.
2. **A lazy stub that fails to load returns no completions and marks the record Failed.** The error is kept on the record and shown by Get-Completer. Added rule: nothing the module does may alter PSReadLine's default behaviour. The stub runs inside the normal completer call and never hooks key handlers, replaces TabExpansion2, or changes PSReadLine options. After a failure, tab on that command behaves exactly as if no completer were registered. Affects: milestone 3, lazy registration and the PSReadLine neutrality constraint.
3. **Keys are output-only. Hand-typed key strings are no longer accepted.** Key remains on every record and binds by property name when a record is piped back into Get, Register, or Unregister. Typed input uses CommandName with Native or ParameterName. The colon and path-separator inference is deleted. Affects: milestone 4, explicit target contract and the migration guide.
4. **File an upstream issue for a public completer-enumeration API; do not block on it.** The capability probe shipped in 1.3.0. If the engine gains an API, a later release swaps the reflection out behind the same commands. Affects: milestone 1, capability probe; tracked as a follow-up, not a milestone item.
5. **The strict grammar runs when a lazy script loads, not when a set imports.** Decided 2026-09-11. Import-CompleterSet parses each strict entry once to derive its targets and rejects what it can see statically: missing or non-parsing files, non-literal targets, trusted entries without targets, and conflicts between entries. The full conformance walk runs through Import-CompleterScript at first tab, immediately before the script executes, so a non-conforming script is never run and moves to Failed with the findings in LoadError. Reason: the walk costs about 20 ms per script against under 2 ms to parse; at import time it added about 3.4 s to a 1.3 s lazy import of the 169-script set, taking the ratio from 0.19 to about 0.67. The check before execution is the one that guarantees safety, since a file can change between import and first tab. Early feedback comes from Test-CompleterScript, which the PS_Completers repo runs as a Pester gate locally and in CI. Affects: milestone 3, Import-CompleterSet and about_Completer_Sets.
6. **2.0.0 ships as a release candidate before it ships as stable.** Decided 2026-09-21. Milestone 4 is tagged `v2.0.0-rc1` first and stays a PSGallery prerelease while it soaks in the user's profile and in the PS_Completers conformance CI. The stable `v2.0.0` tag is cut from the same code once the candidate has run without a defect; a defect produces `rc2` rather than a stable patch. Reason: the milestone changes every public noun and the target contract at once, and the 1.4.0 stable line should keep serving profiles until the migration is proven. Affects: milestone 4, release order and the changelog headings.
