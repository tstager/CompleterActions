<#
.SYNOPSIS
Creates a Register-CompleterRegistration-compatible import object.

.DESCRIPTION
Builds the public object emitted by Import-CompleterScript. The resulting object
captures normalized target metadata plus the imported ScriptBlock object from the
temporary import module so callers can pipe it directly into
Register-CompleterRegistration -InputObject.

.PARAMETER Target
The normalized completer target metadata.

.PARAMETER ScriptBlock
The imported completer script block.

.PARAMETER SourcePath
The source completer script path.

.PARAMETER ImportModule
The temporary module that owns the imported script block context.

.OUTPUTS
CompleterActions.ImportedCompleterRegistration
#>
function New-ImportedCompleterRegistration
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an import object.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSModuleInfo] $ImportModule
    )

    [pscustomobject] [ordered] @{
        PSTypeName      = 'CompleterActions.ImportedCompleterRegistration'
        Key             = [string] $Target.Key
        RegistrationKey = [string] $Target.Key
        RuntimeKey      = [string] $Target.RuntimeKey
        CommandName     = [string] $Target.CommandName
        ParameterName   = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative        = [bool] $Target.IsNative
        Native          = [bool] $Target.IsNative
        CompleterType   = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        TargetType      = [string] $Target.TargetType
        Source          = 'Imported'
        Path            = $SourcePath
        SourcePath      = $SourcePath
        ImportModule    = $ImportModule
        ScriptBlock     = $ScriptBlock
        ScriptText      = $ScriptBlock.ToString()
    }
}
