function Remove-ManagedCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes in-memory module state for higher-level callers.')]
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

    $removedRegistration = $registrations[$resolvedKey]
    $registrations.Remove($resolvedKey)

    return $removedRegistration
}
