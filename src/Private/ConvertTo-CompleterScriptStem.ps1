<#
.SYNOPSIS
Derives the stem that names a generated completer script's state and function.

.DESCRIPTION
Drops one trailing .exe, .cmd, .bat, .ps1, or .com (compared
case-insensitively) from the primary command name, splits the rest on every
character that is not an ASCII letter or digit, upper-cases the first
character of each part with the invariant culture, and joins the parts. 'rg'
and 'rg.exe' give 'Rg', 'DSC' stays 'DSC', and '7z' gives '7z'. When the split
dropped a character, the joined parts are followed by '_' and the first eight
lower-case hex digits of the SHA-256 of the UTF-8 name without its suffix, so
names that differ only in punctuation, such as 'ca-tool' and 'ca_tool', do not
share a stem: 'oh-my-posh' gives 'OhMyPosh_' and eight hex digits. An empty
join is returned as is, for ConvertTo-CompleterTargetName to reject. The
script names $script:<Stem>CompletionCatalog and Complete-<Stem> after it, and
dot-sourced scripts share one scope, so the stem must be distinct per command.

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
    $stem = -join @($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })

    if ($stem.Length -eq 0 -or $stem.Length -eq $baseName.Length)
    {
        return $stem
    }

    # Joining the parts drops the separators, so 'ca-tool' and 'ca_tool' would share one stem.
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($baseName))
    '{0}_{1}' -f $stem, [System.Convert]::ToHexString($hash, 0, 4).ToLowerInvariant()
}
