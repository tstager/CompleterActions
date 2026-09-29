# Milestone 1 specification: faster imports and recovery (2.1.0)

Drafted: 2026-09-28
Base: main at `7bcdc01` (2.0.0 stable, release commit `b2de0be`, tag v2.0.0)
Roadmap: `docs/roadmap-3.0.md`, milestone 1, and locked decisions 1 and 2.
Kind: behaviour spec. It states what the module does after 2.1.0 and how a reader can tell. It does not prescribe helpers, file splits, or commit order.
Status: accepted 2026-09-28. The owner accepted every recommendation in section 9 as written, so each question there is resolved in favour of its recommendation and the contracts in sections 2 to 8 are final.

Every claim about current behaviour cites the file it was read from. Measurements in this document were taken on 2026-09-28 on the owner's Windows machine, PowerShell 7.6.6, against the tracked `build/CompleterActions` (2.0.0) and the PS_Completers set.

## 1. Scope and non-goals

2.1.0 is an additive release on the 2.x line.

- No command, parameter, alias, property, or enum value is renamed or removed. Nothing that 2.0.0 accepts is rejected.
- A set file without `Hash` entries imports exactly as in 2.0.0: same validation, same records in the same order, same errors, same warnings.
- The set file `Version` stays `1`. A set written by 2.1.0 imports unchanged on 2.0.0, because `Resolve-CompleterSetEntry` reads only `Path`, `Trusted`, and `Targets` and ignores other keys (`src/Private/Resolve-CompleterSetEntry.ps1`). This was checked on 2026-09-28: an entry carrying `Hash` imported under the 2.0.0 build as `Pending` with no warning.
- Two public commands are added, `Reset-Completer` and `Test-CompleterSet`. The module then exports 13 functions and the same 3 aliases (2.0.0 exports 11 functions, `CHANGELOG.md` 2.0.0-rc1).

In scope:

| Item | Kind | Section |
| --- | --- | --- |
| Per-entry `Hash` in the set file, written by `Export-CompleterSet` | schema | 2 |
| `Import-CompleterSet` skips the parse when the hash matches | perf | 3 |
| One bulk write path for a whole set | perf | 4 |
| `Reset-Completer` | feature | 5 |
| `Test-CompleterSet` | feature | 6 |
| Startup benchmark, second edition | perf | 7 |
| Command help for the two new commands; `Register-Completer`'s "retry Failed" example switches to `Reset-Completer` | docs | 5, 6 |

Non-goals:

- **No per-user cache.** The parse cache is the per-entry `Hash` in the set file (decision 1). Nothing is written outside the set file, and `Import-CompleterSet` never writes at all.
- **The hash is not a trust mechanism.** It is a cache key for targets. It does not sign anything, it does not change the trust tier, and it does not replace the strict grammar walk.
- **The grammar still runs at first tab, not at import** (2.0 decision 5, `docs/roadmap-2.0.md`). Running it at import comes back only with the compiled walk in 3.0.
- **`Test-CompleterSet` does not run the strict grammar.** That stays with `Test-CompleterScript`.
- **`Reset-Completer` does not re-read the set, re-derive targets, or parse the script.**
- Deferred to 2.2.0: `New-CompleterScript`, installable completer sets and `Import-CompleterSet -Name`, engine cmdlet detection, and the third edition of the author guide. Section 9, question 7, asks how much of `about_Completer_Sets` changes in 2.1.0.
- Deferred to 3.0: the compiled core, public .NET types, removal of the deprecated surface, and the 7.4 engine floor.
- A consequence for the 3.0 roadmap: its exit criterion "8 functions, 0 aliases" becomes 10 functions once the two new commands ship. The roadmap needs that edit when 2.1.0 ships.

## 2. Set file schema change: per-entry `Hash`

### Shape and placement

`Hash` is an optional string key on an entry. `Export-CompleterSet` writes it between `Trusted` and `Targets`, padded like the existing keys:

```powershell
@{
    Version = 1
    Entries = @(
        @{
            Path    = '7z_completer/7z_completer.ps1'
            Trusted = $false
            Hash    = 'SHA256:9F86D081884C7D659A2FEAA0C55AD015A3BF4F1B2B0B822CD15D6C15B0F00A08'
            Targets = @(
                @{ CommandName = '7z'; Native = $true }
                @{ CommandName = '7z.exe'; Native = $true }
            )
        }
    )
}
```

The value is the literal prefix `SHA256:` followed by 64 uppercase hexadecimal digits. Readers compare the prefix and the digits case-insensitively.

### What bytes are hashed

The hash describes the script's text after its line endings are normalised, not the raw bytes on disk:

1. Read the file. Decode it as UTF-8 unless a byte-order mark names another encoding (UTF-8, UTF-16 LE or BE, or UTF-32 LE), and drop the mark. This is the decoding PowerShell's parser applies to a `.ps1`.
2. Replace every CR LF pair with LF, then every remaining lone CR with LF.
3. Encode the resulting text as UTF-8 without a byte-order mark.
4. Compute SHA-256 over those bytes.

This rule is needed because the same commit has different bytes on the two platforms that matter:

- In the PS_Completers working tree on Windows (`core.autocrlf=true`), `git ls-files --eol` reports 168 of the 173 `*_completer.ps1` files as `i/lf w/crlf` and 5 as `i/lf w/lf`.
- That repo's CI checks out on `ubuntu-latest` (`.github/workflows/conformance.yml`), where every file is LF.

A set exported on Windows therefore has to validate on Linux. None of the 173 scripts has a BOM, and 5 contain non-ASCII characters, so decoding to text before hashing matters as well.

A change to the BOM or to line endings alone does not change the hash, and it does not change the parse either. Any other change to the text does change the hash. `Get-FileHash` is not used because it hashes raw bytes.

Measured cost: hashing all 173 scripts this way takes 84 to 87 ms in one process (4.2 MB of script). Parsing them takes 306 to 319 ms, and deriving their targets takes 631 to 654 ms.

### How `Export-CompleterSet` writes it

