<#
.SYNOPSIS
Decodes the bytes a help probe captured into text.

.DESCRIPTION
Applies the help decoding steps in order. Bytes that start with the UTF-16 LE
byte-order mark FF FE, or that contain U+0000 when decoded leniently as UTF-8,
are decoded as UTF-16 LE. Otherwise the bytes are decoded as strict UTF-8,
after skipping a UTF-8 byte-order mark. When strict UTF-8 fails, Windows
decodes with the OEM code page of the current culture and Linux and macOS
decode with Latin-1 (code page 28591). A leading U+FEFF left by any decoder is
removed last. The text is not cleaned; ConvertTo-CompleterCleanHelpText does
that.

.PARAMETER Bytes
The captured bytes of one output stream.

.OUTPUTS
System.String
#>
function ConvertFrom-CompleterHelpOutput
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]] $Bytes
    )

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE)
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    elseif ([System.Text.Encoding]::UTF8.GetString($Bytes).Contains([char] 0))
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    else
    {
        $offset = 0
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
        {
            $offset = 3
        }

        try
        {
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
        catch [System.Text.DecoderFallbackException]
        {
            $codePage = if ($IsWindows)
            {
                [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            }
            else
            {
                28591
            }

            $text = [System.Text.Encoding]::GetEncoding($codePage).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF)
    {
        $text = $text.Substring(1)
    }

    $text
}
