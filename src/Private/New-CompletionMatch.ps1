<#
.SYNOPSIS
Creates a completion match record for a tested completer target.

.DESCRIPTION
Builds the CompletionMatch instance that Test-CompleterRegistration returns for
each completion result TabExpansion2 produced. The helper copies the target
metadata and the input that was completed alongside the completion result's
text, list item, result type, and tooltip.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, and IsNative properties.

.PARAMETER CompletionResult
The completion result returned by TabExpansion2 for the target.

.PARAMETER InputText
The input text that was completed.

.PARAMETER CursorPosition
The cursor position within InputText at which completion ran.

.PARAMETER FromTarget
Indicates that the target's own completer produced the completion result.

.OUTPUTS
CompleterActions.CompletionMatch
Returns a CompletionMatch instance for one completion result.

.EXAMPLE
PS> New-CompletionMatch -Target $target -CompletionResult $result -InputText 'git che' -CursorPosition 7 -FromTarget

Creates the completion match record for one TabExpansion2 result that the
resolved git native completer target produced.
#>
function New-CompletionMatch
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a completion match object.')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CompletionResult] $CompletionResult,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition,

        [Parameter()]
        [switch] $FromTarget
    )

    [CompleterActions.CompletionMatch] @{
        Key            = [string] $Target.Key
        RuntimeKey     = [string] $Target.RuntimeKey
        CommandName    = [string] $Target.CommandName
        ParameterName  = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative       = [bool] $Target.IsNative
        CompleterType  = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        InputText      = $InputText
        CursorPosition = $CursorPosition
        CompletionText = $CompletionResult.CompletionText
        ListItemText   = $CompletionResult.ListItemText
        ResultType     = $CompletionResult.ResultType
        ToolTip        = $CompletionResult.ToolTip
        FromTarget     = [bool] $FromTarget
    }
}
