<#
.SYNOPSIS
Reconciles a managed registration record with the live runtime value for a target.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for a
normalized key and reports whether the managed record still describes what
PowerShell is actually using. A managed record is authoritative only while the
runtime holds the same script block, or a script block with identical text.
When the runtime value was replaced or removed outside this module, the managed
record is reported as stale so public commands can surface the live value,
refuse silent reuse, and apply the unmanaged-removal gate.

.PARAMETER Key
The normalized or runtime key for the completer target to reconcile.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns an object with ManagedRegistration, RuntimeRegistration, and
ManagedState ('None', 'Active', or 'Stale') properties. The registration
properties hold the exact stored objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Key 'get-item:path'

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.
#>
function Resolve-CompleterRegistrationState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    $managedRegistration = Find-ManagedCompleterRegistration -Key $Key
    $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $Key

    $managedState = if ($null -eq $managedRegistration)
    {
        'None'
    }
    elseif ($null -ne $runtimeRegistration -and
        ([object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock) -or
            $managedRegistration.ScriptText -eq $runtimeRegistration.ScriptText))
    {
        'Active'
    }
    else
    {
        'Stale'
    }

    return [pscustomobject] [ordered] @{
        Key                 = $Key
        ManagedRegistration = $managedRegistration
        RuntimeRegistration = $runtimeRegistration
        ManagedState        = $managedState
    }
}
