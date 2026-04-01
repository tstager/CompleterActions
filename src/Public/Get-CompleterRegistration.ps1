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
