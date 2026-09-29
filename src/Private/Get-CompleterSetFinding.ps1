<#
.SYNOPSIS
Checks one completer set against the scripts on disk and returns its drift findings.

.DESCRIPTION
Runs the checks shared with Import-CompleterSet for every entry of a set that
Import-CompleterSetDefinition has read, and adds the checks only a drift
report needs. Each entry goes through Resolve-CompleterSetEntry -Verify, the
static phase of an import with the fast path turned off, so a strict script
is parsed once and its current hash and targets come from that one parse. A
trusted script is never parsed; its hash is read from the file.

The static phase's problems become MissingScript, InvalidEntry,
UnreadableTargets, and TargetMismatch findings with import's problem text.
DuplicateTarget follows import's claiming rule without the session: entries
are walked in set order, an entry with no Error finding claims its targets,
and a later entry that lists a claimed target gets import's duplicate text.
The declared Hash is then compared with the script's current hash
(HashMismatch), or reported as MissingHash or InvalidHash. Last, every file
under the set's directory that matches -Filter and that no entry lists, hidden
files included, is an UnlistedScript finding, compared case-insensitively on Windows and
case-sensitively elsewhere.

Nothing here reads or writes the session's registrations or runs a script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the findings in set order, each entry's in the order MissingScript,
InvalidEntry, UnreadableTargets, TargetMismatch, DuplicateTarget,
HashMismatch, MissingHash, InvalidHash, followed by the UnlistedScript
findings sorted by path. Path is the set file for every finding.
#>
function Get-CompleterSetFinding
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Filter
    )

    $regenerateHint = 'Regenerate the set with Export-CompleterSet.'
    $hints = @{
        MissingScript     = 'Restore the script or remove the entry, then regenerate the set.'
        InvalidEntry      = 'Fix the entry in the set, or regenerate the set with Export-CompleterSet.'
        UnreadableTargets = 'Run Test-CompleterScript on the script, or mark the entry Trusted and list its targets.'
        TargetMismatch    = 'Regenerate the set with Export-CompleterSet; a strict entry must list every target its script registers.'
    }
    $hints['DuplicateTarget'] = $hints['TargetMismatch']

    $setPath = $SetDefinition.Path
    $extents = Get-CompleterSetEntryExtent -LiteralPath $setPath
    $pathComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $listedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    $claimedTargets = @{}
    $entryIndex = 0

    foreach ($rawEntry in $SetDefinition.Entries)
    {
        $entryIndex++
        $entry = Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $SetDefinition.Directory -Verify
        $entryExtent = $extents.Entries[$entryIndex - 1]
        $findings = [System.Collections.Generic.List[object]]::new()

        if ($null -ne $entry.Path)
        {
            $null = $listedPaths.Add($entry.Path)
        }

        $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $entryIndex" } else { "Entry $entryIndex ('$($entry.DeclaredPath)')" }
        $entryStart = $entryExtent.Extent
        $pathStart = if ($null -ne $entryExtent.PathExtent) { $entryExtent.PathExtent } else { $entryStart }
        $hashStart = if ($null -ne $entryExtent.HashExtent) { $entryExtent.HashExtent } else { $entryStart }
        $targetsStart = if ($null -ne $entryExtent.TargetsExtent) { $entryExtent.TargetsExtent } else { $entryStart }
        $problemExtents = @{
            MissingScript     = $pathStart
            InvalidEntry      = $entryStart
            UnreadableTargets = $pathStart
            TargetMismatch    = $targetsStart
        }

        foreach ($kind in 'MissingScript', 'InvalidEntry', 'UnreadableTargets', 'TargetMismatch')
        {
            foreach ($problem in @($entry.Problems | Where-Object { $_.Kind -eq $kind }))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $problemExtents[$kind] -Construct $kind -Message "${entryLabel}: $($problem.Message)" -Hint $hints[$kind]))
            }
        }

        foreach ($target in @($entry.Targets))
        {
            if ($claimedTargets.Contains([string] $target.Key))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $targetsStart -Construct 'DuplicateTarget' -Message "${entryLabel}: Target '$($target.RuntimeKey)' is also listed by entry $($claimedTargets[[string] $target.Key])." -Hint $hints['DuplicateTarget']))
            }
        }

        if ($findings.Count -eq 0)
        {
            foreach ($target in @($entry.Targets))
            {
                $claimedTargets[[string] $target.Key] = $entryIndex
            }
        }

        if ($rawEntry -is [System.Collections.IDictionary])
        {
            if (-not $rawEntry.Contains('Hash'))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $entryStart -Construct 'MissingHash' -Severity Warning -Message "${entryLabel}: The entry has no Hash, so a change to its script cannot be detected." -Hint $regenerateHint))
            }
            elseif (-not (Test-CompleterSetHashFormat -Value $entry.DeclaredHash))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'InvalidHash' -Severity Warning -Message "${entryLabel}: The Hash '$($entry.DeclaredHash)' is not 'SHA256:' followed by 64 hexadecimal digits, so it is ignored." -Hint $regenerateHint))
            }
            elseif ($null -ne $entry.ActualHash -and $entry.ActualHash -ne [string] $entry.DeclaredHash)
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'HashMismatch' -Severity Warning -Message "${entryLabel}: The script has changed since the set was written. Declared: $($entry.DeclaredHash). Script: $($entry.ActualHash)." -Hint $regenerateHint))
            }
        }

        $findings
    }

    $unlistedScripts = @(
        Get-ChildItem -LiteralPath $SetDefinition.Directory -Filter $Filter -File -Recurse -Force -ErrorAction Stop |
            Where-Object { -not $listedPaths.Contains($_.FullName) } |
            Sort-Object -Property FullName
    )

    foreach ($unlistedScript in $unlistedScripts)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extents.EntriesExtent -Construct 'UnlistedScript' -Severity Warning -Message "The script '$($unlistedScript.FullName)' matches '$Filter', but no entry of the set lists it." -Hint $regenerateHint
    }
}
