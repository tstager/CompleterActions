<#
.SYNOPSIS
Makes a value from a file printable for an error message or a finding.

.DESCRIPTION
Replaces each control character, every character of the Unicode category Cc
such as a null character or a line break, with U+FFFD, and cuts a value longer
than 256 characters to its first 256, followed by '...'. A cut that would
leave the first half of a surrogate pair at the end is made one character
earlier. A value of 256 characters or fewer without a control character comes
back unchanged.

.PARAMETER Value
The text to make printable.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterPrintableText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $maximumLength = 256
    $text = $Value

    if ($text.Length -gt $maximumLength)
    {
        $length = if ([char]::IsHighSurrogate($text[$maximumLength - 1])) { $maximumLength - 1 } else { $maximumLength }
        $text = $text.Substring(0, $length) + '...'
    }

    [regex]::Replace($text, '\p{Cc}', [string] [char] 0xFFFD)
}
