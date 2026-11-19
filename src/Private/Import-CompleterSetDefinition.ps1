<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 once and evaluates it as data only, so a set file can never
execute a completer script or anything else. The file must declare Version 1
and a non-empty Entries array; the entries themselves are validated one by one
by Resolve-CompleterSetEntry.

Import-CompleterDataFile does the read: never more than one byte past
$script:CompleterSetMaxFileBytes (128 KB), with a larger file refused before
it is parsed, and with the evaluator Import-PowerShellDataFile uses and the
cmdlet's error text. The read is the measurement, so a symbolic link, a procfs
file whose reported size is 0, or a named pipe is held to the limit too.

The set file is not read by its own path again: the definition carries the
parse, and Test-CompleterSet takes its positions from it, so a set rewritten
during an import or a test cannot change the entries checked or the line and
column of a finding. The module manifests read to find a set by -Name or to
check a packaged set's layout are read by their own paths, held to the same
limit. The scripts the entries name are read by theirs and parsed in full,
because a completer script can be larger than a set. A link can make one of
those paths another name for the set file, and that read then sees the file
as it is at that moment.

The evaluator's hashtable size check is skipped, as Import-PowerShellDataFile
-SkipLimitCheck skips it, because the default limits of 500 keys and 5000
syntax nodes reject an exported set of a few hundred entries. Skipping them
changes nothing else the evaluator accepts. Export-CompleterSet refuses to
write a set over the size limit, so every set it writes reads back.

The limit bounds the bytes parsed and so the parse time, though a malformed
file can still take minutes to refuse; Import-CompleterDataFile gives the
measurements.

.PARAMETER LiteralPath
The literal path to the completer set file.

.OUTPUTS
CompleterActions.CompleterSetDefinition
Returns one record with Path and Directory, the set file's full path and
folder, Version, Entries, the set's non-null entries in order, and Ast, the
parse of the bytes that were read.
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

    $dataFile = Import-CompleterDataFile -LiteralPath $file.FullName -SkipLimitCheck

    if ($dataFile.OverLimit)
    {
        throw "Completer set '$($file.FullName)' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets."
    }

    $data = $dataFile.Data
    $version = $data['Version']

    # -eq converts 1 to the type on its left, so $true or [char]1 would equal
    # it and an array would be filtered rather than compared: only a number of
    # one of these exact types is compared with 1. Text is compared ordinally,
    # because string -eq is culture-aware and takes '1' followed by a
    # zero-width space, or an Arabic-Indic one, as equal to '1'.
    $numberTypes = [sbyte], [byte], [int16], [uint16], [int], [uint32], [long], [uint64], [single], [double], [decimal], [bigint]

    $isVersionOne = if ($version -is [string])
    {
        [string]::Equals($version, '1', [System.StringComparison]::Ordinal)
    }
    else
    {
        $null -ne $version -and $version.GetType() -in $numberTypes -and $version -eq 1
    }

    if (-not $isVersionOne)
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
        Ast        = $dataFile.Ast
    }
}