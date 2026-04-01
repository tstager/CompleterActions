<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers native or command-parameter argument completers with
Register-ArgumentCompleter and records the registrations in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them. The command supports array inputs for command and
parameter targets, and it can also accept pipeline InputObject values that
describe the target and expose a ScriptBlock property.

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
Removes an existing managed or runtime registration for the same target before
registering the new completer.

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
                $existingManagedRegistration = $null
                $existingRuntimeRegistration = $null
                $removedManagedRegistration = $null
                $removedRuntimeRegistration = $null

                try
                {
                    $existingManagedRegistration = Find-ManagedCompleterRegistration -Key $target.Key
                    $existingRuntimeRegistration = Find-RuntimeCompleterRegistration -Key $target.Key

                    if ($null -ne $existingManagedRegistration -and -not $Force)
                    {
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

                    if ($Force)
                    {
                        if ($null -ne $existingManagedRegistration)
                        {
                            $removedManagedRegistration = Remove-ManagedCompleterRegistration -Key $target.Key
                        }

                        if ($null -ne $existingRuntimeRegistration)
                        {
                            $removedRuntimeRegistration = Remove-RuntimeCompleterRegistration -Key $target.Key
                        }
                    }

                    if ($target.IsNative)
                    {
                        Register-ArgumentCompleter -CommandName $target.CommandName -Native -ScriptBlock $targetScriptBlock
                    }
                    else
                    {
                        Register-ArgumentCompleter -CommandName $target.CommandName -ParameterName $target.ParameterName -ScriptBlock $targetScriptBlock
                    }

                    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $targetScriptBlock -Source 'Managed'
                    $registration = Add-ManagedCompleterRegistration -Registration $registration

                    if ($PassThru)
                    {
                        $PSCmdlet.WriteObject($registration)
                    }
                }
                catch
                {
                    if ($Force)
                    {
                        $currentManagedRegistration = Find-ManagedCompleterRegistration -Key $target.Key
                        if ($null -ne $currentManagedRegistration)
                        {
                            $null = Remove-ManagedCompleterRegistration -Key $target.Key
                        }

                        if ($null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
                        {
                            if ($null -ne $removedRuntimeRegistration)
                            {
                                if ($removedRuntimeRegistration.IsNative)
                                {
                                    Register-ArgumentCompleter -CommandName $removedRuntimeRegistration.CommandName -Native -ScriptBlock $removedRuntimeRegistration.ScriptBlock
                                }
                                else
                                {
                                    Register-ArgumentCompleter -CommandName $removedRuntimeRegistration.CommandName -ParameterName $removedRuntimeRegistration.ParameterName -ScriptBlock $removedRuntimeRegistration.ScriptBlock
                                }
                            }

                            if ($null -ne $removedManagedRegistration)
                            {
                                $null = Add-ManagedCompleterRegistration -Registration $removedManagedRegistration
                            }
                        }
                    }

                    throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $existingManagedRegistration = $null
                    $existingRuntimeRegistration = $null
                    $removedManagedRegistration = $null
                    $removedRuntimeRegistration = $null
                }
            }
        }
        finally
        {
            $resolvedInputs = @()
        }
    }
}
