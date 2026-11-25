<#
.SYNOPSIS
Reads a PowerShell data file as data only, within the completer set file limit.

.DESCRIPTION
Reads a completer set file or a module manifest the way
Import-PowerShellDataFile reads a data file, except that the file is read
once, never more than one byte past $script:CompleterSetMaxFileBytes (128 KB),
and a file that holds more is not parsed: the result reports OverLimit, and
the caller words the refusal. The read is the measurement, because the size
the file system reports is 0 for a Windows symbolic link, a procfs file, or a
device, whatever a read of it returns. Opening a named pipe waits until
something writes to it, and the pipe is then read like a file.

The bytes read are decoded as Import-PowerShellDataFile decodes a file, as
UTF-8 unless a byte order mark names another encoding, and parsed. The data is
the first hashtable in the parse, the one Import-PowerShellDataFile takes,
evaluated by Ast.SafeGetValue, the data-only evaluator that cmdlet uses, so an
expression is refused and a script block literal comes back as a ScriptBlock
value that nothing runs. Parse errors, among them input nested too deeply for
the parser, which then returns no parse at all, and a file without a hashtable
throw the cmdlet's error text, as does a value the evaluator refuses.

The limit bounds the bytes parsed and so the parse time, though a malformed
file can still take minutes to refuse. A valid set of 95 KB parsed in 11
milliseconds when the limit was set. The parser's SaveError compares each new
error with every error saved before it, so the time to refuse a malformed file
grows with the square of its syntax errors, and a file can hold about one
error per byte. Measured at the limit: a file that repeats one key on every
line in about 11 bytes took 5.6 seconds (about 12,000 errors), one that
repeats it in 4 bytes 70 seconds (about 33,000), and a file of nothing but
closing parentheses or closing braces, one error per byte, 129 and 171
seconds. A set that Export-CompleterSet writes has no syntax errors.

-Text parses and evaluates text that is already decoded, such as a set that
Update-CompleterSet has rewritten in memory, the same way and with the same
error texts, except that a text without a hashtable is named as text. It reads
nothing and applies no size limit, so OverLimit is always $false.

.PARAMETER LiteralPath
The full path of the data file.

.PARAMETER Text
The decoded text of a data file, parsed instead of a file.

.PARAMETER SkipLimitCheck
Skips the evaluator's hashtable size check, as Import-PowerShellDataFile
-SkipLimitCheck does. The default limits of 500 keys and 5000 syntax nodes
apply otherwise.

.PARAMETER IncludeSource
Adds what was read to the result, so a caller that rewrites the file can
reproduce it: Bytes, the bytes read; Text, their decoded text, the text the
parse positions point into; Encoding, the encoding that decoded them; and
HasPreamble, whether the bytes start with that encoding's byte-order mark,
which the text does not contain.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns OverLimit, which is $true when the file holds more than the limit,
Data, the hashtable the file holds, and Ast, the parse of the bytes read.
Data and Ast are $null when OverLimit is $true. With -IncludeSource the record
also carries Bytes, Text, Encoding, and HasPreamble; Text, Encoding, and
HasPreamble are $null when OverLimit is $true.
#>
function Import-CompleterDataFile
{
    [CmdletBinding(DefaultParameterSetName = 'LiteralPath')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [switch] $SkipLimitCheck,

        [Parameter(ParameterSetName = 'LiteralPath')]
        [switch] $IncludeSource
    )

    $encoding = $null
    $hasPreamble = $null

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        try
        {
            $stream = [System.IO.File]::OpenRead($LiteralPath)

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
            $result = [pscustomobject] [ordered] @{ OverLimit = $true; Data = $null; Ast = $null }

            if ($IncludeSource)
            {
                $result | Add-Member -NotePropertyMembers ([ordered] @{ Bytes = $bytes; Text = $null; Encoding = $null; HasPreamble = $null })
            }

            return $result
        }

        $reader = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($bytes), [System.Text.UTF8Encoding]::new($false))
        $Text = $reader.ReadToEnd()
        # The reader names the encoding a byte-order mark selected only after it has read.
        $encoding = $reader.CurrentEncoding
        $preamble = $encoding.GetPreamble()
        $hasPreamble = $preamble.Length -gt 0 -and $bytes.Length -ge $preamble.Length -and [System.Linq.Enumerable]::SequenceEqual([byte[]] $preamble, [byte[]] $bytes[0..($preamble.Length - 1)])
    }

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, $LiteralPath, [ref] $null, [ref] $parseErrors)
    # A parser that gives up on input nested too deeply returns no AST, only its error.
    $hashtable = if ($parseErrors.Count -eq 0) { $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false) }

    if ($null -eq $hashtable)
    {
        if ($PSCmdlet.ParameterSetName -eq 'Text')
        {
            throw 'The text could not be parsed as a PowerShell Data File.'
        }

        throw "The file '$LiteralPath' could not be parsed as a PowerShell Data File."
    }

    try
    {
        $data = $hashtable.SafeGetValue($SkipLimitCheck.IsPresent)
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }

    $result = [pscustomobject] [ordered] @{ OverLimit = $false; Data = $data; Ast = $ast }

    if ($IncludeSource)
    {
        $result | Add-Member -NotePropertyMembers ([ordered] @{ Bytes = $bytes; Text = $Text; Encoding = $encoding; HasPreamble = $hasPreamble })
    }

    $result
}
