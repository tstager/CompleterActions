<#
.SYNOPSIS
Gets completer registrations known to the module or discovered at runtime.

.DESCRIPTION
Returns completer registration records for all registrations, a specific
registration key, a native command completer, or a command parameter
completer. By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target.

.PARAMETER Key
Gets the registration that matches a specific registration key.

.PARAMETER CommandName
Limits results to a specific command name for native or command-parameter
completers.

.PARAMETER ParameterName
Limits results to a specific parameter completer target.

.PARAMETER Native
Indicates that the lookup target is a native command completer instead of a
command parameter completer.

.PARAMETER ManagedOnly
Returns only registrations tracked by this module.

.PARAMETER DiscoveredOnly
Returns only registrations discovered from the current PowerShell runtime.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-CompleterRegistration -ManagedOnly

Lists only completer registrations that were registered through this module.
#>
function Get-CompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native,

        [Parameter()]
        [switch] $ManagedOnly,

        [Parameter()]
        [switch] $DiscoveredOnly
    )

    if ($ManagedOnly -and $DiscoveredOnly)
    {
        throw 'ManagedOnly and DiscoveredOnly cannot be used together.'
    }

    $managedRegistrations = @()
    $discoveredRegistrations = @()

    if (-not $DiscoveredOnly)
    {
        $managedRegistrations = switch ($PSCmdlet.ParameterSetName)
        {
            'All' { @(Find-ManagedCompleterRegistration) }
            'ByKey' { @(Find-ManagedCompleterRegistration -Key $Key) }
            'Native' { @(Find-ManagedCompleterRegistration -CommandName $CommandName -Native) }
            'CommandParameter' { @(Find-ManagedCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName) }
        }
    }

    if (-not $ManagedOnly)
    {
        $discoveredRegistrations = switch ($PSCmdlet.ParameterSetName)
        {
            'All' { @(Find-RuntimeCompleterRegistration) }
            'ByKey' { @(Find-RuntimeCompleterRegistration -Key $Key) }
            'Native' { @(Find-RuntimeCompleterRegistration -CommandName $CommandName -Native) }
            'CommandParameter' { @(Find-RuntimeCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName) }
        }
    }

    $registrationsByKey = [ordered] @{}

    foreach ($registration in $managedRegistrations)
    {
        if ($null -eq $registration)
        {
            continue
        }

        $registrationsByKey[[string] $registration.Key] = $registration
    }

    foreach ($registration in $discoveredRegistrations)
    {
        if ($null -eq $registration)
        {
            continue
        }

        if (-not $registrationsByKey.Contains([string] $registration.Key))
        {
            $registrationsByKey[[string] $registration.Key] = $registration
        }
    }

    return $registrationsByKey.Values
}
