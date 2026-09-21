---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/11/2026
PlatyPS schema version: 2024-05-01
title: Get-Completer
---

# Get-Completer

## SYNOPSIS

Gets completer registrations known to the module or discovered at runtime.

## SYNTAX

### All (Default)

```PowerShell
Get-Completer [-State <CompleterState[]>] [-IncludeTotalCount] [-Skip <ulong>]
 [-First <ulong>] [<CommonParameters>]
```

### InputObject

```PowerShell
Get-Completer -InputObject <Object[]> [-State <CompleterState[]>] [-IncludeTotalCount]
 [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

### CommandParameter

```PowerShell
Get-Completer -CommandName <string[]> -ParameterName <string[]> [-State <CompleterState[]>]
 [-IncludeTotalCount] [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

### Native

```PowerShell
Get-Completer -CommandName <string[]> -Native [-State <CompleterState[]>]
 [-IncludeTotalCount] [-Skip <ulong>] [-First <ulong>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,

## DESCRIPTION

Returns completer registration records for all registrations, native command
completers, command parameter completers, or the targets described by piped
registration records.
The command merges module-managed registrations with runtime-discovered
registrations and reports each record's State once, so -State can select any
subset. A managed record whose stored script is the live runtime value is
'Active', or 'Pending' while a lazy registration still waits for its first tab
press. A runtime value that no managed record describes is 'Discovered'. When
the runtime registration was replaced outside this module, the managed record
is returned with State 'Stale' and the live value with State 'Conflicted';
when it was removed outside this module, the managed record is 'Stale' with
IsRuntimeRegistered false. A lazy registration whose script failed to load is
'Failed'; it has no runtime entry and carries the error in LoadError. Without
-State every record is returned.
The command accepts arrays for command and parameter lookups, and records
piped back from Get-Completer or Import-CompleterScript resolve
through their Key and IsNative properties. Keys are output-only identifiers: a
hand-typed key string is not accepted, so name the target with -CommandName
plus -Native or -ParameterName instead.

Discovery covers the two target kinds this module manages: command-parameter
completers and native command completers. A completer registered with
`Register-ArgumentCompleter -ParameterName` alone, without `-CommandName`,
applies to every command with that parameter and is stored under the bare
parameter name; such registrations are not returned and are reported with
`-Verbose` as they are skipped, so they never prevent the supported
registrations from being listed.

## EXAMPLES

### EXAMPLE 1

Get-Completer -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

### EXAMPLE 2

Get-Completer -CommandName 'git' -ParameterName 'checkout', 'branch'

Gets multiple command-parameter completer registrations in a single call.

### EXAMPLE 3

Get-Completer -State Pending, Failed

Lists the lazy registrations that have not loaded yet and the ones whose script
failed to load, with the failure message in LoadError.

### EXAMPLE 4

Import-CompleterScript -LiteralPath .\git_completer.ps1 | Get-Completer

Gets the live registrations for the targets a completer script defines by
piping its import records back in.

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

### -InputObject

Supplies one or more objects that describe the registrations to get, such as
records returned by Get-Completer or Import-CompleterScript. An
input object exposes CommandName with IsNative/Native or ParameterName, or a
Key, RegistrationKey, or RuntimeKey together with IsNative/Native.

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

### -State

Returns only the records whose State is one of the given values: Active,
Stale, Conflicted, Pending, Failed, or Discovered. Several values return the
union.

```yaml
Type: CompleterState[]
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
AcceptedValues:
- Active
- Stale
- Conflicted
- Pending
- Failed
- Discovered
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

Returns CompleterActions.CompleterRegistration records. The State property is
'Active' for managed records that describe the live runtime value,
'Discovered' for runtime values that no managed record describes, 'Pending'
for lazy registrations whose script has not loaded yet, 'Failed' for lazy
registrations whose script failed to load, 'Stale' for managed records that no
longer match the runtime, and 'Conflicted' for live runtime values that
replaced a managed registration outside this module. ScriptPath names the
completer script behind a lazy or imported registration and LoadError holds
the failure message of a Failed record.

## NOTES

## RELATED LINKS

[text](https://github.com/tstager/CompleterActions/blob/deae4ca162751c60861237e1d2825f9b0f1fd0ff/src/docs/CompleterActions/Get-Completer.md)
