---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 04/01/2026
PlatyPS schema version: 2024-05-01
title: Get-CompleterRegistration
---

# Get-CompleterRegistration

## SYNOPSIS

Gets completer registrations known to the module or discovered at runtime.

## SYNTAX

### All (Default)

```PowerShell
Get-CompleterRegistration [-ManagedOnly] [-DiscoveredOnly] [-IncludeTotalCount] [-Skip <ulong>]
 [-First <ulong>] [<CommonParameters>]
```

### ByKey

```PowerShell
Get-CompleterRegistration -Key <string[]> [-ManagedOnly] [-DiscoveredOnly] [-IncludeTotalCount]
 [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

### CommandParameter

```PowerShell
Get-CompleterRegistration -CommandName <string[]> -ParameterName <string[]> [-ManagedOnly]
 [-DiscoveredOnly] [-IncludeTotalCount] [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

### Native

```PowerShell
Get-CompleterRegistration -CommandName <string[]> -Native [-ManagedOnly] [-DiscoveredOnly]
 [-IncludeTotalCount] [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Returns completer registration records for all registrations, specific
registration keys, native command completers, or command parameter completers.
By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target and the managed record still matches the live runtime value.
When the runtime registration was replaced outside this module, the live
discovered value is returned with State 'Conflicted' instead; -ManagedOnly
returns the managed record with State 'Stale'.
When the runtime registration was removed outside this module, the managed
record is returned with State 'Stale' and IsRuntimeRegistered false.
The command accepts arrays for key, command, and parameter
lookup scenarios and supports property-name pipeline binding for key-based and
target-based lookups.

## EXAMPLES

### EXAMPLE 1

Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

### EXAMPLE 2

Get-CompleterRegistration -Key 'git:checkout', 'git:branch'

Gets multiple completer registrations by key in a single call.

## PARAMETERS

### -CommandName

Limits results to one or more command names for native or command-parameter
completers.

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

### -DiscoveredOnly

Returns only registrations discovered from the current PowerShell runtime.

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

### -First

```yaml
Type: System.UInt64
DefaultValue: ''
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

### -IncludeTotalCount

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

### -Key

Gets the registrations that match one or more registration keys.

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

### -ManagedOnly

Returns only registrations tracked by this module.

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

### -Native

Indicates that the lookup target is a native command completer instead of a
command parameter completer.

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

Limits results to one or more parameter completer targets.

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

### -Skip

```yaml
Type: System.UInt64
DefaultValue: ''
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

### System.Management.Automation.SwitchParameter

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns CompleterActions.CompleterRegistration records.

### System.Management.Automation.PSObject

## NOTES

## RELATED LINKS

[text](https://github.com/tstager/CompleterActions/blob/deae4ca162751c60861237e1d2825f9b0f1fd0ff/src/docs/CompleterActions/Get-CompleterRegistration.md)
