<#
.SYNOPSIS
Reconciles managed registration records with the live runtime values for one or more targets.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for
each target and reports whether the managed record still describes what
PowerShell is actually using. A target is identified by its Key together with
its kind: a native target is looked up only in the native runtime dictionary
and a parameter target only in the custom one, and the managed record is
found by Get-CompleterTargetIdentity, so a native command named
'Get-Thing:Name' and the parameter target Get-Thing / Name never resolve to
each other's registrations.

A managed record is authoritative only while the runtime holds the very same
script block object. Equal text is not ownership: two closures with the same
text run with different captured values, and text that differs only in case
can complete differently. The record is reported as 'Pending' when that
script block is still a lazy stub and 'Active' otherwise. A managed record
whose lazy load failed is reported as 'Failed' regardless of the runtime,
because its runtime entry was removed on purpose. When the runtime value was
replaced, even by a script block with the same text, or removed outside this
module, the managed record is reported as stale so public commands can
surface the live value, refuse silent reuse, and apply the unmanaged-removal
gate.

Every target is resolved against one snapshot of the managed table and the
runtime dictionaries, the one passed in or one taken here, so a batch of
targets costs a single runtime read. Discovered runtime values keep the key
casing the dictionary stores, and the states come back in the order of the
targets.

.PARAMETER Target
The completer targets or registration records to reconcile. Each must expose
Key, RuntimeKey, and IsNative.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted the helper takes one for this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per target, in order, with Key (the target's Key),
ManagedRegistration, RuntimeRegistration, and ManagedState ('None', 'Active',
'Pending', 'Failed', or 'Stale') properties. The registration properties hold
the exact stored objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Target (Resolve-CompleterTarget -CommandName 'Get-Item' -ParameterName 'Path')

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.

.EXAMPLE
PS> $states = Resolve-CompleterRegistrationState -Target $registrations -Snapshot $snapshot

Reconciles every record of a batch against one snapshot of the session.
#>
function Resolve-CompleterRegistrationState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [psobject[]] $Target,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($null -eq $Snapshot)
    {
        $Snapshot = Get-CompleterRegistrationSnapshot
    }

    foreach ($targetItem in $Target)
    {
        $identity = Get-CompleterTargetIdentity -Target $targetItem
        $isNative = [bool] $targetItem.IsNative
        $managedRegistration = if ($Snapshot.Managed.Contains($identity)) { $Snapshot.Managed[$identity] } else { $null }
        $runtimeRegistration = $null

        foreach ($view in $Snapshot.Runtime)
        {
            if ([bool] $view.IsNative -ne $isNative -or -not $view.Keys.ContainsKey([string] $targetItem.RuntimeKey))
            {
                continue
            }

            $storedKey = $view.Keys[[string] $targetItem.RuntimeKey]
            $storedTarget = if ($isNative) { Resolve-CompleterTarget -RuntimeKey $storedKey -Native } else { Resolve-CompleterTarget -RuntimeKey $storedKey }
            $runtimeRegistration = New-CompleterRegistrationRecord -Target $storedTarget -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary -Key $storedKey) -Source 'Discovered' -State Discovered
            break
        }

        $managedState = if ($null -eq $managedRegistration)
        {
            'None'
        }
        elseif ($managedRegistration.State -eq 'Failed')
        {
            'Failed'
        }
        elseif ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock))
        {
            if ($managedRegistration.State -eq 'Pending') { 'Pending' } else { 'Active' }
        }
        else
        {
            'Stale'
        }

        [pscustomobject] [ordered] @{
            Key                 = $targetItem.Key
            ManagedRegistration = $managedRegistration
            RuntimeRegistration = $runtimeRegistration
            ManagedState        = $managedState
        }
    }
}
