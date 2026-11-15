<#
.SYNOPSIS
Decides whether each of a batch of completer registrations can be written over the current managed and runtime state.

.DESCRIPTION
Reconciles the records through one Resolve-CompleterRegistrationState pass,
or through the states the caller already resolved for them, and applies the
module's replacement rules in one place. Without -Force an existing managed
record blocks a registration when it is stale, when its lazy load failed, or
when it describes a different completer that does not come from a new
instance of the module that registered it, and an unmanaged runtime
registration blocks it as well. A managed record that already describes the
same completer is reported as existing so the caller can reuse it. Script
paths compare the way the file system does: ignoring case on Windows and
macOS, and ordinally elsewhere, where two paths that differ only in case name
two files.

A record is imported when its script block is bound to the capture module
Import-CompleterScript created to run the record's ScriptPath under the
record's tier, as Get-CompleterImportModule finds it in the table the import
writes. Records that Import-CompleterScript emits and records a lazy load
activated are imported. A record that only names a ScriptPath is not, and
neither is one whose ImportModule property names the module its own script
block is bound to, such as a closure of an imported block: provenance comes
from the module's table, never from a property the caller can set.

A record is lazy when its State is 'Pending'. A lazy record describes the
same completer as a managed record that loads, or already loaded, the same
script under the same tier: a Pending record, or an imported record.

An eager record describes the same completer when it holds the very same
script block, or a script block with exactly the same text, compared case
sensitively, with the same ScriptPath and tier, defined in the same file and
bound to the same context. Two imported records of the same script are bound
to the same context, so importing and registering the same script again stays
a no-op although every import binds its script blocks to a new module. Any
other two script blocks are bound to the same context when they are bound to
the same module or to none. A closure is bound to a module of its own with a
unique name, so two closures never match even when their text is identical,
because they run with different captured values.

A script block with that same text, ScriptPath, tier and file that is bound to
another instance of a module with the same name, as when a module is imported
again, comes from the module that owns the managed record. It is not the same
completer, because the new instance holds its own state, so it is not reported
as existing, but it is not a problem either: it replaces the record from the
earlier instance without -Force.

The records are resolved in order as if each earlier record of the same call
had already been written: a later record for the same target sees the earlier
one as the managed and runtime registration, so repeating a target within one
call reuses or replaces the first registration exactly as two calls would.
Register-Completer resolves one record at a time, after the
earlier targets of its call have been written, and throws the reported
problem; Resolve-CompleterSetRegistration resolves an entry's records together and
collects the problems, so a completer set is validated against the same rules
its registrations are held to.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records that are about to be
written, in the order they will be written.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted, one is taken for this call.

.PARAMETER RegistrationState
The rows Resolve-CompleterRegistrationState already returned for these records,
one per record in the same order. When it is supplied no state pass is made
here, so a caller that resolves many batches against one snapshot can resolve
every key in one pass and hand each batch its slice.

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
        [AllowEmptyCollection()]
        [psobject[]] $RegistrationState,

        [Parameter()]
        [switch] $Force
    )

    if ($Registration.Count -eq 0)
    {
        return
    }

    $registrationStates = $RegistrationState

    if (-not $PSBoundParameters.ContainsKey('RegistrationState'))
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Target $Registration -Snapshot $Snapshot)
    }

    function Test-ImportedCompleterRecord
    {
        param(
            [psobject] $Record
        )

        $null -ne (Get-CompleterImportModule -ScriptBlock $Record.ScriptBlock -ScriptPath $Record.ScriptPath -Trusted ([bool] $Record.Trusted))
    }

    $plannedRegistrations = @{}
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    for ($index = 0; $index -lt $Registration.Count; $index++)
    {
        $registrationItem = $Registration[$index]
        $registrationState = $registrationStates[$index]
        $key = [string] $registrationItem.Key
        $identity = Get-CompleterTargetIdentity -Target $registrationItem

        if ($plannedRegistrations.Contains($identity))
        {
            $plannedRegistration = $plannedRegistrations[$identity]
            $registrationState = [pscustomobject] [ordered] @{
                Key                 = $key
                ManagedRegistration = $plannedRegistration
                RuntimeRegistration = New-CompleterRegistrationRecord -Target $plannedRegistration -ScriptBlock $plannedRegistration.ScriptBlock -Source 'Discovered' -State Discovered
                ManagedState        = $plannedRegistration.State
            }
        }

        $existingManagedRegistration = $registrationState.ManagedRegistration
        $existingRuntimeRegistration = $registrationState.RuntimeRegistration
        $isExisting = $false
        $isNewModuleInstance = $false
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
                    $isSameScript = [string]::Equals($existingManagedRegistration.ScriptPath, $registrationItem.ScriptPath, $pathComparison) -and
                        [bool] $existingManagedRegistration.Trusted -eq [bool] $registrationItem.Trusted
                    $isExistingImported = Test-ImportedCompleterRecord -Record $existingManagedRegistration
                    $isExisting = if ($registrationItem.State -eq 'Pending')
                    {
                        $isSameScript -and ($existingManagedRegistration.State -eq 'Pending' -or $isExistingImported)
                    }
                    else
                    {
                        $existingScriptBlock = $existingManagedRegistration.ScriptBlock
                        $newScriptBlock = $registrationItem.ScriptBlock
                        $existingModule = $existingScriptBlock.Module
                        $newModule = $newScriptBlock.Module
                        $isSameDefinition = [string]::Equals($existingManagedRegistration.ScriptText, $registrationItem.ScriptText, [System.StringComparison]::Ordinal) -and
                            $isSameScript -and
                            [string]::Equals($existingScriptBlock.File, $newScriptBlock.File, $pathComparison)
                        $isNewModuleInstance = $isSameDefinition -and
                            $null -ne $existingModule -and $null -ne $newModule -and
                            -not [object]::ReferenceEquals($existingModule, $newModule) -and
                            [string]::Equals($existingModule.Name, $newModule.Name, [System.StringComparison]::OrdinalIgnoreCase)

                        [object]::ReferenceEquals($existingScriptBlock, $newScriptBlock) -or (
                            $isSameDefinition -and (
                                ($isExistingImported -and (Test-ImportedCompleterRecord -Record $registrationItem)) -or
                                [object]::ReferenceEquals($existingModule, $newModule)))
                    }

                    if (-not $isExisting -and -not $isNewModuleInstance)
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
            $plannedRegistrations[$identity] = if ($isExisting) { $existingManagedRegistration } else { $registrationItem }
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
