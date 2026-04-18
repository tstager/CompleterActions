<#
.SYNOPSIS
Removes and returns a value from a runtime completer dictionary by key.
#>
function Remove-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
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
        $removedValue = ([System.Collections.IDictionary] $Dictionary)[$Key]
        ([System.Collections.IDictionary] $Dictionary).Remove($Key)
        return $removedValue
    }

    $removedValue = $Dictionary[$Key]
    $null = $Dictionary.Remove($Key)

    return $removedValue
}
