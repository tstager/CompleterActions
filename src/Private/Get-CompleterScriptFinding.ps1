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

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again, so a caller that also derives the
script's targets from the same parse reads the file once.

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
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    if (-not $PSBoundParameters.ContainsKey('ParseResult'))
    {
        $ParseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    }

    if ($ParseResult.ParseErrors.Count -gt 0)
    {
        foreach ($parseError in $ParseResult.ParseErrors)
        {
            New-CompleterScriptFinding -Path $LiteralPath -Extent $parseError.Extent -Construct 'ParseError' -Message $parseError.Message -Hint 'Fix the syntax error; the completer shape is only checked once the script parses.'
        }

        return
    }

    Test-CompleterScriptAst -Ast $ParseResult.Ast -LiteralPath $LiteralPath
}
