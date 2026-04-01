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
<!-- markdownlint-disable-next-line MD025 -->
# Unregister-CompleterRegistration

## SYNOPSIS

Removes a completer registration from runtime and, when applicable, module state.

## SYNTAX

### ByKey (Default)
<!-- markdownlint-disable-next-line MD040 -->
```
Unregister-CompleterRegistration -Key <string> [-AllowUnmanaged] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### CommandParameter
<!-- markdownlint-disable-next-line MD040 -->
```
Unregister-CompleterRegistration -CommandName <string> -ParameterName <string> [-AllowUnmanaged]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Native
<!-- markdownlint-disable-next-line MD040 -->
```
Unregister-CompleterRegistration -CommandName <string> -Native [-AllowUnmanaged] [-PassThru]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Removes a completer registration identified by registration key, native command,
or command parameter target.
Managed registrations are removed from both the
PowerShell runtime and the module's registration table.
Runtime-only
registrations require -AllowUnmanaged before they can be removed.

## EXAMPLES

### EXAMPLE 1

Unregister-CompleterRegistration -CommandName 'Test-Tool' -ParameterName 'Name' -Confirm:$false

Removes the managed parameter completer for Test-Tool Name without prompting.

### EXAMPLE 2

Unregister-CompleterRegistration -CommandName 'git' -Native -AllowUnmanaged -Confirm:$false -PassThru

Removes a native runtime completer for git even if it was not registered
through this module, and returns the removed record.

## PARAMETERS

### -AllowUnmanaged

Allows removal of a runtime registration that is not tracked by this module.

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

Specifies the command name whose completer should be removed.

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

### -Key

Removes the registration that matches a specific registration key.

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

### -Native

Targets a native completer registration instead of a command parameter
completer.

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

Specifies the parameter name for a command-parameter completer removal target.

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

### -PassThru

Returns the registration record that was removed.

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

## OUTPUTS

### System.Management.Automation.PSCustomObject

When -PassThru is used

### System.Management.Automation.PSObject

## NOTES

## RELATED LINKS
