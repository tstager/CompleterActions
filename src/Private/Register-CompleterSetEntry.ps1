<#
.SYNOPSIS
Registers the targets of one validated completer set entry lazily.

.DESCRIPTION
Import-CompleterSet calls this helper once per valid entry, after every entry
in the set has been validated, and it is the single place where a set entry
becomes managed registrations. The entry's Targets are the CompleterTarget
records Resolve-CompleterSetEntry already resolved, derived from the parsed
script for a strict entry and declared for a trusted one, so nothing is parsed
again here. Each target is registered exactly as Register-CompleterRegistration
-Lazy registers it: its conflicts are resolved against the current managed and
runtime state, an existing record that already describes the same script and
tier is reused, and otherwise a lazy stub is written to the runtime with a
Pending record in the managed table through the same transaction. The script
is not executed until the first tab press for one of its targets.

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

    foreach ($target in $Entry.Targets)
    {
        try
        {
            $conflict = Resolve-CompleterRegistrationConflict -Target $target -ScriptPath $Entry.Path -Trusted:$Entry.Trusted -Lazy -Force:$Force

            if ($null -ne $conflict.Problem)
            {
                throw $conflict.Problem
            }

            if ($conflict.IsExisting)
            {
                $conflict.ManagedRegistration
                continue
            }

            $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock (New-CompleterLazyStub -Key $target.Key) -Source 'Managed' -State 'Pending' -ScriptPath $Entry.Path -Trusted:$Entry.Trusted

            Add-CompleterRegistration -Registration $registration -Conflict $conflict
        }
        catch
        {
            throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
        }
    }
}
