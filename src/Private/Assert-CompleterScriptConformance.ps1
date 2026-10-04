<#
.SYNOPSIS
Throws when a completer script does not conform to the strict import grammar.

.DESCRIPTION
Runs Get-CompleterScriptFinding over a completer script and throws one error
that lists every Error finding with its line, column, construct, message, and
hint. Import-CompleterScript runs this gate under the strict tier, both for an
eager import and when a lazy stub loads its script on the first tab press, and
Register-Completer -Lazy runs it on the parse it derives the targets from, so
no strict path executes or registers a script the grammar rejects and every
path reports the same findings as Test-CompleterScript. A conforming script
returns without output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again; Register-Completer -Lazy passes the
parse it also derives the script's targets from.

.OUTPUTS
None
#>
function Assert-CompleterScriptConformance
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    $findings = @(Get-CompleterScriptFinding @PSBoundParameters | Where-Object -Property Severity -EQ -Value 'Error')

    if ($findings.Count -eq 0)
    {
        return
    }

    $findingLines = foreach ($finding in $findings)
    {
        'Line {0}, column {1} ({2}): {3} {4}' -f $finding.Line, $finding.Column, $finding.Construct, $finding.Message, $finding.Hint
    }

    throw "Completer script '$LiteralPath' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is.$([Environment]::NewLine)$($findingLines -join [Environment]::NewLine)"
}
