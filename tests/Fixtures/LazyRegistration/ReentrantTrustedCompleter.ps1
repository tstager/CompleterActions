# Sample trusted completer whose script scope requests tab completion for its
# own target while it loads, so the lazy stub is re-entered for a key whose
# load is already in flight. The nested result is kept in an environment
# variable for the tests to inspect; the registration below runs after it.

$nestedInput = 'Test-LazyTrustedTool -Name '
$env:CompleterActionsReentrantNestedResult = @((TabExpansion2 -InputScript $nestedInput -CursorColumn $nestedInput.Length).CompletionMatches.CompletionText) -join '|'

Register-ArgumentCompleter -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('reentrant-alpha', 'reentrant-alpha', 'ParameterValue', 'reentrant-alpha')
}
