<#
.SYNOPSIS
Derives the completer targets a strict-tier script registers without executing it.

.DESCRIPTION
Parses the script once and reads the literal -CommandName, -ParameterName, and
-Native arguments of every Register-ArgumentCompleter call from the AST,
resolving them into normalized completer targets. The strict import grammar
requires those arguments to be literal, so a conforming script's targets are
known without running it, and a script whose arguments cannot be read
statically is reported with the position of the offending argument. The
grammar itself does not run here; it runs through Import-CompleterScript when
the script loads, so registering a script lazily costs one parse rather than a
full conformance walk. Duplicate targets collapse to one record.

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
        $parseError = $parseResult.ParseErrors[0]
        throw "The script '$LiteralPath' does not parse, so its targets cannot be derived. Line $($parseError.Extent.StartLineNumber), column $($parseError.Extent.StartColumnNumber): $($parseError.Message)"
    }

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

            if ($argumentParameter -notin 'CommandName', 'ParameterName')
            {
                continue
            }

            try
            {
                $argumentValues = @([string[]] @($argumentAst.SafeGetValue()))
            }
            catch
            {
                throw "The script '$LiteralPath' does not use a literal -$argumentParameter argument at line $($argumentAst.Extent.StartLineNumber), column $($argumentAst.Extent.StartColumnNumber), so its targets cannot be derived without running it. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
            }

            if ($argumentParameter -eq 'CommandName')
            {
                $commandNames += $argumentValues
            }
            else
            {
                $parameterNames += $argumentValues
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

    if ($targetsByKey.Count -eq 0)
    {
        throw "The script '$LiteralPath' does not call Register-ArgumentCompleter with literal targets, so nothing can be registered lazily. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
    }

    return @($targetsByKey.Values)
}
