<#
.SYNOPSIS
Captures the managed registration table and the live runtime completer dictionaries once for a batch of lookups.

.DESCRIPTION
Reads the module's managed registration table and the current session's
runtime completer dictionaries once, and indexes the runtime keys case
insensitively, so that a batch of targets can be reconciled against the
session without reaching into PowerShell internals for each one.
Resolve-CompleterRegistrationState resolves keys against a snapshot, taking
its own when the caller passes none, and Import-CompleterSet takes one
snapshot per set so validating and registering hundreds of targets costs one
runtime read. The snapshot holds references to the live table and
dictionaries: it describes the session at the moment it was taken and is meant
to be consumed before the same batch writes.

.OUTPUTS
CompleterActions.CompleterRegistrationSnapshot
Returns an object with Managed, the managed registration table, and Runtime,
one view per runtime dictionary in the order Find-RuntimeCompleterRegistration
searches them, native first. Each view carries IsNative, the Dictionary, and
Keys, a case-insensitive map from a key to the casing the dictionary stores.

.EXAMPLE
PS> $snapshot = Get-CompleterRegistrationSnapshot

Captures the session's registrations before resolving a set of targets against
them.
#>
function Get-CompleterRegistrationSnapshot
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $runtime = Get-CompleterRuntime
    $views = @(
        foreach ($view in @(
                @{ IsNative = $true; Dictionary = $runtime.NativeArgumentCompleters },
                @{ IsNative = $false; Dictionary = $runtime.CustomArgumentCompleters }
            ))
        {
            $keys = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            if ($null -ne $view.Dictionary)
            {
                foreach ($entryKey in $view.Dictionary.Keys)
                {
                    $keys[[string] $entryKey] = [string] $entryKey
                }
            }

            [pscustomobject] [ordered] @{
                IsNative   = $view.IsNative
                Dictionary = $view.Dictionary
                Keys       = $keys
            }
        }
    )

    return [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterRegistrationSnapshot'
        Managed    = Get-ManagedCompleterRegistrationTable
        Runtime    = $views
    }
}
