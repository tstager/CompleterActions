<#
.SYNOPSIS
Writes a batch of completer registrations to the runtime and the managed state as one transaction.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved every
record's conflicts and confirmed the operation. Each record whose conflict
result reports IsExisting is not written; the managed record it already
matches is returned in its place. The batch is written in two passes: every
other record's script block is first added to the live completer dictionary,
in order, and only then is every such record stored in the managed
registration table, in order. The stored records are returned in the same
order as the input. With one record the two passes are the runtime write and
then the managed write of that record.

If any write fails, the batch is rolled back in reverse from the last record
whose runtime write was started: for each written record, the earlier runtime
value carried on its conflict result is put back or the new one removed, and
the earlier managed record is put back or the new one removed, so the session
ends exactly as it was before the batch. A managed write that fails therefore
also undoes the runtime values of the records after it, which the runtime pass
had already written. The error names the target whose write failed, and a
failure during the rollback is reported together with the original error so
the caller can say the target may be inconsistent. Register-Completer writes
each target through this helper on its own, so every target of a call stays
its own transaction, and Import-CompleterSet writes a whole set through it,
so an eager, a lazy, and a completer set registration share one write path.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records to store, in write order.
Each record's ScriptBlock is the value written to the runtime dictionary.

.PARAMETER Conflict
The results Resolve-CompleterRegistrationConflict returned for the same
records, in the same order. Their RuntimeRegistration and ManagedRegistration
are the state restored when a write fails.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot the records were resolved
against. Its RuntimeContext and Managed table are written through, so a batch
looks up the runtime dictionaries and the managed table once instead of once
per record. When it is omitted each write looks them up itself.

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
        [psobject[]] $Conflict,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($Registration.Count -ne $Conflict.Count)
    {
        throw "Each registration needs the conflict result resolved for it, but $($Registration.Count) registrations came with $($Conflict.Count) conflict results."
    }

    $runtimeParameters = @{}
    $managedParameters = @{}

    if ($null -ne $Snapshot)
    {
        $runtimeParameters['Runtime'] = $Snapshot.RuntimeContext
        $managedParameters['Table'] = $Snapshot.Managed
    }

    $storedRegistrations = [System.Collections.Generic.List[psobject]]::new()
    $runtimeIndex = -1
    $managedIndex = -1

    try
    {
        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            $runtimeIndex = $index
            $null = Add-RuntimeCompleterRegistration -Target $Registration[$index] -ScriptBlock $Registration[$index].ScriptBlock @runtimeParameters
        }

        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                $storedRegistrations.Add($Conflict[$index].ManagedRegistration)
                continue
            }

            $managedIndex = $index
            $storedRegistrations.Add((Add-ManagedCompleterRegistration -Registration $Registration[$index] @managedParameters))
        }

        return $storedRegistrations
    }
    catch
    {
        $registrationError = $_
        $failedIndex = if ($managedIndex -ge 0) { $managedIndex } else { $runtimeIndex }
        $failedRegistration = $Registration[$failedIndex]
        $rollbackErrors = [System.Collections.Generic.List[string]]::new()

        for ($index = $runtimeIndex; $index -ge 0; $index--)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            try
            {
                if ($null -ne $Conflict[$index].RuntimeRegistration)
                {
                    $null = Add-RuntimeCompleterRegistration -Target $Conflict[$index].RuntimeRegistration -ScriptBlock $Conflict[$index].RuntimeRegistration.ScriptBlock @runtimeParameters
                }
                else
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $Registration[$index].Key
                }

                if ($null -ne $Conflict[$index].ManagedRegistration)
                {
                    $null = Add-ManagedCompleterRegistration -Registration $Conflict[$index].ManagedRegistration @managedParameters
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
