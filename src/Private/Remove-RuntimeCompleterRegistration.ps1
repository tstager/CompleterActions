function Remove-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes entries from PowerShell runtime completer dictionaries for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = Get-CompleterRuntime

    if ($PSCmdlet.ParameterSetName -eq 'ByKey')
    {
        $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $Key

        if ($null -eq $runtimeRegistration)
        {
            return
        }

        if ($runtimeRegistration.IsNative)
        {
            $target = Resolve-CompleterTarget -RuntimeKey $runtimeRegistration.RuntimeKey -Native
        }
        else
        {
            $target = Resolve-CompleterTarget -RuntimeKey $runtimeRegistration.RuntimeKey
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Native')
    {
        if (-not $Native)
        {
            throw 'Native target resolution requires the -Native switch.'
        }

        $target = Resolve-CompleterTarget -CommandName $CommandName -Native
    }
    else
    {
        $target = Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
    }

    $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

    if (-not $dictionary.ContainsKey($target.RuntimeKey))
    {
        return
    }

    $removedRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $dictionary[$target.RuntimeKey] -Source 'Discovered'
    $dictionary.Remove($target.RuntimeKey)

    return $removedRegistration
}
