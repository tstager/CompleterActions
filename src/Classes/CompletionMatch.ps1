class CompletionMatch
{
    CompletionMatch()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompletionMatch')
    }

    [string] $Key
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [CompleterType] $CompleterType
    [string] $InputText
    [int] $CursorPosition
    [string] $CompletionText
    [string] $ListItemText
    [System.Management.Automation.CompletionResultType] $ResultType
    [string] $ToolTip
}
