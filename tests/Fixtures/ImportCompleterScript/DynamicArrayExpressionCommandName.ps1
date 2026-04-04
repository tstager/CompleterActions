Register-ArgumentCompleter -CommandName @($script:DynamicCommandName, 'Test-ImportedArrayTwo') -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('dynamic-array', 'dynamic-array', 'ParameterValue', 'dynamic-array')
}
