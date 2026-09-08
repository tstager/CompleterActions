<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers native or command-parameter argument completers with
Register-ArgumentCompleter and records the registrations in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them. Registering the same script for a target that is already
managed is idempotent only while the managed record still matches the live
runtime value; when the runtime registration was replaced or removed outside
this module, the managed record is stale and the command fails until you
reconcile it with -Force. Each target is updated transactionally: if the
runtime or managed write fails, the previous runtime and managed state are
restored and any rollback failure is reported alongside the original error. The
command supports array inputs for command and parameter targets, and it can
also accept pipeline InputObject values that describe the target and expose a
ScriptBlock property.

.PARAMETER InputObject
Supplies one or more objects that describe completer targets. Input objects must
expose target metadata through Key, RegistrationKey, RuntimeKey, or
CommandName/ParameterName plus IsNative/Native, and must expose a ScriptBlock
property whose value is a script block.

.PARAMETER CommandName
Specifies one or more command names whose completers should be registered.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer
registrations.

.PARAMETER Native
Registers native completers for the commands instead of parameter completers.

.PARAMETER ScriptBlock
Provides the completer script block to register. When multiple targets are
supplied through arrays, the same script block is reused for each target.

.PARAMETER Force
Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value was
changed outside this module.

.PARAMETER PassThru
Returns the managed registration records that were created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns CompleterActions.CompleterRegistration records.
#>
function Register-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject[]] $InputObject,

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

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedInputs = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedInputs = @($InputObject | Resolve-CompleterInputObject -RequireScriptBlock)
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

                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = $ScriptBlock
                    }
                }
            }

            foreach ($resolvedInput in $resolvedInputs)
            {
                $target = $resolvedInput.Target
                $targetScriptBlock = $resolvedInput.ScriptBlock
                $targetImportModule = $resolvedInput.ImportModule
                $existingManagedRegistration = $null
                $existingRuntimeRegistration = $null
                $registration = $null
                $rollbackError = $null

                try
                {
                    $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                    $existingManagedRegistration = $registrationState.ManagedRegistration
                    $existingRuntimeRegistration = $registrationState.RuntimeRegistration

                    if ($null -ne $existingManagedRegistration -and -not $Force)
                    {
                        if ($registrationState.ManagedState -eq 'Stale')
                        {
                            throw "The module-managed completer registration for '$($target.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
                        }

                        if ($existingManagedRegistration.ScriptText -eq $targetScriptBlock.ToString())
                        {
                            if ($PassThru)
                            {
                                $PSCmdlet.WriteObject($existingManagedRegistration)
                            }

                            continue
                        }

                        throw "A module-managed completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
                    }

                    if ($null -eq $existingManagedRegistration -and $null -ne $existingRuntimeRegistration -and -not $Force)
                    {
                        throw "A runtime completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
                    }

                    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
                    {
                        continue
                    }

                    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $targetScriptBlock -Source 'Managed' -ImportModule $targetImportModule

                    try
                    {
                        $null = Add-RuntimeCompleterRegistration -Target $target -ScriptBlock $targetScriptBlock
                        $registration = Add-ManagedCompleterRegistration -Registration $registration
                    }
                    catch
                    {
                        try
                        {
                            if ($null -ne $existingRuntimeRegistration)
                            {
                                $null = Add-RuntimeCompleterRegistration -Target $existingRuntimeRegistration -ScriptBlock $existingRuntimeRegistration.ScriptBlock
                            }
                            else
                            {
                                $null = Remove-RuntimeCompleterRegistration -Key $target.Key
                            }

                            if ($null -ne $existingManagedRegistration)
                            {
                                $null = Add-ManagedCompleterRegistration -Registration $existingManagedRegistration
                            }
                            else
                            {
                                $null = Remove-ManagedCompleterRegistration -Key $target.Key
                            }
                        }
                        catch
                        {
                            $rollbackError = $_
                        }

                        throw
                    }

                    if ($PassThru)
                    {
                        $PSCmdlet.WriteObject($registration)
                    }
                }
                catch
                {
                    if ($null -ne $rollbackError)
                    {
                        throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message) Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($rollbackError.Exception.Message)"
                    }

                    throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $existingManagedRegistration = $null
                    $existingRuntimeRegistration = $null
                    $registration = $null
                    $rollbackError = $null
                    $targetImportModule = $null
                }
            }
        }
        finally
        {
            $resolvedInputs = @()
        }
    }
}
