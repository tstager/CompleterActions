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
executed once. When the script registers the same target more than once, the
last definition wins for that target, as it does when the script is
dot-sourced and Register-ArgumentCompleter overwrites the earlier entry. The
call that triggered the load is then delegated to the real script block and
its results are returned.

A load in flight owns its record. The helper tracks the targets it is loading
on the current call stack, so a nested completion for the same target, such as a
script that calls TabExpansion2 for its own command while it loads, returns
nothing instead of starting a second import, and a sibling load never swaps or
fails a record whose own load is still running.

When anything in the load fails, the helper returns nothing, stores the error
message on the managed record as LoadError with State Failed, and removes the
runtime entry for the target, so the completion engine's default completion
applies exactly as it would with no completer registered. No error reaches the
host. The helper never hooks key handlers, replaces TabExpansion2, or touches
PSReadLine options.

.PARAMETER Key
The normalized registration key of the lazy target being invoked.

.PARAMETER Native
Indicates that the lazy target being invoked is a native command completer.

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
        [switch] $Native,

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
        $stubTarget = if ($Native) { Resolve-CompleterTarget -RuntimeKey $Key -Native } else { Resolve-CompleterTarget -RuntimeKey $Key }
        $registration = Find-ManagedCompleterRegistration -Target $stubTarget

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

            $identity = Get-CompleterTargetIdentity -Target $registration

            if (-not $script:CompleterLazyLoadsInProgress.Add($identity))
            {
                return
            }

            try
            {
                # Register-ArgumentCompleter lets the last registration for a target
                # win, so a script that registers the same target twice is reduced
                # to its last definition per target before the initiating target is
                # selected and the siblings are swapped from the same collection.
                $importedRegistrationsByIdentity = [ordered] @{}

                foreach ($importedRegistration in @(Import-CompleterScript -LiteralPath $registration.ScriptPath -Trusted:$registration.Trusted))
                {
                    $importedRegistrationsByIdentity[(Get-CompleterTargetIdentity -Target $importedRegistration)] = $importedRegistration
                }

                if (-not $importedRegistrationsByIdentity.Contains($identity))
                {
                    $importedKeys = @($importedRegistrationsByIdentity.Values | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                    throw "The script '$($registration.ScriptPath)' did not register a completer for '$($registration.RuntimeKey)'. It registered: $importedKeys."
                }

                $ownRegistration = $importedRegistrationsByIdentity[$identity]

                foreach ($importedIdentity in @($importedRegistrationsByIdentity.Keys))
                {
                    $importedRegistration = $importedRegistrationsByIdentity[$importedIdentity]
                    $pendingRegistration = Find-ManagedCompleterRegistration -Target $importedRegistration

                    if ($null -eq $pendingRegistration -or
                        $pendingRegistration.State -ne 'Pending' -or
                        $pendingRegistration.ScriptPath -ne $registration.ScriptPath -or
                        [bool] $pendingRegistration.Trusted -ne [bool] $registration.Trusted -or
                        ($importedIdentity -ne $identity -and $script:CompleterLazyLoadsInProgress.Contains($importedIdentity)))
                    {
                        continue
                    }

                    $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $pendingRegistration

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
            finally
            {
                $null = $script:CompleterLazyLoadsInProgress.Remove($identity)
            }
        }
    }
    catch
    {
        $loadError = $_.Exception.Message

        try
        {
            if ($null -ne $registration)
            {
                $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $registration

                if ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $registration.ScriptBlock))
                {
                    $null = Remove-RuntimeCompleterRegistration -Target $registration
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
