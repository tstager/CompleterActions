<#
.SYNOPSIS
Parses the subcommand table out of cleaned help text.

.DESCRIPTION
Reads the text line by line with fixed rules. A section header is a whole line
of one to six words, optionally wrapped in angle brackets and followed by a
colon, one of which is command, commands, subcommand, or subcommands. After a
header, blank and underline lines are skipped and the first entry fixes the
section's indentation; any other line before the first entry ends the
section. Entries at that indentation are kept; deeper lines are
continuations and other non-entry lines are skipped. A blank line, a header,
or a shallower entry ends the section. Names keep help order and are
de-duplicated case-insensitively. Control, format, and line and paragraph
separator characters in a description become spaces, whitespace runs
collapse, and an empty description becomes the name.

.PARAMETER Text
Help text already cleaned by ConvertTo-CompleterCleanHelpText.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function ConvertFrom-CompleterHelpText
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $headerPattern = [regex]::new('^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$')
    $entryPattern = [regex]::new('^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$')
    $underlinePattern = [regex]::new('^\s*(?:=+|-+)\s*$')
    $headerWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('command', 'commands', 'subcommand', 'subcommands'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $inSection = $false
    $sectionIndent = -1

    foreach ($line in $Text.Split("`n"))
    {
        $header = $headerPattern.Match($line)
        if ($header.Success)
        {
            $isHeader = $false
            foreach ($word in $header.Groups['words'].Value.Split(' '))
            {
                if ($headerWords.Contains($word.Trim('(', ')', ',')))
                {
                    $isHeader = $true
                    break
                }
            }

            if ($isHeader)
            {
                $inSection = $true
                $sectionIndent = -1
                continue
            }
        }

        if (-not $inSection)
        {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line))
        {
            if ($sectionIndent -ge 0)
            {
                $inSection = $false
            }

            continue
        }

        if ($sectionIndent -lt 0)
        {
            if ($underlinePattern.IsMatch($line))
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                $inSection = $false
                continue
            }

            $sectionIndent = $entry.Groups['indent'].Length
        }
        else
        {
            $indent = $line.Length - $line.TrimStart(' ', "`t").Length
            if ($indent -gt $sectionIndent)
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                continue
            }

            if ($indent -lt $sectionIndent)
            {
                $inSection = $false
                continue
            }
        }

        $name = $entry.Groups['name'].Value
        if (-not $seen.Add($name))
        {
            continue
        }

        $description = [regex]::Replace($entry.Groups['desc'].Value, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', ' ')
        $description = [regex]::Replace($description, '\s+', ' ').Trim()
        if ($description.Length -eq 0)
        {
            $description = $name
        }

        [pscustomobject] [ordered] @{
            Name        = $name
            Description = $description
        }
    }
}
