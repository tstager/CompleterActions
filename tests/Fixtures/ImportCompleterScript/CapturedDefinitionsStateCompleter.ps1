# Sample completer whose guarded script state is named CapturedCompleterDefinitions, a name
# the capture scope held for itself before 3.1.0.

if (-not (Get-Variable -Name CapturedCompleterDefinitions -Scope Script -ErrorAction SilentlyContinue))
{
    $script:CapturedCompleterDefinitions = @{
        Values = @('captured-alpha', 'captured-beta')
    }
}

Register-ArgumentCompleter -CommandName 'Test-CapturedDefinitionsStateTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters

    foreach ($value in $script:CapturedCompleterDefinitions.Values)
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
