<#
.SYNOPSIS
Reports drift between a completer set file and the scripts on disk.

.DESCRIPTION
Reads a completer set the way Import-CompleterSet does, checks every entry
in full against the scripts on disk, and returns one
CompleterActions.CompleterScriptFinding record per problem. A set that
matches its folder produces no output, so a gate can assert that the command
returns nothing, the same shape Test-CompleterScript uses.

The set is read with Import-PowerShellDataFile, which evaluates data only,
and the set file is also parsed, never evaluated, to point each finding at a
line and column of the set. Every strict entry is parsed once, whether or not
its Hash matches, because the command verifies rather than takes the fast
path. A trusted entry is never parsed, as at import, so it can report only
MissingScript, InvalidEntry, DuplicateTarget, and the three Hash kinds. No
script is executed, and the session's registrations are neither read nor
changed, so a conflict with what the session has registered is not drift.

Construct names the kind of drift, and Severity is Error when
Import-CompleterSet without -SkipInvalid would reject the set because of it,
or Warning when the set still imports but is stale or slower:

- MissingScript (Error): Path does not resolve to an existing file.
- InvalidEntry (Error): any other problem Import-CompleterSet reports for the
  entry itself, with its text word for word.
- UnreadableTargets (Error): a strict script does not parse or does not name
  its targets with literal arguments.
- TargetMismatch (Error): a strict entry's Targets differ from the targets its
  script registers.
- DuplicateTarget (Error): an earlier entry already lists the target, under
  import's rule that only an entry with no Error claims its targets.
- HashMismatch (Warning): the script changed since the Hash was written.
- MissingHash (Warning): the entry has no Hash.
- InvalidHash (Warning): the Hash is not 'SHA256:' and 64 hexadecimal digits.
- UnlistedScript (Warning): a file under the set's directory matches -Filter
  and no entry lists it.

Findings come in set order, each entry's in the order above, and the
UnlistedScript findings follow, sorted by path. Path is the set file for
every finding, because the fix is always made in the set, usually by
regenerating it with Export-CompleterSet.

Every -Path or -LiteralPath value is resolved before any set is tested. The
sets are then tested in the order given, and each set's findings are written
before the next set is read. A set that cannot be read, such as one without
Version = 1, stops the call with a terminating error after the findings of
the earlier sets.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER Filter
The file-name pattern of the scan for scripts that no entry lists. The scan
is recursive under the set file's directory. The default is *_completer.ps1.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns CompleterActions.CompleterScriptFinding records with Path, Line,
Column, Severity, Construct, Message, and Hint properties, or nothing when
the set matches its folder.

.EXAMPLE
PS> Test-CompleterSet -Path ~\Completers\completers.psd1

Reports every entry that no longer matches its script and every completer
script the set does not list, or nothing when the set is current.

.EXAMPLE
PS> Test-CompleterSet -LiteralPath .\completers.psd1 | Where-Object Severity -eq Error

Lists only the drift that would make Import-CompleterSet reject the set.
#>
function Test-CompleterSet
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
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
        [ValidateNotNullOrEmpty()]
        [string] $Filter = '*_completer.ps1'
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
                Get-CompleterSetFinding -SetDefinition $setDefinition -Filter $Filter
            }
        }
        catch
        {
            throw "Failed to test completer set. $($_.Exception.Message)"
        }
    }
}
