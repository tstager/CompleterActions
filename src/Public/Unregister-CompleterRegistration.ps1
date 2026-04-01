<#
.SYNOPSIS
Removes a completer registration from runtime and, when applicable, module state.

.DESCRIPTION
Removes a completer registration identified by registration key, native command,
or command parameter target. Managed registrations are removed from both the
PowerShell runtime and the module's registration table. Runtime-only
registrations require -AllowUnmanaged before they can be removed.

.PARAMETER Key
Removes the registration that matches a specific registration key.

.PARAMETER CommandName
Specifies the command name whose completer should be removed.

.PARAMETER ParameterName
Specifies the parameter name for a command-parameter completer removal target.

.PARAMETER Native
Targets a native completer registration instead of a command parameter
completer.

.PARAMETER AllowUnmanaged
Allows removal of a runtime registration that is not tracked by this module.

.PARAMETER PassThru
Returns the registration record that was removed.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns the removed CompleterActions.CompleterRegistration
record.

.EXAMPLE
PS> Unregister-CompleterRegistration -CommandName 'Test-Tool' -ParameterName 'Name' -Confirm:$false

Removes the managed parameter completer for Test-Tool Name without prompting.

.EXAMPLE
PS> Unregister-CompleterRegistration -CommandName 'git' -Native -AllowUnmanaged -Confirm:$false -PassThru

Removes a native runtime completer for git even if it was not registered
through this module, and returns the removed record.
#>
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
