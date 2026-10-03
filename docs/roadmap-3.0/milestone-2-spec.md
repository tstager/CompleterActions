# Milestone 2 specification: authoring and distribution (2.2.0)

Drafted: 2026-10-02, revised the same day after three reviews (source grounding and additivity; runtime safety and external dependencies; scope fidelity and testability), and again after the three reviews of the plan, which moved the plan's gap-fills into sections 2, 3, 4, and 8 and added question 14
Base: main at `5473022` (2.1.0 stable, release commit `2086f7f`, tag v2.1.0)
Roadmap: `docs/roadmap-3.0.md`, milestone 2, and locked decisions 3 and 7. Milestone 3 is out of scope and is referenced only where this milestone changes one of its criteria.
Kind: behaviour spec. It states what the module does after 2.2.0 and how a reader can tell. It does not prescribe helpers, file splits, or commit order.
Status: draft for owner review. Section 9 lists the questions for the owner. The plan (`docs/roadmap-3.0/milestone-2-plan.md`, "Owner decisions by gate") states when each answer is due, and an unanswered question means its recommendation applies. Each carries a recommendation, and sections 1 to 8 are written as if every recommendation is accepted. That includes question 1: engine cmdlet detection is held, so it is not 2.2.0 behaviour. Its contract is appendix A, which also lists what comes back into the body if the owner ships it now. Questions 1, 2, 3, 6, 7, and 10 would change roadmap text, which only the owner edits. This spec recommends those edits and collects them in section 6, "Roadmap edits the owner would make"; it edits nothing in the roadmap.

Every claim about current behaviour cites the file it was read from. Measurements and probes in this document were taken on 2026-10-02 on the owner's Windows machine, PowerShell 7.6.6 (.NET 10.0.12), PSResourceGet 1.2.0, against the tracked `build/CompleterActions` (2.1.0) and the PS_Completers repository at `2c590c6`. Linux behaviour was checked the same day under WSL Ubuntu, PowerShell 7.6.5. Upstream state was read the same day with an authenticated `gh`. Appendix B gives the commands that reproduce the counts quoted from PS_Completers.

## 1. Scope and non-goals

2.2.0 is an additive release on the 2.x line.

- No command, parameter, alias, property, or enum value is renamed or removed. Nothing that 2.1.0 accepts is rejected, and every 2.1.0 call gives the same records, warnings, errors, and verbose lines.
- The record types keep their shape. `CompleterActions.CompleterRegistration` and `CompleterActions.CompleterScriptFinding` gain no property (`src/Classes/CompleterTypes.ps1`). If the owner accepts question 8, `Test-CompleterSet` gains one `Construct` value, `PackageLayout`, reported only for a set that a module manifest declares, which is a layout that did not exist before 2.2.0 (section 3). `Construct` is a plain string, so the value is additive.
- The set file schema is unchanged: `Version = 1`, `Path`, `Trusted`, `Hash`, `Targets`. A set written by 2.2.0 imports on 2.1.0 and on 2.0.0 exactly as a 2.1.0 set does.
- One public command is added, `New-CompleterScript`. `Import-CompleterSet` gains the parameter set `Name`, and, if the owner accepts question 9, `Test-CompleterSet` gains one too. In each, `-Name` is mandatory only inside its own new set, so no existing call binds differently. The module then exports 14 functions and the same 3 aliases (2.1.0 exports 13, `build/CompleterActions/CompleterActions.psd1`). Two existing tests pin the export list and change with it: `tests/CompleterDeprecation.Tests.ps1` asserts 13 functions and becomes 14, and `tests/CompleterRegistration.Tests.ps1` compares the manifest's `FunctionsToExport` with the files in `src/Public`, so the manifest list gains `New-CompleterScript`.
- The manifest floor stays `PowerShellVersion = '7.0'`. Every API this spec relies on exists in .NET Core 3.1: `ProcessStartInfo.ArgumentList` (2.1), `Process.Kill(bool)` (3.0), `File.Move(string, string, bool)` (3.0), `Path.GetRelativePath` (2.0, already used by `Export-CompleterSet`). The probe waits with `WaitForExit(int)`, not `WaitForExitAsync`. This is read from the API documentation, not tested: the lowest CI leg is 7.4, as it has been since 1.3.0.
- PSReadLine neutrality holds for everything added: nothing hooks key handlers, replaces `TabExpansion2`, or touches PSReadLine options or prediction.

In scope:

| Item | Kind | Section |
| --- | --- | --- |
| `New-CompleterScript` | feature | 2 |
| Completer-set modules and `Import-CompleterSet -Name` | feature | 3 |
| `Test-CompleterSet -Name` and `PackageLayout` findings | feature, proposed pending questions 8 and 9 | 3 |
| PS_Completers as the reference package | consumer follow-up, outside this repository | 3 |
| Author guide, third edition, and command help | docs | 4 |
| Import-time non-regression | perf check, not a benchmark | 5 |
| `2.2.0-preview1`, then `2.2.0` | release | 6 |

Engine cmdlet detection, the roadmap's third item, is held under question 1. Its contract is appendix A.

What a reader can see after 2.2.0:

| Observation | How to tell |
| --- | --- |
| A new completer starts from a generated file that already conforms | `New-CompleterScript -CommandName cargo -Path .\cargo_completer.ps1 -PassThru \| Test-CompleterScript` returns nothing, and `cargo b<Tab>` offers `build` and `bench` once the file is registered with `Register-Completer -LiteralPath .\cargo_completer.ps1 -Lazy` |
| A set can be installed and named instead of pathed | `Import-CompleterSet -Name PS_Completers` registers the same records as `-LiteralPath` to the installed set file |
| A broken package layout is caught before publishing (if question 8 is accepted) | `Test-CompleterSet` over a set declared by a manifest reports `PackageLayout` findings |

Non-goals:

- **No benchmark.** The startup benchmark is not part of this milestone. Section 5 states the non-regression check, which uses the existing tool.
- **No option or value seeding.** `New-CompleterScript` seeds subcommands only, as the roadmap says. Option layouts vary more than subcommand tables (`-x, --long <ARG>`, `/X`, `--long=VALUE`), and the scaffold's job is a conforming start. Option-only tools such as `rg` and `du` get an empty table. Revisit with real use.
- **No companion `.md`.** `New-CompleterScript` writes the `.ps1` only. The PS_Completers `.md` files are not part of the grammar or the set, and beyond a common first heading (155 of 173 have a heading that begins `## What it completes`) their structure varies, so a generated stub would be boilerplate to delete. A `-Documentation` switch can be added later without a breaking change.
- **No parameter completers from the scaffold.** `New-CompleterScript` emits native completers; the roadmap item says "for a native command".
- **No version selection for `-Name`.** The first root and the highest version win, as `Import-Module` does, and a pinned profile can still use `-LiteralPath`. `-MinimumVersion` and `-RequiredVersion` can be added later without a breaking change.
- **No grammar change.** The closed import grammar (`src/Private/Test-CompleterScriptAst.ps1`) is unchanged. It still runs at first tab, not at import (2.0 decision 5).
- **No engine cmdlet detection in 2.2.0** under question 1's recommendation. Every read, removal, and write runs the 2.1.0 reflection code (`src/Private/Get-CompleterRuntime.ps1`).
- **Deferred to 3.0:** the compiled core, public .NET types, removal of the deprecated surface, the 7.4 floor, and version-gated engine access inside a compiled layer.
- **Consequences for the roadmap** are the owner's to make. Section 6 lists them.

## 2. New-CompleterScript

### SYNOPSIS

Writes a completer script skeleton for a native command that passes `Test-CompleterScript` as written.

### SYNTAX

#### Probe (Default)

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> [-HelpArgument <string>]
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### HelpText

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -HelpText <string[]>
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### NoProbe

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -NoProbe
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

The command uses `[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Probe', ConfirmImpact = 'Low')]` and `[OutputType([System.IO.FileInfo])]`. `SupportsShouldProcess` and `ConfirmImpact = 'Low'` match `Export-CompleterSet` (`src/Public/Export-CompleterSet.ps1`); the default set is new, because `Export-CompleterSet` has one set. Question 5 covers why the impact stays `Low` although the default set runs a program.

### PARAMETERS

| Parameter | Type | Sets | Required | Position | Pipeline | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `-CommandName` | `System.String[]` | all | yes | 0 | no | The native command names. The first is the primary name: it names the functions and state, and it is the one probed. |
| `-Path` | `System.String` | all | yes | 1 | no | The `.ps1` file to write. Resolved with `GetUnresolvedProviderPathFromPSPath`, as `Export-CompleterSet` resolves its `-Path`. |
| `-HelpArgument` | `System.String` | Probe | no | named | no | The one argument the probe passes. When omitted the probe chooses (see "Choosing the probe"). A value with a line break fails step 1 of "Order of work". |
| `-HelpText` | `System.String[]` | HelpText | yes | named | by value | Help text the author already captured. Lines are accumulated across pipeline input, joined with LF, cleaned, and parsed; nothing is run. `winget --help \| New-CompleterScript winget .\winget_completer.ps1` binds here. |
| `-NoProbe` | `SwitchParameter` | NoProbe | yes | named | no | Runs nothing and writes an empty subcommand table. |
| `-Force` | `SwitchParameter` | all | no | named | no | Overwrites an existing file. |
| `-PassThru` | `SwitchParameter` | all | no | named | no | Returns the written file as `System.IO.FileInfo`, so it pipes into `Test-CompleterScript` and `Import-CompleterScript` through their `FullName` and `PSPath` aliases (`src/Public/Test-CompleterScript.ps1`, `src/Public/Import-CompleterScript.ps1`). `Register-Completer` takes no path from the pipeline (`src/Public/Register-Completer.ps1`), so a lazy registration is `Register-Completer -LiteralPath $file.FullName -Lazy`. Without `-PassThru` the command returns nothing, as `Export-CompleterSet` does. |
| `-WhatIf`, `-Confirm` | `SwitchParameter` | all | no | named | no | `ShouldProcess` target = the full output path; the action names the program the probe would run (see "Order of work"). |

`-HelpText` is the one parameter not named in the roadmap. It exists for two reasons found while probing on 2026-10-02: the safety rules below refuse to run app execution aliases and `.cmd` shims (winget, npm, codex), and the tests need fixed help text that does not depend on which tools a CI runner has (section 8). It stays under either answer to question 5.

### Order of work

The command has `begin`, `process`, and `end` blocks. Step 1 runs in `begin`. `process` only accumulates `-HelpText` lines, so `winget --help | New-CompleterScript ...` binds one line per `process` call and the text is joined once. Steps 2 to 7 run once, in `end`.

1. **Validate.** Every check runs before anything is resolved, probed, or written, and under `-WhatIf` too:
   - each `-CommandName` value is a bare command name whose stem is not empty (see "Target list");
   - `-HelpArgument` contains no CR and no LF, else `-HelpArgument must not contain a line break.` Line 2 of the script names the argument in a `#` comment (see "Skeleton"), which a line break would end;
   - `-Path` ends in `.ps1`, else `Completer scripts must be .ps1 files. Received '<path>'.` (the text `Resolve-CompleterScriptPath` uses);
   - `-Path` is not an existing directory, else `Completer scripts must be file paths. '<path>' is a directory.`;
   - the parent directory exists, else `The directory '<directory>' does not exist.` (the text `Export-CompleterSet` uses);
   - the file does not exist, unless `-Force`, else `The file '<path>' already exists. Use -Force to overwrite it.`
2. **Resolve** (Probe set only). The primary name is resolved to an application and checked against the rules in "What 'read safely' means". Nothing runs in this step; it decides what step 3 names.
3. **Ask.** `ShouldProcess(<path>, <action>)`, where `<action>` is:
   - `Create completer script, running '<application path> <arg>' to read its help` for a probe with `-HelpArgument`, and for the default probe on Linux and macOS;
   - `Create completer script, running '<application path> --help' and, if it is rejected, '/?' to read its help` for the default probe on Windows;
   - `Create completer script without running a program` for the HelpText and NoProbe sets, and for a probe that step 2 found nothing to run for.

   Declined or `-WhatIf`: nothing is run, nothing is written, nothing is returned. The `What if:` line therefore names both the file and the program. The probe is a side effect, so it happens after this step, never before.
4. **Seed.** Read help text from the probe, from `-HelpText`, or not at all, and parse it into the subcommand table.
5. **Compose** the script text (see "Skeleton").
6. **Self-check.** Write the composed text to `<path>.<random>.tmp` in the same directory (see "Encoding and line endings"), then parse that file, run the strict grammar walk that `Test-CompleterScript` and `Import-CompleterScript` apply (`src/Private/Test-CompleterScriptAst.ps1`), and derive the targets as `Register-Completer -Lazy` does (`src/Private/Get-CompleterScriptTarget.ps1`, which does not run the grammar). Checking the file rather than the text means the check sees the bytes step 7 installs, encoding included. Any finding, any parse error, or derived targets that differ from the target list delete the temporary file and stop the command with `New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. <detail>`. `<detail>` is the first finding's `Message`, or, when there is no finding and the targets differ, `The script registers <derived list>, not <expected list>.`, each list written as the registration line writes it (`'rg', 'rg.exe'`). This turns the roadmap's "passes Test-CompleterScript before the author touches it" from a property of the template into a property of every output, including output built from arbitrary help text. Its cost was not measured: the roadmap estimates the walk at about 20 ms per script (milestone 3), and it runs once per generated file, never on an import path.
7. **Write.** Move the checked temporary file of step 6 into place with `[System.IO.File]::Move(<tmp>, <path>, <Force>)`. Without `-Force`, a file that appeared at `<path>` after step 1, for example during a probe, makes the move fail, and the command fails with step 1's `already exists` text. The temporary file is deleted on any failure; its `.tmp` extension keeps it out of a `*_completer.ps1` scan if a crash leaves it behind. Under `-PassThru`, the written file is returned.

