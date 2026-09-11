<#
.SYNOPSIS
Decides whether a completer target can be registered over the current managed and runtime state.

.DESCRIPTION
Reconciles the target through Resolve-CompleterRegistrationState and applies
the module's replacement rules in one place. Without -Force an existing managed
record blocks the registration when it is stale, when its lazy load failed, or
when it describes a different completer, and an unmanaged runtime registration
blocks it as well. A managed record that already describes the same completer,
the same script block text for an eager registration or the same script and
tier for a lazy one, is reported as existing so the caller can reuse it.
Register-CompleterRegistration throws the reported problem and
Resolve-CompleterSetEntry collects it, so a completer set is validated against
the same rules its registrations are held to.

.PARAMETER Target
The resolved completer target. It must expose Key and RuntimeKey.

.PARAMETER ScriptText
The text of the script block being registered eagerly, compared against an
existing managed record.

.PARAMETER ScriptPath
The script a lazy registration loads, compared against an existing managed
record.

.PARAMETER Trusted
The tier a lazy registration loads under, compared against an existing managed
record.

.PARAMETER Lazy
Indicates a lazy registration, which matches an existing record by ScriptPath
and Trusted rather than by script text.

.PARAMETER Force
Indicates that existing registrations are replaced, so nothing is reported as
a problem.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns an object with Key, ManagedRegistration, RuntimeRegistration,
IsExisting (the managed record already describes this completer), and Problem
(the message that blocks the registration, or null).
#>
function Resolve-CompleterRegistrationConflict
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter()]
        [string] $ScriptText,

        [Parameter()]
        [string] $ScriptPath,

        [Parameter()]
        [switch] $Trusted,

        [Parameter()]
        [switch] $Lazy,

        [Parameter()]
        [switch] $Force
    )

    $registrationState = Resolve-CompleterRegistrationState -Key $Target.Key
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
                $problem = "The module-managed completer registration for '$($Target.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
            }
            elseif ($registrationState.ManagedState -eq 'Failed')
            {
                $problem = "The module-managed completer registration for '$($Target.RuntimeKey)' failed to load '$($existingManagedRegistration.ScriptPath)': $($existingManagedRegistration.LoadError) Use -Force to retry the lazy load."
            }
            else
            {
                $isExisting = if ($Lazy)
                {
                    $existingManagedRegistration.ScriptPath -eq $ScriptPath -and [bool] $existingManagedRegistration.Trusted -eq [bool] $Trusted
                }
                else
                {
                    $existingManagedRegistration.ScriptText -eq $ScriptText
                }

                if (-not $isExisting)
                {
                    $problem = "A module-managed completer registration already exists for '$($Target.RuntimeKey)'. Use -Force to replace it."
                }
            }
        }
        elseif ($null -ne $existingRuntimeRegistration)
        {
            $problem = "A runtime completer registration already exists for '$($Target.RuntimeKey)'. Use -Force to replace it."
        }
    }

    return [pscustomobject] [ordered] @{
        Key                 = [string] $Target.Key
        ManagedRegistration = $existingManagedRegistration
        RuntimeRegistration = $existingRuntimeRegistration
        IsExisting          = $isExisting
        Problem             = $problem
    }
}
