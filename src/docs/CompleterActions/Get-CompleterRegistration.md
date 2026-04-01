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

# Get-CompleterRegistration <!-- markdownlint-disable-line MD025 -->

## SYNOPSIS

Gets completer registrations known to the module or discovered at runtime.

## SYNTAX

### All (Default)
<!-- markdownlint-disable-next-line MD040 -->
```
Get-CompleterRegistration [-ManagedOnly] [-DiscoveredOnly] [<CommonParameters>]
```

### ByKey
<!-- markdownlint-disable-next-line MD040 -->
```
Get-CompleterRegistration -Key <string> [-ManagedOnly] [-DiscoveredOnly] [<CommonParameters>]
```

### CommandParameter
<!-- markdownlint-disable-next-line MD040 -->
```
Get-CompleterRegistration -CommandName <string> -ParameterName <string> [-ManagedOnly]
 [-DiscoveredOnly] [<CommonParameters>]
```

### Native
<!-- markdownlint-disable-next-line MD040 -->
```
Get-CompleterRegistration -CommandName <string> -Native [-ManagedOnly] [-DiscoveredOnly]
 [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Returns completer registration records for all registrations, a specific
registration key, a native command completer, or a command parameter
completer.
By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target.

## EXAMPLES

### EXAMPLE 1

Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

### EXAMPLE 2

Get-CompleterRegistration -ManagedOnly

Lists only completer registrations that were registered through this module.

## PARAMETERS

### -CommandName

Limits results to a specific command name for native or command-parameter
completers.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CommandParameter
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Native
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
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

### -Key

Gets the registration that matches a specific registration key.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ByKey
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
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
Aliases: []
ParameterSets:
- Name: Native
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ParameterName

Limits results to a specific parameter completer target.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CommandParameter
  Position: Named
  IsRequired: true
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

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns CompleterActions.CompleterRegistration records.

### System.Management.Automation.PSObject

## NOTES

## RELATED LINKS
