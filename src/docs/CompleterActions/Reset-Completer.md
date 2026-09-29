---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Reset-Completer
---

# Reset-Completer

## SYNOPSIS

Returns a Failed or Active script-backed completer to Pending, so its script loads again on the next tab press.

## SYNTAX

### CommandParameter (Default)

```PowerShell
Reset-Completer -CommandName <string[]> -ParameterName <string[]> [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### InputObject

```PowerShell
Reset-Completer -InputObject <Object[]> [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Native

```PowerShell
Reset-Completer -CommandName <string[]> -Native [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Re-arms a script-backed managed registration without re-importing the set it
came from. A script-backed registration is any managed record with a
`ScriptPath`: a lazy registration from `Import-CompleterSet` or
`Register-Completer -Lazy`, or an eager one from
`Import-CompleterScript | Register-Completer`. The targets are named by native
command, command parameter target, or pipeline `InputObject` values, and each
target is decided once per call; a key seen earlier in the same call is
skipped.

Each target is decided from the managed record and the live runtime value,
and the first of these rules that applies decides it:

- No managed record: an error. A live value the module does not manage
  (`Discovered`, `Conflicted`) cannot be reset, and a target with nothing
  registered is reported as not found.
- `Pending`: nothing changes and no confirmation is asked. `-Verbose` says it
  is already pending, and `-PassThru` returns the current record.
- `Stale`, or `Failed` with a live value created outside the module: an error.
  Use `Register-Completer -Force` to register it again, or
  `Unregister-Completer -AllowUnmanaged` to remove an outside value.
- Registered from a script block, with no `ScriptPath`: an error, because
  there is nothing to reload.
- `ScriptPath` no longer exists: an error. Restore the script, or remove the
  registration with `Unregister-Completer`.
- `Failed`: a new lazy stub is written to the runtime. The record becomes
  `Pending`, with `LoadError` cleared and `ScriptPath` and `Trusted` kept.
- `Active`: the stub replaces the live script block. The record becomes
  `Pending`, and `ImportModule` is cleared.

A `Pending` record whose script was deleted is therefore left alone without an
error; its first tab press reports the missing file.

Errors do not stop the call. Each target that cannot be reset is written as a
non-terminating error, `Failed to reset the completer '<RuntimeKey>'.
<reason>`, and the command goes on with the next target or piped record, so
`Get-Completer -State Failed | Reset-Completer` resets every record it can and
reports each one it cannot. Use `-ErrorAction Stop` to stop at the first
error. Each target is its own transaction: if writing the stub or the record
fails, the previous runtime value and managed record are restored.

After a reset, the next tab press follows the ordinary lazy path: it imports
the script under the record's tier, with the strict grammar for a strict
record, swaps in every `Pending` sibling of the same script and tier, and
moves them to `Active`. A script that still fails moves the pressed target to
`Failed` again with the new `LoadError`. Only the targets named are reset, so
an `Active` sibling keeps its loaded script block until it is reset itself;
pipe every record of a script to reload all of it. The script is not parsed
and its targets are not re-derived.

The command writes only the runtime completer dictionaries and the module's
managed table. It never hooks key handlers, replaces `TabExpansion2`, or
changes PSReadLine options. To remove a registration instead of reloading it,
use `Unregister-Completer`.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Get-Completer -State Failed | Reset-Completer
```

Re-arms every failed script-backed registration after the scripts were fixed.
Afterwards, `Get-Completer -State Failed` lists only the records that were
reported as errors, such as a record whose live runtime value was replaced
outside the module or one whose script was deleted.

### EXAMPLE 2

```PowerShell
Reset-Completer -CommandName git, git.exe -Native -PassThru
```

Reloads the git completer on the next tab press after the script was edited,
and returns the two `Pending` records.

### EXAMPLE 3

```PowerShell
Get-Completer -State Active, Failed | Where-Object ScriptPath -eq $path | Reset-Completer
```

Resets every target of one script.

## PARAMETERS

### -CommandName

Specifies one or more command names whose completers should be reset.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CommandParameter
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
- Name: Native
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
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

### -InputObject

Supplies one or more objects that describe registrations to reset, such as
records from `Get-Completer`, `Register-Completer -PassThru`, or
`Import-CompleterSet`. Input objects expose CommandName with IsNative/Native
or ParameterName, or a Key, RegistrationKey, or RuntimeKey together with
IsNative/Native. Each object is resolved on its own, so an object that cannot
be resolved is reported and the rest are still reset.

```yaml
Type: System.Object[]
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

### -Native

Targets native completer registrations instead of command parameter completers.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- IsNative
ParameterSets:
- Name: Native
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ParameterName

Specifies one or more parameter names for command-parameter completer reset
targets.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CommandParameter
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

Returns the `Pending` record of each target that was reset, and the unchanged
record of each target that was already `Pending`.

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

### System.Object[]

### System.String[]

### System.Management.Automation.SwitchParameter

## OUTPUTS

### CompleterActions.CompleterRegistration

When -PassThru is used, returns the `Pending` record of each target that was
reset and the unchanged record of each target that was already `Pending`.

## NOTES

## RELATED LINKS

[Get-Completer](Get-Completer.md)

[Register-Completer](Register-Completer.md)

[Unregister-Completer](Unregister-Completer.md)

[Import-CompleterSet](Import-CompleterSet.md)
