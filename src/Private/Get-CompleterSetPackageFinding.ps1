<#
.SYNOPSIS
Checks a package set against the package layout and returns its PackageLayout findings.

.DESCRIPTION
Reports the declaration problems Get-CompleterSetPackage recorded, then runs
the four package-layout checks for a completer set whose module manifest it
found, in this order:

- Error, per declaration problem in the order recorded: a manifest in the
  folder above the set declares a completer set path that is not a valid file
  path. The message names the manifest by its full path, made printable by
  ConvertTo-CompleterPrintableText, and gives the reason. The finding points
  at line 1, column 1 of the set. These rows are written even when no
  manifest declares the set, and then they are the only rows.
- Error, per entry in set order: the entry's Path is fully qualified, or it
  resolves outside the module folder. The folder is compared with a trailing
  separator, case-insensitively on Windows and macOS and case-sensitively on
  Linux. A relative Path that cannot be resolved has no location to compare,
  and its InvalidEntry finding already reports it. The finding points at the
  entry's Path value.
- Error, per other .psd1 in the module folder in ordinal order of file name:
  Publish-PSResource can take that file as the manifest. The message names
  the module folder by its full path and the two files by name. The finding
  points at line 1, column 1 of the set.
- Error: the set file's base name equals the module name, compared
  case-insensitively on every platform, so PSResourceGet can take the set as
  the module manifest when it saves or installs the package. The message
  names the set file and the module. The finding points at line 1, column 1
  of the set.
- Warning: RequiredModules has no hashtable whose ModuleName is
  CompleterActions and whose ModuleVersion or RequiredVersion is 2.2.0 or
  later. The message and hint name the manifest by its full path. The
  finding points at line 1, column 1 of the set.

Path is the set file for every finding. Every position comes from the parse
in SetDefinition, so the set file is not read again. Nothing is imported or
run.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Package
The record Get-CompleterSetPackage returned for the set.

.PARAMETER Entry
The set's entries as Resolve-CompleterSetEntry returned them, in set order.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the PackageLayout findings in the order above, or nothing.
#>
function Get-CompleterSetPackageFinding
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Package,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entry
    )

    $setPath = $SetDefinition.Path
    # The parse of the whole set starts at line 1, column 1.
    $extentOne = $SetDefinition.Ast.Extent

    foreach ($declarationProblem in $Package.DeclarationProblems)
    {
        $printableManifestPath = ConvertTo-CompleterPrintableText -Value $declarationProblem.ManifestPath
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The module manifest '$printableManifestPath' declares a completer set path that is not a valid file path: $(([string] $declarationProblem.Reason).TrimEnd('.'))." -Hint "Make PrivateData.CompleterSet in '$printableManifestPath' the path of its set file relative to the manifest's folder, such as 'completers/completers.psd1'."
    }

    # Without a manifest that declares the set there is no package to check.
    if ($null -eq $Package.ManifestPath)
    {
        return
    }

    $moduleBase = $Package.ModuleBase
    $manifestPath = $Package.ManifestPath
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $moduleBasePrefix = $moduleBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $extents = Get-CompleterSetEntryExtent -Ast $SetDefinition.Ast

    foreach ($setEntry in $Entry)
    {
        if ([string]::IsNullOrWhiteSpace($setEntry.DeclaredPath))
        {
            continue
        }

        # Path is null when the entry's Path cannot be resolved, which its
        # InvalidEntry finding already reports.
        if ([System.IO.Path]::IsPathFullyQualified($setEntry.DeclaredPath) -or ($null -ne $setEntry.Path -and -not $setEntry.Path.StartsWith($moduleBasePrefix, $pathComparison)))
        {
            $entryExtent = $extents.Entries[$setEntry.Index - 1]
            $pathExtent = if ($null -ne $entryExtent.PathExtent) { $entryExtent.PathExtent } else { $entryExtent.Extent }
            New-CompleterScriptFinding -Path $setPath -Extent $pathExtent -Construct 'PackageLayout' -Message "Entry $($setEntry.Index) ('$($setEntry.DeclaredPath)'): the script is outside the module folder, so an installed copy of the package does not contain it." -Hint 'Move the script under the folder that holds the set file, then regenerate the set with Export-CompleterSet.'
        }
    }

    $otherManifestNames = [string[]] @(
        foreach ($file in [System.IO.Directory]::EnumerateFiles($moduleBase))
        {
            if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::Equals($file, $manifestPath, $pathComparison))
            {
                [System.IO.Path]::GetFileName($file)
            }
        }
    )
    [System.Array]::Sort($otherManifestNames, [System.StringComparer]::Ordinal)

    $manifestName = [System.IO.Path]::GetFileName($manifestPath)

    foreach ($otherManifestName in $otherManifestNames)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The module folder '$moduleBase' holds '$otherManifestName' beside the module manifest '$manifestName', so Publish-PSResource can take the wrong file as the manifest." -Hint 'Keep the module manifest as the only .psd1 in the module folder; move the set into a subfolder and update PrivateData.CompleterSet.'
    }

    $setName = [System.IO.Path]::GetFileName($setPath)

    if ([string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($setPath), $Package.Name, [System.StringComparison]::OrdinalIgnoreCase))
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The set file '$setName' has the base name of the module '$($Package.Name)', so PSResourceGet can take it as the module manifest when it saves or installs the package." -Hint 'Rename the set file so its base name differs from the module name, for example to completers.psd1, and update PrivateData.CompleterSet.'
    }

    $minimumVersion = [version] '2.2.0'
    $requiresCompleterActions = $false

    foreach ($requiredModule in @($Package.Manifest['RequiredModules']))
    {
        if ($requiredModule -isnot [System.Collections.IDictionary] -or
            -not [string]::Equals([string] $requiredModule['ModuleName'], 'CompleterActions', [System.StringComparison]::OrdinalIgnoreCase))
        {
            continue
        }

        foreach ($versionKey in 'ModuleVersion', 'RequiredVersion')
        {
            $requiredVersion = $null

            if ([version]::TryParse([string] $requiredModule[$versionKey], [ref] $requiredVersion) -and $requiredVersion -ge $minimumVersion)
            {
                $requiresCompleterActions = $true
            }
        }
    }

    if (-not $requiresCompleterActions)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Severity Warning -Message "The module manifest '$manifestPath' does not require CompleterActions 2.2.0 or later, so installing the package does not install Import-CompleterSet -Name." -Hint "Add @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' } to RequiredModules in '$manifestPath'."
    }
}
