<#
.ForwardHelpTargetName Get-Completer
.ForwardHelpCategory Function
#>
function Get-CompleterRegistrationLegacy
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
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
        [ValidateNotNullOrEmpty()]
        [CompleterState[]] $State,

        [Parameter()]
        [switch] $ManagedOnly,

        [Parameter()]
        [switch] $DiscoveredOnly
    )

    begin
    {
        Write-CompleterDeprecationWarning -LegacyName 'Get-CompleterRegistration' -NewName 'Get-Completer'

        if (($ManagedOnly -and $DiscoveredOnly) -or (($ManagedOnly -or $DiscoveredOnly) -and $PSBoundParameters.ContainsKey('State')))
        {
            throw 'ManagedOnly, DiscoveredOnly, and State cannot be used together.'
        }

        $forwardedParameters = [hashtable] $PSBoundParameters
        $null = $forwardedParameters.Remove('ManagedOnly')
        $null = $forwardedParameters.Remove('DiscoveredOnly')

        if ($ManagedOnly)
        {
            $forwardedParameters['State'] = [CompleterState[]] @('Active', 'Pending', 'Failed', 'Stale')
        }
        elseif ($DiscoveredOnly)
        {
            $forwardedParameters['State'] = [CompleterState[]] @('Discovered', 'Conflicted')
        }

        $steppablePipeline = { Get-Completer @forwardedParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
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
