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
        [string] $Source = 'Managed'
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
        IsManaged           = $Source -eq 'Managed'
        IsRuntimeRegistered = $true
        ScriptBlock         = $ScriptBlock
        ScriptText          = $ScriptBlock.ToString()
    }

    return $registration
}
