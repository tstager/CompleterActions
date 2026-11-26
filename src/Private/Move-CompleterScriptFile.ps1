<#
.SYNOPSIS
Moves a checked temporary file into place.

.DESCRIPTION
Calls File.Move, which renames the file within its folder, so the file at the
destination is either the old one or the new one. Without -Force a file that
already exists at the destination makes the move fail with an IOException and
stay unchanged.

.PARAMETER LiteralPath
The full path of the temporary file.

.PARAMETER Destination
The full path the file is moved to.

.PARAMETER Force
Replaces a file that exists at the destination.
#>
function Move-CompleterScriptFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Destination,

        [Parameter()]
        [switch] $Force
    )

    [System.IO.File]::Move($LiteralPath, $Destination, [bool] $Force)
}
