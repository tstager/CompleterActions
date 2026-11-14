<#
.SYNOPSIS
Removes a managed completer registration from module state.

.DESCRIPTION
Deletes a registration record from the module's in-memory registration table and
returns the removed record. Callers name the entry by a target or record, or by
command target details. Every removal names the target kind, because a native
target and a parameter target can share a Key; only the record of the named
kind is removed.

.PARAMETER Target
The completer target or registration record whose managed record to remove.
It must expose Key and IsNative.

.PARAMETER CommandName
The command or native executable name for the registration target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER Native
Indicates that the removal target is a native command completer.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the removed CompleterActions.CompleterRegistration record, if one existed.

.EXAMPLE
PS> Remove-ManagedCompleterRegistration -CommandName Get-Widget -ParameterName Name

Removes the managed registration record for a specific command parameter target
and returns the record that was deleted from module state.
#>
function Remove-ManagedCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'Target')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes in-memory module state for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

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
    $removalTarget = switch ($PSCmdlet.ParameterSetName)
    {
        'Target' { $Target }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
    }

    $identity = Get-CompleterTargetIdentity -Target $removalTarget

    if (-not $registrations.Contains($identity))
    {
        return
    }

    $removedRegistration = $registrations[$identity]
    $registrations.Remove($identity)

    return $removedRegistration
}
