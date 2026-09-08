<#
.SYNOPSIS
Creates an internal completer registration record object.

.DESCRIPTION
Builds the PSCustomObject stored in the managed registration table. The helper
copies the required target metadata, derives convenience properties such as
CompleterType and IsManaged, and captures both the script block and its text so
module internals can inspect the registered completer later.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, IsNative, and TargetType properties.

.PARAMETER ScriptBlock
The script block that was or will be registered for the completer target.

.PARAMETER Source
Indicates whether the record originated from module-managed registration or from
runtime discovery.

.PARAMETER ImportModule
Preserves a reference to an imported helper module when a registration originated
from Import-CompleterScript.

.PARAMETER State
Describes how the record relates to the live runtime. 'Active' records describe
the value PowerShell is currently using. 'Stale' marks a managed record whose
stored script no longer matches the runtime because the target was replaced or
removed outside this module. 'Conflicted' marks a discovered runtime value that
shadows a stale managed record for the same target.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns a CompleterActions.CompleterRegistration record suitable for internal storage.

.EXAMPLE
PS> $record = New-CompleterRegistrationRecord -Target $target -ScriptBlock $scriptBlock

Creates a managed registration record from previously resolved target metadata
before adding it to the in-memory registration table.
#>
function New-CompleterRegistrationRecord
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory registration object.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [ValidateSet('Managed', 'Discovered')]
        [string] $Source = 'Managed',

        [Parameter()]
        [System.Management.Automation.PSModuleInfo] $ImportModule,

        [Parameter()]
        [ValidateSet('Active', 'Stale', 'Conflicted')]
        [string] $State = 'Active'
    )

    foreach ($requiredProperty in 'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'TargetType')
    {
        if ($Target.PSObject.Properties.Match($requiredProperty).Count -eq 0)
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $registration = [pscustomobject] [ordered] @{
        PSTypeName          = 'CompleterActions.CompleterRegistration'
        Key                 = [string] $Target.Key
        RegistrationKey     = [string] $Target.Key
        RuntimeKey          = [string] $Target.RuntimeKey
        CommandName         = [string] $Target.CommandName
        ParameterName       = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative            = [bool] $Target.IsNative
        CompleterType       = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        TargetType          = [string] $Target.TargetType
        Source              = $Source
        State               = $State
        IsManaged           = $Source -eq 'Managed'
        IsRuntimeRegistered = $State -ne 'Stale'
        ImportModule        = $ImportModule
        ScriptBlock         = $ScriptBlock
        ScriptText          = $ScriptBlock.ToString()
    }

    return $registration
}
