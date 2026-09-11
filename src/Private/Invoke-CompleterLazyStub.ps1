<#
.SYNOPSIS
Loads a lazily registered completer script on its first invocation and delegates the call.

.DESCRIPTION
Runs inside the ordinary completer call for a Pending lazy target. It imports
the script recorded on the managed record through Import-CompleterScript, in the
strict or trusted tier the record was registered with, finds the imported script
block for its own target, replaces the runtime dictionary entry with it, and
moves the managed record to Active. Every other Pending record that points at
the same script and tier, and whose runtime entry is still its own stub, is
swapped from the same import so a script that registers several targets is
executed once. The call that triggered the load is then delegated to the real
script block and its results are returned.

When anything in the load fails, the helper returns nothing, stores the error
message on the managed record as LoadError with State Failed, and removes the
runtime entry for the target, so the completion engine's default completion
applies exactly as it would with no completer registered. No error reaches the
host. The helper never hooks key handlers, replaces TabExpansion2, or touches
PSReadLine options.

.PARAMETER Key
The normalized registration key of the lazy target being invoked.

.PARAMETER ArgumentList
The arguments the completion engine passed to the completer.

.OUTPUTS
System.Management.Automation.CompletionResult
Whatever the loaded completer returns for the delegated call. Nothing when the
load fails.
#>
function Invoke-CompleterLazyStub
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CompletionResult])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ArgumentList = @()
    )

    $callerErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $registration = $null
    $realScriptBlock = $null

    try
    {
        $registration = Find-ManagedCompleterRegistration -Key $Key

        if ($null -eq $registration)
        {
            throw "No managed registration exists for the lazy completer '$Key'."
        }

        if ($registration.State -eq 'Active')
        {
            $realScriptBlock = $registration.ScriptBlock
        }
        else
        {
            if ($registration.State -ne 'Pending')
            {
                throw "The managed registration for '$($registration.RuntimeKey)' is in state '$($registration.State)' and cannot be loaded lazily."
            }

            $importedRegistrations = @(Import-CompleterScript -LiteralPath $registration.ScriptPath -Trusted:$registration.Trusted)
            $ownRegistration = $importedRegistrations | Where-Object -Property Key -EQ -Value $registration.Key | Select-Object -First 1

            if ($null -eq $ownRegistration)
            {
                $importedKeys = ($importedRegistrations | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                throw "The script '$($registration.ScriptPath)' did not register a completer for '$($registration.RuntimeKey)'. It registered: $importedKeys."
            }

            foreach ($importedRegistration in $importedRegistrations)
            {
                $pendingRegistration = Find-ManagedCompleterRegistration -Key $importedRegistration.Key

                if ($null -eq $pendingRegistration -or
                    $pendingRegistration.State -ne 'Pending' -or
                    $pendingRegistration.ScriptPath -ne $registration.ScriptPath -or
                    [bool] $pendingRegistration.Trusted -ne [bool] $registration.Trusted)
                {
                    continue
                }

                $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $pendingRegistration.Key

                if ($null -eq $runtimeRegistration -or -not [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $pendingRegistration.ScriptBlock))
                {
                    continue
                }

                $null = Add-RuntimeCompleterRegistration -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock
                $null = Add-ManagedCompleterRegistration -Registration (
                    New-CompleterRegistrationRecord -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock -Source 'Managed' -ImportModule $importedRegistration.ImportModule -State 'Active' -ScriptPath $pendingRegistration.ScriptPath -Trusted:$pendingRegistration.Trusted
                )
            }

            $realScriptBlock = $ownRegistration.ScriptBlock
        }
    }
    catch
    {
        $loadError = $_.Exception.Message

        try
        {
            if ($null -ne $registration)
            {
                $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $registration.Key

                if ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $registration.ScriptBlock))
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $registration.Key
                }

                $null = Add-ManagedCompleterRegistration -Registration (
                    New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -State 'Failed' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted -LoadError $loadError
                )
            }
        }
        catch
        {
            Write-Debug -Message "Failed to record the lazy load failure for '$Key'. $($_.Exception.Message)"
        }

        return
    }

    $ErrorActionPreference = $callerErrorActionPreference

    & $realScriptBlock @ArgumentList
}
