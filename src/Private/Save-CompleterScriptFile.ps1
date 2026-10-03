<#
.SYNOPSIS
Writes a generated completer script after checking the bytes it installs.

.DESCRIPTION
Writes the lines to '<path>.<8 hex>.tmp' in the target folder with
Set-Content -Encoding utf8 (UTF-8 without a byte-order mark, the platform
newline, and a final newline). It then checks that file the way
Test-CompleterScript does, parse errors included, and derives its targets the
way Register-Completer -Lazy does. Any finding, or derived targets that differ
from -ExpectedTarget in order or spelling, throws the self-check text. A
checked file is moved into place with File.Move, overwriting only under
-Force; without -Force, a file that appeared at the path before the move makes
the call fail with the already-exists text and stay unchanged. The temporary
file never survives the call.

.PARAMETER Line
The script's lines, without line endings.

.PARAMETER LiteralPath
The full path of the .ps1 file to write. Its folder must exist.

.PARAMETER ExpectedTarget
The target list the script must register, in order.

.PARAMETER Force
Overwrites an existing file at the path.

.OUTPUTS
System.IO.FileInfo
#>
function Save-CompleterScriptFile
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ExpectedTarget,

        [Parameter()]
        [switch] $Force
    )

    $temporaryPath = '{0}.{1}.tmp' -f $LiteralPath, [guid]::NewGuid().ToString('N').Substring(0, 8)

    try
    {
        Set-Content -LiteralPath $temporaryPath -Value $Line -Encoding utf8 -ErrorAction Stop

        $detail = $null
        $finding = @(Get-CompleterScriptFinding -LiteralPath $temporaryPath) | Select-Object -First 1

        if ($null -ne $finding)
        {
            $detail = $finding.Message
        }
        else
        {
            try
            {
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $temporaryPath | ForEach-Object { [string] $_.RuntimeKey })
            }
            catch
            {
                $derivedTargets = $null
                $detail = $_.Exception.Message
            }

            if ($null -ne $derivedTargets -and -not [System.Linq.Enumerable]::SequenceEqual([string[]] $derivedTargets, [string[]] $ExpectedTarget))
            {
                $derivedList = @($derivedTargets | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', '
                $expectedList = @($ExpectedTarget | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', '
                $detail = 'The script registers {0}, not {1}.' -f $derivedList, $expectedList
            }
        }

        if ($null -ne $detail)
        {
            throw "New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. $detail"
        }

        try
        {
            [System.IO.File]::Move($temporaryPath, $LiteralPath, [bool] $Force)
        }
        catch [System.IO.IOException]
        {
            if (-not $Force -and (Test-Path -LiteralPath $LiteralPath))
            {
                throw "The file '$LiteralPath' already exists. Use -Force to overwrite it."
            }

            throw
        }

        Get-Item -LiteralPath $LiteralPath
    }
    finally
    {
        if (Test-Path -LiteralPath $temporaryPath)
        {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}
