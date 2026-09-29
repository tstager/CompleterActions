<#
.SYNOPSIS
Tests whether a set entry's Hash value has a form this module recognises.

.DESCRIPTION
Returns $true only for a string made of the prefix 'SHA256:' and 64
hexadecimal digits, compared case-insensitively. Any other value, including a
non-string, an empty string, or an unknown prefix such as 'SHA512:', returns
$false, so a reader treats the Hash as absent and falls back to parsing the
script instead of failing.

.PARAMETER Value
The Hash value read from a set entry.

.OUTPUTS
System.Boolean
#>
function Test-CompleterSetHashFormat
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [object] $Value
    )

    $Value -is [string] -and [regex]::IsMatch($Value, '\ASHA256:[0-9A-F]{64}\z', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
