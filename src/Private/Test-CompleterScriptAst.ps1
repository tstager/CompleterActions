<#
.SYNOPSIS
Validates that a completer script uses a supported import shape.

.DESCRIPTION
Checks the script AST for patterns that Import-CompleterScript can safely and
predictably import. Supported scripts must be self-contained, must call
Register-ArgumentCompleter at script scope, and must use literal values for the
registration target and script block. The walk runs in the compiled
CompleterActions.Internal.StrictGrammar class; every unsupported construct it
returns is reported as a CompleterActions.CompleterScriptFinding record, in the
order the walk found it. A conforming script produces no output.

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

    try
    {
        $grammarFindings = [CompleterActions.Internal.StrictGrammar]::Test($Ast)
    }
    catch
    {
        # A static-method exception arrives wrapped in a MethodInvocationException whose
        # message names the method; the base exception carries the walk's own text.
        throw $_.Exception.GetBaseException().Message
    }

    foreach ($grammarFinding in $grammarFindings)
    {
        New-CompleterScriptFinding -Path $LiteralPath -Extent $grammarFinding.Extent -Construct $grammarFinding.Construct -Message $grammarFinding.Message -Hint $grammarFinding.Hint
    }
}
