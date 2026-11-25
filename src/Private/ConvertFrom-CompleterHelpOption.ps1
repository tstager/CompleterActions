<#
.SYNOPSIS
Parses the option table out of cleaned help text.

.DESCRIPTION
Reads the text line by line with fixed rules. A line's indent is its count of
leading white-space characters. An option line starts, after its indent, with
a dash and a letter, digit, question mark, or period; with two dashes and a
letter or digit; with a slash and a letter, digit, or question mark; or is two
dashes alone or followed by white space.

While no option section is open, a section opens at a heading-shaped line
that is not a commands heading and whose next non-blank line is an option
line, or at an option line that is not under a commands heading when another
option line at the same indent follows it within its extent. A section with a
heading runs to the line before the next non-blank line indented no deeper
than the heading that is not an option line; one without a heading runs to
the line before the next non-blank line indented less than its first row that
is not an option line. Blank lines end neither.

The section indent is the smallest indent of an option line in the extent.
Rows are the option lines at that indent, and the lines that start with a long
name four columns deeper when no row at the section indent starts with a long
name. A line is under a commands heading while the subcommand parser's
commands section is open on it, unless an option heading has opened a section
since; such a line opens no section without a heading and is never a row.

A row holds names separated by a comma and an optional space, each followed
by at most one dropped placeholder: =TEXT or [=TEXT], a space and <TEXT>, a
space and one all-upper-case or all-lower-case word followed by a comma, two
or more spaces, or the end of the line, or one attached bracket or brace
group. The description is the text after the first run of two or more
spaces, a tab, or ' : ' after the names and placeholders; when that is empty,
the next non-blank line is used if it is deeper than the row and is not a
row. Descriptions are cleaned as subcommand descriptions are, and an empty
one becomes the name. Each name gives one row, in help order; a name already
seen, compared ordinally, is dropped.

