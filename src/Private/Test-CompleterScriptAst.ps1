<#
.SYNOPSIS
Validates that a completer script uses a supported import shape.

.DESCRIPTION
Checks the script AST for patterns that Import-CompleterScript can safely and
predictably import. Supported scripts must be self-contained, must call
Register-ArgumentCompleter at script scope, and must use literal values for the
registration target and script block. Every unsupported construct is reported
as a CompleterActions.CompleterScriptFinding record; a conforming script
produces no output.

.PARAMETER Ast
The parsed script AST to validate.

.PARAMETER LiteralPath
The source path recorded on each finding.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Test-CompleterScriptAst
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    $scriptScopeHint = 'Script scope may only contain Set-StrictMode, Get-Variable, Register-ArgumentCompleter, function definitions, and guarded if statements. Move this into a function that the completer calls lazily.'

    function Add-Finding
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.IScriptExtent] $Extent,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Construct,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Hint
        )

        $findings.Add((New-CompleterScriptFinding -Path $LiteralPath -Extent $Extent -Construct $Construct -Message $Message -Hint $Hint))
    }

    function Get-ImportSafeExpressionHint
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.ExpressionAst] $ExpressionAst
        )

        if ($ExpressionAst -is [System.Management.Automation.Language.ConvertExpressionAst])
        {
            return "A type cast runs at import time. Move the $($ExpressionAst.Type.Extent.Text) literal into a lazy initializer inside a function."
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.MemberExpressionAst])
        {
            return 'A [type]::Member or object member access runs at import time. Move it into a lazy initializer inside a function.'
        }

        return 'Keep script-scope values literal (strings, numbers, arrays, and hashtables) and compute everything else lazily inside a function.'
    }

    function Test-IsSupportedRegisterArgumentAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.Ast] $ArgumentAst,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ParameterName
        )

        function Get-LiteralArrayExpressionElement
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [System.Management.Automation.Language.ArrayExpressionAst] $ExpressionAst
            )

            $statementBlockAst = $ExpressionAst.SubExpression
            if ($statementBlockAst.Traps.Count -ne 0 -or $statementBlockAst.Statements.Count -ne 1)
            {
                return $null
            }

            $pipelineAst = $statementBlockAst.Statements[0]
            if ($pipelineAst -isnot [System.Management.Automation.Language.PipelineAst] -or $pipelineAst.PipelineElements.Count -ne 1)
            {
                return $null
            }

            $commandExpressionAst = $pipelineAst.PipelineElements[0]
            if ($commandExpressionAst -isnot [System.Management.Automation.Language.CommandExpressionAst])
            {
                return $null
            }

            if ($commandExpressionAst.Expression -is [System.Management.Automation.Language.ArrayLiteralAst])
            {
                return @($commandExpressionAst.Expression.Elements)
            }

            return @($commandExpressionAst.Expression)
        }

        if ($ParameterName -eq 'ScriptBlock')
        {
            if ($ArgumentAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                Add-Finding -Extent $ArgumentAst.Extent -Construct $ArgumentAst.GetType().Name -Message 'The script must provide a literal script block for -ScriptBlock.' -Hint 'Pass the completer body as a literal { ... } script block and move any shared code into functions that the script block calls.'
            }

            return
        }

        if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
        {
            return
        }

        $elements = $null
        if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            $elements = @($ArgumentAst.Elements)
        }
        elseif ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            $elements = Get-LiteralArrayExpressionElement -ExpressionAst $ArgumentAst
        }

        if ($null -ne $elements -and @($elements | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] }).Count -eq 0)
        {
            return
        }

        Add-Finding -Extent $ArgumentAst.Extent -Construct $ArgumentAst.GetType().Name -Message "The script must use literal string values for -$ParameterName." -Hint "Replace the -$ParameterName value with a literal string or a literal @('name', 'name.exe') array; a value computed at import time cannot be analyzed."
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
    # through them, so anything they do not recognize is reported before the
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
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'VariableExpressionAst' -Message 'The script uses argument splatting at script scope.' -Hint 'Spell out each parameter explicitly; Import-CompleterScript requires explicit top-level command arguments.'
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
        {
            foreach ($nestedExpression in $ExpressionAst.NestedExpressions)
            {
                if ($nestedExpression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $nestedExpression.Splatted)
                {
                    Add-Finding -Extent $nestedExpression.Extent -Construct $nestedExpression.GetType().Name -Message "The script contains unsupported top-level expression '$($nestedExpression.GetType().Name)' inside an expandable string." -Hint 'Use only plain variables inside script-scope strings, or build the string lazily inside a function.'
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
                Add-Finding -Extent $ExpressionAst.SubExpression.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
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
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'UnaryExpressionAst' -Message "The script uses unsupported top-level operator '$($ExpressionAst.TokenKind)'." -Hint 'Only -not and ! are supported at script scope; compute other values lazily inside a function.'
                return
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Child
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.BinaryExpressionAst])
        {
            if ($ExpressionAst.Operator -notin $allowedTopLevelOperators)
            {
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'BinaryExpressionAst' -Message "The script uses unsupported top-level operator '$($ExpressionAst.Operator)'." -Hint 'Only comparison and logical operators are supported at script scope; compute other values lazily inside a function.'
                return
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Left
            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Right
            return
        }

        Add-Finding -Extent $ExpressionAst.Extent -Construct $ExpressionAst.GetType().Name -Message "The script contains unsupported top-level expression '$($ExpressionAst.GetType().Name)'." -Hint (Get-ImportSafeExpressionHint -ExpressionAst $ExpressionAst)
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
            Add-Finding -Extent $CommandExpressionAst.Redirections[0].Extent -Construct $CommandExpressionAst.Redirections[0].GetType().Name -Message 'The script uses redirection at script scope.' -Hint 'Remove the redirection, or move the expression into a function that the completer calls lazily.'
            return
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
            Add-Finding -Extent $CommandAst.Redirections[0].Extent -Construct $CommandAst.Redirections[0].GetType().Name -Message 'The script uses redirection at script scope.' -Hint 'Remove the redirection, or move the command into a function that the completer calls lazily.'
            return
        }

        $commandName = $CommandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script uses a non-literal top-level command.' -Hint 'Call commands by their literal name at script scope, or move the call into a function that the completer calls lazily.'
            return
        }

        if ($allowedImportCommands -notcontains $commandName)
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message "The script uses unsupported top-level command '$commandName'." -Hint "Only Set-StrictMode, Get-Variable, and Register-ArgumentCompleter may run at script scope. Move '$commandName' into a function that the completer calls lazily."
            return
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
            Add-Finding -Extent $PipelineAst.Extent -Construct 'PipelineAst' -Message 'The script starts a background pipeline at script scope.' -Hint 'Remove the & background operator; Import-CompleterScript does not support background execution.'
            return
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

                Add-Finding -Extent $pipelineElement.Extent -Construct $pipelineElement.Expression.GetType().Name -Message "The script contains unsupported top-level expression '$($pipelineElement.Expression.GetType().Name)'." -Hint (Get-ImportSafeExpressionHint -ExpressionAst $pipelineElement.Expression)
                continue
            }

            Add-Finding -Extent $pipelineElement.Extent -Construct $pipelineElement.GetType().Name -Message "The script contains unsupported top-level syntax '$($pipelineElement.GetType().Name)'." -Hint $scriptScopeHint
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

        Add-Finding -Extent $StatementAst.Extent -Construct $StatementAst.GetType().Name -Message "The script contains unsupported top-level syntax '$($StatementAst.GetType().Name)'." -Hint $scriptScopeHint
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
                    Add-Finding -Extent $clause.Item1.Extent -Construct $clause.Item1.GetType().Name -Message "The script contains unsupported top-level syntax '$($clause.Item1.GetType().Name)'." -Hint $scriptScopeHint
                    continue
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
                Add-Finding -Extent $StatementAst.Extent -Construct 'AssignmentStatementAst' -Message 'The script uses a top-level assignment.' -Hint 'Guard script-scope state with if (-not (Get-Variable -Name State -Scope Script -ErrorAction SilentlyContinue)) { $script:State = @{ ... } }, or initialize it lazily inside a function.'
                return
            }

            if ($StatementAst.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals)
            {
                Add-Finding -Extent $StatementAst.Extent -Construct 'AssignmentStatementAst' -Message "The script uses unsupported top-level operator '$($StatementAst.Operator)'." -Hint 'Use plain = assignment for script-scope state.'
                return
            }

            $target = $StatementAst.Left
            if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $target.Splatted -or
                -not ($target.VariablePath.IsUnqualified -or $target.VariablePath.IsScript))
            {
                Add-Finding -Extent $target.Extent -Construct $target.GetType().Name -Message "The script assigns to unsupported target '$($target.Extent.Text)'." -Hint 'Assign only to unqualified or $script: variables at script scope; drive-qualified and member targets change state outside the script at import time.'
                return
            }

            Test-ImportSafeValueStatementAst -StatementAst $StatementAst.Right
            return
        }

        Add-Finding -Extent $StatementAst.Extent -Construct $StatementAst.GetType().Name -Message "The script contains unsupported top-level syntax '$($StatementAst.GetType().Name)'." -Hint $scriptScopeHint
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
            Add-Finding -Extent $StatementBlockAst.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
        }

        foreach ($statement in $StatementBlockAst.Statements)
        {
            Test-ImportSafeStatementAst -StatementAst $statement -AllowAssignment
        }
    }

    function Test-RegisterArgumentCompleterCommandAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandAst] $CommandAst
        )

        $ancestor = $CommandAst.Parent
        while ($null -ne $ancestor -and $ancestor -ne $Ast)
        {
            if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script registers a completer from inside a nested function or script block.' -Hint 'Move the Register-ArgumentCompleter call to script scope; Import-CompleterScript only captures script-scope registrations.'
                return
            }

            $ancestor = $ancestor.Parent
        }

        $currentParameter = $null
        $seenParameters = [ordered] @{}

        foreach ($commandElement in ($CommandAst.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -notin 'CommandName', 'ParameterName', 'Native', 'ScriptBlock')
                {
                    Add-Finding -Extent $commandElement.Extent -Construct 'CommandParameterAst' -Message "The script uses unsupported Register-ArgumentCompleter parameter '-$($commandElement.ParameterName)'." -Hint 'Use only -CommandName, -ParameterName, -Native, and -ScriptBlock.'
                    return
                }

                if ($null -ne $commandElement.Argument)
                {
                    if ($commandElement.ParameterName -eq 'Native')
                    {
                        Add-Finding -Extent $commandElement.Extent -Construct 'CommandParameterAst' -Message 'The script uses an argument for -Native.' -Hint 'Use the bare -Native switch.'
                        return
                    }

                    Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement.Argument -ParameterName $commandElement.ParameterName
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
                Add-Finding -Extent $commandElement.Extent -Construct 'VariableExpressionAst' -Message 'The script uses argument splatting for Register-ArgumentCompleter.' -Hint 'Spell out -CommandName, -ParameterName or -Native, and -ScriptBlock explicitly.'
                return
            }

            if ([string]::IsNullOrWhiteSpace($currentParameter))
            {
                Add-Finding -Extent $commandElement.Extent -Construct $commandElement.GetType().Name -Message 'The script uses positional Register-ArgumentCompleter arguments.' -Hint 'Name every argument: -CommandName, -ParameterName or -Native, and -ScriptBlock.'
                return
            }

            Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement -ParameterName $currentParameter
            $currentParameter = $null
        }

        if (-not [string]::IsNullOrWhiteSpace($currentParameter))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message "The script is missing the argument for -$currentParameter." -Hint "Supply a literal value after -$currentParameter."
            return
        }

        if (-not $seenParameters.Contains('CommandName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script is missing -CommandName in a Register-ArgumentCompleter call.' -Hint 'Add -CommandName with a literal command name or a literal array of command names.'
        }

        if (-not $seenParameters.Contains('ScriptBlock'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script is missing -ScriptBlock in a Register-ArgumentCompleter call.' -Hint 'Add -ScriptBlock with a literal { ... } script block.'
        }

        if ($seenParameters.Contains('Native') -and $seenParameters.Contains('ParameterName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script combines -Native and -ParameterName.' -Hint 'Use -Native for a native command completer or -ParameterName for a command parameter completer, not both.'
        }

        if (-not $seenParameters.Contains('Native') -and -not $seenParameters.Contains('ParameterName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script does not identify whether the completer is native or parameter-based.' -Hint 'Add -Native for a native command completer or -ParameterName for a command parameter completer.'
        }
    }

    foreach ($usingStatement in @($Ast.UsingStatements))
    {
        if ($usingStatement.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Namespace)
        {
            Add-Finding -Extent $usingStatement.Extent -Construct 'UsingStatementAst' -Message "The script uses a 'using $($usingStatement.UsingStatementKind.ToString().ToLowerInvariant())' statement." -Hint 'Remove the using statement; only using namespace is supported. Load the module or assembly lazily inside a function with Import-Module or Add-Type.'
        }
    }

    if ($null -ne $Ast.ScriptRequirements)
    {
        if ($Ast.ScriptRequirements.RequiredModules.Count -gt 0)
        {
            Add-Finding -Extent $Ast.Extent -Construct 'ScriptRequirements' -Message "The script uses a '#requires -Modules' directive." -Hint 'Remove the directive; the required modules are imported, and their top-level code executes, when the script is dot-sourced. Import the module lazily inside a function instead.'
        }

        if ($Ast.ScriptRequirements.RequiredAssemblies.Count -gt 0)
        {
            Add-Finding -Extent $Ast.Extent -Construct 'ScriptRequirements' -Message "The script uses a '#requires -Assembly' directive." -Hint 'Remove the directive; the required assemblies are loaded when the script is dot-sourced. Load the assembly lazily inside a function with Add-Type instead.'
        }
    }

    foreach ($namedBlock in @($Ast.ParamBlock, $Ast.BeginBlock, $Ast.ProcessBlock, $Ast.DynamicParamBlock, $Ast.CleanBlock))
    {
        if ($null -ne $namedBlock)
        {
            Add-Finding -Extent $namedBlock.Extent -Construct $namedBlock.GetType().Name -Message "The script contains unsupported top-level syntax '$($namedBlock.GetType().Name)'." -Hint 'Remove the param, begin, process, dynamicparam, or clean block; a completer script is a flat script that defines functions and registers completers.'
        }
    }

    if ($Ast.EndBlock.Traps.Count -ne 0)
    {
        Add-Finding -Extent $Ast.EndBlock.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
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

    foreach ($functionOverride in $functionOverrides)
    {
        Add-Finding -Extent $functionOverride.Extent -Construct 'FunctionDefinitionAst' -Message "The script defines its own $($functionOverride.Name) function." -Hint "Rename the function; Import-CompleterScript only supports scripts that call the built-in $($functionOverride.Name) directly."
    }

    $dotSourcedCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            },
            $true
        ))

    foreach ($dotSourcedCommand in $dotSourcedCommands)
    {
        Add-Finding -Extent $dotSourcedCommand.Extent -Construct 'CommandAst' -Message 'The script dot-sources another script.' -Hint 'Inline the dot-sourced content, or move the dot-source into a function that the completer calls lazily; Import-CompleterScript only supports self-contained completer scripts.'
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
        Add-Finding -Extent $Ast.Extent -Construct 'ScriptBlockAst' -Message 'The script does not contain a Register-ArgumentCompleter call.' -Hint 'Add a script-scope Register-ArgumentCompleter call with -CommandName, -ScriptBlock, and either -Native or -ParameterName.'
    }

    foreach ($registerCommand in $registerCommands)
    {
        Test-RegisterArgumentCompleterCommandAst -CommandAst $registerCommand
    }

    return $findings.ToArray()
}
