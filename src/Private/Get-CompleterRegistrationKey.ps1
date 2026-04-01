function Get-CompleterRegistrationKey
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'RuntimeKey')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeKey,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [switch] $Native,

        [Parameter()]
        [ValidateSet('Parameter', 'Native')]
        [string] $CompleterType
    )

    $isNative = $Native.IsPresent -or $CompleterType -eq 'Native'

    if ($PSBoundParameters.ContainsKey('RuntimeKey'))
    {
        return $RuntimeKey.ToLowerInvariant()
    }

    if ($isNative)
    {
        return $CommandName.ToLowerInvariant()
    }

    return ('{0}:{1}' -f $CommandName, $ParameterName).ToLowerInvariant()
}
