<#
.SYNOPSIS
Verifies every entry of one completer set and finds the scripts it does not list.

.DESCRIPTION
The per-entry work Test-CompleterSet and Update-CompleterSet share, so both
judge a set alike. Each entry goes through Resolve-CompleterSetEntry -Verify,
the static phase of an import with the fast path turned off, so a strict
script is parsed once and its current hash and targets come from that one
parse. A trusted script is never parsed; its hash is read from the file.

The duplicate-target check follows import's claiming rule without the session:
entries are walked in set order, an entry with no problem claims its targets,
and a later entry that lists a claimed target gets import's duplicate text as
a DuplicateTarget problem. An entry with a problem, such as a malformed
target, still lists its targets for the check, as import does.

Last, every file under the set's directory that matches -Filter and that no
entry lists, hidden files included, is an unlisted script, compared
case-insensitively on Windows and case-sensitively elsewhere. A folder that
cannot be read stops the scan with a terminating error.

Each record is written as soon as it is made, so a caller in the same
pipeline handles every entry before the scan for unlisted scripts starts.
Every position comes from the parse in SetDefinition, so the set file is not
read again. Nothing here reads or writes the session's registrations or runs a
script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.OUTPUTS
CompleterActions.CompleterSetEntryState
CompleterActions.CompleterSetUnlistedScript
Returns one CompleterActions.CompleterSetEntryState per entry in set order,
with Entry, the record Resolve-CompleterSetEntry -Verify returned, RawEntry,
the entry as the set holds it, DuplicateTargetProblems, the entry's
DuplicateTarget problems as Kind and Message hashtables, and Extent, the
entry's positions from Get-CompleterSetEntryExtent. Then one
CompleterActions.CompleterSetUnlistedScript per unlisted script, sorted by
path, with Path, Message, the UnlistedScript text, and Extent, the position of
the set's Entries key.
#>
function Get-CompleterSetEntryState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Filter
    )

    $extents = Get-CompleterSetEntryExtent -Ast $SetDefinition.Ast
    $pathComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $listedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    $claimedTargets = @{}
    $entryIndex = 0

    foreach ($rawEntry in $SetDefinition.Entries)
    {
        $entryIndex++
        $entry = Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $SetDefinition.Directory -Verify
        $duplicateTargetProblems = [System.Collections.Generic.List[hashtable]]::new()

        if ($null -ne $entry.Path)
        {
            $null = $listedPaths.Add($entry.Path)
        }

        # $entry.Targets is the list import checks, so an entry with a problem,
        # such as a malformed target, can still report a duplicate.
        $entryTargets = @($entry.Targets)
        $targetIdentities = @($entryTargets | ForEach-Object { Get-CompleterTargetIdentity -Target $_ })

        for ($targetIndex = 0; $targetIndex -lt $entryTargets.Count; $targetIndex++)
        {
            $targetIdentity = $targetIdentities[$targetIndex]

            if ($claimedTargets.Contains($targetIdentity))
            {
                $duplicateTargetProblems.Add(@{ Kind = 'DuplicateTarget'; Message = "Target '$($entryTargets[$targetIndex].RuntimeKey)' is also listed by entry $($claimedTargets[$targetIdentity])." })
            }
        }

        if ($entry.Problems.Count -eq 0 -and $duplicateTargetProblems.Count -eq 0)
        {
            foreach ($targetIdentity in $targetIdentities)
            {
                $claimedTargets[$targetIdentity] = $entryIndex
            }
        }

        [pscustomobject] [ordered] @{
            PSTypeName              = 'CompleterActions.CompleterSetEntryState'
            Entry                   = $entry
            RawEntry                = $rawEntry
            DuplicateTargetProblems = $duplicateTargetProblems.ToArray()
            Extent                  = $extents.Entries[$entryIndex - 1]
        }
    }

    $unlistedScripts = @(
        Get-ChildItem -LiteralPath $SetDefinition.Directory -Filter $Filter -File -Recurse -Force -ErrorAction Stop |
            Where-Object { -not $listedPaths.Contains($_.FullName) } |
            Sort-Object -Property FullName
    )

    foreach ($unlistedScript in $unlistedScripts)
    {
        [pscustomobject] [ordered] @{
            PSTypeName = 'CompleterActions.CompleterSetUnlistedScript'
            Path       = $unlistedScript.FullName
            Message    = "The script '$($unlistedScript.FullName)' matches '$Filter', but no entry of the set lists it."
            Extent     = $extents.EntriesExtent
        }
    }
}
