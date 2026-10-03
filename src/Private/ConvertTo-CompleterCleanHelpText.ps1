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

    # Removing [^\x08]\x08 until stable and then any remaining \x08 is done in
    # linear time: one regex pass removes the simple overstrikes, then a run of
    # n backspaces erases up to n characters before it, and the backspaces left
    # over are dropped. Pair removal gives the same result in any order.
    $clean = [regex]::Replace($clean, '[^\x08]\x08', '')
    $backspaceRuns = [regex]::Matches($clean, '\x08+')
    if ($backspaceRuns.Count -gt 0)
    {
        $builder = [System.Text.StringBuilder]::new($clean.Length)
        $start = 0
        foreach ($run in $backspaceRuns)
        {
            $null = $builder.Append($clean.Substring($start, $run.Index - $start))
            $builder.Length -= [System.Math]::Min($run.Length, $builder.Length)
            $start = $run.Index + $run.Length
        }

        $null = $builder.Append($clean.Substring($start))
        $clean = $builder.ToString()
    }

    $clean = $clean.Replace("`r`n", "`n")

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
