Register-ArgumentCompleter -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('imported-alpha', 'imported-alpha', 'ParameterValue', 'imported-alpha')
}
