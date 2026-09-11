# Sample strict completer that conforms to the import grammar but throws while
# it loads: Get-Variable may run at script scope, and -ErrorAction Stop turns
# the missing variable into a terminating error before the registration below
# runs. Import-CompleterSet registers it lazily so the first tab press has to
# fail the load.

Get-Variable -Name 'CompleterActionsLazyFixtureMissing' -ErrorAction Stop

Register-ArgumentCompleter -CommandName 'Test-LazyStrictSetTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('never', 'never', 'ParameterValue', 'never')
}