Every failure is a terminating error `Failed to create completer script. <reason>`, including the step 1 checks, and nothing is left at `<path>` by a failed call. This differs from `Export-CompleterSet`, which throws its `begin`-block checks unwrapped and wraps only the failures in `end` with `Failed to export completer set. <reason>` (`src/Public/Export-CompleterSet.ps1`).

### Target list

- A command name must match `^(?=.*[A-Za-z0-9])[A-Za-z0-9_](?:[A-Za-z0-9._+-]*[A-Za-z0-9_+])?$`: at least one letter or digit; no path separators, spaces, quotes, or wildcard characters; no leading `-` or `.`; and no trailing `.` or `-`. So `_` and `__`, which would give an empty stem, and `foo.`, which would give `foo..exe`, are rejected. Otherwise: `'<name>' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters.`
- A name that matches but whose only letters and digits are in a trailing `.exe`, `.cmd`, `.bat`, `.ps1`, or `.com`, such as `_.exe` or `__.cmd`, would give an empty stem (see "Names in the generated script"), and with it `function Complete-` and `$script:CompletionCatalog`. It is rejected with `The command name '<name>' has no letter or digit outside its suffix, so no function name can be derived from it.` The check applies to every name, as the pattern does. `_a` passes and gives the stem `A`.
- The target list is built in `-CommandName` order. Each name is written as given, and a name that does not end in `.exe`, `.cmd`, `.bat`, `.ps1`, or `.com` (compared case-insensitively) is followed by the same name with `.exe` appended. Names are de-duplicated case-insensitively, keeping the first spelling. So:
  - `-CommandName rg` gives `'rg', 'rg.exe'`, and `-CommandName rg, rg.exe` gives the same list;
  - `-CommandName python3.12` gives `'python3.12', 'python3.12.exe'`, because a dotted version is not one of the five suffixes;
  - `-CommandName npm.cmd` gives `'npm.cmd'`, and `-CommandName rg.exe` gives `'rg.exe'`: no bare name is derived from a suffixed one.
- Why `.exe` is added on every platform (question 4): 161 of the 173 PS_Completers entries list every bare name together with its `.exe` form. Of the other 12, 3 register one name (`dism`, `dotnet`, `dsc`), 8 pair the bare name with `.cmd` or `.ps1` shims (`codex`, `pnpm`, `scoop`, and five more), and `grok` adds the bare alias `agent` without an `.exe`. The set is shared between Windows and the Linux CI, where the `.exe` target is harmless. Counted from `ps_completers.psd1` at `2c590c6` (appendix B); the roadmap's milestone 2 introduction says 169 scripts, and the set now has 173 entries and 362 targets.

### Names in the generated script

- **Stem.** The primary name, without a trailing `.exe`, `.cmd`, `.bat`, `.ps1`, or `.com`, is split on every character that is not an ASCII letter or digit; the first character of each part is upper-cased with the invariant culture, and the parts are joined. `rg` and `rg.exe` both give `Rg`, `cargo-binstall` gives `CargoBinstall`, `oh-my-posh` gives `OhMyPosh`, `DSC` stays `DSC`, `7z` gives `7z`. A stem that starts with a digit is valid: `$script:7zCompletionCatalog` and `Complete-7z` parse and pass the grammar (checked 2026-10-02). The regex alone does not keep the stem from being empty, because `_.exe` and `__.cmd` match it; the empty-stem rule of "Target list" rejects them in step 1, so no script is ever written with an empty stem.
- **State variable:** `$script:<Stem>CompletionCatalog`, the naming PS_Completers already uses (`du_completer/du_completer.ps1` declares `$script:DuCompletionCatalog`).
- **Completion function:** `Complete-<Stem>`, as in `Complete-Du`.
- Line 1 uses the primary name as given, so `-CommandName rg.exe` writes `# rg.exe tab completion for PowerShell`.

### Choosing the probe

| Parameter set | What runs |
| --- | --- |
| `NoProbe` | Nothing. The table is empty. |
| `HelpText` | Nothing. The given text is cleaned and parsed. |
| `Probe` with `-HelpArgument <arg>` | `<primary> <arg>`, once. |
| `Probe` without `-HelpArgument`, Windows | `<primary> --help`. If that run completed, yielded no subcommand, and printed fewer than five non-blank lines, which is what a tool that rejects `--help` prints, then `<primary> /?` runs once and its result is used. |
| `Probe` without `-HelpArgument`, Linux and macOS | `<primary> --help`, once. `/?` is never tried. |

No `/?` runs after a timeout, a start failure, a run whose output a descendant still held, or a refusal to run; the fallback applies only when `--help` ran to completion. So one call never writes two probe warnings or starts a second program after a failed first.

The five-line rule comes from probes on the owner's machine on 2026-10-02, all of Windows-only tools, so CI tests the rule through a double (section 8, check 9). `schtasks`, `reg`, `bcdedit`, and `netsh` reject `--help` in one or two lines and print their help for `/?`. `wsl --help` prints 14,092 characters without a commands section, and `wsl /?` started `/bin/bash` inside WSL and took 3.6 s. The rule runs `/?` for the first group and never for `wsl`.

### What "read safely" means

The probe resolves the primary name with `Get-Command -Name <primary> -CommandType Application -ErrorAction Ignore`, first match, so a function, alias, cmdlet, or `.ps1` script of that name is never run. `-ErrorAction Ignore` is required: under `$ErrorActionPreference = 'Stop'`, which GitHub's `shell: pwsh` sets, a missing command otherwise throws `CommandNotFoundException` out of the module function (checked on 7.6.6). Then:

- **Not found:** nothing runs; warning `The command '<primary>' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand.`
- **Windows, not a console program:** the file is run only if it is a `.exe` whose PE header can be read and whose `Subsystem` field is 3 (Windows CUI). The header is read with `[System.IO.File]::OpenRead`; no process is started to inspect it. The reader checks the `MZ` signature, follows `e_lfanew` to the `PE\0\0` signature, checks the optional-header magic (`0x10B` for PE32, `0x20B` for PE32+), and reads `Subsystem` from the optional header; a file too short for that, or with a wrong signature or magic, counts as unreadable. Otherwise nothing runs and the command warns `'<path>' was not run: <reason>. Run '<primary> --help' yourself and pass the text with -HelpText.` The reasons are:
  - `it is a Windows GUI program` when `Subsystem` is 2. On 2026-10-02 `calc.exe` and `explorer.exe` read as 2; `pwsh.exe`, `wsl.exe`, `schtasks.exe`, and scoop's `7z.exe` shim read as 3.
  - `it is not a Windows console program (subsystem <n>)` when `Subsystem` is any value other than 2 or 3, with `<n>` in decimal, for example 1 for a native image or 10 for an EFI application.
  - `it is a <ext> file, which only runs through cmd.exe` for any other extension, where `<ext>` is the extension with its dot, in lower case: `npm` resolved to `npm.cmd` and `code` to `code.cmd`, and a file named `TOOL.BAT` gives `it is a .bat file`.
  - `its program header could not be read` when opening or reading fails. App execution aliases fail this way: `winget.exe` under `%LOCALAPPDATA%\Microsoft\WindowsApps` has length 0 and `OpenRead` throws "The file cannot be accessed by the system", and so did each of the six aliases sampled there. `Process.Start` can run an alias, but the probe does not, because it cannot tell whether a GUI program sits behind it.
- **Linux and macOS:** any resolved application is run directly. There is no subsystem to check; a script with a shebang runs its own interpreter.
- **Start failure:** any exception from `Process.Start` becomes the warning `'<path>' was not run: <exception message>. Pass captured help with -HelpText.`, and the table stays empty. Cases seen on 2026-10-02: on Linux, a file on `PATH` without the execute bit still resolves through `Get-Command -CommandType Application`; on Windows, a `.exe` the loader rejects throws "not a valid application for this OS platform". A program that requires elevation is expected to throw the same way.

The run itself:

- `System.Diagnostics.Process` with `UseShellExecute = $false`, `CreateNoWindow = $true`, and the argument in `ArgumentList`, so no shell parses it. Standard input is redirected and closed at once, so a tool that reads stdin sees end of file instead of waiting.
- Standard output and standard error are read concurrently as bytes. Each reader keeps the first 1 MiB and keeps draining after that, discarding the rest, so a chatty tool never blocks on a full pipe. The working directory is `[System.IO.Path]::GetTempPath()`, so a tool that writes into its current directory does not write into the author's repository. The environment is the session's, plus `NO_COLOR=1`.
- **One deadline covers the process and both reads.** The limit is 5 seconds, held in module state so a test can shorten it; it is not a parameter.
  - If the process has not exited at the deadline, the process and the descendants it still has are killed (`Kill($true)`), the output is not used, and the command warns `'<primary> <arg>' did not exit within <limit> seconds and was stopped, so its help was not used.` `<limit>` is the effective limit, formatted with the invariant culture (`5`, or `0.05` in a test).
  - If the process exited but a reader has not finished 1 second later, or at the deadline if that comes first, a descendant holds the output pipe. This is what daemonising tools (build servers, device bridges) do. The streams are closed, `Kill($true)` is attempted and any failure ignored, the output is not used, and the command warns `'<primary> <arg>' exited but left a process holding its output, so its help was not used.` On 2026-10-02 a parent that started such a descendant exited in 31 ms on Windows while its reader was still open 1.6 s later, and on Linux `Kill($true)` after the parent's exit left the descendant running.
  - **Residual risk:** a descendant whose parent has exited is no longer in the tree that `Kill($true)` walks, so it can outlive the probe on every platform. A Windows Job Object would contain it, but needs a P/Invoke type compiled with `Add-Type`, which took 188 to 349 ms on first use in a fresh `pwsh -NoProfile` (measured 2026-10-02), and native interop belongs in 3.0's compiled core. `about_Import_Completers` lists this risk (section 4).
- The exit code does not decide anything. Many tools print help and exit nonzero: `go --help` exits 2 with its help on stderr, `netsh /?` exits 1. The text used is standard output, or standard error when standard output is empty or whitespace after decoding.
- **Decoding**, in order:
  1. Bytes that start with the UTF-16 LE byte-order mark `FF FE`, or that contain U+0000 when decoded as UTF-8, are decoded as UTF-16 LE. `wsl.exe` writes UTF-16 LE without a byte-order mark.
  2. Otherwise the bytes are decoded as strict UTF-8, which throws on an invalid sequence; a UTF-8 byte-order mark is dropped.
  3. If strict UTF-8 fails: on Windows the bytes are decoded with the OEM code page of the current culture (`[System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage`, 437 on this machine), which is what a console tool writes when nothing changed its code page: `cmd /c echo café` writes `82` for `é`, and a lenient UTF-8 decode turns it into U+FFFD. On Linux and macOS the fallback is Latin-1.
  4. A leading U+FEFF left by any decoder is removed.
- **Cleaning**, which applies to probe output and to `-HelpText` alike:
  - CSI sequences, with the pattern PS_Completers scripts use, `\e\[[0-9;?]*[ -/]*[@-~]`;
  - OSC sequences, such as titles and OSC 8 hyperlinks, `\e\][^\a\e]*(?:\a|\e\\)`, which the CSI pattern leaves as `]8;;http...`;
  - any remaining two-character escape, `\e[@-_]`;
  - backspace overstrikes;
  - carriage returns: CR LF becomes LF, and then a line keeps only the text after its last remaining CR, as a terminal shows it. That removes progress spinners such as winget's.
- Each run writes one verbose line: `VERBOSE: Probed '<path> <arg>': exit <code>, <n> characters, <m> subcommands, <ms> ms.`

On 2026-10-02 every console tool probed finished in under 1 s with `--help` (`rg` 29 ms, `cargo` 47 ms, `docker` 196 ms, `uv` 934 ms), so 5 s leaves a wide margin.

### Parsing the subcommand table

The parser reads line by line. The rules are fixed, so the same text always gives the same table:

1. **Section header:** a whole line, at any indentation, made of an optional `<`, one to six words separated by single spaces, an optional `>`, and an optional trailing `:`. A word is made of letters, `(`, `)`, and `,`, and one word, with its parentheses and commas trimmed, is `command`, `commands`, `subcommand`, or `subcommands` in any case. Examples that match: `Commands:`, `Common Commands:`, `CORE COMMANDS`, `SDK commands:`, `Basic Commands (Beginner):`, `Subcommands provided by plugins:`, `The following commands are available:`, `The commands are:`, `<Commands>`, `Additional commands from bundled tools:`. Not matching: git's `These are common Git commands used in various situations:` (nine words), `Parameter List:`, `Options:`.
2. After a header, blank lines and underline lines (`===`, `---`) are skipped.
3. **Entry:** a line that starts with optional indentation, then a name, then a separator, then a description. A name is an optional `/` followed by letters, digits, `.`, `_`, or `-`, starting and ending with a letter or digit. An optional `*` (docker plugins) and comma-separated aliases (`build, b`) may follow the name and are dropped. The separator is a `:` followed by whitespace (`auth:`, `a : Add`), a run of two or more `-` (`query-----Queries`), ` - `, two or more spaces, or a tab.
4. **Inside a section.** The first entry fixes the section's indentation. After it, until the section ends:
   - an entry at that indentation is kept;
   - a line indented deeper is a continuation and is skipped;
   - any other line that is not an entry is skipped and does not end the section. That covers a description wrapped back to column 0 (pip's `dependencies.`) and an entry whose separator the rules do not know (sc's `qmanagedaccount-Queries`, with one `-`);
   - a blank line, a header, or an entry at a shallower indentation ends the section. A line that ends a section is checked as a header in its turn.
5. Names are kept in help order and de-duplicated case-insensitively, keeping the first. The description is the entry's text with control characters, Unicode format characters (category Cf, such as U+202E and U+200B), and line and paragraph separators (Zl, Zp) replaced by spaces, runs of whitespace collapsed, and ends trimmed. That keeps bidirectional overrides out of the generated `.ps1`. An empty description becomes the name, because `CompletionResult` rejects an empty tooltip.