- Every entry gets a `Hash`, strict and trusted alike. A trusted entry's hash is never used at import (section 3), but `Test-CompleterSet` uses it to report drift.
- **A strict script is read once.** Today the strict-subset check calls `Get-CompleterScriptTarget -LiteralPath`, which reads and parses the file itself through `Get-CompleterScriptParseResult` (`[Parser]::ParseFile`) and hands back only targets (`src/Public/Export-CompleterSet.ps1`, `src/Private/Get-CompleterScriptTarget.ps1`, `src/Private/Get-CompleterScriptParseResult.ps1`). In 2.1.0 the export takes both the targets and the hash from that one parse. The hash input is the parse result's source text, `Ast.Extent.Text`, which is the decoded file text of step 1 above. This was checked on 2026-09-28: for all 173 PS_Completers scripts, and for UTF-8, UTF-8 with BOM, and UTF-16 LE fixtures, `Ast.Extent.Text` equals `[System.IO.File]::ReadAllText` of the file, character for character. Whether the parse helper returns its text alongside the targets or the export passes a parse result in is an internal choice. What is fixed is that no second read happens, so an edit between two reads cannot give a hash that does not match the checked targets. The hash always describes a file whose targets matched the entry's `Targets` when it was written.
- **A strict entry's `Targets` are written in the script's order.** Today the export writes targets in input-record order, and without `-InputObject` the records come from `Get-Completer`, which sorts by `CompleterType`, `CommandName`, `ParameterName` (`src/Public/Get-Completer.ps1`). In 2.1.0 a strict entry's `Targets` are written in the order the script registers them, one per `Key`, with the script's `CommandName` and `ParameterName` casing. The strict-subset check already guarantees that the record keys equal the derived keys, so only order and casing can change. This is what lets the fast path reproduce 2.0.0's records (section 3). The existing export tests compare targets after sorting, so they are unaffected. Trusted entries keep the record order, as today.
- **A trusted script is read once, for the hash only.** 2.0.0 never reads a trusted script at export and exports a trusted entry whose file is missing (`if ($entry.Trusted) { continue }`). 2.1.0 keeps accepting that. If a trusted file is missing or cannot be read, the entry is written without `Hash`, the export still succeeds, and the command writes one warning per such entry: `The script '<path>' could not be read, so its entry was written without a Hash. <reason>`. `Test-CompleterSet` then reports that entry as `MissingScript` or `MissingHash`. A strict entry whose file cannot be read already fails the export in 2.0.0, through the target check, with `Failed to export completer set. <reason>`, and nothing is written. That is unchanged.
- Nothing else about the export changes. `Path` stays relative with forward slashes, `Targets` is always written, the strict-subset refusal is unchanged, `-WhatIf` writes nothing, and `-PassThru` returns the file.
- Regenerating the PS_Completers set with 2.1.0 adds exactly one `Hash` line per entry and changes no other line. `tools/Export-CompleterSetFile.ps1` in that repo pipes the lazy registration records straight into the export, so its `Targets` are already in script order. This was checked on 2026-09-28: for all 173 entries the declared targets equal `Get-CompleterScriptTarget`'s output in order and in `RuntimeKey` casing, and no entry lists a target twice.

### A set without `Hash`, or with one the reader does not recognise

- **No `Hash` key:** the entry is handled exactly as in 2.0.0.
- **A `Hash` that is not a string, or that does not match `SHA256:` plus 64 hexadecimal digits:** `Import-CompleterSet` treats it as absent. It is not an entry problem, because the cache must never make an import fail. `Test-CompleterSet` reports it as `InvalidHash` (section 6).
- An unknown prefix such as `SHA512:` is handled the same way, so a later algorithm change degrades to the parse path instead of failing.

## 3. `Import-CompleterSet` fast path

### Current behaviour (2.0.0)

`src/Public/Import-CompleterSet.ps1` handles each set in these steps:

1. It reads the set once through `Import-CompleterSetDefinition` (`Import-PowerShellDataFile`, data only).
2. It takes one registration snapshot per set.
3. It resolves every entry with `Resolve-CompleterSetEntry`.
4. For each strict entry, it calls `Get-CompleterScriptTarget`, which parses the file, walks the script-scope `Register-ArgumentCompleter` calls, and compares the derived targets with any declared `Targets` (`src/Private/Resolve-CompleterSetEntry.ps1`, `src/Private/Get-CompleterScriptTarget.ps1`).

Trusted entries are never parsed.

### Decision per entry after 2.1.0

| Entry | `Hash` | Script file | What import does |
| --- | --- | --- | --- |
| any | any | missing, or not a `.ps1` | As today: the problem `The file '<path>' does not exist.` or `... is not a .ps1 script.` The file is not hashed. |
| Trusted | any | present | As today: no parse, and no hash is computed. `Hash` is ignored. |
| Strict, no `Targets` | any | present | As today: parse and derive. A hash cannot supply targets the set does not list. |
| Strict with `Targets` | absent or unrecognised | present | As today: parse, derive, compare. |
| Strict with `Targets` | present, differs from the file | present | As today: parse, derive, compare. Only the verbose line differs. |
| Strict with `Targets` | present, matches the file | present | **Fast path:** no parse. The targets are the entry's declared `Targets`, in declared order, de-duplicated by `Key`. The first occurrence of a key is kept, with its declared casing. |

If reading the file for the hash fails, the entry falls through to the parse path, so the reported problem is the one 2.0.0 reports. At import the file is read with the same decoding as the parser (`[System.IO.File]::ReadAllText`, section 2), and only for the hash.

### Records on the fast path compared with 2.0.0

2.0.0 always builds a strict entry's records from the derived targets. When the declared and derived targets match, `Resolve-CompleterSetEntry` takes `$targets = $derivedTargets` (`src/Private/Resolve-CompleterSetEntry.ps1`). Its comparison is by `Key` only, so it ignores order, repeats, and casing (`Key` is lower-cased, `RuntimeKey` keeps the written casing, `src/Private/Resolve-CompleterTarget.ps1`). `Get-CompleterScriptTarget` returns the targets in script order, one per `Key`. The fast path has no derived targets, so it uses the declared ones.

The two paths give identical records (`Key`, `RuntimeKey`, `State`, `ScriptPath`, `Trusted`, and their order) whenever the declared `Targets` list each derived target once, in script order, with the script's casing. Two kinds of set meet that condition:

- every strict entry written by 2.1.0's `Export-CompleterSet` (section 2);
- the current PS_Completers set, as checked in section 2.

A hand-edited entry can reorder, repeat, or recase its `Targets` while its hash still matches, because the hash covers the script, not the entry. That entry imports the same keys, states, and script paths as on 2.0.0. Its records follow the declared order and the first declared casing of each key instead of the script's. That is the only difference the fast path can make.

### Static checks that still run from the set alone on the fast path

