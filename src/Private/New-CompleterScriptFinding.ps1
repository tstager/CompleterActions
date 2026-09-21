<#
.SYNOPSIS
Creates a completer script validation finding.

.DESCRIPTION
Builds the CompleterActions.CompleterScriptFinding record shared by
Test-CompleterScript and Import-CompleterScript. Each finding pins one
unsupported construct to a source position and pairs the problem statement with
a hint that describes how to bring the script back inside the strict import
grammar.

.PARAMETER Path
The completer script path the finding belongs to.

.PARAMETER Extent
The script extent of the offending construct. The finding takes its line and
column from the start of the extent.

.PARAMETER Construct
The offending construct type, usually the AST node type name.

.PARAMETER Message
The problem statement.

.PARAMETER Hint
How to change the script so the finding goes away.

.PARAMETER Severity
'Error' for constructs the strict importer rejects, 'Warning' for constructs
that import but should be changed.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function New-CompleterScriptFinding
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a finding object.')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.IScriptExtent] $Extent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Construct,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Hint,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string] $Severity = 'Error'
    )

    [CompleterScriptFinding] @{
        Path       = $Path
        Line       = $Extent.StartLineNumber
        Column     = $Extent.StartColumnNumber
        Severity   = $Severity
        Construct  = $Construct
        Message    = $Message
        Hint       = $Hint
    }
}
