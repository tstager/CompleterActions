<#
.SYNOPSIS
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope. Parse
errors are returned on the result rather than thrown, so callers can report
them as findings. A file that cannot be read yields a single FileReadError.

.PARAMETER LiteralPath
The literal path to the completer script file. Every extent in the result names
it as its file, whether the text is read from disk or from Script.

.PARAMETER Script
The script's command information, already resolved from LiteralPath. When it is
supplied, the text it reads and keeps is parsed instead of the file, so
dot-sourcing the same object afterwards runs exactly the text that was parsed.
Import-CompleterScript passes it so the grammar validates what executes.

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
        [ValidateNotNull()]
        [System.Management.Automation.ExternalScriptInfo] $Script
    )

    $tokens = $null
    $parseErrors = $null
    $ast = if (-not $PSBoundParameters.ContainsKey('Script'))
    {
        [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $tokens, [ref] $parseErrors)
    }
    else
    {
        try
        {
            # Reading the ScriptContents property returns $null when the file cannot be read;
            # calling its getter raises the read failure instead.
            [System.Management.Automation.Language.Parser]::ParseInput($Script.get_ScriptContents(), $LiteralPath, [ref] $tokens, [ref] $parseErrors)
        }
        catch
        {
            # Report the failure exactly as ParseFile does: one FileReadError with no position.
            $noPosition = [System.Management.Automation.Language.ScriptPosition]::new($null, 0, 0, $null)
            $readError = [System.Management.Automation.Language.ParseError]::new(
                [System.Management.Automation.Language.ScriptExtent]::new($noPosition, $noPosition),
                'FileReadError',
                ('The file could not be read: {0}.' -f $_.Exception.GetBaseException().Message)
            )

            [System.Management.Automation.Language.Parser]::ParseInput('', $LiteralPath, [ref] $tokens, [ref] $parseErrors)
            $parseErrors = @($readError)
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
