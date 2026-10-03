Register-ArgumentCompleter -Native -CommandName 'cafixbeta', 'cafixbeta.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $commandAst, $cursorPosition

    foreach ($value in 'beta-one', 'beta-two')
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
