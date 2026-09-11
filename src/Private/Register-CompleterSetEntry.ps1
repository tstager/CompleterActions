<#
.SYNOPSIS
Registers the targets of one validated completer set entry.

.DESCRIPTION
Import-CompleterSet calls this helper once per valid entry, after every entry
in the set has been validated, and it is the single place where a set entry
becomes managed registrations. The current body imports the script eagerly
through Import-CompleterScript under the entry's trust tier, keeps only the
targets the entry resolved to, and registers them with
Register-CompleterRegistration. Lazy registration replaces that import so the
script is not executed until the first tab press for one of its targets.

.PARAMETER Entry
A valid CompleterActions.CompleterSetEntry record from Resolve-CompleterSetEntry.

.PARAMETER Force
Replaces existing managed or runtime registrations for the entry's targets.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the CompleterActions.CompleterRegistration records that were created
or reused.
#>
function Register-CompleterSetEntry
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Entry,

        [Parameter()]
        [switch] $Force
    )

    # LAZY INTEGRATION POINT: replace the eager import below with the lazy
    # Register-CompleterRegistration path (script path, -Lazy, -Trusted per the
    # entry, explicit targets for trusted entries, -Force pass-through, -PassThru).
    $importedByKey = @{}

    foreach ($imported in @(Import-CompleterScript -LiteralPath $Entry.Path -Trusted:$Entry.Trusted))
    {
        $importedByKey[[string] $imported.Key] = $imported
    }

    $selectedInputs = @(
        foreach ($target in $Entry.Targets)
        {
            if (-not $importedByKey.ContainsKey([string] $target.Key))
            {
                throw "The script '$($Entry.Path)' did not register the target '$($target.RuntimeKey)' that the completer set declares for it."
            }

            $importedByKey[[string] $target.Key]
        }
    )

    $selectedInputs | Register-CompleterRegistration -Force:$Force -PassThru -Confirm:$false
}
