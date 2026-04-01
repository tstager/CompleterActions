function Resolve-CompleterTarget
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to select native-specific parameter sets and to derive the target kind.')]
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
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'RuntimeKey')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeKey
    )

    $resolvedCommandName = $CommandName
    $resolvedParameterName = $ParameterName
    $resolvedIsNative = $false

    switch ($PSCmdlet.ParameterSetName)
    {
        'Native'
        {
            $resolvedIsNative = [bool] $Native
            $RuntimeKey = $CommandName
            break
        }

        'CommandParameter'
        {
            $RuntimeKey = '{0}:{1}' -f $CommandName, $ParameterName
            break
        }

        'NativeRuntimeKey'
        {
            $resolvedCommandName = $RuntimeKey
            $resolvedParameterName = $null
            $resolvedIsNative = [bool] $Native
            break
        }

        'RuntimeKey'
        {
            $match = [System.Text.RegularExpressions.Regex]::Match($RuntimeKey, '^(.*):([^:]+)$')

            if (-not $match.Success)
            {
                throw "Parameter completer runtime keys must use the format 'Command:Parameter'. Received '$RuntimeKey'."
            }

            $resolvedCommandName = $match.Groups[1].Value
            $resolvedParameterName = $match.Groups[2].Value
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedCommandName))
    {
        throw 'Completer targets require a non-empty command name.'
    }

    if (-not $resolvedIsNative -and [string]::IsNullOrWhiteSpace($resolvedParameterName))
    {
        throw 'Command-parameter completer targets require a non-empty parameter name.'
    }

    $resolvedKey = Get-CompleterRegistrationKey -RuntimeKey $RuntimeKey

    $target = [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterTarget'
        Key           = $resolvedKey
        RuntimeKey    = $RuntimeKey
        CommandName   = $resolvedCommandName
        ParameterName = if ($resolvedIsNative) { $null } else { $resolvedParameterName }
        IsNative      = $resolvedIsNative
        TargetType    = if ($resolvedIsNative) { 'Native' } else { 'CommandParameter' }
    }

    return $target
}
