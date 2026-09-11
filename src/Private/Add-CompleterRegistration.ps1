<#
.SYNOPSIS
Writes a batch of completer registrations to the runtime and the managed state as one transaction.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved every
record's conflicts and confirmed the operation. Each record whose conflict
result reports IsExisting is not written; the managed record it already
matches is returned in its place. Every other record's script block is added
to the live completer dictionary and the record is stored in the managed
registration table, in order, and the stored records are returned in the same
order as the input.

If any write fails, the batch is rolled back in reverse: for every record that
was written, the earlier runtime value carried on its conflict result is put
back or the new one removed, and the earlier managed record is put back or the
new one removed, so the session ends exactly as it was before the batch. The
error names the target whose write failed, and a failure during the rollback
is reported together with the original error so the caller can say the target
may be inconsistent. Register-CompleterRegistration writes the targets of one
call through this helper and Import-CompleterSet writes a whole set through
it, so an eager, a lazy, and a completer set registration share one
transaction.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records to store, in write order.
Each record's ScriptBlock is the value written to the runtime dictionary.

.PARAMETER Conflict
The results Resolve-CompleterRegistrationConflict returned for the same
records, in the same order. Their RuntimeRegistration and ManagedRegistration
are the state restored when a write fails.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one record per input, in order: the reused managed record for an
existing registration, otherwise the record as stored in the managed
registration table.
#>
function Add-CompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Conflict
    )

    if ($Registration.Count -ne $Conflict.Count)
    {
        throw "Each registration needs the conflict result resolved for it, but $($Registration.Count) registrations came with $($Conflict.Count) conflict results."
    }

    $storedRegistrations = [System.Collections.Generic.List[psobject]]::new()
    $writeIndex = -1

    try
    {
        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                $storedRegistrations.Add($Conflict[$index].ManagedRegistration)
                continue
            }

            $writeIndex = $index
            $null = Add-RuntimeCompleterRegistration -Target $Registration[$index] -ScriptBlock $Registration[$index].ScriptBlock
            $storedRegistrations.Add((Add-ManagedCompleterRegistration -Registration $Registration[$index]))
        }

        return $storedRegistrations
    }
    catch
    {
        $registrationError = $_
        $failedRegistration = $Registration[$writeIndex]
        $rollbackErrors = [System.Collections.Generic.List[string]]::new()

        for ($index = $writeIndex; $index -ge 0; $index--)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            try
            {
                if ($null -ne $Conflict[$index].RuntimeRegistration)
                {
                    $null = Add-RuntimeCompleterRegistration -Target $Conflict[$index].RuntimeRegistration -ScriptBlock $Conflict[$index].RuntimeRegistration.ScriptBlock
                }
                else
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $Registration[$index].Key
                }

                if ($null -ne $Conflict[$index].ManagedRegistration)
                {
                    $null = Add-ManagedCompleterRegistration -Registration $Conflict[$index].ManagedRegistration
                }
                else
                {
                    $null = Remove-ManagedCompleterRegistration -Key $Registration[$index].Key
                }
            }
            catch
            {
                $rollbackErrors.Add($_.Exception.Message)
            }
        }

        $message = "Failed to register the completer '$($failedRegistration.RuntimeKey)'. $($registrationError.Exception.Message)"

        if ($rollbackErrors.Count -gt 0)
        {
            $message += " Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($rollbackErrors -join ' ')"
        }

        throw $message
    }
}
