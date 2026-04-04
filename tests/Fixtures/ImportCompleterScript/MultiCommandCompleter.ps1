Register-ArgumentCompleter -CommandName 'Test-ImportedOne', 'Test-ImportedTwo' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('imported-shared', 'imported-shared', 'ParameterValue', 'imported-shared')
}
