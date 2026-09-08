<#
.SYNOPSIS
Determines whether a key-only input should be treated as a native completer target.

.DESCRIPTION
Applies the module's shared rule for classifying a key when no explicit native
indicator is available. A key without a colon is a native command name. A key
with a colon is still native when it has the Windows drive-qualified path shape
(a single letter, a colon, then a path separator) or when the text after its
last colon contains a path separator, because a 'Command:Parameter' key never
contains a path separator in its parameter part. Every other colon-bearing key
is a command-parameter target.

.PARAMETER Key
The registration or runtime key to classify.

.OUTPUTS
System.Boolean
Returns $true when the key should be resolved as a native completer target.

.EXAMPLE
Test-CompleterNativeKeyShape -Key 'C:\tools\example.exe'

Returns $true because the key is a drive-qualified native path.

.EXAMPLE
Test-CompleterNativeKeyShape -Key 'Get-Item:Path'

Returns $false because the key is a command-parameter key.

.NOTES
Resolve-CompleterTargetList and Resolve-CompleterInputObject both use this
helper so key-only inputs classify identically on every public path.
#>
function Test-CompleterNativeKeyShape
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if ($Key -notmatch ':')
    {
        return $true
    }

    if ($Key -match '^[A-Za-z]:[\/]')
    {
        return $true
    }

    $parameterPart = $Key.Substring($Key.LastIndexOf(':') + 1)

    return $parameterPart.IndexOfAny([char[]] @('\', '/')) -ge 0
}
