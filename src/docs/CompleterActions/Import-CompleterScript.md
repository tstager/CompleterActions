---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 04/04/2026
PlatyPS schema version: 2024-05-01
title: Import-CompleterScript
---

# Import-CompleterScript

## SYNOPSIS

Imports self-contained completer scripts into registration input objects.

## SYNTAX

### Path (Default)

```PowerShell
Import-CompleterScript [-Path] <string[]> [<CommonParameters>]
```

### LiteralPath

```PowerShell
Import-CompleterScript -LiteralPath <string[]> [<CommonParameters>]
```

## DESCRIPTION

Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows `Register-ArgumentCompleter`, and emits objects
that can be piped directly to `Register-CompleterRegistration -InputObject`.

Supported scripts must be self-contained and must use literal
`Register-ArgumentCompleter` arguments for the target metadata and script block.
Imported script blocks preserve the temporary module context that contains any
helper functions and script-scope state defined by the source script.

## COMPATIBLE COMPLETER SCRIPT SPECIFICATION

Write standalone completer scripts to this specification if you want them to
remain importable through `Import-CompleterScript` without redesign:

- Keep the script self-contained. Do not dot-source other scripts.
- Keep script scope limited to:
  - `Set-StrictMode`
  - function definitions
  - importer-safe `if` statements
  - script-scope `Register-ArgumentCompleter` calls
- Do not use top-level assignments, loops, `try`/`catch`, alias bootstrap,
  cache initialization, generated completion loading, or external command
  execution.
- Register completers directly with the built-in
  `Register-ArgumentCompleter`; do not wrap registration in custom helper
  functions.
- Use only these `Register-ArgumentCompleter` parameters:
  - `-CommandName`
  - `-ParameterName`
  - bare `-Native`
  - `-ScriptBlock`
- Use explicit parameter names only. Positional registration arguments and
  argument splatting are not supported.
- Keep target metadata literal:
  - `-CommandName` and `-ParameterName` may be a single literal string
  - a literal string array
  - or a literal `@('name', 'name.exe')` array expression
- Keep `-ScriptBlock` literal.
- Keep `Register-ArgumentCompleter` calls at script scope, not inside nested
  functions or nested script blocks.
- Move alias bootstrap, cache initialization, generated completion loading, and
  other setup into lazy, idempotent helper paths reached from the registered
  completion script block.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Import-CompleterScript -Path .\7z_completer.ps1 |
    Register-CompleterRegistration -PassThru
```

Imports a supported completer script and registers the imported definitions
through the module's managed registration API.

### EXAMPLE 2

```PowerShell
Register-ArgumentCompleter -Native -CommandName @('tool', 'tool.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Tool -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

This is the preferred registration shape for an import-compatible native
completer. Keep setup logic in helper functions that run from `Complete-Tool`
rather than at script scope.

## PARAMETERS

### -LiteralPath

One or more literal paths to completer script files. Wildcards are not expanded.

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

One or more paths to completer script files. Wildcards are supported.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns `CompleterActions.ImportedCompleterRegistration` records compatible with
`Register-CompleterRegistration -InputObject`.

## NOTES

Importer compatibility and runtime correctness are both required for future
standalone completer scripts. Validate both the real `pwsh -NoProfile`
completion behavior and the script's `Import-CompleterScript` compatibility
before treating a completer as complete.

## RELATED LINKS
