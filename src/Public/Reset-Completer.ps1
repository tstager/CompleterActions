<#
.SYNOPSIS
Returns a Failed or Active script-backed completer to Pending, so its script loads again on the next tab press.

.DESCRIPTION
Re-arms a script-backed managed registration without re-importing the set it
came from. A script-backed registration is any managed record with a
ScriptPath: a lazy registration from Import-CompleterSet or Register-Completer
-Lazy, or an eager one from Import-CompleterScript | Register-Completer. The
targets are named by native command, command parameter target, or pipeline
InputObject values, and each target is decided once per call; a key seen
earlier in the same call is skipped.

A Failed record gets a new lazy stub in the runtime and becomes Pending, with
LoadError cleared and ScriptPath and Trusted kept. An Active record has its
live script block replaced by the stub and becomes Pending, with ImportModule
cleared. A Pending record is left alone without a confirmation prompt, and
-PassThru returns it unchanged. The next tab press follows the ordinary lazy
path: it imports the script under the record's tier, swaps in every Pending
sibling of the same script and tier, and moves them to Active, or moves the
pressed target to Failed again with the new LoadError. Only the targets named
are reset, so an Active sibling keeps its loaded script block until it is
reset itself. The script is not parsed and its targets are not re-derived.

A target that cannot be reset is reported as a non-terminating error, and the
command goes on with the next target or piped record: a registration the
module does not manage, a target with nothing registered, a stale record, a
Failed record whose live runtime value was created outside this module, a
record registered from a script block rather than a script file, and a record
whose script file no longer exists. Use -ErrorAction Stop to stop at the first
error. Each target is its own transaction: if writing the stub or the record
fails, the previous runtime value and managed record are restored. The command
writes only the runtime completer dictionaries and the module's managed table;
it never hooks key handlers, replaces TabExpansion2, or changes PSReadLine
options. To remove a registration instead of reloading it, use
Unregister-Completer.

.PARAMETER InputObject
Supplies one or more objects that describe registrations to reset. Input
objects expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies one or more command names whose completers should be reset.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer reset
targets.

.PARAMETER Native
Targets native completer registrations instead of command parameter completers.

.PARAMETER PassThru
Returns the Pending record of each target that was reset, and the unchanged
record of each target that was already Pending.

.OUTPUTS
CompleterActions.CompleterRegistration
When -PassThru is used, returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Get-Completer -State Failed | Reset-Completer

Re-arms every failed script-backed registration after the scripts were fixed,
and reports each record that cannot be reset.

.EXAMPLE
PS> Reset-Completer -CommandName git, git.exe -Native -PassThru

Reloads the git completer on the next tab press after the script was edited,
and returns the two Pending records.

.EXAMPLE
PS> Get-Completer -State Active, Failed | Where-Object ScriptPath -eq $path | Reset-Completer

Resets every target of one script.
#>
function Reset-Completer
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $decidedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # A plain function, not an advanced one, so the error is written by
        # Reset-Completer itself: it names Reset-Completer and sets $? to false.
        function Write-CompleterResetError
        {
            param(
                [string] $Message,
                [System.Exception] $Exception,
                [object] $TargetObject
            )

            $PSCmdlet.WriteError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($Message, $Exception),
                    'CompleterResetFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $TargetObject
                )
            )
        }
    }

    process
    {
        $resolvedTargets = [System.Collections.Generic.List[psobject]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'InputObject')
        {
            foreach ($inputItem in $InputObject)
            {
                try
                {
                    $resolvedTargets.Add((Resolve-CompleterInputObject -InputObject $inputItem).Target)
                }
                catch
                {
                    Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception -TargetObject $inputItem
                }
            }
        }
        else
        {
            $targetParameters = @{ CommandName = $CommandName }

            if ($PSCmdlet.ParameterSetName -eq 'Native')
            {
                $targetParameters['Native'] = $true
            }
            else
            {
                $targetParameters['ParameterName'] = $ParameterName
            }

            try
            {
                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedTargets.Add($target)
                }
            }
            catch
            {
                Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception
            }
        }

        foreach ($target in $resolvedTargets)
        {
            if (-not $decidedKeys.Add($target.Key))
            {
                continue
            }

            # Every row that cannot be reset sets a reason instead of throwing,
            # so -ErrorVariable collects exactly one error per target.
            $reason = $null
            $failure = $null

            try
            {
                $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                $managedRegistration = $registrationState.ManagedRegistration
                $runtimeRegistration = $registrationState.RuntimeRegistration
                $managedState = $registrationState.ManagedState
                $runtimeKey = if ($null -ne $managedRegistration) { $managedRegistration.RuntimeKey } else { $target.RuntimeKey }

                $reason = if ($null -eq $managedRegistration -and $null -ne $runtimeRegistration)
                {
                    "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed, so it cannot be reset."
                }
                elseif ($null -eq $managedRegistration)
                {
                    'No completer registration was found for the requested target.'
                }
                elseif ($managedState -eq 'Pending')
                {
                    $null
                }
                elseif ($managedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                {
                    "The module-managed completer registration for '$runtimeKey' is $($managedState.ToLowerInvariant()) and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it."
                }
                elseif ($managedState -eq 'Stale')
                {
                    "The module-managed completer registration for '$runtimeKey' is stale. Use Register-Completer -Force to register it again."
                }
                elseif ([string]::IsNullOrWhiteSpace($managedRegistration.ScriptPath))
                {
                    "The completer registration '$runtimeKey' was registered from a script block, not a script file, so there is nothing to reload."
                }
                elseif (-not (Test-Path -LiteralPath $managedRegistration.ScriptPath -PathType Leaf))
                {
                    "The script '$($managedRegistration.ScriptPath)' for '$runtimeKey' no longer exists. Restore it, or remove the registration with Unregister-Completer."
                }

                if ($null -eq $reason)
                {
                    if ($managedState -eq 'Pending')
                    {
                        Write-Verbose -Message "The completer registration '$runtimeKey' is already pending."

                        if ($PassThru -and -not $WhatIfPreference)
                        {
                            $PSCmdlet.WriteObject($managedRegistration)
                        }
                    }
                    elseif ($PSCmdlet.ShouldProcess($runtimeKey, 'Reset completer registration'))
                    {
                        $registration = New-CompleterRegistrationRecord -Target $managedRegistration -ScriptBlock (New-CompleterLazyStub -Key $managedRegistration.Key) -Source 'Managed' -State 'Pending' -ScriptPath $managedRegistration.ScriptPath -Trusted:([bool] $managedRegistration.Trusted)
                        $conflict = [pscustomobject] [ordered] @{
                            Key                 = $registration.Key
                            ManagedRegistration = $managedRegistration
                            RuntimeRegistration = $runtimeRegistration
                            IsExisting          = $false
                            Problem             = $null
                        }

                        $storedRegistration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                        if ($PassThru)
                        {
                            $PSCmdlet.WriteObject($storedRegistration)
                        }
                    }
                }
            }
            catch
            {
                $failure = $_.Exception
                $reason = $_.Exception.Message
            }

            if ($null -ne $reason)
            {
                Write-CompleterResetError -Message "Failed to reset the completer '$($target.RuntimeKey)'. $reason" -Exception $failure -TargetObject $target.RuntimeKey
            }
        }
    }
}