.PARAMETER Text
Help text already cleaned by ConvertTo-CompleterCleanHelpText.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function ConvertFrom-CompleterHelpOption
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Copies of the locals of ConvertFrom-CompleterHelpText.ps1 (lines 34 to 40).
    # They decide what a heading and a commands heading are, and where a
    # commands section ends, exactly as the subcommand parser does. Keep the
    # two copies equal.
    $headerPattern = [regex]::new('^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$')
    $entryPattern = [regex]::new('^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$')
    $underlinePattern = [regex]::new('^\s*(?:=+|-+)\s*$')
    $headerWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('command', 'commands', 'subcommand', 'subcommands'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $optionLinePattern = [regex]::new('^(?:-[A-Za-z0-9?.]|--[A-Za-z0-9]|/[A-Za-z0-9?]|--(?:\s|$))')
    $longNamePattern = [regex]::new('^--[A-Za-z0-9]')
    $namePattern = [regex]::new('\G(?:--[A-Za-z0-9][A-Za-z0-9_-]*|-[A-Za-z0-9?.][A-Za-z0-9_-]*|/[A-Za-z0-9?]+)')
    $placeholderPattern = [regex]::new('\G(?:\[?=[^\s,]*| <[^>]*>| (?:[A-Z][A-Z0-9_-]*|[a-z][a-z0-9_-]*)(?=,| {2,}|\s*$)|\[[^\]]*\]|\{[^}]*\})')
    $listPattern = [regex]::new('\G, ?')
    $separatorPattern = [regex]::new(' {2,}|\t| : ')
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    $lines = $Text.Split("`n")
    $count = $lines.Length
    $isBlank = [bool[]]::new($count)
    $isOption = [bool[]]::new($count)
    $indent = [int[]]::new($count)
    $trimmedLines = [string[]]::new($count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $trimmed = $lines[$index].TrimStart()
        $trimmedLines[$index] = $trimmed
        $isBlank[$index] = [string]::IsNullOrWhiteSpace($trimmed)
        $indent[$index] = $lines[$index].Length - $trimmed.Length
        $isOption[$index] = $optionLinePattern.IsMatch($trimmed)
    }

    # First pass: which lines are under a commands heading, and which section
    # each line belongs to (-1 for none).
    $underCommands = [bool[]]::new($count)
    $sectionOf = [int[]]::new($count)
    [System.Array]::Fill($sectionOf, -1)
    $sectionIndents = [System.Collections.Generic.List[int]]::new()
    $inCommands = $false
    $commandsIndent = -1
    $sectionEnd = -1

    for ($index = 0; $index -lt $count; $index++)
    {
        $line = $lines[$index]

        # Follow the subcommand parser's commands section, so a line it reads
        # stays its own and no option section opens inside it.
        $isHeading = $false
        $isCommandsHeading = $false
        $header = $headerPattern.Match($line)
        if ($header.Success)
        {
            $isHeading = $true
            foreach ($word in $header.Groups['words'].Value.Split(' '))
            {
                if ($headerWords.Contains($word.Trim('(', ')', ',')))
                {
                    $isCommandsHeading = $true
                    break
                }
            }
        }

        if ($isCommandsHeading)
        {
            $inCommands = $true
            $commandsIndent = -1
        }
        elseif ($inCommands)
        {
            if ($isBlank[$index])
            {
                if ($commandsIndent -ge 0)
                {
                    $inCommands = $false
                }
            }
            elseif ($commandsIndent -lt 0)
            {
                if ($underlinePattern.IsMatch($line))
                {
                    $underCommands[$index] = $true
                }
                else
                {
                    $entry = $entryPattern.Match($line)
                    if ($entry.Success)
                    {
                        $commandsIndent = $entry.Groups['indent'].Length
                        $underCommands[$index] = $true
                    }
                    else
                    {
                        $inCommands = $false
                    }
                }
            }
            else
            {
                $entryIndent = $line.Length - $line.TrimStart(' ', "`t").Length
                if ($entryIndent -lt $commandsIndent -and $entryPattern.IsMatch($line))
                {
                    $inCommands = $false
                }
                else
                {
                    $underCommands[$index] = $true
                }
            }
        }

        if ($sectionEnd -lt $index)
        {
            $first = -1
            if ($isHeading -and -not $isCommandsHeading)
            {
                $next = $index + 1
                while ($next -lt $count -and $isBlank[$next])
                {
                    $next++
                }

                if ($next -lt $count -and $isOption[$next])
                {
                    $end = $index + 1
                    while ($end -lt $count -and ($isBlank[$end] -or $indent[$end] -gt $indent[$index] -or $isOption[$end]))
                    {
                        $end++
                    }

                    $first = $index + 1
                    $sectionEnd = $end - 1
                    $inCommands = $false
                }
            }
            elseif ($isOption[$index] -and -not $underCommands[$index])
            {
                $paired = $false
                $end = $index + 1
                while ($end -lt $count -and ($isBlank[$end] -or $indent[$end] -ge $indent[$index] -or $isOption[$end]))
                {
                    if ($isOption[$end] -and $indent[$end] -eq $indent[$index])
                    {
                        $paired = $true
                    }

                    $end++
                }

                if ($paired)
                {
                    $first = $index
                    $sectionEnd = $end - 1
                }
            }

            if ($first -ge 0)
            {
                $sectionIndent = [int]::MaxValue
                for ($row = $first; $row -le $sectionEnd; $row++)
                {
                    if ($isOption[$row] -and $indent[$row] -lt $sectionIndent)
                    {
                        $sectionIndent = $indent[$row]
                    }
                }

                $sectionIndents.Add($sectionIndent)
                for ($row = $first; $row -le $sectionEnd; $row++)
                {
                    $sectionOf[$row] = $sectionIndents.Count - 1
                }
            }
        }
    }

    # A section has a long row when one of its rows at the section indent
    # starts with a long name; a bare -- and a line under commands are not rows.
    $hasLongRow = [bool[]]::new($sectionIndents.Count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $section = $sectionOf[$index]
        if ($section -ge 0 -and $isOption[$index] -and -not $underCommands[$index] -and $indent[$index] -eq $sectionIndents[$section] -and $longNamePattern.IsMatch($trimmedLines[$index]))
        {
            $hasLongRow[$section] = $true
        }
    }

    $isRow = [bool[]]::new($count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $section = $sectionOf[$index]
        if ($section -lt 0 -or -not $isOption[$index] -or $underCommands[$index])
        {
            continue
        }

        $depth = $indent[$index] - $sectionIndents[$section]
        $isRow[$index] = $depth -eq 0 -or ($depth -eq 4 -and -not $hasLongRow[$section] -and $longNamePattern.IsMatch($trimmedLines[$index]))
    }

    for ($index = 0; $index -lt $count; $index++)
    {
        if (-not $isRow[$index])
        {
            continue
        }

        $rowText = $trimmedLines[$index]
        $names = [System.Collections.Generic.List[string]]::new()
        $position = 0
        $name = $namePattern.Match($rowText, 0)
        while ($name.Success)
        {
            $names.Add($name.Value)
            $position = $name.Index + $name.Length
            $placeholder = $placeholderPattern.Match($rowText, $position)
            if ($placeholder.Success)
            {
                $position += $placeholder.Length
            }

            $comma = $listPattern.Match($rowText, $position)
            if (-not $comma.Success)
            {
                break
            }

            $name = $namePattern.Match($rowText, $comma.Index + $comma.Length)
        }

        if ($names.Count -eq 0)
        {
            continue
        }

        $description = ''
        $separator = $separatorPattern.Match($rowText, $position)
        if ($separator.Success)
        {
            $description = $rowText.Substring($separator.Index + $separator.Length)
        }

        if ([string]::IsNullOrWhiteSpace($description))
        {
            $next = $index + 1
            while ($next -lt $count -and $isBlank[$next])
            {
                $next++
            }

            if ($next -lt $count -and $indent[$next] -gt $indent[$index] -and -not $isRow[$next])
            {
                $description = $trimmedLines[$next]
            }
        }

        $description = [regex]::Replace($description, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', ' ')
        $description = [regex]::Replace($description, '\s+', ' ').Trim()

        foreach ($optionName in $names)
        {
            if (-not $seen.Add($optionName))
            {
                continue
            }

            $rowDescription = $description
            if ($rowDescription.Length -eq 0)
            {
                $rowDescription = $optionName
            }

            [pscustomobject] [ordered] @{
                Name        = $optionName
                Description = $rowDescription
            }
        }
    }
}
