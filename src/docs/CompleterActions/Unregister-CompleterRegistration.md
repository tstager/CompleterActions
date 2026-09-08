---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 04/01/2026
PlatyPS schema version: 2024-05-01
title: Unregister-CompleterRegistration
---

# Unregister-CompleterRegistration

## SYNOPSIS

Removes completer registrations from runtime and, when applicable, module state.

## SYNTAX

### ByKey (Default)

```PowerShell
Unregister-CompleterRegistration -Key <string[]> [-AllowUnmanaged] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### InputObject

```PowerShell
Unregister-CompleterRegistration -InputObject <psobject[]> [-AllowUnmanaged] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### CommandParameter

```PowerShell
Unregister-CompleterRegistration -CommandName <string[]> -ParameterName <string[]> [-AllowUnmanaged]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Native

```PowerShell
Unregister-CompleterRegistration -CommandName <string[]> -Native [-AllowUnmanaged] [-PassThru]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Removes completer registrations identified by registration key, native command,
command parameter target, or pipeline InputObject values.
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
The command supports array inputs for keys and target fields, plus
pipeline input from Get-CompleterRegistration output.

## EXAMPLES

## PARAMETERS

### -AllowUnmanaged

Allows removal of runtime registrations that are not tracked by this module.

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
Input
objects can expose Key, RegistrationKey, RuntimeKey, or
CommandName/ParameterName plus IsNative/Native.

```yaml
Type: System.Management.Automation.PSObject[]
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

### -Key

Removes the registrations that match one or more registration keys.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- RegistrationKey
ParameterSets:
- Name: ByKey
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
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

### System.Management.Automation.PSObject[]

### System.String[]

### System.Management.Automation.SwitchParameter

## OUTPUTS

### System.Management.Automation.PSCustomObject

When -PassThru is used

### System.Management.Automation.PSObject

## NOTES

## RELATED LINKS

[text](https://github.com/tstager/CompleterActions/blob/deae4ca162751c60861237e1d2825f9b0f1fd0ff/src/docs/CompleterActions/Unregister-CompleterRegistration.md)
