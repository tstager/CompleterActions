---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: https://github.com/tstager/CompleterActions/blob/main/src/docs/CompleterActions/Update-CompleterSet.md
Locale: en-US
Module Name: CompleterActions
ms.date: 11/25/2026
PlatyPS schema version: 2024-05-01
title: Update-CompleterSet
---

# Update-CompleterSet

## SYNOPSIS

Rewrites the Hash of each completer set entry whose script has changed, leaving the rest of the set file as it is.

## SYNTAX

### Path (Default)

```PowerShell
Update-CompleterSet [-Path] <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### LiteralPath

```PowerShell
Update-CompleterSet -LiteralPath <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### InputObject

```PowerShell
Update-CompleterSet -InputObject <CompleterScriptFinding[]> [-Filter <string>] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Reads each completer set once, verifies every entry the way
`Test-CompleterSet` does, and replaces the `Hash` value of each entry whose
script has changed since the set was written, or whose `Hash` is not
`SHA256:` followed by 64 hexadecimal digits, with the script's current hash,
written as `Export-CompleterSet` writes it: a single-quoted `SHA256:` followed
by 64 upper-case hexadecimal digits. Nothing else in the file changes. An
entry whose `Hash` equals its script's, ignoring letter case, is not touched.
The command never adds an entry or a `Hash`; regenerate the set with
`Export-CompleterSet` for that.

An entry is updated only when it has a `Hash` value, its script can be read,
and `Test-CompleterSet` reports no `Error` for it: no `MissingScript`,
`InvalidEntry`, `UnreadableTargets`, `TargetMismatch`, or `DuplicateTarget`. A
matching `Hash` makes `Import-CompleterSet` take a strict entry's `Targets`
without comparing them with the script, so rehashing an entry whose targets
also changed would make the import register stale targets unchecked. Such an
entry is left as it is, with a warning that names its first `Error`, whether
or not its `Hash` differs, and the set needs `Export-CompleterSet`. An entry
that is not trusted and whose script no longer passes the strict grammar is
left as it is too, with a warning that names the first grammar `Error` as
`Test-CompleterScript` words it, because a matching `Hash` would let the
import skip the grammar and move the failure to the first tab. A trusted
entry is updated, with a warning, because its script is never parsed, so its
`Targets` cannot be checked; import ignores a trusted entry's `Hash`, which
only feeds `Test-CompleterSet`. One warning per set counts the entries without
a `Hash`, and one warning names each script under the set's folder that
matches `-Filter` and that no entry lists.

The file is read once as bytes and decoded as `Import-CompleterSet` decodes
it, as UTF-8 unless a byte-order mark names another encoding. Each new value
is spliced into the text where the old value was parsed, last entry first, so
no line outside a replaced value is split or joined: a file with LF line
endings keeps them, and a `Hash` that shares its line with other keys keeps
them. A double-quoted or here-string `Hash` becomes the single-quoted form, on
one line. The result is encoded with the same encoding and byte-order mark and
written through a temporary file beside the set and a replacing move, so a
reader sees the old set or the new one. A set reached through a symbolic link
is written at the link's final target, and the link is kept. Nothing is
written when the set's text does not give back its bytes in its encoding, such as a set with an invalid
UTF-8 byte, when the new text does not read back as the same entries, paths,
and targets, or when it would be larger than the 128 KB (131072-byte) limit
that `Import-CompleterSet` reads. A set with nothing to update is not written,
and its timestamp does not change.

Every set is resolved as it arrives and updated once, in the end block, so a
piped `Test-CompleterSet` has finished reading before anything is written, and
a set named by many findings is still read and written once. A set that
cannot be read stops the call with a terminating error after the sets before
it were updated. With `-WhatIf` nothing is written, and the warnings are still
written.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Update-CompleterSet -Path ~\Completers\completers.psd1
```

Rewrites the `Hash` of every entry whose script changed since the set was
written, and warns about each entry it leaves for `Export-CompleterSet`.

### EXAMPLE 2

```PowerShell
Test-CompleterSet -Path ~\Completers\completers.psd1 | Update-CompleterSet
```

Updates the set the drift report names, once, after the report has read it.

### EXAMPLE 3

```PowerShell
Update-CompleterSet -Path ~\Completers\completers.psd1 -WhatIf
```

Reports how many `Hash` values would be rewritten, and writes the same
warnings, without changing the file.

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

### -Filter

The file-name pattern of the scan for scripts that no entry lists. The scan is
recursive under the set file's directory. The default is `*_completer.ps1`.

```yaml
Type: System.String
DefaultValue: '*_completer.ps1'
SupportsWildcards: true
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

### -InputObject

The `CompleterActions.CompleterScriptFinding` records `Test-CompleterSet`
returns, from the pipeline or by name. Only each finding's `Path`, the set
file, is used, taken literally, and each set is updated once however many
findings name it. A finding names the set to update, not the entries: every
entry of that set is verified again. Given positionally, a finding binds to
`-Path` as text.

```yaml
Type: CompleterActions.CompleterScriptFinding[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: InputObject
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
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

### -PassThru

Returns the `System.IO.FileInfo` of each set that was written.

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

### CompleterActions.CompleterScriptFinding[]

The findings `Test-CompleterSet` writes, each naming its set file in `Path`.

## OUTPUTS

### System.IO.FileInfo

With `-PassThru`, returns each set file that was written; otherwise the
command returns nothing.

## NOTES

The set file schema and its `Hash` key are described in `about_Completer_Sets`.
The command never registers a completer, never hooks PSReadLine key handlers,
replaces `TabExpansion2`, or changes PSReadLine options.

## RELATED LINKS

[Test-CompleterSet](Test-CompleterSet.md)

[Export-CompleterSet](Export-CompleterSet.md)

[Import-CompleterSet](Import-CompleterSet.md)
