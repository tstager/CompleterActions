---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/11/2026
PlatyPS schema version: 2024-05-01
title: Import-CompleterSet
---

# Import-CompleterSet

## SYNOPSIS

Validates a completer set file and registers every script it lists.

## SYNTAX

### Path (Default)

```PowerShell
Import-CompleterSet [-Path] <string[]> [-SkipInvalid] [-Force] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### LiteralPath

```PowerShell
Import-CompleterSet -LiteralPath <string[]> [-SkipInvalid] [-Force] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### Name

```PowerShell
Import-CompleterSet -Name <string[]> [-SkipInvalid] [-Force] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION

Reads a completer set, a `.psd1` data file written by `Export-CompleterSet` or
by hand, validates every entry up front, and then registers each valid entry's
targets as managed registrations. The set is read with
`Import-PowerShellDataFile`, which evaluates data only, and validation never
executes a completer script.

Every entry is checked before anything is registered: the script file must
exist and be a `.ps1`, `Trusted` entries must declare their `Targets` because
the script is not parsed, strict entries must name their targets with literal
`Register-ArgumentCompleter` arguments so the targets can be derived from the
parsed script and compared against any `Targets` the entry declares, no target
may be listed by two entries of the set, and without `-Force` no target may
already carry a managed or runtime registration for a different completer. An
entry that repeats a registration the session already has is reused.
Validating a strict entry parses its script once and runs the strict import
grammar on that parse, and registration reuses the targets that validation
derived, so a set import parses and walks each strict script once, unless its
`Hash` matches, in which case the grammar first runs when the script loads. A
script that fails the grammar is an invalid entry whose message names the
first finding; run `Test-CompleterScript` over the repository to see every
finding ahead of time. When one or more entries are invalid the command
throws a single error that lists every problem and registers nothing. With
`-SkipInvalid` each problem is written as a warning instead and the valid
entries register.

A strict entry that declares `Targets` and carries a `Hash`, as
`Export-CompleterSet` writes it, is not parsed when the `Hash` matches the
script's text: its declared `Targets` are registered as they are, and the
parse errors, the literal-argument check, and the comparison with the
script's targets are skipped because the export ran them against the same
text. Every other check still runs. An absent, unrecognised, or different
`Hash`, or a script that cannot be read for it, falls back to the parse, and a
stale `Hash` is not a warning. A hand-edited entry whose `Hash` still matches
registers its targets in the order and with the casing it declares, keeping
the first occurrence of a repeated key, where the parse would use the
script's order and casing. A trusted entry's `Hash` is ignored. With
`-Verbose` the command writes one line per valid entry saying how its targets
were read, and one summary line per set.

Relative `Path` values resolve against the directory of the set file, so a
completer repository can carry its set file next to its scripts.

Registering a set does not run its scripts. Every valid entry is registered
lazily under the entry's trust tier, exactly as `Register-Completer
-Lazy` registers a script, so each target gets a stub and a managed record in
state `Pending`. The whole set is one transaction against one snapshot of the
session's registrations: validation and registration read the managed table
and the runtime dictionaries once, and if any runtime or managed write fails,
every change the set made is rolled back and nothing from it stays registered.
The first tab press for a target loads the script and moves the record to
`Active`; a script that fails to load moves to `Failed` with the message in
`LoadError`, and the completion engine's default completion applies as if no
completer were registered. `-Force` replaces existing registrations for the
set's targets and retries `Failed` ones; `Reset-Completer` retries them without
re-importing the set.

With `-Name` the set comes from an installed completer set package: a module
whose manifest names its set file in `PrivateData.CompleterSet`, as
`'<folder>/<file>.psd1'` in a folder directly below the module folder, which
holds the manifest as its only `.psd1`. The module is found the way
`Import-Module` finds it, without loading it: the first `$env:PSModulePath` root
that has the module wins, and within it the highest version, which is used
even when its set is broken. The manifest is read as data, so the package's
`RootModule`, `ScriptsToProcess`, `NestedModules`, and `RequiredModules` never
load or run. Every name is resolved before any set is imported, and the set is
then imported as `-LiteralPath` imports it, with two rules for packages. An
entry whose script resolves outside the module folder is an invalid entry. A
set with trusted entries writes one warning per name that counts them.
Installing a completer set package and importing it by name is a decision to
run its scripts: each one runs at its first tab, under its entry's trust tier.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Import-CompleterSet -Path ~\Completers\completers.psd1
```

Registers every completer script listed in the set. This is the one line a
profile needs for a whole completer repository.

### EXAMPLE 2

```PowerShell
Import-CompleterSet -Path ~\Completers\completers.psd1 -SkipInvalid -Force
```

Registers the valid entries, warns about the rest, and replaces any existing
registration for the same targets.

### EXAMPLE 3

```PowerShell
Import-CompleterSet -Path ~\Completers\completers.psd1 -WhatIf
```

Runs the full validation and reports what would be registered without changing
the session.

### EXAMPLE 4

```PowerShell
Import-CompleterSet -Name PS_Completers
```

Registers every completer script in the set of the installed `PS_Completers`
package. After `Install-PSResource PS_Completers` this is the one line a profile
needs, with no path.

## PARAMETERS

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

Replaces existing managed or runtime registrations for the targets in the set,
including `Failed` lazy records whose load should be retried; `Reset-Completer`
retries them without re-importing the set.

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

### -LiteralPath

The literal path to a completer set file. Wildcards are not expanded.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- PSPath
ParameterSets:
- Name: LiteralPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

The names of installed completer set modules. Each name is taken literally: a
name containing `*`, `?`, `[`, or `]` fails the call before any name is
resolved. The parameter takes no pipeline input.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Name
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

The path to a completer set file. Wildcards are supported.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases:
- FullName
ParameterSets:
- Name: Path
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipInvalid

Writes each invalid entry as a warning and registers the valid entries instead
of failing the whole set.

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

A set file path, or `Get-ChildItem` output bound through `FullName`.

## OUTPUTS

### CompleterActions.CompleterRegistration

Returns the `CompleterActions.CompleterRegistration` records that were created
or reused for the set's targets, in state `Pending` until each script loads.

## NOTES

The set file schema, the per-entry trust tier, and the `Pending` and `Failed`
lifecycle of lazily loaded completers are described in `about_Completer_Sets`.
The command never hooks PSReadLine key handlers, replaces `TabExpansion2`, or
changes PSReadLine options.

## RELATED LINKS

[Export-CompleterSet](Export-CompleterSet.md)

[Register-Completer](Register-Completer.md)

[Test-CompleterScript](Test-CompleterScript.md)

[Get-Completer](Get-Completer.md)
