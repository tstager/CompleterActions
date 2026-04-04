<#
.SYNOPSIS
Validates that a completer script uses a supported import shape.

.DESCRIPTION
Checks the script AST for patterns that Import-CompleterScript can safely and
predictably import. Supported scripts must be self-contained, must call
Register-ArgumentCompleter at script scope, and must use literal values for the
registration target and script block.

.PARAMETER Ast
The parsed script AST to validate.

.PARAMETER LiteralPath
The source path for error reporting.

.OUTPUTS
System.Boolean
#>
function Test-CompleterScriptAst
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    function Test-IsSupportedRegisterArgumentAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.Ast] $ArgumentAst,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ParameterName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path
        )

        switch ($ParameterName)
        {
            'CommandName'
            {
                if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
                {
                    foreach ($element in $ArgumentAst.Elements)
                    {
                        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            throw "Completer script '$Path' must use literal string values for -CommandName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                        }
                    }

                    return
                }

                throw "Completer script '$Path' must use literal string values for -CommandName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
            }

            'ParameterName'
            {
                if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
                {
                    foreach ($element in $ArgumentAst.Elements)
                    {
                        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            throw "Completer script '$Path' must use literal string values for -ParameterName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                        }
                    }

                    return
                }

                throw "Completer script '$Path' must use literal string values for -ParameterName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
            }

            'ScriptBlock'
            {
                if ($ArgumentAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst])
                {
                    throw "Completer script '$Path' must provide a literal script block for -ScriptBlock. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                }

                return
            }
        }
    }

    foreach ($statement in @($Ast.EndBlock.Statements))
    {
        if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $statement -isnot [System.Management.Automation.Language.IfStatementAst] -and
            $statement -isnot [System.Management.Automation.Language.PipelineAst])
        {
            throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($statement.GetType().Name)' at line $($statement.Extent.StartLineNumber)."
        }
    }

    $allowedImportCommands = @(
        'Get-Variable',
        'Register-ArgumentCompleter',
        'Set-StrictMode'
    )

    foreach ($commandAst in @($Ast.FindAll(
                {
                    param($node)

                    $node -is [System.Management.Automation.Language.CommandAst]
                },
                $true
            )))
    {
        $isTopLevelCommand = $true
        $ancestor = $commandAst.Parent

        while ($null -ne $ancestor -and $ancestor -ne $Ast)
        {
            if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                $isTopLevelCommand = $false
                break
            }

            $ancestor = $ancestor.Parent
        }

        if (-not $isTopLevelCommand)
        {
            continue
        }

        $commandName = $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName))
        {
            throw "Completer script '$LiteralPath' uses a non-literal top-level command at line $($commandAst.Extent.StartLineNumber)."
        }

        if ($allowedImportCommands -notcontains $commandName)
        {
            throw "Completer script '$LiteralPath' uses unsupported top-level command '$commandName' at line $($commandAst.Extent.StartLineNumber)."
        }
    }

    $functionOverrides = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Register-ArgumentCompleter'
            },
            $true
        ))

    if ($functionOverrides.Count -gt 0)
    {
        $lineNumber = $functionOverrides[0].Extent.StartLineNumber
        throw "Completer script '$LiteralPath' defines its own Register-ArgumentCompleter function at line $lineNumber. Import-CompleterScript only supports scripts that call the built-in command name directly."
    }

    $dotSourcedCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            },
            $true
        ))

    if ($dotSourcedCommands.Count -gt 0)
    {
        $lineNumber = $dotSourcedCommands[0].Extent.StartLineNumber
        throw "Completer script '$LiteralPath' dot-sources another script at line $lineNumber. Import-CompleterScript only supports self-contained completer scripts."
    }

    $registerCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $true
        ))

    if ($registerCommands.Count -eq 0)
    {
        throw "Completer script '$LiteralPath' does not contain a Register-ArgumentCompleter call."
    }

    foreach ($registerCommand in $registerCommands)
    {
        $ancestor = $registerCommand.Parent
        while ($null -ne $ancestor -and $ancestor -ne $Ast)
        {
            if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                throw "Completer script '$LiteralPath' registers a completer from inside a nested function or script block at line $($registerCommand.Extent.StartLineNumber). Import-CompleterScript only supports script-scope Register-ArgumentCompleter calls."
            }

            $ancestor = $ancestor.Parent
        }

        $currentParameter = $null
        $seenParameters = [ordered] @{}

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -notin 'CommandName', 'ParameterName', 'Native', 'ScriptBlock')
                {
                    throw "Completer script '$LiteralPath' uses unsupported Register-ArgumentCompleter parameter '-$($commandElement.ParameterName)' at line $($commandElement.Extent.StartLineNumber). Supported import parameters are -CommandName, -ParameterName, -Native, and -ScriptBlock."
                }

                if ($null -ne $commandElement.Argument)
                {
                    if ($commandElement.ParameterName -eq 'Native')
                    {
                        throw "Completer script '$LiteralPath' uses an argument for -Native at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript only supports the bare -Native switch."
                    }

                    Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement.Argument -ParameterName $commandElement.ParameterName -Path $LiteralPath
                    $currentParameter = $null
                }
                elseif ($commandElement.ParameterName -eq 'Native')
                {
                    $currentParameter = $null
                }
                else
                {
                    $currentParameter = $commandElement.ParameterName
                }

                $seenParameters[$commandElement.ParameterName] = $true
                continue
            }

            if ($commandElement -is [System.Management.Automation.Language.VariableExpressionAst] -and $commandElement.Splatted)
            {
                throw "Completer script '$LiteralPath' uses argument splatting at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript requires explicit Register-ArgumentCompleter parameters."
            }

            if ([string]::IsNullOrWhiteSpace($currentParameter))
            {
                throw "Completer script '$LiteralPath' uses positional Register-ArgumentCompleter arguments at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript requires explicit parameter names."
            }

            Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement -ParameterName $currentParameter -Path $LiteralPath
            $currentParameter = $null
        }

        if (-not [string]::IsNullOrWhiteSpace($currentParameter))
        {
            throw "Completer script '$LiteralPath' is missing the argument for -$currentParameter at line $($registerCommand.Extent.StartLineNumber)."
        }

        if (-not $seenParameters.Contains('CommandName'))
        {
            throw "Completer script '$LiteralPath' is missing -CommandName in a Register-ArgumentCompleter call at line $($registerCommand.Extent.StartLineNumber)."
        }

        if (-not $seenParameters.Contains('ScriptBlock'))
        {
            throw "Completer script '$LiteralPath' is missing -ScriptBlock in a Register-ArgumentCompleter call at line $($registerCommand.Extent.StartLineNumber)."
        }

        if ($seenParameters.Contains('Native') -and $seenParameters.Contains('ParameterName'))
        {
            throw "Completer script '$LiteralPath' combines -Native and -ParameterName at line $($registerCommand.Extent.StartLineNumber). Import-CompleterScript only supports the standard Register-ArgumentCompleter parameter sets."
        }

        if (-not $seenParameters.Contains('Native') -and -not $seenParameters.Contains('ParameterName'))
        {
            throw "Completer script '$LiteralPath' does not identify whether the completer is native or parameter-based at line $($registerCommand.Extent.StartLineNumber). Use -Native or -ParameterName."
        }
    }

    return $true
}
