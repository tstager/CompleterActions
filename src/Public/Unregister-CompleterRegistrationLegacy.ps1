<#
.ForwardHelpTargetName Unregister-Completer
.ForwardHelpCategory Function
#>
function Unregister-CompleterRegistrationLegacy
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The wrapper forwards -WhatIf and -Confirm to the wrapped command, which calls ShouldProcess.')]
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
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        Write-CompleterDeprecationWarning -LegacyName 'Unregister-CompleterRegistration' -NewName 'Unregister-Completer'

        $steppablePipeline = { Unregister-Completer @PSBoundParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $steppablePipeline.Begin($PSCmdlet)
    }

    process
    {
        $steppablePipeline.Process($_)
    }

    end
    {
        $steppablePipeline.End()
    }
}