Results on 2026-10-02 with a prototype of these rules over help captured that day (scratch only, not committed). The same prototype with the first draft's rules, which differed in rule 1 (letters only) and rule 4 (any non-entry line ended the section), reproduced the first draft's counts for every tool in this table except the three marked.

| Command | Probe | Subcommands | Notes |
| --- | --- | --- | --- |
| `cargo` | `--help` | 16 | `...  See all commands` is not an entry, because a name starts with a letter or digit |
| `docker` | `--help` | 65 | four sections; `*` dropped |
| `gh` | `--help` | 34 | `name:` form |
| `rustup` | `--help` | 17 | its later `Common commands:` holds examples and yields none |
| `dotnet` | `--help` | 26 | two sections |
| `go` | `--help` | 19 | tab-indented, on stderr, exit 2 |
| `uv` | `--help` | 23 | |
| `pip` | `--help` | 18 | all 18; a description wraps to column 0 (first draft: 9) |
| `kubectl` | `--help` | 43 | all 43; parenthesised headers (first draft: 35) |
| `7z` | `--help` | 11 | `<Commands>`, `a : Add files` form |
| `sc` | `--help` | 35 | dashed form; continuations skipped; `qmanagedaccount` missed (first draft: 22) |
| `bcdedit` | `/?` | 20 | `/store` names kept with the slash |
| `winget` | `--help` via `-HelpText` | 19 | not probed: app execution alias |
| `rg`, `just` | `--help` | 0 | option-only tools |
| `git` | `--help` | 0 | nine-word header; grouped layout |
| `schtasks`, `netsh`, `reg` | `/?` | 0 | `Parameter List:`, unindented `?` first entry, inline list |

`sc`, `bcdedit`, `schtasks`, `netsh`, `reg`, and `winget` exist only on Windows; their rows are evidence from the owner's machine, and CI exercises their captures through `-HelpText` (section 8, check 4).

A table with no entries is not an error and not a warning when help was read. It is the normal result for an option-only tool such as `rg`.

**A partial table is a known limitation.** It passes `Test-CompleterScript`, so the self-check cannot catch it; `sc` above is the example. `about_Import_Completers` tells the author to compare the table with the tool's help (section 4).

### Skeleton

The output is exactly the following, with `<Name>` the primary name, `<Stem>` from above, `<Arg>` the probe argument, and the target list from above. This is what `-CommandName cargo` produced through the prototype; the subcommand rows are abbreviated here.

```powershell
# cargo tab completion for PowerShell
# Help-seeded native completer: the subcommand table was read from 'cargo --help' when the script was generated.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name CargoCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:CargoCompletionCatalog = @{
        Subcommands = @(
            @{ Name = 'build'; Description = 'Compile the current package' }
            @{ Name = 'check'; Description = 'Analyze the current package and report errors, but don''t build object files' }
        )
    }
}

function Complete-Cargo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Offer subcommands in the first argument position only; extend this function for options and values.
    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })
    if ($precedingElements.Count -gt 1) {
        return
    }

    foreach ($subcommand in $script:CargoCompletionCatalog.Subcommands) {
        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.Management.Automation.CompletionResult]::new($subcommand.Name, $subcommand.Name, 'ParameterValue', $subcommand.Description)
        }
    }
}

Register-ArgumentCompleter -Native -CommandName 'cargo', 'cargo.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cargo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Fixed properties of the shape (counts from PS_Completers at `2c590c6`, appendix B):

- **Line 1** is `# <Name> tab completion for PowerShell`, the first line of 118 of the 173 PS_Completers scripts.
- **Line 2** depends on the source. From a probe, it reads `... read from '<Name> <Arg>' when the script was generated.`, where `<Arg>` is the argument whose output was used (`/?` when the fallback ran). From `-HelpText` it reads `... read from help text passed to New-CompleterScript.` When the table is empty, it reads `# Native completer skeleton: add subcommands to the table and options to Complete-<Stem>.` No date, version, or machine path appears anywhere, so the output is deterministic.
- **`Set-StrictMode -Version 2.0`**, as in 144 of the 173 scripts.
- **One guarded, literal-only state block** (shape 1 of `about_Import_Completers`): an `if (-not (Get-Variable ...))` guard around a single `$script:` assignment whose value is a hashtable of literals. An empty table is written `Subcommands = @()`. Anything computed, such as tool discovery or a cache filled from live output, belongs in a function the author adds and calls lazily from `Complete-<Stem>` (shape 3). The skeleton has no initializer of its own, because a static table needs none.
- **String literals** are single-quoted. Every single-quote character PowerShell's tokenizer accepts as a delimiter, U+0027, U+2018, U+2019, U+201A, and U+201B, is doubled. Help text such as "don’t" with a typographic apostrophe would otherwise end the string. Other non-ASCII letters are kept as is; format and separator characters were already replaced by parsing rule 5.
- **The completion function** offers the table only in the first argument position. A completer that returns nothing lets PowerShell fall back to path completion, which is what `rg <Tab>` shows with an empty table. The generated code uses only APIs available in PowerShell 7.0.
- **The registration** is a bare script-scope `Register-ArgumentCompleter` at the end of the file: named `-Native`, `-CommandName` as a literal comma list, a named literal `-ScriptBlock`, no `try`/`catch` around it, and no splatting. 100 of the 173 scripts register with one top-level call that names a literal `-CommandName` list and a literal `-ScriptBlock`.
- **Formatting:** four-space indentation and opening braces on the same line, as in the PS_Completers scripts. This is a deliberate difference from the module's own Allman style, because the output belongs to the author's repository.

On 2026-10-02, 16 prototype outputs under the first draft's parsing rules (`cargo`, `docker`, `gh`, `git`, `rustup`, `winget`, `dotnet`, `go`, `7z`, `uv`, `rg`, `just`, `schtasks`, `bcdedit`, `sc`, `netsh`) gave:

- 0 `Test-CompleterScript` findings;
- 32 records from `Import-CompleterScript`, and the same 32 targets from `Register-Completer -Lazy`;
- an `Export-CompleterSet` set for which `Test-CompleterSet` returned nothing;
- these `TabExpansion2` results: `cargo b` gave `build, bench`; `cargo.exe ru` gave `run`; `docker con` gave `container, context`; `bcdedit /cr` gave `/createstore`; `cargo build ` gave path completion. The `cargo ch` tooltip round-tripped the doubled apostrophe.

The skeleton does not depend on the parsing rules, so the revision changes only table contents. Checks 4 and 5 in section 8 re-establish these results under the final rules.

### Encoding and line endings

The file is written as `Export-CompleterSet` writes a set: `Set-Content -Encoding utf8`, which is UTF-8 without a byte-order mark, with the platform newline (CR LF on Windows, LF elsewhere) and a final newline, first to the temporary file of step 6. None of the 173 PS_Completers scripts has a BOM, and their Windows working tree is CR LF (milestone 1 spec, section 2). The set `Hash` normalises line endings, so the choice does not affect drift checks.

### Output and messages

- **Output:** nothing, or the `FileInfo` under `-PassThru`.
- **Warnings:** only the probe warnings above: not found, not run (with its reason or the start exception), did not exit, and exited but left a process holding its output. An empty table from readable help is silent.
- **Verbose:** the resolved application, or the reason it was not run; the probe line per run; then `VERBOSE: Wrote '<path>': <n> targets, <m> subcommands.`

### EXAMPLES

```powershell
New-CompleterScript -CommandName cargo -Path .\cargo_completer\cargo_completer.ps1 -PassThru | Test-CompleterScript
```

Example 1. Writes the cargo skeleton seeded from `cargo --help` and checks it; the pipeline is empty.

```powershell
winget --help | New-CompleterScript -CommandName winget -Path .\winget_completer\winget_completer.ps1
```

Example 2. Seeds the table from help the author ran, for a command the probe will not run.

```powershell
New-CompleterScript -CommandName mytool -Path .\mytool_completer.ps1 -NoProbe -Force
```

Example 3. Writes an empty skeleton without running anything, replacing an existing file.

## 3. Installable completer sets

### The package layout

A completer-set package is an ordinary PowerShell module whose manifest names a set file in a subfolder. Installed, it looks like this:

```text
PS_Completers/
  1.0.0/
    PS_Completers.psd1          module manifest, the only .psd1 in this folder
    LICENSE
    README.md
    completers/
      completers.psd1           the set, written by Export-CompleterSet
      7z_completer/
        7z_completer.ps1
        7z_completer.md
      git_completer/
        git_completer.ps1
      ...
```

- **The module folder (`ModuleBase`) holds exactly one `.psd1`, the manifest.** `Publish-PSResource` takes the first `*.psd1` it finds in the folder as the module manifest. Tested on 2026-10-02 against a local file repository: `completers.psd1` beside `PS_Completers.psd1`, and `aaa.psd1` beside `ZzPk.psd1`, each failed with "No author was provided in the module manifest"; a set file whose name sorts after the manifest's published, and so did a set in a subfolder. On Linux the directory listing came back unsorted, so a set beside the manifest publishes or fails depending on file system order.
- **The set file sits in one subfolder directly below `ModuleBase`.** `PrivateData.CompleterSet` names both, as `'<folder>/<file>.psd1'`. The scripts sit in or below that folder, and every entry `Path` is relative, which is how `Export-CompleterSet` writes a path under the set's folder (`src/Public/Export-CompleterSet.ps1`).
- **The set file's base name differs from the module name, compared case-insensitively.** PSResourceGet 1.2.0 `Save-PSResource` reads any `.psd1` in the package whose base name equals the module name, case-insensitively, as the manifest, even in a subfolder: on 2026-10-03, under WSL, a package `PS_Completers` holding `completers/ps_completers.psd1` published but could not be saved, and the same package with the set named `set.psd1` saved (`validation/milestone-2-runtime.md`, row 5). `Test-CompleterSet` reports the collision (below).
- **Otherwise the folder and file names are free.** The examples use `completers/completers.psd1`. PS_Completers's package names its set `completers/completers.psd1`; the repository keeps `ps_completers.psd1` (see "PS_Completers as the reference package").
- This deviates from the roadmap item's "the set file at the module root, scripts beside it", which cannot be published reliably. Question 7 asks the owner to accept it, and section 6 carries the roadmap edit.

The manifest needs four things:

```powershell
@{
    ModuleVersion     = '1.0.0'
    GUID              = '<new guid>'
    Author            = '<author>'
    Description       = 'Argument completers for native commands, as a CompleterActions completer set.'
    RequiredModules   = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' })
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        CompleterSet = 'completers/completers.psd1'
        PSData       = @{ Tags = @('completer', 'argument-completer') }
    }
}
```

- **`PrivateData.CompleterSet`** is the marker and the pointer, and it is the only thing that makes a module a completer-set package. There is no fallback file name: a module without the key is not a set package. `New-ModuleManifest -PrivateData @{ CompleterSet = 'completers/completers.psd1' }` writes it beside `PSData` (checked 2026-10-02). Pass tags with `-Tags`, not as a `PSData` key inside `-PrivateData`: that writes a manifest with two `PSData` keys, which `Test-ModuleManifest` rejects. `New-ModuleManifest` also omits an empty `VariablesToExport`, which is harmless for a package with no `RootModule`.
- **`RequiredModules` names CompleterActions 2.2.0 or later**, so `Install-PSResource PS_Completers` installs the command that imports it. The package is never imported, so this is an install dependency only.
- **No `RootModule`** and empty export lists. Nothing in the package runs when the set is imported. A `RootModule` is not an error: `Import-CompleterSet -Name` never loads it, and `Test-CompleterSet` reports no finding for it.
- A manifest `ModuleVersion` cannot carry a prerelease label, so a package cannot depend on `2.2.0-preview1`. Question 10 covers what that means for the exit criterion.

### `Import-CompleterSet -Name`

New parameter set:

