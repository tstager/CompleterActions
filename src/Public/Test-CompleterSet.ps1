<#
.SYNOPSIS
Reports drift between a completer set file and the scripts on disk.

.DESCRIPTION
Reads a completer set the way Import-CompleterSet does, checks every entry
in full against the scripts on disk, and returns one
CompleterActions.CompleterScriptFinding record per problem. A set that
matches its folder produces no output, so a gate can assert that the command
returns nothing, the same shape Test-CompleterScript uses.

The set is read with Import-PowerShellDataFile, which evaluates data only,
and the set file is also parsed, never evaluated, to point each finding at a
line and column of the set. Every strict entry is parsed once, whether or not
its Hash matches, because the command verifies rather than takes the fast
path. A trusted entry is never parsed, as at import, so it can report only
MissingScript, InvalidEntry, DuplicateTarget, and the three Hash kinds. No
script is executed, and the session's registrations are neither read nor
changed, so a conflict with what the session has registered is not drift.

Construct names the kind of drift, and Severity is Error when
Import-CompleterSet without -SkipInvalid would reject the set because of it,
or Warning when the set still imports but is stale or slower:

- MissingScript (Error): Path does not resolve to an existing file.
- InvalidEntry (Error): any other problem Import-CompleterSet reports for the
  entry itself, with its text word for word.
- UnreadableTargets (Error): a strict script does not parse or does not name
  its targets with literal arguments.
- TargetMismatch (Error): a strict entry's Targets differ from the targets its
  script registers.
- DuplicateTarget (Error): an earlier entry already lists the target, under
  import's rule that only an entry with no Error claims its targets.
- HashMismatch (Warning): the script changed since the Hash was written.
- MissingHash (Warning): the entry has no Hash.
- InvalidHash (Warning): the Hash is not 'SHA256:' and 64 hexadecimal digits.
- PackageLayout (Error or Warning): the set belongs to a completer set
  package that breaks the package layout. Error when the package would fail
  to publish, install, or import, and Warning when it installs but a clean
  machine is missing a piece, as listed below.
- UnlistedScript (Warning): a file under the set's directory matches -Filter
  and no entry lists it.

Findings come in set order, each entry's in the order above, then the
PackageLayout findings, and the UnlistedScript findings follow, sorted by
path. Path is the set file for every finding, because the fix is always made
in the set, usually by regenerating it with Export-CompleterSet; a finding
about the manifest or the module folder names the file in Message and points
at line 1, column 1 of the set.

A set is a package set when its module manifest is known: through -Name, or,
for -Path and -LiteralPath, when the folder above the set file's folder holds
a .psd1 that reads as data and whose PrivateData.CompleterSet resolves to the
set file, as in a staged package before it is published. When more than one
.psd1 there declares the set, the first in ordinal order of file name is the
manifest. A .psd1 that is not data declares nothing, and a folder that cannot
be listed holds no manifest. A set that no manifest declares gets no
PackageLayout finding. A package set is checked for three things, reported
in this order:

- Error, one per entry in set order, at the entry's Path: the Path is fully
  qualified, or resolves outside the module folder, so an installed copy of
  the package does not contain the script. A fully qualified path is an
  error even inside the module folder, because it names the source tree, not
  the installed copy.
- Error, one per file in ordinal order of file name: the module folder holds
  a .psd1 other than the manifest, so Publish-PSResource can take the wrong
  file as the manifest.
- Warning: RequiredModules does not list CompleterActions as a hashtable
  with a ModuleVersion or RequiredVersion of 2.2.0 or later, so installing
  the package does not install Import-CompleterSet -Name.

A RootModule in the manifest is not a finding.

With -Name the set comes from an installed completer set package, found
exactly as Import-CompleterSet -Name finds it: the first $env:PSModulePath
root that has the module wins, and within it the highest version. The
manifest is read as data, so nothing in the package runs. Each name is taken
literally, and a name that does not resolve fails the call.

Every -Path, -LiteralPath, or -Name value is resolved before any set is
tested. The sets are then tested in the order given, and each set's findings
are written before the next set is read. A set that cannot be read, such as
one without Version = 1, stops the call with a terminating error after the
findings of the earlier sets. A folder under a set's directory that cannot be
read also stops the call with a terminating error, after that set's entry
findings, because the scan for unlisted scripts would be incomplete.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER Name
The names of installed completer set modules. Each name is taken literally: a
name containing *, ?, [, or ] fails the call before any name is resolved. The
parameter takes no pipeline input.

.PARAMETER Filter
The file-name pattern of the scan for scripts that no entry lists. The scan
is recursive under the set file's directory. The default is *_completer.ps1.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns CompleterActions.CompleterScriptFinding records with Path, Line,
Column, Severity, Construct, Message, and Hint properties, or nothing when
the set matches its folder.

.EXAMPLE
PS> Test-CompleterSet -Path ~\Completers\completers.psd1

Reports every entry that no longer matches its script and every completer
script the set does not list, or nothing when the set is current.

.EXAMPLE
PS> Test-CompleterSet -LiteralPath .\completers.psd1 | Where-Object Severity -eq Error

Lists only the drift that would make Import-CompleterSet reject the set.

.EXAMPLE
PS> Test-CompleterSet -Name PS_Completers

Checks the installed PS_Completers package's set against its scripts and the
package layout, by the same name the profile's Import-CompleterSet line uses.
#>
function Test-CompleterSet
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Filter = '*_completer.ps1'
    )

    process
    {
        try
        {
            $sets = @(
                if ($PSCmdlet.ParameterSetName -eq 'Name')
                {
                    foreach ($nameItem in $Name)
                    {
                        if ($nameItem -match '[*?\[\]]')
                        {
                            throw "Test-CompleterSet -Name does not accept wildcards. Received '$nameItem'."
                        }
                    }

                    foreach ($nameItem in $Name)
                    {
                        $setModule = Resolve-CompleterSetModule -Name $nameItem
                        @{ SetPath = $setModule.SetPath; Module = $setModule }
                    }
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        @{ SetPath = (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName; Module = $null }
                    }
                }
                else
                {
                    foreach ($pathItem in $Path)
                    {
                        foreach ($resolvedPath in @(Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath))
                        {
                            @{ SetPath = $resolvedPath; Module = $null }
                        }
                    }
                }
            )

            foreach ($set in $sets)
            {
                $setDefinition = Import-CompleterSetDefinition -LiteralPath $set.SetPath
                $findingParameters = @{ SetDefinition = $setDefinition; Filter = $Filter }
                $package = Get-CompleterSetPackage -SetPath $setDefinition.Path -Module $set.Module

                if ($null -ne $package)
                {
                    $findingParameters['Package'] = $package
                }

                Get-CompleterSetFinding @findingParameters
            }
        }
        catch
        {
            throw "Failed to test completer set. $($_.Exception.Message)"
        }
    }
}
