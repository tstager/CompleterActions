<#
.SYNOPSIS
Finds the module manifest that declares a completer set, if any.

.DESCRIPTION
Decides whether a completer set is a package set, one whose module manifest
is known, so Test-CompleterSet can check the package layout.

With Module, as Test-CompleterSet -Name gives it, the manifest is the one
Resolve-CompleterSetModule chose. Without it, the candidates are the .psd1
files in the folder above the set file's folder, taken in ordinal order of
file name. The first that reads as data and whose PrivateData.CompleterSet
resolves to the set file is the manifest, so a staged package is recognised
before it is published, whatever its folder is called. A .psd1 that is not
data does not declare the set, and a folder that cannot be listed holds no
manifest. Paths are compared case-insensitively on Windows and macOS and
case-sensitively on Linux.

A declaration that is not a valid file path, because it holds a null
character or, on Windows, is longer than the platform allows, is recorded as a
declaration problem, and the search goes on. Every candidate is read, also
after the manifest is found, so each such manifest in the folder is recorded,
in ordinal order of file name. The reason is 'it is longer than the platform
allows' or the underlying message, as Resolve-CompleterSetEntry words an
entry's Path.

Nothing is imported or run: Import-CompleterDataFile reads each candidate as
data only, under the set file limit, so a .psd1 larger than 128 KB is not
parsed and does not declare the set.

.PARAMETER SetPath
The full path of the completer set file.

.PARAMETER Module
The record Resolve-CompleterSetModule returned for the set.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Name, ManifestPath, ModuleBase (the folder that holds the manifest),
Manifest (the manifest's data), and DeclarationProblems, one record with
ManifestPath and Reason per manifest whose declaration is not a valid file
path, empty with Module. When no manifest declares the set but a declaration
problem was recorded, Name, ManifestPath, ModuleBase, and Manifest are null.
Returns nothing when no manifest declares the set and none was recorded.
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
            Name                = $Module.Name
            ManifestPath        = $Module.ManifestPath
            ModuleBase          = $Module.ModuleBase
            Manifest            = $Module.Manifest
            DeclarationProblems = @()
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
    $package = $null
    $declarationProblems = [System.Collections.Generic.List[psobject]]::new()

    foreach ($fileName in $fileNames)
    {
        $manifestPath = [System.IO.Path]::Combine($moduleBase, $fileName)

        try
        {
            $manifestFile = Import-CompleterDataFile -LiteralPath $manifestPath
        }
        catch
        {
            continue
        }

        if ($manifestFile.OverLimit)
        {
            continue
        }

        $manifest = $manifestFile.Data
        $privateData = $manifest['PrivateData']
        $declaredSet = if ($privateData -is [System.Collections.IDictionary]) { $privateData['CompleterSet'] } else { $null }

        if ($declaredSet -isnot [string] -or [string]::IsNullOrWhiteSpace($declaredSet))
        {
            continue
        }

        # A bad declaration in one manifest must not hide the set's own manifest
        # or another bad one, so it is recorded and the search goes on.
        try
        {
            $declaredSetPath = [System.IO.Path]::GetFullPath($declaredSet.Replace('\', '/'), $moduleBase)
        }
        catch [System.IO.PathTooLongException]
        {
            # Its message repeats the whole path, so the reason is worded as the
            # entry rule words it.
            $declarationProblems.Add([pscustomobject] [ordered] @{ ManifestPath = $manifestPath; Reason = 'it is longer than the platform allows' })
            continue
        }
        catch [System.ArgumentException]
        {
            $declarationProblems.Add([pscustomobject] [ordered] @{ ManifestPath = $manifestPath; Reason = $_.Exception.GetBaseException().Message })
            continue
        }

        # A rooted declaration that is a valid path does not declare a set in the
        # package, so it is checked after the bad ones are recorded.
        if ([System.IO.Path]::IsPathRooted($declaredSet))
        {
            continue
        }

        if ($null -eq $package -and [string]::Equals($declaredSetPath, $SetPath, $pathComparison))
        {
            $package = [pscustomobject] [ordered] @{
                Name                = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                ManifestPath        = $manifestPath
                ModuleBase          = $moduleBase
                Manifest            = $manifest
                DeclarationProblems = $null
            }
        }
    }

    if ($null -eq $package)
    {
        if ($declarationProblems.Count -eq 0)
        {
            return
        }

        # No manifest declares the set, so only the bad declarations are reported.
        $package = [pscustomobject] [ordered] @{
            Name                = $null
            ManifestPath        = $null
            ModuleBase          = $null
            Manifest            = $null
            DeclarationProblems = $null
        }
    }

    $package.DeclarationProblems = $declarationProblems.ToArray()
    $package
}
