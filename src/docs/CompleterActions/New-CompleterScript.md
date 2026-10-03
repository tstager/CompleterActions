---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: New-CompleterScript
---

# New-CompleterScript

## SYNOPSIS

Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.

## SYNTAX

### Probe (Default)

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> [-HelpArgument <string>]
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### HelpText

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -HelpText <string[]>
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### NoProbe

```PowerShell
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -NoProbe
 [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Writes a native completer script for one or more command names: a guarded,
literal-only table of subcommands, a `Complete-<Stem>` function that offers
them in the first argument position, and one bare
`Register-ArgumentCompleter` call that names every target. The file passes
`Test-CompleterScript` and imports with `Import-CompleterScript` and
`Register-Completer -Lazy` before the author edits it.

The first `-CommandName` value is the primary name: it names the functions and
the state variable, and it is the one probed. Every name must be a bare command
name: at least one letter or digit, no path separators, spaces, quotes, or
wildcard characters, no leading `-` or `.`, and no trailing `.` or `-`. A name
must also keep a letter or digit outside a trailing `.exe`, `.cmd`, `.bat`,
`.ps1`, or `.com`, because the function names are derived from what is left:
`_.exe` is refused and `_a` gives `Complete-A`. The target list follows the
`-CommandName` order, and a name that does not end in `.exe`, `.cmd`, `.bat`,
`.ps1`, or `.com` is followed by the same name with `.exe` appended, so
`-CommandName rg` registers `'rg', 'rg.exe'` and `-CommandName npm.cmd`
registers `'npm.cmd'` alone. Names are de-duplicated case-insensitively,
keeping the first spelling.

The subcommand table is seeded in one of three ways:

- **Probe** (the default) runs the primary name's help and parses its commands
  section. With `-HelpArgument` the program runs once with that argument.
  Without it the probe passes `--help`; on Windows, when `--help` ran to
  completion, gave no subcommand, and printed fewer than five non-blank lines,
  which is what a tool that rejects `--help` prints, `/?` runs once and its
  result is used. On Linux and macOS `/?` is never tried.
- **HelpText** parses help text the author already captured, for a command the
  probe will not run. Lines are accumulated across pipeline input, joined, and
  parsed; nothing is run.
- **NoProbe** runs nothing and writes an empty table.

The probe runs only an application that `Get-Command` resolves, so a function,
alias, cmdlet, or script of that name is never run. On Windows it runs only a
`.exe` whose PE header marks a console program: a GUI program, a `.cmd` or
`.bat` shim, and an app execution alias are not run, and a warning says why
and suggests `-HelpText`. The program runs with the one argument, no shell,
standard input closed, the temporary directory as its working directory, and
`NO_COLOR=1` added to the environment. One 5-second limit covers the run. A
program that has not exited by then is stopped, and a program that exits but
leaves a process holding its output is not waited for; in both cases its
output is not used and a warning says so. The exit code decides nothing: the
text used is standard output, or standard error when standard output is
empty. It is decoded (UTF-16 LE, UTF-8, or the OEM code page on Windows and
Latin-1 elsewhere), and terminal escape sequences, backspace overstrikes, and
carriage-return progress lines are removed, for probe output and `-HelpText`
alike.

The parser looks for a section header such as `Commands:`, `CORE COMMANDS`, or
`<Commands>`, then reads one entry per line: a name, a separator (a colon,
two or more dashes, ` - `, two or more spaces, or a tab), and a description.
Names are kept in help order without duplicates. Control, format, and line
separator characters in a description become spaces, and an empty description
becomes the name. Help without a commands section gives an empty table, which
is not an error and not a warning.

Before anything is resolved, probed, or written, every `-CommandName` value,
`-HelpArgument`, and the `-Path` are checked: `-HelpArgument` must not contain
a line break, the path must end in `.ps1`, must not be a
directory, and its folder must exist, and the file must not exist unless
`-Force` is given. `-WhatIf` and `-Confirm` name the file and the program the
probe would run, and the probe runs only after the call is confirmed.

The script is written to a temporary file beside the target, checked with the
strict grammar `Test-CompleterScript` applies, and its targets are derived as
`Register-Completer -Lazy` derives them. Only a file that conforms and
registers exactly the target list is moved into place; otherwise the command
fails with a message that asks for a defect report, and nothing is written.
The file is UTF-8 without a byte-order mark, with the platform newline and a
final newline, and it holds no date, version, or machine path, so the same
input always gives the same bytes.

Every failure is a terminating error that begins
`Failed to create completer script.`, and a failed call leaves nothing at the
path.

## EXAMPLES

### EXAMPLE 1

```PowerShell
New-CompleterScript -CommandName cargo -Path .\cargo_completer\cargo_completer.ps1 -PassThru | Test-CompleterScript
```

Writes the cargo skeleton seeded from `cargo --help` and checks it; the
pipeline is empty.

### EXAMPLE 2

```PowerShell
winget --help | New-CompleterScript -CommandName winget -Path .\winget_completer\winget_completer.ps1
```

Seeds the table from help the author ran, for a command the probe will not
run.

### EXAMPLE 3

```PowerShell
New-CompleterScript -CommandName mytool -Path .\mytool_completer.ps1 -NoProbe -Force
```

Writes an empty skeleton without running anything, replacing an existing file.

## PARAMETERS

### -CommandName

The native command names. The first is the primary name: it names the
functions and state, and it is the one probed.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Overwrites an existing file.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HelpArgument

The one argument the probe passes. When omitted the probe passes `--help` and,
on Windows, may fall back to `/?`. It must not contain a line break, because
line 2 of the script names it in a comment.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Probe
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HelpText

Help text the author already captured. Lines are accumulated across pipeline
input, joined with LF, cleaned, and parsed; nothing is run.
`winget --help | New-CompleterScript winget .\winget_completer.ps1` binds here.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: HelpText
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoProbe

Runs nothing and writes an empty subcommand table.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoProbe
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Returns the written file as `System.IO.FileInfo`, so it pipes into
`Test-CompleterScript` and `Import-CompleterScript`. Without `-PassThru` the
command returns nothing.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

The `.ps1` file to write. A relative path is resolved against the current
location. The parent directory must exist.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

Help text lines, bound to `-HelpText`.

## OUTPUTS

### System.IO.FileInfo

When `-PassThru` is used, returns the written script file.

## NOTES

The probe runs a third-party program, and some risks remain. The PE check
cannot see through a console shim that starts a GUI program. Some tools treat
`--help` as an operand: `tee --help` writes a file named `--help` into the
temporary directory, and a BSD `yes` prints until the limit. On Linux and
macOS a child can open `/dev/tty` although its standard input is closed. A
descendant whose parent has exited is no longer in the process tree the probe
stops, so it can outlive the probe. `-NoProbe` and `-HelpText` avoid all of
them.

A partial table passes `Test-CompleterScript`, so compare a seeded table with
the tool's help before relying on it. The generated script is a start: once
the author edits it, keeping it conforming is the author's responsibility, and
`Test-CompleterScript` checks it again. The strict grammar is described in
`about_Import_Completers`.

## RELATED LINKS

[Test-CompleterScript](Test-CompleterScript.md)

[Import-CompleterScript](Import-CompleterScript.md)

[Register-Completer](Register-Completer.md)

[Export-CompleterSet](Export-CompleterSet.md)
