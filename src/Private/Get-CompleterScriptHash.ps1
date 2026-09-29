<#
.SYNOPSIS
Computes the set file Hash of a completer script's text.

.DESCRIPTION
Returns 'SHA256:' followed by 64 uppercase hexadecimal digits: the SHA-256 of
the script's decoded text after every CR LF pair, and then every remaining lone
CR, is replaced with LF, encoded as UTF-8 without a byte-order mark. The same
script therefore hashes to one value whether it is checked out with CRLF on
Windows or LF on Linux, and whether or not it carries a byte-order mark.

-Text hashes text that is already decoded, such as a parse result's
Ast.Extent.Text, so a caller that has parsed the script does not read it a
second time. -LiteralPath reads the file with File.ReadAllText, which decodes
UTF-8 unless a byte-order mark names another encoding, as PowerShell's parser
does. ReadAllText resolves a relative path against the process directory, so
callers pass a full path.

.PARAMETER Text
The decoded script text to hash.

.PARAMETER LiteralPath
The full path of the script file to read and hash.

.OUTPUTS
System.String
#>
function Get-CompleterScriptHash
{
    [CmdletBinding(DefaultParameterSetName = 'LiteralPath')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        $Text = [System.IO.File]::ReadAllText($LiteralPath)
    }

    $normalizedText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try
    {
        $digest = $sha256.ComputeHash($bytes)
    }
    finally
    {
        $sha256.Dispose()
    }

    'SHA256:' + ([System.BitConverter]::ToString($digest) -replace '-', '')
}
