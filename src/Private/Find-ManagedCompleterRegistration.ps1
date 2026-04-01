function Find-ManagedCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
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
        [switch] $Native
    )

    $registrations = Get-ManagedCompleterRegistrationTable

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        return $registrations.Values
    }

    $resolvedKey = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey' { Get-CompleterRegistrationKey -RuntimeKey $Key }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Get-CompleterRegistrationKey -CommandName $CommandName -Native
        }
        'CommandParameter' { Get-CompleterRegistrationKey -CommandName $CommandName -ParameterName $ParameterName }
    }

    if (-not $registrations.Contains($resolvedKey))
    {
        return
    }

    return $registrations[$resolvedKey]
}
