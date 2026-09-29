<#
.SYNOPSIS
Reconciles the statically resolved entries of one completer set with the session's registrations.

.DESCRIPTION
The session phase of a set import. For each entry that
Resolve-CompleterSetEntry produced, in set order, it builds the Pending
records, one lazy stub per target, and holds them to the rules
Register-Completer applies through Resolve-CompleterRegistrationConflict
against the snapshot the whole set shares. A target that already carries a
different registration is a Conflict problem unless -Force is given, and a
target that an earlier valid entry of the same set already claimed is always
a DuplicateTarget problem. An entry with no problem claims its targets for
the entries after it. The entry's Registrations and Conflicts are what
Import-CompleterSet writes, so the session's registrations are read once per
set.

Every target of the set is reconciled with the session in one
Resolve-CompleterRegistrationState pass, in set order. Each entry's conflicts
are then decided on its own slice of that pass, so an entry is planned
exactly as if it were resolved alone and a target two entries share stays a
DuplicateTarget problem, not a conflict with the earlier entry. When no entry
resolved a target there is nothing to reconcile and no pass is made.

Each entry record is completed in place: Registrations and Conflicts are
filled, the session problems are appended after the entry's static ones, and
IsValid is recomputed.

.PARAMETER Entry
The CompleterActions.CompleterSetEntry records of one set, in set order.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot, shared by every entry of
the set, that the entries' targets are reconciled against.

.PARAMETER Force
Indicates that the set is imported with -Force, so existing registrations for
its targets are replaced rather than reported.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns each entry record, in set order, with Registrations, the Conflicts
resolved for them in the same order, Problems, and IsValid.
#>
function Resolve-CompleterSetRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Entry,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    $entryRegistrations = [System.Collections.Generic.List[object]]::new()
    $keys = [System.Collections.Generic.List[string]]::new()

    foreach ($entryItem in $Entry)
    {
        $registrations = @(
            foreach ($target in @($entryItem.Targets))
            {
                New-CompleterRegistrationRecord -Target $target -ScriptBlock (New-CompleterLazyStub -Key $target.Key) -Source 'Managed' -State 'Pending' -ScriptPath $entryItem.Path -Trusted:$entryItem.Trusted
            }
        )

        $entryRegistrations.Add($registrations)

        foreach ($registration in $registrations)
        {
            $keys.Add([string] $registration.Key)
        }
    }

    $registrationStates = @()

    if ($keys.Count -gt 0)
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Key $keys.ToArray() -Snapshot $Snapshot)
    }

    $claimedTargets = @{}
    $stateIndex = 0

    for ($entryIndex = 0; $entryIndex -lt $Entry.Count; $entryIndex++)
    {
        $entryItem = $Entry[$entryIndex]
        $problems = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($problem in $entryItem.Problems)
        {
            $problems.Add($problem)
        }

        $targets = @($entryItem.Targets)
        $registrations = $entryRegistrations[$entryIndex]
        $conflicts = @()

        if ($registrations.Count -gt 0)
        {
            $stateSlice = $registrationStates[$stateIndex..($stateIndex + $registrations.Count - 1)]
            $stateIndex += $registrations.Count
            $conflicts = @(Resolve-CompleterRegistrationConflict -Registration $registrations -RegistrationState $stateSlice -Force:$Force)
        }

        for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++)
        {
            $target = $targets[$targetIndex]

            if ($null -ne $conflicts[$targetIndex].Problem)
            {
                $problems.Add(@{ Kind = 'Conflict'; Message = $conflicts[$targetIndex].Problem })
            }

            if ($claimedTargets.Contains([string] $target.Key))
            {
                $problems.Add(@{ Kind = 'DuplicateTarget'; Message = "Target '$($target.RuntimeKey)' is also listed by entry $($claimedTargets[[string] $target.Key])." })
            }
        }

        if ($problems.Count -eq 0)
        {
            foreach ($target in $targets)
            {
                $claimedTargets[[string] $target.Key] = $entryItem.Index
            }
        }

        $entryItem.Registrations = $registrations
        $entryItem.Conflicts = $conflicts
        $entryItem.Problems = @($problems)
        $entryItem.IsValid = $problems.Count -eq 0
        $entryItem
    }
}
