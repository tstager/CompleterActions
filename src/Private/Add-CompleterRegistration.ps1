<#
.SYNOPSIS
Writes one completer registration to the runtime and the managed state transactionally.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved the
target's conflicts and confirmed the operation. The record's script block is
added to the live completer dictionary, the record is stored in the managed
registration table, and the stored record is returned. If either write fails,
the previous runtime and managed state carried on the conflict result are
restored: the earlier runtime value is put back or the new one removed, and the
earlier managed record is put back or the new one removed. A failure during
that rollback is reported together with the original error so the caller can
say the target may be inconsistent. Register-CompleterRegistration and
Register-CompleterSetEntry both write through this helper, so an eager, a lazy,
and a completer set registration share one transaction.

.PARAMETER Registration
The CompleterActions.CompleterRegistration record to store. Its ScriptBlock is
the value written to the runtime dictionary.

.PARAMETER Conflict
The result Resolve-CompleterRegistrationConflict returned for the same target.
Its RuntimeRegistration and ManagedRegistration are the state restored when a
write fails.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the record as stored in the managed registration table.
#>
function Add-CompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Registration,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Conflict
    )

    try
    {
        $null = Add-RuntimeCompleterRegistration -Target $Registration -ScriptBlock $Registration.ScriptBlock

        return Add-ManagedCompleterRegistration -Registration $Registration
    }
    catch
    {
        $registrationError = $_

        try
        {
            if ($null -ne $Conflict.RuntimeRegistration)
            {
                $null = Add-RuntimeCompleterRegistration -Target $Conflict.RuntimeRegistration -ScriptBlock $Conflict.RuntimeRegistration.ScriptBlock
            }
            else
            {
                $null = Remove-RuntimeCompleterRegistration -Key $Registration.Key
            }

            if ($null -ne $Conflict.ManagedRegistration)
            {
                $null = Add-ManagedCompleterRegistration -Registration $Conflict.ManagedRegistration
            }
            else
            {
                $null = Remove-ManagedCompleterRegistration -Key $Registration.Key
            }
        }
        catch
        {
            throw "$($registrationError.Exception.Message) Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($_.Exception.Message)"
        }

        throw $registrationError
    }
}
