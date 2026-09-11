<#
.SYNOPSIS
Derives the completer targets a strict-tier script registers without running it.

.DESCRIPTION
Parses the script and reads the literal -CommandName, -ParameterName, and
-Native arguments of every Register-ArgumentCompleter call. The strict import
grammar guarantees those arguments are literal, so callers run
Get-CompleterScriptFinding first and only call this helper for a script with no
Error findings. Targets are expanded through Resolve-CompleterTargetList, so
one call that names several commands yields several targets, exactly as
Import-CompleterScript would emit them.

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

    $parseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath

    if ($parseResult.ParseErrors.Count -gt 0)
    {
        throw "Completer script '$LiteralPath' does not parse, so its targets cannot be derived."
    }

    $registerCommands = @($parseResult.Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $true
        ))

    foreach ($registerCommand in $registerCommands)
    {
        $commandNames = @()
        $parameterNames = @()
        $isNative = $false
        $currentParameter = $null

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            $parameterName = $currentParameter
            $valueAst = $commandElement
            $currentParameter = $null

            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -eq 'Native')
                {
                    $isNative = $true
                    continue
                }

                if ($null -eq $commandElement.Argument)
                {
                    $currentParameter = $commandElement.ParameterName
                    continue
                }

                $parameterName = $commandElement.ParameterName
                $valueAst = $commandElement.Argument
            }

            switch ($parameterName)
            {
                'CommandName'
                {
                    $commandNames = @($valueAst.SafeGetValue())
                    break
                }

                'ParameterName'
                {
                    $parameterNames = @($valueAst.SafeGetValue())
                    break
                }
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

        Resolve-CompleterTargetList @targetParameters
    }
}
