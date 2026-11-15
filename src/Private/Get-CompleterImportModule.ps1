<#
.SYNOPSIS
Returns the capture module Import-CompleterScript ran a script in, when a script block is bound to it.

.DESCRIPTION
Import-CompleterScript runs each script in a capture module of its own and
records that module, with the script's path and tier, in the module's
CompleterImportModules table. This helper returns the capture module a script
block is bound to when the table holds that module for the given script path
and tier, and nothing otherwise.

That is how the module tells an imported script block from any other. A
record's ImportModule, ScriptPath, SourcePath, and Trusted properties are
claims that any caller can set, so none of them establishes provenance: a
closure of an imported block is bound to a module of its own, and a module
that a caller creates, whatever its name, is never in the table. Script paths
compare the way the file system does: ignoring case on Windows and macOS, and
ordinally elsewhere.

.PARAMETER ScriptBlock
The script block whose binding to check. A null script block, or one bound to
no module, has no capture module.

.PARAMETER ScriptPath
The script the block must have been imported from.

.PARAMETER Trusted
The tier the script must have been imported under.

.OUTPUTS
System.Management.Automation.PSModuleInfo
Returns the capture module, or nothing when the script block was not imported
from that script under that tier.

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

    if ($null -eq $ScriptBlock -or $null -eq $ScriptBlock.Module -or [string]::IsNullOrEmpty($ScriptPath))
    {
        return
    }

    $importedScript = $null

    if (-not $script:CompleterImportModules.TryGetValue($ScriptBlock.Module, [ref] $importedScript))
    {
        return
    }

    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ([string]::Equals($importedScript.ScriptPath, $ScriptPath, $pathComparison) -and $importedScript.Trusted -eq $Trusted)
    {
        return $ScriptBlock.Module
    }
}
