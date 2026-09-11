<#
.SYNOPSIS
Checks completer scripts against the strict import grammar and reports findings.

.DESCRIPTION
Parses one or more completer scripts and runs the same validation that
Import-CompleterScript applies before it executes a script. Instead of stopping
at the first problem, the command returns one
CompleterActions.CompleterScriptFinding record per unsupported construct with
the line and column, the construct type, a message, and a hint that describes
how to change the script so it imports under the strict tier.

A conforming script produces no output, so a conformance test can assert that
the command returns nothing, or filter on Severity the way the strict importer
does. A script that cannot be parsed yields one finding per parse error and is
not checked further. Test-CompleterScript never executes the script.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompleterScriptFinding records with Path, Line,
Column, Severity, Construct, Message, and Hint properties. Every finding the
strict grammar produces has Severity 'Error'.

.EXAMPLE
PS> Test-CompleterScript -Path .\tool_completer.ps1

Reports each construct that keeps the script from importing under the strict
tier, or nothing when the script conforms.

.EXAMPLE
PS> Get-ChildItem -Path ~\Completers -Recurse -Filter *.ps1 | Test-CompleterScript | Where-Object Severity -eq Error

Runs the conformance check over a completer repository. The pipeline is empty
when every script conforms.
#>
function Test-CompleterScript
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                Get-CompleterScriptFinding -LiteralPath $resolvedPath
            }
        }
        catch
        {
            throw "Failed to test completer script. $($_.Exception.Message)"
        }
    }
}
