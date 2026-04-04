Register-ArgumentCompleter -Native -CommandName $script:DynamicFixtureNames -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $wordToComplete, $commandAst, $cursorPosition
}