```PowerShell
Import-CompleterSet -Name <string[]> [-SkipInvalid] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

| Parameter | Type | Sets | Required | Pipeline | Notes |
| --- | --- | --- | --- | --- | --- |
| `-Name` | `System.String[]` | Name | yes | no | Module names. Literal: a value containing `*`, `?`, `[`, or `]` fails the call, before any value is resolved, with `Failed to import completer set. Import-CompleterSet -Name does not accept wildcards. Received '<name>'.` |

`-Name` takes no pipeline input. `Get-Module` output already binds `-Path` by its `Path` property, and a second by-property binding would make the parameter set ambiguous. The `Path` set stays the default, and `-Path` stays at position 0.

**Resolution.** It follows the module's own lookup without calling `Get-Module -ListAvailable`:

1. Walk `$env:PSModulePath` in order, split on `[System.IO.Path]::PathSeparator` (`;` on Windows, `:` on Linux and macOS), skipping empty and missing entries.
2. In each root, the module folders are the root's subdirectories whose name equals `<Name>` case-insensitively, on every platform. The root is enumerated rather than joined with the name, because `Import-Module ps_completers` loads a module installed as `PS_Completers` on Linux (checked under WSL), and a profile line should not depend on file system case. Within a module folder, the manifest is the `.psd1` whose base name equals the folder's name, case-insensitively.
3. The candidates are `<folder>/<version>/<manifest>` for every `<version>` subfolder that parses as `[version]` and equals the manifest's `ModuleVersion` compared as `[version]`, and `<folder>/<manifest>`. A version folder that disagrees with its manifest is not a candidate, because PowerShell ignores it too: on 2026-10-02 `Get-Module -ListAvailable` found nothing for folder `9.0.0` with `ModuleVersion = '1.0.0'`, nor for `1.0.0.0` with `1.0.0`, while folder `1.0` with `1.0` was found.
4. **The first root with a candidate wins**, and within it the highest version wins. The unversioned layout is used only when the root has no versioned candidate. This is the rule `Import-Module` follows. Checked 2026-10-02: with `ZzSetProbe` 1.0.0 in the first root and 2.0.0 in the second, `Import-Module ZzSetProbe` loaded 1.0.0.
5. Manifests are read with `Import-PowerShellDataFile`, as data only. The package module is not imported, so its `RootModule`, `ScriptsToProcess`, `NestedModules`, and `RequiredModules` never load or run.
6. `PrivateData.CompleterSet` must be a non-empty string of the form `<folder>/<file>.psd1` (`\` is accepted as the separator), naming a file in a folder directly below `ModuleBase`. `..`, a rooted path, and a file directly in `ModuleBase` are rejected.
7. The resolved file is then imported as `-LiteralPath <file>` would import it: same validation, same records, same warnings, same transaction per set, with the two additions below. The records' `ScriptPath` values point into the installed module.

Every `-Name` value is resolved before any set is imported. A value that does not resolve fails the call with `Failed to import completer set. <reason>`, which is how a `-Path` that does not resolve fails today (`src/Public/Import-CompleterSet.ps1`). The reasons are:

| Situation | Reason text |
| --- | --- |
| No root has the module | `No installed module named '<Name>' was found in $env:PSModulePath. Install it with Install-PSResource <Name>.` |
| The chosen manifest has no `PrivateData.CompleterSet` | `The module '<Name>' <version> at '<ModuleBase>' does not declare a completer set. A completer set module names its set file in PrivateData.CompleterSet.` |
| The value is not a string, not `.psd1`, not in a folder directly below `ModuleBase`, or contains `..` | `The module '<Name>' <version> declares the completer set '<value>', which must be a .psd1 file in a folder directly below '<ModuleBase>'.` |
| The set file is missing | `The completer set '<file>' declared by the module '<Name>' <version> does not exist.` |

The highest version is used even when it is broken. The command never falls back to a lower version, because a silent downgrade would hide the broken install. `<version>` is `ModuleVersion`, followed by `-<Prerelease>` when `PrivateData.PSData.Prerelease` is set; the folder decides the order, and, since a candidate's folder equals its `ModuleVersion`, the two cannot disagree.

`<Name>` in the not-found reason is the value as given, because no folder was found. Everywhere else, in the other reasons, the verbose line, the containment problem, and the trusted-entry warning, `<Name>` is the installed module folder's spelling, so `-Name cafixtureset` reports `CaFixtureSet`. `<ModuleBase>` is the full path of the version folder, or of the module folder for the unversioned layout, as `[System.IO.Path]::GetFullPath` returns it.

**A package's set is the package author's code.** Two additions apply under `-Name` only:

- **Scripts stay inside the module.** An entry whose script resolves outside `ModuleBase` is an invalid entry, with the problem text `the script '<path>' is outside the module '<Name>' at '<ModuleBase>'`. It goes through the existing invalid-entry path: the set fails with nothing registered, or, under `-SkipInvalid`, the entry is skipped with a warning (`src/Public/Import-CompleterSet.ps1`). The test runs on the full path after `[System.IO.Path]::GetFullPath`, compares with a trailing separator so that `PS_Completers2` is not inside `PS_Completers`, and compares with `OrdinalIgnoreCase` on Windows and macOS and `Ordinal` on Linux. Links are not resolved: a link inside the package is the package's own content. The containment test comes before the existence check, so an entry outside the module gets this problem and no other, whether or not its file exists, and the file is never opened, read, or hashed.
- **Trusted entries are announced.** When the set has trusted entries, one warning per name: `The completer set module '<Name>' <version> declares <n> trusted completer scripts, which run without the strict grammar check at first tab.` `<n>` counts the set file's entries whose `Trusted` is `$true`. The warning is written after the set file is read and before its entries are validated, so a set that then fails still announces its trusted entries. The 173 PS_Completers entries are all `Trusted = $false`, so its profile line stays quiet.

`-LiteralPath` and `-Path` keep their 2.1.0 behaviour in both respects, because a set on a path is the user's own. The help and `about_Completer_Sets` say that installing a completer-set package and importing it by name is a decision to run its scripts (section 4).

**Verbose:** one line per name before the set's own lines: `VERBOSE: Completer set module '<Name>' <version> at '<ModuleBase>': '<file>'.`

**Cost:** resolution touches only the directories and the manifests it needs. On 2026-10-02 a direct lookup of CompleterActions took 1.3 to 8.4 ms, against 48 to 94 ms for `Get-Module -ListAvailable -Name CompleterActions`. Section 5 sets the budget.

### `Test-CompleterSet` and the package layout (proposed, pending questions 8 and 9)

The roadmap asks how `Test-CompleterSet` works with the package layout but names no new checks. Everything in this subsection ships only for the parts of questions 8 and 9 the owner accepts. If both are rejected, the rules of "The package layout" are documentation only (section 4), and `Test-CompleterSet` is unchanged from 2.1.0.

**`Test-CompleterSet -Name` (question 9).** New parameter set, resolved exactly as `Import-CompleterSet -Name` resolves:

```PowerShell
Test-CompleterSet -Name <string[]> [-Filter <string>] [<CommonParameters>]
```

A resolution failure is the terminating error `Failed to test completer set. <reason>`, with the reasons from the table above and the same `<Name>` spelling rule. A value containing `*`, `?`, `[`, or `]` fails the call, before any value is resolved, with `Failed to test completer set. Test-CompleterSet -Name does not accept wildcards. Received '<name>'.`

**When the package checks run (question 8).** A set is a package set when its manifest is known: through `-Name`, or, for `-Path` and `-LiteralPath`, when the folder above the set file's folder holds a `.psd1` that reads as data through `Import-PowerShellDataFile` and whose `PrivateData.CompleterSet` resolves to this set file. That is the case in a staged package before it is published, where the folder name need not match the module name. A `.psd1` that cannot be read as data is not a manifest that declares the set, and a folder that cannot be listed holds none. When more than one `.psd1` in that folder declares the set, the first in ordinal order of file name is the manifest. A set that no manifest declares gets no `PackageLayout` finding, so every set that 2.1.0 tests gives the same findings in 2.2.0.

**`PackageLayout` findings** come after the 2.1.0 entry findings and before the `UnlistedScript` findings. `Path` is the set file for every finding, as `Test-CompleterSet`'s help states (`src/Public/Test-CompleterSet.ps1`); a finding about the manifest or the module folder names the file in `Message` and points at line 1, column 1 of the set. Each row is an independent choice under question 8:

| Severity | Reported when | `Line`, `Column` | `Message` | `Hint` |
| --- | --- | --- | --- | --- |
| Error | An entry's `Path` is fully qualified, or resolves outside the module folder | the entry's `Path` value | `Entry <n> ('<path>'): the script is outside the module folder, so an installed copy of the package does not contain it.` | `Move the script under the folder that holds the set file, then regenerate the set with Export-CompleterSet.` |
| Error | The module folder holds a `.psd1` other than the manifest | line 1, column 1 | `The module folder '<ModuleBase>' holds '<file>' beside the module manifest '<manifest>', so Publish-PSResource can take the wrong file as the manifest.` | `Keep the module manifest as the only .psd1 in the module folder; move the set into a subfolder and update PrivateData.CompleterSet.` |
| Error | The set file's base name equals the module name, compared case-insensitively on every platform (the module name is the manifest's base name, or under `-Name` the installed module folder's spelling) | line 1, column 1 | `The set file '<file>' has the base name of the module '<Name>', so PSResourceGet can take it as the module manifest when it saves or installs the package.` | `Rename the set file so its base name differs from the module name, for example to completers.psd1, and update PrivateData.CompleterSet.` |
| Warning | `RequiredModules` does not list `CompleterActions` with a `ModuleVersion` or `RequiredVersion` of 2.2.0 or later | line 1, column 1 | `The module manifest '<manifest>' does not require CompleterActions 2.2.0 or later, so installing the package does not install Import-CompleterSet -Name.` | `Add @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' } to RequiredModules in '<manifest>'.` |

The first row is reported per entry, in set order. The second row gives one finding per extra `.psd1`, in ordinal order of file name. The `PackageLayout` findings come in row order: every row 1 finding, then row 2's, then row 3's, then row 4's.

Row 3 was added on 2026-10-03, after WP9 found that PSResourceGet 1.2.0 reads a `.psd1` named like the module as the manifest, even in a subfolder ("The package layout"). `<file>` is the set's file name. Like the other rows it fires only for a set a manifest declares, so every set that 2.1.0 tests still gives 2.1.0's findings, and `Import-CompleterSet -Name` is unchanged.

The severity rule extends 2.1.0's: `Error` when the package would fail to publish, install, or import, and `Warning` when it installs but a clean machine is missing a piece. A fully qualified path is an error even when it points inside the module folder, because it names the source tree, not the installed copy. On Windows, a script on another drive than the set is written fully qualified by `Export-CompleterSet`, which is exactly what the first row catches.

Trusted entries are not a package finding. `Import-CompleterSet -Name` announces them (above).

### `Export-CompleterSet` and the package layout

No change. Run with `-Path` in the set's folder, it already writes relative, forward-slash paths for scripts under that folder, `../` paths for scripts elsewhere on the same drive, and fully qualified paths for scripts on another drive (`src/Public/Export-CompleterSet.ps1`, `GetRelativePath`). `Export-CompleterSet` does not read manifests and does not refuse an outside path, because a set that is not a package may legitimately point anywhere.

### PS_Completers as the reference package (consumer follow-up, outside this repository)

Nothing here is part of the module change. It is listed so the owner can see the whole cost, and so the order against the releases is fixed.

**The package.** The layout tree above is PS_Completers', with `PrivateData.CompleterSet = 'completers/completers.psd1'`. The set is staged as `completers/completers.psd1`, not under its repository name, because a set named `ps_completers.psd1` in a module named `PS_Completers` cannot be saved or installed (the set-file name rule of "The package layout"). The set and the `*_completer` folders keep their positions relative to each other, so the set file is copied byte for byte under its new name: its relative paths and its hashes hold unchanged.

**What changes in the PS_Completers repository:**

1. **A manifest at `package/PS_Completers.psd1`**, shaped as above. It cannot sit at the repository root, because `PS_Completers.psd1` and `ps_completers.psd1` are one file on Windows and macOS.
2. **A staging tool** (name free, for example `tools/Build-Package.ps1`) that builds `<staging>/PS_Completers/`: the manifest, `LICENSE`, and `README.md` at its root, and, under `completers/`, `ps_completers.psd1` copied as `completers.psd1` with every `*_completer` folder. It leaves out `tests`, `tools`, `.github`, `docs`, `package`, and `.claude`. `Publish-PSResource` packs the whole folder it is given, so publishing the repository root would ship the tests and tools.
3. **A package gate**, if question 8 is accepted: `tests/Completers.Tests.ps1` stages into `$TestDrive` and asserts that `Test-CompleterSet -LiteralPath <staging>/PS_Completers/completers/completers.psd1` returns nothing. The manifest one folder up makes it a package set, so the gate also catches a set staged under the module's name.
4. **`README.md`** gains an install section (`Install-PSResource PS_Completers`, then `Import-CompleterSet -Name PS_Completers`), after the publish.

**What does not change.** The set keeps its name and place in the repository (only the staged copy is named `completers.psd1`), so every file that names it stays correct: `README.md` (lines 17, 43, 71), `.github/skills/powershell-completer-implementation/SKILL.md` (lines 21, 132, 187, 198, 217, 248), `.github/skills/powershell-completer-implementation/validation-checklist.md` (lines 41, 168, 176), `tests/Completers.Tests.ps1` (comment line 9, `Describe` title line 46, `$script:SetPath` line 50), `tools/Export-CompleterSetFile.ps1` (lines 5, 22), and the owner's profile line. `.github/workflows/conformance.yml` is unchanged: it installs CompleterActions with `-Prerelease` and never installs PS_Completers, so the manifest's `RequiredModules` has no effect on CI.

**Order:**

| When | Who | What |
| --- | --- | --- |
| Before `2.2.0-preview1` is on PSGallery | — | Nothing changes in PS_Completers. Its CI runs 2.1.0, which has no `-Name` and no `PackageLayout`. |
| After `2.2.0-preview1` is on PSGallery | owner | Steps 1 to 3 on a PS_Completers branch. The CI picks up the preview through `-Prerelease`, so the package gate runs against it; a green branch is part of the soak (section 6). |
| Any time before the publish | owner | Confirm the PSGallery name is free: `Find-PSResource PS_Completers -Repository PSGallery` found nothing on 2026-10-02 (question 11). |
| After `2.2.0` stable is on PSGallery | owner | Merge the branch, stage, and run `Publish-PSResource -Path <staging>/PS_Completers -Repository PSGallery -ApiKey <key>` with the owner's own key. This is an action outside this repository. Then run roadmap exit criterion 2 literally on a clean session (section 8, check 2) and step 4. |
| After the publish | owner | Optionally switch the profile to `Import-CompleterSet -Name PS_Completers` on machines that install the package; the working tree keeps `-Path`. |

## 4. Documentation: author guide, third edition

The about topics are edited in `en-US/` at the repository root (the build copies them into `build/CompleterActions/en-US`, `CompleterActions.build.ps1`). Section placement follows question 6's recommendation.

### `about_Import_Completers` (scaffold workflow)

