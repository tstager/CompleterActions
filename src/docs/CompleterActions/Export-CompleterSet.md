---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: https://github.com/tstager/CompleterActions/blob/main/src/docs/CompleterActions/Export-CompleterSet.md
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

Records arrive through `-InputObject` or the pipeline, typically from
`Get-Completer` or `Import-CompleterScript`. When the command comes after a
pipe or is given `-InputObject`, it exports only the records that arrive that
way, even when none do. A `Get-Completer` filter that matches nothing selects
nothing, whether it is piped to the command or passed to `-InputObject`, and so
do an empty array and `$null`; the command then warns that no registrations
were selected, writes nothing, and leaves an existing file unchanged. Only a
call with no pipe before it and no `-InputObject`, such as the command on its
own or as the first command of a pipeline, exports every managed registration
that records a `ScriptPath`. The command cannot see a pipe in front of a
function or script block that calls it, so a wrapper must pass its input on,
for example as `$input | Export-CompleterSet`; otherwise the inner call has no
pipe before it and exports every managed registration.

Script paths are written relative to the set file when both share a root, with
forward slashes so the file is portable, so a repository can carry its set file
alongside its scripts; paths on another drive stay absolute. The `Trusted` flag of each entry is taken from the records, and
records for the same script must agree on it. A record without a `Trusted`
property is strict.

A strict entry must list every target its script registers, because
`Import-CompleterSet` compares a strict entry's `Targets` with the targets
derived from the parsed script and rejects a mismatch. The command derives
those targets the same way before writing and refuses, naming the missing
targets and leaving the output untouched, when the records for a strict script
cover only some of them, as they do after
`Register-Completer -Lazy -CommandName` selected a subset. A strict
entry's targets are written in the order the script registers them, with the
script's casing. Trusted entries are written with the targets the records
carry, in record order, so a subset of a trusted script's targets exports and
imports as given.

Every entry also records a `Hash` of its script: `SHA256:` followed by the
SHA-256 of the script's text with CR LF and lone CR line endings normalised to
LF, so the same script hashes to the same value on a Windows and a Linux
checkout. The hash is a cache key for the entry's targets, not a signature,
and readers that do not know the key ignore it. A strict script is read once
for both its targets and its hash. When a trusted script cannot be read, its
entry is written without a `Hash`, a warning names the script, and the export
still succeeds.

A set file can be at most 128 KB (131072 bytes), roughly 400 entries of one
target each as this command writes them, with a `Hash`, fewer when their paths
are long or they list several targets, because `Import-CompleterSet` and
`Test-CompleterSet` refuse a larger file. The command measures the set it
would write, under `-WhatIf` too, and refuses a larger one with an error that
names its size and the limit, writing nothing, so an existing file is left
unchanged; export the registrations as several sets instead. The limit also
bounds the time a set takes to parse: a valid set at the limit parses in
milliseconds, and a malformed one, which the command never writes, can take
minutes to refuse, because the parser's time grows with the square of the
syntax errors and a file can hold about one per byte.

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
A null carries no record and is skipped, so `-InputObject $null`, like the
output of a `Get-Completer` filter that matches nothing, selects nothing.
`Trusted`, `IsNative` and `Native` take a Boolean value, a number, where zero
is `False`, or the text `True` or `False` in any letter case, as `Export-Csv`
writes a Boolean, so rows read back with `Import-Csv` export with the tier and
kind they were written with. A null value or empty text counts as `False`,
and any other text is rejected.
`CommandName`, or `RuntimeKey`, names the target exactly. `Key` and
`RegistrationKey` are folded to lowercase, so an object that has only one of
them names the target whose runtime key is that key, apart from letter case,
whether or not it is registered. Such an object is rejected while a
registered target of its kind has the key under a name that the lowercasing
merged into it, such as a name spelled with the Kelvin sign (U+212A) for a
key spelled with the letter k.

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

Registration records from `Get-Completer` or
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

[Get-Completer](Get-Completer.md)
