<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 through Import-PowerShellDataFile, which evaluates data only
and refuses anything that would run code, so a set file can never execute a
completer script or anything else. The file must declare Version 1 and a
non-empty Entries array; the entries themselves are validated one by one by
Resolve-CompleterSetEntry.

A set file larger than $script:CompleterSetMaxFileBytes (1 MB) is refused
before it is read; for a symbolic link, the size of its final target is
checked. Within that size the file is read with -SkipLimitCheck, because the
reader's default limits of 500 keys and 5000 syntax nodes reject an exported
set of a few hundred entries. The switch lifts only those limits: anything
that is not data is still refused. Export-CompleterSet refuses to write a set
over the same size, so every set it writes reads back.

.PARAMETER LiteralPath
The literal path to the completer set file.

.OUTPUTS
CompleterActions.CompleterSetDefinition
#>
function Import-CompleterSetDefinition
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $file = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop

    if ($file.PSIsContainer)
    {
        throw "Completer sets must be file paths. '$LiteralPath' is a directory."
    }

    if ($file.Extension -ne '.psd1')
    {
        throw "Completer sets must be .psd1 files. Received '$LiteralPath'."
    }

    # Get-Item reports a Windows symbolic link's own size, 0, so measure the
    # file the reader will actually open.
    $fileLength = ($file.ResolveLinkTarget($true) ?? $file).Length

    if ($fileLength -gt $script:CompleterSetMaxFileBytes)
    {
        throw "Completer set '$($file.FullName)' is $fileLength bytes, larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets."
    }

    $data = Import-PowerShellDataFile -LiteralPath $file.FullName -SkipLimitCheck -ErrorAction Stop

    if (-not $data.Contains('Version') -or $data['Version'] -ne 1)
    {
        throw "Completer set '$($file.FullName)' must declare Version = 1."
    }

    $entries = @()

    if ($data.Contains('Entries'))
    {
        $entries = @($data['Entries'] | Where-Object { $null -ne $_ })
    }

    if ($entries.Count -eq 0)
    {
        throw "Completer set '$($file.FullName)' has no Entries."
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterSetDefinition'
        Path       = $file.FullName
        Directory  = $file.DirectoryName
        Version    = 1
        Entries    = $entries
    }
}
