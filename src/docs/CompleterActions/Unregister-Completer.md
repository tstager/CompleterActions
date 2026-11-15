---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: https://github.com/tstager/CompleterActions/blob/main/src/docs/CompleterActions/Unregister-Completer.md
Locale: en-US
Module Name: CompleterActions
ms.date: 09/11/2026
PlatyPS schema version: 2024-05-01
title: Unregister-Completer
---

# Unregister-Completer

## SYNOPSIS

Removes completer registrations from runtime and, when applicable, module state.

## SYNTAX

### CommandParameter (Default)

```PowerShell
Unregister-Completer -CommandName <string[]> -ParameterName <string[]> [-AllowUnmanaged]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### InputObject

```PowerShell
Unregister-Completer -InputObject <Object[]> [-AllowUnmanaged] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### Native

```PowerShell
Unregister-Completer -CommandName <string[]> -Native [-AllowUnmanaged] [-PassThru]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Removes completer registrations identified by native command, command
parameter target, or pipeline InputObject values.
Managed registrations
are removed from both the PowerShell runtime and the module's registration
table.
Runtime-only registrations require -AllowUnmanaged before they can be
removed.
The same gate applies when a managed record is stale because the runtime
registration was replaced outside this module: the live value is only removed
with -AllowUnmanaged, and the stale managed record is dropped with it.
When the runtime registration was already removed outside this module, only the
stale managed record remains and it is removed without the gate.
A Pending lazy registration is removed like any managed registration, stub and
record together. A Failed lazy registration has no runtime entry of its own, so
only its managed record is removed.
The command supports array inputs for the target fields, plus pipeline input
from Get-Completer output; each target is decided once per call, so the
Conflicted twin of a Stale record is skipped rather than confirmed again or
reported as missing, and a declined confirmation stands. Keys are output-only
identifiers: a
hand-typed key string is not accepted, so name the target with -CommandName
plus -Native or -ParameterName instead. Only the kind of target named is
removed: a native command whose name contains a colon, such as an alias named
`Get-Thing:Name`, shares its key with the parameter target `Get-Thing` /
`Name`, and removing one never touches the other.
To reload a Failed or Active script-backed registration instead of removing
it, use Reset-Completer.

## EXAMPLES

## PARAMETERS

### -AllowUnmanaged

Allows removal of runtime registrations that are not tracked by this module,
including a live value that replaced a managed registration outside this
module.

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

### -CommandName

Specifies one or more command names whose completers should be removed.

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

Supplies one or more objects that describe registrations to remove.
Input objects expose CommandName with IsNative/Native or ParameterName, or a
Key, RegistrationKey, or RuntimeKey together with IsNative/Native.
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

Specifies one or more parameter names for command-parameter completer removal
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

Returns the registration records that were removed.

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

When `-PassThru` is used, returns the removed
`CompleterActions.CompleterRegistration` records.

## NOTES

## RELATED LINKS

[Reset-Completer](Reset-Completer.md)
