---
document type: cmdlet
external help file: CompleterActions-Help.xml
HelpUri: ''
Locale: en-US
Module Name: CompleterActions
ms.date: 09/10/2026
PlatyPS schema version: 2024-05-01
title: Test-CompleterScript
---

# Test-CompleterScript

## SYNOPSIS

Checks completer scripts against the strict import grammar and reports findings.

## SYNTAX

### Path (Default)

```PowerShell
Test-CompleterScript [-Path] <string[]> [<CommonParameters>]
```

### LiteralPath

```PowerShell
Test-CompleterScript -LiteralPath <string[]> [<CommonParameters>]
```

## DESCRIPTION

Parses one or more completer scripts and runs the same validation that
`Import-CompleterScript` applies before it executes a script. Instead of
stopping at the first problem, the command returns one
`CompleterActions.CompleterScriptFinding` record per unsupported construct with
the line and column, the construct type, a message, and a hint that describes
how to change the script so it imports under the strict tier.

A conforming script produces no output, so a conformance test can assert that
the command returns nothing, or filter on `Severity` the way the strict importer
does. A script that cannot be parsed yields one finding per parse error and is
not checked further. `Test-CompleterScript` never executes the script.

## EXAMPLES

### EXAMPLE 1

```PowerShell
Test-CompleterScript -Path .\tool_completer.ps1
```

Reports each construct that keeps the script from importing under the strict
tier, or nothing when the script conforms.

### EXAMPLE 2

```PowerShell
Get-ChildItem -Path ~\Completers -Recurse -Filter *.ps1 |
    Test-CompleterScript |
    Where-Object Severity -eq Error
```

Runs the conformance check over a completer repository. The pipeline is empty
when every script conforms.

### EXAMPLE 3

```PowerShell
Describe 'completer conformance' {
    It 'imports under the strict tier: <Name>' -TestCases (
        Get-ChildItem -Path $PSScriptRoot -Filter *_completer.ps1 -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        param($Path)

        Test-CompleterScript -Path $Path | Should -BeNullOrEmpty
    }
}
```

Turns the conformance check into a Pester test for a completer repository.

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
Aliases:
- FullName
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

### CompleterActions.CompleterScriptFinding

Returns `CompleterActions.CompleterScriptFinding` records with `Path`, `Line`,
`Column`, `Severity`, `Construct`, `Message`, and `Hint` properties. Every
finding the strict grammar produces has `Severity` `Error`.

## NOTES

`Import-CompleterScript` builds its strict-tier error text from the same
findings, so the two commands cannot disagree about what the grammar accepts.
Scripts that must stay outside the grammar can be imported with
`Import-CompleterScript -Trusted` instead of being rewritten.

## RELATED LINKS

[Import-CompleterScript](Import-CompleterScript.md)

[Test-CompleterRegistration](Test-CompleterRegistration.md)
