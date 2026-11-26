# Milestone 1 specification: authoring, second pass (3.1.0)

Drafted: 2026-11-25, revised the same day after two reviews (the option rules prototyped against the captures, and every cited fact checked against the source; plan coverage and implementability)
Base: main at `b0aa0be` (3.0.1 stable, release commit `820d224`, tag v3.0.1; the only change since the tag is `.github/workflows/ci.yml`)
Roadmap: `docs/roadmap-4.0.md`, milestone 1, and proposed decisions 2 and 3, which the owner locked on 2026-11-25. Milestones 2 and 3 are out of scope.
Kind: behaviour spec. It states what the module does after 3.1.0 and how a reader can tell. It does not prescribe helpers, file splits, or commit order; the plan (`docs/roadmap-4.0/milestone-1-plan.md`) does.
Status: accepted. The owner answered every question of section 14 on 2026-11-25, each as recommended, and sections 1 to 13 are written to those answers. The owner also chose to have the roadmap edits of section 11 made in the same commit as this spec.

Owner decisions this spec carries, all made on 2026-11-25:

- 3.1.0 starts now; the roadmap's trigger is waived once.
- `Update-CompleterSet` reports scripts the set does not list and never adds an entry.
- `Test-CompleterRegistration` gains `-TargetOnly` (2026-11-18 review, finding 5).
- The help probe resolves an app execution alias's target, checks the target's subsystem, and runs the alias.
- The defect fixes ruled the same day ship inside 3.1.0, not as a 3.0.2: review findings 7, 9, and 11, the capture variable names, the tests that probe `pwsh` by name, and the help note on stems that differ only by case.
- Pushes to main that change only `docs/**` or `CHANGELOG.md` start no CI run.

Every claim about current behaviour cites the file it was read from. Probes and measurements in this document were taken on 2026-11-25 on the owner's Windows machine (Windows 11 10.0.26300, PowerShell 7.7.0 from the Microsoft Store, not elevated), against the installed CompleterActions 3.0.1, whose `src` is identical to `b0aa0be`, and the PS_Completers repository at `9db457c`. Linux behaviour was not checked for this draft; the plan says where it is proven.

## 1. Scope and non-goals

3.1.0 is an additive release on the 3.x line, with six defect fixes folded in.

- No command, parameter, property, or enum value is renamed or removed. The engine floor stays 7.4 and the core assembly keeps `AssemblyVersion` 3.0.0.0 (question 9).
- One public command is added, `Update-CompleterSet`. The module then exports 12 functions and no alias (3.0.1 exports 11, `CompleterActions.psd1` lines 75 to 87). Two tests pin the list and change with it: `tests/CompleterActions.Tests.ps1` "exports exactly the eleven functions and no alias" and the eleven cases of `tests/CompleterClasses.Tests.ps1` "declares the 2.2.0 output type name on \<Command\>".
- Four existing commands gain parameters. Each new parameter is optional, or mandatory only inside a new parameter set, so no 3.0.1 call binds differently:
  - `New-CompleterScript -Documentation`;
  - `Import-CompleterSet -MinimumVersion` and `-RequiredVersion`, and the same two on `Test-CompleterSet` (question 4);
  - `Test-CompleterRegistration -TargetOnly`.
- No public type gains a property, and no type is added to the `CompleterActions` namespace (question 6). The `CompleterActions.Internal` namespace, which is not a contract, gains one class for section 7.
- The set file schema is unchanged: `Version = 1`, `Path`, `Trusted`, `Hash`, `Targets`.
- PSReadLine neutrality holds for everything added.

Four things change for input that 3.0.1 accepted. Each is a defect fix the owner ruled on, each is listed under Changed in the changelog, and section 8 gives the detail:

| Change | Who sees it |
| --- | --- |
| A script that gives `-ParameterName` an array is refused by the strict grammar | A script that registers several parameters in one call; none of the 176 PS_Completers scripts does |
| `Export-CompleterSet -Path` refuses a path on another provider, and a provider-qualified relative path | A caller that passes such a path; today the first fails with a misleading text and the second writes entry paths against the wrong folder |
| A completer script's own `$ScriptInfo` or `$CapturedCompleterDefinitions` state is no longer shadowed during import | A script that uses either name |
| The scripts `New-CompleterScript` generates carry an option table, a second completion branch, and new comment lines | Anyone who regenerates a script; scripts generated earlier keep working unchanged |

In scope:

| Item | Kind | Section |
| --- | --- | --- |
| Option seeding in `New-CompleterScript` | feature | 2 |
| `New-CompleterScript -Documentation` | feature | 3 |
| Version selection for `-Name` | feature | 4 |
| `Update-CompleterSet` | feature | 5 |
| `Test-CompleterRegistration -TargetOnly` | feature | 6 |
| App execution aliases in the help probe | feature | 7 |
| Folded fixes | fix | 8 |
| Help, about topics, README, changelog | docs | 9 |
| Import-time non-regression | perf check | 10 |
| `3.1.0-preview1`, then `3.1.0` | release | 11 |

What a reader can see after 3.1.0:

| Observation | How to tell |
| --- | --- |
| An option-only tool gets a seeded script | `New-CompleterScript -CommandName rg -Path .\rg_completer.ps1 -PassThru \| Test-CompleterScript` returns nothing, the script's `Options` table has rows, and `rg --reg<Tab>` offers `--regexp` once the file is registered |
| A profile can pin a set version by name | `Import-CompleterSet -Name PS_Completers -MinimumVersion 1.1.3` |
| Drift is fixed without regenerating the set | `Test-CompleterSet .\completers.psd1 \| Update-CompleterSet`, after which `git diff` shows only `Hash` values |
| A Store-installed tool is probed | `New-CompleterScript -CommandName winget -Path .\winget_completer.ps1 -Verbose` shows a probe line with exit 0 |

Non-goals:

- **No value seeding.** The option table holds names and descriptions. An argument placeholder such as `<ARG>` or `=VALUE` is recognised so the name is read correctly, and then dropped. The generated script completes no option value.
- **No option parsing from a usage synopsis.** git prints its options only inside `usage: git [-v | --version] ...`; it gets no option rows.
- **No per-subcommand options.** Only the help the scaffold already reads is parsed; `cargo build --help` is never run.
- **No new entries from `Update-CompleterSet`,** and no `-Name` on it: the command takes set files, not installed module names. It rewrites whatever set file it is given, a package's source and an installed copy alike.
- **No `MissingHash` repair.** An entry without a `Hash` has no value to rewrite, and adding a line is `Export-CompleterSet`'s job (question 5).
- **No PATH search past the first match.** The probe still takes the first application `Get-Command` returns. It no longer refuses that match for being an alias.
- **No prerelease labels in version selection.** A package folder is its `ModuleVersion`, and the label is display text, as today (`src/Private/Resolve-CompleterSetModule.ps1` lines 183 to 193).
- **No engine cmdlet path.** It is still gated on a shipped engine (3.0 decision 3).
- **Milestone 2 of the roadmap** (`Measure-Completer`, `-FromGenerator`, `-SkipHashCheck`) is untouched and still waits for its trigger.

## 2. Option seeding in New-CompleterScript

`New-CompleterScript` reads option rows from the same help text that feeds the subcommand table, in all three ways the text can arrive: the probe, `-HelpText`, and pipeline input. `-NoProbe` reads nothing, as today. No parameter is added for this, and there is no switch that turns it off (question 1).

Current behaviour, for reference. `src/Private/ConvertFrom-CompleterHelpText.ps1` returns subcommand rows only. A name must start with `/?[A-Za-z0-9]` (line 35), so a line that starts with `-` is never a row, and a `/X` line is a row only inside a commands section. `src/Private/Get-CompleterScriptSkeleton.ps1` emits a catalog with one key, `Subcommands`, and a function that returns as soon as more than one element precedes the cursor (lines 128 to 131).

### Finding option sections

The text is the cleaned help text the subcommand parser already receives. A line's indent is its count of leading white-space characters, a tab counting as one. The rules were prototyped on 2026-11-25 against the fourteen captures and against GNU `du` 9.5, and reworded where the first draft failed on `7z`, `du`, and cargo.

