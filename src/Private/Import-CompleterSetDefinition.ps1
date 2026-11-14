<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 through Import-PowerShellDataFile, which evaluates data only
and refuses anything that would run code, so a set file can never execute a
completer script or anything else. The file must declare Version 1 and a
non-empty Entries array; the entries themselves are validated one by one by
Resolve-CompleterSetEntry.

A set file that holds more than $script:CompleterSetMaxFileBytes (1 MB) is
refused before it is read as data. Its size is measured by reading it, never
more than one byte past the limit, because the size the file system reports
is 0 for a Windows symbolic link, a procfs file, or a device, whatever a read
of it returns. Within that size the file is read with -SkipLimitCheck,
because the reader's default limits of 500 keys and 5000 syntax nodes reject
an exported set of a few hundred entries. The switch lifts only those limits
and changes nothing else the reader accepts: an expression is still refused,
and a script block literal still comes back as a ScriptBlock value that
nothing runs. Export-CompleterSet refuses to write a set over the same size,
so every set it writes reads back. The limit bounds the bytes read, not the
parse time: the PowerShell parser compares each syntax error with every
earlier one, so 20,000 repeated keys (200 KB) take about 20 seconds to refuse
and a malformed file near the limit takes minutes.

Import-PowerShellDataFile opens the path again, so the measured file must
return the same bytes to both reads. The measuring stream stays open until
the data reader has read the file, which on Windows keeps other processes
from writing, replacing, or deleting it in between. Linux and macOS have no
such lock, and a symbolic link or junction in the path can be pointed
elsewhere on any platform, so there a set changed during the read can still
reach the data reader unmeasured. Changing a set that way takes write access
to its folder, which already decides what the set imports. A file that
cannot seek, such as a named pipe, can hand each open different bytes, so it
is refused before anything is read from it. Opening a named pipe still waits
until something writes to it.

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

    $stream = $null

    try
    {
        $stream = [System.IO.File]::OpenRead($file.FullName)

        if (-not $stream.CanSeek)
        {
            throw "Completer set '$($file.FullName)' is not a regular file. Completer sets must be regular files, not named pipes or other streams."
        }

        $byteCount = [System.IO.BinaryReader]::new($stream).ReadBytes($script:CompleterSetMaxFileBytes + 1).Length

        if ($byteCount -gt $script:CompleterSetMaxFileBytes)
        {
            throw "Completer set '$($file.FullName)' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets."
        }

        # The measuring stream is still open, so on Windows no other process
        # can change the file before the data reader has read it.
        $data = Import-PowerShellDataFile -LiteralPath $file.FullName -SkipLimitCheck -ErrorAction Stop
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }
    finally
    {
        if ($null -ne $stream)
        {
            $stream.Dispose()
        }
    }

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
