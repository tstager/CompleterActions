<#
.SYNOPSIS
Removes completer registrations from runtime and, when applicable, module state.

.DESCRIPTION
Removes completer registrations identified by native command, command
parameter target, or pipeline InputObject values. Managed registrations
are removed from both the PowerShell runtime and the module's registration
table. Runtime-only registrations require -AllowUnmanaged before they can be
removed. The same gate applies when a managed record is stale because the
runtime registration was replaced outside this module: the live value is only
removed with -AllowUnmanaged, and the stale managed record is dropped with it.
When the runtime registration was already removed outside this module, only
the stale managed record remains and it is removed without the gate. A Pending
lazy registration is removed like any managed registration, stub and record
together. A Failed lazy registration has no runtime entry of its own, so only
its managed record is removed. The command supports array inputs for the
target fields, plus pipeline input from Get-CompleterRegistration output. Keys
are output-only identifiers: a hand-typed key string is not accepted, so name
the target with -CommandName plus -Native or -ParameterName instead.

.PARAMETER InputObject
Supplies one or more objects that describe registrations to remove. Input
objects expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies one or more command names whose completers should be removed.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer removal
targets.

.PARAMETER Native
Targets native completer registrations instead of command parameter completers.

.PARAMETER AllowUnmanaged
Allows removal of runtime registrations that are not tracked by this module,
including a live value that replaced a managed registration outside this
module.

.PARAMETER PassThru
Returns the registration records that were removed.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns removed CompleterActions.CompleterRegistration
records.
#>
function Unregister-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
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
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedTargets = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                $resolvedTargets = @(Resolve-CompleterTargetList @targetParameters)
            }

            foreach ($target in $resolvedTargets)
            {
                $managedRegistration = $null
                $runtimeRegistration = $null
                $registrationToRemove = $null
                $removedRuntimeRegistration = $null
                $removedManagedRegistration = $null

                try
                {
                    $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                    $managedRegistration = $registrationState.ManagedRegistration
                    $runtimeRegistration = $registrationState.RuntimeRegistration

                    if ($registrationState.ManagedState -in 'Active', 'Pending')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The module-managed completer registration for '$($runtimeRegistration.RuntimeKey)' is $($registrationState.ManagedState.ToLowerInvariant()): the live runtime registration was created outside this module. Re-run with -AllowUnmanaged to remove the live runtime registration and the managed record."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed. Re-run with -AllowUnmanaged to remove the runtime registration."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    else
                    {
                        throw 'No completer registration was found for the requested target.'
                    }

                    if (-not $PSCmdlet.ShouldProcess($registrationToRemove.RuntimeKey, 'Unregister completer registration'))
                    {
                        continue
                    }

                    if ($null -ne $runtimeRegistration)
                    {
                        $removedRuntimeRegistration = Remove-RuntimeCompleterRegistration -Key $registrationToRemove.Key
                    }

                    if ($null -ne $managedRegistration)
                    {
                        $removedManagedRegistration = Remove-ManagedCompleterRegistration -Key $registrationToRemove.Key
                    }

                    if ($PassThru)
                    {
                        if ($registrationToRemove.IsManaged -and $null -ne $removedManagedRegistration)
                        {
                            $PSCmdlet.WriteObject($removedManagedRegistration)
                        }
                        elseif ($null -ne $removedRuntimeRegistration)
                        {
                            $PSCmdlet.WriteObject($removedRuntimeRegistration)
                        }
                    }
                }
                catch
                {
                    if ($null -ne $removedRuntimeRegistration -and $null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
                    {
                        $null = Add-RuntimeCompleterRegistration -Target $removedRuntimeRegistration -ScriptBlock $removedRuntimeRegistration.ScriptBlock
                    }

                    if ($null -ne $removedManagedRegistration -and $null -eq (Find-ManagedCompleterRegistration -Key $target.Key))
                    {
                        $null = Add-ManagedCompleterRegistration -Registration $removedManagedRegistration
                    }

                    throw "Failed to unregister the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $managedRegistration = $null
                    $runtimeRegistration = $null
                    $registrationToRemove = $null
                    $removedRuntimeRegistration = $null
                    $removedManagedRegistration = $null
                }
            }
        }
        finally
        {
            $resolvedTargets = @()
        }
    }
}
