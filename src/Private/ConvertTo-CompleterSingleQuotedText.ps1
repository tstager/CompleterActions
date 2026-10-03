<#
.SYNOPSIS
Escapes text for a single-quoted PowerShell string literal.

.DESCRIPTION
Doubles every character PowerShell's tokenizer accepts as a single-quote
delimiter: U+0027, U+2018, U+2019, U+201A, and U+201B. Help text such as
"don't" written with a typographic apostrophe would otherwise end the string.
Every other character is kept as is. The result goes between two U+0027
quotes.

.PARAMETER Value
The text to escape.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterSingleQuotedText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $escaped = $Value

    foreach ($quote in [char] 0x0027, [char] 0x2018, [char] 0x2019, [char] 0x201A, [char] 0x201B)
    {
        $escaped = $escaped.Replace([string] $quote, [string] $quote + $quote)
    }

    $escaped
}