1. **Option line.** A line whose first non-blank characters begin an option name: `-` followed by a letter, a digit, `?`, or `.`; `--` followed by a letter or a digit; or `/` followed by a letter, a digit, or `?`. A line that is `--` alone, or `--` followed by white space, is also an option line, one that gives no row (7z's `-- : Stop switches and @listfile parsing`).
2. **A section opens in one of two ways,** and only while no option section is open:
   - **With a heading.** A line that has the shape the subcommand parser already uses for a heading (one to six words, an optional `<...>` wrapper, an optional trailing colon; `ConvertFrom-CompleterHelpText.ps1` line 34), that is not a commands heading, and whose next non-blank line is an option line. No word list is involved, so `Options:`, `Global Options:`, `FLAGS`, `General Options:`, `OUTPUT MODES:`, `<Switches>`, `Parameter List:`, and `The following options are available:` all qualify.
   - **Without one.** An option line that is not under a commands heading, when at least one more option line at the same indent follows it before the extent of rule 3 would end. GNU tools print their options this way: `du --help` has no heading at all.

   Because a section opens only while none is open, a wrapped description line that happens to look like a heading (cargo's `details`, rg's `flag again:`) starts nothing.
3. **Extent.** A section with a heading runs to the line before the next non-blank line that is indented no deeper than the heading and is not an option line. A section without one runs to the line before the next non-blank line that is indented less than its first row and is not an option line. Either runs to the end of the text if no such line comes. Blank lines do not end an option section, because rg and schtasks put one between rows.
4. **Section indent.** The smallest indent of any option line in the extent. A line is a row when it is an option line at the section indent. A line that starts with `--` and sits exactly four columns deeper is also a row, but only when no row at the section indent starts with `--`. That admits cargo's and docker's layout, where a long-only option is aligned under the long names (`      --list` under `  -V, --version`), and keeps out rg's description lines, which sit four columns below rows that are themselves long-only. A single-dash line deeper than the section indent (7z's `-mmt[N]` under `-m{Parameters}`) is never a row.
5. **Everything else in the extent** is description or prose and gives no row.

A line under a commands heading stays a subcommand row exactly as today, so bcdedit's `/store` rows are subcommands and gain no option twin. A `/X` row under an option heading (schtasks' `/Create` under `Parameter List:`) is an option.

### Reading a row

A row holds one or more names, optional argument placeholders, and an optional description.

- **Names** are separated by a comma with or without a following space: `-x, --long`, `-v,--version`, `--logs,--open-logs`.
  - A short name is `-`, then one letter, digit, `?`, or `.`, then any letters, digits, `_`, or `-` (`-V`, `-?`, `-.`, `-ao`).
  - A long name is `--`, then a letter or a digit, then any letters, digits, `_`, or `-`.
  - A slash name is `/`, then letters, digits, or `?`.
  - A name ends at the first other character, so cargo's `--verbose...` gives `--verbose`.
  - Text after a comma that is not a name ends the list of names; the names read so far are kept.
