<#
.SYNOPSIS
Removes terminal formatting from help text.

.DESCRIPTION
Applies the help cleaning rules in order: CSI sequences, OSC sequences such as
titles and OSC 8 hyperlinks (only the link text remains), any remaining
two-character escape, backspace overstrikes, and carriage returns. CR LF
becomes LF, and then each line keeps only the text after its last remaining
CR, which removes progress lines. The probe output and -HelpText both go
through this cleaner before parsing. The result uses LF line endings.

.PARAMETER Text
The decoded help text.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterCleanHelpText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $clean = [regex]::Replace($Text, '\e\[[0-9;?]*[ -/]*[@-~]', '')
    $clean = [regex]::Replace($clean, '\e\][^\a\e]*(?:\a|\e\\)', '')
    $clean = [regex]::Replace($clean, '\e[@-_]', '')

    $overstrike = [regex]::new('[^\x08]\x08')
    while ($overstrike.IsMatch($clean))
    {
        $clean = $overstrike.Replace($clean, '')
    }

    $clean = $clean.Replace([string] [char] 0x08, '').Replace("`r`n", "`n")

    $lines = $clean.Split("`n")
    for ($index = 0; $index -lt $lines.Length; $index++)
    {
        $lastReturn = $lines[$index].LastIndexOf("`r")
        if ($lastReturn -ge 0)
        {
            $lines[$index] = $lines[$index].Substring($lastReturn + 1)
        }
    }

    $lines -join "`n"
}
