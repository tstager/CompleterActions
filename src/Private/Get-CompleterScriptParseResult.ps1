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
The literal path to the completer script file. Every extent in the result names
it as its file, whether the text is read from disk or supplied.

.PARAMETER ScriptContents
The text of the script, already read from LiteralPath. When it is supplied the
file is not read again; Import-CompleterScript passes the contents it then
executes, so the grammar validates exactly what runs.

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
        [string] $LiteralPath,

        [Parameter()]
        [AllowEmptyString()]
        [string] $ScriptContents
    )

    $tokens = $null
    $parseErrors = $null
    $ast = if ($PSBoundParameters.ContainsKey('ScriptContents'))
    {
        [System.Management.Automation.Language.Parser]::ParseInput($ScriptContents, $LiteralPath, [ref] $tokens, [ref] $parseErrors)
    }
    else
    {
        [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $tokens, [ref] $parseErrors)
    }

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
