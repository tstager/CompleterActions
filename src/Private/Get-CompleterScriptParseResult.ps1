<#
.SYNOPSIS
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterScriptParseResult
#>
function Get-CompleterScriptParseResult
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $LiteralPath,
        [ref] $tokens,
        [ref] $parseErrors
    )

    if ($parseErrors.Count -gt 0)
    {
        $errorSummary = @($parseErrors |
            Select-Object -First 3 |
            ForEach-Object {
                'line {0}, column {1}: {2}' -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
            }) -join '; '

        throw "Completer script '$LiteralPath' could not be parsed. $errorSummary"
    }

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
