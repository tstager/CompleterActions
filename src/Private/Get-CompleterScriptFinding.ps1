<#
.SYNOPSIS
Parses a completer script and returns its strict-grammar findings.

.DESCRIPTION
Runs the validation shared by Test-CompleterScript and Import-CompleterScript.
A script that fails to parse yields one finding per parse error and is not
checked further; a script that parses is validated against the strict import
grammar by Test-CompleterScriptAst. A conforming script produces no output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Get-CompleterScriptFinding
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
        foreach ($parseError in $parseResult.ParseErrors)
        {
            New-CompleterScriptFinding -Path $LiteralPath -Extent $parseError.Extent -Construct 'ParseError' -Message $parseError.Message -Hint 'Fix the syntax error; the completer shape is only checked once the script parses.'
        }

        return
    }

    Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $LiteralPath
}