- **New section `SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT`**, placed before `THE STRICT GRAMMAR`. It must cover:
  - the three ways to seed the table, and when to use each;
  - what the probe will and will not run: console `.exe` only on Windows, and no aliases, functions, scripts, shims, or app execution aliases;
  - the 5-second limit, the working directory, and the two ways a run's output is dropped;
  - the parsing rules in plain words, with `cargo` and `pip` as the "works" examples, `git` as the "does not", and the advice to compare a seeded table with the tool's help, because a partial table passes every check;
  - the residual risks: the PE check cannot see through a console shim that starts a GUI program; some tools treat `--help` as an operand (`tee --help` writes a file named `--help` into the temp directory, and a BSD `yes` prints until the limit); on Linux and macOS a child can open `/dev/tty` although its stdin is closed; a detached descendant can outlive the probe; `-NoProbe` and `-HelpText` avoid all of them;
  - the skeleton, annotated against shapes 1 to 3;
  - the guarantee that the output passes `Test-CompleterScript`, and that the author's edits are then the author's responsibility.
- **`BASIC WORKFLOW`** gains a step 0: "For a new script, start from `New-CompleterScript`." It also gains a step after registration: add the script to the set with `Export-CompleterSet`, then check it with `Test-CompleterSet`.
- **A short `DISTRIBUTING COMPLETERS AS A MODULE` paragraph** points to `about_Completer_Sets`, where the package layout lives.
- **`SEE ALSO`** gains `Get-Help New-CompleterScript -Full`.

### `about_Completer_Sets` (hash, drift, packages)

2.1.0 added `Hash` to the schema list and one paragraph each on the fast path and on `Test-CompleterSet` (milestone 1 spec, section 9, question 7). The third edition adds the full sections:

- **`THE HASH AND THE FAST PATH`**:
  - what is hashed: decoded text, line endings normalised, the `SHA256:` form;
  - that it is a cache key, not a signature;
  - the per-entry decision table from the milestone 1 spec, section 3, in prose;
  - the fast-path records rule for hand-edited entries;
  - why a stale hash is verbose-only;
  - why a wrong hash can never run unchecked code;
  - a reminder to regenerate after every script edit.
- **`CHECKING FOR DRIFT WITH TEST-COMPLETERSET`**:
  - every `Construct`, with its severity and fix, including `PackageLayout` if question 8 is accepted;
  - the severity rule;
  - finding order;
  - the empty-output gate, with the PS_Completers `Describe` as the example;
  - the `-Filter` scan and its no-exclusion consequence;
  - the order for adopting hashes into an existing set (milestone 1 spec, section 6).
- **`COMPLETER SETS AS MODULES`**:
  - the package layout and manifest of section 3, including the one-`.psd1` rule and why `Publish-PSResource` needs it;
  - `New-ModuleManifest` with `-PrivateData @{ CompleterSet = ... }` and `-Tags`;
  - `Import-CompleterSet -Name`, its resolution order, and its two package rules (scripts inside the module, the trusted-entry warning);
  - that installing a completer-set package and importing it by name is a decision to run its scripts, and that a trusted entry runs without the grammar;
  - `Test-CompleterSet -Name`, if question 9 is accepted;
  - staging before `Publish-PSResource`.
- **`WORKFLOW`** gains the one-line profile form `Import-CompleterSet -Name <module>`.
- **`SEE ALSO`** gains `Get-Help New-CompleterScript -Full`.

### Command help and other files

- **`src/docs/CompleterActions/New-CompleterScript.md`**: new, from section 2, with its three examples and the residual-risk paragraph in `NOTES`.
- **`Import-CompleterSet.md`**: the `Name` parameter set, one example, the two package rules, and the trust sentence. The comment-based help in the `.ps1` follows.
- **`Test-CompleterSet.md`**: if question 9 is accepted, the `Name` parameter set and one example; if question 8 is accepted, `PackageLayout` in the list of kinds, and the help paragraph "Path is the set file for every finding" stays true as written. The comment-based help follows.
- **`CompleterActions.md`**, the module page: list `New-CompleterScript`.
- **`README.md`**: the command list and a "scaffold a completer" line.
- **`.github/copilot-instructions.md`**: "ten commands" becomes "eleven commands", with `New-CompleterScript` added to the list, and both "thirteen functions" mentions become "fourteen functions". The file describes the public surface for coding agents, and it would otherwise state the 2.1.0 count.
- **`CHANGELOG.md`**: `## [2.2.0-preview1]` with `### Added` (the command, the `Name` parameter sets, and `PackageLayout`, each as accepted) and `### Documentation`, then `## [2.2.0]` as a promotion note, as 2.1.0 did.

## 5. Performance: no regression

The startup benchmark is not part of this milestone, and no leg is added to `tools/Measure-CompleterStartup.ps1`. Two numbers must hold.

**The 2.1.0 import cost does not regress.** Run the existing tool over the scratch clone, with the 2.1.0 build as the baseline:

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v2.1.0\build\CompleterActions -Iterations 10
```

The baseline is extracted with `git archive v2.1.0 build | tar -x -C <scratch>\v2.1.0`.

- **The gate is the `LazyNoHash` row**: its `RatioToBaseline` must be 1.05 or lower. The tool's `Baseline` leg imports the no-`Hash` copy of the set under the baseline module, its `Lazy` leg imports the hashed set under the module under test, and its `LazyNoHash` leg imports the same no-`Hash` copy under the module under test (`tools/Measure-CompleterStartup.ps1`, the leg list in its help and the `$legs` it builds). So `LazyNoHash` is the only row that compares the same set under 2.2.0 and 2.1.0 in one interleaved run.
- **The `Lazy` row is reported, not gated.** Its `RatioToBaseline` divides hashed 2.2.0 by unhashed 2.1.0, about 0.5 by milestone 1's result, and would stay far under 1.05 whatever 2.2.0 did. For the hashed fast path, a second run with `-ModulePath <scratch>\v2.1.0\build\CompleterActions` gives 2.1.0's `Lazy` median, which is reported beside 2.2.0's for information; it is not a gate, because the two runs are not interleaved.
- A run above 1.05 is repeated up to four runs, as milestone 1 did, and all runs are reported; a median above 1.05 across them is a regression to fix before merging. Under question 1's recommendation 2.2.0 adds no import-time work beyond loading one more function, so the expected ratio is 1.00.

**Spot cost**, ten samples in fresh processes, reported in the pull request: `Import-CompleterSet -Name` takes at most 20 ms longer than `-LiteralPath` to the same file (1.3 to 8.4 ms measured for the lookup).

## 6. Release

Per decision 7, which the roadmap states for 2.1.0 and which the owner's instructions for this milestone carry forward:

- The branch keeps `ModuleVersion = '2.1.0'` until the preview release commit, so checks that need 2.2.0 follow the run rules of section 8.
- The preview release commit stamps `ModuleVersion = '2.2.0'` and `PrivateData.PSData.Prerelease = 'preview1'`. Tag `v2.2.0-preview1` from it, with PSGallery prerelease label `preview1`. It soaks in the owner's profile and in the PS_Completers CI, which installs with `-Prerelease` (PS_Completers' `.github/workflows/conformance.yml`), on the branch described in section 3.
- Stable `v2.2.0` is cut from the same code once the preview has run without a defect; its release commit removes `Prerelease`. A defect means `preview2`.
- Publishing PS_Completers is an owner action outside this repository, after stable (section 3). The roadmap marks milestone 2 shipped only after the literal exit criterion 2 has passed on PSGallery (question 10), which can be later than the 2.2.0 release.

### Roadmap edits the owner would make

This spec edits nothing in `docs/roadmap-3.0.md`. Under the recommendations, the owner would make these edits; each is conditional on the question named.

1. **Exit criterion 1** (question 2): restate it as `New-CompleterScript -CommandName rg -Path .\rg_completer.ps1 -PassThru | Test-CompleterScript   # empty`, because the line as written pipes nothing and passes for any output.
2. **The "Installable completer sets" item** (question 7): replace "the set file at the module root, scripts beside it" with "the set file in a subfolder named by the manifest's `PrivateData.CompleterSet`, scripts beside it, and the manifest the only `.psd1` in the module folder".
3. **The "Author guide, third edition" item** (question 6): the package layout goes to `about_Completer_Sets`, and `about_Import_Completers` points to it.
4. **The "Engine cmdlet detection" item and exit criterion 3** (question 1): record both as deferred to the first 2.x minor after a released engine, preview or stable, carries the merged cmdlets, with appendix A as the accepted contract. Exit criterion 3 cannot be met literally until an engine has the cmdlets. Decision 3 needs no edit under this recommendation; under the alternative, its "Gated on PR #26680 landing in a shipped engine" would need rewording, because the code would ship before the PR lands.
5. **Exit criterion 2** (question 10): note that the literal line is checked by the owner against PSGallery after 2.2.0 stable and the PS_Completers publish, and that the 2.2.0 release rests on the local-repository check.
6. **Milestone 3's exit criterion** (question 3): "10 functions, 0 aliases (8 from 2.0 plus Reset-Completer and Test-CompleterSet)" becomes "11 functions, 0 aliases (8 from 2.0 plus Reset-Completer, Test-CompleterSet, and New-CompleterScript)", and the "Remove the deprecated surface" item's "ten functions" becomes eleven, when 2.2.0 ships.
7. **Milestone 2's introduction**: "The 169 scripts" becomes 173, the count in `ps_completers.psd1` at `2c590c6`. And, when 2.2.0 ships, the status line and the milestone table, as for 2.1.0.

## 7. What stays exactly as in 2.1.0

- The set schema, the hash rule, the fast path, the bulk registration path, and every `Import-CompleterSet -Path`/`-LiteralPath` record, warning, error, and verbose line, including the absence of a trusted-entry warning.
- `Reset-Completer` in full, including its verbose output.
- `Test-CompleterSet` over any set that no manifest declares: the same findings, in the same order, with the same text.
- The strict grammar and its messages, `Import-CompleterScript`, `Test-CompleterScript`, and `Export-CompleterSet`.
- Engine access: every read, removal, and write through the reflection path, and the capability probe and its message.
- `about_CompleterActions_Migration`; it is rewritten for 3.0.

## 8. Acceptance criteria

The commands use these values:

```powershell
$module = 'C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions'
$completers = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers'   # source of the scratch clone only
```

Run rules, carried over from milestone 1 and tightened:

- Every numbered check runs in its own `pwsh -NoProfile` process against `$module` built from the branch, and starts with this preamble:

  ```powershell
  Import-Module -Name "$module\CompleterActions.psd1" -Force
  if ((Get-Module CompleterActions).ModuleBase -ne $module) { throw 'wrong ModuleBase' }
  ```

- Pester runs in its own process, never in a process that also lints.
- PS_Completers is read only through a scratch clone, `git clone $completers <scratch>\PS_Completers`. No check reads or writes `$completers` otherwise, and the real repository is not touched until after release.
- "2.1.0 build" means `build/CompleterActions` extracted from tag v2.1.0 with `git archive`, never the gallery copy.
- **Package isolation.** A check that registers a repository, publishes, or saves does it in a child `pwsh -NoProfile`, under a unique repository name `CaLocal-<8 hex>`, with `Unregister-PSResourceRepository -Name <that name>` in `finally`, and asserts that the store's repository names are the same before and after the child.
  - On Linux and macOS the child's store is redirected with `$env:XDG_DATA_HOME`, pointed at a folder created before the child starts, so `Register-PSResourceRepository` never writes the user's store. Checked 2026-10-02 under WSL: the child wrote `PSResourceGet/PSResourceRepository.xml` into that folder, and with the folder missing `GetFolderPath('LocalApplicationData')` returned an empty string.
  - On Windows the store cannot be redirected: a child started with `$env:LOCALAPPDATA` redirected still reported and used the user's real store, because .NET reads the known folder, not the variable (checked 2026-10-02). So on Windows the register, publish, and save steps run only when `$env:GITHUB_ACTIONS` is `true`, where the runner's store is disposable, and are skipped everywhere else with the reason `the PSResourceGet store cannot be redirected on Windows`. That variable is the only switch; there is no parameter, setting, or other variable that lets the steps run on a developer's Windows machine (question 14). On the owner's machine the by-name import of check 2 runs under WSL instead.
  - Packing needs no repository: `Compress-PSResource -SkipModuleManifestValidate` builds the `.nupkg` on every leg and exercises the one-`.psd1` rule.
  - These cmdlets need PSResourceGet 1.1.0 or later: `Compress-PSResource` is absent from 1.0.x, and PowerShell bundles 1.1.0 from 7.4.10 and 7.5.0 and 1.2.0 from 7.6.0. A check skips with the reason `PSResourceGet 1.1.0 or later is required` where `Compress-PSResource` is missing, and no check matches PSResourceGet's own message text, which differs on the preview leg's 1.3.0 preview.
  - `Publish-PSResource` runs with `-SkipModuleManifestValidate` and `-SkipDependenciesCheck`, because a fixture requiring CompleterActions 2.2.0 fails manifest validation on a machine that has no 2.2.0 installed, and `-SkipDependenciesCheck` does not bypass that. `Save-PSResource` runs with `-SkipDependencyCheck`. The saved module root is prepended to `$env:PSModulePath` in the check's own process only. The module under test is always the branch build imported by the preamble, never one resolved from `RequiredModules`.
- A check that needs a module reporting 2.2.0 before the preview release commit uses a scratch copy of the branch build whose `.psd1` alone is stamped `2.2.0`, as milestone 1 did.
- **Fixture provenance.** Help fixtures under `tests/Fixtures/NewCompleterScript/` are captured in the plan from the real tools, with the tool version and capture command recorded beside each, and each has a checked-in expected-names file produced from that capture and reviewed by hand against the help. The expected-names files are the assertion; the counts in section 2's table are a cross-check, and a difference is resolved in the plan before code.

### Roadmap exit criteria, expanded

