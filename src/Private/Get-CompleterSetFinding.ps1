<#
.SYNOPSIS
Checks one completer set against the scripts on disk and returns its drift findings.

.DESCRIPTION
Runs the checks shared with Import-CompleterSet for every entry of a set that
Import-CompleterSetDefinition has read, and adds the checks only a drift
report needs. Get-CompleterSetEntryState does the per-entry work, which
Update-CompleterSet shares: each entry goes through Resolve-CompleterSetEntry
-Verify, the static phase of an import with the fast path turned off, so a
strict script is parsed once and its current hash and targets come from that
one parse. A trusted script is never parsed; its hash is read from the file.

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

With Package, the set is a package set, and Get-CompleterSetPackageFinding
adds its PackageLayout findings after every entry's findings and before the
UnlistedScript findings. Without it the findings are exactly the plain set's.
Each finding is written as its entry is checked, so the findings of every
entry, and the PackageLayout findings, are written before a folder that cannot
be read stops the scan for unlisted scripts.

Every position comes from the parse in SetDefinition, so the set file is not
read again. Nothing here reads or writes the session's registrations or runs a
script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.PARAMETER Package
The record Get-CompleterSetPackage returned for the set, when a module
manifest declares it.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the findings in set order, each entry's in the order MissingScript,
InvalidEntry, UnreadableTargets, TargetMismatch, DuplicateTarget,
HashMismatch, MissingHash, InvalidHash, then, for a package set, the
PackageLayout findings, followed by the UnlistedScript findings sorted by
path. Path is the set file for every finding.
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
        [string] $Filter,

        [Parameter()]
        [psobject] $Package
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
    $entryCount = @($SetDefinition.Entries).Count
    $resolvedEntries = [System.Collections.Generic.List[object]]::new()

    # The states arrive as each entry is checked, so this block writes an entry's
    # findings, and after the last entry the PackageLayout findings, before the
    # scan for unlisted scripts starts.
    Get-CompleterSetEntryState -SetDefinition $SetDefinition -Filter $Filter | ForEach-Object {
        $state = $_

        if ($state.PSObject.TypeNames[0] -eq 'CompleterActions.CompleterSetUnlistedScript')
        {
            New-CompleterScriptFinding -Path $setPath -Extent $state.Extent -Construct 'UnlistedScript' -Severity Warning -Message $state.Message -Hint $regenerateHint
        }
        else
        {
            $entry = $state.Entry
            $rawEntry = $state.RawEntry
            $entryIndex = $entry.Index
            $entryExtent = $state.Extent
            $findings = [System.Collections.Generic.List[object]]::new()

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

            foreach ($problem in $state.DuplicateTargetProblems)
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $targetsStart -Construct 'DuplicateTarget' -Message "${entryLabel}: $($problem.Message)" -Hint $hints['DuplicateTarget']))
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
            $resolvedEntries.Add($entry)

            if ($resolvedEntries.Count -eq $entryCount -and $null -ne $Package)
            {
                Get-CompleterSetPackageFinding -SetDefinition $SetDefinition -Package $Package -Entry $resolvedEntries.ToArray()
            }
        }
    }
}
