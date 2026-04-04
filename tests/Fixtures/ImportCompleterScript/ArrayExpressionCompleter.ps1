Register-ArgumentCompleter -CommandName @('Test-ImportedArrayOne', 'Test-ImportedArrayTwo') -ParameterName @('Name', 'Path') -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('array-target', 'array-target', 'ParameterValue', 'array-target')
}