1. **The scaffold passes the grammar as written.** The roadmap line pipes without `-PassThru`, so as written it pipes nothing and passes for any output (question 2). This check is the proposed replacement:

   ```powershell
   $file = New-CompleterScript -CommandName rg -Path <scratch>\rg_completer.ps1 -PassThru
   $file | Test-CompleterScript                            # empty
   Test-CompleterScript -LiteralPath $file.FullName        # empty
   Get-Content -LiteralPath $file.FullName -TotalCount 1   # '# rg tab completion for PowerShell'
   ```

   Expected on the owner's machine, with ripgrep 15.2.0, through the Probe set: the file exists, no findings, targets `'rg', 'rg.exe'`, an empty table (rg's help has no commands section), and line 2 is the skeleton line. CI runners may lack `rg`, so the Pester version of this check runs the HelpText set with the checked-in `rg` fixture and expects the same results, including the skeleton line 2, because the table is empty either way. CI therefore exercises a different parameter set than the owner's run, and checks 8 and 9 cover the probe on CI.

2. **A package installs and imports by name.** Under the package isolation rule:
   - A fixture package `CaFixtureSet` is built in the test drive: the manifest at its root, `completers/completers.psd1` written by `Export-CompleterSet`, and three fixture scripts in folders under `completers/`.
   - It is published to a local file repository and saved to `<scratch>\modules`:

     ```powershell
     Register-PSResourceRepository -Name CaLocal-<8 hex> -Uri <scratch>\repo -Trusted
     Publish-PSResource -Path <scratch>\CaFixtureSet -Repository CaLocal-<8 hex> -SkipModuleManifestValidate -SkipDependenciesCheck
     Save-PSResource -Name CaFixtureSet -Repository CaLocal-<8 hex> -Path <scratch>\modules -SkipDependencyCheck
     ```

   Then, in the check's process, with `<scratch>\modules` first on `PSModulePath`:

   ```powershell
   Import-CompleterSet -Name CaFixtureSet | Select-Object Key, RuntimeKey, State, Trusted, ScriptPath | ConvertTo-Csv
   ```

   Expected: exactly the CSV that `Import-CompleterSet -LiteralPath <scratch>\modules\CaFixtureSet\<version>\completers\completers.psd1` gives in a second process, every `ScriptPath` under the installed `ModuleBase`, no warning, and no error. "One line, no path" in the roadmap describes the profile line, which this is.

   No automated check runs the literal roadmap line, `Install-PSResource PS_Completers; Import-CompleterSet -Name PS_Completers`. The owner runs it by hand on a clean session after 2.2.0 stable and the PS_Completers publish (section 3, "Order"). It blocks marking milestone 2 shipped in the roadmap, not the 2.2.0 release (question 10).

3. **Engine cmdlets.** Not met in 2.2.0 under question 1's recommendation, and it cannot be met literally until a released engine has the cmdlets. On every CI leg, `Get-Command Get-ArgumentCompleter, Unregister-ArgumentCompleter -ErrorAction Ignore` returns nothing, and the full suite shows the reflection path unchanged. Before deciding question 1, the owner can re-check the PR with `gh pr view 26680 --repo PowerShell/PowerShell --json state,mergedAt,updatedAt`. If the owner ships detection now, appendix A's checks A1 to A3 replace this one.

### New-CompleterScript

4. **Parser fixtures.** The captures are `cargo`, `docker`, `gh`, `go` (tab-indented), `7z`, `sc`, `bcdedit` (`/?`), `rustup`, `pip`, `kubectl`, `winget`, `git`, `rg`, and `schtasks` (`/?`). Each, run through `-HelpText`, gives exactly the names in its expected-names file, in order. The `cargo` output equals the checked-in golden file `cargo_completer.expected.ps1` after line endings are normalised.
5. **Every output conforms and works.** For every fixture output:
   - `Test-CompleterScript` returns nothing;
   - `Import-CompleterScript` returns one record per target;
   - `Register-Completer -LiteralPath <file> -Lazy -PassThru` derives the same targets.

   After registration, `Test-CompleterRegistration -CommandName cargo -Native -InputText 'cargo b'` returns `build` and `bench`. With `-InputText 'cargo build '` it returns no subcommand. Each fixture's registrations are removed with `Unregister-Completer` before the next, so no run sees another's state.
6. **Quoting and cleaning.** A `-HelpText` fixture whose descriptions contain `'`, `‘`, `’`, `‚`, `‛`, a tab, a NUL, U+202E, U+200B, U+2028, a CSI colour sequence, an OSC 8 hyperlink, a CR progress line, and non-ASCII letters gives a conforming script. Each completion tooltip equals the expected cleaned description character for character: format and separator characters became spaces, the escape sequences are gone, and the letters are kept.
7. **Decoding**, on every leg, through `InModuleScope` on the private decoder with byte arrays, because no CI tool produces these:
   - UTF-16 LE without a byte-order mark, and with `FF FE`, decode to the same text with no leading U+FEFF;
   - UTF-8 with a byte-order mark loses it;
   - the bytes `63 61 66 82` decode on Windows exactly as `[System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)` decodes them, which is `café` under code page 437, so the check holds whatever the runner's locale; and they decode to Latin-1 `caf` plus U+0082 on Linux;
   - an OSC 8 sequence leaves only its link text after cleaning.
8. **Probe mechanics, on every leg.**
   - `New-CompleterScript -CommandName pwsh -Path <scratch>\pwsh_completer.ps1` runs `pwsh --help`: one probe verbose line with exit 0 and a conforming file. `pwsh --help` differs between legs, so only the exit code and conformance are asserted.
   - A fixture script run as `-CommandName pwsh -HelpArgument <scratch>\fake.ps1` (pwsh runs a single path argument as a file) writes chosen bytes: help on stderr only with exit 2 is used; UTF-16 LE bytes are decoded; more than 1 MiB of stdout is cut at 1 MiB and the run still exits normally.
   - With the probe limit lowered to 0.05 s through `InModuleScope`, a fixture that sleeps warns `did not exit within 0.05 seconds`, writes the skeleton line, and leaves no direct child running.
   - A fixture that starts a descendant holding its standard output and then exits returns within 3 s with the warning `exited but left a process holding its output`, and writes the skeleton line. The plan picks the per-OS mechanism; the 2026-10-02 experiments used `cmd /c "start /b ping -n 15 127.0.0.1"` on Windows and `sh -c 'sleep 30 & exit 0'` on Linux. The test stops the descendant itself afterwards.
9. **Probe decisions, on every leg.**
   - The PE reader, on synthetic files written to the test drive: a zero-byte file, a truncated header, and a header with a wrong optional-header magic read as unreadable; a header with `Subsystem` 2 reads as GUI, 3 as console, and 1 as another subsystem. On Windows legs, `pwsh.exe` reads as 3, and a copy of `cmd.exe` written to the test drive with its `Subsystem` field set to 2 reads as 2. The patched copy replaces `calc.exe`, which a runner image need not have.
   - The `/?` rule, with the process runner replaced through `InModuleScope`: on Windows legs, a `--help` result of two lines and no subcommand runs `/?` once and uses its table; five lines runs no `/?`; a timeout, a start failure, and held output each run no `/?`. On Linux legs, `/?` is never run.
   - On Linux legs, an executable `#!/bin/sh` fixture on a scratch `PATH` that prints a `Commands:` section is run and seeds the table; the same file without the execute bit warns `was not run:` with the start exception. On Windows legs, a synthetic `.exe` with a console header that the loader rejects warns `was not run:` the same way.
10. **Probe safety.**
    - On Windows legs, the patched GUI copy of check 9, on a scratch `PATH`, warns `it is a Windows GUI program` and the file is written. A `.cmd` fixture on a scratch `PATH` that would create a marker file warns `which only runs through cmd.exe`, and the marker does not exist.
    - On every leg, a global function and an alias named like the command are never run: the probe resolves only applications.
    - On every leg, with `$ErrorActionPreference = 'Stop'`, `-CommandName zz_nonexistent` warns `was not found as an application`, writes the skeleton, and does not throw.
    - Under `-WhatIf`, a pass-through counter on the probe counts 0, nothing is written, and the `What if:` line names the target path and the program, for example `running '<path>\pwsh.exe --help'`. The call runs in a child `pwsh -NoProfile -File`, because the `What if:` line goes to the host and cannot be captured in the calling process.
11. **Files, errors, and pipeline input.**
    - The output has no BOM, uses CR LF on Windows and LF elsewhere, and ends with a newline. The same input twice gives identical bytes.
    - An existing file without `-Force` fails with `The file '<path>' already exists. Use -Force to overwrite it.` and leaves the file unchanged; `-Force` replaces it. A file created at `<path>` during a probe (through the replaced runner) also fails the call and is left unchanged. No `.tmp` file remains after any of these.
    - A missing directory, a non-`.ps1` path, a directory path, and the names `_`, `foo.`, `-x`, `a b`, `C:\tools\rg`, `_.exe`, and `__.cmd` each fail with their section 2 text, wrapped in `Failed to create completer script.`
    - A `-HelpArgument` that holds CR, LF, or CR LF fails with `Failed to create completer script. -HelpArgument must not contain a line break.`; no process is started and nothing is written.
    - `-PassThru` returns `System.IO.FileInfo`; without it, the command returns nothing.
    - `'Commands:', '  build    Compile' | New-CompleterScript -CommandName fx -Path <scratch>\fx_completer.ps1` gives a table with `build`: the two pipeline lines were joined before parsing.
12. **Self-check.** With the composer replaced through `InModuleScope` to emit a top-level assignment, the command fails with `New-CompleterScript did not produce a conforming script, so nothing was written.` and no file exists.

### Installable completer sets

13. **Resolution rule.** In scratch module roots:
    - the first root wins over a higher version in a later root;
    - the highest version folder wins within a root;
    - a version folder that differs from its manifest's `ModuleVersion` is skipped;
    - a module folder spelled `CaFixtureSet` is found by `-Name cafixtureset` on every leg, including Linux;
    - a missing module, a manifest without `CompleterSet`, a value directly in `ModuleBase`, a value with `..`, a value naming a non-`.psd1`, and a missing set file each fail with the section 3 text;
    - a wildcard name fails;
    - a `RootModule`, a `ScriptsToProcess` script, and a `NestedModules` entry that would each write a marker file never run.

    The roots are joined with `[System.IO.Path]::PathSeparator`, so the Ubuntu legs cover the `:` separator.
14. **Package rules for `-Name`.**
    - An entry whose `Path` is `../../outside_completer.ps1`, resolving outside `ModuleBase`, fails the set with the `is outside the module` problem and registers nothing; with `-SkipInvalid` it is skipped with a warning and the other entries register.
    - A package whose set has two trusted entries writes exactly one warning, `declares 2 trusted completer scripts`; the same set through `-LiteralPath` writes none.
15. **`Test-CompleterSet` package checks** (only for the parts of questions 8 and 9 accepted). The fixture package is copied into the test drive before its set is generated, so the set and its scripts share a drive. On the copy, each single mutation gives exactly the finding listed; reverting it gives none:

    | Mutation | Findings |
    | --- | --- |
    | One entry `Path` made fully qualified | `PackageLayout` (Error) at that `Path` |
    | One script moved to `<ModuleBase>\..\outside_completer.ps1`, set regenerated | `PackageLayout` (Error) at that `Path` |
    | A second `.psd1` added beside the manifest | `PackageLayout` (Error) at line 1 of the set, naming the file |
    | Manifest renamed to the set file's base name (`Completers.psd1` beside `completers/completers.psd1`) | `PackageLayout` (Error) at line 1 of the set, naming the set file and the module |
    | `RequiredModules` emptied | `PackageLayout` (Warning) at line 1 of the set, naming the manifest |
    | Manifest deleted | none of the above; the set is no longer a package set |

    The set-file name row also fires through `-Name` for an installed module `Completers` whose set is `completers/completers.psd1`, and gives nothing for `CaFixtureSet` with the same set, on every leg.

    `Test-CompleterSet -Name CaFixtureSet` returns nothing on an installed copy: a package folder in a scratch module root on every leg, and the copy check 2 saved, where check 2's save step runs. On Windows legs where the repository and `$env:TEMP` are on different drives (the GitHub runner: workspace on D:, temp on C:), a set generated in the test drive for a script in the repository gives exactly one `PackageLayout` Error, for the fully qualified path; the test is skipped with that reason where both are on one drive.
