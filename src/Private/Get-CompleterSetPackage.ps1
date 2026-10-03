<#
.SYNOPSIS
Finds the module manifest that declares a completer set, if any.

.DESCRIPTION
Decides whether a completer set is a package set, one whose module manifest
is known, so Test-CompleterSet can check the package layout.

With Module, as Test-CompleterSet -Name gives it, the manifest is the one
Resolve-CompleterSetModule chose. Without it, the candidates are the .psd1
files in the folder above the set file's folder, taken in ordinal order of
file name. The first that Import-PowerShellDataFile reads as data and whose
PrivateData.CompleterSet resolves to the set file is the manifest, so a
staged package is recognised before it is published, whatever its folder is
called. A .psd1 that is not data does not declare the set, and a folder that
cannot be listed holds no manifest. Paths are compared case-insensitively on
Windows and macOS and case-sensitively on Linux.

Nothing is imported or run: manifests are read as data only.

.PARAMETER SetPath
The full path of the completer set file.

.PARAMETER Module
The record Resolve-CompleterSetModule returned for the set.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Name, ManifestPath, ModuleBase (the folder that holds the manifest),
and Manifest (the manifest's data), or nothing when no manifest declares the
set.
#>
function Get-CompleterSetPackage
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SetPath,

        [Parameter()]
        [psobject] $Module
    )

    if ($null -ne $Module)
    {
        return [pscustomobject] [ordered] @{
            Name         = $Module.Name
            ManifestPath = $Module.ManifestPath
            ModuleBase   = $Module.ModuleBase
            Manifest     = $Module.Manifest
        }
    }

    $setDirectory = [System.IO.Path]::GetDirectoryName($SetPath)
    $moduleBase = if ([string]::IsNullOrEmpty($setDirectory)) { $null } else { [System.IO.Path]::GetDirectoryName($setDirectory) }

    if ([string]::IsNullOrEmpty($moduleBase))
    {
        return
    }

    try
    {
        $fileNames = [string[]] @(
            foreach ($file in [System.IO.Directory]::EnumerateFiles($moduleBase))
            {
                if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase))
                {
                    [System.IO.Path]::GetFileName($file)
                }
            }
        )
    }
    catch
    {
        return
    }

    [System.Array]::Sort($fileNames, [System.StringComparer]::Ordinal)
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    foreach ($fileName in $fileNames)
    {
        $manifestPath = [System.IO.Path]::Combine($moduleBase, $fileName)

        try
        {
            $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
        }
        catch
        {
            continue
        }

        $privateData = $manifest['PrivateData']
        $declaredSet = if ($privateData -is [System.Collections.IDictionary]) { $privateData['CompleterSet'] } else { $null }

        if ($declaredSet -isnot [string] -or [string]::IsNullOrWhiteSpace($declaredSet) -or [System.IO.Path]::IsPathRooted($declaredSet))
        {
            continue
        }

        $declaredSetPath = [System.IO.Path]::GetFullPath($declaredSet.Replace('\', '/'), $moduleBase)

        if ([string]::Equals($declaredSetPath, $SetPath, $pathComparison))
        {
            return [pscustomobject] [ordered] @{
                Name         = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                ManifestPath = $manifestPath
                ModuleBase   = $moduleBase
                Manifest     = $manifest
            }
        }
    }
}
