<#
.SYNOPSIS
Decides whether each of a batch of completer registrations can be written over the current managed and runtime state.

.DESCRIPTION
Reconciles the records through one Resolve-CompleterRegistrationState pass and
applies the module's replacement rules in one place. Without -Force an
existing managed record blocks a registration when it is stale, when its lazy
load failed, or when it describes a different completer, and an unmanaged
runtime registration blocks it as well. A managed record that already
describes the same completer, the same script block text for an eager
registration or the same script and tier for a lazy one, is reported as
existing so the caller can reuse it. A record is lazy when its State is
'Pending'.

The records are resolved in order as if each earlier record of the same call
had already been written: a later record for the same key sees the earlier
one as the managed and runtime registration, so repeating a target within one
call reuses or replaces the first registration exactly as two calls would.
Register-Completer resolves one record at a time, after the
earlier targets of its call have been written, and throws the reported
problem; Resolve-CompleterSetEntry resolves an entry's records together and
collects the problems, so a completer set is validated against the same rules
its registrations are held to.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records that are about to be
written, in the order they will be written.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted, one is taken for this call.

.PARAMETER Force
Indicates that existing registrations are replaced, so nothing is reported as
a problem.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per record, in order, with Key, ManagedRegistration,
RuntimeRegistration, IsExisting (the managed record already describes this
completer), and Problem (the message that blocks the registration, or null).
#>
function Resolve-CompleterRegistrationConflict
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    if ($Registration.Count -eq 0)
    {
        return
    }

    $registrationStates = @(Resolve-CompleterRegistrationState -Key @($Registration | ForEach-Object { [string] $_.Key }) -Snapshot $Snapshot)
    $plannedRegistrations = @{}

    for ($index = 0; $index -lt $Registration.Count; $index++)
    {
        $registrationItem = $Registration[$index]
        $registrationState = $registrationStates[$index]
        $key = [string] $registrationItem.Key

        if ($plannedRegistrations.Contains($key))
        {
            $plannedRegistration = $plannedRegistrations[$key]
            $registrationState = [pscustomobject] [ordered] @{
                Key                 = $key
                ManagedRegistration = $plannedRegistration
                RuntimeRegistration = New-CompleterRegistrationRecord -Target $plannedRegistration -ScriptBlock $plannedRegistration.ScriptBlock -Source 'Discovered'
                ManagedState        = $plannedRegistration.State
            }
        }

        $existingManagedRegistration = $registrationState.ManagedRegistration
        $existingRuntimeRegistration = $registrationState.RuntimeRegistration
        $isExisting = $false
        $problem = $null

        if (-not $Force)
        {
            if ($null -ne $existingManagedRegistration)
            {
                if ($registrationState.ManagedState -eq 'Stale')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
                }
                elseif ($registrationState.ManagedState -eq 'Failed')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' failed to load '$($existingManagedRegistration.ScriptPath)': $($existingManagedRegistration.LoadError) Use -Force to retry the lazy load."
                }
                else
                {
                    $isExisting = if ($registrationItem.State -eq 'Pending')
                    {
                        $existingManagedRegistration.ScriptPath -eq $registrationItem.ScriptPath -and [bool] $existingManagedRegistration.Trusted -eq [bool] $registrationItem.Trusted
                    }
                    else
                    {
                        $existingManagedRegistration.ScriptText -eq $registrationItem.ScriptText
                    }

                    if (-not $isExisting)
                    {
                        $problem = "A module-managed completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
                    }
                }
            }
            elseif ($null -ne $existingRuntimeRegistration)
            {
                $problem = "A runtime completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
            }
        }

        if ($null -eq $problem)
        {
            $plannedRegistrations[$key] = if ($isExisting) { $existingManagedRegistration } else { $registrationItem }
        }

        [pscustomobject] [ordered] @{
            Key                 = $key
            ManagedRegistration = $existingManagedRegistration
            RuntimeRegistration = $existingRuntimeRegistration
            IsExisting          = $isExisting
            Problem             = $problem
        }
    }
}