- The entry is a hashtable with a `Path`.
- `Path` resolves against the set directory, and the file exists and is a `.ps1`.
- `Trusted`, when present, is a `[bool]`.
- Every declared target has a `CommandName` and either `Native = $true` or a `ParameterName`, and it resolves through `Resolve-CompleterTarget`.
- No target is claimed by two entries of the set.
- Without `-Force`, no target already carries a different managed or runtime registration (`Resolve-CompleterRegistrationConflict` against the set's snapshot). An identical registration is reused.

The fast path skips three checks: the parse errors, the literal-argument check, and the declared-versus-derived comparison. The hash stands in for all three, because the export that wrote it ran them against the same content.

### What is still parsed

- Every strict entry whose hash is absent, unrecognised, or different.
- Every strict entry without `Targets`.
- Nothing on the fast path.

The set file itself is still read only through `Import-PowerShellDataFile`. The existing test "reads the set through Import-PowerShellDataFile only and never evaluates set content" (`tests/CompleterSet.Tests.ps1`) keeps passing.

### What is printed

- **Output:** the same `CompleterActions.CompleterRegistration` records as 2.0.0, in set order, `Pending` or reused, whichever path each entry took, subject to the order and casing rule above. For a set written by `Export-CompleterSet`, a reader cannot tell from the output which entries used the fast path.
- **Warnings and errors:** unchanged. A stale hash is not a warning (section 9, question 3). A stale hash therefore shows up only in `Import-CompleterSet -Verbose` and in `Test-CompleterSet`. The owner's profile imports the set with `-WarningAction SilentlyContinue | Out-Null` (`Microsoft.PowerShell_profile.ps1`), so it would not show a warning anyway. The PS_Completers CI drift gate (section 6) is what keeps the profile on the fast path after a script is edited.
- **Verbose:** one line per entry, then one summary line per set:

  ```text
  VERBOSE: Entry 12 ('git_completer/git_completer.ps1'): hash matches; targets read from the set.
  VERBOSE: Entry 13 ('go_completer/go_completer.ps1'): hash differs; parsed the script.
  VERBOSE: Entry 14 ('grep_completer/grep_completer.ps1'): no hash; parsed the script.
  VERBOSE: Completer set '<path>': 171 entries from the hash, 2 parsed, 0 trusted.
  ```

### Safety guarantee

A non-conforming script still never executes, whether its entry took the fast path or not. `Import-CompleterSet` registers stubs and executes nothing. On the first tab press, `Invoke-CompleterLazyStub` loads the script through `Import-CompleterScript -LiteralPath $registration.ScriptPath -Trusted:$registration.Trusted` (`src/Private/Invoke-CompleterLazyStub.ps1`), which parses the file as it is at that moment and runs the full strict grammar walk before executing anything (2.0 decision 5).

Two cases show that a bad hash cannot lead to execution:

- **A forged or hand-edited hash** that claims targets the script does not register produces `Pending` records. The first press then fails to `Failed` with `The script '<path>' did not register a completer for '<target>'.`
- **A script edited after import** is checked in its edited form at first tab.

The worst outcome of a wrong hash is therefore a `Failed` record, never execution of unchecked code.

## 4. Bulk registration path

### What already holds in 2.0.0

Each set already takes one snapshot (`Get-CompleterRegistrationSnapshot`). Every confirmed entry is then written through a single `Add-CompleterRegistration` call, with whole-set rollback (`src/Public/Import-CompleterSet.ps1`, `src/Private/Add-CompleterRegistration.ps1`).

The per-target costs that remain are these:

- a conflict pass per entry (`Resolve-CompleterRegistrationConflict` is called once per entry from `Resolve-CompleterSetEntry`, and the test "reads the session registrations once" asserts 3 state passes for 3 entries);
- a reflection lookup of the runtime dictionaries on every runtime write (`Add-RuntimeCompleterRegistration` calls `Get-CompleterRuntime`);
- a module-state lookup on every managed write (`Add-ManagedCompleterRegistration` calls `Get-ManagedCompleterRegistrationTable`).

The module takes no lock anywhere (no lock or `Monitor` exists under `src`). The roadmap's "managed-table lock" means these repeated reads.

### Contract after 2.1.0

The contract below is what a caller can observe. The internals may change freely as long as it holds.

1. **One snapshot per set.** The session's managed table and runtime dictionaries are read once per set, for validation and writing together.
2. **One conflict pass per set.** The conflicts for every target of the set are resolved in one pass, in set order. A later entry sees the targets claimed by earlier entries, exactly as today.
3. **One managed-table write per set.** The managed records of the whole set go into the table as one batch step, after the runtime writes succeed. Runtime dictionaries are resolved once per set, not once per target.
4. **Same records and states.**
   - Records come out in set order, one per target.
   - New records are `Pending`, with the stub from `New-CompleterLazyStub`, `ScriptPath`, and `Trusted`.
   - A reused registration is returned as the very object already stored, which the test "returns the records in set order and keeps a reused record in its place" checks by reference.
   - `Get-Completer` afterwards returns exactly what it returns after a 2.0.0 import.
5. **Rollback.**
   - If any runtime or managed write of the set fails, every change the set made is undone in reverse. Each replaced runtime value and managed record is restored, and each new one is removed. Because the runtime values of the whole set are written before the first managed record (item 3), a managed write that fails undoes the runtime value of every entry of the set, including entries after the one that failed. The command throws `Failed to import completer set. Failed to register the completer '<RuntimeKey>'. <reason>`, where `<RuntimeKey>` is the target whose write threw, with the rollback failure appended when there is one, which is today's text.
   - One call that names several sets treats each set as its own transaction. A failure in a later set leaves earlier sets registered, as today.
6. **`-WhatIf` and `-Confirm`.**
   - Validation always runs in full, so an invalid set fails under `-WhatIf` too.
   - `ShouldProcess` is asked once per valid entry, with target = the resolved script path and action `Import completer set entry`.
   - Under `-WhatIf` each valid entry prints one `What if:` line, nothing is written, and nothing is returned.
   - Under `-Confirm`, declined entries are left out and the confirmed entries are written together as one transaction.
7. **`-SkipInvalid` and `-Force`:** unchanged.

`Register-Completer` keeps its per-target transaction. It resolves and writes each target on its own, through `Resolve-CompleterRegistrationConflict` and `Add-CompleterRegistration` inside its per-input loop (`src/Public/Register-Completer.ps1`), so a failure on one target never undoes an earlier target of the same call. The bulk path is for `Import-CompleterSet` only.

## 5. Reset-Completer

### SYNOPSIS

Returns a Failed or Active script-backed completer to Pending, so its script loads again on the next tab press.

### SYNTAX

#### CommandParameter (Default)

```PowerShell
Reset-Completer -CommandName <string[]> -ParameterName <string[]> [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

#### InputObject

```PowerShell
Reset-Completer -InputObject <Object[]> [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Native

```PowerShell
Reset-Completer -CommandName <string[]> -Native [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

The parameter sets, the default set, the types, and the pipeline bindings mirror `Unregister-Completer` (`src/Public/Unregister-Completer.ps1`, `src/docs/CompleterActions/Unregister-Completer.md`), with one difference: there is no `-AllowUnmanaged`, because a reset never touches a registration the module does not manage. The command uses `[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]` and `[OutputType('CompleterActions.CompleterRegistration')]`.

### DESCRIPTION

Re-arms a script-backed managed registration without re-importing the set. The roadmap's wording is "a `Failed` or `Active` lazy record". The record has no field that tells a lazily loaded record from an eagerly registered one: `Resolve-CompleterRegistrationState` reports `Active` from the stored state alone, and both `Invoke-CompleterLazyStub` and `Register-Completer`'s eager path write `Active` records with `ScriptPath`, `Trusted`, and `ImportModule`. The command and its help therefore state the scope as a `Failed` or `Active` **script-backed** record, meaning any managed record with a `ScriptPath` (section 9, question 1). Each target named by `-CommandName` with `-Native` or `-ParameterName`, or described by a piped record, is decided once per call. As in `Unregister-Completer`, a key seen earlier in the same call is skipped.

Each target is decided from the managed record and the live runtime value, using the same state rules as `Resolve-CompleterRegistrationState`:

| Current state of the target | Result |
| --- | --- |
| `Failed`, no live runtime value, `ScriptPath` exists | A new lazy stub is written to the runtime dictionary. The record becomes `Pending`, with `LoadError` cleared and `ScriptPath` and `Trusted` kept. |
| `Active`, `ScriptPath` exists | The stub replaces the live script block. The record becomes `Pending`, and `ImportModule` is cleared. |
| `Pending` | Nothing changes and `ShouldProcess` is not asked. `-Verbose` says it is already pending, and `-PassThru` returns the current record. |
| `Active` or `Failed`, empty `ScriptPath` (registered from a script block) | Error: `... was registered from a script block, not a script file, so there is nothing to reload.` |
| `Failed` or `Stale` with a live value created outside the module | Error: `The module-managed completer registration for '<RuntimeKey>' is <state> and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it.` |
| `Stale`, runtime value removed outside the module | Error: `... is stale. Use Register-Completer -Force to register it again.` |
| No managed record, live value present (`Discovered`, `Conflicted`) | Error: `The completer registration '<RuntimeKey>' is not module-managed, so it cannot be reset.` |
| Nothing registered | Error: `No completer registration was found for the requested target.` This is `Unregister-Completer`'s text. |
| `Active` or `Failed`, `ScriptPath` no longer exists | Error: `The script '<path>' for '<RuntimeKey>' no longer exists. Restore it, or remove the registration with Unregister-Completer.` |

**Precedence.** The rows are checked in this order, and the first that applies decides the target:

1. Whether a managed record exists: the `Discovered`/`Conflicted` row or the nothing-registered row.
2. The state: `Pending` is a no-op, then the `Stale` rows, then `Failed` with an outside live value.
3. Whether `ScriptPath` is empty: the script-block row.
4. Whether the script file exists: the missing-script row.
5. Otherwise the target is reset.

A `Pending` record whose script was deleted is therefore left alone without an error. Its first press reports the missing file, as today.

**Errors do not stop the call.** Each error is written as a non-terminating error, `Failed to reset the completer '<RuntimeKey>'. <reason>`. The wording mirrors `Unregister-Completer`'s `Failed to unregister the completer ...`. The command then goes on to the next target or piped record. An input object that `Resolve-CompleterInputObject` rejects is reported the same way. `Get-Completer -State Failed | Reset-Completer` therefore resets every record it can, and reports each record it cannot, which stays as it was.

This is the one deliberate difference from `Unregister-Completer`, whose catch block throws and so stops the pipeline at the first bad record (`src/Public/Unregister-Completer.ps1`). Decision 2 locks the target contract and the pipeline input, which are unchanged. A reset is a repair step run over a filtered list, so one record that cannot be reset must not strand the rest. `-ErrorAction Stop` restores stop-on-first-error for a caller who wants it. `$?` is `$false` after a call that wrote any error.

Each target is its own transaction. If writing the stub or the record fails, the previous runtime value (or its absence) and the previous managed record are restored.

After a reset, the record cannot be told apart from one that `Import-CompleterSet` or `Register-Completer -Lazy` just created. The next tab press follows the ordinary lazy path (`Invoke-CompleterLazyStub`):

- The press imports the script under the record's tier, with the strict grammar walk for a strict record, swaps in every `Pending` sibling of the same script and tier, and moves them to `Active`.
- A script that still fails moves the pressed target to `Failed` again, with the new `LoadError`.

Only the targets named are reset. An `Active` sibling of a reset target keeps its loaded block until it is reset itself. To reload a whole script, pipe every one of its records, as in example 3.

The script is not parsed and its targets are not re-derived. If a fixed script no longer registers a target, that target fails on its first press with `did not register a completer for`.

**PSReadLine neutrality.** `Reset-Completer` writes only the runtime completer dictionaries and the module's managed table. It never hooks key handlers, never replaces `TabExpansion2`, and never touches PSReadLine options or prediction. `Get-PSReadLineKeyHandler -Bound -Unbound` returns the same list before and after a reset and the load that follows.

### PARAMETERS

| Parameter | Type | Sets | Required | Pipeline | Notes |
| --- | --- | --- | --- | --- | --- |
| `-InputObject` | `System.Object[]` | InputObject | yes | by value | Records from `Get-Completer`, `Register-Completer -PassThru`, or `Import-CompleterSet`. Any object that `Resolve-CompleterInputObject` accepts: `CommandName` with `IsNative`/`Native` or `ParameterName`, or `Key`/`RegistrationKey`/`RuntimeKey` with `IsNative`/`Native`. A bare key is rejected with the 2.0 message. |
| `-CommandName` | `System.String[]` | CommandParameter, Native | yes | by property name | |
| `-ParameterName` | `System.String[]` | CommandParameter | yes | by property name | |
| `-Native` | `SwitchParameter` | Native | yes | by property name | Alias `IsNative`. |
| `-PassThru` | `SwitchParameter` | all | no | no | Returns the `Pending` record of each target that was reset, and the unchanged record of each target that was already `Pending`. |
| `-WhatIf`, `-Confirm` | `SwitchParameter` | all | no | no | `ShouldProcess` target = `RuntimeKey`, action `Reset completer registration`. Under `-WhatIf` nothing changes and nothing is returned. |

### INPUTS and OUTPUTS

- **Inputs:** `System.Object[]`, `System.String[]`, `System.Management.Automation.SwitchParameter`.
- **Outputs:** `CompleterActions.CompleterRegistration`, when `-PassThru` is used.

### EXAMPLES

```powershell
Get-Completer -State Failed | Reset-Completer
```

Example 1. Re-arms every failed script-backed registration after the scripts were fixed. Afterwards, `Get-Completer -State Failed` lists only the records that were reported as errors, for example a record whose live runtime value was replaced outside the module (which `Get-Completer` also lists as a `Conflicted` record), or one whose script was deleted. When every failed record can be reset, it is empty.

```powershell
Reset-Completer -CommandName git, git.exe -Native -PassThru
```

Example 2. Reloads the git completer on the next tab press after the script was edited, and returns the two `Pending` records.

```powershell
Get-Completer -State Active, Failed | Where-Object ScriptPath -eq $path | Reset-Completer
```

Example 3. Resets every target of one script.

## 6. Test-CompleterSet

### Synopsis and syntax

Reports drift between a completer set file and the scripts on disk.

```PowerShell
Test-CompleterSet [-Path] <string[]> [-Filter <string>] [<CommonParameters>]
Test-CompleterSet -LiteralPath <string[]> [-Filter <string>] [<CommonParameters>]
```

| Parameter | Type | Notes |
| --- | --- | --- |
| `-Path` | `System.String[]` | Position 0. Pipeline by value and by property name, alias `FullName`. Wildcards are supported. This mirrors `Import-CompleterSet`. |
| `-LiteralPath` | `System.String[]` | Pipeline by property name, alias `PSPath`. |
| `-Filter` | `System.String` | The file-name pattern for the unlisted-script scan. The default is `*_completer.ps1` (section 9, question 5). |

The command is read-only, so it has no `ShouldProcess`. Its output type is `CompleterActions.CompleterScriptFinding`.

### Behaviour

- **Reading the set.** The set is read through the same reader as `Import-CompleterSetDefinition`: data only, `Version = 1`, non-empty `Entries`. A set that fails there is a terminating error, `Failed to test completer set. <reason>`, where `<reason>` is that reader's text: a directory, a file that is not `.psd1`, a missing `Version = 1`, or no `Entries` (`src/Private/Import-CompleterSetDefinition.ps1`). No findings are returned for that set.
- **Several sets in one call.** As in `Import-CompleterSet` (`src/Public/Import-CompleterSet.ps1`), every `-Path` or `-LiteralPath` value is resolved first (`Resolve-Path` or `Get-Item`, `-ErrorAction Stop`). A value that does not resolve fails the call with `Failed to test completer set. <reason>` before any set is tested. The sets are then tested in the order given, and each set's findings are written before the next set is read. A set that fails to read stops the call with the terminating error above. The findings of earlier sets have already been written to the pipeline by then, and later sets are not tested.
- **Positions.** The set file is also parsed with the PowerShell parser, never evaluated, only to get positions for findings. `New-CompleterScriptFinding` requires an `IScriptExtent` (`src/Private/New-CompleterScriptFinding.ps1`).
- **Every entry is checked in full.** Strict entries are always parsed, because the command verifies and does not take the fast path.
- **Trusted entries are never parsed,** as at import, where a trusted entry's targets are taken as given. A trusted entry can therefore report only `MissingScript`, `InvalidEntry`, `DuplicateTarget`, and the three hash kinds. It never reports `UnreadableTargets` or `TargetMismatch`. The roadmap's "targets no longer match the script" applies to strict entries only. Checking a trusted script's targets would mean parsing or running it, which the trusted tier exists to avoid.
- **Session independence.** The command never registers anything, never reads or writes the session's registrations, and never executes a script. Conflicts with the live session are therefore not drift, and they are not reported.
- **Duplicate targets follow import's claiming rule.** Entries are walked in set order, and each has resolved targets:
  - a trusted entry's resolved targets are its well-formed declared targets, even when the entry also has a `MissingScript` or `InvalidEntry` finding;
  - a strict entry's resolved targets are its derived targets, when its well-formed declared `Targets` match them or it declares none, even when the entry also has an `InvalidEntry` finding for a malformed target or a `Trusted` value that is not a bool;
  - a strict entry with a `TargetMismatch`, `UnreadableTargets`, or `MissingScript` finding, no `Path`, or a `Path` that is not a `.ps1` has no resolved targets, and neither has an entry that is not a hashtable.

  An entry claims its resolved targets only when it has no `Error` finding. A later entry whose resolved target is already claimed gets `DuplicateTarget`, naming the earlier entry. This is `Resolve-CompleterSetEntry`'s rule: the duplicate check iterates `$targets`, which stays empty on a mismatch, and `$ClaimedTargets` is filled only when the entry has no problems. The one difference is that session conflicts do not count here. So `DuplicateTarget` is reported exactly when `Import-CompleterSet` would reject the set for a duplicate in a session without conflicting registrations.
- **Unlisted scripts.** The scan is recursive under the set file's directory, using `-Filter`. Paths are compared case-insensitively on Windows and case-sensitively elsewhere. Scripts that an entry lists by an absolute path outside that directory still count as listed.
  - The PS_Completers gate that this replaces scans only one level deep: `*_completer` folders, then `*_completer.ps1` inside them. For that repo the two scans give the same files. On 2026-09-28 a recursive search found 173 `*_completer.ps1` files, all at `<folder>_completer/<name>_completer.ps1`, which is the 173 the set lists.
  - A future file matching `*_completer.ps1` elsewhere under the set directory, such as a test fixture or a docs sample, would be reported as `UnlistedScript` and fail an empty-output gate. The fix is to name it so that it does not match `-Filter`, or to keep it outside the set directory. The scan has no exclusion list.
  - A folder under the set directory that cannot be read stops the call with `Failed to test completer set. <reason>`, where `<reason>` is the file system's text. That set's entry findings have already been written, and its `UnlistedScript` findings are not. A scan that skipped the folder could miss an unlisted script and let an empty-output gate pass.
- **Order.** Entry findings come first, in set order. Unlisted-script findings follow, sorted by path.

### Drift kinds

The severity rule: `Error` when `Import-CompleterSet` without `-SkipInvalid` would reject the set because of this finding; `Warning` when the set still imports but is stale or slower.

| `Construct` | Severity | Reported when | Line and column point at |
| --- | --- | --- | --- |
| `MissingScript` | Error | `Path` does not resolve to an existing file. | the entry's `Path` value |
| `InvalidEntry` | Error | Any other schema problem that `Import-CompleterSet` reports for the entry: not a hashtable, no `Path`, not a `.ps1`, `Trusted` not a bool, a malformed target, a trusted entry without `Targets`. The `Message` is `Import-CompleterSet`'s problem text, word for word. | the entry's `@{` |
| `UnreadableTargets` | Error | A strict script does not parse, uses a non-literal target argument, or registers no literal targets. The `Message` is `Get-CompleterScriptTarget`'s text. | the entry's `Path` value |
| `TargetMismatch` | Error | A strict entry's declared `Targets` differ from the script's derived targets. The `Message` lists both, as the import problem does. | the entry's `Targets` key |
| `DuplicateTarget` | Error | A resolved target of this entry was already claimed by an earlier entry, under the claiming rule above. The `Message` is import's text, `Target '<RuntimeKey>' is also listed by entry <n>.` | the later entry's `Targets` key, or its `@{` when it declares none |
| `HashMismatch` | Warning | `Hash` is well formed and differs from the file's current hash, strict or trusted. | the entry's `Hash` value |
| `MissingHash` | Warning | The entry has no `Hash` (section 9, question 4). | the entry's `@{` |
| `InvalidHash` | Warning | `Hash` is present but not `SHA256:` plus 64 hexadecimal digits. | the entry's `Hash` value |
| `UnlistedScript` | Warning | A file under the set directory matches `-Filter` and no entry lists it. The `Message` names the file. | the `Entries` key |

One entry can produce more than one finding. For example, a script that gained a target yields both `HashMismatch` and `TargetMismatch`.

### Finding fields

The command fills every field of the existing `CompleterScriptFinding` class (`src/Classes/CompleterTypes.ps1`). No field is added.

- **`Path`:** the set file's full path, for every kind. The fix is always made in the set, usually by regenerating it.
- **`Line`, `Column`:** the start of the extent named in the table.
- **`Severity`:** `Error` or `Warning`, per the table.
- **`Construct`:** the kind name from the table.
- **`Message`:** the problem, naming the entry by number and declared path, as import messages do (`Entry 12 ('git_completer/git_completer.ps1'): ...`).
- **`Hint`:**
  - Hash kinds and `UnlistedScript`: `Regenerate the set with Export-CompleterSet.`
  - `MissingScript`: `Restore the script or remove the entry, then regenerate the set.`
  - `TargetMismatch` and `DuplicateTarget`: `Regenerate the set with Export-CompleterSet; a strict entry must list every target its script registers.`
  - `UnreadableTargets`: `Run Test-CompleterScript on the script, or mark the entry Trusted and list its targets.`

### Exit shape when clean

A set that matches the folder produces no output: no findings, no warnings, no errors, and `$?` is `$true`. A gate can therefore assert `Should -BeNullOrEmpty`, the same shape `Test-CompleterScript` uses (`src/Public/Test-CompleterScript.ps1`).

### The PS_Completers gate becomes one call

Today the second `Describe` in PS_Completers `tests/Completers.Tests.ps1` hand-builds the drift check. It has two `It` blocks:

- `keeps every entry on the strict tier`;
- `imports lazily and lists exactly the completer scripts in the repository`, which imports the set with `-Force`, asserts every record is `Pending`, and compares `ScriptPath` against a folder scan.

An `AfterAll` cleans up through the deprecated `Get-CompleterRegistration -ManagedOnly` and `Unregister-CompleterRegistration`. After 2.1.0 that `Describe` becomes the block below, which the owner can paste as is:

```powershell
Describe 'ps_completers.psd1 matches the repository' {
    BeforeAll {
        Import-Module -Name CompleterActions -MinimumVersion 2.1.0 -ErrorAction Stop

        $script:SetPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'ps_completers.psd1'
    }

    It 'keeps every entry on the strict tier' {
        $set = Import-PowerShellDataFile -LiteralPath $script:SetPath

        @($set.Entries | Where-Object { $_.Trusted }) | Should -BeNullOrEmpty -Because 'every script passes the strict grammar, so no entry needs to be trusted'
    }

    It 'has no drift' {
        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        $findings | Should -BeNullOrEmpty -Because (($findings | ForEach-Object { "$($_.Construct): $($_.Message) $($_.Hint)" }) -join '; ')
    }
}
```

- The strict-tier policy test is repo policy, not drift, so it stays unchanged.
- The import-and-compare `It` is replaced by `has no drift`. The `Describe` keeps two `It` blocks, and the run's test count is unchanged.
- The `AfterAll` goes, because nothing is registered. The new gate therefore stops calling the two deprecated names that 3.0 removes.
- The conformance `Describe` over `Test-CompleterScript` stays. Its `Import-Module -MinimumVersion 2.0.0` may stay, since the drift `Describe` sets the 2.1.0 floor.
- **The regeneration tool needs the same follow-up.** `tools/Export-CompleterSetFile.ps1` in that repo calls `Register-CompleterRegistration -LiteralPath ... -Lazy -Force -PassThru`, the third deprecated name, and has `#Requires` CompleterActions 2.0.0. It keeps working unchanged on 2.x, so check 3 runs it as is. Before 3.0 it must switch to `Register-Completer -LiteralPath ... -Lazy -Force -PassThru`. Raising its `#Requires` to 2.1.0 at the same time means a module without `Hash` support cannot regenerate the set and silently drop the hashes.

Changing that repo is the owner's follow-up after release. It is not part of the module change.

### Adopting 2.1.0 in PS_Completers

The order matters. `MissingHash` is a `Warning` and the new gate asserts empty output, so switching the gate before the set carries hashes fails CI.

1. **Upgrade the module.** The PS_Completers workflow installs the latest CompleterActions with `-Prerelease` (`.github/workflows/conformance.yml`), so CI moves to 2.1.0 on release day. The old gate keeps passing there, because an unhashed set imports exactly as in 2.0.0 and the deprecated names still exist on 2.x. The first profile import after upgrading is silent and no faster. The set has no hashes yet, so every entry is parsed as before.
2. **Regenerate the set.** Run `pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1` with 2.1.0 first on the module path. No script changes are needed. The diff is one added `Hash` line per entry and nothing else (check 5). Commit the set. From the next profile import on, every entry takes the fast path.
3. **Switch the gate.** Replace the drift `Describe` as above, and optionally update the regeneration tool as described above. Commit.

Steps 2 and 3 can go in one commit. What must not happen is step 3 before step 2.

## 7. Startup benchmark, second edition

### Method

The method is the same as the 2.0 edition (`tools/Measure-CompleterStartup.ps1`):

- Every sample runs in a fresh child `pwsh -NoProfile -NonInteractive`.
- A `Stopwatch` inside the child times `Import-Module` plus the registration work, which is what a profile pays.
- The median of the samples per leg is reported, with the minimum and the maximum.

The second edition changes five things:

1. The lazy leg imports a set exported by the module under test, so under 2.1.0 every entry carries a `Hash` and no file has changed since. This is the "no file changed" condition in the exit criterion.
2. A new `LazyNoHash` leg imports the same set with every `Hash` line removed. It shows that an unhashed set costs what it cost in 2.0.0.
3. A new `-BaselineModulePath` runs a `Baseline` lazy leg against the 2.0.0 package. Its samples are interleaved with the lazy leg's, so drift in machine load affects both legs. The baseline package is extracted from the tag without a worktree: `git archive v2.0.0 build | tar -x -C <scratch>`. Orphaned worktree entries in this repo print prune errors, so a worktree is avoided.
4. The default `-Iterations` rises from 5 to 10.
5. Each row gains `RatioToBaseline` next to `RatioToEager`.

The run uses the PS_Completers repo as it is on the day, and `-ModulePath` points at `build/CompleterActions` built from the milestone branch, never the gallery copy.

### The number to beat

The target is the `Baseline` (2.0.0 lazy) median from the same run, not the historical 1316 ms. That figure was measured for 2.0.0-preview1 over 169 scripts (`docs/roadmap-2.0.md`), and the set now has 173 entries and 362 targets.

**Pass:** the 2.1.0 lazy median is below 0.5 × the Baseline median, which is `RatioToBaseline < 0.50`. `LazyNoHash` must be within 10 percent of Baseline.

Spot measurement on 2026-09-28 (2.0.0 build, 3 runs, one process each, file cache warm):

| Phase | ms |
| --- | --- |
| `Import-Module` | 125 to 232 |
| `Import-CompleterSet` total | 1304 to 1383 |
| entry resolution, all 173 entries | 1126 to 1179 |
| of which target derivation (`Get-CompleterScriptTarget` over all entries) | 631 to 654 |
| write (`Add-CompleterRegistration`, 362 targets) | 165 to 171 |
| hashing all 173 scripts with the section 2 rule | 84 to 87 |

**Risk.** From these numbers, the hash fast path alone takes a lazy import from about 1.45 s to about 0.9 s, a ratio near 0.62. Reaching 0.50 needs the bulk path and the per-entry work to give back at least another 170 ms or so. That work is record construction (about 120 ms for 362 records), the per-entry conflict passes, and the 165 ms write.

### Committed mechanism, budget, and fallback

This resolves section 9, question 6.

- **Mechanism.** The milestone ships option (a) together with the section 4 bulk path. On the fast path, every declared target of the set is resolved in one pass. Stubs and records are built once per target inside that pass. The conflict pass runs once per set against the one snapshot, and the write is one runtime pass plus one managed-table batch. Nothing is cached outside the process (decision 1). "Prebuilt" means built once per import, not stored.
- **Budget.** Measured the way the spot table above was measured, `Import-CompleterSet` over the hashed PS_Completers set must take at most 550 ms, against 1304 to 1383 ms today. The per-phase targets are:
  - entry resolution over all 173 entries: at most 300 ms, against 1126 to 1179 ms today, of which about 85 ms is hashing;
  - the write of 362 targets: at most 120 ms, against 165 to 171 ms today.

  With `Import-Module` at its measured 125 to 232 ms, 550 ms gives a total near 0.72 s against a baseline near 1.45 s. That is the 0.50 line with no margin, so the budget is the ceiling, not the goal. The spot numbers go in the pull request next to the benchmark table.
- **Fallback.** If the `Lazy` row's `RatioToBaseline` is still 0.50 or higher once (a) and the bulk path have landed, option (b) applies. The milestone ships with the measured ratio, and the exit criterion in `docs/roadmap-3.0.md` is restated to that ratio in the same pull request. The pull request states the miss plainly, and it needs the owner's sign-off before merging. Option (c) is not used. `Import-Module` stays in the measurement, because it is what a profile pays and the 2.0 number included it.
- **What does not change.** Check 1 still reports the measured ratio against 0.50. Under the fallback, a ratio at or above 0.50 is recorded as a miss, not relabelled as a pass.

### How the result is recorded

- **The pull request description:** the tool's full output table, the pwsh version, the OS, the script and target counts, and the commit.
- **`CHANGELOG.md`**, in a Performance entry under `## [2.1.0]`, following the 2.0 wording: `Startup benchmark over the 173-script set, ten samples each: 2.0.0 lazy median <n> ms, 2.1.0 lazy median <n> ms, ratio <r> against the 0.50 target; an unhashed set <n> ms.`
- **`docs/roadmap-3.0.md`:** milestone 1's status row and a "Shipped" line carry the same numbers, as `docs/roadmap-2.0.md` did for milestone 3.

## 8. Acceptance criteria

The commands use these values:

```powershell
$module = 'C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions'
$set = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers\ps_completers.psd1'
```

Run rules:

- Every numbered check runs in its own `pwsh -NoProfile` process, against `$module` built from the branch.
- Checks that regenerate or edit PS_Completers run in a scratch clone of that repo (`git clone <PS_Completers> <scratch>\PS_Completers`) with the build first on the module path (`$env:PSModulePath = "<repo>\build;$env:PSModulePath"`, or the stamped copy described below before the release commit). The real repo is not touched until after release.
- "2.0.0 build" means `build/CompleterActions` extracted from tag v2.0.0 (`git archive v2.0.0 build | tar -x -C <scratch>\v2.0.0`), never the gallery copy installed on the machine.
- The branch keeps `ModuleVersion = '2.0.0'` until the release commit, so the branch build and the 2.0.0 build report the same version. Every check that is not run by name therefore imports its module by the full path of the `.psd1` and asserts `(Get-Module CompleterActions).ModuleBase` before it runs.
- Two things need a module that reports 2.1.0: the replaced PS_Completers gate in check 3 (`Import-Module -MinimumVersion 2.1.0`) and the version line of check 21. Before the release commit, check 3 runs against a scratch copy of the branch build whose `.psd1` alone is stamped `ModuleVersion = '2.1.0'`, placed first on the module path, and each run asserts that `ModuleBase` is that copy. On the release commit, before the tag, check 3's gate runs once more against the real build, and the version line of check 21 is checked there. It cannot be checked earlier.

### Roadmap exit criteria, expanded

1. **Hashed import is under half the 2.0.0 lazy time.**

   ```powershell
   .\tools\Measure-CompleterStartup.ps1 -BaselineModulePath <scratch>\v2.0.0\build\CompleterActions -Iterations 10
   ```

   Expected: the `Lazy` row has `RatioToBaseline` below `0.50`, and the `LazyNoHash` row is within 10 percent of `Baseline`. A ratio at or above 0.50 follows the fallback in section 7 and is recorded as a miss.

2. **Reset returns failed records to Pending, and the next tab press loads the fixed script.** A strict fixture set (two targets, one script) is imported. The script is then broken so that its first press fails, and fixed again.

   ```powershell
   Import-CompleterSet -LiteralPath $fixtureSet
   TabExpansion2 -InputScript 'fixturecmd ' -CursorColumn 11   # no matches; one record Failed
   # fix the script
   Get-Completer -State Failed | Reset-Completer
   Get-Completer -State Failed                                  # empty
   (Get-Completer -CommandName fixturecmd -Native).State        # Pending
   (TabExpansion2 -InputScript 'fixturecmd ' -CursorColumn 11).CompletionMatches.CompletionText   # the fixed script's values
   (Get-Completer -CommandName fixturecmd -Native).State        # Active
   ```

   A second run adds two records that cannot be reset. The first is a failed fixture record whose runtime value is replaced outside the module with `Register-ArgumentCompleter`. The second is a failed fixture record whose script is deleted. They are ordered so that one of them comes before the resettable record in `Get-Completer -State Failed`. Expected:
   - `Get-Completer -State Failed | Reset-Completer -ErrorVariable e` writes exactly two errors, both starting `Failed to reset the completer`.
   - The resettable record is `Pending` even though an error came before it.
   - `Get-Completer -State Failed` lists exactly the two unresettable records.

3. **`Test-CompleterSet` is empty when the set matches the folder.** In the scratch clone, run `pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1`, then:

   ```powershell
   Test-CompleterSet -LiteralPath .\ps_completers.psd1   # no output; $? is True
   ```

   With the gate replaced as in section 6, `Invoke-Pester -Path ./tests -Output Detailed` passes. The drift `Describe` has two `It` blocks, `keeps every entry on the strict tier` and `has no drift`. The run has the same number of tests as before the change. Before the regeneration, the same gate fails with one `MissingHash` per entry, which is why section 6 orders the adoption steps.

   The check therefore has four separate assertions, each a Pester run in its own process in the scratch clone: (a) the unmodified gate passes under 2.1.0 before regeneration (adoption step 1); (b) the replaced gate fails before regeneration, in `has no drift` only, and `Test-CompleterSet` returns exactly 173 findings, all `MissingHash`; (c) after regeneration the replaced gate passes; (d) runs (a) and (c) report the same test count.

### Schema, fast path, and compatibility

4. **The untouched PS_Completers set imports as before.** Run the following against the 2.0.0 build and against the 2.1.0 build:

   ```powershell
   Import-Module $module
   Import-CompleterSet -LiteralPath $set -WarningVariable w | Select-Object Key, State, ScriptPath, Trusted | ConvertTo-Csv
   ```

   Expected: identical CSV from both builds; 362 rows, all `Pending`; `$w` empty; no error.

5. **Export adds exactly one `Hash` per entry.** In the scratch clone, after the regeneration in check 3:
   - `git diff --numstat ps_completers.psd1` shows 173 insertions and 0 deletions.
   - Every added line matches `^\s{12}Hash    = 'SHA256:[0-9A-F]{64}'$` and sits between `Trusted` and `Targets`.

   Two further export tests:
   - A strict fixture whose targets arrive through `Get-Completer` sorted in a different order from the script is written in script order.
   - A trusted entry whose script is missing is written without `Hash`, with the section 2 warning, and the export succeeds.

6. **The hash does not depend on line endings.** A module test hashes one fixture script written with LF, with CRLF, with a UTF-8 BOM plus CRLF, and with lone CRs, and gets one value. A checked-in fixture has its expected hash as a literal, asserted on both the Windows and the Ubuntu CI legs.

7. **The fast path skips the parse and nothing else.** Pester runs `Import-CompleterSet` over a hashed fixture set with both `Get-CompleterScriptTarget` and `Get-CompleterScriptParseResult` wrapped in the module by pass-through counters, which call the real function so the records are real. Counting only `Get-CompleterScriptTarget` would miss a parse made through another route. Each count, and each entry's verbose line, is asserted, so that a silent fall-through to the parse path cannot pass as a fast-path run:
   - Both are invoked 0 times, and every entry's verbose line is `hash matches`.
   - After one fixture script is edited, each is invoked exactly once, and that entry's verbose line is `hash differs`.
   - The same set with the `Hash` lines removed invokes each once per strict entry.
   - The records are identical across all three runs, in `Key`, `RuntimeKey`, `State`, `ScriptPath`, `Trusted`, and order. The fixture set is written by `Export-CompleterSet`, so its declared order is script order (section 3).
   - A hand-edited copy of one entry lists its targets in reverse order, repeats one, and changes one `CommandName`'s casing, with its hash left matching. It takes the fast path, yields the same keys, states, and script paths, one record per key, in declared order.

   With `-Verbose`, there is one `hash matches`, `hash differs`, or `no hash` line per entry, plus the summary line.

   The same comparison runs against the real set. After the regeneration in check 3, the hashed scratch set is imported under the 2.1.0 build and the unhashed original under the 2.0.0 build. Both runs use `Select-Object Key, RuntimeKey, State, ScriptPath, Trusted | ConvertTo-Csv`. The two outputs are identical, row for row.

8. **A wrong hash never runs unchecked code.**
   - The fixture script contains a construct the grammar rejects and a statement that would create a probe file. The export wrote its hash, and the entry takes the fast path.
   - After the first tab press, the record is `Failed` with the grammar findings in `LoadError`, and the probe file does not exist.
   - A second fixture's entry carries a hand-written matching hash and a target the script does not register. That target's first press ends `Failed` with `did not register a completer for`.

9. **A hashed set imports on 2.0.0.** The set regenerated in check 3 is imported under the 2.0.0 build. Expected: the same CSV as check 4, and no warning. This holds because that set comes from the `Export-CompleterSetFile.ps1` flow, where declared order is script order. It is not claimed for a hand-edited set whose `Targets` are in another order, because 2.0.0 always follows script order.

10. **An unrecognised `Hash` falls back to the parse.** An entry with `Hash = 'SHA512:abc'` imports through the parse path with no problem reported. `Test-CompleterSet` reports `InvalidHash` as a `Warning` for it.

### Bulk path

11. These existing tests in `tests/CompleterSet.Tests.ps1` pass unchanged:
    - `rolls back every entry of the set when a later entry fails to write`
    - `returns the records in set order and keeps a reused record in its place`
    - `supports WhatIf without importing or registering anything`
    - `reuses the Pending records when the same set is imported again without -Force`
    - `registers the valid entries and warns about the rest with -SkipInvalid`

    `reads the session registrations once` still asserts one snapshot, and its per-entry state-pass count becomes one pass per set. A new test counts one runtime-dictionary resolution and one managed-table batch per set.

12. `Import-CompleterSet -LiteralPath $fixtureSet -Confirm`, declining the second of three entries, registers the first and third entries only, and returns their records.

13. `Register-Completer` keeps its per-target transaction. The existing lazy and eager registration tests pass unchanged. Among them, a failure writing the second target of one call leaves the first target registered.

### Reset-Completer

14. An `Active` record from a lazily loaded script is edited and reset with `Reset-Completer -CommandName fixturecmd -Native -PassThru`. The call returns one `Pending` record with an empty `LoadError`, and the next tab press returns the edited script's values.
15. `-WhatIf` prints `What if: Performing the operation "Reset completer registration" on target "fixturecmd".` and changes no state. A `Pending` target is left alone without a prompt.
16. Each error row in the section 5 table has a test asserting its message: a `Discovered` target, a script-block `Active` target, a `Stale` target, a `Failed` target re-registered outside the module, a missing target, and a missing script. Each error is non-terminating. A precedence test resets a `Pending` record whose script was deleted, and gets no error and no change.
17. `Get-Command Reset-Completer -Syntax` shows the three parameter sets of section 5. The `CommandParameter`, `Native`, and `InputObject` sets match `Unregister-Completer`'s names, types, and pipeline bindings, apart from `-AllowUnmanaged`.

### Test-CompleterSet

18. On the regenerated scratch set, each of these single mutations yields exactly the findings listed, and reverting it yields none:

    | Mutation | Findings |
    | --- | --- |
    | Append a comment to one script | `HashMismatch` (Warning) |
    | Add `new_completer/new_completer.ps1` | `UnlistedScript` (Warning) |
    | Delete one script | `MissingScript` (Error) |
    | Add a `Register-ArgumentCompleter` target to one script | `HashMismatch` (Warning) and `TargetMismatch` (Error) |
    | Delete one `Hash` line | `MissingHash` (Warning) |
    | Copy one entry's `Targets` into another entry | `TargetMismatch` (Error) on the receiving entry only. That entry has no resolved targets, so it claims nothing and no duplicate is reported, as at import. |
    | Duplicate one whole entry block, `@{ ... }` included | `DuplicateTarget` (Error) on the copy, one per target, each naming the original entry |

    Every finding's `Path` is the set file, and its `Line` points at the extent named in section 6. For every mutation, `Import-CompleterSet` without `-SkipInvalid` rejects the set exactly when the mutation's findings include an `Error`.

19. `Test-CompleterSet` over a set whose file is not `Version = 1` throws `Failed to test completer set. ...`. It never executes a script: the probe-file fixture from check 8 stays absent. Given a valid set followed by a set without `Version = 1`, the call writes the first set's findings and then throws. Given a path that does not resolve, it throws before writing anything.

### Neutrality and repository gates

20. **PSReadLine snapshots.** These existing tests pass:
    - `leaves PSReadLine key handlers unchanged across import, first tab, and export` (`tests/CompleterSet.Tests.ps1`)
    - `... across lazy registration, first tab, and removal` (`tests/CompleterLazyRegistration.Tests.ps1`)
    - `leaves PSReadLine key handlers unchanged` (`tests/CompleterAuthorTooling.Tests.ps1`)

    A new test asserts an identical `Get-PSReadLineKeyHandler -Bound -Unbound` snapshot across `Reset-Completer`, the reloading tab press, and `Test-CompleterSet`.

21. **Surface.** After `Import-Module $module`:
    - `(Get-Module CompleterActions).Version` is `2.1.0`. This line is checked on the release commit only (run rules above).
    - `Get-Command -Module CompleterActions` lists 13 functions and 3 aliases.
    - For each of the 11 functions 2.0.0 exports, the parameter names and parameter sets are identical to the 2.0.0 build's.

22. **Suite and lint, in separate processes.**
    - `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"` passes.
    - In another process, `Invoke-ScriptAnalyzer` over `./src` and `./tests` with `./PSScriptAnalyzerSettings.psd1` returns nothing.
    - All eight CI legs are green.
    - `Get-Help Reset-Completer -Full` and `Get-Help Test-CompleterSet -Full` resolve from the build.

## 9. Open questions for the owner

All eight resolved on 2026-09-28 in favour of the recommendation stated under each. They stay here as the record of the alternatives considered.

1. **Which `Active` records can be reset?** The record class has no lazy flag (`src/Classes/CompleterTypes.ps1`). An `Active` record loaded by a stub looks the same as one from `Import-CompleterScript | Register-Completer`: both carry `ScriptPath`, `Trusted`, and `ImportModule`. `Resolve-CompleterRegistrationConflict` already treats the two alike when a set is re-imported.
   - Recommendation: accept any managed `Active` record with a `ScriptPath`, as section 5 does.
   - Alternative: add a lazy marker property to `CompleterRegistration`. That is an additive property on a class that 3.0 makes public.
2. **Resetting a `Pending` record.** Recommendation: a silent no-op that `-PassThru` still returns, so `Get-Completer | Where-Object ScriptPath | Reset-Completer` does not write one error per `Pending` record. Errors no longer stop the call in any case (section 5). The alternative is an error.
3. **A stale hash at import.** Recommendation: verbose only. A profile that imports a slightly stale set stays quiet, and `Test-CompleterSet` is where staleness is reported. The consequence is that `-Verbose` and `Test-CompleterSet` are the only places a stale hash shows. The PS_Completers CI gate is what keeps the owner's profile fast, because that profile discards warnings anyway (section 3). The alternative is one summary warning per set when any hash differs.
4. **`MissingHash` severity.** Recommendation: a `Warning`, so "empty" means the set is fully on the fast path. The consequence is that every set written by 2.0 reports one finding per entry until it is regenerated. The alternative is not to report absent hashes at all.
5. **The default `-Filter` for the unlisted scan.** Recommendation: `*_completer.ps1`, which matches the module docs, the benchmark tool, and the PS_Completers layout. `*.ps1` would flag that repo's `tools/Export-CompleterSetFile.ps1` and `tests/Completers.Tests.ps1`.
6. **If the bulk path does not reach 0.50.** Resolved in section 7, "Committed mechanism, budget, and fallback". The measurements put the hash alone near 0.62, and three options were considered:
   - (a) extend the fast path to build stubs and records in one pass and resolve declared targets in one pass;
   - (b) accept the measured ratio and restate the exit criterion;
   - (c) measure `Import-CompleterSet` alone and exclude `Import-Module`.

   The spec commits to (a) with a 550 ms `Import-CompleterSet` budget, falls back to (b) with the owner's sign-off, and never uses (c). The owner can still overrule the fallback before the milestone branches.
7. **`about_Completer_Sets` in 2.1.0.** The roadmap puts the hash and drift sections in the 2.2.0 author guide. Recommendation: 2.1.0 adds `Hash` to the schema list and one paragraph each on the fast path and `Test-CompleterSet`, so a shipped key is never undocumented. The full sections still land in 2.2.0.
8. **Resetting siblings.** Recommendation: reset only the named targets, as section 5 says, and document the whole-script pipeline. The alternative, expanding a reset to every target of the same script and tier, would make one target's reset reload targets the caller did not name.
