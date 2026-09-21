---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/11/2026
PlatyPS schema version: 2024-05-01
title: Register-Completer
---

# Register-Completer

## SYNOPSIS

Registers a managed PowerShell argument completer.

## SYNTAX

### CommandParameter (Default)

```PowerShell
Register-Completer -CommandName <string[]> -ParameterName <string[]>
 -ScriptBlock <scriptblock> [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### InputObject

```PowerShell
Register-Completer -InputObject <psobject[]> [-Force] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### LazyLiteralPath

```PowerShell
Register-Completer -LiteralPath <string> -Lazy [-CommandName <string[]>]
 [-ParameterName <string[]>] [-Native] [-Trusted] [-Force] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### LazyPath

```PowerShell
Register-Completer -Path <string> -Lazy [-CommandName <string[]>] [-ParameterName <string[]>]
 [-Native] [-Trusted] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Native

```PowerShell
Register-Completer -CommandName <string[]> -Native -ScriptBlock <scriptblock> [-Force]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}

## DESCRIPTION

Registers native or command-parameter argument completers with
`Register-ArgumentCompleter` and records the registrations in the module's
managed state. Existing managed or runtime registrations are preserved unless
you use `-Force` to replace them. Registering the same script for a target that
is already managed is idempotent only while the managed record still matches
the live runtime value; when the runtime registration was replaced or removed
outside this module, the managed record is stale and the command fails until
you reconcile it with `-Force`. Each target is updated transactionally: if the
runtime or managed write fails, the previous runtime and managed state are
restored and any rollback failure is reported alongside the original error. The
command supports array inputs for command and parameter targets, and it can
also accept pipeline `InputObject` values that describe the target and expose a
`ScriptBlock` property.

With `-Path` or `-LiteralPath` and `-Lazy` the command registers a completer
script without running it. The runtime entry for each target is a small stub
that imports the script through `Import-CompleterScript` on the first tab
press, replaces itself with the real completer, and delegates that first call
to it. The managed record reports `State` `Pending` until then and `Active`
afterwards. Under the default strict tier the targets are read from the
script's literal `Register-ArgumentCompleter` arguments, so the script is
parsed but never executed at registration time; the strict grammar itself
runs when the script loads, and a script that fails it moves to `Failed`
then. With `-Trusted` the script is dot-sourced as-is on first use and cannot be parsed safely, so the targets must
be supplied with `-CommandName` and `-Native` or `-ParameterName`.

If the script fails to load on the first tab press, the press returns no
completions, the runtime entry is removed so the completion engine's default
completion applies exactly as with no completer registered, and the managed
record moves to `State` `Failed` with the error message in `LoadError`. Nothing
is written to the host. Registering the same target again with `-Force`
retries the load. Lazy loading runs entirely inside the ordinary completer
call; it never hooks key handlers, replaces `TabExpansion2`, or changes
PSReadLine options.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Register-Completer -CommandName demoexe -Native -ScriptBlock $nativeScriptBlock
```

Registers a native completer for `demoexe` with a script block that is already
in memory.

### EXAMPLE 2

```PowerShell
Register-Completer -Path .\git_completer.ps1 -Lazy -PassThru
```

Reads the targets from the script's `Register-ArgumentCompleter` calls,
registers a stub for each of them, and returns the `Pending` records. The
script runs the first time tab completion is requested for one of its targets.

### EXAMPLE 3

```PowerShell
Register-Completer -Path .\git_completer.ps1 -Lazy -Trusted -CommandName git, git.exe -Native
```

Registers a script that needs the trusted tier lazily. The targets are named
explicitly because a trusted script is not parsed.

### EXAMPLE 4

```PowerShell
Get-Completer -State Failed |
    ForEach-Object {
        Register-Completer -LiteralPath $_.ScriptPath -Lazy -Trusted:$_.Trusted `
            -CommandName $_.CommandName -Native:$_.IsNative -Force
    }
```

Retries every lazy registration whose script failed to load, after the scripts
have been fixed.

## PARAMETERS

### -CommandName

Specifies one or more command names whose completers should be registered.
With `-Lazy` the parameter names the targets the script owns; it is required
with `-Trusted` and optional under the strict tier, where every name given must
be one the script registers.

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
- Name: LazyPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LazyLiteralPath
  Position: Named
  IsRequired: false
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

### -Force

Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value
was changed outside this module and a `Failed` lazy record whose load should be
retried.

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

### -InputObject

Supplies one or more objects that describe completer targets. Input objects
must expose `CommandName` with `IsNative`/`Native` or `ParameterName`, or a
`Key`, `RegistrationKey`, or `RuntimeKey` together with `IsNative`/`Native`,
and must expose a `ScriptBlock` property whose value is a script block. A key
without a native indicator is rejected; keys are output-only identifiers and
are never classified by their shape. `ScriptPath` or
`SourcePath` and `Trusted` properties, such as those on `Import-CompleterScript`
records, are carried onto the managed record.

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

### -Lazy

Registers a stub for each target of the script instead of running the script
now. The script is imported on the first tab press for any of its targets.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: LazyPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LazyLiteralPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -LiteralPath

The literal path to one completer script file to register lazily. Wildcards
are not expanded.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: LazyLiteralPath
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

Registers native completers for the commands instead of parameter completers.

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
- Name: LazyPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LazyLiteralPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ParameterName

Specifies one or more parameter names for command-parameter completer
registrations.

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
- Name: LazyPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LazyLiteralPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Returns the managed registration records that were created or reused.

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

The path to one completer script file to register lazily. Wildcards are
supported but must resolve to a single file.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: true
Aliases: []
ParameterSets:
- Name: LazyPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ScriptBlock

Provides the completer script block to register. When multiple targets are
supplied through arrays, the same script block is reused for each target.

```yaml
Type: System.Management.Automation.ScriptBlock
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

### -Trusted

Imports the script through the trusted tier on first use, dot-sourcing it
as-is without the strict grammar. The targets must be supplied with
`-CommandName` and `-Native` or `-ParameterName` because a trusted script is
not parsed. The default is the strict tier, which validates the script against
the grammar when it loads.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: LazyPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LazyLiteralPath
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

### System.Management.Automation.PSCustomObject

When -PassThru is used, returns `CompleterActions.CompleterRegistration`
records. Lazy registrations carry `State` `Pending`, the `ScriptPath` they
load, and `Trusted`.

### System.Management.Automation.PSObject

## NOTES

## RELATED LINKS

[Get-Completer](Get-Completer.md)

[Import-CompleterScript](Import-CompleterScript.md)

[Test-CompleterScript](Test-CompleterScript.md)
