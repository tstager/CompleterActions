Register-ArgumentCompleter -Native -CommandName 'cafixalpha', 'cafixalpha.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $commandAst, $cursorPosition

    foreach ($value in 'alpha-one', 'alpha-two')
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
