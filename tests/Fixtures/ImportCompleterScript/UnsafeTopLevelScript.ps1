Get-Date | Out-Null

Register-ArgumentCompleter -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('unsafe', 'unsafe', 'ParameterValue', 'unsafe')
}
