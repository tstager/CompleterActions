<#
.SYNOPSIS
Replaces a completer set file with new bytes in one step.

.DESCRIPTION
Writes the bytes to '<path>.<8 hex>.tmp' beside the set and moves that file
over the set with File.Move, replacing it, so a reader sees either the old set
or the new one and never part of either. The temporary file never survives
the call.

A set reached through a symbolic link is written at the link's final target,
with the temporary file beside that target, so the link is kept and the move
stays on the target's volume.

.PARAMETER Bytes
The complete new content of the set file, byte-order mark included.

.PARAMETER LiteralPath
The full path of the set file to replace.

.OUTPUTS
System.IO.FileInfo
Returns the set file at LiteralPath, the link itself when it is one.
#>
function Save-CompleterSetFile
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]] $Bytes,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $temporaryPath = $null

    try
    {
        $linkTarget = [System.IO.File]::ResolveLinkTarget($LiteralPath, $true)
        $destinationPath = if ($null -eq $linkTarget) { $LiteralPath } else { $linkTarget.FullName }
        $temporaryPath = '{0}.{1}.tmp' -f $destinationPath, [guid]::NewGuid().ToString('N').Substring(0, 8)
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }
    finally
    {
        if ([System.IO.File]::Exists($temporaryPath))
        {
            [System.IO.File]::Delete($temporaryPath)
        }
    }

    [System.IO.FileInfo]::new($LiteralPath)
}
