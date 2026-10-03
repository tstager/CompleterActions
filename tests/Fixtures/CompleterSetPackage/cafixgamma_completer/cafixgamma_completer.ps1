Register-ArgumentCompleter -Native -CommandName 'cafixgamma', 'cafixgamma.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $commandAst, $cursorPosition

    foreach ($value in 'gamma-one', 'gamma-two')
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
