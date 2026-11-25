# Sample completer whose guarded script state is named ScriptInfo, a name the capture
# scope held for itself before 3.1.0.

if (-not (Get-Variable -Name ScriptInfo -Scope Script -ErrorAction SilentlyContinue))
{
    $script:ScriptInfo = @{
        Values = @('script-info-alpha', 'script-info-beta')
    }
}

Register-ArgumentCompleter -CommandName 'Test-ScriptInfoStateTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters

    foreach ($value in $script:ScriptInfo.Values)
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
