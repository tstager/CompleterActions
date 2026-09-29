<#
.SYNOPSIS
Adds or replaces a managed registration record in module state.

.DESCRIPTION
Stores a registration object in the module's in-memory registration table using
its Key property as the dictionary key. Existing entries with the same key are
replaced, which lets higher-level registration code refresh an internal record
after re-registering a completer.

.PARAMETER Registration
The registration record to store. The object must expose a non-empty Key
property.

.PARAMETER Table
The managed registration table to write to, as a registration snapshot
carries it in Managed. When it is omitted the module's table is looked up for
this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the record that is stored in the managed registration table.

.EXAMPLE
PS> $record | Add-ManagedCompleterRegistration

Adds a newly created internal registration record to the module state, replacing
any prior record for the same target key.
#>
function Add-ManagedCompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $Registration,

        [Parameter()]
        [System.Collections.IDictionary] $Table
    )

    process
    {
        if ($null -eq $Registration.PSObject.Properties['Key'] -or [string]::IsNullOrWhiteSpace([string] $Registration.Key))
        {
            throw 'Registration records must expose a non-empty Key property.'
        }

        try
        {
            $registrations = $Table

            if ($null -eq $registrations)
            {
                $registrations = Get-ManagedCompleterRegistrationTable
            }

            $registrations[[string] $Registration.Key] = $Registration

            return $registrations[[string] $Registration.Key]
        }
        catch
        {
            throw "Failed to add the managed completer registration '$([string] $Registration.Key)'. $($_.Exception.Message)"
        }
    }
}
