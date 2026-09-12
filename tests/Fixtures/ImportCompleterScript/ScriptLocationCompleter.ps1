# Sample native completer that reports where its script lives. Used to prove
# that an imported completer keeps its source-file location.

function Get-ScriptLocationCompletionResult
{
    param(
        [Parameter(Mandatory)]
        [string] $CompletionText
    )

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        'ParameterValue',
        $CompletionText
    )
}

Register-ArgumentCompleter -Native -CommandName 'locationfixture' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $wordToComplete, $commandAst, $cursorPosition

    Get-ScriptLocationCompletionResult -CompletionText $PSScriptRoot
    Get-ScriptLocationCompletionResult -CompletionText $PSCommandPath
}
