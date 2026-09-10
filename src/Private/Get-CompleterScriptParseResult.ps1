<#
.SYNOPSIS
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope. Parse
errors are returned on the result rather than thrown, so callers can report
them as findings.

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

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
