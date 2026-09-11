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
script is not parsed, and strict entries must pass the strict import grammar,
with their targets derived from the script and compared against any Targets
the entry declares. When one or more entries are invalid the command throws a
single error that lists every problem and registers nothing. With -SkipInvalid
each problem is written as a warning instead and the valid entries register.

Relative Path values resolve against the directory of the set file, so a
completer repository can carry its set file next to its scripts.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER SkipInvalid
Writes each invalid entry as a warning and registers the valid entries instead
of failing the whole set.

.PARAMETER Force
Replaces existing managed or runtime registrations for the targets in the set.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the CompleterActions.CompleterRegistration records that were created
or reused for the set's targets.

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
                $entryIndex = 0
                $entries = @(
                    foreach ($rawEntry in $setDefinition.Entries)
                    {
                        $entryIndex++
                        Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $setDefinition.Directory
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
