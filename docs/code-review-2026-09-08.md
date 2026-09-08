# CompleterActions code review

Date: 2026-09-08  
Reviewed commit: `db7da4b7936bd856b60ffcc882376010601fa45b` (`main`)  
Review mode: read-only product-code review; this document is the only intended repository change

## Executive summary

The module has a clear four-command surface, a consistent `src/Public` and
`src/Private` split, structured output, appropriate `ShouldProcess` use at the
public boundary, extensive comment-based help, and meaningful runtime tests.
The build and packaged-module smoke test succeed on PowerShell 7.6.5, and
PSScriptAnalyzer reports no source or test findings.

The review found eight actionable issues:

| Severity | Count |
| --- | ---: |
| High | 3 |
| Medium | 4 |
| Low | 1 |

The highest-priority work is to close the importer's executable-AST gap, make
registration changes transactional, and reconcile module-managed state with the
live runtime before reporting, reusing, or removing a registration.

## Scope and method

The review covered the root module and manifest, all public and private source
files, Pester suites and fixtures, build/release logic, generated and conceptual
help, formatting data, repository instructions, and recent release metadata.

The work was split deliberately:

- A Luna reconnaissance pass mapped the architecture, risks, tests, and candidate
  defects across the repository.
- A Terra PowerShell review independently evaluated the candidates, rejected
  unproven items, assigned severity, and proposed remediation directions.
- The primary reviewer inspected the implementation, ran the standard toolchain,
  and reproduced the important runtime findings in isolated PowerShell processes.

## Findings

### CA-001 — High — Import validation permits executable .NET side effects

`Test-CompleterScriptAst` allows any top-level `IfStatementAst` or `PipelineAst`,
then limits only `CommandAst` nodes to a short command allowlist. Static and
instance method calls are expression ASTs rather than `CommandAst` nodes, so they
are not rejected. The accepted file is subsequently dot-sourced inside a dynamic
module.

Evidence:

