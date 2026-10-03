<#
.SYNOPSIS
Builds the native target list a generated completer script registers.

.DESCRIPTION
Checks every command name before building anything, and throws for the first
name that is not a bare command name: at least one ASCII letter or digit, no
path separators, spaces, quotes, or wildcard characters, no leading '-' or
'.', and no trailing '.' or '-'. A name that passes but whose stem would be
empty, such as '_.exe', whose only letters are its suffix, is then refused
with its own reason, so no function name is ever derived from an empty stem.
The list then follows the -CommandName order.
Each name is written as given, and a name that does not end in .exe, .cmd,
.bat, .ps1, or .com is followed by the same name with .exe appended. Names are
de-duplicated case-insensitively, keeping the first spelling, so 'rg' and
'rg', 'rg.exe' give the same list, and no bare name is derived from a suffixed
one.

.PARAMETER CommandName
The command names, primary name first.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterTargetName
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName
    )

    # The spec's pattern, with \z in place of $ so a trailing newline does not match.
    $commandNamePattern = '^(?=.*[A-Za-z0-9])[A-Za-z0-9_](?:[A-Za-z0-9._+-]*[A-Za-z0-9_+])?\z'

    foreach ($commandNameItem in $CommandName)
    {
        if (-not [System.Text.RegularExpressions.Regex]::IsMatch($commandNameItem, $commandNamePattern))
        {
            throw "'$commandNameItem' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters."
        }

        if ([string]::IsNullOrEmpty((ConvertTo-CompleterScriptStem -Name $commandNameItem)))
        {
            throw "The command name '$commandNameItem' has no letter or digit outside its suffix, so no function name can be derived from it."
        }
    }

    $suffixes = '.exe', '.cmd', '.bat', '.ps1', '.com'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetNames = [System.Collections.Generic.List[string]]::new()

    foreach ($commandNameItem in $CommandName)
    {
        $names = @($commandNameItem)
        $hasSuffix = @($suffixes | Where-Object { $commandNameItem.EndsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0

        if (-not $hasSuffix)
        {
            $names += '{0}.exe' -f $commandNameItem
        }

        foreach ($name in $names)
        {
            if ($seen.Add($name))
            {
                $targetNames.Add($name)
            }
        }
    }

    $targetNames.ToArray()
}
