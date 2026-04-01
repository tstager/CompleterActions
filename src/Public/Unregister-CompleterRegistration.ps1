function Unregister-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByKey', ConfirmImpact = 'Medium')]
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
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    $lookup = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -Key $Key
                Runtime = Find-RuntimeCompleterRegistration -Key $Key
            }
            break
        }

        'Native'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -CommandName $CommandName -Native
                Runtime = Find-RuntimeCompleterRegistration -CommandName $CommandName -Native
            }
            break
        }

        'CommandParameter'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName
                Runtime = Find-RuntimeCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName
            }
            break
        }
    }

    $managedRegistration = $lookup['Managed']
    $runtimeRegistration = $lookup['Runtime']
    if ($null -ne $managedRegistration)
    {
        $registrationToRemove = $managedRegistration
    }
    elseif ($null -ne $runtimeRegistration)
    {
        if (-not $AllowUnmanaged)
        {
            throw "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed. Re-run with -AllowUnmanaged to remove the runtime registration."
        }

        $registrationToRemove = $runtimeRegistration
    }
    else
    {
        $registrationToRemove = $null
    }

    if ($null -eq $registrationToRemove)
    {
        throw 'No completer registration was found for the requested target.'
    }

    if (-not $PSCmdlet.ShouldProcess($registrationToRemove.RuntimeKey, 'Unregister completer registration'))
    {
        return
    }

    $removedRuntimeRegistration = $null
    $removedManagedRegistration = $null

    if ($null -ne $runtimeRegistration)
    {
        $removedRuntimeRegistration = Remove-RuntimeCompleterRegistration -Key $registrationToRemove.Key
    }

    if ($null -ne $managedRegistration)
    {
        $removedManagedRegistration = Remove-ManagedCompleterRegistration -Key $registrationToRemove.Key
    }

    if ($PassThru)
    {
        if ($null -ne $removedManagedRegistration)
        {
            return $removedManagedRegistration
        }

        return $removedRuntimeRegistration
    }
}
