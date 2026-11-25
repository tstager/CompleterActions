<#
.SYNOPSIS
Composes the lines of the markdown file New-CompleterScript -Documentation writes.

.DESCRIPTION
Returns one string per line, without line endings: the title '# <Name>
completer', the heading '## What it completes', and one sentence that names
the script file and every target in registration order, with a blank line
between them. Two targets are joined with 'and'; three or more with commas
and a final ', and'. The output names no date, version, or machine path, so
the same input always gives the same lines.

.PARAMETER Name
The primary command name, as given.

.PARAMETER ScriptName
The file name of the script, without its folder.

.PARAMETER Target
The target list from ConvertTo-CompleterTargetName.

.OUTPUTS
System.String
#>
function Get-CompleterScriptDocumentation
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ScriptName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Target
    )

    $names = @($Target | ForEach-Object { '`{0}`' -f $_ })

    $targetList = switch ($names.Count)
    {
        1 { $names[0] }
        2 { '{0} and {1}' -f $names[0], $names[1] }
        default { '{0}, and {1}' -f ($names[0..($names.Count - 2)] -join ', '), $names[-1] }
    }

    '# {0} completer' -f $Name
    ''
    '## What it completes'
    ''
    '`{0}` registers a native PowerShell completer for {1}.' -f $ScriptName, $targetList
}
