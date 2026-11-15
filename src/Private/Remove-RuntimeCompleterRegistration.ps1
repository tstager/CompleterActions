<#
.SYNOPSIS
Removes a completer registration directly from the live PowerShell runtime.

.DESCRIPTION
Targets the current session's runtime completer dictionaries and removes the
matching discovered registration. Maintainers use this helper when internal
module workflows need to reconcile or replace registrations that already exist
in PowerShell's live runtime state. Only the dictionary of the target's kind is
touched, so removing a parameter target never removes a native entry that
shares its key, and the reverse.

This helper mutates dictionaries reached through PowerShell runtime internals,
not a public management API. It is therefore intentionally private and should
only be used from higher-level module operations that already understand the
runtime caveats and session-scoped effects.

.PARAMETER Target
The completer target or registration record whose runtime entry to remove. It
must expose RuntimeKey and IsNative.

.PARAMETER CommandName
The command or native executable name that identifies the completer target to
remove.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target to remove.

.PARAMETER Native
Indicates that the target to remove is a native completer registration.

.OUTPUTS
CompleterActions.CompleterRegistration

.EXAMPLE
Remove-RuntimeCompleterRegistration -Target $registration

Removes the live runtime entry for the target of a registration record from
the dictionary of that record's kind.

.EXAMPLE
Remove-RuntimeCompleterRegistration -CommandName git -Native

Shows how a native completer registration can be removed from the live runtime
dictionary during internal reconciliation.

.NOTES
This helper changes live session state by removing entries from runtime
dictionaries obtained through reflection-backed helpers. If PowerShell changes
those internals, both the targeting logic and the runtime access helper may need
to be updated together.
#>
function Remove-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'Target')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes entries from PowerShell runtime completer dictionaries for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

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

    $runtime = $null
    $runtimeRegistration = $null
    $removalTarget = $null
    $dictionary = $null

    try
    {
        $removalTarget = switch ($PSCmdlet.ParameterSetName)
        {
            'Target' { $Target }
            'Native'
            {
                if (-not $Native)
                {
                    throw 'Native target resolution requires the -Native switch.'
                }

                Resolve-CompleterTarget -CommandName $CommandName -Native
            }
            'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
        }

        $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $removalTarget

        if ($null -eq $runtimeRegistration)
        {
            return
        }

        $runtime = Get-CompleterRuntime
        $dictionary = if ($runtimeRegistration.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
        $null = Remove-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeRegistration.RuntimeKey

        return $runtimeRegistration
    }
    catch
    {
        $targetDescription = if ($null -ne $removalTarget) { $removalTarget.RuntimeKey } else { $CommandName }
        throw "Failed to remove the runtime completer registration '$targetDescription'. $($_.Exception.Message)"
    }
    finally
    {
        $runtime = $null
        $runtimeRegistration = $null
        $removalTarget = $null
        $dictionary = $null
    }
}
