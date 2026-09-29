# Hash fixture for Export-CompleterSet tests. The comment carries one non-ASCII
# character (café) so the Hash is taken over decoded text, not raw bytes. It
# registers HashFixture.exe before hashfixture, which is not the order
# Get-Completer sorts them in.

Register-ArgumentCompleter -Native -CommandName 'HashFixture.exe', 'hashfixture' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $commandAst, $cursorPosition

    foreach ($value in 'hash-alpha', 'hash-beta')
    {
        if ($value -like "$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
