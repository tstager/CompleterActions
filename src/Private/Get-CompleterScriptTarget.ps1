<#
.SYNOPSIS
Derives the completer targets a strict-tier script registers without executing it.

.DESCRIPTION
Checks the script against the strict import grammar, then reads the literal
-CommandName, -ParameterName, and -Native arguments of every script-scope
Register-ArgumentCompleter call from the AST and resolves them into normalized
completer targets. The grammar guarantees that those arguments are literal, so
the targets a lazy registration will own are known at registration time
without running the script. Duplicate targets collapse to one record.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterTarget
#>
function Get-CompleterScriptTarget
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    Assert-CompleterScriptConformance -LiteralPath $LiteralPath

    $parseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    $registerCommands = @($parseResult.Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $true
        ))

    $targetsByKey = [ordered] @{}

    foreach ($registerCommand in $registerCommands)
    {
        $commandNames = @()
        $parameterNames = @()
        $isNative = $false
        $currentParameter = $null

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -eq 'Native')
                {
                    $isNative = $true
                    $currentParameter = $null
                    continue
                }

                if ($null -eq $commandElement.Argument)
                {
                    $currentParameter = $commandElement.ParameterName
                    continue
                }

                $argumentAst = $commandElement.Argument
                $argumentParameter = $commandElement.ParameterName
            }
            else
            {
                $argumentAst = $commandElement
                $argumentParameter = $currentParameter
            }

            $currentParameter = $null

            switch ($argumentParameter)
            {
                'CommandName' { $commandNames += @([string[]] @($argumentAst.SafeGetValue())) }
                'ParameterName' { $parameterNames += @([string[]] @($argumentAst.SafeGetValue())) }
            }
        }

        $targetParameters = @{
            CommandName = $commandNames
        }

        if ($isNative)
        {
            $targetParameters['Native'] = $true
        }
        else
        {
            $targetParameters['ParameterName'] = $parameterNames
        }

        foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
        {
            $targetsByKey[[string] $target.Key] = $target
        }
    }

    return @($targetsByKey.Values)
}
