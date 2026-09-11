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

## DESCRIPTION

Reads a completer set, a `.psd1` data file written by `Export-CompleterSet` or
by hand, validates every entry up front, and then registers each valid entry's
targets as managed registrations. The set is read with
`Import-PowerShellDataFile`, which evaluates data only, and validation never
executes a completer script.

Every entry is checked before anything is registered: the script file must
exist and be a `.ps1`, `Trusted` entries must declare their `Targets` because
the script is not parsed, and strict entries must pass the strict import
grammar, with their targets derived from the script and compared against any
`Targets` the entry declares. When one or more entries are invalid the command
throws a single error that lists every problem and registers nothing. With
`-SkipInvalid` each problem is written as a warning instead and the valid
entries register.

Relative `Path` values resolve against the directory of the set file, so a
completer repository can carry its set file next to its scripts.

Registering a set does not run its scripts. Every valid entry is registered
through `Register-CompleterRegistration -Lazy` under the entry's trust tier, so
each target gets a stub and a managed record in state `Pending`. The first tab
press for a target loads the script and moves the record to `Active`; a script
that fails to load moves to `Failed` with the message in `LoadError`, and the
completion engine's default completion applies as if no completer were
registered. `-Force` replaces existing registrations for the set's targets and
retries `Failed` ones.

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
including `Failed` lazy records whose load should be retried.

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

### System.Management.Automation.PSCustomObject

Returns the `CompleterActions.CompleterRegistration` records that were created
or reused for the set's targets, in state `Pending` until each script loads.

## NOTES

The set file schema, the per-entry trust tier, and the `Pending` and `Failed`
lifecycle of lazily loaded completers are described in `about_Completer_Sets`.
The command never hooks PSReadLine key handlers, replaces `TabExpansion2`, or
changes PSReadLine options.

## RELATED LINKS

[Export-CompleterSet](Export-CompleterSet.md)

[Register-CompleterRegistration](Register-CompleterRegistration.md)

[Test-CompleterScript](Test-CompleterScript.md)

[Get-CompleterRegistration](Get-CompleterRegistration.md)
