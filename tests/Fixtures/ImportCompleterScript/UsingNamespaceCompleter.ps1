# Sample native completer that relies on a top-level 'using namespace'
# statement. Used to prove that an imported completer still resolves the
# namespaced types in its helper function and in the completer block.

using namespace System.Collections.Generic
using namespace System.Management.Automation

function Get-UsingNamespaceCompletionValue
{
    [List[string]] $values = [List[string]]::new()
    $values.Add('ns-alpha')
    $values.Add('ns-beta')

    return $values
}

Register-ArgumentCompleter -Native -CommandName 'namespacefixture' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $commandAst, $cursorPosition

    [HashSet[string]] $seen = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($value in Get-UsingNamespaceCompletionValue)
    {
        if ($value -like "$wordToComplete*" -and $seen.Add($value))
        {
            [CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}
