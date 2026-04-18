<#
.SYNOPSIS
Tests whether a runtime completer dictionary contains a key.
#>
function Test-CompleterRuntimeDictionaryKey
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary).Contains($Key)
    }

    return $Dictionary.ContainsKey($Key)
}
