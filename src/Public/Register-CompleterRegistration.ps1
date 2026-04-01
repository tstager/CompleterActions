<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers a native or command-parameter argument completer with
Register-ArgumentCompleter and records the registration in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them.

.PARAMETER CommandName
Specifies the command name whose completer should be registered.

.PARAMETER ParameterName
Specifies the parameter name for a command-parameter completer registration.

.PARAMETER Native
Registers a native completer for the command instead of a parameter completer.

.PARAMETER ScriptBlock
Provides the completer script block to register.

.PARAMETER Force
Removes an existing managed or runtime registration for the same target before
registering the new completer.

.PARAMETER PassThru
Returns the managed registration record that was created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns a CompleterActions.CompleterRegistration record.

.EXAMPLE
PS> Register-CompleterRegistration -CommandName 'Test-Tool' -ParameterName 'Name' -ScriptBlock {
>>     param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
>>     [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
>> }

Registers a managed parameter completer for the Name parameter on Test-Tool.

.EXAMPLE
PS> Register-CompleterRegistration -CommandName 'git' -Native -ScriptBlock $nativeCompleter -Force -PassThru

Replaces any existing native completer registration for git and returns the new
managed registration record.
#>
function Register-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    $target = if ($PSCmdlet.ParameterSetName -eq 'Native')
    {
        Resolve-CompleterTarget -CommandName $CommandName -Native
    }
    else
    {
        Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
    }

    $existingManagedRegistration = Find-ManagedCompleterRegistration -Key $target.Key
    $existingRuntimeRegistration = Find-RuntimeCompleterRegistration -Key $target.Key

    if ($null -ne $existingManagedRegistration -and -not $Force)
    {
        if ($existingManagedRegistration.ScriptText -eq $ScriptBlock.ToString())
        {
            if ($PassThru)
            {
                return $existingManagedRegistration
            }

            return
        }

        throw "A module-managed completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if ($null -eq $existingManagedRegistration -and $null -ne $existingRuntimeRegistration -and -not $Force)
    {
        throw "A runtime completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
    {
        return
    }

    if ($Force)
    {
        if ($null -ne $existingManagedRegistration)
        {
            $null = Remove-ManagedCompleterRegistration -Key $target.Key
        }

        if ($null -ne $existingRuntimeRegistration)
        {
            $null = Remove-RuntimeCompleterRegistration -Key $target.Key
        }
    }

    if ($target.IsNative)
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -Native -ScriptBlock $ScriptBlock
    }
    else
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -ParameterName $target.ParameterName -ScriptBlock $ScriptBlock
    }

    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $ScriptBlock -Source 'Managed'
    $registration = Add-ManagedCompleterRegistration -Registration $registration

    if ($PassThru)
    {
        return $registration
    }
}
