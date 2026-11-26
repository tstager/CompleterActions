# Sample completer that passes an array to -ParameterName. Register-ArgumentCompleter binds
# a single parameter name, so the script fails when it is dot-sourced by itself and the
# strict grammar refuses it; the trusted tier still imports one record per name.

Register-ArgumentCompleter -CommandName 'Test-ImportedParameterArrayTool' -ParameterName @('Name', 'Path') -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('parameter-array', 'parameter-array', 'ParameterValue', 'parameter-array')
}