- [`Test-CompleterScriptAst.ps1`](../src/Private/Test-CompleterScriptAst.ps1#L171)
  permits broad top-level statement categories at lines 171-178.
- The command allowlist at lines 181-225 inspects only `CommandAst` nodes.
- [`Import-CompleterScriptDefinition.ps1`](../src/Private/Import-CompleterScriptDefinition.ps1#L77)
  executes the validated file at line 77.
- [`Import-CompleterScript.ps1`](../src/Public/Import-CompleterScript.ps1#L10)
  describes the accepted shape as safe and excludes top-level setup and external
  execution at lines 10-29.

Reproduction on PowerShell 7.6.5:

```text
Input top-level expression:
[System.Environment]::SetEnvironmentVariable(
    'COMPLETERACTIONS_REVIEW_PROBE', 'executed', 'Process')

Observed after Import-CompleterScript:
SideEffect    : executed
ImportedCount : 1
RuntimeBefore : 0
RuntimeAfter  : 0
```

The runtime completer table remained untouched, but arbitrary code still ran in
the importing process. That violates the documented validation boundary and can
mislead callers into treating an untrusted completer script as safe to inspect.

Recommendation: define a closed top-level grammar rather than broad allowed
statement categories. Reject invocation/member/type expressions, assignments,
and other executable expressions outside function bodies and literal registered
script blocks. Narrowly validate every permitted `if` shape. Add adversarial tests
for static methods, instance methods, subexpressions, type expressions, and side
effects in conditions and statement bodies.

### CA-002 — High — Registration failures leave partially committed runtime state

`Register-CompleterRegistration` writes the live runtime entry before it creates
and stores the managed record. The catch path does not roll back a fresh
non-`Force` registration. During `-Force`, it restores the old runtime only when
no runtime entry exists, so the newly inserted entry causes restoration to be
skipped.

Evidence:

- [`Register-CompleterRegistration.ps1`](../src/Public/Register-CompleterRegistration.ps1#L158)
  removes existing state at lines 158-169, writes the new runtime at line 171,
  and stores managed state at lines 173-174.
- Its recovery logic at lines 181-205 is gated by `-Force` and tests only whether
  any runtime entry exists, not whether that entry is the old or new value.

Fault-injection results:

```text
Fresh registration followed by forced managed-state failure:
Error         : Failed to register ... forced managed-state failure
RuntimeCount  : 1
RuntimeScript : "new"

Forced replacement followed by the same failure:
Error         : Failed to register ... forced managed-state failure
RuntimeScript : "new"
ManagedCount  : 0
```

The command reports failure while leaving a live unmanaged completer behind. In
the replacement case, the previous registration is also lost.

Recommendation: implement a per-target transaction. Snapshot the exact old
runtime and managed values, prepare the new record before mutation, and on any
post-mutation failure explicitly remove or replace the new runtime value before
restoring the prior runtime and managed state. Report rollback failure separately
from the initiating error. Add fault-injection coverage for fresh registration,
replacement, runtime-write failure, and managed-write failure.

### CA-003 — High — Stale managed state hides and removes an external replacement

If another module or caller overwrites a target using the built-in
`Register-ArgumentCompleter`, CompleterActions retains its old managed record.
The normal query path prefers that stale record, idempotent registration checks
only the stale script text, and unregistering deletes the current external
runtime entry without applying the `-AllowUnmanaged` safety gate.

Evidence:

- [`Get-CompleterRegistration.ps1`](../src/Public/Get-CompleterRegistration.ps1#L157)
  inserts managed records first and suppresses discovered conflicts at lines
  157-191.
- [`Register-CompleterRegistration.ps1`](../src/Public/Register-CompleterRegistration.ps1#L130)
  collects the runtime record but treats matching managed `ScriptText` as
  authoritative at lines 130-150.
- [`Unregister-CompleterRegistration.ps1`](../src/Public/Unregister-CompleterRegistration.ps1#L126)
  applies `-AllowUnmanaged` only when no managed record exists, then removes the
  current runtime value at lines 126-159.

Reproduction:

```text
1. Register script "old" through CompleterActions.
2. Overwrite the same target directly with script "external".

ReportedSource         : Managed
ReportedScript         : "old"
ActualBefore           : "external"
ReusedScript           : "old"
ActualAfterIdempotent  : "external"
RuntimeAfterUnregister : 0
```

The reported object does not describe active behavior, re-registration silently
does nothing, and unregistering crosses the module's explicit unmanaged-removal
boundary.

Recommendation: consider a record managed only while its live runtime value
matches the stored identity/content. On mismatch, expose a stale/conflicted state,
make ordinary registration fail with an actionable reconciliation message, and
require `-AllowUnmanaged` or explicit replacement before deleting the live value.
Cover direct overwrite and direct removal between every managed lifecycle step.

### CA-004 — Medium — Colon-based type inference misclassifies native drive paths

Key-only inputs infer registration type solely from whether the key contains a
colon. That is ambiguous on Windows because a valid native command path contains
a drive-letter colon. A native path can collide with the normalized key for a
command-parameter target.

Evidence:

- [`Resolve-CompleterTargetList.ps1`](../src/Private/Resolve-CompleterTargetList.ps1#L50)
  treats every colon-bearing key as a parameter target at lines 50-61.
- [`Resolve-CompleterInputObject.ps1`](../src/Private/Resolve-CompleterInputObject.ps1#L127)
  repeats the heuristic at lines 127-162 when no explicit native indicator is
  present.

Observed for key `C:\tools\review-probe.exe`:

```text
IsNative      : False
CommandName   : C
ParameterName : \tools\review-probe.exe
```

Recommendation: do not infer type from the delimiter for ambiguous key-only
input. Require an explicit native/type indicator, or resolve against both runtime
dictionaries and reject collisions. Document the ambiguity and add drive-qualified
native-path tests for registration, lookup, and removal.

### CA-005 — Medium — The build is Windows-path dependent

The manifest declares PowerShell Core compatibility, but the build derives the
module name by splitting on a backslash and constructs most paths with literal
backslashes. Those paths do not represent the same filesystem hierarchy on
non-Windows PowerShell.

Evidence:

- [`CompleterActions.build.ps1`](../CompleterActions.build.ps1#L13) uses
  `$PSScriptRoot.Split("\")[-1]` at line 13.
- Lines 14-17, 46-48, 126, 138, and 154 construct paths with Windows separators.
- Line 47 includes `src\Classes`; the directory is not tracked, so it will not
  exist in a fresh clone even though an empty local directory may mask the issue.

The current Windows build succeeds. Non-Windows execution was not available in
this review, so the portability impact is established statically rather than by a
Linux/macOS build run.

Recommendation: derive the module name with `Split-Path -Leaf`, construct paths
with `Join-Path`, and enumerate only source directories that exist. Add at least
one clean Linux PowerShell build to automated validation if cross-platform build
support is intended. If build portability is intentionally out of scope, state
that explicitly instead of implying it through the Core-only module declaration.

### CA-006 — Medium — Remote tag `v1.1.2` contains version `1.1.1`

The current remote tag cannot reproduce a 1.1.2 release:

```text
git ls-remote --tags origin-main refs/tags/v1.1.2
8a245cabafbf1381cf585c60241914ff34ae1796 refs/tags/v1.1.2

git show v1.1.2:CompleterActions.psd1
ModuleVersion = '1.1.1'

git show v1.1.2:build/CompleterActions/CompleterActions.psd1
ModuleVersion = '1.1.1'
```

Current `main` declares 1.1.2, but that version update occurred after the tag.
This breaks tag-to-artifact provenance and makes a checkout of `v1.1.2` build the
wrong package version.

Recommendation: do not silently move a tag that consumers may already have. If
the tag/release was published, issue a correctly tagged next release and document
the bad tag. If it was never consumed or published, correct it using the project's
release policy. Add a release check asserting that the tag name matches the source
and built manifest versions.

### CA-007 — Medium — A Pester test rewrites tracked build and help artifacts

The test intended to validate publish metadata invokes the real build in the
working tree. That build cleans and regenerates packaged output and source MAML.
Running the suite during this review changed three tracked files, including a
date-only manifest change and large generator-dependent help rewrites.

Evidence:

- [`CompleterRegistration.Tests.ps1`](../tests/CompleterRegistration.Tests.ps1#L38)
  invokes `Invoke-Build ... build` at line 46.
- [`CompleterActions.build.ps1`](../CompleterActions.build.ps1#L30) runs `clean`
  and `external_help` as build dependencies, then writes tracked locations.
- The review run changed:
  - `build/CompleterActions/CompleterActions.psd1`
  - `build/CompleterActions/en-US/CompleterActions-help.xml`
  - `src/docs/CompleterActions/CompleterActions/CompleterActions-Help.xml`

Those generated changes were removed after validation; they are not included in
this review artifact.

Recommendation: make tests hermetic. Build into an isolated temporary destination
or test already-generated metadata without rewriting tracked source/output. Pin
the help generator version and add a separate reproducibility check that fails on
an unexpected post-build diff.

### CA-008 — Low — The manifest version assertion is stale

[`CompleterActions.psd1`](../CompleterActions.psd1#L15) declares version 1.1.2,
while [`CompleterRegistration.Tests.ps1`](../tests/CompleterRegistration.Tests.ps1#L9)
expects 1.0.0. This is the only current Pester failure.

Recommendation: either update the expected version for each release or replace
the hard-coded value with a release-policy assertion that will remain meaningful.

## Validation evidence

All commands below were run from the repository root with profile loading
disabled where PowerShell was launched.

| Check | Result |
| --- | --- |
| `Invoke-Build -File ./CompleterActions.build.ps1 build` | Succeeded: 3 tasks, 0 errors, 0 warnings |
| `Invoke-Pester -Path ./tests` with Pester 6.1.0 | Failed: 47 total, 46 passed, 1 failed, 0 skipped |
| Source PSScriptAnalyzer with repository settings | No findings |
| Test PSScriptAnalyzer with repository settings | No findings |
| Built `Test-ModuleManifest` and module import | Succeeded |
| Built exported-command check | Exactly 4 expected commands |
| Built conceptual help check | `about_Import_Completers` loaded |
| Importer side-effect probe | Reproduced CA-001 |
| Fresh and forced registration fault injection | Reproduced CA-002 |
| Direct runtime overwrite lifecycle probe | Reproduced CA-003 |
| Drive-path key-only registration probe | Reproduced CA-004 |
| Remote tag lookup | Confirmed CA-006 against `origin-main` |

## Qualified non-findings

- Dynamic import modules are intentionally retained by returned import objects and
  managed registration records so their script blocks keep helper functions and
  script-scope state. An isolated probe showed no matching module in `Get-Module
  -All`; no leak is reported without stronger lifetime or stress evidence.
- Paging currently follows merged insertion/enumerator order. The project does not
  promise a stable sort order, so nondeterministic page membership across runtime
  mutations is a possible enhancement rather than a confirmed defect.
- Reflection into PowerShell runtime internals is an explicit design constraint,
  is documented, and has real-runtime test coverage. It remains a compatibility
  risk, not a current defect on PowerShell 7.6.5.

## Review limits

- Runtime verification used Windows PowerShell 7.6.5 only.
- No Linux or macOS build was available.
- No gallery publish/install operation was performed.
- No older or preview PowerShell runtime was tested.
- Fault-injection probes intentionally replaced private functions only inside
  isolated PowerShell processes; they did not alter repository source.

## Suggested remediation order

1. Fix CA-001 and add adversarial importer tests.
2. Fix CA-002 and CA-003 together around one explicit runtime/managed
   reconciliation and transaction model.
3. Resolve the CA-004 key contract before expanding input shapes further.
4. Correct the test/build hygiene and version checks in CA-007 and CA-008.
5. Repair release provenance (CA-006) and decide the intended build portability
   contract (CA-005).
