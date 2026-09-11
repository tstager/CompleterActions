# Sample completer whose guarded script state uses a [pscustomobject] literal.
# The guard shape is import-safe, but the type cast inside it is not.

if (-not (Get-Variable -Name GuardedObjectFixtureState -Scope Script -ErrorAction SilentlyContinue))
{
    $script:GuardedObjectFixtureState = [pscustomobject] @{
        Values = @('object-alpha', 'object-beta')
    }
}

Register-ArgumentCompleter -CommandName 'Test-GuardedObjectFixtureTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters

    foreach ($value in $script:GuardedObjectFixtureState.Values)
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
