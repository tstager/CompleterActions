<#
.SYNOPSIS
Registers the targets of one validated completer set entry lazily.

.DESCRIPTION
Import-CompleterSet calls this helper once per valid entry, after every entry
in the set has been validated, and it is the single place where a set entry
becomes managed registrations. The entry's script is registered through
Register-CompleterRegistration -Lazy under the entry's trust tier, so the
script is not executed until the first tab press for one of its targets. A
trusted entry names its targets explicitly because a trusted script is not
parsed; a strict entry lets the lazy path derive them from the script, which
validation has already matched against the entry.

.PARAMETER Entry
A valid CompleterActions.CompleterSetEntry record from Resolve-CompleterSetEntry.

.PARAMETER Force
Replaces existing managed or runtime registrations for the entry's targets.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the CompleterActions.CompleterRegistration records that were created
or reused.
#>
function Register-CompleterSetEntry
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Entry,

        [Parameter()]
        [switch] $Force
    )

    $registerParameters = @{
        LiteralPath = $Entry.Path
        Lazy        = $true
        Trusted     = $Entry.Trusted
        Force       = $Force
        PassThru    = $true
        Confirm     = $false
    }

    if (-not $Entry.Trusted)
    {
        Register-CompleterRegistration @registerParameters
        return
    }

    $nativeTargets = @($Entry.Targets | Where-Object -Property IsNative -EQ -Value $true)

    if ($nativeTargets.Count -gt 0)
    {
        Register-CompleterRegistration @registerParameters -CommandName @($nativeTargets.CommandName) -Native
    }

    foreach ($parameterGroup in @($Entry.Targets | Where-Object -Property IsNative -EQ -Value $false | Group-Object -Property ParameterName))
    {
        Register-CompleterRegistration @registerParameters -CommandName @($parameterGroup.Group.CommandName) -ParameterName $parameterGroup.Name
    }
}
