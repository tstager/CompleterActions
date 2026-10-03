<#
.SYNOPSIS
Derives the stem that names a generated completer script's state and function.

.DESCRIPTION
Drops one trailing .exe, .cmd, .bat, .ps1, or .com (compared
case-insensitively) from the primary command name, splits the rest on every
character that is not an ASCII letter or digit, upper-cases the first
character of each part with the invariant culture, and joins the parts. 'rg'
and 'rg.exe' give 'Rg', 'oh-my-posh' gives 'OhMyPosh', 'DSC' stays 'DSC', and
'7z' gives '7z'. The script names $script:<Stem>CompletionCatalog and
Complete-<Stem> after it.

.PARAMETER Name
The primary command name, already checked by ConvertTo-CompleterTargetName.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterScriptStem
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $baseName = $Name

    foreach ($suffix in '.exe', '.cmd', '.bat', '.ps1', '.com')
    {
        if ($baseName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $baseName = $baseName.Substring(0, $baseName.Length - $suffix.Length)
            break
        }
    }

    $parts = [System.Text.RegularExpressions.Regex]::Split($baseName, '[^A-Za-z0-9]+') | Where-Object { $_.Length -gt 0 }

    -join @($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
}
