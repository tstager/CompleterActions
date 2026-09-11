# Sample completer that throws while it is dot-sourced. It is registered lazily
# through the trusted tier with explicit targets so the first tab press has to
# fail the load; the registration call below is never reached.

throw 'lazy fixture import failure'

Register-ArgumentCompleter -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('never', 'never', 'ParameterValue', 'never')
}
