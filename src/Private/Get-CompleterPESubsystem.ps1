<#
.SYNOPSIS
Reads the Subsystem field of a Windows program's PE header.

.DESCRIPTION
Opens the file with File.OpenRead, reads at most its first 4096 bytes, and
returns the optional header's Subsystem value: 2 for a Windows GUI program, 3
for a Windows console program, and other values for other images. No process
is started to inspect the file.

The reader checks the MZ signature, follows e_lfanew (the Int32 at 0x3C) to
the PE\0\0 signature, checks the optional-header magic (0x10B for PE32, 0x20B
for PE32+), and reads Subsystem as the UInt16 at e_lfanew + 24 + 68, an offset
that is the same in PE32 and PE32+. A file too short for that, a wrong
signature or magic, and any failure to open or read the file, such as an app
execution alias or a file another handle holds exclusively, return null. The
reader never throws.

.PARAMETER LiteralPath
The full path of the file to read.

.OUTPUTS
System.Int32
Returns the Subsystem value, or null when the header cannot be read.
#>
function Get-CompleterPESubsystem
{
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $buffer = [byte[]]::new(4096)
    $count = 0

    try
    {
        $stream = [System.IO.File]::OpenRead($LiteralPath)
        try
        {
            while ($count -lt $buffer.Length)
            {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -eq 0)
                {
                    break
                }

                $count += $read
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }
    catch
    {
        Write-Debug -Message "The program header of '$LiteralPath' could not be read. $($_.Exception.Message)"
        return $null
    }

    if ($count -lt 0x40 -or $buffer[0] -ne 0x4D -or $buffer[1] -ne 0x5A)
    {
        return $null
    }

    $peOffset = [System.BitConverter]::ToInt32($buffer, 0x3C)
    if ($peOffset -lt 0 -or ([long] $peOffset + 94) -gt $count)
    {
        return $null
    }

    if ($buffer[$peOffset] -ne 0x50 -or $buffer[$peOffset + 1] -ne 0x45 -or $buffer[$peOffset + 2] -ne 0 -or $buffer[$peOffset + 3] -ne 0)
    {
        return $null
    }

    $magic = [System.BitConverter]::ToUInt16($buffer, $peOffset + 24)
    if ($magic -ne 0x10B -and $magic -ne 0x20B)
    {
        return $null
    }

    [int] [System.BitConverter]::ToUInt16($buffer, $peOffset + 24 + 68)
}