16. **Plain sets are untouched.** Every `tests/CompleterSetDrift.Tests.ps1` test passes unchanged. In the scratch clone, `Test-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1` returns nothing under the branch build, as under 2.1.0.
17. **PS_Completers as a package**, in the scratch clone, after steps 1 to 3 of section 3's "What changes":
    - `Test-CompleterSet -LiteralPath <staging>\PS_Completers\completers\completers.psd1` returns nothing;
    - the clone's Pester run passes with its previous test count plus the package gate;
    - the staged folder, published and saved under the package isolation rule, gives `Import-CompleterSet -Name PS_Completers` with the same number of `Pending` records and the same `Key` list as `Import-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1` (the clone's root copy, not the staged one) in a second process (362 at `2c590c6`; the assertion is equality, not the number).

### Documentation

18. **Help content**, from the build:
    - `about_Completer_Sets` contains the headings `THE HASH AND THE FAST PATH`, `CHECKING FOR DRIFT WITH TEST-COMPLETERSET`, and `COMPLETER SETS AS MODULES`, and the last contains `PrivateData.CompleterSet` and `Import-CompleterSet -Name`;
    - `about_Import_Completers` contains `SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT` before `THE STRICT GRAMMAR`, and `DISTRIBUTING COMPLETERS AS A MODULE`;
    - `(Get-Help New-CompleterScript).Synopsis` is `Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.`, and `Get-Help New-CompleterScript -Examples` has three examples;
    - `Get-Help Import-CompleterSet -Parameter Name` resolves.

### Neutrality, surface, and gates

19. **PSReadLine.** The three existing snapshot tests pass, and a new one asserts an identical `Get-PSReadLineKeyHandler -Bound -Unbound` across `New-CompleterScript` (probe included), `Import-CompleterSet -Name`, and, if question 9 is accepted, `Test-CompleterSet -Name`.
20. **Surface.**
    - `(Get-Module CompleterActions).Version` is `2.2.0`, with `PrivateData.PSData.Prerelease` equal to `preview1` on the preview release commit and absent on the stable release commit. Each is checked on its commit, before its tag.
    - `Get-Command -Module CompleterActions` lists 14 functions and 3 aliases. `tests/CompleterDeprecation.Tests.ps1` asserts 14, and the manifest's `FunctionsToExport` lists `New-CompleterScript`.
    - For each of the 13 functions 2.1.0 exports, the parameter names and parameter sets match the 2.1.0 build's, except that `Import-CompleterSet` gains the set `Name`, and `Test-CompleterSet` gains it if question 9 is accepted.
    - `Get-Command New-CompleterScript -Syntax` shows the three sets of section 2.
21. **Performance.** Section 5's `LazyNoHash` ratio, the reported `Lazy` medians, and the spot cost are in the pull request with the pwsh version, the OS, and the commit.
22. **Suite and lint, in separate processes.**
    - `pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'` passes locally, which is how CI's `shell: pwsh` runs the suite.
    - `Invoke-ScriptAnalyzer` over `./src` and `./tests` with `./PSScriptAnalyzerSettings.psd1` returns nothing.
    - All eight CI legs are green on the pull request.
    - `Get-Help New-CompleterScript -Full` resolves from the build.

## 9. Open questions for the owner

Settled scope is in section 1's non-goals (option seeding, companion `.md`, version selection for `-Name`); the owner can reopen any of them in review. Questions 12 and 13 matter only if question 1 is answered against the recommendation.

1. **Ship engine detection in 2.2.0, or hold it?**
   - Why it is a question: decision 3 gates the item on PR #26680 "landing in a shipped engine". On 2026-10-02 the PR is open and stalled: its author offered to close it, its build fails, and it has no milestone. The surface may change, and iSazonov questioned its shape. Re-check with `gh pr view 26680 --repo PowerShell/PowerShell --json state,mergedAt,updatedAt`.
   - Recommendation: hold. 2.2.0 ships the other three items. Appendix A is the accepted contract, and its code ships in the first 2.x minor after a released engine, preview or stable, carries the merged cmdlets. Exit criterion 3 is recorded as deferred by the owner; it cannot be met literally until an engine has the cmdlets.
   - Alternative: ship the code now. It is invisible on every engine today, but it is written and tested only against a double of an unmerged API, and appendix A lists what then comes back into sections 1, 4, 5, 6, 7, and 8.
2. **Exit criterion 1 is vacuous as written.** `New-CompleterScript` returns nothing without `-PassThru`, following `Export-CompleterSet`, so the roadmap's pipe gives `Test-CompleterScript` no input and passes for any output.
   - Recommendation: restate the criterion with `-PassThru` (section 6, edit 1).
   - Alternative: return the `FileInfo` by default, the `New-Item` convention, and drop `-PassThru`. That breaks the module's own convention.
3. **Milestone 3's surface count.** With `New-CompleterScript`, 3.0 exports 11 functions, not 10.
   - Recommendation: update that exit criterion and the "ten functions" sentence when 2.2.0 ships (section 6, edit 6), as milestone 1 did for the count of 10.
   - Alternative: remove `New-CompleterScript` in 3.0, which no one has asked for.
4. **Adding `.exe` to bare names.**
   - Recommendation: keep it, with the five-suffix exception of section 2: a name ending in `.exe`, `.cmd`, `.bat`, `.ps1`, or `.com` gets no `.exe`, so `npm.cmd` stays one target and `python3.12` gains `python3.12.exe`. 161 of 173 PS_Completers entries list every bare name with its `.exe` form, and the extra target is harmless on Linux.
   - Alternatives: write the names exactly as given and let the author add `.exe`; or skip the `.exe` for any name with `[System.IO.Path]::HasExtension`, the first draft's rule, which also skips `python3.12` and `node.js`.
5. **Probe by default.** The roadmap's criterion 1 calls `New-CompleterScript` without a seeding parameter and its item says the table is seeded "when it can be read safely", which implies probing by default.
   - Recommendation: probe by default with section 2's safety rules, and keep `ConfirmImpact = 'Low'`. `-WhatIf` and `-Confirm` name the program, and the residual risks are documented. `ConfirmImpact = 'Medium'` would not prompt either, because the default `$ConfirmPreference` is `High`, so it would change nothing by default.
   - Alternative: an opt-in `-Probe` switch, so that generating a file never runs a program unless asked. The default set then writes an empty table, `-NoProbe` goes away, and `-HelpText` stays. The safety rules apply under either answer, and the alternative makes the restated exit criterion 1 a check of an unseeded skeleton.
6. **Where the package layout is documented.** The roadmap puts it in `about_Import_Completers`, but it is about sets.
   - Recommendation: the full section goes in `about_Completer_Sets`, and `about_Import_Completers` points to it (section 6, edit 3).
   - Alternative: follow the roadmap's wording; the full `COMPLETER SETS AS MODULES` section then moves into `about_Import_Completers`, and `about_Completer_Sets` gets the pointer.
7. **Where the set file sits in a package.**
   - Recommendation: in one subfolder directly below the module folder, named with the file in `PrivateData.CompleterSet` (`'<folder>/<file>.psd1'`), with the manifest the only `.psd1` in the module folder; folder and file names free, except that the set file's base name must differ from the module name. PS_Completers stages its set as `completers/completers.psd1` (the repository keeps `ps_completers.psd1`; see the set-file name rule of "The package layout") and keeps its manifest at `package/PS_Completers.psd1` in its repository. This changes the roadmap item's wording (section 6, edit 2).
   - Alternative: the roadmap's "set file at the module root". `Publish-PSResource` takes the first `*.psd1` as the manifest, so this fails whenever the set sorts first, and nondeterministically on Linux (section 3).
   - Alternative: the module root with a set name that sorts after the manifest, such as `<ModuleName>.set.psd1`. It publishes on Windows, where the listing came back sorted, but not reliably on Linux, where it did not.
8. **The `PackageLayout` finding kind** (proposed in section 3). Each row is a separate choice.
   - Recommendation: add the kind with all three rows (a fourth, the set-file name row, was added on 2026-10-03; see section 3). The outside-the-module row is an `Error`, because the installed copy lacks the script and `Import-CompleterSet -Name` rejects the entry. The second-`.psd1` row is an `Error`, because it is the only check that catches the publish failure before `Publish-PSResource` does, and on Linux that failure depends on file order. The `RequiredModules` row is a `Warning`.
   - Alternatives: the outside-the-module row as a `Warning`; any row dropped; or no kind at all, with the layout rules documented only (section 4) and the author learning of a problem at publish or install time.
9. **`Test-CompleterSet -Name`** (proposed in section 3).
   - Recommendation: add it. It checks the installed copy, which is where an install-time problem shows, by the same name the profile uses.
   - Alternative: leave it out. `Test-CompleterSet -LiteralPath` to the installed set file does the same work, and, if question 8 is accepted, still finds the manifest one folder up.
10. **What exit criterion 2 means for 2.2.0, and what PS_Completers requires.** A manifest cannot require `2.2.0-preview1`, because `ModuleVersion` takes no prerelease label. On 2026-10-02 a package whose `RequiredModules` named 2.2.0, published to a local repository holding only a `2.2.0-preview1` dependency, failed to install with "version range [2.2.0, ) could not be found", with or without `-Prerelease`. Requiring 2.1.0 would install a version without `-Name`.
    - Recommendation: 2.2.0 is released on the local-repository check (section 8, check 2). PS_Completers requires 2.2.0 and publishes after 2.2.0 stable. The owner runs the literal gallery line by hand then, and it gates marking milestone 2 shipped, not the release (section 6, edit 5).
    - Alternative: publish PS_Completers during the preview with `RequiredModules` 2.1.0, and accept that a clean install lacks `-Name` until stable.
11. **The PSGallery name, who publishes, and when.** `Find-PSResource PS_Completers -Repository PSGallery` found nothing on 2026-10-02. This spec found no way to hold a PSGallery name without publishing under it.
    - Recommendation: the owner publishes `PS_Completers` from the staged folder with the owner's own API key, after 2.2.0 stable (section 3, "Order"), and re-checks the name just before.
    - Alternative: publish a first version earlier to hold the name, which is question 10's alternative and its consequence.
12. **Contingent on question 1: the native fallback on the cmdlet path.**
    - Recommendation: report it as 2.1.0 does, a `Discovered` native record under the engine's key, so the two paths are indistinguishable. In 3.0, consider skipping it on both paths, as parameter-only keys are skipped.
    - Alternative: skip it on the cmdlet path now, which makes the paths differ.
13. **Contingent on question 1: writes through `Register-ArgumentCompleter` when the cmdlets exist.**
    - Recommendation: no, not in 2.x. The roadmap scopes this item to the snapshot and removal, and rollback must restore the exact prior value, which a dictionary write does directly. With writes on the public cmdlet too, the reflection probe could become optional; that belongs to milestone 3's version-gated access.
    - Alternative: route writes through `Register-ArgumentCompleter` as well, which needs a rollback design for values the cmdlet cannot restore.
14. **Package tests on Windows.** The first draft redirected the PSResourceGet store with `$env:LOCALAPPDATA`, which does not work on Windows (section 8, "Package isolation").
    - Recommendation: pack with `Compress-PSResource` on every leg; register, publish, and save only on Linux and macOS (redirected store) and on Windows when `$env:GITHUB_ACTIONS` is `true`, with a unique repository name, unregistration in `finally`, and a before-and-after assertion on the store; skip on every other Windows machine; run check 2 on the owner's machine under WSL. A job killed mid-test can leave a runner-store entry, which dies with the runner. The owner's store is never written.
    - Alternative: allow the transient, uniquely named registration in a developer's real Windows store, unregistered in `finally`. A killed test run then leaves an entry in the user's store.

## Appendix A. Engine cmdlet detection: accepted contract, ships later

This appendix is the accepted contract for the roadmap's third item. Under question 1's recommendation, nothing in it is 2.2.0 behaviour. It ships in the first 2.x minor after a released engine, preview or stable, carries the merged `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter`, after the surface below is confirmed against the merged PR. Any difference is an amendment to this appendix before code. **Roadmap exit criterion 3 cannot be met literally until an engine has the cmdlets**; before then, the checks below can only simulate it on a double.

### If the owner instead ships it in 2.2.0

These come back into the body:

- **Section 1:** the in-scope row "Engine cmdlet detection (`Get-ArgumentCompleter`, `Unregister-ArgumentCompleter`), infra, appendix A"; the observation row "Which engine path is in use: `Get-Completer -Verbose` prints one `Engine completer access:` line"; the first bullet's exception, "except the one verbose line appendix A adds to `Get-Completer` and `Unregister-Completer`"; and the non-goal "No writes through the engine cmdlets" (question 13). The non-goal "No engine cmdlet detection in 2.2.0" goes.
- **Section 4:** `Get-Completer.md` and `Unregister-Completer.md` gain a `NOTES` paragraph on the engine path and its verbose line, and the `CHANGELOG.md` `### Added` list gains engine detection.
- **Section 5:** a second spot cost, detection adds at most 5 ms to `Import-Module` on an engine without the cmdlets (1.5 to 2.7 ms measured), and the expected `LazyNoHash` ratio is restated as "1.00 plus detection".
- **Section 6:** roadmap edit 4 becomes "exit criterion 3 is satisfied on a double only until an engine has the cmdlets", and decision 3's "gated on" sentence needs the owner's rewording.
- **Section 7:** the engine-access bullet becomes "every write through the reflection path, and the capability probe and its message".
- **Section 8:** check 3 is replaced by checks A1 to A3 below, and check 19's snapshot test adds `Get-Completer` and `Unregister-Completer` on the double.

### Upstream state on 2026-10-02

- **PR #26680** ("Add Get-ArgumentCompleter and Unregister-ArgumentCompleter cmdlets") is **open and not merged**. It has one commit, `fc26c434`, from 2026-01-11; no milestone; the label `Review - Needed`; and it was last updated 2026-08-02.
  - Review on 2026-08-01 found a StyleCop failure (SA1518, missing final newline) and a missing update to the default-commands test.
  - iSazonov questioned the command-centric shape in January.
  - The author replied on 2026-08-01 "We can close this", and a reviewer apologised and asked him to continue.
  - The roadmap's "targets 7.7" is not reflected in a milestone.
- **Issue #25800** is open: `WG-Reviewed`, `Up-for-Grabs`, `KeepOpen`, no milestone.
- **No engine has the cmdlets.**
  - This machine has PowerShell 7.6.6 only; there is no `pwsh-preview`.
  - `Get-Command Get-ArgumentCompleter, Unregister-ArgumentCompleter -ErrorAction Ignore` returns nothing in `pwsh -NoProfile`.
  - The newest upstream release is v7.7.0-preview.5 (2026-09-23), which is what the CI `preview` leg installs (`.github/workflows/ci.yml` takes the newest prerelease). It cannot contain unmerged code.

### The surface the module relies on (PR head `fc26c434`)

- `Get-ArgumentCompleter [[-CommandName] <string[]>] [[-ParameterName] <string[]>]` returns the custom (PowerShell) completers. With `-Native` it returns native completers, including the native fallback; the PR returns the fallback only when no `-CommandName` filter is given, and the module never passes one, so it always sees the fallback. Filters are wildcards. Output is `System.Management.Automation.ArgumentCompleterInfo`, with these properties:
  - `CommandName`: `$null` for a parameter-only key and for the fallback;
  - `ParameterName`: `$null` for native completers;
  - `ScriptBlock`: the stored block itself, not a copy;
  - `Type`: an `ArgumentCompleterType` value, `PowerShell`, `Native`, or `NativeFallback`.

  A custom key is split at its first `:`.
- `Unregister-ArgumentCompleter` has three parameter sets: `-CommandName <string[]> -ParameterName <string>` (PowerShellSet), `-CommandName <string[]> [-Native]` (NativeCommandSet, where `-CommandName` alone binds it), and `-NativeFallback`. Names are trimmed. It writes no output and no error when nothing matched.
- Both cmdlets read the same `CustomArgumentCompleters` and `NativeArgumentCompleters` dictionaries the module reaches by reflection today (`src/Private/Get-CompleterRuntime.ps1`).

### Detection

- **Once per import**, in the module's bootstrap (`src/Bootstrap.ps1`), right after the existing capability probe.
- **The engine has the cmdlets when** `$ExecutionContext.SessionState.InvokeCommand.GetCmdlet()` resolves both `Microsoft.PowerShell.Core\Get-ArgumentCompleter` and `Microsoft.PowerShell.Core\Unregister-ArgumentCompleter`, and both `CmdletInfo.ImplementingType` values live in the engine assembly (`[psobject].Assembly`). Module-qualified lookup means a user function, alias, or polyfill module called `Get-ArgumentCompleter` is never mistaken for the engine's cmdlet.
- **The resolved command objects are kept in module state and invoked through them** (`& $info ...`), so a later shadowing definition cannot intercept a call either. The invocation must work for a `CmdletInfo`, which detection stores, and for a `FunctionInfo`, which the test double supplies; check A2 runs both.
- **Cost** is 1.5 to 2.7 ms in a fresh `pwsh -NoProfile` on 7.6.6 when the cmdlets are absent (measured 2026-10-02 for `GetCmdlet` and an assembly type lookup).
- **The import-time capability probe stays** and keeps requiring `EngineIntrinsics._context`, `CustomArgumentCompleters`, and `NativeArgumentCompleters` (`src/Private/Assert-CompleterRuntimeCapability.ps1`), because writes still use them. Its message is unchanged. An engine that had the cmdlets but lost those members would still fail import in 2.x; making that survivable is milestone 3's version-gated access.

### What routes through the cmdlets when they are present

| Operation | Today (2.1.0) | With the cmdlets |
| --- | --- | --- |
| Runtime snapshot for reads (`Get-Completer`, `Test-CompleterRegistration`, `Unregister-Completer`, state resolution) | `Get-CompleterRegistrationSnapshot` reads both dictionaries through `Get-CompleterRuntime` | Two calls, `Get-ArgumentCompleter` and `Get-ArgumentCompleter -Native`; the reflection context is not resolved |
| Runtime snapshot for writers (`Import-CompleterSet`, `Register-Completer`, `Reset-Completer`) | As above | The same two calls for the values; the reflection context is resolved on the call's first write, which these commands always make |
| Runtime lookup by key or full listing (`Get-Completer`, `Test-CompleterRegistration`, `Unregister-Completer`, the lazy stub) | `Find-RuntimeCompleterRegistration` enumerates the dictionaries | The same two calls, filtered by the module with its own case-insensitive key comparison. Engine wildcards are never used for lookup, because a name with `[` would be read as a pattern |
| Runtime removal (`Unregister-Completer`, rollback in `Import-CompleterSet`, `Register-Completer`, and `Reset-Completer`, the lazy stub's failure path) | `Remove-RuntimeCompleterRegistration` removes the dictionary entry | `Unregister-ArgumentCompleter`: `-CommandName <cmd> -ParameterName <param>` for a custom key split at its first `:`, `-CommandName <name> -Native` for a native key, and `-NativeFallback` for the fallback key |
| Runtime write (registration, stub install, rollback restore) | dictionary set through reflection | **Unchanged**: dictionary set through reflection |

So with the cmdlets present, `Get-Completer` and `Test-CompleterRegistration` never touch reflection, which is the roadmap's third exit criterion. `Unregister-Completer` touches it only to restore a value after a failure. `Import-CompleterSet`, `Register-Completer`, and `Reset-Completer` always reach it, because they write.

The snapshot's private shape changes on the cmdlet path. Today `Get-CompleterRegistrationSnapshot` returns a `RuntimeContext` and, per view, a `Dictionary` and `Keys` (`src/Private/Get-CompleterRegistrationSnapshot.ps1`); `Add-CompleterRegistration` writes through `$Snapshot.RuntimeContext` (`src/Private/Add-CompleterRegistration.ps1`), and `Resolve-CompleterRegistrationState` reads values through `Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary` (`src/Private/Resolve-CompleterRegistrationState.ps1`). On the cmdlet path the views are built from the cmdlets' output and `RuntimeContext` is resolved lazily, so those three consumers change with it. The change is private; the public surface stays additive.

### Parity between the paths

Records and errors must be identical on both paths. The cmdlet path uses the engine's output only to rebuild the runtime key and to take the stored script block. From there it builds the record through the same target resolution as today (`src/Private/Resolve-CompleterTarget.ps1`). The rules:

- `Type` is compared by name (`'PowerShell'`, `'Native'`, `'NativeFallback'`), so a test double that emits strings behaves like the real enum.
- `PowerShell` with a `CommandName`: the runtime key is `"<CommandName>:<ParameterName>"`. That is lossless, because the engine split at the first colon. The module then splits that key at its last colon, exactly as it does today, so `a:b:c` gives the same `CommandName` (`a:b`) and `ParameterName` (`c`) on both paths.
- `PowerShell` without a `CommandName`, a parameter-only key, is skipped with today's verbose text, `Skipping the parameter-only completer registration '<ParameterName>': it was registered with Register-ArgumentCompleter -ParameterName without -CommandName, and CompleterActions manages command-parameter and native targets only.` `tests/CompleterActions.Tests.ps1` asserts that line.
- `Native`: the runtime key is `CommandName`.
- `NativeFallback`: the runtime key is `___ps::<native_fallback_key>@@___`. That is the engine's own key, `RegisterArgumentCompleterCommand.FallbackCompleterKey` on 7.6.6, and 2.1.0 already reports it as a `Discovered` native record under that `Key` (checked 2026-10-02 with `Register-ArgumentCompleter -NativeFallback`). The cmdlet path reports it the same way (question 12). Removing it uses `-NativeFallback`.
- **Removal is confirmed.** The value is read before the removal, and that read supplies the removed record and the value used for rollback. After `Unregister-ArgumentCompleter` the key is read back once. A key still present fails the removal with `The engine did not remove the completer registration '<RuntimeKey>'.`, which surfaces through the caller's existing wrapper, for example `Failed to unregister the completer '<RuntimeKey>'. The engine did not remove the completer registration '<RuntimeKey>'.` This matters because the cmdlet is silent when nothing matched, and it trims names.
- An exception from either cmdlet surfaces through the same wrappers as a reflection failure does today. The module never falls back to reflection within a session; the path chosen at import is the path used.

### Verbose line

`Get-Completer` and `Unregister-Completer` write one line per call, first, under `-Verbose`:

```text
VERBOSE: Engine completer access: Get-ArgumentCompleter and Unregister-ArgumentCompleter (PowerShell 7.7.0); runtime writes use the completer tables.
VERBOSE: Engine completer access: the runtime completer tables through reflection (PowerShell 7.6.6 has no Get-ArgumentCompleter).
```

Only those two commands write it, because they are the read and the removal the roadmap names. Other commands keep their 2.1.0 verbose output exactly, which existing tests pin. For example, `tests/CompleterReset.Tests.ps1` asserts `RETURNED=1 verbose` for a `Reset-Completer -Verbose` call, and `tests/CompleterSet.Tests.ps1` filters on the entry and summary lines. `Import-Module -Verbose` cannot carry the line, because a module's own `Write-Verbose` during import is not shown by `Import-Module -Verbose` (checked 2026-10-02).

### When the cmdlets are absent

Nothing changes. Every read, removal, and write runs the 2.1.0 reflection code. The only visible differences are the reflection verbose line above and at most 5 ms more at `Import-Module`. This is the state of every engine on 2026-10-02.

### Test strategy

No CI leg has the cmdlets (7.4, 7.5, 7.6, and 7.7.0-preview.5 on Windows and Ubuntu), so the cmdlet path is tested through a double, and the real cmdlets are tested where they exist:

1. **The double.** A test fixture module defines `Get-ArgumentCompleter` and `Unregister-ArgumentCompleter` with the PR's parameter sets and semantics:
   - it splits keys at the first colon;
   - it reports `NativeFallback`, only when no `-CommandName` filter is given;
   - it trims names, and it is silent when nothing matched;
   - it emits `[pscustomobject]` records with `PSTypeName = 'System.Management.Automation.ArgumentCompleterInfo'` and a string `Type`.

   It reads and removes through the real runtime dictionaries, using reflection inside the test fixture only. Tests swap its `FunctionInfo` objects into the module state that detection fills (`InModuleScope`), and restore the state in `AfterEach`.
2. **Parity.** On the double, a fixture registry holds:
   - a managed native target and a managed parameter target;
   - a parameter-only key, the native fallback, and an `a:b:c` key;
   - a `Stale` record, and a `Failed` record whose live value was replaced outside the module.

   `Get-Completer | Select-Object Key, RuntimeKey, CommandName, ParameterName, State, Source | ConvertTo-Csv` is identical on the double and on reflection, and so is `Test-CompleterRegistration` output. A removal the double leaves in place fails with the `The engine did not remove` text inside the `Failed to unregister` wrapper.
3. **No reflection on reads.** On the double, a pass-through counter on the reflection resolver (`Resolve-CompleterRuntimeExecutionContext`, which every reflection access goes through) counts 0 during `Get-Completer`, `Get-Completer -CommandName ... -Native`, and `Test-CompleterRegistration`. `Unregister-Completer` counts 0 on success, and the double's removal counter counts one per target.
4. **Rollback still restores.** A failure injected after the cmdlet removal restores the value through the reflection write, and `Get-Completer` afterwards matches the state before the call.
5. **Detection.** On every CI leg, without the double, `Get-Completer -Verbose` writes the reflection line, and the full 2.1.0 suite passes unchanged. A global function named `Get-ArgumentCompleter`, defined before import in a fresh process, does not switch the path.
6. **The real engine.** A `Describe` runs tests 2 to 4 against the real cmdlets with `-Skip:(-not $engineHasCmdlets)`, where `$engineHasCmdlets` is computed in `BeforeDiscovery` with the module-qualified lookup above. It is skipped everywhere today. It runs by itself on the `preview` leg the day a preview carries the merged PR.

### Acceptance checks for this appendix

These replace section 8, check 3, in the release that ships this appendix.

- **A1. With the cmdlets, `Get-Completer` does not touch reflection.** Test strategy items 2 and 3, on the double, satisfy the criterion only as a simulation. Item 6 is the literal criterion and runs on the first engine that has the cmdlets.
- **A2. The test strategy passes.** Items 1 to 5 pass on all eight CI legs, invoking the stored command object both as the double's `FunctionInfo` and, through `GetCmdlet`, as the `CmdletInfo` of an existing engine cmdlet; item 6 is reported as skipped with its reason until an engine has the cmdlets.
- **A3. Neutrality and surface.** Section 8, check 19's snapshot covers `Get-Completer` and `Unregister-Completer` on the double, and check 20's parameter comparison is unchanged, because detection adds no parameter.

## Appendix B. Reproducing the counts

Run in `pwsh -NoProfile` with `$root` set to the PS_Completers scratch clone at `2c590c6`.

```powershell
$set = Import-PowerShellDataFile -LiteralPath "$root\ps_completers.psd1"
$set.Entries.Count                                                               # 173
($set.Entries | ForEach-Object { @($_.Targets).Count } | Measure-Object -Sum).Sum   # 362
$set.Entries | Group-Object { @($_.Targets).Count } | Select-Object Name, Count   # 1: 3, 2: 157, 3: 7, 4: 6

# Entries that list every bare name together with its .exe form: 161
@($set.Entries | Where-Object {
    $targets = @($_.Targets | ForEach-Object { $_.CommandName })
    $bare = @($targets | Where-Object { -not [System.IO.Path]::HasExtension($_) })
    $bare.Count -gt 0 -and @($bare | Where-Object { $targets -notcontains "$_.exe" }).Count -eq 0
}).Count

$scripts = Get-ChildItem -LiteralPath $root -Recurse -Filter '*_completer.ps1' -File
@($scripts | Where-Object { (Get-Content -LiteralPath $_.FullName -TotalCount 1) -cmatch '^# \S+ tab completion for PowerShell$' }).Count   # 118
@($scripts | Where-Object { Select-String -LiteralPath $_.FullName -Pattern '^Set-StrictMode -Version 2\.0\s*$' -Quiet }).Count            # 144

# One top-level Register-ArgumentCompleter that names a literal -CommandName list and a literal -ScriptBlock: 100
@($scripts | Where-Object {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
    $calls = @($ast.EndBlock.Statements |
        Where-Object { $_ -is [System.Management.Automation.Language.PipelineAst] -and $_.PipelineElements.Count -eq 1 } |
        ForEach-Object { $_.PipelineElements[0] } |
        Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -eq 'Register-ArgumentCompleter' })
    if ($calls.Count -ne 1) { return $false }
    $elements = $calls[0].CommandElements
    $literalNames = $false; $literalBlock = $false
    for ($i = 1; $i -lt $elements.Count - 1; $i++) {
        if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        $next = $elements[$i + 1]
        if ($elements[$i].ParameterName -eq 'CommandName' -and ($next -is [System.Management.Automation.Language.ArrayLiteralAst] -or $next -is [System.Management.Automation.Language.StringConstantExpressionAst])) { $literalNames = $true }
        if ($elements[$i].ParameterName -eq 'ScriptBlock' -and $next -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $literalBlock = $true }
    }
    $literalNames -and $literalBlock
}).Count

@(Get-ChildItem -LiteralPath $root -Recurse -Filter '*_completer.md' -File | Where-Object { Select-String -LiteralPath $_.FullName -Pattern '^## What it completes' -Quiet }).Count   # 155
```
