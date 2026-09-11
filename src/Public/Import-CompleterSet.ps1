<#
.SYNOPSIS
Validates a completer set file and registers every script it lists.

.DESCRIPTION
Reads a completer set, a .psd1 data file written by Export-CompleterSet or by
hand, validates every entry up front, and then registers each valid entry's
targets as managed registrations. The set is read with
Import-PowerShellDataFile, which evaluates data only, and validation never
executes a completer script.

Every entry is checked before anything is registered: the script file must
exist and be a .ps1, Trusted entries must declare their Targets because the
script is not parsed, strict entries must name their targets with literal
Register-ArgumentCompleter arguments so the targets can be derived from the
parsed script and compared against any Targets the entry declares, no target
may be listed by two entries of the set, and without -Force no target may
already carry a managed or runtime registration for a different completer. An
entry that repeats a registration the session already has is reused. The
strict import grammar runs when a script loads, so a set import costs one
parse per script; run Test-CompleterScript over the repository to find grammar
findings ahead of time. When one or more entries are invalid the command
throws a single error that lists every problem and registers nothing. With
-SkipInvalid each problem is written as a warning instead and the valid
entries register.

Relative Path values resolve against the directory of the set file, so a
completer repository can carry its set file next to its scripts.

Registering a set does not run its scripts. Every valid entry is registered
through Register-CompleterRegistration -Lazy under the entry's trust tier, so
each target gets a stub and a managed record in state Pending. The first tab
press for a target loads the script and moves the record to Active; a script
that fails to load moves to Failed with the message in LoadError, and the
completion engine's default completion applies as if no completer were
registered. -Force replaces existing registrations for the set's targets and
retries Failed ones.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER SkipInvalid
Writes each invalid entry as a warning and registers the valid entries instead
of failing the whole set.

.PARAMETER Force
Replaces existing managed or runtime registrations for the targets in the set,
including Failed lazy records whose load should be retried.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the CompleterActions.CompleterRegistration records that were created
or reused for the set's targets, in state Pending until each script loads.

.EXAMPLE
PS> Import-CompleterSet -Path ~\Completers\completers.psd1

Registers every completer script listed in the set. This is the one line a
profile needs for a whole completer repository.

.EXAMPLE
PS> Import-CompleterSet -Path ~\Completers\completers.psd1 -SkipInvalid -Force

Registers the valid entries, warns about the rest, and replaces any existing
registration for the same targets.
#>
function Import-CompleterSet
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter()]
        [switch] $SkipInvalid,

        [Parameter()]
        [switch] $Force
    )

    process
    {
        try
        {
            $resolvedPaths = @(
                if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
                    }
                }
                else
                {
                    foreach ($pathItem in $Path)
                    {
                        Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath
                    }
                }
            )

            foreach ($setPath in $resolvedPaths)
            {
                $setDefinition = Import-CompleterSetDefinition -LiteralPath $setPath
                $claimedTargets = @{}
                $entryIndex = 0
                $entries = @(
                    foreach ($rawEntry in $setDefinition.Entries)
                    {
                        $entryIndex++
                        Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $setDefinition.Directory -ClaimedTargets $claimedTargets -Force:$Force
                    }
                )

                $invalidEntries = @($entries | Where-Object { -not $_.IsValid })

                if ($invalidEntries.Count -gt 0)
                {
                    $problemLines = @(
                        foreach ($entry in $invalidEntries)
                        {
                            $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $($entry.Index)" } else { "Entry $($entry.Index) ('$($entry.DeclaredPath)')" }

                            foreach ($problem in $entry.Problems)
                            {
                                '{0}: {1}' -f $entryLabel, $problem
                            }
                        }
                    )

                    if (-not $SkipInvalid)
                    {
                        $entryNoun = if ($invalidEntries.Count -eq 1) { 'entry' } else { 'entries' }
                        throw "Completer set '$setPath' has $($invalidEntries.Count) invalid $entryNoun and nothing was registered. Fix the entries or use -SkipInvalid to register the valid ones.$([Environment]::NewLine)$($problemLines -join [Environment]::NewLine)"
                    }

                    foreach ($problemLine in $problemLines)
                    {
                        Write-Warning -Message "Completer set '$setPath' skipped $problemLine"
                    }
                }

                foreach ($entry in @($entries | Where-Object { $_.IsValid }))
                {
                    if (-not $PSCmdlet.ShouldProcess($entry.Path, 'Import completer set entry'))
                    {
                        continue
                    }

                    Register-CompleterSetEntry -Entry $entry -Force:$Force
                }
            }
        }
        catch
        {
            throw "Failed to import completer set. $($_.Exception.Message)"
        }
    }
}
