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

With -MinimumVersion or -RequiredVersion every manifest of each root walked is
read, and the unversioned layout is a candidate beside the version folders
when its ModuleVersion parses as a version. A version folder or unversioned
layout whose manifest cannot be read or parsed is left out of the candidates
instead of failing the call. -RequiredVersion takes the
candidate equal to the value from the first root that holds one.
-MinimumVersion takes, from the first root that holds a candidate equal to or
above the value, the highest such candidate; a root whose candidates are all
lower is passed over. Versions compare as System.Version values, so 1.2.0 and
1.2.0.0 differ, and a prerelease label takes no part. On a tie a version
folder wins over the unversioned layout. When no root holds a match but some
root holds a candidate, the error names the wanted version and lists every
candidate's version from every root, highest first, without repeats; when no
root holds a candidate, the error is the one without a version parameter.

Manifests are read by Import-CompleterDataFile, as data only, so nothing in
the package runs, and under the set file limit, so a manifest larger than
128 KB is refused before it is parsed. PrivateData.CompleterSet must name
a .psd1 file in a folder directly below ModuleBase, with / or \ as the
separator, and the file must exist. A declaration that is not a valid file
path, because it holds a null character or is longer than the platform allows,
fails with the invalid-declaration text, the value shown through
ConvertTo-CompleterPrintableText; the error for a set file that does not exist
shows its path the same way. A failure throws the bare reason; the caller adds
its own prefix.

.PARAMETER Name
The module name, taken literally.

.PARAMETER MinimumVersion
Selects the highest candidate equal to or above this version, from the first
root that holds one.

.PARAMETER RequiredVersion
Selects the candidate equal to this version, from the first root that holds
one.

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
    [CmdletBinding(DefaultParameterSetName = 'Highest')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = 'MinimumVersion')]
        [version] $MinimumVersion,

        [Parameter(Mandatory, ParameterSetName = 'RequiredVersion')]
        [version] $RequiredVersion
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

    $readManifest = {
        param([string] $ManifestPath)

        $fullPath = [System.IO.Path]::GetFullPath($ManifestPath)
        $manifestFile = Import-CompleterDataFile -LiteralPath $fullPath

        if ($manifestFile.OverLimit)
        {
            throw "The module manifest '$fullPath' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files and their module manifests."
        }

        $manifestFile.Data
    }

    # A version folder is a candidate when its manifest's ModuleVersion equals the folder's version.
    $readVersionFolder = {
        param([pscustomobject] $VersionFolder)

        $moduleName = [System.IO.Path]::GetFileName($VersionFolder.ModuleFolder)
        $manifestPath = & $findManifest $VersionFolder.Folder $moduleName

        if ($null -ne $manifestPath)
        {
            $manifest = & $readManifest $manifestPath
            $manifestVersion = $null

            if ([version]::TryParse([string] $manifest['ModuleVersion'], [ref] $manifestVersion) -and $manifestVersion -eq $VersionFolder.FolderVersion)
            {
                @{ Name = $moduleName; ModuleBase = $VersionFolder.Folder; ManifestPath = $manifestPath; Manifest = $manifest }
            }
        }
    }

    $selectVersion = $PSCmdlet.ParameterSetName -ne 'Highest'
    $candidateVersions = [System.Collections.Generic.SortedSet[version]]::new()
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

        $versionFolders = @($versionFolders | Sort-Object -Property @{ Expression = 'FolderVersion'; Descending = $true }, @{ Expression = 'Order'; Descending = $false })

        if ($selectVersion)
        {
            # Version folders come first, so on a tie a version folder wins over the unversioned layout.
            # A copy whose manifest cannot be read or parsed is left out instead of failing the call.
            $candidates = @(
                foreach ($versionFolder in $versionFolders)
                {
                    try
                    {
                        $candidate = & $readVersionFolder $versionFolder
                    }
                    catch
                    {
                        continue
                    }

                    if ($null -ne $candidate)
                    {
                        @{ Version = $versionFolder.FolderVersion; Module = $candidate }
                    }
                }

                foreach ($moduleFolder in $moduleFolders)
                {
                    $moduleName = [System.IO.Path]::GetFileName($moduleFolder)
                    $manifestPath = & $findManifest $moduleFolder $moduleName

                    if ($null -ne $manifestPath)
                    {
                        try
                        {
                            $manifest = & $readManifest $manifestPath
                        }
                        catch
                        {
                            continue
                        }

                        $manifestVersion = $null

                        if ([version]::TryParse([string] $manifest['ModuleVersion'], [ref] $manifestVersion))
                        {
                            @{ Version = $manifestVersion; Module = @{ Name = $moduleName; ModuleBase = $moduleFolder; ManifestPath = $manifestPath; Manifest = $manifest } }
                        }
                    }
                }
            )

            $selected = $null

            foreach ($candidate in $candidates)
            {
                $null = $candidateVersions.Add($candidate.Version)
                $isMatch = if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion') { $candidate.Version -eq $RequiredVersion } else { $candidate.Version -ge $MinimumVersion }

                if ($isMatch -and ($null -eq $selected -or $candidate.Version -gt $selected.Version))
                {
                    $selected = $candidate
                }
            }

            if ($null -ne $selected)
            {
                $chosen = $selected.Module
                break
            }

            continue
        }

        foreach ($versionFolder in $versionFolders)
        {
            $chosen = & $readVersionFolder $versionFolder

            if ($null -ne $chosen)
            {
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
                    $manifest = & $readManifest $manifestPath
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
        if ($candidateVersions.Count -gt 0)
        {
            $wanted = if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion') { "version $RequiredVersion" } else { "version $MinimumVersion or later" }
            $installed = @($candidateVersions.Reverse()) -join ', '
            throw "No installed module named '$Name' with $wanted was found in `$env:PSModulePath. Installed versions: $installed."
        }

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
        throw "The module '$moduleName' $version declares the completer set '$(ConvertTo-CompleterPrintableText -Value ([string] $declaredSet))', which must be a .psd1 file in a folder directly below '$moduleBase'."
    }

    try
    {
        $setPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($moduleBase, $segments[0], $segments[1]))
    }
    catch [System.IO.PathTooLongException], [System.ArgumentException]
    {
        # A null character, or a path longer than the platform allows, names no
        # file. The value can hold control characters, so it is made printable.
        throw "The module '$moduleName' $version declares the completer set '$(ConvertTo-CompleterPrintableText -Value $declaredSet)', which must be a .psd1 file in a folder directly below '$moduleBase'."
    }

    if (-not [System.IO.File]::Exists($setPath))
    {
        throw "The completer set '$(ConvertTo-CompleterPrintableText -Value $setPath)' declared by the module '$moduleName' $version does not exist."
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
