<#
.SYNOPSIS
Returns the capture module Import-CompleterScript ran a script in, when a script block is one the import emitted.

.DESCRIPTION
Import-CompleterScript runs each script in a capture module of its own and
records every script block it emits, with that capture module, the script's
path, and the tier, in the module's CompleterImportedScriptBlocks table, keyed
on the script block object itself. This helper returns the capture module of a
script block the table holds for the given script path and tier, and nothing
otherwise.

That is how the module tells an imported script block from any other. A
record's ImportModule, ScriptPath, SourcePath, and Trusted properties are
claims that any caller can set, so none of them establishes provenance, and
neither does a block's binding: the capture module is public on every
imported record, so a caller can bind a script block of its own to it, but
only the objects the import emitted are in the table. A closure of an imported
block is a new object too. Script paths compare the way the file system does:
ignoring case on Windows and macOS, and ordinally elsewhere.

.PARAMETER ScriptBlock
The script block to look up. A null script block has no capture module.

.PARAMETER ScriptPath
The script the block must have been imported from.

.PARAMETER Trusted
The tier the script must have been imported under.

.OUTPUTS
System.Management.Automation.PSModuleInfo
Returns the capture module, or nothing when the script block is not one the
import emitted for that script under that tier.

.EXAMPLE
PS> Get-CompleterImportModule -ScriptBlock $record.ScriptBlock -ScriptPath $record.ScriptPath -Trusted $record.Trusted

Returns the capture module of an Import-CompleterScript record, or nothing for
a script block that only claims to come from the script.
#>
function Get-CompleterImportModule
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSModuleInfo])]
    param(
        [Parameter()]
        [AllowNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ScriptPath,

        [Parameter()]
        [bool] $Trusted
    )

    if ($null -eq $ScriptBlock -or [string]::IsNullOrEmpty($ScriptPath))
    {
        return
    }

    $importedScript = $null

    if (-not $script:CompleterImportedScriptBlocks.TryGetValue($ScriptBlock, [ref] $importedScript))
    {
        return
    }

    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ([string]::Equals($importedScript.ScriptPath, $ScriptPath, $pathComparison) -and $importedScript.Trusted -eq $Trusted)
    {
        return $importedScript.Module
    }
}
