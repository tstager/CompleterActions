<#
.SYNOPSIS
Sets a value in a runtime completer dictionary by key.
#>
function Set-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        ([System.Collections.IDictionary] $Dictionary)[$Key] = $Value
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    $Dictionary[$Key] = $Value

    return $Dictionary[$Key]
}
