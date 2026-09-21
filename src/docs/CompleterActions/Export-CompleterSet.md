---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/11/2026
PlatyPS schema version: 2024-05-01
title: Export-CompleterSet
---

# Export-CompleterSet

## SYNOPSIS

Writes a completer set file from registrations that came from scripts.

## SYNTAX

### __AllParameterSets

```PowerShell
Export-CompleterSet [-Path] <string> [-InputObject <psobject[]>] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION

Groups registration records by the completer script they came from and writes
a completer set: a `.psd1` data file that lists each script once with its
trust tier and the targets it registers. `Import-CompleterSet` reads the file
back and registers everything in it, so a profile that imports a completer
repository becomes one `Import-CompleterSet` call.

Records arrive through `-InputObject`, typically from
`Get-CompleterRegistration` or `Import-CompleterScript`. Without `-InputObject`
the command exports every managed registration that records a `ScriptPath`.
Script paths are written relative to the set file when both share a root, with
forward slashes so the file is portable, so a repository can carry its set file
alongside its scripts; paths on another drive stay absolute. The `Trusted` flag of each entry is taken from the records, and
records for the same script must agree on it.

A strict entry must list every target its script registers, because
`Import-CompleterSet` compares a strict entry's `Targets` with the targets
derived from the parsed script and rejects a mismatch. The command derives
those targets the same way before writing and refuses, naming the missing
targets and leaving the output untouched, when the records for a strict script
cover only some of them, as they do after
`Register-CompleterRegistration -Lazy -CommandName` selected a subset. Trusted
entries are written with the targets the records carry, so a subset of a
trusted script's targets exports and imports as given.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Export-CompleterSet -Path ~\Completers\completers.psd1
```

Writes every managed registration that came from a script into a set file next
to the scripts.

### EXAMPLE 2

```PowerShell
Get-ChildItem ~\Completers -Recurse -Filter *_completer.ps1 |
    Import-CompleterScript |
    Export-CompleterSet -Path ~\Completers\completers.psd1
```

Builds a set from a completer repository without registering anything in the
current session.

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

### -InputObject

Registration records to export. Each record must describe a target and expose
the script it came from through a `ScriptPath` or `SourcePath` property.
Records without a script path cannot be expressed in a set and are rejected.

```yaml
Type: System.Object[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Returns the written file.

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

The path of the `.psd1` file to write. The parent directory must exist.

```yaml
Type: System.String
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

### System.Object[]

Registration records from `Get-CompleterRegistration` or
`Import-CompleterScript`, or any object that describes a target and exposes a
`ScriptPath` or `SourcePath`.

## OUTPUTS

### System.IO.FileInfo

When `-PassThru` is used, returns the written set file.

## NOTES

The set file schema and the per-entry trust tier are described in
`about_Completer_Sets`.

## RELATED LINKS

[Import-CompleterSet](Import-CompleterSet.md)

[Import-CompleterScript](Import-CompleterScript.md)

[Get-CompleterRegistration](Get-CompleterRegistration.md)
