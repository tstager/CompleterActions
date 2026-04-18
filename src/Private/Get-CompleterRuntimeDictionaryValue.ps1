<#
.SYNOPSIS
Gets a value from a runtime completer dictionary by key.
#>
function Get-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if (-not (Test-CompleterRuntimeDictionaryKey -Dictionary $Dictionary -Key $Key))
    {
        return $null
    }

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    return $Dictionary[$Key]
}
