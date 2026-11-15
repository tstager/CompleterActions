<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 once and evaluates it as data only, so a set file can never
execute a completer script or anything else. The file must declare Version 1
and a non-empty Entries array; the entries themselves are validated one by one
by Resolve-CompleterSetEntry.

The file is read once, never more than one byte past
$script:CompleterSetMaxFileBytes (128 KB), and a file that holds more is
refused before it is parsed. The read is the measurement, because the size the
file system reports is 0 for a Windows symbolic link, a procfs file, or a
device, whatever a read of it returns. Opening a named pipe waits until
something writes to it, and the pipe is then read like a file.

The bytes read are decoded as Import-PowerShellDataFile decodes a file, as
UTF-8 unless a byte order mark names another encoding, and parsed. The data is
the first hashtable in the parse, the one Import-PowerShellDataFile takes,
evaluated by Ast.SafeGetValue, the data-only evaluator that cmdlet uses, so an
expression is refused and a script block literal comes back as a ScriptBlock
value that nothing runs. Parse errors and a file without a hashtable get the
cmdlet's error text. Nothing opens the file again: the definition carries the
parse, and Test-CompleterSet takes its positions from it, so a set rewritten
during an import or a test reaches no later step and nothing past the limit is
ever parsed.

SafeGetValue skips its hashtable size check, as Import-PowerShellDataFile
-SkipLimitCheck does, because the default limits of 500 keys and 5000 syntax
nodes reject an exported set of a few hundred entries. Skipping them changes
nothing else the evaluator accepts. Export-CompleterSet refuses to write a set
over the same size, so every set it writes reads back.

The limit bounds the bytes parsed and so the parse time. A valid set of 95 KB
parsed in 11 milliseconds when the limit was set, but the time the PowerShell
parser takes to refuse a malformed file grows with the square of its syntax
errors: a file that repeats one key on every line took 0.4 seconds to refuse
at 32 KB and 5.6 seconds at 128 KB, about 12,000 errors.

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

    try
    {
        $stream = [System.IO.File]::OpenRead($file.FullName)

        try
        {
            $bytes = [System.IO.BinaryReader]::new($stream).ReadBytes($script:CompleterSetMaxFileBytes + 1)
        }
        finally
        {
            $stream.Dispose()
        }
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }

    if ($bytes.Length -gt $script:CompleterSetMaxFileBytes)
    {
        throw "Completer set '$($file.FullName)' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets."
    }

    $text = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($bytes), [System.Text.UTF8Encoding]::new($false)).ReadToEnd()
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $file.FullName, [ref] $null, [ref] $parseErrors)
    $setHashtable = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)

    if ($parseErrors.Count -gt 0 -or $null -eq $setHashtable)
    {
        throw "The file '$($file.FullName)' could not be parsed as a PowerShell Data File."
    }

    try
    {
        $data = $setHashtable.SafeGetValue($true)
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
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
        Ast        = $ast
    }
}
