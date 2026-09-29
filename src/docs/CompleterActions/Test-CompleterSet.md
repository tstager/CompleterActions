---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-CompleterSet
---

# Test-CompleterSet

## SYNOPSIS

Reports drift between a completer set file and the scripts on disk.

## SYNTAX

### Path (Default)

```PowerShell
Test-CompleterSet [-Path] <string[]> [-Filter <string>] [<CommonParameters>]
```

### LiteralPath

```PowerShell
Test-CompleterSet -LiteralPath <string[]> [-Filter <string>] [<CommonParameters>]
```

## DESCRIPTION

Reads a completer set the way `Import-CompleterSet` does, checks every entry in
full against the scripts on disk, and returns one
`CompleterActions.CompleterScriptFinding` record per problem. A set that
matches its folder produces no output, so a gate can assert that the command
returns nothing, the same shape `Test-CompleterScript` uses.

The set is read with `Import-PowerShellDataFile`, which evaluates data only,
and the set file is also parsed, never evaluated, to point each finding at a
line and column of the set. Every strict entry is parsed once, whether or not
its `Hash` matches, because the command verifies rather than takes the fast
path. A trusted entry is never parsed, as at import, so it can report only
`MissingScript`, `InvalidEntry`, `DuplicateTarget`, and the three `Hash` kinds.
No script is executed, and the session's registrations are neither read nor
changed, so a conflict with what the session has registered is not drift.

`Construct` names the kind of drift, and `Severity` is `Error` when
`Import-CompleterSet` without `-SkipInvalid` would reject the set because of
it, or `Warning` when the set still imports but is stale or slower:

- `MissingScript` (`Error`): `Path` does not resolve to an existing file.
- `InvalidEntry` (`Error`): any other problem `Import-CompleterSet` reports for
  the entry itself, with its text word for word.
- `UnreadableTargets` (`Error`): a strict script does not parse or does not
  name its targets with literal arguments.
- `TargetMismatch` (`Error`): a strict entry's `Targets` differ from the
  targets its script registers.
- `DuplicateTarget` (`Error`): an earlier entry already lists the target, under
  import's rule that only an entry with no `Error` claims its targets.
- `HashMismatch` (`Warning`): the script changed since the `Hash` was written.
- `MissingHash` (`Warning`): the entry has no `Hash`.
- `InvalidHash` (`Warning`): the `Hash` is not `SHA256:` and 64 hexadecimal
  digits.
- `UnlistedScript` (`Warning`): a file under the set's directory matches
  `-Filter` and no entry lists it.

Findings come in set order, each entry's in the order above, and the
`UnlistedScript` findings follow, sorted by path. `Path` is the set file for
every finding, because the fix is always made in the set, usually by
regenerating it with `Export-CompleterSet`.

Every `-Path` or `-LiteralPath` value is resolved before any set is tested.
The sets are then tested in the order given, and each set's findings are
written before the next set is read. A set that cannot be read, such as one
without `Version = 1`, stops the call with a terminating error after the
findings of the earlier sets. A folder under a set's directory that cannot be
read also stops the call with a terminating error, after that set's entry
findings, because the scan for unlisted scripts would be incomplete.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Test-CompleterSet -Path ~\Completers\completers.psd1
```

Reports every entry that no longer matches its script and every completer
script the set does not list, or nothing when the set is current.

### EXAMPLE 2

```PowerShell
Test-CompleterSet -LiteralPath .\completers.psd1 | Where-Object Severity -eq Error
```

Lists only the drift that would make `Import-CompleterSet` reject the set.

## PARAMETERS

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

A set file path, or `Get-ChildItem` output bound through `FullName`.

## OUTPUTS

### CompleterActions.CompleterScriptFinding

Returns `CompleterActions.CompleterScriptFinding` records with `Path`, `Line`,
`Column`, `Severity`, `Construct`, `Message`, and `Hint` properties, or nothing
when the set matches its folder.

## NOTES

The set file schema and its `Hash` key are described in `about_Completer_Sets`.
The command never registers a completer, never hooks PSReadLine key handlers,
replaces `TabExpansion2`, or changes PSReadLine options.

## RELATED LINKS

[Import-CompleterSet](Import-CompleterSet.md)

[Export-CompleterSet](Export-CompleterSet.md)

[Test-CompleterScript](Test-CompleterScript.md)
