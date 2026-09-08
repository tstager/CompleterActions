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

        function Test-IsSupportedLiteralStringArrayExpressionAst
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [System.Management.Automation.Language.ArrayExpressionAst] $ExpressionAst,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $AstParameterName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $AstPath
            )

            $statementBlockAst = $ExpressionAst.SubExpression
            if ($statementBlockAst.Traps.Count -ne 0 -or $statementBlockAst.Statements.Count -ne 1)
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $pipelineAst = $statementBlockAst.Statements[0]
            if ($pipelineAst -isnot [System.Management.Automation.Language.PipelineAst] -or $pipelineAst.PipelineElements.Count -ne 1)
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $commandExpressionAst = $pipelineAst.PipelineElements[0]
            if ($commandExpressionAst -isnot [System.Management.Automation.Language.CommandExpressionAst])
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $arrayLiteralAst = $commandExpressionAst.Expression
            if ($arrayLiteralAst -isnot [System.Management.Automation.Language.ArrayLiteralAst])
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            foreach ($element in $arrayLiteralAst.Elements)
            {
                if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
                }
            }
        }

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

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
                {
                    Test-IsSupportedLiteralStringArrayExpressionAst -ExpressionAst $ArgumentAst -AstParameterName $ParameterName -AstPath $Path
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

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
                {
                    Test-IsSupportedLiteralStringArrayExpressionAst -ExpressionAst $ArgumentAst -AstParameterName $ParameterName -AstPath $Path
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

    $allowedImportCommands = @(
        'Get-Variable',
        'Register-ArgumentCompleter',
        'Set-StrictMode'
    )

    $allowedTopLevelOperators = @(
        [System.Management.Automation.Language.TokenKind]::And,
        [System.Management.Automation.Language.TokenKind]::Or,
        [System.Management.Automation.Language.TokenKind]::Xor,
        [System.Management.Automation.Language.TokenKind]::Ieq,
        [System.Management.Automation.Language.TokenKind]::Ine,
        [System.Management.Automation.Language.TokenKind]::Ige,
        [System.Management.Automation.Language.TokenKind]::Igt,
        [System.Management.Automation.Language.TokenKind]::Ilt,
        [System.Management.Automation.Language.TokenKind]::Ile,
        [System.Management.Automation.Language.TokenKind]::Ilike,
        [System.Management.Automation.Language.TokenKind]::Inotlike,
        [System.Management.Automation.Language.TokenKind]::Imatch,
        [System.Management.Automation.Language.TokenKind]::Inotmatch,
        [System.Management.Automation.Language.TokenKind]::Icontains,
        [System.Management.Automation.Language.TokenKind]::Inotcontains,
        [System.Management.Automation.Language.TokenKind]::Iin,
        [System.Management.Automation.Language.TokenKind]::Inotin,
        [System.Management.Automation.Language.TokenKind]::Ceq,
        [System.Management.Automation.Language.TokenKind]::Cne,
        [System.Management.Automation.Language.TokenKind]::Cge,
        [System.Management.Automation.Language.TokenKind]::Cgt,
        [System.Management.Automation.Language.TokenKind]::Clt,
        [System.Management.Automation.Language.TokenKind]::Cle,
        [System.Management.Automation.Language.TokenKind]::Clike,
        [System.Management.Automation.Language.TokenKind]::Cnotlike,
        [System.Management.Automation.Language.TokenKind]::Cmatch,
        [System.Management.Automation.Language.TokenKind]::Cnotmatch,
        [System.Management.Automation.Language.TokenKind]::Ccontains,
        [System.Management.Automation.Language.TokenKind]::Cnotcontains,
        [System.Management.Automation.Language.TokenKind]::Cin,
        [System.Management.Automation.Language.TokenKind]::Cnotin
    )

    # The nested validators below define the closed top-level grammar. Everything
    # outside function bodies and literal -ScriptBlock arguments must be reachable
    # through them, so anything they do not recognize is rejected before the
    # script is executed.
    function Test-ImportSafeExpressionAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.ExpressionAst] $ExpressionAst
        )

        if ($ExpressionAst -is [System.Management.Automation.Language.ConstantExpressionAst])
        {
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.VariableExpressionAst])
        {
            if ($ExpressionAst.Splatted)
            {
                throw "Completer script '$LiteralPath' uses argument splatting at line $($ExpressionAst.Extent.StartLineNumber). Import-CompleterScript requires explicit top-level command arguments."
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
        {
            foreach ($nestedExpression in $ExpressionAst.NestedExpressions)
            {
                if ($nestedExpression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $nestedExpression.Splatted)
                {
                    throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($nestedExpression.GetType().Name)' at line $($nestedExpression.Extent.StartLineNumber)."
                }
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            foreach ($element in $ExpressionAst.Elements)
            {
                Test-ImportSafeExpressionAst -ExpressionAst $element
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            if ($ExpressionAst.SubExpression.Traps.Count -ne 0)
            {
                throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            foreach ($statement in $ExpressionAst.SubExpression.Statements)
            {
                Test-ImportSafeValueStatementAst -StatementAst $statement
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.HashtableAst])
        {
            foreach ($keyValuePair in $ExpressionAst.KeyValuePairs)
            {
                Test-ImportSafeExpressionAst -ExpressionAst $keyValuePair.Item1
                Test-ImportSafeValueStatementAst -StatementAst $keyValuePair.Item2
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ParenExpressionAst])
        {
            Test-ImportSafeValueStatementAst -StatementAst $ExpressionAst.Pipeline
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.UnaryExpressionAst])
        {
            if ($ExpressionAst.TokenKind -notin [System.Management.Automation.Language.TokenKind]::Not, [System.Management.Automation.Language.TokenKind]::Exclaim)
            {
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($ExpressionAst.TokenKind)' at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Child
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.BinaryExpressionAst])
        {
            if ($ExpressionAst.Operator -notin $allowedTopLevelOperators)
            {
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($ExpressionAst.Operator)' at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Left
            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Right
            return
        }

        throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($ExpressionAst.GetType().Name)' at line $($ExpressionAst.Extent.StartLineNumber). Import-CompleterScript only supports literal values, variables, and simple comparisons outside function bodies and registered script blocks."
    }

    function Test-ImportSafeCommandExpressionAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandExpressionAst] $CommandExpressionAst
        )

        if ($CommandExpressionAst.Redirections.Count -ne 0)
        {
            throw "Completer script '$LiteralPath' uses redirection at line $($CommandExpressionAst.Extent.StartLineNumber). Import-CompleterScript does not support top-level redirection."
        }

        Test-ImportSafeExpressionAst -ExpressionAst $CommandExpressionAst.Expression
    }

    function Test-ImportSafeCommandAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandAst] $CommandAst
        )

        if ($CommandAst.Redirections.Count -ne 0)
        {
            throw "Completer script '$LiteralPath' uses redirection at line $($CommandAst.Extent.StartLineNumber). Import-CompleterScript does not support top-level redirection."
        }

        $commandName = $CommandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName))
        {
            throw "Completer script '$LiteralPath' uses a non-literal top-level command at line $($CommandAst.Extent.StartLineNumber)."
        }

        if ($allowedImportCommands -notcontains $commandName)
        {
            throw "Completer script '$LiteralPath' uses unsupported top-level command '$commandName' at line $($CommandAst.Extent.StartLineNumber)."
        }

        if ($commandName -eq 'Register-ArgumentCompleter')
        {
            # Register-ArgumentCompleter arguments are validated separately below.
            return
        }

        foreach ($commandElement in ($CommandAst.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($null -ne $commandElement.Argument)
                {
                    Test-ImportSafeExpressionAst -ExpressionAst $commandElement.Argument
                }

                continue
            }

            Test-ImportSafeExpressionAst -ExpressionAst $commandElement
        }
    }

    function Test-ImportSafePipelineAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.PipelineAst] $PipelineAst,

            [Parameter()]
            [switch] $AllowExpression
        )

        if ($PipelineAst.Background)
        {
            throw "Completer script '$LiteralPath' starts a background pipeline at line $($PipelineAst.Extent.StartLineNumber). Import-CompleterScript does not support background execution."
        }

        foreach ($pipelineElement in $PipelineAst.PipelineElements)
        {
            if ($pipelineElement -is [System.Management.Automation.Language.CommandAst])
            {
                Test-ImportSafeCommandAst -CommandAst $pipelineElement
                continue
            }

            if ($pipelineElement -is [System.Management.Automation.Language.CommandExpressionAst])
            {
                if ($AllowExpression)
                {
                    Test-ImportSafeCommandExpressionAst -CommandExpressionAst $pipelineElement
                    continue
                }

                throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($pipelineElement.Expression.GetType().Name)' at line $($pipelineElement.Extent.StartLineNumber). Import-CompleterScript only supports Set-StrictMode, Get-Variable, and Register-ArgumentCompleter commands at script scope."
            }

            throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($pipelineElement.GetType().Name)' at line $($pipelineElement.Extent.StartLineNumber)."
        }
    }

    function Test-ImportSafeValueStatementAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementAst] $StatementAst
        )

        if ($StatementAst -is [System.Management.Automation.Language.PipelineAst])
        {
            Test-ImportSafePipelineAst -PipelineAst $StatementAst -AllowExpression
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.CommandExpressionAst])
        {
            Test-ImportSafeCommandExpressionAst -CommandExpressionAst $StatementAst
            return
        }

        throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($StatementAst.GetType().Name)' at line $($StatementAst.Extent.StartLineNumber)."
    }

    function Test-ImportSafeStatementAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementAst] $StatementAst,

            [Parameter()]
            [switch] $AllowAssignment
        )

        if ($StatementAst -is [System.Management.Automation.Language.FunctionDefinitionAst])
        {
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.IfStatementAst])
        {
            foreach ($clause in $StatementAst.Clauses)
            {
                if ($clause.Item1 -isnot [System.Management.Automation.Language.PipelineAst])
                {
                    throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($clause.Item1.GetType().Name)' at line $($clause.Item1.Extent.StartLineNumber)."
                }

                Test-ImportSafePipelineAst -PipelineAst $clause.Item1 -AllowExpression
                Test-ImportSafeStatementBlockAst -StatementBlockAst $clause.Item2
            }

            if ($null -ne $StatementAst.ElseClause)
            {
                Test-ImportSafeStatementBlockAst -StatementBlockAst $StatementAst.ElseClause
            }

            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.PipelineAst])
        {
            Test-ImportSafePipelineAst -PipelineAst $StatementAst
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.AssignmentStatementAst])
        {
            if (-not $AllowAssignment)
            {
                throw "Completer script '$LiteralPath' uses a top-level assignment at line $($StatementAst.Extent.StartLineNumber). Import-CompleterScript only supports assignments inside importer-safe if statements."
            }

            if ($StatementAst.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals)
            {
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($StatementAst.Operator)' at line $($StatementAst.Extent.StartLineNumber)."
            }

            $target = $StatementAst.Left
            if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $target.Splatted -or
                -not ($target.VariablePath.IsUnqualified -or $target.VariablePath.IsScript))
            {
                throw "Completer script '$LiteralPath' assigns to unsupported target '$($target.Extent.Text)' at line $($target.Extent.StartLineNumber). Import-CompleterScript only supports assignments to unqualified or script-scope variables."
            }

            Test-ImportSafeValueStatementAst -StatementAst $StatementAst.Right
            return
        }

        throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($StatementAst.GetType().Name)' at line $($StatementAst.Extent.StartLineNumber)."
    }

    function Test-ImportSafeStatementBlockAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementBlockAst] $StatementBlockAst
        )

        if ($StatementBlockAst.Traps.Count -ne 0)
        {
            throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($StatementBlockAst.Traps[0].Extent.StartLineNumber)."
        }

        foreach ($statement in $StatementBlockAst.Statements)
        {
            Test-ImportSafeStatementAst -StatementAst $statement -AllowAssignment
        }
    }

    foreach ($usingStatement in @($Ast.UsingStatements))
    {
        if ($usingStatement.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Namespace)
        {
            throw "Completer script '$LiteralPath' uses a 'using $($usingStatement.UsingStatementKind.ToString().ToLowerInvariant())' statement at line $($usingStatement.Extent.StartLineNumber). Import-CompleterScript only supports 'using namespace' statements."
        }
    }

    if ($null -ne $Ast.ScriptRequirements)
    {
        if ($Ast.ScriptRequirements.RequiredModules.Count -gt 0)
        {
            throw "Completer script '$LiteralPath' uses a '#requires -Modules' directive. Import-CompleterScript does not support '#requires -Modules' because the required modules are imported, and their top-level code executes, when the script is dot-sourced."
        }

        if ($Ast.ScriptRequirements.RequiredAssemblies.Count -gt 0)
        {
            throw "Completer script '$LiteralPath' uses a '#requires -Assembly' directive. Import-CompleterScript does not support '#requires -Assembly' because the required assemblies are loaded when the script is dot-sourced."
        }
    }

    foreach ($namedBlock in @($Ast.ParamBlock, $Ast.BeginBlock, $Ast.ProcessBlock, $Ast.DynamicParamBlock, $Ast.CleanBlock))
    {
        if ($null -ne $namedBlock)
        {
            throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($namedBlock.GetType().Name)' at line $($namedBlock.Extent.StartLineNumber)."
        }
    }

    if ($Ast.EndBlock.Traps.Count -ne 0)
    {
        throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($Ast.EndBlock.Traps[0].Extent.StartLineNumber)."
    }

    foreach ($statement in @($Ast.EndBlock.Statements))
    {
        Test-ImportSafeStatementAst -StatementAst $statement
    }

    $functionOverrides = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in $allowedImportCommands
            },
            $true
        ))

    if ($functionOverrides.Count -gt 0)
    {
        $lineNumber = $functionOverrides[0].Extent.StartLineNumber
        throw "Completer script '$LiteralPath' defines its own $($functionOverrides[0].Name) function at line $lineNumber. Import-CompleterScript only supports scripts that call the built-in command name directly."
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
