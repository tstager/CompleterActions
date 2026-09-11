<#
.SYNOPSIS
Reconciles managed registration records with the live runtime values for one or more targets.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for
each normalized key and reports whether the managed record still describes
what PowerShell is actually using. A managed record is authoritative only
while the runtime holds the same script block, or a script block with
identical text; it is reported as 'Pending' when that script block is still a
lazy stub and 'Active' otherwise. A managed record whose lazy load failed is
reported as 'Failed' regardless of the runtime, because its runtime entry was
removed on purpose. When the runtime value was replaced or removed outside
this module, the managed record is reported as stale so public commands can
surface the live value, refuse silent reuse, and apply the unmanaged-removal
gate.

Every key is resolved against one snapshot of the managed table and the
runtime dictionaries, the one passed in or one taken here, so a batch of keys
costs a single runtime read. Discovered runtime values keep the key casing the
dictionary stores, native entries win over parameter entries with the same
key, and the states come back in the order of the keys.

.PARAMETER Key
The normalized or runtime keys for the completer targets to reconcile.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted the helper takes one for this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per key, in order, with ManagedRegistration,
RuntimeRegistration, and ManagedState ('None', 'Active', 'Pending', 'Failed',
or 'Stale') properties. The registration properties hold the exact stored
objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Key 'get-item:path'

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.

.EXAMPLE
PS> $states = Resolve-CompleterRegistrationState -Key $targets.Key -Snapshot $snapshot

Reconciles every target of a batch against one snapshot of the session.
#>
function Resolve-CompleterRegistrationState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($null -eq $Snapshot)
    {
        $Snapshot = Get-CompleterRegistrationSnapshot
    }

    foreach ($keyItem in $Key)
    {
        $normalizedKey = Get-CompleterRegistrationKey -RuntimeKey $keyItem
        $managedRegistration = if ($Snapshot.Managed.Contains($normalizedKey)) { $Snapshot.Managed[$normalizedKey] } else { $null }
        $runtimeRegistration = $null

        foreach ($view in $Snapshot.Runtime)
        {
            if (-not $view.Keys.ContainsKey($normalizedKey))
            {
                continue
            }

            $storedKey = $view.Keys[$normalizedKey]
            $target = if ($view.IsNative) { Resolve-CompleterTarget -RuntimeKey $storedKey -Native } else { Resolve-CompleterTarget -RuntimeKey $storedKey }
            $runtimeRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary -Key $storedKey) -Source 'Discovered'
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
        elseif ($null -ne $runtimeRegistration -and
            ([object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock) -or
                $managedRegistration.ScriptText -eq $runtimeRegistration.ScriptText))
        {
            if ($managedRegistration.State -eq 'Pending') { 'Pending' } else { 'Active' }
        }
        else
        {
            'Stale'
        }

        [pscustomobject] [ordered] @{
            Key                 = $keyItem
            ManagedRegistration = $managedRegistration
            RuntimeRegistration = $runtimeRegistration
            ManagedState        = $managedState
        }
    }
}
