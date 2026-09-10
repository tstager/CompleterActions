---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/10/2026
PlatyPS schema version: 2024-05-01
title: Test-CompleterRegistration
---

# Test-CompleterRegistration

## SYNOPSIS

Runs tab completion for an input against a registered completer target.

## SYNTAX

### CommandParameter (Default)

```PowerShell
Test-CompleterRegistration -CommandName <string[]> -ParameterName <string[]> -InputText <string>
 [-CursorPosition <int>] [<CommonParameters>]
```

### InputObject

```PowerShell
Test-CompleterRegistration -InputObject <psobject[]> -InputText <string> [-CursorPosition <int>]
 [<CommonParameters>]
```

### ByKey

```PowerShell
Test-CompleterRegistration -Key <string[]> -InputText <string> [-CursorPosition <int>]
 [<CommonParameters>]
```

### Native

```PowerShell
Test-CompleterRegistration -CommandName <string[]> -Native -InputText <string>
 [-CursorPosition <int>] [<CommonParameters>]
```

## DESCRIPTION

Resolves a completer target, confirms that it has a live runtime registration,
and runs `TabExpansion2` for the supplied input text. The completion matches
are returned as `CompleterActions.CompletionMatch` records that carry the
target key alongside `CompletionText`, `ListItemText`, `ResultType`, and
`ToolTip`, so the same check that used to be done by hand after every
registration can be scripted and asserted on.

One input text invokes one completer, so each call tests exactly one target.
The target parameters accept the same shapes as `Get-CompleterRegistration` so
registration records and property-bound values pipe in, but the command throws
when more than one target resolves in a single call.

The command only reads the completion engine. It does not change any
registration, and it never touches PSReadLine.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Test-CompleterRegistration -CommandName git -Native -InputText 'git che'
```

Returns the completion matches the registered git completer produces for
`git che`, such as `checkout`, `cherry`, and `cherry-pick`.

### EXAMPLE 2

```PowerShell
Get-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name |
    Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'
```

Verifies a registration record returned by `Get-CompleterRegistration` by
completing an argument for its parameter.

### EXAMPLE 3

```PowerShell
$matches = Test-CompleterRegistration -CommandName git -Native -InputText 'git che'
$matches.CompletionText | Should -Contain 'checkout'
```

Asserts on the matches inside a Pester test.

## PARAMETERS

### -CommandName

Specifies the command name of the native or command-parameter completer
target.

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

### -CursorPosition

The zero-based cursor position within `InputText` at which completion runs. The
default is the end of the input.

```yaml
Type: System.Int32
DefaultValue: 0
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

Supplies an object that describes the completer target, such as a record
returned by `Get-CompleterRegistration` or `Import-CompleterScript`. The object
must expose target metadata through `Key`, `RegistrationKey`, `RuntimeKey`, or
`CommandName`/`ParameterName` plus `IsNative`/`Native`.

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

### -InputText

The command line to complete, exactly as it would be typed at the prompt. It
must invoke the target's command, because the matches come from whatever
command the text names.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Key

Identifies the target by registration key. A key without a colon is treated
as a native command. A key with a colon is treated as a `Command:Parameter`
target unless the text after its last colon contains a path separator, in which
case it is treated as a native command path such as `C:\tools\example.exe`.

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

Indicates that the target is a native command completer instead of a command
parameter completer.

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

Specifies the parameter name of the command-parameter completer target.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.Management.Automation.PSObject[]

A registration record, or any object that describes a completer target.

### System.String[]

A registration key or command and parameter names bound by property name.

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns `CompleterActions.CompletionMatch` records, one per completion match,
with `Key`, `RuntimeKey`, `CommandName`, `ParameterName`, `CompleterType`,
`InputText`, `CursorPosition`, `CompletionText`, `ListItemText`, `ResultType`,
and `ToolTip` properties. Nothing is returned when the completer yields no
matches.

## NOTES

Completion runs from the module's scope, so the commands named in `InputText`
must be resolvable from the global scope, as they are in an interactive
session. Functions defined in a script's local scope are not visible to the
completion engine when it is invoked from this command.

## RELATED LINKS

[Get-CompleterRegistration](Get-CompleterRegistration.md)

[Test-CompleterScript](Test-CompleterScript.md)