- **Argument placeholder.** After a name, any of these is read and dropped:
  - `=TEXT` or `[=TEXT]`, where `TEXT` runs to the next white space or comma (`--regexp=PATTERN`, `--max-filesize=NUM+SUFFIX?`);
  - a space and `<TEXT>`;
  - a space and one word, a letter followed by letters, digits, `_`, or `-`, all in upper case or all in lower case, when it is followed by a comma, by two or more spaces, or by the end of the line (`-e PATTERN, --regexp=PATTERN`; docker's `--context string`);
  - an attached bracket or brace group (`-ao{a|s|t|u}`, `-bb[0-3]`). A nested or repeated group is not followed; whatever remains before the description separator is ignored.
- **Description.** The text after the first run of two or more spaces, a tab, or ` : ` that follows the names and placeholders. When the row has none, and the next non-blank line is indented deeper than the row and is not itself a row, that line is the description (rg's layout, and pip's `--keyring-provider`). Only that one line is used; wrapped lines after it are dropped, as they are for subcommands. The text is cleaned as subcommand descriptions are (`ConvertFrom-CompleterHelpText.ps1` lines 127 to 132), and an empty result becomes the name.
- A row yields one table row per name, in the order written, each with the row's description. `-e PATTERN, --regexp=PATTERN` gives `-e` and `--regexp`.
- **Duplicates.** A name already in the table, compared ordinally, is dropped, first kept. `-c` and `-C` are different options and both stay.
- A candidate row whose first name does not parse gives nothing, and the scan goes on.

Two shapes are knowingly read wrong, and neither occurs in the captures: a one-word description after a single space (`-v verbose`) is taken for a placeholder, and a mixed-case placeholder such as `stringArray` is taken for the start of a description.

There is no cap on the number of rows, as there is none for subcommands.

Expected results from the checked-in captures (`tests/Fixtures/NewCompleterScript/`), stated as shapes; the plan records each capture's exact names in an expected-options file, written by hand from the help before the parser is run against it, and those files are the assertion (section 13, fixture provenance). The counts are from the review's prototype of the first draft and are a cross-check, not the assertion:

| Capture | Option rows |
| --- | --- |
| `cargo` | the rows under `Options:`, short and long names both, with `--verbose` and not `--verbose...` (17 names) |
| `pip`, `docker`, `rustup`, `winget`, `gh` | the rows under their option heading (30, 16, 8, 15, and 2 names) |
| `rg` | the 104 rows at indent 4 under its seven headings; nothing from the description lines at indent 8 or deeper (145 names) |
| `7z` | the names at the section indent under `<Switches>`, without their brace and bracket groups; nothing from the lone `--` or from the deeper single-dash lines |
| `schtasks` | `/Create` and its seven neighbours under `Parameter List:` |
| `bcdedit` | its `/X` lines under a commands heading stay subcommand rows and give no option. Seven more sit under headings of eight to ten words, which no rule reaches today (`CAPTURES.md`); the section without a heading may now read them as options, and the expected-options file records which |
| `git`, `go`, `kubectl`, `sc` | none |
| `du` (new capture, question 2) | every option of GNU `du`, through the section without a heading (about 46 names) |

### The generated script

The skeleton changes in three places. Everything else in it is as 3.0.1 writes it.

- **Line 2** is one of:
  - no row of either kind: `# Native completer skeleton: add subcommands and options to the tables.`
  - seeded by a probe: `# Help-seeded native completer: the tables were read from '<Name> <Argument>' when the script was generated.`
  - seeded from help text: `# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.`

  "Seeded" means at least one subcommand or option row.
- **The catalog** has two keys, in this order. `Options` is written exactly as `Subcommands` is: `Options = @()` when empty, otherwise one `@{ Name = '<n>'; Description = '<d>' }` row per line, in help order, with the same quoting.

  ```powershell
  if (-not (Get-Variable -Name RgCompletionCatalog -Scope Script -ErrorAction Ignore)) {
      $script:RgCompletionCatalog = @{
          Subcommands = @()
          Options = @(
              @{ Name = '-e'; Description = 'A pattern to search for. This option can be provided multiple times,' }
              @{ Name = '--regexp'; Description = 'A pattern to search for. This option can be provided multiple times,' }
          )
      }
  }
  ```

  Both tables are plain literal hashtables inside the guarded `if`, which the strict grammar accepts (checked 2026-11-25 with `Test-CompleterScript` 3.0.1 on a scratch script of this shape: no finding). A cast such as `[ordered]` is refused by the grammar, so none is used.
- **The function** offers options before the position check, in any argument position, when the word being completed starts with `-` or `/`:

  ```powershell
      # Offer options in any position once the word starts with '-' or '/'.
      if ($wordToComplete.StartsWith('-') -or $wordToComplete.StartsWith('/')) {
          foreach ($option in $script:RgCompletionCatalog.Options) {
              if ($option.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                  [System.Management.Automation.CompletionResult]::new($option.Name, $option.Name, 'ParameterName', $option.Description)
              }
          }
      }

      # Offer subcommands in the first argument position only; extend this function for values.
  ```

  The subcommand branch below it is unchanged apart from that comment. An empty word offers no option, so `rg <Tab>` still falls through to PowerShell's file names. A word that starts with `/` and matches no option returns nothing from this branch, so a path such as `/usr` completes as before.

The `Register-ArgumentCompleter` call, `Set-StrictMode`, encoding, and line endings are unchanged.

A script generated by 3.0.1 has no `Options` key and never reads one, so it keeps working.

### Probe and messages

- The Windows `/?` fallback runs when `--help` gave no subcommand **and no option** and fewer than five non-blank lines (today: no subcommand; `src/Private/Get-CompleterHelpSubcommand.ps1` line 112).
- The probe's verbose line becomes `Probed '<path> <arg>': exit <n>, <n> characters, <n> subcommands, <n> options, <n> ms.`
- The final verbose line becomes `Wrote '<path>': <n> targets, <n> subcommands, <n> options.`
- No warning text changes. Help that yields no row of either kind is still not a warning.
- The self-check is unchanged: the generated text must pass the grammar and register the expected targets, or nothing is written (`src/Private/Save-CompleterScriptFile.ps1`).

## 3. New-CompleterScript -Documentation

A switch, in all three parameter sets, off by default. With it, the command also writes a markdown file beside the script: the same folder and base name with the extension `.md`, which is where all 176 PS_Completers completers keep theirs.

Content, for `-CommandName rg` (question 3):

```markdown
# rg completer

## What it completes

`rg_completer.ps1` registers a native PowerShell completer for `rg` and `rg.exe`.
```

- Line 1 names the first command name. The sentence names the script file and every target, in registration order, joined with commas and a final `and`.
- The file is UTF-8 without a byte-order mark, uses the platform newline, and ends with a newline, as the script does. The same input gives the same bytes.
- **Existing file.** When the markdown file exists and `-Force` is not given, the call fails before anything runs with `Failed to create completer script. The file '<md path>' already exists. Use -Force to overwrite it.`, and neither file is written. `-Force` replaces both.
- **Order.** Both files are written to temporary files first, and the script passes its self-check before either is moved. The script is moved into place first, then the markdown file. If the second move fails, the call fails with `Failed to create completer script. The script '<path>' was written, but its documentation file '<md path>' was not: <reason>`, and no temporary file remains.
- **ShouldProcess.** Still one call on the script path. Each action text begins `Create completer script and documentation` in place of `Create completer script`. Under `-WhatIf` neither file is written.
- **Output.** `-PassThru` still returns the script's `System.IO.FileInfo` only, so the pipe to `Test-CompleterScript` is unchanged. A verbose line `Wrote '<md path>'.` follows the script's.

Without `-Documentation`, no `.md` file is read, written, or checked for.

## 4. Version selection for -Name

`Import-CompleterSet` and `Test-CompleterSet` (question 4) gain two parameters in their `Name` set:

```text
Import-CompleterSet -Name <string[]> [-MinimumVersion <version>] [-RequiredVersion <version>] [-SkipInvalid] [-Force] [-WhatIf] [-Confirm]
Test-CompleterSet   -Name <string[]> [-MinimumVersion <version>] [-RequiredVersion <version>] [-Filter <string>]
```

Current behaviour, for reference: `src/Private/Resolve-CompleterSetModule.ps1` walks `$env:PSModulePath` in order; the first root that holds a valid candidate wins, and inside it the highest version folder whose manifest `ModuleVersion` equals the folder name. The unversioned layout, a manifest directly in the module folder, is used only when its root has no versioned candidate. Versions are `System.Version` values.

With neither parameter, resolution is exactly as in 3.0.1.

With either parameter, each root's candidates are its version folders that pass today's manifest check, and its unversioned manifest as well when that manifest's `ModuleVersion` parses as a version. The unversioned copy takes part beside the version folders here, as it does for `Import-Module` (run 2026-11-25: with a versioned 1.0.0 and an unversioned 2.0.0 in one root, `Import-Module -MinimumVersion 1.5.0` loads the 2.0.0).

- **`-RequiredVersion`** selects the candidate equal to the value. The roots are walked in order and the first root that holds one wins.
- **`-MinimumVersion`** selects, in the first root that holds any candidate equal to or above the value, the highest such candidate. A root whose candidates are all lower is passed over, so a newer copy in a later root is found. This matches `Import-Module -MinimumVersion` across two roots (run the same day).
- A version folder that differs from its manifest's `ModuleVersion` is not a candidate, as today. An unversioned manifest whose `ModuleVersion` does not parse is not one either.
- `System.Version` equality is exact: `1.2.0` and `1.2.0.0` differ, as they already do between a folder and its manifest (checked 2026-11-25). The help says to write the version as the folder is named.
- A prerelease label never takes part. `2.0.0-preview1` is installed in the folder `2.0.0`, and `-RequiredVersion 2.0.0` selects it.
- Once a version is selected, a broken declaration in it fails the call. There is no fall back to a lower version, as today.

Errors, each wrapped in the command's own prefix (`Failed to import completer set. ` or `Failed to test completer set. `):

- Both parameters given: `-MinimumVersion and -RequiredVersion cannot be used together.`
- Either parameter with more than one name: `-MinimumVersion and -RequiredVersion apply to one module name, but <n> names were given.`
- No match for `-RequiredVersion`: `` No installed module named '<Name>' with version <v> was found in $env:PSModulePath. Installed versions: <list>. `` The list holds every candidate's version from every root, highest first, de-duplicated; when no root holds a candidate at all, today's not-found text is used unchanged.
- No match for `-MinimumVersion`: the same with `version <v> or later`.

The verbose line and the trusted-entry warning keep their 3.0.1 text and show the selected version.

## 5. Update-CompleterSet

```text
Update-CompleterSet [-Path] <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm]
Update-CompleterSet -LiteralPath <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm]
Update-CompleterSet -InputObject <CompleterScriptFinding[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm]
```

- `-Path` (position 0, wildcards, pipeline by value and by property name, alias `FullName`) and `-LiteralPath` (alias `PSPath`) bind as they do on `Test-CompleterSet`.
- `-InputObject` takes the findings `Test-CompleterSet` writes, from the pipeline. Only each finding's `Path`, the set file, is used, taken literally and de-duplicated. A finding names which set to update; it does not name which entries. A finding binds here only from the pipeline or by name: given positionally it would bind to `-Path` as text, and the help says so.
- `-Filter` defaults to `*_completer.ps1`, as on `Test-CompleterSet`.
- `SupportsShouldProcess`, `ConfirmImpact` `Medium`, as `Import-CompleterSet` has.
- Synopsis: `Rewrites the Hash of each completer set entry whose script has changed, leaving the rest of the set file as it is.`

### What it does

For each set file, once, in `end`, so a piped `Test-CompleterSet` has finished reading before anything is written:

1. Read the file and verify every entry the way `Test-CompleterSet` does. Findings carry positions from an earlier read, so they are never trusted for where to write.
2. An entry is **updated** when all of these hold:
   - it has a `Hash` value, well formed or not (`Test-CompleterSet` reports it as `HashMismatch` or `InvalidHash`);
   - its script can be read, so the actual hash is known;
   - it has no problem that `Test-CompleterSet` reports as an Error: `MissingScript`, `InvalidEntry`, `UnreadableTargets`, `TargetMismatch`, or `DuplicateTarget`.
3. The `Hash` value of each updated entry is replaced with the script's current hash, written as Export writes it: a single-quoted `SHA256:` followed by 64 upper-case hex digits.
4. Nothing else in the file changes.

The third condition of step 2 is the point of the command's care. A matching `Hash` makes `Import-CompleterSet` skip the comparison of declared and derived targets (`src/Private/Resolve-CompleterSetEntry.ps1` lines 316 to 330). Rehashing an entry whose targets also changed would make import register the stale `Targets` without a check. Such an entry needs `Export-CompleterSet`.

An entry whose declared hash equals the script's, ignoring letter case, is not touched, as `Test-CompleterSet` does not report it.

**Trusted entries** are updated too, with a warning each (question 11). A trusted script is never parsed (`Resolve-CompleterSetEntry.ps1` lines 259 to 285), so its declared `Targets` cannot be compared with what it registers, and import ignores a trusted entry's `Hash`. The `Hash` there only feeds `Test-CompleterSet`, and rewriting it clears that signal without any check of the targets, which is what the warning says.

A malformed `Hash` is repaired as well as a stale one. The roadmap item says "the entries `Test-CompleterSet` reports as changed"; a malformed value is a `Hash` that cannot detect a change, and its fix is the same replacement (section 11, edit 10).

### Byte identity

- The file is read once as bytes. Its encoding and byte-order mark are detected as the set reader detects them (`src/Private/Import-CompleterDataFile.ps1` line 85).
- Each replacement is spliced into the decoded text at the value's extent in the parsed file, last entry first. No line outside a replaced value is split or joined, so a file with LF endings keeps them (the PS_Completers set is LF; an export on Windows is CR LF), and a `Hash` that shares its line with other keys is handled.
- The result is encoded with the same encoding and the same byte-order mark.
- If decoding and re-encoding the unchanged text does not give the original bytes, the file is not written: `'<set>' cannot be rewritten without changing bytes outside its Hash values, because its text does not round-trip in its encoding. Regenerate the set with Export-CompleterSet.`
- A double-quoted or here-string `Hash` value is replaced by the single-quoted form, on one line. That is the one change inside a replaced value besides the digits.
- The new text is parsed again before it is written and must give the same entries, paths, and targets as before, or the call fails with `Update-CompleterSet did not produce an equivalent set, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues.`
- A result over the 131072-byte limit for set files fails with the text `Export-CompleterSet` uses for a set it would write over the limit (`src/Public/Export-CompleterSet.ps1` line 376), and nothing is written. A replacement changes the file's length only when the old value was not already a single-quoted `SHA256:` and 64 digits.
- The write is atomic: a temporary file beside the set, then a replacing move. A set with nothing to update is not written, and its timestamp does not change.

### Reporting

- **Skipped entries.** One warning per entry that has a `Hash` and an Error problem, whether or not its hash differs: `Entry <n> ('<path>') of '<set>' was not updated: <problem> Regenerate the set with Export-CompleterSet.` `<problem>` is the entry's first Error problem as `Test-CompleterSet` words it, without that finding's leading `Entry <n> ('<path>'): ` label; it already ends with a period.
- **Trusted entries.** One warning per trusted entry that is updated: `Entry <n> ('<path>') of '<set>' is trusted, so its Targets were not checked against the script.`
- **Entries without a `Hash`.** One warning per set that has any: `Entries of '<set>' without a Hash were not updated: <n>. Regenerate the set with Export-CompleterSet to add them.`
- **Unlisted scripts.** One warning per script under the set's folder that matches `-Filter` and that no entry lists, with the text `Test-CompleterSet` already uses for `UnlistedScript` followed by ` Add it with Export-CompleterSet.` Nothing is added to the set.
- **Verbose.** `Updated the Hash of entry <n> ('<path>') in '<set>'.` per entry, then `Updated <n> of <m> entries in '<set>'.` per set.
- **ShouldProcess.** One call per set that has something to update, on the set path, with the action `Update <n> Hash values`. Under `-WhatIf` nothing is written, and the warnings are still written.
- **Output.** Nothing by default. `-PassThru` returns the `System.IO.FileInfo` of each set that was written.
- **Errors.** A set that cannot be read fails with the reader's existing text, wrapped in `Failed to update completer set. `, as a terminating error.

A file that is not a set, a directory, and a non-`.psd1` path fail with the reader's existing texts under that prefix.

## 6. Test-CompleterRegistration -TargetOnly

A switch on every parameter set. With it, the command writes only the matches whose `FromTarget` is `$true`. Without it, nothing changes: every match the engine returns is written, as in 3.0.1.

- With no match from the target, nothing is written and `$?` is true, as for no match at all today.
- The filter is applied to the finished matches. How `FromTarget` is computed (`src/Public/Test-CompleterRegistration.ps1` lines 216 to 252) does not change: it matches by completion text and records the first engine call.
- The help's third example and `about_Import_Completers` show `-TargetOnly` in place of `| Where-Object FromTarget`, and keep one sentence saying the two are equivalent.

Whether `-TargetOnly` becomes the default is a 4.0 question and is not decided here.

## 7. App execution aliases in the help probe

Current behaviour. On Windows, `src/Private/Resolve-CompleterHelpProbeApplication.ps1` takes the first application `Get-Command` returns and allows it to run only when it is a `.exe` whose header reads as a console program. An app execution alias is a zero-byte reparse point, so the header read fails (`The file cannot be accessed by the system.`) and the probe warns `its program header could not be read`. On the owner's machine that refuses `pwsh` and `winget` (appendix A).

After 3.1.0, on Windows, when the resolved file is a `.exe` whose header cannot be read:

1. The probe reads the file's reparse data. When the tag is `IO_REPARSE_TAG_APPEXECLINK` (0x8000001B), the third string of the data is the target executable.
2. The target must be a fully qualified path to an existing file with the extension `.exe`. Its header is read, and the subsystem rules that apply to an ordinary `.exe` apply to it: console runs, GUI and every other subsystem do not.
3. When the target is a console program, **the alias is what runs**, with the probe's usual settings. The resolved application's path stays the alias path in every message, because that is the program the user's shell would start.

A file that is not an alias, or an alias on which step 1 fails, keeps today's warning unchanged. The data's version field is not checked: every alias read on 2026-11-25 carried version 3, and a layout that has no third string is the "no target" case below. Nothing about the PATH search changes.

Messages:

- A new verbose line after `Resolved '<name>' to the application '<path>'.`: `'<path>' is an app execution alias for '<target>'.`
- The warning keeps its form, `'<path>' was not run: <reason>. Run '<name> --help' yourself and pass the text with -HelpText.`, with these reasons:

  | Case | Reason |
  | --- | --- |
  | The alias has no target path | `it is an app execution alias with no target` |
  | The target is not a fully qualified path, or does not exist | `its target '<target>' does not exist` |
  | The target is not a `.exe` | `its target '<target>' is not a .exe file` |
  | The target's header cannot be read | `the program header of its target '<target>' could not be read` |
  | The target is a GUI program | `its target '<target>' is a Windows GUI program` |
  | The target has another subsystem | `its target '<target>' is not a Windows console program (subsystem <n>)` |

- The `-WhatIf` and `-Confirm` action text names the alias path, as it names any resolved application today.

On Linux and macOS nothing changes, and the code that reads reparse data is never called.

Reading the reparse data needs a Windows API call from the compiled core, which has none today (`src/Core` has no `DllImport`). It needs no elevation (appendix A). The plan owns the design; the behaviour above is the contract.

## 8. Folded fixes

### An array given to -ParameterName (2026-11-18 review, finding 7)

Current behaviour. `src/Core/Grammar/StrictGrammar.cs` (`TestIsSupportedRegisterArgumentAst`, lines 124 to 158) accepts a literal array for `-ParameterName` as it does for `-CommandName`. `Register-ArgumentCompleter` declares `-ParameterName` as a single string, so `-ParameterName 'a', 'b'`, `@('a', 'b')`, and `@('a')` all fail to bind when the script is dot-sourced (`Cannot convert 'System.Object[]' to the type 'System.String' required by parameter 'ParameterName'`, run 2026-11-25). The module's own import does not fail: its capture function declares `[string[]] $ParameterName` (`src/Private/Import-CompleterScriptDefinition.ps1` line 66), so `Import-CompleterScript` returns one record per name.

After 3.1.0, `Test-CompleterScript` reports an Error for an array literal or an `@( )` array of any element count given to `-ParameterName`, at the argument, with the argument's AST type as `Construct`:

- Message: `The script passes an array to -ParameterName.`
- Hint: `Give -ParameterName one literal string; Register-ArgumentCompleter binds a single parameter name. Register each parameter with its own call.`

Strict import therefore refuses such a script (question 7). The capture function keeps `[string[]]`, so `Import-CompleterScript -Trusted` still imports one. An array for `-CommandName` is untouched.

- **Order.** The existing literal-value check runs first. An array that it already refuses, such as one with a redirection inside `@( )`, keeps today's literal-string finding and gets no second one.
- **The literal-string hint.** Today's hint for a non-literal value suggests "a literal `@('name', 'name.exe')` array" whichever parameter is named (`src/Core/Grammar/GrammarMessages.cs` line 40). For `-ParameterName` the hint becomes `Replace the -ParameterName value with one literal string; a value computed at import time cannot be analyzed.` The message is unchanged, and `('a')` in parentheses stays refused with it.
- The `Import-CompleterScript` help says `-ParameterName` may be a literal array (`src/docs/CompleterActions/Import-CompleterScript.md` lines 84 to 86); that sentence is corrected.

### The output path of Export-CompleterSet (finding 9)

Current behaviour. `src/Public/Export-CompleterSet.ps1` resolves `-Path` with `GetUnresolvedProviderPathFromPSPath` and no provider check (lines 130 to 142). Run on 2026-11-25 with the PowerShell location and the process working directory in different folders: `-Path 'FileSystem::sub\out.psd1'` wrote the file under the PowerShell location but computed every entry `Path` against the process working directory; `-Path 'HKCU:\Software\x.psd1'` failed with `The directory 'HKEY_CURRENT_USER\Software' does not exist.`

After 3.1.0, `-Path` follows the two rules the input paths already follow (lines 211 and 220), with the subject changed:

- `The output path '<given>' resolves to '<resolved>' on the <Provider> provider, not to a file system path.`
- `The output path '<given>' is provider-qualified but not fully qualified, so PowerShell would resolve it against the process working directory rather than the PowerShell location. Drop the provider qualifier or give a fully qualified path.`

Both are raised before the `.psd1` and directory checks, as those are: terminating, without the `Failed to export completer set. ` prefix, because the neighbouring checks in the same block carry none. A plain relative path, a drive-qualified path, and a fully qualified provider-qualified path behave as today.

### A bad path in PrivateData.CompleterSet (finding 11)

Current behaviour. A null character, or a path longer than the platform allows, in a manifest's `PrivateData.CompleterSet` reaches `GetFullPath` unguarded in two places, and the caller gets a raw .NET exception: `Resolve-CompleterSetModule.ps1` line 217 (every `-Name` call) and `Get-CompleterSetPackage.ps1` line 113 (`Test-CompleterSet -Path` and `-LiteralPath`, which read the manifests in the folder above the set). The second makes a valid set fail its test because a neighbouring manifest is bad.

After 3.1.0 (question 8):

- **By path.** `Test-CompleterSet -Path` and `-LiteralPath` report one `PackageLayout` Error per such manifest, at line 1, column 1 of the set, and go on to every other finding: `The module manifest '<manifest>' declares a completer set path that is not a valid file path: <reason>.` The reason is `it is longer than the platform allows` or the underlying message, as the entry rule words them (`src/Private/Resolve-CompleterSetEntry.ps1` lines 160 to 172). The search for the set's own manifest goes on past the bad one, so a real package still gets its other layout rows, and a set that no manifest declares gets none of them.
- **By name.** `Import-CompleterSet -Name` and `Test-CompleterSet -Name` fail with the existing declaration error (`The module '<name>' <version> declares the completer set '<declaration>', which must be a .psd1 file in a folder directly below '<base>'.`). A set that cannot be located has no file for a finding to point at, and every other bad declaration already ends a by-name call this way.
- In both, and in the by-name `does not exist` error (line 221), the declaration or path is shown with each control character replaced by U+FFFD and cut to 256 characters followed by `...`, so the message stays printable.
- **Platforms.** A null character raises the exception everywhere. An over-long path raises it on Windows only (run 2026-11-25 under WSL: no exception), so on Linux and macOS a 40000-character declaration is simply a set file that does not exist.

### Names in the capture scope

Current behaviour. `Import-CompleterScriptDefinition.ps1` dot-sources the script inside a module scope that already holds a parameter `$ScriptInfo` and a list `$script:CapturedCompleterDefinitions` (lines 50 and 53). A conforming script whose guarded state uses either name finds the name taken: its guard is skipped and its completer sees the module's object, with no finding and no error (run 2026-11-25 under strict import). A script that assigns either name inside its guard fails the import with a misleading message.

After 3.1.0 the two names are `$__CompleterActionsScriptInfo` and `$script:__CompleterActionsCapturedDefinitions`. A script that uses `ScriptInfo` or `CapturedCompleterDefinitions` for its own state imports, and its completer sees its own value. The help states that names beginning `__CompleterActions` are reserved. The misleading message for a failure inside the capture scope is not changed here.

### Tests that find pwsh by name

Not a behaviour change. On a machine with Store PowerShell the alias is the first `pwsh` on `PATH`, and a child `pwsh` puts its package's alias folder back at the front of `PATH` on startup (appendix A), so tests in `tests/CompleterHelpProbe.Tests.ps1`, `tests/CompleterScaffold.Tests.ps1`, and `tests/CompleterSetPackage.Tests.ps1` that pass the bare name `pwsh` to the probe, or start a child by that name, fail locally and pass on CI. After 3.1.0 those tests use the `pwsh` that is running the suite, and the full suite gives the same result on the owner's machine as on CI. Section 7 removes the cause for most of them as well; the tests are pinned anyway so that they do not depend on what is installed.

The pin covers the tests where the name is what is under test: the bare name is handed to the probe or to `New-CompleterScript`, or a child process does that. Six other test files start a plain child `pwsh` by name 21 times; those work on every machine, because the alias runs, and are left alone.

### Stems that differ only by case

No code change. `Tool` and `tool` share the stem `Tool` (`src/Private/ConvertTo-CompleterScriptStem.ps1`), and that is left as it is: PowerShell's completer table and its function table both ignore case (checked 2026-11-25: registering `zzcatool` after `ZzCaTool` replaces it, under one key), so two such commands cannot have separate completers in one session whatever the stem. `about_Import_Completers` and the `New-CompleterScript` help say so in one sentence each.

### CI on docs-only pushes

`.github/workflows/ci.yml` gains the same `paths-ignore` list (`docs/**`, `CHANGELOG.md`) on its `push` trigger that its `pull_request` trigger has. A docs-only change then gets no CI run on the pull request or on main. Nothing depends on a run existing for every commit: the release workflow runs its own tests on the tag, main has no branch protection and no ruleset, and no test reads `CHANGELOG.md` or anything under top-level `docs/` (checked 2026-11-25). The CI badge in `README.md` then shows the last push that was not docs-only.

## 9. Documentation

- **Command help** (`src/docs/CompleterActions/*.md`, regenerated into the MAML):
  - a new `Update-CompleterSet.md`, with three examples: a path, the pipeline from `Test-CompleterSet`, and `-WhatIf`;
  - `New-CompleterScript.md`: the option table, `-Documentation`, the app execution alias sentence, the reserved-name sentence, and the case-only stem sentence; one new example with `-Documentation`;
  - `Import-CompleterSet.md` and `Test-CompleterSet.md`: the two version parameters and one example each;
  - `Test-CompleterRegistration.md`: `-TargetOnly`, and example 3 rewritten;
  - `Import-CompleterScript.md`: `-ParameterName` takes one literal string;
  - `CompleterActions.md`: the twelfth command.
- **Comment help** in `src/Public/*.ps1` is a second copy that the source layout serves and a test reads; each changed command's comment help is updated with its page.
- **"A failed call leaves nothing at the path."** `New-CompleterScript.md`, the command's comment help, and `about_Import_Completers` say this. With `-Documentation` it gains its one exception, from section 3.
- **`.github/copilot-instructions.md`** says eleven commands in two places; both become twelve.
- **`about_Completer_Sets`**: a section `FIXING DRIFT WITH UPDATE-COMPLETERSET` after `CHECKING FOR DRIFT WITH TEST-COMPLETERSET`, which says what is updated, what is refused and why, and when `Export-CompleterSet` is the right tool; and `-MinimumVersion` and `-RequiredVersion` in `COMPLETER SETS AS MODULES`.
- **`about_Import_Completers`**: option seeding and `-Documentation` in `SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT`; the array rule for `-ParameterName` in `THE STRICT GRAMMAR`; `-TargetOnly` where `FromTarget` is described; the case-only stem sentence; the reserved-name sentence.
- **`README.md`**: the command table and the command list.
- **`CHANGELOG.md`**: Added, Changed, and Fixed entries under Unreleased, with the four changes of section 1 under Changed.
- **`docs/roadmap-3.0/milestone-2-spec.md`**: lines 130 and 139 still give the stem rule from before the 3.0.1 hash suffix (`oh-my-posh` gives `OhMyPosh`; `_a` gives `A`). They are corrected to the shipped rule, with a dated note (owner ruling on finding 13).
- `about_CompleterActions_Migration` is not touched: nothing in 3.1.0 needs a migration.

## 10. Performance: no regression

3.1.0 adds no work to an import that uses no new parameter. One number must hold, measured with the existing tool and the 3.0.1 build as the baseline:

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v3.0.1\CompleterActions\build\CompleterActions -Iterations 10
```

The baseline is tag v3.0.1 extracted with `git archive` into a folder named `CompleterActions`, because the build script takes the module name from its folder, and compiled there with `Invoke-Build -Task compile`, which also fills the tracked package's `lib` folder.

- The gate is the `LazyNoHash` row: its `RatioToBaseline` must be 1.05 or lower. It is the only row that compares the same set under both builds in one interleaved run.
- The `Lazy` row is reported, not gated.
- A run above 1.05 is repeated up to four runs and all are reported; a median above 1.05 is a regression to fix before merging.

Reported in the pull request, not gated: the time `Update-CompleterSet` takes over the PS_Completers set with one changed script, and with none.

## 11. Release

Per roadmap decision 2, locked 2026-11-25:

- The branch keeps `ModuleVersion = '3.0.1'` until the preview release commit.
- The preview release commit stamps `ModuleVersion = '3.1.0'` and `Prerelease = 'preview1'`. Tag `v3.1.0-preview1`. It soaks in the owner's profile and on the PS_Completers CI, which installs with `-Prerelease`.
- Stable `v3.1.0` is cut from the same code once the preview has run without a defect. A defect means `preview2`.
- `AssemblyVersion` stays 3.0.0.0; the file and informational versions follow the manifest, as the `compile` task already sets them (question 9).

### Roadmap edits made with this spec

On 2026-11-25 the owner chose to have these edits to `docs/roadmap-4.0.md` made in the same commit as this spec. They are the owner's edits; no implementer touches the roadmap.

1. **Header.** Baseline 3.0.1 (`820d224`, tag v3.0.1); the status line records that milestone 1 started on 2026-11-25 with its trigger waived, and that decisions 2 and 3 are locked.
2. **"Where 3.0 leaves us".** The test count and the scaffold row are stale after 3.0.1; refresh or date them.
3. **Milestone 1 items.** Add `Test-CompleterRegistration -TargetOnly` and app execution aliases in the help probe, and one line for the folded fixes. Record the answer to the `Update-CompleterSet` question: report only.
4. **The `-Documentation` item** (question 3): "the one heading the PS_Completers corpus already shares, 'What it completes', and nothing else" becomes the title line, that heading, and one sentence naming the targets.
5. **The version selection item** (question 4): the two parameters are on `Test-CompleterSet -Name` as well.
6. **Exit criterion 2**: `-MinimumVersion 1.1.3` is below every PS_Completers version now published (1.2.0, 1.3.0, and 1.3.1 are installed on the owner's machine), so the "errors below it" half cannot be seen with that number. Either keep the line and add a second with a version above the installed one, or leave it to this spec's check 2.
7. **Exit criterion 3**: note that the second `Test-CompleterSet` call is empty only when the drift was hash-only, because an entry whose targets changed is refused (section 5).
8. **A new exit criterion** for the alias probe, in the form of section 13 check 14.
9. **Milestone 3's surface line**: "11 from 3.0 plus whatever 3.1 and 3.2 added" names `Update-CompleterSet`.
10. **The `Update-CompleterSet` item**: it also repairs a malformed `Hash`, warns for trusted entries, and leaves an entry whose targets changed to `Export-CompleterSet`.
11. **The option seeding item**: GNU-style help without an option heading is read too, and the generated script offers options in any argument position.

## 12. What stays exactly as in 3.0.1

- Every call that uses no new parameter, with these exceptions only: the four changes in section 1; in `New-CompleterScript`, the two verbose lines, the three line-2 comment texts, and the `/?` fallback condition of section 2, and the alias cases of section 7; and the bad-declaration cases of section 8.
- `Import-CompleterSet` and `Test-CompleterSet` without a version parameter: the same resolution, records, findings, warnings, errors, and verbose lines, apart from those bad-declaration cases.
- The set schema, the hash rule, the fast path, and `Export-CompleterSet`'s output for every call that 3.0.1 completed correctly.
- The strict grammar and its messages, apart from the one new finding.
- `Get-Completer`, `Register-Completer`, `Unregister-Completer`, `Reset-Completer`, `Import-CompleterScript`, lazy loading, and engine access.
- The public types and their property order.
- The subcommand parser: every capture gives the same subcommand names as today.

## 13. Acceptance criteria

The commands use these values:

```powershell
$module = '<repository>\build\CompleterActions'
$completers = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers'   # source of the scratch clone only
```

Run rules, carried over from the 3.0 milestones:

- Every numbered check runs in its own `pwsh -NoProfile` process against `$module` built from the branch, and starts with:

  ```powershell
  Import-Module -Name "$module\CompleterActions.psd1" -Force
  if ((Get-Module CompleterActions).ModuleBase -ne $module) { throw 'wrong ModuleBase' }
  ```

- Pester runs in its own process, never in a process that also builds or lints.
- PS_Completers is read only through a scratch clone, `git clone $completers <scratch>\PS_Completers`.
- "3.0.1 build" means tag v3.0.1 extracted with `git archive` into a folder named `CompleterActions` and compiled there (section 10), never the gallery copy.
- By-name checks use package folders built in scratch module roots, with `$env:PSModulePath` set in the check's own process. No check writes the PSResourceGet store.
- **Fixture provenance.** Each capture under `tests/Fixtures/NewCompleterScript/` gains an expected-options file, written by hand from the help before the parser is run against it, as `CAPTURES.md` records for the existing names files. Those files are the assertion. The `du` capture is GNU coreutils `du --help`. On the owner's WSL (Ubuntu 25.10) plain `du` is the uutils rewrite, whose help has a clap layout, and GNU 9.5 is `gnudu`; the capture is taken with `gnudu --help`, with its version and command recorded in `CAPTURES.md`, as the other fourteen were.
- **Bytes.** The repository has `core.autocrlf` on and no `.gitattributes`, so a checked-in fixture does not keep its line endings or a byte-order mark across platforms. A test that asserts bytes writes its input with `[System.IO.File]::WriteAllBytes` into the test drive.

### Roadmap exit criteria, expanded

1. **An option-only tool is seeded.**

   ```powershell
   $file = New-CompleterScript -CommandName rg -Path <scratch>\rg_completer.ps1 -PassThru
   $file | Test-CompleterScript                            # empty
   Get-Content -LiteralPath $file.FullName -TotalCount 2   # line 2 is the probe form of the Help-seeded line
   ```

   Expected on the owner's machine with ripgrep installed: no findings, `Subcommands = @()`, and an `Options` table that holds `--regexp`. The Pester form uses `-HelpText` with the `rg` capture, expects line 2 in its help-text form, and compares the option names with the expected-options file.

2. **A set is selected by version.** In two scratch module roots holding `CaFixtureSet` 1.0.0 and 1.2.0 in the first and 2.0.0 in the second:
   - no version parameter gives 1.2.0 (unchanged);
   - `-MinimumVersion 1.1.3` gives 1.2.0;
   - `-MinimumVersion 1.5.0` gives 2.0.0, from the second root;
   - `-MinimumVersion 3.0.0` fails with the `or later` text and the list `2.0.0, 1.2.0, 1.0.0`;
   - `-RequiredVersion 1.0.0` gives 1.0.0, and `-RequiredVersion 1.1.0` fails with its text;
   - both parameters together, and either with two names, fail with their texts;
   - a 2.0.0 folder whose manifest carries `Prerelease = 'preview1'` is selected by `-RequiredVersion 2.0.0`, and the verbose line shows `2.0.0-preview1`;
   - with a versioned 1.0.0 and an unversioned 2.0.0 in one root, `-MinimumVersion 1.5.0` and `-RequiredVersion 2.0.0` both give the unversioned copy, and no version parameter gives 1.0.0 (unchanged);
   - through `Test-CompleterSet -Name`, with one script of the 1.0.0 copy changed after its set was written: `-RequiredVersion 1.0.0` returns that `HashMismatch`, whose `Path` is the 1.0.0 set file, and `-MinimumVersion 1.1.3` returns nothing.

   On the owner's machine, with PS_Completers installed, `Import-CompleterSet -Name PS_Completers -MinimumVersion 1.1.3 -WhatIf -Verbose` names the highest installed version.

3. **Drift is repaired in place.** In a scratch copy of a set with three scripts, after one script gains a comment line:

   ```powershell
   Test-CompleterSet <scratch>\completers.psd1 | Update-CompleterSet
   Test-CompleterSet <scratch>\completers.psd1    # empty
   ```

   The file differs from its earlier bytes only inside that entry's `Hash` value, and the file's length is unchanged. In the scratch clone of PS_Completers, the same two lines after one script changes leave `git diff --stat` showing the set file with one line changed, and `git diff` showing only that `Hash` line.

### Option seeding

4. **Captures.** Each of the fifteen captures, through `-HelpText`, gives exactly the option names in its expected-options file, in order, and exactly the subcommand names in its existing expected-names file. The `cargo` output equals the regenerated golden file.
5. **Rules, on synthetic text:**
   - a heading followed by a non-option line starts no option section;
   - a heading whose first line is a bare `--` starts one, and the `--` gives no row;
   - two option lines at one indent with no heading start a section, and a single option line alone does not;
   - a heading-shaped description line inside an open section starts no second section, and a deeper example line that begins with an option gives no row;
   - a single-dash line deeper than the section indent gives no row;
   - a blank line between rows does not end a section;
   - a line at heading indent ends it, and a line shallower than the rows ends a section without a heading;
   - `--verbose...` gives `--verbose`, and `-., --hidden` gives `-.` and `--hidden`;
   - long-only rows four columns deep are rows when the section indent has none, and are not rows when it has;
   - `-x, --long <ARG>`, `-x,--long`, `--long=VALUE`, `--long[=VALUE]`, `-e PATTERN, --regexp=PATTERN`, `--context string`, `-ao{a|s}`, and `/X` each give the names expected and no placeholder;
   - a row without a description takes the next deeper line;
   - `-c` and `-C` both stay; a repeated `--help` is kept once;
   - an option line under a commands heading gives no option row, and a `/X` row there is still a subcommand.
6. **Every output conforms and works.** For every capture's output: `Test-CompleterScript` returns nothing, `Import-CompleterScript` returns one record per target, and `Register-Completer -LiteralPath <file> -Lazy -PassThru` derives the same targets. After registration:
   - `Test-CompleterRegistration -CommandName rg -Native -InputText 'rg --reg' -TargetOnly` returns matches that include `--regexp`, each with `ResultType` `ParameterName` (rg also has `--regex-size-limit`);
   - `-InputText 'rg foo --reg'` returns the same;
   - `-InputText 'rg '` returns nothing from the target;
   - `-InputText 'cargo b'` still returns `build` and `bench`, and `-InputText 'cargo --ver'` returns `--version`.
7. **Probe and messages.** With the process runner replaced: help with options, no subcommand, and two lines runs no `/?`; the probe line and the `Wrote` line carry the option count. A script generated by 3.0.1 (the old golden file, kept as a fixture) still passes `Test-CompleterScript` and completes its subcommands.
8. **Self-check.** With the composer replaced to emit a cast in the option table, the command fails with the existing did-not-produce text and no file exists.

### -Documentation

9. **Files.**
   - With the switch, the `.md` file exists beside the script with exactly the three content lines of section 3 for `rg`, and for a two-name call the sentence lists four targets.
   - No BOM, platform newline, final newline; the same input twice gives identical bytes.
   - An existing `.md` without `-Force` fails with its text and leaves both paths as they were; `-Force` replaces both.
   - Under `-WhatIf`, in a child process, neither file exists and the `What if:` line begins `Create completer script and documentation`.
   - With the markdown move made to fail through `InModuleScope`, the call fails with the was-written text, the script exists and conforms, and no `.tmp` file remains.
   - Without the switch, an existing `.md` beside the path is not read or changed.
   - `-PassThru` returns one `FileInfo`, the script's.

### Update-CompleterSet

10. **What is updated.** On a scratch set, each single mutation gives the result listed:

    | Mutation | Result |
    | --- | --- |
    | One script's text changes | that entry's `Hash` is rewritten; no warning |
    | One `Hash` value is malformed | rewritten |
    | One script gains a registration | not updated; one warning with the `TargetMismatch` text; the file is not written |
    | One script is deleted | not updated; one warning with the `MissingScript` text |
    | Two entries list one target, and one of their scripts changes | not updated; one warning with the `DuplicateTarget` text |
    | One entry has no `Hash` | not updated; the one no-`Hash` warning counts it |
    | A trusted entry's script changes | rewritten; one trusted-entry warning |
    | A declared hash in lower case that matches | untouched; the file is not written |
    | A new `*_completer.ps1` under the folder | one unlisted-script warning; the set is unchanged |
    | Two scripts change, one of them with a target change | one rewritten, one warned; `-PassThru` returns the file |

11. **Bytes.** For a set with CR LF, a set with LF, a set with a UTF-8 byte-order mark, a set whose `Hash` shares a line with `Path`, a set with comments and a double-quoted `Hash`, and a set whose `Hash` is a here-string: after an update, every byte outside the replaced values equals the original. A set with an invalid UTF-8 byte fails with the round-trip text and is unchanged. With the splice replaced through `InModuleScope` to drop an entry, the call fails with the not-equivalent text and the file is unchanged. No temporary file remains after any of these.
12. **Binding and surface.**
    - `Test-CompleterSet a.psd1, b.psd1 | Update-CompleterSet` updates each set once, however many findings each has.
    - `Test-CompleterSet` on a clean set pipes nothing, so the set is not read or written; the same set given by `-Path` is read and not written, and its timestamp is unchanged.
    - A set whose file name holds `[` and `]` is updated through the pipeline from `Test-CompleterSet -LiteralPath` and through `-LiteralPath`.
    - `-WhatIf` writes nothing and still warns.
    - `Get-Command Update-CompleterSet -Syntax` shows the three sets of section 5.
    - After an update, `Test-CompleterSet` on the set returns nothing, and `Import-CompleterSet` returns records with the same `Key`, `RuntimeKey`, `State`, and `ScriptPath` as it gave before the script changed.

### -TargetOnly

13. **Filter.** For the fixtures of the existing `FromTarget` tests (`tests/CompleterAuthorTooling.Tests.ps1`): with `-TargetOnly`, the output equals the 3.0.1 output piped to `Where-Object FromTarget`, for a completer that matches, one that returns nothing while a file name matches, and one whose cursor sits on another parameter. Without the switch the output equals 3.0.1's.

### App execution aliases

14. **Resolution.** On Windows legs, with reparse points written into the test drive by the test (an `APPEXECLINK` point can be created without elevation; appendix A):
    - an alias whose target is a copy of `cmd.exe` reads as runnable, and the verbose line names the target;
    - one whose target is the patched GUI copy warns with the GUI reason;
    - a missing target, an empty target, and a target that is not a `.exe` warn with their reasons;
    - an ordinary zero-byte `.exe` that is not a reparse point still warns `its program header could not be read`.

    The test removes every reparse point it creates. These cases prove the decision, not the run: a reparse point written by a test has no package behind it and does not start. They are skipped on Linux and macOS legs with the reason `app execution aliases exist only on Windows`, where one test asserts instead that the reader is never called, through a counter on the private function that wraps it. That the alias itself runs is shown where a real one exists. On a machine where `winget` resolves to an alias, which includes the owner's:

    ```powershell
    New-CompleterScript -CommandName winget -Path <scratch>\winget_completer.ps1 -Verbose   # a probe line with exit 0, and a table with rows
    ```

    The Pester form of that last check skips with the reason `winget is not an app execution alias here` elsewhere.

### Folded fixes

15. **`-ParameterName` arrays.** `'a', 'b'`, `@('a', 'b')`, and `@('a')` each give exactly one finding with the section 8 message, at the argument. `-ParameterName 'a'` and `-CommandName 'x', 'y'` give none. `-ParameterName @('a' >> file)` gives only today's literal-string finding, and `-ParameterName $name` gives that finding with the new hint. `Import-CompleterScript` refuses the script with that finding; `Import-CompleterScript -Trusted` returns its records. In the scratch clone of PS_Completers, `Test-CompleterScript` over every script returns nothing, as under 3.0.1.
16. **Export output path.** With the PowerShell location and the process working directory in different folders: `-Path 'FileSystem::sub/out.psd1'` and `-Path 'Variable:\x.psd1'` fail with their section 8 texts and write nothing, on every leg; `-Path 'HKCU:\Software\x.psd1'` does on Windows legs and is skipped elsewhere with the reason `the Registry provider exists only on Windows`; `out.psd1`, `./sub/out.psd1`, and a fully qualified `FileSystem::` path write the same file and the same entry paths as 3.0.1.
17. **Bad declaration.** For a manifest whose `CompleterSet` holds a null character, on every leg, and one whose value is 40000 characters long, on Windows legs (skipped elsewhere with the reason `an over-long path raises no exception on this platform`):
    - `Test-CompleterSet -LiteralPath <set>` returns one `PackageLayout` Error with the section 8 text, and returns the set's other findings; with two such manifests beside a real one, it returns two such rows and the real package's rows;
    - `Test-CompleterSet -Name` and `Import-CompleterSet -Name` fail with the declaration error, whose text holds no control character and is under 1000 characters;
    - on Linux legs, the 40000-character declaration by name fails with the `does not exist` text, under 1000 characters;
    - `Import-CompleterSet -LiteralPath <set>` imports as in 3.0.1.
18. **Capture names.** A conforming script whose guarded state is `$script:ScriptInfo`, and one that uses `$script:CapturedCompleterDefinitions`, import under the strict tier, and each completer returns values from its own table. No file under `src` contains `$ScriptInfo` or `CapturedCompleterDefinitions` outside the reserved names.
19. **Tests are pinned.** On the owner's machine, with the Store alias first on `PATH`, the full suite passes with no failure. No test passes the bare name `pwsh` to the probe or to `New-CompleterScript`, and no test starts a child that does, without first putting the running `pwsh`'s folder at the front of `PATH` in the process that resolves the name.

### Documentation, surface, and gates

20. **Help content**, from the build:
    - `(Get-Help Update-CompleterSet).Synopsis` is the section 5 text, and `-Examples` shows three;
    - `Get-Help` resolves `-Documentation`, `-MinimumVersion`, `-RequiredVersion` (on both commands), and `-TargetOnly`;
    - `about_Completer_Sets` contains `FIXING DRIFT WITH UPDATE-COMPLETERSET`;
    - `about_Import_Completers` contains `__CompleterActions` and the sentence on names that differ only by case.
21. **Surface.**
    - `Get-Command -Module CompleterActions` lists 12 functions and no alias.
    - For each of the 11 functions 3.0.1 exports, the parameter names and sets match the 3.0.1 build's, except the additions named in section 1.
    - `[CompleterActions.CompleterRegistration].Assembly.GetName().Version` is 3.0.0.0, and the types of the `CompleterActions` namespace and their property lists equal 3.0.1's.
    - `(Get-Module CompleterActions).Version` is 3.1.0 with `Prerelease` `preview1` on the preview release commit and absent on the stable one, each checked on its commit before its tag.
22. **PSReadLine.** The existing snapshot tests pass, and one new test asserts an identical `Get-PSReadLineKeyHandler -Bound -Unbound` across `Update-CompleterSet`, `Import-CompleterSet -Name -MinimumVersion`, `New-CompleterScript -Documentation`, and `Test-CompleterRegistration -TargetOnly`.
23. **PS_Completers under the branch build.** In the scratch clone, its own Pester suite passes with the branch build first on `PSModulePath`, and strict `Import-CompleterScript` imports every script, as under 3.0.1.
24. **Performance.** Section 10's ratio and the two reported times are in the pull request with the pwsh version, the OS, and the commit.
25. **Suite, lint, and CI.**
    - `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes locally.
    - `Invoke-ScriptAnalyzer` over `./src` and `./tests` with `./PSScriptAnalyzerSettings.psd1`, CI's two Lint calls, returns nothing.
    - `dotnet build` of the core gives zero warnings.
    - All eight CI legs are green on the pull request.
26. **CI trigger.** The first CI run on the feature pull request shows the changed workflow parses and still runs for a change outside the ignored paths. That a docs-only push to main starts no run can only be seen after the merge: the next commit to main that touches only `docs/**` or `CHANGELOG.md` shows no new run in `gh run list --workflow ci.yml --branch main`.

## 14. Questions for the owner, answered 2026-11-25

The owner answered each question with its recommendation. The alternatives are kept as the record of what was considered. Question 11 came from the review of this spec.

1. **Option seeding has no off switch.**
   - Recommendation: none. The tables are data in the generated file; an author who does not want the rows deletes them, and `-NoProbe` still writes an unseeded skeleton.
   - Alternative: a `-NoOptions` switch, for a subcommand-only table from help that has both.
2. **A `du` capture.** The roadmap names `rg` and `du` as the option-only tools; `du` is not among the fourteen captures.
   - Recommendation: add one from GNU coreutils `du --help` (`gnudu --help` on the owner's WSL), with its version in `CAPTURES.md`.
   - Alternative: leave `rg` as the only option-only capture.
3. **What `-Documentation` writes.** The roadmap says one heading, "What it completes", and nothing else. In PS_Completers at `9db457c`, 169 of 176 files begin `# <name> completer`; 156 have a heading that begins `## What it completes`, of which 152 are exactly `## What it completes / overview` and 4 are exactly `## What it completes`.
   - Recommendation: the title line, `## What it completes`, and one sentence naming the script and its targets. An empty heading is nothing to keep, and the sentence is true as generated. This changes the roadmap's wording (section 11, edit 4).
   - Alternatives: the heading alone, as the roadmap says; or the corpus's majority spelling, `## What it completes / overview`.
4. **Version parameters on `Test-CompleterSet -Name`.** The roadmap names `Import-CompleterSet` only.
   - Recommendation: both commands. A profile that pins a version should be able to test the copy it pins, by the same words.
   - Alternative: `Import-CompleterSet` only; `Test-CompleterSet -LiteralPath` to the version folder does the same work.
5. **Entries without a `Hash`.**
   - Recommendation: `Update-CompleterSet` does not add one and warns once per set. The roadmap says it rewrites `Hash` lines, and adding a line changes more than a value.
   - Alternative: insert a `Hash` line after `Trusted`, matching the entry's indentation, under a switch such as `-AddMissing`.
6. **`Update-CompleterSet` output.**
   - Recommendation: nothing by default and the written files with `-PassThru`, the module's convention; skipped entries are warnings. No new public type.
   - Alternative: one record per entry considered (set, index, path, old hash, new hash, action), which needs a new public type and a format view.
7. **The `-ParameterName` array finding is an Error.** The owner ruled on 2026-11-25 that the array is reported. The research for this spec then found that the module's own import handles the array today, through its capture function, and that only a standalone dot-source fails. An Error therefore refuses, under the strict tier, a script that 3.0.1 imports.
   - Recommendation: keep it an Error. The grammar's promise is that a conforming script also works when it is dot-sourced by itself, which is how the PS_Completers scripts are documented to work, and none of the 176 uses the form. `-Trusted` still imports such a script.
   - Alternative: a Warning. `Test-CompleterScript` shows it, and strict import keeps accepting the script.
8. **A bad `PrivateData.CompleterSet`.** The owner ruled that the bad path becomes a finding, not an exception. By name there is no set file to carry a finding, and by path the bad manifest is only a neighbour of the set under test.
   - Recommendation: by name, the existing declaration error, with the value made printable, as every other bad declaration already ends a by-name call; by path, one `PackageLayout` Error row per bad manifest.
   - Alternatives: by path, pass over the bad neighbour silently, as a rooted or blank declaration in a neighbour already is; or have `Test-CompleterSet -Name` return a finding whose `Path` is the manifest, the only finding not on a set file.
9. **`AssemblyVersion` stays 3.0.0.0.**
   - Recommendation: keep it for the whole 3.x line, so anything compiled against the public types keeps binding. The file and informational versions carry 3.1.0.
   - Alternative: 3.1.0.0, which changes the assembly identity for no behaviour.
10. **The roadmap edits of section 11**, in particular edits 6 and 7, which qualify two exit criteria as written.
    - Recommendation: make them when the spec is accepted, so the plan's checks and the roadmap say the same thing.
    - Alternatives: at the preview release; or by the owner's own hand.
11. **Trusted entries in `Update-CompleterSet`.** A trusted script is never parsed, so the check that protects a strict entry, refusing to rehash when the targets changed, cannot be made.
    - Recommendation: rehash, and warn once per trusted entry updated that its `Targets` were not checked. Import ignores a trusted entry's `Hash`, so it only feeds `Test-CompleterSet`.
    - Alternatives: rehash without a warning; or never rehash a trusted entry, which leaves a trusted set no way to be repaired in place.

## Appendix A. Probes behind sections 7 and 8

Taken on 2026-11-25 on the owner's machine, not elevated, PowerShell 7.7.0. The scratch scripts are not in the repository.

**App execution aliases.**

- Every `.exe` under `%LOCALAPPDATA%\Microsoft\WindowsApps` is zero bytes with the attributes `Archive, ReparsePoint`. PowerShell reports no `LinkType` and no `Target` for them, and `[System.IO.File]::ResolveLinkTarget` returns nothing, so no managed API gives the target.
- `CreateFileW` with `FILE_READ_ATTRIBUTES`, share mode 7, and the flags `FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS`, then `DeviceIoControl` with `FSCTL_GET_REPARSE_POINT` (0x000900A8), read the data for every alias tried. Layout: tag 0x8000001B, data length, reserved; a 32-bit version, 3; then NUL-terminated UTF-16 strings: the package family name, the application user model ID, the target path, and `0`.
- The target was a fully qualified path under `C:\Program Files\WindowsApps\` in all nine aliases tried, sometimes in a subfolder.
- Reading the target's header gave subsystem 3 for `pwsh`, `winget`, `python`, and `wsl`, and 2 for `wt`, `notepad`, `SnippingTool`, `ms-teams`, and `Procmon`. No read was denied.
- Run through the module's own process runner (`src/Private/Invoke-CompleterHelpProcess.ps1`), `winget --help` by its alias path exited 0 in 134 ms with 2087 bytes, and `pwsh --help` exited 0 in 193 ms.
- Reparse points of this kind written into a scratch folder with `FSCTL_SET_REPARSE_POINT` (0x000900A4) needed no elevation. One with a missing target, one with an empty target, and one whose target is not an executable each failed to start with `The file cannot be accessed by the system.`
- In PowerShell the literal `0x8000001B` is a negative `Int32`; a comparison with the unsigned tag must use an unsigned value.

**`pwsh` on `PATH`.** `Get-Command pwsh -CommandType Application -All` in a `pwsh -NoProfile` child returned, first, `...\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe`, an alias. A child started from any `pwsh` on the machine, with `PATH` reset to `C:\Windows\System32`, had that package folder at or near the front of its `PATH`. Putting `$PSHOME` first in the parent therefore does not pin a child.

**PS_Completers.** At `9db457c`: 176 completer folders, each with a script and a markdown file; no script passes `-ParameterName` to `Register-ArgumentCompleter` (the two matches for the text are calls to the scripts' own helper functions). The installed 1.3.1 set is 65984 bytes, UTF-8 without a byte-order mark, LF line endings, 176 entries, each with a `Hash` in the exact shape `Export-CompleterSet` writes.

## 15. Amendments after the final review

The owner ruled on these on 2026-11-25, after the final review of the branch. Each amends the section named and is implemented on the branch.

1. **Section 5, what is updated.** An untrusted entry whose script does not pass the strict grammar is not updated. It is skipped with the skipped-entry warning, whose problem text is the first grammar Error as `Test-CompleterScript` words it. Without this, a matching `Hash` would let `Import-CompleterSet` take the fast path and move the failure from import to the first tab.
2. **Section 4, candidates.** With a version parameter, a version folder or an unversioned manifest that cannot be read is left out of the candidates; it no longer fails the call. A pin therefore never breaks a call that works without one, as `Import-Module` behaves. Without a version parameter, resolution and its errors are as in 3.0.1.
3. **Section 3, existing file.** When a directory sits at the markdown path, the call fails before anything runs, with or without `-Force`: `Failed to create completer script. Documentation files must be file paths. '<md path>' is a directory.` Neither file is written.
4. **Section 5, wording.** The ShouldProcess action is `Update 1 Hash value` for one entry and `Update <n> Hash values` otherwise. When the rewritten set would exceed the limit, the text is `Completer set '<set>' would be <n> bytes after the update, which is larger than the 131072-byte limit for completer set files. Split its entries across several sets and regenerate them with Export-CompleterSet.` `Export-CompleterSet` keeps its own text.
