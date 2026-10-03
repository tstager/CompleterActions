<#
.SYNOPSIS
Finds an installed completer set module by name and returns its set file.

.DESCRIPTION
Follows the module lookup without calling Get-Module. The roots of
$env:PSModulePath are walked in order, split on the platform's path separator,
skipping empty and missing entries. In each root the module folders are the
subdirectories whose name equals Name case-insensitively, on every platform,
and within a module folder the manifest is the .psd1 whose base name equals
the folder's name case-insensitively.

The candidates in a root are every version subfolder that parses as a version
and equals its manifest's ModuleVersion, and the unversioned layout, the
manifest directly in the module folder. The first root with a candidate wins;
within it the highest version wins, and the unversioned layout is used only
when the root has no versioned candidate. The chosen module is never replaced
by a lower version, even when its set declaration is broken.

Manifests are read with Import-PowerShellDataFile, as data only, so nothing in
the package runs. PrivateData.CompleterSet must name a .psd1 file in a folder
directly below ModuleBase, with / or \ as the separator, and the file must
exist. A failure throws the bare reason; the caller adds its own prefix.

.PARAMETER Name
The module name, taken literally.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Name (the installed module folder's spelling), Version (ModuleVersion,
followed by -<Prerelease> when PrivateData.PSData.Prerelease is set),
ModuleBase (the full path of the version folder, or of the module folder for
the unversioned layout), ManifestPath, Manifest (the manifest's data), and
SetPath (the full path of the set file).
#>
function Resolve-CompleterSetModule
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $sortOrdinal = {
        param([string[]] $Value)

        $sorted = [string[]] @($Value)
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $sorted
    }

    $findManifest = {
        param([string] $Folder, [string] $ModuleName)

        $manifestPaths = @(
            foreach ($file in [System.IO.Directory]::EnumerateFiles($Folder, '*.psd1'))
            {
                if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase) -and
                    [string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($file), $ModuleName, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $file
                }
            }
        )

        if ($manifestPaths.Count -gt 0)
        {
            @(& $sortOrdinal $manifestPaths)[0]
        }
    }

    $chosen = $null

    foreach ($root in ([string] $env:PSModulePath).Split([System.IO.Path]::PathSeparator))
    {
        if ([string]::IsNullOrWhiteSpace($root) -or -not [System.IO.Directory]::Exists($root))
        {
            continue
        }

        $moduleFolders = @(
            foreach ($directory in [System.IO.Directory]::EnumerateDirectories($root))
            {
                if ([string]::Equals([System.IO.Path]::GetFileName($directory), $Name, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $directory
                }
            }
        )

        if ($moduleFolders.Count -eq 0)
        {
            continue
        }

        $moduleFolders = @(& $sortOrdinal $moduleFolders)
        $order = 0
        $versionFolders = @(
            foreach ($moduleFolder in $moduleFolders)
            {
                foreach ($versionFolder in @(& $sortOrdinal @([System.IO.Directory]::EnumerateDirectories($moduleFolder))))
                {
                    $folderVersion = $null

                    if ([version]::TryParse([System.IO.Path]::GetFileName($versionFolder), [ref] $folderVersion))
                    {
                        $order++
                        [pscustomobject] @{ ModuleFolder = $moduleFolder; Folder = $versionFolder; FolderVersion = $folderVersion; Order = $order }
                    }
                }
            }
        )

        foreach ($versionFolder in @($versionFolders | Sort-Object -Property @{ Expression = 'FolderVersion'; Descending = $true }, @{ Expression = 'Order'; Descending = $false }))
        {
            $moduleName = [System.IO.Path]::GetFileName($versionFolder.ModuleFolder)
            $manifestPath = & $findManifest $versionFolder.Folder $moduleName

            if ($null -eq $manifestPath)
            {
                continue
            }

            $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
            $manifestVersion = $null

            if ([version]::TryParse([string] $manifest['ModuleVersion'], [ref] $manifestVersion) -and $manifestVersion -eq $versionFolder.FolderVersion)
            {
                $chosen = @{ Name = $moduleName; ModuleBase = $versionFolder.Folder; ManifestPath = $manifestPath; Manifest = $manifest }
                break
            }
        }

        if ($null -eq $chosen)
        {
            foreach ($moduleFolder in $moduleFolders)
            {
                $moduleName = [System.IO.Path]::GetFileName($moduleFolder)
                $manifestPath = & $findManifest $moduleFolder $moduleName

                if ($null -ne $manifestPath)
                {
                    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
                    $chosen = @{ Name = $moduleName; ModuleBase = $moduleFolder; ManifestPath = $manifestPath; Manifest = $manifest }
                    break
                }
            }
        }

        if ($null -ne $chosen)
        {
            break
        }
    }

    if ($null -eq $chosen)
    {
        throw "No installed module named '$Name' was found in `$env:PSModulePath. Install it with Install-PSResource $Name."
    }

    $moduleName = $chosen.Name
    $moduleBase = [System.IO.Path]::GetFullPath($chosen.ModuleBase)
    $manifest = $chosen.Manifest
    $privateData = $manifest['PrivateData']
    $version = [string] $manifest['ModuleVersion']

    if ($privateData -is [System.Collections.IDictionary] -and $privateData['PSData'] -is [System.Collections.IDictionary])
    {
        $prerelease = [string] $privateData['PSData']['Prerelease']

        if (-not [string]::IsNullOrEmpty($prerelease))
        {
            $version = '{0}-{1}' -f $version, $prerelease
        }
    }

    $declaredSet = if ($privateData -is [System.Collections.IDictionary]) { $privateData['CompleterSet'] } else { $null }

    if ($null -eq $declaredSet)
    {
        throw "The module '$moduleName' $version at '$moduleBase' does not declare a completer set. A completer set module names its set file in PrivateData.CompleterSet."
    }

    $segments = @(
        if ($declaredSet -is [string] -and -not [System.IO.Path]::IsPathRooted($declaredSet))
        {
            $declaredSet.Replace('\', '/').Split('/')
        }
    )
    $isValidDeclaration = $segments.Count -eq 2 -and
        @($segments.Where({ [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' -or [System.IO.Path]::IsPathRooted($_) })).Count -eq 0 -and
        [System.IO.Path]::GetExtension($segments[1]) -eq '.psd1'

    if (-not $isValidDeclaration)
    {
        throw "The module '$moduleName' $version declares the completer set '$declaredSet', which must be a .psd1 file in a folder directly below '$moduleBase'."
    }

    $setPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($moduleBase, $segments[0], $segments[1]))

    if (-not [System.IO.File]::Exists($setPath))
    {
        throw "The completer set '$setPath' declared by the module '$moduleName' $version does not exist."
    }

    [pscustomobject] [ordered] @{
        Name         = $moduleName
        Version      = $version
        ModuleBase   = $moduleBase
        ManifestPath = [System.IO.Path]::GetFullPath($chosen.ManifestPath)
        Manifest     = $manifest
        SetPath      = $setPath
    }
}
