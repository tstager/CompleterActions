class CompleterRegistration
{
    CompleterRegistration()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompleterRegistration')
    }

    [string] $Key
    [string] $RegistrationKey
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [bool] $IsNative
    [CompleterType] $CompleterType
    [string] $TargetType
    [string] $Source
    [string] $State
    [bool] $IsManaged
    [bool] $IsRuntimeRegistered
    [string] $ScriptPath
    [bool] $Trusted
    [string] $LoadError
    [System.Management.Automation.PSModuleInfo] $ImportModule = $null
    [scriptblock] $ScriptBlock = $null
    [string] $ScriptText
}
class CompleterScriptFinding
{
    CompleterScriptFinding()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompleterScriptFinding')
    }

    [string] $Path
    [int] $Line
    [int] $Column
    [string] $Severity
    [string] $Construct
    [string] $Message
    [string] $Hint
}
enum CompleterState
{
    Active
    Stale
    Conflicted
    Pending
    Failed
    Discovered
}
enum CompleterType
{
    Native
    Parameter
}
class CompletionMatch
{
    CompletionMatch()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompletionMatch')
    }

    [string] $Key
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [CompleterType] $CompleterType
    [string] $InputText
    [int] $CursorPosition
    [string] $CompletionText
    [string] $ListItemText
    [System.Management.Automation.CompletionResultType] $ResultType
    [string] $ToolTip
}
class ImportedCompleterRegistration
{
    ImportedCompleterRegistration()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.ImportedCompleterRegistration')
    }

    [string] $Key
    [string] $RegistrationKey
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [bool] $IsNative
    [bool] $Native
    [CompleterType] $CompleterType
    [string] $TargetType
    [string] $Source
    [bool] $Trusted
    [string] $Path
    [string] $SourcePath
    [System.Management.Automation.PSModuleInfo] $ImportModule = $null
    [scriptblock] $ScriptBlock = $null
    [string] $ScriptText
}
<#
.SYNOPSIS
Writes a completer set file from registrations that came from scripts.

.DESCRIPTION
Groups registration records by the completer script they came from and writes
a completer set: a .psd1 data file that lists each script once with its trust
tier and the targets it registers. Import-CompleterSet reads the file back and
registers everything in it, so a profile that imports a completer repository
becomes one Import-CompleterSet call.

Records arrive through -InputObject, typically from Get-Completer
or Import-CompleterScript. Without -InputObject the command exports every
managed registration that records a ScriptPath. Script paths are written
relative to the set file when both share a root, so a repository can carry its
set file alongside its scripts; paths on another drive stay absolute. The
Trusted flag of each entry is taken from the records, and records for the same
script must agree on it.

A strict entry must list every target its script registers, because
Import-CompleterSet compares a strict entry's Targets with the targets derived
from the parsed script and rejects a mismatch. The command derives those
targets the same way before writing and refuses, naming the missing targets
and leaving the output untouched, when the records for a strict script cover
only some of them, as they do after Register-Completer -Lazy
-CommandName selected a subset. Trusted entries are written with the targets
the records carry, so a subset of a trusted script's targets exports and
imports as given.

.PARAMETER Path
The path of the .psd1 file to write. The parent directory must exist.

.PARAMETER InputObject
Registration records to export. Each record must describe a target and expose
the script it came from through a ScriptPath or SourcePath property. Records
without a script path cannot be expressed in a set and are rejected.

.PARAMETER PassThru
Returns the written file.

.OUTPUTS
System.IO.FileInfo
When -PassThru is used, returns the written set file.

.EXAMPLE
PS> Export-CompleterSet -Path ~\Completers\completers.psd1

Writes every managed registration that came from a script into a set file next
to the scripts.

.EXAMPLE
PS> Get-ChildItem ~\Completers -Recurse -Filter *_completer.ps1 | Import-CompleterScript | Export-CompleterSet -Path ~\Completers\completers.psd1

Builds a set from a completer repository without registering anything in the
current session.
#>
function Export-CompleterSet
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $outputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

        if ([System.IO.Path]::GetExtension($outputPath) -ne '.psd1')
        {
            throw "Completer sets must be .psd1 files. Received '$outputPath'."
        }

        $outputDirectory = Split-Path -Path $outputPath -Parent

        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
        {
            throw "The directory '$outputDirectory' does not exist."
        }

        $records = [System.Collections.Generic.List[psobject]]::new()
        $inputBound = $false
    }

    process
    {
        if ($PSBoundParameters.ContainsKey('InputObject'))
        {
            $inputBound = $true
            $records.AddRange([psobject[]] @($InputObject))
        }
    }

    end
    {
        try
        {
            if (-not $inputBound)
            {
                $records.AddRange([psobject[]] @(Get-Completer -ManagedOnly | Where-Object { $_.PSObject.Properties['ScriptPath'] -and -not [string]::IsNullOrWhiteSpace([string] $_.ScriptPath) }))
            }

            $entriesByPath = [ordered] @{}

            foreach ($record in $records)
            {
                $scriptPath = $null

                foreach ($propertyName in 'ScriptPath', 'SourcePath')
                {
                    $property = $record.PSObject.Properties[$propertyName]

                    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                    {
                        $scriptPath = [System.IO.Path]::GetFullPath([string] $property.Value)
                        break
                    }
                }

                if ($null -eq $scriptPath)
                {
                    throw 'InputObject must expose the script it came from through a ScriptPath or SourcePath property; registrations created from an in-memory script block cannot be exported to a set.'
                }

                $target = ($record | Resolve-CompleterInputObject).Target
                $trustedProperty = $record.PSObject.Properties['Trusted']
                $trusted = $null -ne $trustedProperty -and [bool] $trustedProperty.Value

                if (-not $entriesByPath.Contains($scriptPath))
                {
                    $entriesByPath[$scriptPath] = [pscustomobject] [ordered] @{
                        Path    = $scriptPath
                        Trusted = $trusted
                        Targets = [ordered] @{}
                    }
                }

                $entry = $entriesByPath[$scriptPath]

                if ($entry.Trusted -ne $trusted)
                {
                    throw "The records for '$scriptPath' disagree on Trusted, so the entry's trust tier cannot be written."
                }

                $entry.Targets[[string] $target.Key] = $target
            }

            if ($entriesByPath.Count -eq 0)
            {
                throw 'No registrations with a script path were found to export.'
            }

            # Import-CompleterSet holds a strict entry's Targets to the script's full
            # derived target list, so a strict group that covers only some of those
            # targets would write a set that cannot be imported. Check it here,
            # before anything is written, with the same derivation the import uses.
            foreach ($entry in $entriesByPath.Values)
            {
                if ($entry.Trusted)
                {
                    continue
                }

                $derivedKeys = @(Get-CompleterScriptTarget -LiteralPath $entry.Path | ForEach-Object { [string] $_.Key })
                $missingTargets = @($derivedKeys | Where-Object { -not $entry.Targets.Contains($_) })
                $unknownTargets = @($entry.Targets.Keys | Where-Object { $_ -notin $derivedKeys })

                if ($missingTargets.Count -eq 0 -and $unknownTargets.Count -eq 0)
                {
                    continue
                }

                $problem = "The strict entry for '$($entry.Path)' cannot be imported as a set entry because its targets do not match the script."

                if ($missingTargets.Count -gt 0)
                {
                    $problem += " Missing: $(@($missingTargets | ForEach-Object { "'$_'" }) -join ', ')."
                }

                if ($unknownTargets.Count -gt 0)
                {
                    $problem += " Not registered by the script: $(@($unknownTargets | ForEach-Object { "'$($entry.Targets[$_].RuntimeKey)'" }) -join ', ')."
                }

                throw "$problem Export the registrations for every target the script registers, or register the script with -Trusted, whose entries take their targets as given. Nothing was written."
            }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('@{')
            $lines.Add('    Version = 1')
            $lines.Add('    Entries = @(')

            foreach ($entry in $entriesByPath.Values)
            {
                $relativePath = [System.IO.Path]::GetRelativePath($outputDirectory, $entry.Path)
                $writtenPath = if ([System.IO.Path]::IsPathRooted($relativePath)) { $entry.Path } else { $relativePath.Replace('\', '/') }

                $lines.Add('        @{')
                $lines.Add("            Path    = '$($writtenPath.Replace("'", "''"))'")
                $lines.Add("            Trusted = `$$($entry.Trusted.ToString().ToLowerInvariant())")
                $lines.Add('            Targets = @(')

                foreach ($target in $entry.Targets.Values)
                {
                    $commandName = ([string] $target.CommandName).Replace("'", "''")

                    if ($target.IsNative)
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; Native = `$true }")
                    }
                    else
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; ParameterName = '$(([string] $target.ParameterName).Replace("'", "''"))' }")
                    }
                }

                $lines.Add('            )')
                $lines.Add('        }')
            }

            $lines.Add('    )')
            $lines.Add('}')

            if (-not $PSCmdlet.ShouldProcess($outputPath, 'Export completer set'))
            {
                return
            }

            Set-Content -LiteralPath $outputPath -Value $lines -Encoding utf8

            if ($PassThru)
            {
                Get-Item -LiteralPath $outputPath
            }
        }
        catch
        {
            throw "Failed to export completer set. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Gets completer registrations known to the module or discovered at runtime.

.DESCRIPTION
Returns completer registration records for all registrations, native command
completers, command parameter completers, or the targets described by piped
registration records.
By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target and the managed record still matches the live runtime value.
When the runtime registration was replaced outside this module, the live
discovered value is returned with State 'Conflicted' instead; -ManagedOnly
returns the managed record with State 'Stale'. When the runtime registration
was removed outside this module, the managed record is returned with State
'Stale' and IsRuntimeRegistered false. Lazy registrations report State
'Pending' until their script loads on the first tab press and 'Failed' when
that load failed; a Failed record has no runtime entry and carries the error
in LoadError. Both are returned by default and by -ManagedOnly. The command
accepts arrays for command and parameter lookups, and records piped back from
Get-Completer or Import-CompleterScript resolve through their Key
and IsNative properties. Keys are output-only identifiers: a hand-typed key
string is not accepted, so name the target with -CommandName plus -Native or
-ParameterName instead.

Discovery covers the two target kinds this module manages: command-parameter
completers and native command completers. A completer registered with
Register-ArgumentCompleter -ParameterName alone, without -CommandName, applies
to every command with that parameter and is stored under the bare parameter
name; such registrations are not returned and are reported with -Verbose as
they are skipped, so they never prevent the supported registrations from being
listed.

.PARAMETER InputObject
Supplies one or more objects that describe the registrations to get, such as
records returned by Get-Completer or Import-CompleterScript. An
input object exposes CommandName with IsNative/Native or ParameterName, or a
Key, RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Limits results to one or more command names for native or command-parameter
completers.

.PARAMETER ParameterName
Limits results to one or more parameter completer targets.

.PARAMETER Native
Indicates that the lookup target is a native command completer instead of a
command parameter completer.

.PARAMETER ManagedOnly
Returns only registrations tracked by this module.

.PARAMETER DiscoveredOnly
Returns only registrations discovered from the current PowerShell runtime.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompleterRegistration records. The State property is
'Active' for records that describe the live runtime value, 'Pending' for lazy
registrations whose script has not loaded yet, 'Failed' for lazy registrations
whose script failed to load, 'Stale' for managed records that no longer match
the runtime, and 'Conflicted' for live runtime values that replaced a managed
registration outside this module. ScriptPath names the completer script behind
a lazy or imported registration and LoadError holds the failure message of a
Failed record.

.EXAMPLE
PS> Get-Completer -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-Completer -CommandName 'git' -ParameterName 'checkout', 'branch'

Gets multiple command-parameter completer registrations in a single call.

.EXAMPLE
PS> Import-CompleterScript -LiteralPath .\git_completer.ps1 | Get-Completer

Gets the live registrations for the targets a completer script defines by
piping its import records back in.
#>
function Get-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $ManagedOnly,

        [Parameter()]
        [switch] $DiscoveredOnly
    )

    begin
    {
        if ($ManagedOnly -and $DiscoveredOnly)
        {
            throw 'ManagedOnly and DiscoveredOnly cannot be used together.'
        }

        $registrationsByKey = [ordered] @{}
    }

    process
    {
        $targets = @()
        $managedRegistrations = @()
        $discoveredRegistrations = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $targets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            elseif ($PSCmdlet.ParameterSetName -ne 'All')
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                $targets = @(Resolve-CompleterTargetList @targetParameters)
            }

            if (-not $DiscoveredOnly)
            {
                if ($targets.Count -eq 0)
                {
                    $managedRegistrations = @(Find-ManagedCompleterRegistration)
                }
                else
                {
                    foreach ($target in $targets)
                    {
                        $managedRegistrations += @(Find-ManagedCompleterRegistration -Key $target.Key)
                    }
                }
            }

            if (-not $ManagedOnly)
            {
                if ($targets.Count -eq 0)
                {
                    $discoveredRegistrations = @(Find-RuntimeCompleterRegistration)
                }
                else
                {
                    foreach ($target in $targets)
                    {
                        $discoveredRegistrations += @(Find-RuntimeCompleterRegistration -Key $target.Key)
                    }
                }
            }

            foreach ($registration in $managedRegistrations)
            {
                if ($null -eq $registration)
                {
                    continue
                }

                $registrationState = Resolve-CompleterRegistrationState -Key $registration.Key

                if ($registrationState.ManagedState -in 'Active', 'Pending')
                {
                    $registrationsByKey[[string] $registration.Key] = $registration
                }
                elseif ($registrationState.ManagedState -eq 'Failed' -and ($ManagedOnly -or $null -eq $registrationState.RuntimeRegistration))
                {
                    $registrationsByKey[[string] $registration.Key] = $registration
                }
                elseif ($ManagedOnly -or $null -eq $registrationState.RuntimeRegistration)
                {
                    $registrationsByKey[[string] $registration.Key] = New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -ImportModule $registration.ImportModule -State 'Stale' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted
                }
                else
                {
                    $registrationsByKey[[string] $registration.Key] = New-CompleterRegistrationRecord -Target $registrationState.RuntimeRegistration -ScriptBlock $registrationState.RuntimeRegistration.ScriptBlock -Source 'Discovered' -State 'Conflicted'
                }
            }

            foreach ($registration in $discoveredRegistrations)
            {
                if ($null -eq $registration)
                {
                    continue
                }

                if ($registrationsByKey.Contains([string] $registration.Key))
                {
                    continue
                }

                if ($DiscoveredOnly)
                {
                    $registrationState = Resolve-CompleterRegistrationState -Key $registration.Key

                    if ($registrationState.ManagedState -in 'Active', 'Pending')
                    {
                        continue
                    }

                    if ($registrationState.ManagedState -in 'Stale', 'Failed')
                    {
                        $registrationsByKey[[string] $registration.Key] = New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Discovered' -State 'Conflicted'
                        continue
                    }
                }

                $registrationsByKey[[string] $registration.Key] = $registration
            }
        }
        catch
        {
            throw "Failed to retrieve completer registrations. $($_.Exception.Message)"
        }
        finally
        {
            $targets = @()
            $managedRegistrations = @()
            $discoveredRegistrations = @()
        }
    }

    end
    {
        $registrations = @($registrationsByKey.Values)
        $totalCount = $registrations.Count

        if ($PSCmdlet.PagingParameters.IncludeTotalCount)
        {
            $null = $PSCmdlet.WriteObject($PSCmdlet.PagingParameters.NewTotalCount($totalCount, 1.0))
        }

        $skip = $PSCmdlet.PagingParameters.Skip
        $first = $PSCmdlet.PagingParameters.First

        if ($skip -ge [uint64] $totalCount)
        {
            return
        }

        $startIndex = [int] $skip
        $itemsAvailable = $totalCount - $startIndex
        $itemsToEmit = if ($first -eq [uint64]::MaxValue)
        {
            $itemsAvailable
        }
        elseif ($first -gt [uint64] $itemsAvailable)
        {
            $itemsAvailable
        }
        else
        {
            [int] $first
        }

        if ($itemsToEmit -le 0)
        {
            return
        }

        $endIndex = $startIndex + $itemsToEmit - 1
        $PSCmdlet.WriteObject($registrations[$startIndex..$endIndex], $true)
    }
}
<#
.ForwardHelpTargetName Get-Completer
.ForwardHelpCategory Function
#>
function Get-CompleterRegistrationLegacy
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $ManagedOnly,

        [Parameter()]
        [switch] $DiscoveredOnly
    )

    begin
    {
        Write-CompleterDeprecationWarning -LegacyName 'Get-CompleterRegistration' -NewName 'Get-Completer'

        $steppablePipeline = { Get-Completer @PSBoundParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $steppablePipeline.Begin($PSCmdlet)
    }

    process
    {
        $steppablePipeline.Process($_)
    }

    end
    {
        $steppablePipeline.End()
    }
}
<#
.SYNOPSIS
Imports self-contained completer scripts into registration input objects.

.DESCRIPTION
Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows Register-ArgumentCompleter, and emits objects that
can be piped directly to Register-Completer -InputObject.

Import-CompleterScript has two tiers. The strict tier is the default: it
validates the script against a closed grammar before executing it, rejects
every unsupported construct with the same findings Test-CompleterScript
reports, and avoids mutating the live runtime completer tables during import.
The trusted tier, selected with -Trusted, skips the grammar and dot-sources the
script as-is inside the same capture module, so use it only for scripts you
wrote or reviewed. Imported ScriptBlock objects keep the temporary module
context that contains helper functions and script-scope state defined by the
source script under either tier, and they keep the script as their source
file, so $PSScriptRoot and $PSCommandPath inside a completer name the script's
directory and path exactly as they do when the script is dot-sourced.

Compatible strict-tier completer scripts must be self-contained and must keep script scope
limited to Set-StrictMode, function definitions, importer-safe if statements,
and script-scope Register-ArgumentCompleter calls. Register-ArgumentCompleter
usage must use explicit parameter names and only the supported import-time
surface: -CommandName, -ParameterName, the bare -Native switch, and
-ScriptBlock.

Target metadata must stay literal. -CommandName and -ParameterName may be a
single literal string, a literal string array, or a literal @('...') array
expression. -ScriptBlock must be a literal script block. Positional arguments,
argument splatting, custom Register-ArgumentCompleter wrappers, dot-sourcing,
top-level assignments, loops, try/catch blocks, alias bootstrap, cache
initialization, and external command execution are not import-compatible and
should be moved into lazy helper paths reached from the registered script block.
'#requires -Modules', '#requires -Assembly', 'using module', and 'using
assembly' are rejected because they load code when the script is dot-sourced.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.PARAMETER Trusted
Skips the strict grammar validation and dot-sources the script as-is inside the
capture module. Everything at script scope runs at import time, exactly as it
would when the script is dot-sourced from a profile. The emitted records carry
Trusted set to true.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.ImportedCompleterRegistration records compatible with
Register-Completer -InputObject. The Trusted property records which
tier produced the record.

.EXAMPLE
PS> Import-CompleterScript -Path .\7z_completer.ps1 | Register-Completer -PassThru

Imports a supported completer script and immediately registers the imported
completer definitions through the module's managed registration API.

.EXAMPLE
PS> Import-CompleterScript -Path .\git_completer.ps1 -Trusted | Register-Completer

Imports a completer script you own without validating it against the strict
grammar, then registers it.

.NOTES
Use this compatibility specification when authoring future standalone completer
scripts for import:

- Keep the script self-contained; do not dot-source other scripts.
- Register completers at script scope with literal Register-ArgumentCompleter
  calls.
- Use only -CommandName, -ParameterName, bare -Native, and -ScriptBlock.
- Keep -CommandName and -ParameterName literal; use literal @('name','name.exe')
  when multiple command names are required.
- Move alias bootstrap, cache initialization, generated completion loading, and
  tool discovery into lazy helper logic invoked during completion rather than at
  import time.
#>
function Import-CompleterScript
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter()]
        [switch] $Trusted
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                if (-not $Trusted)
                {
                    Assert-CompleterScriptConformance -LiteralPath $resolvedPath
                }

                $importSession = Import-CompleterScriptDefinition -LiteralPath $resolvedPath

                foreach ($definition in $importSession.Definitions)
                {
                    $targetParameters = @{
                        CommandName = $definition.CommandName
                    }

                    if ($definition.IsNative)
                    {
                        $targetParameters['Native'] = $true
                    }
                    else
                    {
                        $targetParameters['ParameterName'] = $definition.ParameterName
                    }

                    foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                    {
                        $PSCmdlet.WriteObject(
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $resolvedPath -ImportModule $importSession.Module -Trusted:$Trusted)
                        )
                    }
                }
            }
        }
        catch
        {
            throw "Failed to import completer script. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Validates a completer set file and registers every script it lists.

.DESCRIPTION
Reads a completer set, a .psd1 data file written by Export-CompleterSet or by
hand, validates every entry up front, and then registers each valid entry's
targets as managed registrations. The set is read with
Import-PowerShellDataFile, which evaluates data only, and validation never
executes a completer script.

Every entry is checked before anything is registered: the script file must
exist and be a .ps1, Trusted entries must declare their Targets because the
script is not parsed, strict entries must name their targets with literal
Register-ArgumentCompleter arguments so the targets can be derived from the
parsed script and compared against any Targets the entry declares, no target
may be listed by two entries of the set, and without -Force no target may
already carry a managed or runtime registration for a different completer. An
entry that repeats a registration the session already has is reused. The
strict import grammar does not run here; it runs when a script loads.
Validating a strict entry parses its script once and registration reuses the
targets that validation derived, so a set import parses each strict script
once and walks none of them; run Test-CompleterScript over the repository to
find grammar findings ahead of time. When one or more entries are invalid the
command throws a single error that lists every problem and registers nothing.
With -SkipInvalid each problem is written as a warning instead and the valid
entries register.

Relative Path values resolve against the directory of the set file, so a
completer repository can carry its set file next to its scripts.

Registering a set does not run its scripts. Every valid entry is registered
lazily under the entry's trust tier, exactly as Register-Completer
-Lazy registers a script, so each target gets a stub and a managed record in
state Pending. The whole set is one transaction against one snapshot of the
session's registrations: validation and registration read the managed table
and the runtime dictionaries once, and if any runtime or managed write fails,
every change the set made is rolled back and nothing from it stays registered.
The first tab press for a target loads the script and moves the record to
Active; a script that fails to load moves to Failed with the message in
LoadError, and the completion engine's default completion applies as if no
completer were registered. -Force replaces existing registrations for the
set's targets and retries Failed ones.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER SkipInvalid
Writes each invalid entry as a warning and registers the valid entries instead
of failing the whole set.

.PARAMETER Force
Replaces existing managed or runtime registrations for the targets in the set,
including Failed lazy records whose load should be retried.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the CompleterActions.CompleterRegistration records that were created
or reused for the set's targets, in state Pending until each script loads.

.EXAMPLE
PS> Import-CompleterSet -Path ~\Completers\completers.psd1

Registers every completer script listed in the set. This is the one line a
profile needs for a whole completer repository.

.EXAMPLE
PS> Import-CompleterSet -Path ~\Completers\completers.psd1 -SkipInvalid -Force

Registers the valid entries, warns about the rest, and replaces any existing
registration for the same targets.
#>
function Import-CompleterSet
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter()]
        [switch] $SkipInvalid,

        [Parameter()]
        [switch] $Force
    )

    process
    {
        try
        {
            $resolvedPaths = @(
                if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
                    }
                }
                else
                {
                    foreach ($pathItem in $Path)
                    {
                        Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath
                    }
                }
            )

            foreach ($setPath in $resolvedPaths)
            {
                $setDefinition = Import-CompleterSetDefinition -LiteralPath $setPath
                $snapshot = Get-CompleterRegistrationSnapshot
                $claimedTargets = @{}
                $entryIndex = 0
                $entries = @(
                    foreach ($rawEntry in $setDefinition.Entries)
                    {
                        $entryIndex++
                        Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $setDefinition.Directory -ClaimedTargets $claimedTargets -Snapshot $snapshot -Force:$Force
                    }
                )

                $invalidEntries = @($entries | Where-Object { -not $_.IsValid })

                if ($invalidEntries.Count -gt 0)
                {
                    $problemLines = @(
                        foreach ($entry in $invalidEntries)
                        {
                            $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $($entry.Index)" } else { "Entry $($entry.Index) ('$($entry.DeclaredPath)')" }

                            foreach ($problem in $entry.Problems)
                            {
                                '{0}: {1}' -f $entryLabel, $problem
                            }
                        }
                    )

                    if (-not $SkipInvalid)
                    {
                        $entryNoun = if ($invalidEntries.Count -eq 1) { 'entry' } else { 'entries' }
                        throw "Completer set '$setPath' has $($invalidEntries.Count) invalid $entryNoun and nothing was registered. Fix the entries or use -SkipInvalid to register the valid ones.$([Environment]::NewLine)$($problemLines -join [Environment]::NewLine)"
                    }

                    foreach ($problemLine in $problemLines)
                    {
                        Write-Warning -Message "Completer set '$setPath' skipped $problemLine"
                    }
                }

                $confirmedEntries = @(
                    foreach ($entry in @($entries | Where-Object { $_.IsValid }))
                    {
                        if ($PSCmdlet.ShouldProcess($entry.Path, 'Import completer set entry'))
                        {
                            $entry
                        }
                    }
                )

                $registrations = @(foreach ($entry in $confirmedEntries) { $entry.Registrations })
                $conflicts = @(foreach ($entry in $confirmedEntries) { $entry.Conflicts })

                Add-CompleterRegistration -Registration $registrations -Conflict $conflicts
            }
        }
        catch
        {
            throw "Failed to import completer set. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers native or command-parameter argument completers with
Register-ArgumentCompleter and records the registrations in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them. Registering the same script for a target that is already
managed is idempotent only while the managed record still matches the live
runtime value; when the runtime registration was replaced or removed outside
this module, the managed record is stale and the command fails until you
reconcile it with -Force. Each target is updated transactionally: if the
runtime or managed write fails, the previous runtime and managed state are
restored and any rollback failure is reported alongside the original error. The
command supports array inputs for command and parameter targets, and it can
also accept pipeline InputObject values that describe the target and expose a
ScriptBlock property.

With -Path or -LiteralPath and -Lazy the command registers a completer script
without running it. The runtime entry for each target is a small stub that
imports the script through Import-CompleterScript on the first tab press,
replaces itself with the real completer, and delegates that first call to it.
The managed record reports State 'Pending' until then and 'Active' afterwards.
Under the default strict tier the targets are read from the script's literal
Register-ArgumentCompleter arguments, so the script is parsed but never
executed at registration time; the strict grammar itself runs when the script
loads, and a script that fails it moves to 'Failed' then. With -Trusted the
script is dot-sourced as-is
on first use and cannot be parsed safely, so the targets must be supplied with
-CommandName and -Native or -ParameterName.

If the script fails to load on the first tab press, the press returns no
completions, the runtime entry is removed so the completion engine's default
completion applies exactly as with no completer registered, and the managed
record moves to State 'Failed' with the error message in LoadError. Nothing is
written to the host. Registering the same target again with -Force retries the
load. Lazy loading runs entirely inside the ordinary completer call; it never
hooks key handlers, replaces TabExpansion2, or changes PSReadLine options.

.PARAMETER InputObject
Supplies one or more objects that describe completer targets. Input objects must
expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native, and must expose a
ScriptBlock property whose value is a script block. A key without a native
indicator is rejected; keys are output-only identifiers and are never
classified by their shape. ScriptPath or SourcePath and
Trusted properties, such as those on Import-CompleterScript records, are
carried onto the managed record.

.PARAMETER CommandName
Specifies one or more command names whose completers should be registered.
With -Lazy the parameter names the targets the script owns; it is required
with -Trusted and optional under the strict tier, where every name given must
be one the script registers.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer
registrations.

.PARAMETER Native
Registers native completers for the commands instead of parameter completers.

.PARAMETER ScriptBlock
Provides the completer script block to register. When multiple targets are
supplied through arrays, the same script block is reused for each target.

.PARAMETER Path
The path to one completer script file to register lazily. Wildcards are
supported but must resolve to a single file.

.PARAMETER LiteralPath
The literal path to one completer script file to register lazily. Wildcards
are not expanded.

.PARAMETER Lazy
Registers a stub for each target of the script instead of running the script
now. The script is imported on the first tab press for any of its targets.

.PARAMETER Trusted
Imports the script through the trusted tier on first use, dot-sourcing it as-is
without the strict grammar. The targets must be supplied with -CommandName and
-Native or -ParameterName because a trusted script is not parsed. The default
is the strict tier, which validates the script against the grammar when it
loads.

.PARAMETER Force
Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value was
changed outside this module and a Failed lazy record whose load should be
retried.

.PARAMETER PassThru
Returns the managed registration records that were created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Register-Completer -CommandName demoexe -Native -ScriptBlock $nativeScriptBlock

Registers a native completer for demoexe with a script block that is already in
memory.

.EXAMPLE
PS> Register-Completer -Path .\git_completer.ps1 -Lazy -PassThru

Reads the targets from the script's Register-ArgumentCompleter calls, registers
a stub for each of them, and returns the Pending records. The script runs the
first time tab completion is requested for one of its targets.

.EXAMPLE
PS> Register-Completer -Path .\git_completer.ps1 -Lazy -Trusted -CommandName git, git.exe -Native

Registers a script that needs the trusted tier lazily. The targets are named
explicitly because a trusted script is not parsed.

.EXAMPLE
PS> Get-Completer -ManagedOnly | Where-Object State -eq Failed | ForEach-Object { Register-Completer -LiteralPath $_.ScriptPath -Lazy -Trusted:$_.Trusted -CommandName $_.CommandName -Native:$_.IsNative -Force }

Retries every lazy registration whose script failed to load, after the scripts
have been fixed.
#>
function Register-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [switch] $Lazy,

        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [switch] $Trusted,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedInputs = @()
        $isLazy = $PSCmdlet.ParameterSetName -in 'LazyPath', 'LazyLiteralPath'

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedInputs = @($InputObject | Resolve-CompleterInputObject -RequireScriptBlock)
            }
            elseif ($isLazy)
            {
                $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LazyLiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }
                $resolvedPaths = @(Resolve-CompleterScriptPath @pathParameters)

                if ($resolvedPaths.Count -ne 1)
                {
                    throw "Lazy registration takes one completer script per call, but the path resolved to $($resolvedPaths.Count) files."
                }

                $scriptPath = $resolvedPaths[0]
                $explicitTargets = @()

                if ($PSBoundParameters.ContainsKey('CommandName'))
                {
                    if ($Native)
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -Native)
                    }
                    elseif ($PSBoundParameters.ContainsKey('ParameterName'))
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -ParameterName $ParameterName)
                    }
                    else
                    {
                        throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                    }
                }
                elseif ($Native -or $PSBoundParameters.ContainsKey('ParameterName'))
                {
                    throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                }

                if ($Trusted)
                {
                    if ($explicitTargets.Count -eq 0)
                    {
                        throw "-Trusted lazy registration requires explicit targets: a trusted script is not parsed, so its targets cannot be derived from '$scriptPath'. Pass -CommandName with -Native or -ParameterName."
                    }

                    $targets = $explicitTargets
                }
                else
                {
                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath)

                    if ($explicitTargets.Count -eq 0)
                    {
                        $targets = $derivedTargets
                    }
                    else
                    {
                        foreach ($explicitTarget in $explicitTargets)
                        {
                            if (@($derivedTargets.Key) -notcontains $explicitTarget.Key)
                            {
                                $derivedList = ($derivedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                                throw "The script '$scriptPath' does not register a completer for '$($explicitTarget.RuntimeKey)'. It registers: $derivedList."
                            }
                        }

                        $targets = $explicitTargets
                    }
                }

                foreach ($target in $targets)
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = New-CompleterLazyStub -Key $target.Key
                        ImportModule = $null
                        ScriptPath = $scriptPath
                        Trusted = [bool] $Trusted
                    }
                }
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = $ScriptBlock
                        ImportModule = $null
                        ScriptPath = $null
                        Trusted = $false
                    }
                }
            }

            $targetState = if ($isLazy) { 'Pending' } else { 'Active' }

            foreach ($resolvedInput in $resolvedInputs)
            {
                $registration = New-CompleterRegistrationRecord -Target $resolvedInput.Target -ScriptBlock $resolvedInput.ScriptBlock -Source 'Managed' -ImportModule $resolvedInput.ImportModule -State $targetState -ScriptPath $resolvedInput.ScriptPath -Trusted:([bool] $resolvedInput.Trusted)
                $conflict = Resolve-CompleterRegistrationConflict -Registration $registration -Force:$Force

                if ($null -ne $conflict.Problem)
                {
                    throw "Failed to register the completer '$($registration.RuntimeKey)'. $($conflict.Problem)"
                }

                if (-not $conflict.IsExisting -and -not $PSCmdlet.ShouldProcess($registration.RuntimeKey, 'Register completer registration'))
                {
                    continue
                }

                $storedRegistration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                if ($PassThru)
                {
                    $PSCmdlet.WriteObject($storedRegistration)
                }
            }
        }
        finally
        {
            $resolvedInputs = @()
        }
    }
}
<#
.ForwardHelpTargetName Register-Completer
.ForwardHelpCategory Function
#>
function Register-CompleterRegistrationLegacy
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The wrapper forwards -WhatIf and -Confirm to the wrapped command, which calls ShouldProcess.')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [switch] $Lazy,

        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [switch] $Trusted,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        Write-CompleterDeprecationWarning -LegacyName 'Register-CompleterRegistration' -NewName 'Register-Completer'

        $steppablePipeline = { Register-Completer @PSBoundParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $steppablePipeline.Begin($PSCmdlet)
    }

    process
    {
        $steppablePipeline.Process($_)
    }

    end
    {
        $steppablePipeline.End()
    }
}
<#
.SYNOPSIS
Runs tab completion for an input against a registered completer target.

.DESCRIPTION
Resolves a completer target, confirms that it has a live runtime registration,
and runs TabExpansion2 for the supplied input text. The completion matches are
returned as CompleterActions.CompletionMatch records that carry the target key
alongside CompletionText, ListItemText, ResultType, and ToolTip, so the same
check that used to be done by hand after every registration can be scripted
and asserted on.

One input text invokes one completer, so each call tests exactly one target.
The target parameters accept the same shapes as Get-Completer so
registration records and property-bound values pipe in, but the command throws
when more than one target resolves in a single call.

The command only reads the completion engine. It does not change any
registration, and it never touches PSReadLine.

.PARAMETER InputObject
Supplies an object that describes the completer target, such as a record
returned by Get-Completer or Import-CompleterScript. The object
must expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies the command name of the native or command-parameter completer
target.

.PARAMETER ParameterName
Specifies the parameter name of the command-parameter completer target.

.PARAMETER Native
Indicates that the target is a native command completer instead of a command
parameter completer.

.PARAMETER InputText
The command line to complete, exactly as it would be typed at the prompt. It
must invoke the target's command, because the matches come from whatever
command the text names.

.PARAMETER CursorPosition
The zero-based cursor position within InputText at which completion runs. The
default is the end of the input.

.OUTPUTS
CompleterActions.CompletionMatch
Returns CompleterActions.CompletionMatch records, one per completion match,
with Key, RuntimeKey, CommandName, ParameterName, CompleterType, InputText,
CursorPosition, CompletionText, ListItemText, ResultType, and ToolTip
properties. Nothing is returned when the completer yields no matches.

.EXAMPLE
PS> Test-CompleterRegistration -CommandName git -Native -InputText 'git che'

Returns the completion matches the registered git completer produces for
'git che', such as checkout, cherry, and cherry-pick.

.EXAMPLE
PS> Get-Completer -CommandName Invoke-DemoTool -ParameterName Name | Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'

Verifies a registration record returned by Get-Completer by
completing an argument for its parameter.

.NOTES
Completion runs from the module's scope, so the commands named in InputText
must be resolvable from the global scope, as they are in an interactive
session. Functions defined in a script's local scope are not visible to the
completion engine when it is invoked from this command.
#>
function Test-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition
    )

    begin
    {
        $resolvedCursorPosition = if ($PSBoundParameters.ContainsKey('CursorPosition')) { $CursorPosition } else { $InputText.Length }

        if ($resolvedCursorPosition -gt $InputText.Length)
        {
            throw "CursorPosition $resolvedCursorPosition is past the end of InputText, which has $($InputText.Length) characters."
        }

        $resolvedTargets = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets.AddRange([object[]] @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target }))
                return
            }

            $targetParameters = @{}

            switch ($PSCmdlet.ParameterSetName)
            {
                'Native'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['Native'] = $true
                    break
                }

                'CommandParameter'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['ParameterName'] = $ParameterName
                    break
                }
            }

            $resolvedTargets.AddRange([object[]] @(Resolve-CompleterTargetList @targetParameters))
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
    }

    end
    {
        try
        {
            if ($resolvedTargets.Count -ne 1)
            {
                $targetList = ($resolvedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                throw "Test-CompleterRegistration tests one completer target per call because InputText can only invoke one completer, but $($resolvedTargets.Count) targets resolved: $targetList. Call it once per target."
            }

            $target = $resolvedTargets[0]

            if ($null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
            {
                throw "No runtime completer registration exists for '$($target.RuntimeKey)'. Register the completer before testing it."
            }

            $completion = TabExpansion2 -InputScript $InputText -CursorColumn $resolvedCursorPosition

            foreach ($completionMatch in @($completion.CompletionMatches))
            {
                $PSCmdlet.WriteObject((New-CompletionMatch -Target $target -CompletionResult $completionMatch -InputText $InputText -CursorPosition $resolvedCursorPosition))
            }
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedTargets.Clear()
        }
    }
}
<#
.SYNOPSIS
Checks completer scripts against the strict import grammar and reports findings.

.DESCRIPTION
Parses one or more completer scripts and runs the same validation that
Import-CompleterScript applies before it executes a script. Instead of stopping
at the first problem, the command returns one
CompleterActions.CompleterScriptFinding record per unsupported construct with
the line and column, the construct type, a message, and a hint that describes
how to change the script so it imports under the strict tier.

A conforming script produces no output, so a conformance test can assert that
the command returns nothing, or filter on Severity the way the strict importer
does. A script that cannot be parsed yields one finding per parse error and is
not checked further. Test-CompleterScript never executes the script.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompleterScriptFinding records with Path, Line,
Column, Severity, Construct, Message, and Hint properties. Every finding the
strict grammar produces has Severity 'Error'.

.EXAMPLE
PS> Test-CompleterScript -Path .\tool_completer.ps1

Reports each construct that keeps the script from importing under the strict
tier, or nothing when the script conforms.

.EXAMPLE
PS> Get-ChildItem -Path ~\Completers -Recurse -Filter *.ps1 | Test-CompleterScript | Where-Object Severity -eq Error

Runs the conformance check over a completer repository. The pipeline is empty
when every script conforms.
#>
function Test-CompleterScript
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                Get-CompleterScriptFinding -LiteralPath $resolvedPath
            }
        }
        catch
        {
            throw "Failed to test completer script. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Removes completer registrations from runtime and, when applicable, module state.

.DESCRIPTION
Removes completer registrations identified by native command, command
parameter target, or pipeline InputObject values. Managed registrations
are removed from both the PowerShell runtime and the module's registration
table. Runtime-only registrations require -AllowUnmanaged before they can be
removed. The same gate applies when a managed record is stale because the
runtime registration was replaced outside this module: the live value is only
removed with -AllowUnmanaged, and the stale managed record is dropped with it.
When the runtime registration was already removed outside this module, only
the stale managed record remains and it is removed without the gate. A Pending
lazy registration is removed like any managed registration, stub and record
together. A Failed lazy registration has no runtime entry of its own, so only
its managed record is removed. The command supports array inputs for the
target fields, plus pipeline input from Get-Completer output. Keys
are output-only identifiers: a hand-typed key string is not accepted, so name
the target with -CommandName plus -Native or -ParameterName instead.

.PARAMETER InputObject
Supplies one or more objects that describe registrations to remove. Input
objects expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies one or more command names whose completers should be removed.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer removal
targets.

.PARAMETER Native
Targets native completer registrations instead of command parameter completers.

.PARAMETER AllowUnmanaged
Allows removal of runtime registrations that are not tracked by this module,
including a live value that replaced a managed registration outside this
module.

.PARAMETER PassThru
Returns the registration records that were removed.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns removed CompleterActions.CompleterRegistration
records.
#>
function Unregister-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedTargets = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                $resolvedTargets = @(Resolve-CompleterTargetList @targetParameters)
            }

            foreach ($target in $resolvedTargets)
            {
                $managedRegistration = $null
                $runtimeRegistration = $null
                $registrationToRemove = $null
                $removedRuntimeRegistration = $null
                $removedManagedRegistration = $null

                try
                {
                    $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                    $managedRegistration = $registrationState.ManagedRegistration
                    $runtimeRegistration = $registrationState.RuntimeRegistration

                    if ($registrationState.ManagedState -in 'Active', 'Pending')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The module-managed completer registration for '$($runtimeRegistration.RuntimeKey)' is $($registrationState.ManagedState.ToLowerInvariant()): the live runtime registration was created outside this module. Re-run with -AllowUnmanaged to remove the live runtime registration and the managed record."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed. Re-run with -AllowUnmanaged to remove the runtime registration."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    else
                    {
                        throw 'No completer registration was found for the requested target.'
                    }

                    if (-not $PSCmdlet.ShouldProcess($registrationToRemove.RuntimeKey, 'Unregister completer registration'))
                    {
                        continue
                    }

                    if ($null -ne $runtimeRegistration)
                    {
                        $removedRuntimeRegistration = Remove-RuntimeCompleterRegistration -Key $registrationToRemove.Key
                    }

                    if ($null -ne $managedRegistration)
                    {
                        $removedManagedRegistration = Remove-ManagedCompleterRegistration -Key $registrationToRemove.Key
                    }

                    if ($PassThru)
                    {
                        if ($registrationToRemove.IsManaged -and $null -ne $removedManagedRegistration)
                        {
                            $PSCmdlet.WriteObject($removedManagedRegistration)
                        }
                        elseif ($null -ne $removedRuntimeRegistration)
                        {
                            $PSCmdlet.WriteObject($removedRuntimeRegistration)
                        }
                    }
                }
                catch
                {
                    if ($null -ne $removedRuntimeRegistration -and $null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
                    {
                        $null = Add-RuntimeCompleterRegistration -Target $removedRuntimeRegistration -ScriptBlock $removedRuntimeRegistration.ScriptBlock
                    }

                    if ($null -ne $removedManagedRegistration -and $null -eq (Find-ManagedCompleterRegistration -Key $target.Key))
                    {
                        $null = Add-ManagedCompleterRegistration -Registration $removedManagedRegistration
                    }

                    throw "Failed to unregister the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $managedRegistration = $null
                    $runtimeRegistration = $null
                    $registrationToRemove = $null
                    $removedRuntimeRegistration = $null
                    $removedManagedRegistration = $null
                }
            }
        }
        finally
        {
            $resolvedTargets = @()
        }
    }
}
<#
.ForwardHelpTargetName Unregister-Completer
.ForwardHelpCategory Function
#>
function Unregister-CompleterRegistrationLegacy
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The wrapper forwards -WhatIf and -Confirm to the wrapped command, which calls ShouldProcess.')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        Write-CompleterDeprecationWarning -LegacyName 'Unregister-CompleterRegistration' -NewName 'Unregister-Completer'

        $steppablePipeline = { Unregister-Completer @PSBoundParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $steppablePipeline.Begin($PSCmdlet)
    }

    process
    {
        $steppablePipeline.Process($_)
    }

    end
    {
        $steppablePipeline.End()
    }
}
<#
.SYNOPSIS
Writes a batch of completer registrations to the runtime and the managed state as one transaction.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved every
record's conflicts and confirmed the operation. Each record whose conflict
result reports IsExisting is not written; the managed record it already
matches is returned in its place. Every other record's script block is added
to the live completer dictionary and the record is stored in the managed
registration table, in order, and the stored records are returned in the same
order as the input.

If any write fails, the batch is rolled back in reverse: for every record that
was written, the earlier runtime value carried on its conflict result is put
back or the new one removed, and the earlier managed record is put back or the
new one removed, so the session ends exactly as it was before the batch. The
error names the target whose write failed, and a failure during the rollback
is reported together with the original error so the caller can say the target
may be inconsistent. Register-Completer writes each target through
this helper on its own, so every target of a call stays its own transaction,
and Import-CompleterSet writes a whole set through it, so an eager, a lazy,
and a completer set registration share one write path.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records to store, in write order.
Each record's ScriptBlock is the value written to the runtime dictionary.

.PARAMETER Conflict
The results Resolve-CompleterRegistrationConflict returned for the same
records, in the same order. Their RuntimeRegistration and ManagedRegistration
are the state restored when a write fails.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one record per input, in order: the reused managed record for an
existing registration, otherwise the record as stored in the managed
registration table.
#>
function Add-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Conflict
    )

    if ($Registration.Count -ne $Conflict.Count)
    {
        throw "Each registration needs the conflict result resolved for it, but $($Registration.Count) registrations came with $($Conflict.Count) conflict results."
    }

    $storedRegistrations = [System.Collections.Generic.List[psobject]]::new()
    $writeIndex = -1

    try
    {
        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                $storedRegistrations.Add($Conflict[$index].ManagedRegistration)
                continue
            }

            $writeIndex = $index
            $null = Add-RuntimeCompleterRegistration -Target $Registration[$index] -ScriptBlock $Registration[$index].ScriptBlock
            $storedRegistrations.Add((Add-ManagedCompleterRegistration -Registration $Registration[$index]))
        }

        return $storedRegistrations
    }
    catch
    {
        $registrationError = $_
        $failedRegistration = $Registration[$writeIndex]
        $rollbackErrors = [System.Collections.Generic.List[string]]::new()

        for ($index = $writeIndex; $index -ge 0; $index--)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            try
            {
                if ($null -ne $Conflict[$index].RuntimeRegistration)
                {
                    $null = Add-RuntimeCompleterRegistration -Target $Conflict[$index].RuntimeRegistration -ScriptBlock $Conflict[$index].RuntimeRegistration.ScriptBlock
                }
                else
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $Registration[$index].Key
                }

                if ($null -ne $Conflict[$index].ManagedRegistration)
                {
                    $null = Add-ManagedCompleterRegistration -Registration $Conflict[$index].ManagedRegistration
                }
                else
                {
                    $null = Remove-ManagedCompleterRegistration -Key $Registration[$index].Key
                }
            }
            catch
            {
                $rollbackErrors.Add($_.Exception.Message)
            }
        }

        $message = "Failed to register the completer '$($failedRegistration.RuntimeKey)'. $($registrationError.Exception.Message)"

        if ($rollbackErrors.Count -gt 0)
        {
            $message += " Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($rollbackErrors -join ' ')"
        }

        throw $message
    }
}
<#
.SYNOPSIS
Adds or replaces a managed registration record in module state.

.DESCRIPTION
Stores a registration object in the module's in-memory registration table using
its Key property as the dictionary key. Existing entries with the same key are
replaced, which lets higher-level registration code refresh an internal record
after re-registering a completer.

.PARAMETER Registration
The registration record to store. The object must expose a non-empty Key
property.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the record that is stored in the managed registration table.

.EXAMPLE
PS> $record | Add-ManagedCompleterRegistration

Adds a newly created internal registration record to the module state, replacing
any prior record for the same target key.
#>
function Add-ManagedCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $Registration
    )

    process
    {
        if ($Registration.PSObject.Properties.Match('Key').Count -eq 0 -or [string]::IsNullOrWhiteSpace([string] $Registration.Key))
        {
            throw 'Registration records must expose a non-empty Key property.'
        }

        try
        {
            $registrations = Get-ManagedCompleterRegistrationTable
            $registrations[[string] $Registration.Key] = $Registration

            return $registrations[[string] $Registration.Key]
        }
        catch
        {
            throw "Failed to add the managed completer registration '$([string] $Registration.Key)'. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Adds or replaces a runtime completer registration in PowerShell's live dictionaries.

.DESCRIPTION
Writes directly to the runtime completer dictionaries that back TabExpansion2. The
helper initializes the relevant dictionary when PowerShell has not created it yet,
which keeps imported and ordinary completer registrations on the same runtime path.

.PARAMETER Target
The completer target or registration object. It must expose RuntimeKey and IsNative.

.PARAMETER ScriptBlock
The completer script block to register.
#>
function Add-RuntimeCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates the live completer runtime dictionaries on behalf of public commands.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($Target.PSObject.Properties.Match($requiredProperty).Count -eq 0)
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $runtime = Get-CompleterRuntime
    $propertyName = if ($Target.IsNative) { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
    $dictionary = $runtime.$propertyName

    if ($null -eq $dictionary)
    {
        $runtimeProperty = if ($Target.IsNative) { $runtime.NativeProperty } else { $runtime.CustomProperty }
        if ($null -eq $runtimeProperty)
        {
            throw "The current PowerShell runtime does not expose the '$propertyName' completer dictionary."
        }

        $dictionary = [System.Collections.Generic.Dictionary[string, scriptblock]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $runtimeProperty.SetValue($runtime.ExecutionContext, $dictionary)
    }

    $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey) -Value $ScriptBlock

    return Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey)
}
<#
.SYNOPSIS
Asserts that the PowerShell runtime exposes every internal member CompleterActions needs.

.DESCRIPTION
CompleterActions reaches into non-public PowerShell runtime members to discover and
manage argument completers: the execution context field behind EngineIntrinsics and
the two completer dictionaries that execution context owns.

This probe resolves all of those members once during module import so an engine whose
internals changed fails with a single terminating error that names the PowerShell
version and the unresolved members, instead of failing deep inside a later
registration or discovery call.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to reflect against. This is primarily exposed for
internal testing of compatibility guards.

.PARAMETER RuntimeExecutionContext
An already resolved execution context object to inspect for the completer
dictionaries. When supplied, the execution context resolution step is skipped. This
is primarily exposed for internal testing of compatibility guards.

.OUTPUTS
None

.EXAMPLE
Assert-CompleterRuntimeCapability

Verifies that the current engine exposes the reflected completer runtime members and
throws a single terminating error when any of them cannot be resolved.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the error
message explicit about both the engine version and the unresolved members so a future
runtime change is diagnosable from the import failure alone.
#>
function Assert-CompleterRuntimeCapability
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics],

        [Parameter()]
        [object] $RuntimeExecutionContext
    )

    $missingMembers = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $RuntimeExecutionContext)
    {
        try
        {
            $RuntimeExecutionContext = Resolve-CompleterRuntimeExecutionContext -EngineIntrinsics $EngineIntrinsics -EngineIntrinsicsType $EngineIntrinsicsType
        }
        catch
        {
            $missingMembers.Add('System.Management.Automation.EngineIntrinsics._context')
        }
    }

    if ($missingMembers.Count -eq 0)
    {
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
        $runtimeExecutionContextType = $RuntimeExecutionContext.GetType()

        foreach ($propertyName in 'CustomArgumentCompleters', 'NativeArgumentCompleters')
        {
            if ($null -eq $runtimeExecutionContextType.GetProperty($propertyName, $bindingFlags))
            {
                $missingMembers.Add("$($runtimeExecutionContextType.FullName).$propertyName")
            }
        }
    }

    if ($missingMembers.Count -gt 0)
    {
        $missingMemberList = $missingMembers -join "', '"

        throw "CompleterActions cannot run on PowerShell $($PSVersionTable.PSVersion): the required runtime member(s) '$missingMemberList' could not be resolved. Completer discovery depends on PowerShell internals; check for a module update that supports this engine version."
    }
}
<#
.SYNOPSIS
Throws when a completer script does not conform to the strict import grammar.

.DESCRIPTION
Runs Get-CompleterScriptFinding over a completer script and throws one error
that lists every Error finding with its line, column, construct, message, and
hint. Import-CompleterScript runs this gate under the strict tier, both for an
eager import and when a lazy stub loads its script on the first tab press, so
no strict path executes a script the grammar rejects and every path reports
the same findings as Test-CompleterScript. A conforming script returns without
output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
None
#>
function Assert-CompleterScriptConformance
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $findings = @(Get-CompleterScriptFinding -LiteralPath $LiteralPath | Where-Object -Property Severity -EQ -Value 'Error')

    if ($findings.Count -eq 0)
    {
        return
    }

    $findingLines = foreach ($finding in $findings)
    {
        'Line {0}, column {1} ({2}): {3} {4}' -f $finding.Line, $finding.Column, $finding.Construct, $finding.Message, $finding.Hint
    }

    throw "Completer script '$LiteralPath' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is.$([Environment]::NewLine)$($findingLines -join [Environment]::NewLine)"
}
<#
.SYNOPSIS
Finds managed completer registrations from module state.

.DESCRIPTION
Returns registration records from the module's in-memory registration table.
Callers can enumerate all records, resolve a record by its normalized key, or
look up a record by command and parameter target details using the same key
resolution logic as registration and removal helpers.

.PARAMETER Key
The normalized or runtime key for the registration record to retrieve.

.PARAMETER CommandName
The command or native executable name for the registration target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER Native
Indicates that the lookup target is a native command completer.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns matching CompleterActions.CompleterRegistration records, if found.

.EXAMPLE
PS> Find-ManagedCompleterRegistration -CommandName Get-Widget -ParameterName Name

Looks up the registration record associated with a specific command parameter
target.

.EXAMPLE
PS> Find-ManagedCompleterRegistration

Enumerates every managed registration record currently tracked in module state.
#>
function Find-ManagedCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $registrations = Get-ManagedCompleterRegistrationTable

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        return $registrations.Values
    }

    $resolvedKey = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey' { Get-CompleterRegistrationKey -RuntimeKey $Key }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Get-CompleterRegistrationKey -CommandName $CommandName -Native
        }
        'CommandParameter' { Get-CompleterRegistrationKey -CommandName $CommandName -ParameterName $ParameterName }
    }

    if (-not $registrations.Contains($resolvedKey))
    {
        return
    }

    return $registrations[$resolvedKey]
}
<#
.SYNOPSIS
Finds completer registrations from the live PowerShell runtime dictionaries.

.DESCRIPTION
Queries the current session's runtime completer dictionaries and returns
registration records for discovered entries. Maintainers use this helper to
inspect the registrations that PowerShell is actually using, rather than only
the module's cached or intended state.

The lookup can enumerate all discovered registrations, resolve a specific
command-parameter or native target, or search by the module's normalized key.
Because the underlying data comes from PowerShell runtime internals, the result
represents the current session only and depends on internal dictionary shapes
remaining stable.

A completer registered with Register-ArgumentCompleter -ParameterName alone,
without -CommandName, sits in the custom dictionary under the bare parameter
name. The module does not manage that target kind, so enumeration skips such
entries with a verbose message and key lookups never match them; they cannot
abort discovery of the supported targets.

.PARAMETER Key
The normalized registration key used by the module when matching a discovered
runtime registration.

.PARAMETER CommandName
The command or native executable name that identifies the runtime completer
target.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target.

.PARAMETER Native
Indicates that the lookup targets the native completer dictionary.

.OUTPUTS
CompleterActions.CompleterRegistration
System.Collections.Generic.List[object]

.EXAMPLE
Find-RuntimeCompleterRegistration

Enumerates all completer registrations currently exposed by the live PowerShell
runtime for maintainer inspection.

.EXAMPLE
Find-RuntimeCompleterRegistration -CommandName git -Native

Looks up the discovered runtime registration for a native completer target.

.EXAMPLE
Find-RuntimeCompleterRegistration -Key 'get-item:path'

Shows how maintainers can search for a runtime registration by the module's
normalized key instead of by raw runtime key shape.

.NOTES
This helper reads PowerShell's live completer dictionaries through
Get-CompleterRuntime, which depends on runtime internals. Treat the discovered
results as implementation details for maintainers, not as a stable public
contract.
#>
function Find-RuntimeCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject], [System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = Get-CompleterRuntime

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        $registrations = [System.Collections.Generic.List[object]]::new()

        if ($null -ne $runtime.NativeArgumentCompleters)
        {
            foreach ($entry in $runtime.NativeArgumentCompleters.GetEnumerator())
            {
                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key) -Native
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered'))
            }
        }

        if ($null -ne $runtime.CustomArgumentCompleters)
        {
            foreach ($entry in $runtime.CustomArgumentCompleters.GetEnumerator())
            {
                if (Test-CompleterParameterOnlyKey -Key ([string] $entry.Key))
                {
                    Write-Verbose -Message "Skipping the parameter-only completer registration '$($entry.Key)': it was registered with Register-ArgumentCompleter -ParameterName without -CommandName, and CompleterActions manages command-parameter and native targets only."
                    continue
                }

                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key)
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered'))
            }
        }

        return $registrations
    }

    $target = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey'
        {
            $normalizedKey = Get-CompleterRegistrationKey -RuntimeKey $Key

            if ($null -ne $runtime.NativeArgumentCompleters)
            {
                foreach ($entryKey in $runtime.NativeArgumentCompleters.Keys)
                {
                    if ([string]::Equals([string] $entryKey, $normalizedKey, [System.StringComparison]::OrdinalIgnoreCase))
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) -Native) -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $runtime.NativeArgumentCompleters -Key ([string] $entryKey)) -Source 'Discovered'
                    }
                }
            }

            if ($null -ne $runtime.CustomArgumentCompleters)
            {
                foreach ($entryKey in $runtime.CustomArgumentCompleters.Keys)
                {
                    if ((Test-CompleterParameterOnlyKey -Key ([string] $entryKey)))
                    {
                        continue
                    }

                    if ([string]::Equals([string] $entryKey, $normalizedKey, [System.StringComparison]::OrdinalIgnoreCase))
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entryKey)) -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $runtime.CustomArgumentCompleters -Key ([string] $entryKey)) -Source 'Discovered'
                    }
                }
            }

            return
        }

        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
            break
        }

        'CommandParameter'
        {
            Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
            break
        }
    }

    $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

    if ($null -eq $dictionary -or -not (Test-CompleterRuntimeDictionaryKey -Dictionary $dictionary -Key $target.RuntimeKey))
    {
        return
    }

    return New-CompleterRegistrationRecord -Target $target -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $target.RuntimeKey) -Source 'Discovered'
}
<#
.SYNOPSIS
Gets the module-scoped completer state table.

.DESCRIPTION
Returns the script-scoped state container used by the module to track managed
completer registrations. The helper initializes the state on first access and
repairs missing top-level members when older or partially constructed state is
encountered during maintenance or tests.

.OUTPUTS
System.Collections.Specialized.OrderedDictionary
Returns the module state dictionary with SchemaVersion and Registrations entries.

.EXAMPLE
PS> $state = Get-CompleterActionState

Retrieves the current in-memory state table so a maintainer can inspect or
update registration bookkeeping during module development.
#>
function Get-CompleterActionState
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $stateVariable = Get-Variable -Name 'CompleterActionState' -Scope Script -ErrorAction Ignore

    if ($null -eq $stateVariable)
    {
        $script:CompleterActionState = [ordered]@{
            SchemaVersion = 1
            Registrations = [ordered]@{}
        }

        return $script:CompleterActionState
    }

    if ($null -eq $script:CompleterActionState)
    {
        $script:CompleterActionState = [ordered]@{}
    }

    if ($script:CompleterActionState -isnot [System.Collections.IDictionary])
    {
        throw 'Module state variable ''CompleterActionState'' must be a dictionary-backed object.'
    }

    if (-not $script:CompleterActionState.Contains('SchemaVersion'))
    {
        $script:CompleterActionState['SchemaVersion'] = 1
    }

    if (-not $script:CompleterActionState.Contains('Registrations'))
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($null -eq $script:CompleterActionState['Registrations'])
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($script:CompleterActionState['Registrations'] -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $script:CompleterActionState
}
<#
.SYNOPSIS
Normalizes a completer target into the module's registration key format.

.DESCRIPTION
Builds the lowercase lookup key used by the private registration table. For
parameter completers the key is command and parameter name joined with a colon;
for native completers the command name alone is used. When a runtime key is
already available, the helper normalizes and returns it unchanged apart from
case folding.

.PARAMETER CommandName
The command or native executable name that identifies the completer target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER RuntimeKey
An existing runtime key to normalize for table lookups.

.PARAMETER Native
Indicates that the target represents a native command completer.

.PARAMETER CompleterType
An alternate way to indicate whether the target should be treated as a native
or parameter completer when resolving the key.

.OUTPUTS
System.String
Returns the normalized registration key used for internal lookups.

.EXAMPLE
PS> Get-CompleterRegistrationKey -CommandName Get-Widget -ParameterName Name

Returns the normalized key used to store or retrieve a parameter completer
registration for Get-Widget:Name.

.EXAMPLE
PS> Get-CompleterRegistrationKey -RuntimeKey 'Git'

Normalizes a previously captured runtime key before using it against the
registration table.
#>
function Get-CompleterRegistrationKey
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'RuntimeKey')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeKey,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [switch] $Native,

        [Parameter()]
        [ValidateSet('Parameter', 'Native')]
        [string] $CompleterType
    )

    $isNative = $Native.IsPresent -or $CompleterType -eq 'Native'

    if ($PSBoundParameters.ContainsKey('RuntimeKey'))
    {
        return $RuntimeKey.ToLowerInvariant()
    }

    if ($isNative)
    {
        return $CommandName.ToLowerInvariant()
    }

    return ('{0}:{1}' -f $CommandName, $ParameterName).ToLowerInvariant()
}
<#
.SYNOPSIS
Captures the managed registration table and the live runtime completer dictionaries once for a batch of lookups.

.DESCRIPTION
Reads the module's managed registration table and the current session's
runtime completer dictionaries once, and indexes the runtime keys case
insensitively, so that a batch of targets can be reconciled against the
session without reaching into PowerShell internals for each one.
Resolve-CompleterRegistrationState resolves keys against a snapshot, taking
its own when the caller passes none, and Import-CompleterSet takes one
snapshot per set so validating and registering hundreds of targets costs one
runtime read. The snapshot holds references to the live table and
dictionaries: it describes the session at the moment it was taken and is meant
to be consumed before the same batch writes. Parameter-only entries of the
custom dictionary, registered with Register-ArgumentCompleter -ParameterName
alone, are left out of the index because the module does not manage them and
a native-shaped key must never resolve against one.

.OUTPUTS
CompleterActions.CompleterRegistrationSnapshot
Returns an object with Managed, the managed registration table, and Runtime,
one view per runtime dictionary in the order Find-RuntimeCompleterRegistration
searches them, native first. Each view carries IsNative, the Dictionary, and
Keys, a case-insensitive map from a key to the casing the dictionary stores.

.EXAMPLE
PS> $snapshot = Get-CompleterRegistrationSnapshot

Captures the session's registrations before resolving a set of targets against
them.
#>
function Get-CompleterRegistrationSnapshot
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $runtime = Get-CompleterRuntime
    $views = @(
        foreach ($view in @(
                @{ IsNative = $true; Dictionary = $runtime.NativeArgumentCompleters },
                @{ IsNative = $false; Dictionary = $runtime.CustomArgumentCompleters }
            ))
        {
            $keys = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            if ($null -ne $view.Dictionary)
            {
                foreach ($entryKey in $view.Dictionary.Keys)
                {
                    if (-not $view.IsNative -and (Test-CompleterParameterOnlyKey -Key ([string] $entryKey)))
                    {
                        continue
                    }

                    $keys[[string] $entryKey] = [string] $entryKey
                }
            }

            [pscustomobject] [ordered] @{
                IsNative   = $view.IsNative
                Dictionary = $view.Dictionary
                Keys       = $keys
            }
        }
    )

    return [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterRegistrationSnapshot'
        Managed    = Get-ManagedCompleterRegistrationTable
        Runtime    = $views
    }
}
<#
.SYNOPSIS
Gets the current session's completer runtime dictionaries from PowerShell internals.

.DESCRIPTION
Uses reflection against the current EngineIntrinsics instance to reach the
execution context object that owns the runtime completer dictionaries.
Maintainers use this helper when they need authoritative access to the live
CustomArgumentCompleters and NativeArgumentCompleters collections that
Register-ArgumentCompleter populates.

This helper depends on non-public PowerShell runtime details. It is therefore
intended only for internal module plumbing and may require updates if future
PowerShell versions rename or hide the reflected members.

.OUTPUTS
CompleterActions.CompleterRuntime

.EXAMPLE
Get-CompleterRuntime

Returns the current runtime wrapper object so a maintainer can inspect the live
completer dictionaries during module development or debugging.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the
error messages explicit so failures are diagnosable when runtime implementation
details change across PowerShell releases.
#>
function Get-CompleterRuntime
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
    $runtimeExecutionContext = Resolve-CompleterRuntimeExecutionContext
    $runtimeExecutionContextType = $runtimeExecutionContext.GetType()
    $customArgumentCompletersProperty = $runtimeExecutionContextType.GetProperty('CustomArgumentCompleters', $bindingFlags)
    $nativeArgumentCompletersProperty = $runtimeExecutionContextType.GetProperty('NativeArgumentCompleters', $bindingFlags)

    if ($null -eq $customArgumentCompletersProperty -or $null -eq $nativeArgumentCompletersProperty)
    {
        throw 'The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.'
    }

    $runtime = [pscustomobject] [ordered] @{
        PSTypeName               = 'CompleterActions.CompleterRuntime'
        ExecutionContext         = $runtimeExecutionContext
        CustomProperty           = $customArgumentCompletersProperty
        CustomArgumentCompleters = $customArgumentCompletersProperty.GetValue($runtimeExecutionContext)
        NativeProperty           = $nativeArgumentCompletersProperty
        NativeArgumentCompleters = $nativeArgumentCompletersProperty.GetValue($runtimeExecutionContext)
    }

    return $runtime
}
<#
.SYNOPSIS
Gets a value from a runtime completer dictionary by key.
#>
function Get-CompleterRuntimeDictionaryValue
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if (-not (Test-CompleterRuntimeDictionaryKey -Dictionary $Dictionary -Key $Key))
    {
        return $null
    }

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    return $Dictionary[$Key]
}
<#
.SYNOPSIS
Parses a completer script and returns its strict-grammar findings.

.DESCRIPTION
Runs the validation shared by Test-CompleterScript and Import-CompleterScript.
A script that fails to parse yields one finding per parse error and is not
checked further; a script that parses is validated against the strict import
grammar by Test-CompleterScriptAst. A conforming script produces no output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Get-CompleterScriptFinding
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $parseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath

    if ($parseResult.ParseErrors.Count -gt 0)
    {
        foreach ($parseError in $parseResult.ParseErrors)
        {
            New-CompleterScriptFinding -Path $LiteralPath -Extent $parseError.Extent -Construct 'ParseError' -Message $parseError.Message -Hint 'Fix the syntax error; the completer shape is only checked once the script parses.'
        }

        return
    }

    Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $LiteralPath
}
<#
.SYNOPSIS
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope. Parse
errors are returned on the result rather than thrown, so callers can report
them as findings.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterScriptParseResult
#>
function Get-CompleterScriptParseResult
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $LiteralPath,
        [ref] $tokens,
        [ref] $parseErrors
    )

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
<#
.SYNOPSIS
Derives the completer targets a strict-tier script registers without executing it.

.DESCRIPTION
Parses the script once and reads the literal -CommandName, -ParameterName, and
-Native arguments of every script-scope Register-ArgumentCompleter call from
the AST, resolving them into normalized completer targets. Nested script
blocks are not searched: a call inside a completer body or a function does not
run when the script is imported, and skipping them keeps the walk cheap. The
strict import grammar requires those arguments to be literal, so a conforming
script's targets are known without running it, and a script whose arguments
cannot be read statically is reported with the position of the offending
argument. The grammar itself does not run here; it runs through
Import-CompleterScript when the script loads, so registering a script lazily
costs one parse rather than a full conformance walk. Duplicate targets
collapse to one record.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterTarget
#>
function Get-CompleterScriptTarget
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $parseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath

    if ($parseResult.ParseErrors.Count -gt 0)
    {
        $parseError = $parseResult.ParseErrors[0]
        throw "The script '$LiteralPath' does not parse, so its targets cannot be derived. Line $($parseError.Extent.StartLineNumber), column $($parseError.Extent.StartColumnNumber): $($parseError.Message)"
    }

    $registerCommands = @($parseResult.Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $false
        ))

    $targetsByKey = [ordered] @{}

    foreach ($registerCommand in $registerCommands)
    {
        $commandNames = @()
        $parameterNames = @()
        $isNative = $false
        $currentParameter = $null

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -eq 'Native')
                {
                    $isNative = $true
                    $currentParameter = $null
                    continue
                }

                if ($null -eq $commandElement.Argument)
                {
                    $currentParameter = $commandElement.ParameterName
                    continue
                }

                $argumentAst = $commandElement.Argument
                $argumentParameter = $commandElement.ParameterName
            }
            else
            {
                $argumentAst = $commandElement
                $argumentParameter = $currentParameter
            }

            $currentParameter = $null

            if ($argumentParameter -notin 'CommandName', 'ParameterName')
            {
                continue
            }

            try
            {
                $argumentValues = @([string[]] @($argumentAst.SafeGetValue()))
            }
            catch
            {
                throw "The script '$LiteralPath' does not use a literal -$argumentParameter argument at line $($argumentAst.Extent.StartLineNumber), column $($argumentAst.Extent.StartColumnNumber), so its targets cannot be derived without running it. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
            }

            if ($argumentParameter -eq 'CommandName')
            {
                $commandNames += $argumentValues
            }
            else
            {
                $parameterNames += $argumentValues
            }
        }

        $targetParameters = @{
            CommandName = $commandNames
        }

        if ($isNative)
        {
            $targetParameters['Native'] = $true
        }
        else
        {
            $targetParameters['ParameterName'] = $parameterNames
        }

        foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
        {
            $targetsByKey[[string] $target.Key] = $target
        }
    }

    if ($targetsByKey.Count -eq 0)
    {
        throw "The script '$LiteralPath' does not call Register-ArgumentCompleter with literal targets, so nothing can be registered lazily. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
    }

    return @($targetsByKey.Values)
}
<#
.SYNOPSIS
Gets the managed registration dictionary from module state.

.DESCRIPTION
Returns the dictionary stored in the module state under the Registrations key.
This helper centralizes validation of that member so callers can work with the
registration table without repeating state-shape checks.

.OUTPUTS
System.Collections.IDictionary
Returns the dictionary that stores managed completer registration records by key.

.EXAMPLE
PS> $registrations = Get-ManagedCompleterRegistrationTable

Retrieves the backing registration table before adding, finding, or removing
managed completer records inside module internals.
#>
function Get-ManagedCompleterRegistrationTable
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    $state = Get-CompleterActionState
    $registrations = $state['Registrations']

    if ($registrations -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $registrations
}
<#
.SYNOPSIS
Executes a completer script in a controlled capture module.

.DESCRIPTION
Creates a temporary dynamic module that shadows Register-ArgumentCompleter so the
target script can run without mutating the live runtime completer tables. Each
captured script block is the script's own block rebound to the capture module,
so helper functions and script state remain available later and the block
keeps its source file: $PSScriptRoot and $PSCommandPath inside the completer
name the script's directory and path, as they do when the script is
dot-sourced.

.PARAMETER LiteralPath
The literal path to the completer script file.

.OUTPUTS
CompleterActions.CompleterScriptImportSession
#>
function Import-CompleterScriptDefinition
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $importModule = $null
    $capturedDefinitions = @()

    try
    {
        $importModule = New-Module -Name ('CompleterActions.ScriptImport.{0}' -f ([guid]::NewGuid().ToString('N'))) -ArgumentList $LiteralPath -ScriptBlock {
            param(
                [Parameter(Mandatory)]
                [string] $ScriptPath
            )

            $script:CapturedCompleterDefinitions = [System.Collections.Generic.List[object]]::new()

            function Register-ArgumentCompleter
            {
                [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
                param(
                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $CommandName,

                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $ParameterName,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [switch] $Native,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNull()]
                    [scriptblock] $ScriptBlock
                )

                process
                {
                    # Rebinding the original block to this module keeps its source file, so
                    # $PSScriptRoot and $PSCommandPath inside the completer still name the
                    # script; rebuilding it from text would drop that association.
                    $capturedScriptBlock = $ExecutionContext.SessionState.Module.NewBoundScriptBlock($ScriptBlock)

                    $script:CapturedCompleterDefinitions.Add(
                        [pscustomobject] [ordered] @{
                            CommandName   = @($CommandName)
                            ParameterName = if ($Native) { @() } else { @($ParameterName) }
                            IsNative      = [bool] $Native
                            ScriptBlock   = $capturedScriptBlock
                        }
                    )
                }
            }

            $null = @(. $ScriptPath)
        }

        $capturedDefinitions = @(& $importModule {
                @($script:CapturedCompleterDefinitions)
            })

        if ($capturedDefinitions.Count -eq 0)
        {
            throw 'The script executed successfully but did not register any completers at script scope.'
        }

        [pscustomobject] [ordered] @{
            PSTypeName  = 'CompleterActions.CompleterScriptImportSession'
            Path        = $LiteralPath
            Module      = $importModule
            Definitions = $capturedDefinitions
        }
    }
    catch
    {
        throw "Failed to execute completer script '$LiteralPath' in the import scope. $($_.Exception.Message)"
    }
}
<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 through Import-PowerShellDataFile, which evaluates data only
and refuses anything that would run code, so a set file can never execute a
completer script or anything else. The file must declare Version 1 and a
non-empty Entries array; the entries themselves are validated one by one by
Resolve-CompleterSetEntry.

.PARAMETER LiteralPath
The literal path to the completer set file.

.OUTPUTS
CompleterActions.CompleterSetDefinition
#>
function Import-CompleterSetDefinition
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $file = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop

    if ($file.PSIsContainer)
    {
        throw "Completer sets must be file paths. '$LiteralPath' is a directory."
    }

    if ($file.Extension -ne '.psd1')
    {
        throw "Completer sets must be .psd1 files. Received '$LiteralPath'."
    }

    $data = Import-PowerShellDataFile -LiteralPath $file.FullName -ErrorAction Stop

    if (-not $data.Contains('Version') -or $data['Version'] -ne 1)
    {
        throw "Completer set '$($file.FullName)' must declare Version = 1."
    }

    $entries = @()

    if ($data.Contains('Entries'))
    {
        $entries = @($data['Entries'] | Where-Object { $null -ne $_ })
    }

    if ($entries.Count -eq 0)
    {
        throw "Completer set '$($file.FullName)' has no Entries."
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterSetDefinition'
        Path       = $file.FullName
        Directory  = $file.DirectoryName
        Version    = 1
        Entries    = $entries
    }
}
<#
.SYNOPSIS
Loads a lazily registered completer script on its first invocation and delegates the call.

.DESCRIPTION
Runs inside the ordinary completer call for a Pending lazy target. It imports
the script recorded on the managed record through Import-CompleterScript, in the
strict or trusted tier the record was registered with, finds the imported script
block for its own target, replaces the runtime dictionary entry with it, and
moves the managed record to Active. Every other Pending record that points at
the same script and tier, and whose runtime entry is still its own stub, is
swapped from the same import so a script that registers several targets is
executed once. When the script registers the same target more than once, the
last definition wins for that target, as it does when the script is
dot-sourced and Register-ArgumentCompleter overwrites the earlier entry. The
call that triggered the load is then delegated to the real script block and
its results are returned.

A load in flight owns its record. The helper tracks the keys it is loading on
the current call stack, so a nested completion for the same target, such as a
script that calls TabExpansion2 for its own command while it loads, returns
nothing instead of starting a second import, and a sibling load never swaps or
fails a record whose own load is still running.

When anything in the load fails, the helper returns nothing, stores the error
message on the managed record as LoadError with State Failed, and removes the
runtime entry for the target, so the completion engine's default completion
applies exactly as it would with no completer registered. No error reaches the
host. The helper never hooks key handlers, replaces TabExpansion2, or touches
PSReadLine options.

.PARAMETER Key
The normalized registration key of the lazy target being invoked.

.PARAMETER ArgumentList
The arguments the completion engine passed to the completer.

.OUTPUTS
System.Management.Automation.CompletionResult
Whatever the loaded completer returns for the delegated call. Nothing when the
load fails.
#>
function Invoke-CompleterLazyStub
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CompletionResult])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ArgumentList = @()
    )

    $callerErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $registration = $null
    $realScriptBlock = $null

    try
    {
        $registration = Find-ManagedCompleterRegistration -Key $Key

        if ($null -eq $registration)
        {
            throw "No managed registration exists for the lazy completer '$Key'."
        }

        if ($registration.State -eq 'Active')
        {
            $realScriptBlock = $registration.ScriptBlock
        }
        else
        {
            if ($registration.State -ne 'Pending')
            {
                throw "The managed registration for '$($registration.RuntimeKey)' is in state '$($registration.State)' and cannot be loaded lazily."
            }

            if (-not $script:CompleterLazyLoadsInProgress.Add($registration.Key))
            {
                return
            }

            try
            {
                # Register-ArgumentCompleter lets the last registration for a target
                # win, so a script that registers the same target twice is reduced
                # to its last definition per key before the initiating target is
                # selected and the siblings are swapped from the same collection.
                $importedRegistrationsByKey = [ordered] @{}

                foreach ($importedRegistration in @(Import-CompleterScript -LiteralPath $registration.ScriptPath -Trusted:$registration.Trusted))
                {
                    $importedRegistrationsByKey[[string] $importedRegistration.Key] = $importedRegistration
                }

                if (-not $importedRegistrationsByKey.Contains($registration.Key))
                {
                    $importedKeys = @($importedRegistrationsByKey.Values | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                    throw "The script '$($registration.ScriptPath)' did not register a completer for '$($registration.RuntimeKey)'. It registered: $importedKeys."
                }

                $ownRegistration = $importedRegistrationsByKey[$registration.Key]

                foreach ($importedRegistration in $importedRegistrationsByKey.Values)
                {
                    $pendingRegistration = Find-ManagedCompleterRegistration -Key $importedRegistration.Key

                    if ($null -eq $pendingRegistration -or
                        $pendingRegistration.State -ne 'Pending' -or
                        $pendingRegistration.ScriptPath -ne $registration.ScriptPath -or
                        [bool] $pendingRegistration.Trusted -ne [bool] $registration.Trusted -or
                        ($pendingRegistration.Key -ne $registration.Key -and $script:CompleterLazyLoadsInProgress.Contains($pendingRegistration.Key)))
                    {
                        continue
                    }

                    $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $pendingRegistration.Key

                    if ($null -eq $runtimeRegistration -or -not [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $pendingRegistration.ScriptBlock))
                    {
                        continue
                    }

                    $null = Add-RuntimeCompleterRegistration -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock
                    $null = Add-ManagedCompleterRegistration -Registration (
                        New-CompleterRegistrationRecord -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock -Source 'Managed' -ImportModule $importedRegistration.ImportModule -State 'Active' -ScriptPath $pendingRegistration.ScriptPath -Trusted:$pendingRegistration.Trusted
                    )
                }

                $realScriptBlock = $ownRegistration.ScriptBlock
            }
            finally
            {
                $null = $script:CompleterLazyLoadsInProgress.Remove($registration.Key)
            }
        }
    }
    catch
    {
        $loadError = $_.Exception.Message

        try
        {
            if ($null -ne $registration)
            {
                $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $registration.Key

                if ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $registration.ScriptBlock))
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $registration.Key
                }

                $null = Add-ManagedCompleterRegistration -Registration (
                    New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -State 'Failed' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted -LoadError $loadError
                )
            }
        }
        catch
        {
            Write-Debug -Message "Failed to record the lazy load failure for '$Key'. $($_.Exception.Message)"
        }

        return
    }

    $ErrorActionPreference = $callerErrorActionPreference

    & $realScriptBlock @ArgumentList
}
<#
.SYNOPSIS
Creates the runtime stub registered for a lazy completer target.

.DESCRIPTION
Builds a script block, bound to this module's session state, that hands every
invocation to Invoke-CompleterLazyStub together with the target's normalized
key. The stub carries nothing else: the script path and trust tier live on the
managed record, so the stub text is the same shape for every lazy target and
the record stays the single source of truth. Binding through the module's
InvokeCommand is what lets the stub reach the module's private helpers when the
completion engine invokes it.

.PARAMETER Key
The normalized registration key of the lazy target.

.OUTPUTS
System.Management.Automation.ScriptBlock
#>
function New-CompleterLazyStub
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory script block.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    $escapedKey = $Key.Replace("'", "''")

    return $ExecutionContext.SessionState.InvokeCommand.NewScriptBlock("Invoke-CompleterLazyStub -Key '$escapedKey' -ArgumentList `$args")
}
<#
.SYNOPSIS
Creates an internal completer registration record object.

.DESCRIPTION
Builds the CompleterRegistration instance stored in the managed registration table. The helper
copies the required target metadata, derives convenience properties such as
CompleterType and IsManaged, and captures both the script block and its text so
module internals can inspect the registered completer later.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, IsNative, and TargetType properties.

.PARAMETER ScriptBlock
The script block that was or will be registered for the completer target.

.PARAMETER Source
Indicates whether the record originated from module-managed registration or from
runtime discovery.

.PARAMETER ImportModule
Preserves a reference to an imported helper module when a registration originated
from Import-CompleterScript.

.PARAMETER State
Describes how the record relates to the live runtime. 'Active' records describe
the value PowerShell is currently using. 'Pending' marks a lazy registration
whose runtime value is still the stub that loads the script on first use.
'Failed' marks a lazy registration whose script failed to load; its runtime
entry was removed and LoadError holds the reason. 'Stale' marks a managed
record whose stored script no longer matches the runtime because the target
was replaced or removed outside this module. 'Conflicted' marks a discovered
runtime value that shadows a stale managed record for the same target.

.PARAMETER ScriptPath
The completer script the registration came from: the file a lazy registration
loads on first use, or the source of an Import-CompleterScript record.

.PARAMETER Trusted
Indicates that the script is imported through the trusted tier, which
dot-sources it without validating it against the strict import grammar.

.PARAMETER LoadError
The error message from the failed lazy load of a 'Failed' record.

.OUTPUTS
CompleterActions.CompleterRegistration
Returns a CompleterRegistration instance suitable for internal storage.

.EXAMPLE
PS> $record = New-CompleterRegistrationRecord -Target $target -ScriptBlock $scriptBlock

Creates a managed registration record from previously resolved target metadata
before adding it to the in-memory registration table.
#>
function New-CompleterRegistrationRecord
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory registration object.')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [ValidateSet('Managed', 'Discovered')]
        [string] $Source = 'Managed',

        [Parameter()]
        [System.Management.Automation.PSModuleInfo] $ImportModule,

        [Parameter()]
        [ValidateSet('Active', 'Pending', 'Failed', 'Stale', 'Conflicted')]
        [string] $State = 'Active',

        [Parameter()]
        [string] $ScriptPath,

        [Parameter()]
        [switch] $Trusted,

        [Parameter()]
        [string] $LoadError
    )

    foreach ($requiredProperty in 'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'TargetType')
    {
        if ($Target.PSObject.Properties.Match($requiredProperty).Count -eq 0)
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $registration = [CompleterRegistration] @{
        Key                 = [string] $Target.Key
        RegistrationKey     = [string] $Target.Key
        RuntimeKey          = [string] $Target.RuntimeKey
        CommandName         = [string] $Target.CommandName
        ParameterName       = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative            = [bool] $Target.IsNative
        CompleterType       = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        TargetType          = [string] $Target.TargetType
        Source              = $Source
        State               = $State
        IsManaged           = $Source -eq 'Managed'
        IsRuntimeRegistered = $State -notin 'Stale', 'Failed'
        ScriptPath          = if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $null } else { $ScriptPath }
        Trusted             = [bool] $Trusted
        LoadError           = if ([string]::IsNullOrWhiteSpace($LoadError)) { $null } else { $LoadError }
        ImportModule        = $ImportModule
        ScriptBlock         = $ScriptBlock
        ScriptText          = $ScriptBlock.ToString()
    }

    return $registration
}
<#
.SYNOPSIS
Creates a completer script validation finding.

.DESCRIPTION
Builds the CompleterActions.CompleterScriptFinding record shared by
Test-CompleterScript and Import-CompleterScript. Each finding pins one
unsupported construct to a source position and pairs the problem statement with
a hint that describes how to bring the script back inside the strict import
grammar.

.PARAMETER Path
The completer script path the finding belongs to.

.PARAMETER Extent
The script extent of the offending construct. The finding takes its line and
column from the start of the extent.

.PARAMETER Construct
The offending construct type, usually the AST node type name.

.PARAMETER Message
The problem statement.

.PARAMETER Hint
How to change the script so the finding goes away.

.PARAMETER Severity
'Error' for constructs the strict importer rejects, 'Warning' for constructs
that import but should be changed.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function New-CompleterScriptFinding
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a finding object.')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.IScriptExtent] $Extent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Construct,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Hint,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string] $Severity = 'Error'
    )

    [CompleterScriptFinding] @{
        Path       = $Path
        Line       = $Extent.StartLineNumber
        Column     = $Extent.StartColumnNumber
        Severity   = $Severity
        Construct  = $Construct
        Message    = $Message
        Hint       = $Hint
    }
}
<#
.SYNOPSIS
Creates a completion match record for a tested completer target.

.DESCRIPTION
Builds the CompletionMatch instance that Test-CompleterRegistration returns for
each completion result TabExpansion2 produced. The helper copies the target
metadata and the input that was completed alongside the completion result's
text, list item, result type, and tooltip.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, and IsNative properties.

.PARAMETER CompletionResult
The completion result returned by TabExpansion2 for the target.

.PARAMETER InputText
The input text that was completed.

.PARAMETER CursorPosition
The cursor position within InputText at which completion ran.

.OUTPUTS
CompleterActions.CompletionMatch
Returns a CompletionMatch instance for one completion result.

.EXAMPLE
PS> New-CompletionMatch -Target $target -CompletionResult $result -InputText 'git che' -CursorPosition 7

Creates the completion match record for one TabExpansion2 result against the
resolved git native completer target.
#>
function New-CompletionMatch
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a completion match object.')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CompletionResult] $CompletionResult,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition
    )

    [CompletionMatch] @{
        Key            = [string] $Target.Key
        RuntimeKey     = [string] $Target.RuntimeKey
        CommandName    = [string] $Target.CommandName
        ParameterName  = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        CompleterType  = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        InputText      = $InputText
        CursorPosition = $CursorPosition
        CompletionText = $CompletionResult.CompletionText
        ListItemText   = $CompletionResult.ListItemText
        ResultType     = $CompletionResult.ResultType
        ToolTip        = $CompletionResult.ToolTip
    }
}
<#
.SYNOPSIS
Creates a Register-Completer-compatible import object.

.DESCRIPTION
Builds the public object emitted by Import-CompleterScript. The resulting object
captures normalized target metadata plus the imported ScriptBlock object from the
temporary import module so callers can pipe it directly into
Register-Completer -InputObject.

.PARAMETER Target
The normalized completer target metadata.

.PARAMETER ScriptBlock
The imported completer script block.

.PARAMETER SourcePath
The source completer script path.

.PARAMETER ImportModule
The temporary module that owns the imported script block context.

.PARAMETER Trusted
Indicates that the script was imported through the trusted tier, which
dot-sources it without validating it against the strict import grammar.

.OUTPUTS
CompleterActions.ImportedCompleterRegistration
#>
function New-ImportedCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an import object.')]
    [OutputType('CompleterActions.ImportedCompleterRegistration')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSModuleInfo] $ImportModule,

        [Parameter()]
        [switch] $Trusted
    )

    [ImportedCompleterRegistration] @{
        Key             = [string] $Target.Key
        RegistrationKey = [string] $Target.Key
        RuntimeKey      = [string] $Target.RuntimeKey
        CommandName     = [string] $Target.CommandName
        ParameterName   = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative        = [bool] $Target.IsNative
        Native          = [bool] $Target.IsNative
        CompleterType   = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        TargetType      = [string] $Target.TargetType
        Source          = 'Imported'
        Trusted         = [bool] $Trusted
        Path            = $SourcePath
        SourcePath      = $SourcePath
        ImportModule    = $ImportModule
        ScriptBlock     = $ScriptBlock
        ScriptText      = $ScriptBlock.ToString()
    }
}
<#
.SYNOPSIS
Removes and returns a value from a runtime completer dictionary by key.
#>
function Remove-CompleterRuntimeDictionaryValue
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if (-not (Test-CompleterRuntimeDictionaryKey -Dictionary $Dictionary -Key $Key))
    {
        return $null
    }

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        $removedValue = ([System.Collections.IDictionary] $Dictionary)[$Key]
        ([System.Collections.IDictionary] $Dictionary).Remove($Key)
        return $removedValue
    }

    $removedValue = $Dictionary[$Key]
    $null = $Dictionary.Remove($Key)

    return $removedValue
}
<#
.SYNOPSIS
Removes a managed completer registration from module state.

.DESCRIPTION
Deletes a registration record from the module's in-memory registration table and
returns the removed record. Callers can target an entry by normalized key or by
command target details, using the same key resolution rules as the other
registration helpers.

.PARAMETER Key
The normalized or runtime key for the registration record to remove.

.PARAMETER CommandName
The command or native executable name for the registration target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER Native
Indicates that the removal target is a native command completer.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the removed CompleterActions.CompleterRegistration record, if one existed.

.EXAMPLE
PS> Remove-ManagedCompleterRegistration -CommandName Get-Widget -ParameterName Name

Removes the managed registration record for a specific command parameter target
and returns the record that was deleted from module state.
#>
function Remove-ManagedCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes in-memory module state for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $registrations = Get-ManagedCompleterRegistrationTable
    $resolvedKey = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey' { Get-CompleterRegistrationKey -RuntimeKey $Key }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Get-CompleterRegistrationKey -CommandName $CommandName -Native
        }
        'CommandParameter' { Get-CompleterRegistrationKey -CommandName $CommandName -ParameterName $ParameterName }
    }

    if (-not $registrations.Contains($resolvedKey))
    {
        return
    }

    $removedRegistration = $registrations[$resolvedKey]
    $registrations.Remove($resolvedKey)

    return $removedRegistration
}
<#
.SYNOPSIS
Removes a completer registration directly from the live PowerShell runtime.

.DESCRIPTION
Targets the current session's runtime completer dictionaries and removes the
matching discovered registration. Maintainers use this helper when internal
module workflows need to reconcile or replace registrations that already exist
in PowerShell's live runtime state.

This helper mutates dictionaries reached through PowerShell runtime internals,
not a public management API. It is therefore intentionally private and should
only be used from higher-level module operations that already understand the
runtime caveats and session-scoped effects.

.PARAMETER Key
The normalized registration key used by the module to find the runtime entry to
remove.

.PARAMETER CommandName
The command or native executable name that identifies the completer target to
remove.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target to remove.

.PARAMETER Native
Indicates that the target to remove is a native completer registration.

.OUTPUTS
CompleterActions.CompleterRegistration

.EXAMPLE
Remove-RuntimeCompleterRegistration -Key 'get-item:path'

Shows the maintainer-oriented path for removing a discovered registration by the
module's normalized key.

.EXAMPLE
Remove-RuntimeCompleterRegistration -CommandName git -Native

Shows how a native completer registration can be removed from the live runtime
dictionary during internal reconciliation.

.NOTES
This helper changes live session state by removing entries from runtime
dictionaries obtained through reflection-backed helpers. If PowerShell changes
those internals, both the targeting logic and the runtime access helper may need
to be updated together.
#>
function Remove-RuntimeCompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes entries from PowerShell runtime completer dictionaries for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = $null
    $runtimeRegistration = $null
    $target = $null
    $dictionary = $null

    try
    {
        $runtime = Get-CompleterRuntime

        if ($PSCmdlet.ParameterSetName -eq 'ByKey')
        {
            $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $Key

            if ($null -eq $runtimeRegistration)
            {
                return
            }

            if ($runtimeRegistration.IsNative)
            {
                $target = Resolve-CompleterTarget -RuntimeKey $runtimeRegistration.RuntimeKey -Native
            }
            else
            {
                $target = Resolve-CompleterTarget -RuntimeKey $runtimeRegistration.RuntimeKey
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Native')
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            $target = Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        else
        {
            $target = Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
        }

        $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

        if ($null -eq $dictionary -or -not (Test-CompleterRuntimeDictionaryKey -Dictionary $dictionary -Key $target.RuntimeKey))
        {
            return
        }

        $removedScriptBlock = Remove-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $target.RuntimeKey
        $removedRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $removedScriptBlock -Source 'Discovered'

        return $removedRegistration
    }
    catch
    {
        $targetDescription = if ($null -ne $target) { $target.RuntimeKey } elseif (-not [string]::IsNullOrWhiteSpace($Key)) { $Key } else { $CommandName }
        throw "Failed to remove the runtime completer registration '$targetDescription'. $($_.Exception.Message)"
    }
    finally
    {
        $runtime = $null
        $runtimeRegistration = $null
        $target = $null
        $dictionary = $null
    }
}
<#
.SYNOPSIS
Resolves a pipeline input object into a completer target definition.

.DESCRIPTION
Normalizes public pipeline input into the target metadata used by the module's
registration, lookup, and removal commands. The helper accepts module
registration records and custom objects that expose CommandName with
IsNative/Native or ParameterName, or a Key, RegistrationKey, or RuntimeKey
together with IsNative/Native. Keys are output-only identifiers, so a key
without a native indicator is rejected rather than classified by its shape.
A ScriptBlock, ImportModule,
ScriptPath or SourcePath, and Trusted property are carried through when present
so imported and managed records round-trip into Register-Completer.

.PARAMETER InputObject
The object to resolve into a completer target.

.PARAMETER RequireScriptBlock
Requires the input object to expose a ScriptBlock property whose value is a
script block.

.OUTPUTS
CompleterActions.ResolvedInputObject

.EXAMPLE
Resolve-CompleterInputObject -InputObject $registration

Resolves a completer registration object returned by Get-Completer
into the normalized target metadata used by the module internals.
#>
function Resolve-CompleterInputObject
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $InputObject,

        [Parameter()]
        [switch] $RequireScriptBlock
    )

    process
    {
        $keyValue = $null
        $commandName = $null
        $parameterName = $null
        $hasNativeIndicator = $false
        $isNative = $false
        $scriptBlock = $null
        $importModule = $null
        $scriptPath = $null
        $trusted = $false
        $target = $null

        try
        {
            foreach ($propertyName in 'Key', 'RegistrationKey', 'RuntimeKey')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                {
                    $keyValue = [string] $property.Value
                    break
                }
            }

            $commandProperty = $InputObject.PSObject.Properties['CommandName']
            if ($null -ne $commandProperty -and -not [string]::IsNullOrWhiteSpace([string] $commandProperty.Value))
            {
                $commandName = [string] $commandProperty.Value
            }

            $parameterProperty = $InputObject.PSObject.Properties['ParameterName']
            if ($null -ne $parameterProperty -and -not [string]::IsNullOrWhiteSpace([string] $parameterProperty.Value))
            {
                $parameterName = [string] $parameterProperty.Value
            }

            foreach ($propertyName in 'IsNative', 'Native')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property)
                {
                    $hasNativeIndicator = $true
                    $isNative = [bool] $property.Value
                    break
                }
            }

            $scriptBlockProperty = $InputObject.PSObject.Properties['ScriptBlock']
            if ($null -ne $scriptBlockProperty -and $scriptBlockProperty.Value -is [scriptblock])
            {
                $scriptBlock = [scriptblock] $scriptBlockProperty.Value
            }

            $importModuleProperty = $InputObject.PSObject.Properties['ImportModule']
            if ($null -ne $importModuleProperty -and $importModuleProperty.Value -is [System.Management.Automation.PSModuleInfo])
            {
                $importModule = [System.Management.Automation.PSModuleInfo] $importModuleProperty.Value
            }

            foreach ($propertyName in 'ScriptPath', 'SourcePath')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                {
                    $scriptPath = [string] $property.Value
                    break
                }
            }

            $trustedProperty = $InputObject.PSObject.Properties['Trusted']
            if ($null -ne $trustedProperty)
            {
                $trusted = [bool] $trustedProperty.Value
            }

            if ($RequireScriptBlock -and $null -eq $scriptBlock)
            {
                throw 'InputObject must expose a ScriptBlock property whose value is a script block.'
            }

            if (-not [string]::IsNullOrWhiteSpace($commandName))
            {
                if ($hasNativeIndicator -and $isNative)
                {
                    $target = Resolve-CompleterTarget -CommandName $commandName -Native
                }
                elseif (-not [string]::IsNullOrWhiteSpace($parameterName))
                {
                    $target = Resolve-CompleterTarget -CommandName $commandName -ParameterName $parameterName
                }
                else
                {
                    throw 'InputObject must expose ParameterName for command-parameter targets or IsNative/Native for native targets.'
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($keyValue))
            {
                if (-not $hasNativeIndicator)
                {
                    throw "InputObject supplies the key '$keyValue' without an IsNative or Native property. Keys are output-only identifiers and are no longer classified by their shape: add IsNative or Native alongside the key, or supply CommandName with Native or ParameterName. See about_CompleterActions_Migration."
                }

                if ($isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue -Native
                }
                else
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue
                }
            }
            else
            {
                throw 'InputObject must expose CommandName with Native or ParameterName, or Key, RegistrationKey, or RuntimeKey with IsNative or Native.'
            }

            [pscustomobject] [ordered] @{
                PSTypeName = 'CompleterActions.ResolvedInputObject'
                InputObject = $InputObject
                Target = $target
                ScriptBlock = $scriptBlock
                ImportModule = $importModule
                ScriptPath = $scriptPath
                Trusted = $trusted
            }
        }
        catch
        {
            throw "Failed to resolve a completer target from InputObject. $($_.Exception.Message)"
        }
        finally
        {
            $keyValue = $null
            $commandName = $null
            $parameterName = $null
            $scriptBlock = $null
            $importModule = $null
            $scriptPath = $null
            $trusted = $false
            $target = $null
        }
    }
}
<#
.SYNOPSIS
Decides whether each of a batch of completer registrations can be written over the current managed and runtime state.

.DESCRIPTION
Reconciles the records through one Resolve-CompleterRegistrationState pass and
applies the module's replacement rules in one place. Without -Force an
existing managed record blocks a registration when it is stale, when its lazy
load failed, or when it describes a different completer, and an unmanaged
runtime registration blocks it as well. A managed record that already
describes the same completer, the same script block text for an eager
registration or the same script and tier for a lazy one, is reported as
existing so the caller can reuse it. A record is lazy when its State is
'Pending'.

The records are resolved in order as if each earlier record of the same call
had already been written: a later record for the same key sees the earlier
one as the managed and runtime registration, so repeating a target within one
call reuses or replaces the first registration exactly as two calls would.
Register-Completer resolves one record at a time, after the
earlier targets of its call have been written, and throws the reported
problem; Resolve-CompleterSetEntry resolves an entry's records together and
collects the problems, so a completer set is validated against the same rules
its registrations are held to.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records that are about to be
written, in the order they will be written.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted, one is taken for this call.

.PARAMETER Force
Indicates that existing registrations are replaced, so nothing is reported as
a problem.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per record, in order, with Key, ManagedRegistration,
RuntimeRegistration, IsExisting (the managed record already describes this
completer), and Problem (the message that blocks the registration, or null).
#>
function Resolve-CompleterRegistrationConflict
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    if ($Registration.Count -eq 0)
    {
        return
    }

    $registrationStates = @(Resolve-CompleterRegistrationState -Key @($Registration | ForEach-Object { [string] $_.Key }) -Snapshot $Snapshot)
    $plannedRegistrations = @{}

    for ($index = 0; $index -lt $Registration.Count; $index++)
    {
        $registrationItem = $Registration[$index]
        $registrationState = $registrationStates[$index]
        $key = [string] $registrationItem.Key

        if ($plannedRegistrations.Contains($key))
        {
            $plannedRegistration = $plannedRegistrations[$key]
            $registrationState = [pscustomobject] [ordered] @{
                Key                 = $key
                ManagedRegistration = $plannedRegistration
                RuntimeRegistration = New-CompleterRegistrationRecord -Target $plannedRegistration -ScriptBlock $plannedRegistration.ScriptBlock -Source 'Discovered'
                ManagedState        = $plannedRegistration.State
            }
        }

        $existingManagedRegistration = $registrationState.ManagedRegistration
        $existingRuntimeRegistration = $registrationState.RuntimeRegistration
        $isExisting = $false
        $problem = $null

        if (-not $Force)
        {
            if ($null -ne $existingManagedRegistration)
            {
                if ($registrationState.ManagedState -eq 'Stale')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
                }
                elseif ($registrationState.ManagedState -eq 'Failed')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' failed to load '$($existingManagedRegistration.ScriptPath)': $($existingManagedRegistration.LoadError) Use -Force to retry the lazy load."
                }
                else
                {
                    $isExisting = if ($registrationItem.State -eq 'Pending')
                    {
                        $existingManagedRegistration.ScriptPath -eq $registrationItem.ScriptPath -and [bool] $existingManagedRegistration.Trusted -eq [bool] $registrationItem.Trusted
                    }
                    else
                    {
                        $existingManagedRegistration.ScriptText -eq $registrationItem.ScriptText
                    }

                    if (-not $isExisting)
                    {
                        $problem = "A module-managed completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
                    }
                }
            }
            elseif ($null -ne $existingRuntimeRegistration)
            {
                $problem = "A runtime completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
            }
        }

        if ($null -eq $problem)
        {
            $plannedRegistrations[$key] = if ($isExisting) { $existingManagedRegistration } else { $registrationItem }
        }

        [pscustomobject] [ordered] @{
            Key                 = $key
            ManagedRegistration = $existingManagedRegistration
            RuntimeRegistration = $existingRuntimeRegistration
            IsExisting          = $isExisting
            Problem             = $problem
        }
    }
}
<#
.SYNOPSIS
Reconciles managed registration records with the live runtime values for one or more targets.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for
each normalized key and reports whether the managed record still describes
what PowerShell is actually using. A managed record is authoritative only
while the runtime holds the same script block, or a script block with
identical text; it is reported as 'Pending' when that script block is still a
lazy stub and 'Active' otherwise. A managed record whose lazy load failed is
reported as 'Failed' regardless of the runtime, because its runtime entry was
removed on purpose. When the runtime value was replaced or removed outside
this module, the managed record is reported as stale so public commands can
surface the live value, refuse silent reuse, and apply the unmanaged-removal
gate.

Every key is resolved against one snapshot of the managed table and the
runtime dictionaries, the one passed in or one taken here, so a batch of keys
costs a single runtime read. Discovered runtime values keep the key casing the
dictionary stores, native entries win over parameter entries with the same
key, and the states come back in the order of the keys.

.PARAMETER Key
The normalized or runtime keys for the completer targets to reconcile.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted the helper takes one for this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per key, in order, with ManagedRegistration,
RuntimeRegistration, and ManagedState ('None', 'Active', 'Pending', 'Failed',
or 'Stale') properties. The registration properties hold the exact stored
objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Key 'get-item:path'

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.

.EXAMPLE
PS> $states = Resolve-CompleterRegistrationState -Key $targets.Key -Snapshot $snapshot

Reconciles every target of a batch against one snapshot of the session.
#>
function Resolve-CompleterRegistrationState
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($null -eq $Snapshot)
    {
        $Snapshot = Get-CompleterRegistrationSnapshot
    }

    foreach ($keyItem in $Key)
    {
        $normalizedKey = Get-CompleterRegistrationKey -RuntimeKey $keyItem
        $managedRegistration = if ($Snapshot.Managed.Contains($normalizedKey)) { $Snapshot.Managed[$normalizedKey] } else { $null }
        $runtimeRegistration = $null

        foreach ($view in $Snapshot.Runtime)
        {
            if (-not $view.Keys.ContainsKey($normalizedKey))
            {
                continue
            }

            $storedKey = $view.Keys[$normalizedKey]
            $target = if ($view.IsNative) { Resolve-CompleterTarget -RuntimeKey $storedKey -Native } else { Resolve-CompleterTarget -RuntimeKey $storedKey }
            $runtimeRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary -Key $storedKey) -Source 'Discovered'
            break
        }

        $managedState = if ($null -eq $managedRegistration)
        {
            'None'
        }
        elseif ($managedRegistration.State -eq 'Failed')
        {
            'Failed'
        }
        elseif ($null -ne $runtimeRegistration -and
            ([object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock) -or
                $managedRegistration.ScriptText -eq $runtimeRegistration.ScriptText))
        {
            if ($managedRegistration.State -eq 'Pending') { 'Pending' } else { 'Active' }
        }
        else
        {
            'Stale'
        }

        [pscustomobject] [ordered] @{
            Key                 = $keyItem
            ManagedRegistration = $managedRegistration
            RuntimeRegistration = $runtimeRegistration
            ManagedState        = $managedState
        }
    }
}
<#
.SYNOPSIS
Resolves PowerShell's internal execution context object used for completer storage.

.DESCRIPTION
Uses reflection against EngineIntrinsics to access the internal execution
context object that owns the runtime completer dictionaries.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to reflect against. This is primarily exposed for
internal testing of compatibility guards.

.OUTPUTS
System.Object
#>
function Resolve-CompleterRuntimeExecutionContext
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics]
    )

    $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
    $engineIntrinsicsField = $EngineIntrinsicsType.GetField('_context', $bindingFlags)

    if ($null -eq $engineIntrinsicsField)
    {
        throw 'Unable to access the PowerShell execution context field required for completer runtime discovery.'
    }

    $runtimeExecutionContext = $engineIntrinsicsField.GetValue($EngineIntrinsics)

    if ($null -eq $runtimeExecutionContext)
    {
        throw 'Unable to resolve the current PowerShell execution context.'
    }

    return $runtimeExecutionContext
}
<#
.SYNOPSIS
Resolves completer script path input into full .ps1 file paths.

.DESCRIPTION
Shared by Import-CompleterScript and Test-CompleterScript so both commands
accept the same -Path and -LiteralPath input and reject the same non-script
input. Wildcards in -Path are expanded; -LiteralPath is used as written.
Directories and files without a .ps1 extension are rejected.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.String
#>
function Resolve-CompleterScriptPath
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    $resolvedPaths = @()

    switch ($PSCmdlet.ParameterSetName)
    {
        'Path'
        {
            foreach ($pathItem in $Path)
            {
                $resolvedPaths += @(Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath)
            }

            break
        }

        'LiteralPath'
        {
            foreach ($literalPathItem in $LiteralPath)
            {
                $resolvedPaths += (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
            }

            break
        }
    }

    foreach ($resolvedPath in $resolvedPaths)
    {
        $file = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
        if ($file.PSIsContainer)
        {
            throw "Completer scripts must be file paths. '$resolvedPath' is a directory."
        }

        if ($file.Extension -ne '.ps1')
        {
            throw "Completer scripts must be .ps1 files. Received '$resolvedPath'."
        }

        $file.FullName
    }
}
<#
.SYNOPSIS
Validates one completer set entry and resolves its script path and targets.

.DESCRIPTION
Normalizes a raw entry hashtable from a completer set into a record that
Import-CompleterSet can register, collecting every problem instead of stopping
at the first so the caller can report all of them at once. A Path that is not
fully qualified, a drive-relative form such as C:scripts\x.ps1 included,
resolves against the set file's directory rather than the current location.
Trusted defaults to false. Trusted
entries must declare Targets because the script is not parsed. Strict entries
must register their targets with literal arguments so the targets can be
derived from the parsed script and, when the entry also declares Targets, the
two lists must match; the strict import grammar itself runs when the script
loads. The entry's Pending records, one lazy stub per target, are then held to
the rules Register-Completer applies through
Resolve-CompleterRegistrationConflict against the snapshot the whole set
shares, so a target that already carries a different registration is a
problem unless -Force is given, and a target that an earlier valid entry of
the same set already claimed is always a problem. A valid entry claims its
targets in ClaimedTargets for the entries after it, and its Registrations and
Conflicts are what Import-CompleterSet writes, so a strict script is parsed
once per import and the session's registrations are read once per set. The
script is never executed.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.PARAMETER ClaimedTargets
The dictionary, shared by every entry of one set, that maps a claimed target
key to the index of the valid entry that claimed it.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot, shared by every entry of
one set, that the entry's targets are reconciled against.

.PARAMETER Force
Indicates that the set is imported with -Force, so existing registrations for
its targets are replaced rather than reported.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns a record with Index, DeclaredPath, Path, Trusted, Targets, the Pending
Registrations built for those targets, the Conflicts resolved for them in the
same order, Problems, and IsValid.
#>
function Resolve-CompleterSetEntry
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Entry,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Index,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SetDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $ClaimedTargets,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $declaredPath = $null
    $resolvedPath = $null
    $scriptIsUsable = $false
    $trusted = $false
    $declaredTargets = $null
    $targets = @()

    if ($Entry -isnot [System.Collections.IDictionary])
    {
        $problems.Add('The entry is not a hashtable with Path, Trusted, and Targets keys.')
    }
    else
    {
        if (-not $Entry.Contains('Path') -or [string]::IsNullOrWhiteSpace([string] $Entry['Path']))
        {
            $problems.Add('The entry has no Path.')
        }
        else
        {
            $declaredPath = [string] $Entry['Path']
            $resolvedPath = [System.IO.Path]::GetFullPath($declaredPath.Replace('\', '/'), $SetDirectory)

            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
            {
                $problems.Add("The file '$resolvedPath' does not exist.")
            }
            elseif ([System.IO.Path]::GetExtension($resolvedPath) -ne '.ps1')
            {
                $problems.Add("The file '$resolvedPath' is not a .ps1 script.")
            }
            else
            {
                $scriptIsUsable = $true
            }
        }

        if ($Entry.Contains('Trusted'))
        {
            if ($Entry['Trusted'] -isnot [bool])
            {
                $problems.Add('Trusted must be $true or $false.')
            }
            else
            {
                $trusted = $Entry['Trusted']
            }
        }

        if ($Entry.Contains('Targets') -and @($Entry['Targets']).Count -gt 0)
        {
            $declaredTargets = @(
                foreach ($targetEntry in @($Entry['Targets']))
                {
                    if ($targetEntry -isnot [System.Collections.IDictionary])
                    {
                        $problems.Add('Each target must be a hashtable with CommandName and either Native = $true or ParameterName.')
                        continue
                    }

                    $commandName = if ($targetEntry.Contains('CommandName')) { [string] $targetEntry['CommandName'] } else { $null }

                    if ([string]::IsNullOrWhiteSpace($commandName))
                    {
                        $problems.Add('A target has no CommandName.')
                        continue
                    }

                    try
                    {
                        if ($targetEntry.Contains('Native') -and $targetEntry['Native'] -eq $true)
                        {
                            Resolve-CompleterTarget -CommandName $commandName -Native
                        }
                        elseif ($targetEntry.Contains('ParameterName') -and -not [string]::IsNullOrWhiteSpace([string] $targetEntry['ParameterName']))
                        {
                            Resolve-CompleterTarget -CommandName $commandName -ParameterName ([string] $targetEntry['ParameterName'])
                        }
                        else
                        {
                            $problems.Add("Target '$commandName' must declare Native = `$true or a ParameterName.")
                        }
                    }
                    catch
                    {
                        $problems.Add($_.Exception.Message)
                    }
                }
            )
        }

        if ($trusted)
        {
            if ($null -eq $declaredTargets)
            {
                $problems.Add('Trusted entries must declare Targets, because a trusted script is not parsed for them.')
            }
            else
            {
                $targets = $declaredTargets
            }
        }
        elseif ($scriptIsUsable)
        {
            $derivedTargets = @()

            try
            {
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $resolvedPath)
            }
            catch
            {
                $problems.Add($_.Exception.Message)
            }

            if ($derivedTargets.Count -gt 0)
            {
                if ($null -eq $declaredTargets)
                {
                    $targets = $derivedTargets
                }
                else
                {
                    $declaredKeys = @($declaredTargets | ForEach-Object { [string] $_.Key })
                    $derivedKeys = @($derivedTargets | ForEach-Object { [string] $_.Key })
                    $mismatch = @($declaredKeys | Where-Object { $_ -notin $derivedKeys }).Count -gt 0 -or @($derivedKeys | Where-Object { $_ -notin $declaredKeys }).Count -gt 0

                    if ($mismatch)
                    {
                        $declaredList = @($declaredTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                        $derivedList = @($derivedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                        $problems.Add("The declared Targets do not match the script. Declared: $declaredList. Script registers: $derivedList.")
                    }
                    else
                    {
                        $targets = $derivedTargets
                    }
                }
            }
        }
    }

    $registrations = @(
        foreach ($target in $targets)
        {
            New-CompleterRegistrationRecord -Target $target -ScriptBlock (New-CompleterLazyStub -Key $target.Key) -Source 'Managed' -State 'Pending' -ScriptPath $resolvedPath -Trusted:$trusted
        }
    )
    $conflicts = @(Resolve-CompleterRegistrationConflict -Registration $registrations -Snapshot $Snapshot -Force:$Force)

    for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++)
    {
        $target = $targets[$targetIndex]

        if ($null -ne $conflicts[$targetIndex].Problem)
        {
            $problems.Add($conflicts[$targetIndex].Problem)
        }

        if ($ClaimedTargets.Contains([string] $target.Key))
        {
            $problems.Add("Target '$($target.RuntimeKey)' is also listed by entry $($ClaimedTargets[[string] $target.Key]).")
        }
    }

    if ($problems.Count -eq 0)
    {
        foreach ($target in $targets)
        {
            $ClaimedTargets[[string] $target.Key] = $Index
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterSetEntry'
        Index         = $Index
        DeclaredPath  = $declaredPath
        Path          = $resolvedPath
        Trusted       = $trusted
        Targets       = @($targets)
        Registrations = $registrations
        Conflicts     = $conflicts
        Problems      = @($problems)
        IsValid       = $problems.Count -eq 0
    }
}
<#
.SYNOPSIS
Resolves completer target metadata from user-facing inputs or runtime keys.

.DESCRIPTION
Normalizes the different target shapes used by the module into a single
CompleterTarget record. Maintainers use this helper when moving between the
module's public command/parameter model and the runtime key shapes used by
PowerShell's completer dictionaries.

For command-parameter completers, runtime keys are expected to use the
'Command:Parameter' format. For native completers, the runtime key is the
command name. This helper validates those assumptions and returns a normalized
target object that other runtime helpers can consume.

.PARAMETER CommandName
The command or native executable name that identifies the completer target.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target.

.PARAMETER Native
Indicates that the target refers to a native command completer rather than a
PowerShell command parameter completer.

.PARAMETER RuntimeKey
The raw key shape used by the PowerShell runtime dictionaries. This is either a
native command name or a 'Command:Parameter' string for command-parameter
targets.

.OUTPUTS
CompleterActions.CompleterTarget

.EXAMPLE
Resolve-CompleterTarget -CommandName git -Native

Shows the maintainer-oriented path that converts a native completer target into
the normalized object used by runtime registration helpers.

.EXAMPLE
Resolve-CompleterTarget -RuntimeKey 'Get-Item:Path'

Shows how a command-parameter runtime key is parsed back into normalized target
metadata.

.NOTES
This helper is intentionally aligned with the runtime key conventions used by
PowerShell's completer dictionaries and the module's registration records. If
those runtime conventions change, update this parser and the related runtime
helpers together.
#>
function Resolve-CompleterTarget
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to select native-specific parameter sets and to derive the target kind.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'RuntimeKey')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeKey
    )

    $resolvedCommandName = $CommandName
    $resolvedParameterName = $ParameterName
    $resolvedIsNative = $false

    switch ($PSCmdlet.ParameterSetName)
    {
        'Native'
        {
            $resolvedIsNative = [bool] $Native
            $RuntimeKey = $CommandName
            break
        }

        'CommandParameter'
        {
            $RuntimeKey = '{0}:{1}' -f $CommandName, $ParameterName
            break
        }

        'NativeRuntimeKey'
        {
            $resolvedCommandName = $RuntimeKey
            $resolvedParameterName = $null
            $resolvedIsNative = [bool] $Native
            break
        }

        'RuntimeKey'
        {
            $match = [System.Text.RegularExpressions.Regex]::Match($RuntimeKey, '^(.*):([^:]+)$')

            if (-not $match.Success)
            {
                throw "Parameter completer runtime keys must use the format 'Command:Parameter'. Received '$RuntimeKey'."
            }

            $resolvedCommandName = $match.Groups[1].Value
            $resolvedParameterName = $match.Groups[2].Value
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedCommandName))
    {
        throw 'Completer targets require a non-empty command name.'
    }

    if (-not $resolvedIsNative -and [string]::IsNullOrWhiteSpace($resolvedParameterName))
    {
        throw 'Command-parameter completer targets require a non-empty parameter name.'
    }

    $resolvedKey = Get-CompleterRegistrationKey -RuntimeKey $RuntimeKey

    $target = [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterTarget'
        Key           = $resolvedKey
        RuntimeKey    = $RuntimeKey
        CommandName   = $resolvedCommandName
        ParameterName = if ($resolvedIsNative) { $null } else { $resolvedParameterName }
        IsNative      = $resolvedIsNative
        TargetType    = if ($resolvedIsNative) { 'Native' } else { 'CommandParameter' }
    }

    return $target
}
<#
.SYNOPSIS
Resolves one or more public cmdlet inputs into completer targets.

.DESCRIPTION
Expands array-based public command inputs into the normalized target objects used
throughout the module. Command and parameter arrays are paired by position when
they have matching lengths, or broadcast when either side contains a single
value.

.PARAMETER CommandName
One or more command names to resolve.

.PARAMETER ParameterName
One or more parameter names to resolve for command-parameter targets.

.PARAMETER Native
Indicates that the targets refer to native completers.

.OUTPUTS
CompleterActions.CompleterTarget
#>
function Resolve-CompleterTargetList
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    switch ($PSCmdlet.ParameterSetName)
    {
        'Native'
        {
            foreach ($commandNameItem in $CommandName)
            {
                Resolve-CompleterTarget -CommandName $commandNameItem -Native
            }

            break
        }

        'CommandParameter'
        {
            $commandCount = $CommandName.Count
            $parameterCount = $ParameterName.Count

            if ($commandCount -ne $parameterCount -and $commandCount -ne 1 -and $parameterCount -ne 1)
            {
                throw 'CommandName and ParameterName arrays must have matching lengths, or one side must provide a single value to broadcast.'
            }

            $iterationCount = [Math]::Max($commandCount, $parameterCount)

            for ($index = 0; $index -lt $iterationCount; $index++)
            {
                $resolvedCommandName = if ($commandCount -eq 1) { $CommandName[0] } else { $CommandName[$index] }
                $resolvedParameterName = if ($parameterCount -eq 1) { $ParameterName[0] } else { $ParameterName[$index] }

                Resolve-CompleterTarget -CommandName $resolvedCommandName -ParameterName $resolvedParameterName
            }

            break
        }
    }
}
<#
.SYNOPSIS
Sets a value in a runtime completer dictionary by key.
#>
function Set-CompleterRuntimeDictionaryValue
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        ([System.Collections.IDictionary] $Dictionary)[$Key] = $Value
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    $Dictionary[$Key] = $Value

    return $Dictionary[$Key]
}
<#
.SYNOPSIS
Determines whether a custom completer dictionary key is a parameter-only registration.

.DESCRIPTION
Register-ArgumentCompleter accepts -ParameterName without -CommandName and then
stores the completer in the custom completer dictionary under the parameter
name alone, so that dictionary holds two key shapes: 'Command:Parameter' for a
command-parameter completer and a bare parameter name for a completer that
applies to every command with that parameter. This module manages
command-parameter and native targets only, so discovery and the registration
snapshot use this rule to leave the parameter-only entries alone instead of
parsing them as 'Command:Parameter' keys and failing. The rule is the engine's
own key format, not an inference: a 'Command:Parameter' key always contains a
colon and a parameter name never does.

.PARAMETER Key
The key as stored in the custom completer dictionary.

.OUTPUTS
System.Boolean
Returns $true when the key names a parameter-only registration.

.EXAMPLE
Test-CompleterParameterOnlyKey -Key 'Get-Item:Path'

Returns $false because the key is a command-parameter key.

.EXAMPLE
Test-CompleterParameterOnlyKey -Key 'ComputerName'

Returns $true because the key came from Register-ArgumentCompleter
-ParameterName ComputerName without a command name.
#>
function Test-CompleterParameterOnlyKey
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    return $Key.IndexOf(':') -lt 0
}
<#
.SYNOPSIS
Tests whether a runtime completer dictionary contains a key.
#>
function Test-CompleterRuntimeDictionaryKey
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary).Contains($Key)
    }

    return $Dictionary.ContainsKey($Key)
}
<#
.SYNOPSIS
Validates that a completer script uses a supported import shape.

.DESCRIPTION
Checks the script AST for patterns that Import-CompleterScript can safely and
predictably import. Supported scripts must be self-contained, must call
Register-ArgumentCompleter at script scope, and must use literal values for the
registration target and script block. Every unsupported construct is reported
as a CompleterActions.CompleterScriptFinding record; a conforming script
produces no output.

.PARAMETER Ast
The parsed script AST to validate.

.PARAMETER LiteralPath
The source path recorded on each finding.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Test-CompleterScriptAst
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    $scriptScopeHint = 'Script scope may only contain Set-StrictMode, Get-Variable, Register-ArgumentCompleter, function definitions, and guarded if statements. Move this into a function that the completer calls lazily.'

    function Add-Finding
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.IScriptExtent] $Extent,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Construct,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Hint
        )

        $findings.Add((New-CompleterScriptFinding -Path $LiteralPath -Extent $Extent -Construct $Construct -Message $Message -Hint $Hint))
    }

    function Get-ImportSafeExpressionHint
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.ExpressionAst] $ExpressionAst
        )

        if ($ExpressionAst -is [System.Management.Automation.Language.ConvertExpressionAst])
        {
            return "A type cast runs at import time. Move the $($ExpressionAst.Type.Extent.Text) literal into a lazy initializer inside a function."
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.MemberExpressionAst])
        {
            return 'A [type]::Member or object member access runs at import time. Move it into a lazy initializer inside a function.'
        }

        return 'Keep script-scope values literal (strings, numbers, arrays, and hashtables) and compute everything else lazily inside a function.'
    }

    function Get-UnqualifiedFunctionName
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        return $Name.Substring($Name.LastIndexOfAny([char[]] @(':', '\')) + 1)
    }

    function Test-IsSupportedRegisterArgumentAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.Ast] $ArgumentAst,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ParameterName
        )

        function Get-LiteralArrayExpressionElement
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [System.Management.Automation.Language.ArrayExpressionAst] $ExpressionAst
            )

            $statementBlockAst = $ExpressionAst.SubExpression
            if ($statementBlockAst.Traps.Count -ne 0 -or $statementBlockAst.Statements.Count -ne 1)
            {
                return $null
            }

            $pipelineAst = $statementBlockAst.Statements[0]
            if ($pipelineAst -isnot [System.Management.Automation.Language.PipelineAst] -or $pipelineAst.PipelineElements.Count -ne 1)
            {
                return $null
            }

            $commandExpressionAst = $pipelineAst.PipelineElements[0]
            if ($commandExpressionAst -isnot [System.Management.Automation.Language.CommandExpressionAst])
            {
                return $null
            }

            if ($commandExpressionAst.Expression -is [System.Management.Automation.Language.ArrayLiteralAst])
            {
                return @($commandExpressionAst.Expression.Elements)
            }

            return @($commandExpressionAst.Expression)
        }

        if ($ParameterName -eq 'ScriptBlock')
        {
            if ($ArgumentAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                Add-Finding -Extent $ArgumentAst.Extent -Construct $ArgumentAst.GetType().Name -Message 'The script must provide a literal script block for -ScriptBlock.' -Hint 'Pass the completer body as a literal { ... } script block and move any shared code into functions that the script block calls.'
            }

            return
        }

        if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
        {
            return
        }

        $elements = $null
        if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            $elements = @($ArgumentAst.Elements)
        }
        elseif ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            $elements = Get-LiteralArrayExpressionElement -ExpressionAst $ArgumentAst
        }

        if ($null -ne $elements -and @($elements | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] }).Count -eq 0)
        {
            return
        }

        Add-Finding -Extent $ArgumentAst.Extent -Construct $ArgumentAst.GetType().Name -Message "The script must use literal string values for -$ParameterName." -Hint "Replace the -$ParameterName value with a literal string or a literal @('name', 'name.exe') array; a value computed at import time cannot be analyzed."
    }

    $allowedImportCommands = @(
        'Get-Variable',
        'Register-ArgumentCompleter',
        'Set-StrictMode'
    )

    $allowedTopLevelOperators = @(
        [System.Management.Automation.Language.TokenKind]::And,
        [System.Management.Automation.Language.TokenKind]::Or,
        [System.Management.Automation.Language.TokenKind]::Xor,
        [System.Management.Automation.Language.TokenKind]::Ieq,
        [System.Management.Automation.Language.TokenKind]::Ine,
        [System.Management.Automation.Language.TokenKind]::Ige,
        [System.Management.Automation.Language.TokenKind]::Igt,
        [System.Management.Automation.Language.TokenKind]::Ilt,
        [System.Management.Automation.Language.TokenKind]::Ile,
        [System.Management.Automation.Language.TokenKind]::Ilike,
        [System.Management.Automation.Language.TokenKind]::Inotlike,
        [System.Management.Automation.Language.TokenKind]::Imatch,
        [System.Management.Automation.Language.TokenKind]::Inotmatch,
        [System.Management.Automation.Language.TokenKind]::Icontains,
        [System.Management.Automation.Language.TokenKind]::Inotcontains,
        [System.Management.Automation.Language.TokenKind]::Iin,
        [System.Management.Automation.Language.TokenKind]::Inotin,
        [System.Management.Automation.Language.TokenKind]::Ceq,
        [System.Management.Automation.Language.TokenKind]::Cne,
        [System.Management.Automation.Language.TokenKind]::Cge,
        [System.Management.Automation.Language.TokenKind]::Cgt,
        [System.Management.Automation.Language.TokenKind]::Clt,
        [System.Management.Automation.Language.TokenKind]::Cle,
        [System.Management.Automation.Language.TokenKind]::Clike,
        [System.Management.Automation.Language.TokenKind]::Cnotlike,
        [System.Management.Automation.Language.TokenKind]::Cmatch,
        [System.Management.Automation.Language.TokenKind]::Cnotmatch,
        [System.Management.Automation.Language.TokenKind]::Ccontains,
        [System.Management.Automation.Language.TokenKind]::Cnotcontains,
        [System.Management.Automation.Language.TokenKind]::Cin,
        [System.Management.Automation.Language.TokenKind]::Cnotin
    )

    # The nested validators below define the closed top-level grammar. Everything
    # outside function bodies and literal -ScriptBlock arguments must be reachable
    # through them, so anything they do not recognize is reported before the
    # script is executed.
    function Test-ImportSafeExpressionAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.ExpressionAst] $ExpressionAst
        )

        if ($ExpressionAst -is [System.Management.Automation.Language.ConstantExpressionAst])
        {
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.VariableExpressionAst])
        {
            if ($ExpressionAst.Splatted)
            {
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'VariableExpressionAst' -Message 'The script uses argument splatting at script scope.' -Hint 'Spell out each parameter explicitly; Import-CompleterScript requires explicit top-level command arguments.'
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
        {
            foreach ($nestedExpression in $ExpressionAst.NestedExpressions)
            {
                if ($nestedExpression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $nestedExpression.Splatted)
                {
                    Add-Finding -Extent $nestedExpression.Extent -Construct $nestedExpression.GetType().Name -Message "The script contains unsupported top-level expression '$($nestedExpression.GetType().Name)' inside an expandable string." -Hint 'Use only plain variables inside script-scope strings, or build the string lazily inside a function.'
                }
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            foreach ($element in $ExpressionAst.Elements)
            {
                Test-ImportSafeExpressionAst -ExpressionAst $element
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            if ($ExpressionAst.SubExpression.Traps.Count -ne 0)
            {
                Add-Finding -Extent $ExpressionAst.SubExpression.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
            }

            foreach ($statement in $ExpressionAst.SubExpression.Statements)
            {
                Test-ImportSafeValueStatementAst -StatementAst $statement
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.HashtableAst])
        {
            foreach ($keyValuePair in $ExpressionAst.KeyValuePairs)
            {
                Test-ImportSafeExpressionAst -ExpressionAst $keyValuePair.Item1
                Test-ImportSafeValueStatementAst -StatementAst $keyValuePair.Item2
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ParenExpressionAst])
        {
            Test-ImportSafeValueStatementAst -StatementAst $ExpressionAst.Pipeline
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.UnaryExpressionAst])
        {
            if ($ExpressionAst.TokenKind -notin [System.Management.Automation.Language.TokenKind]::Not, [System.Management.Automation.Language.TokenKind]::Exclaim)
            {
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'UnaryExpressionAst' -Message "The script uses unsupported top-level operator '$($ExpressionAst.TokenKind)'." -Hint 'Only -not and ! are supported at script scope; compute other values lazily inside a function.'
                return
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Child
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.BinaryExpressionAst])
        {
            if ($ExpressionAst.Operator -notin $allowedTopLevelOperators)
            {
                Add-Finding -Extent $ExpressionAst.Extent -Construct 'BinaryExpressionAst' -Message "The script uses unsupported top-level operator '$($ExpressionAst.Operator)'." -Hint 'Only comparison and logical operators are supported at script scope; compute other values lazily inside a function.'
                return
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Left
            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Right
            return
        }

        Add-Finding -Extent $ExpressionAst.Extent -Construct $ExpressionAst.GetType().Name -Message "The script contains unsupported top-level expression '$($ExpressionAst.GetType().Name)'." -Hint (Get-ImportSafeExpressionHint -ExpressionAst $ExpressionAst)
    }

    function Test-ImportSafeCommandExpressionAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandExpressionAst] $CommandExpressionAst
        )

        if ($CommandExpressionAst.Redirections.Count -ne 0)
        {
            Add-Finding -Extent $CommandExpressionAst.Redirections[0].Extent -Construct $CommandExpressionAst.Redirections[0].GetType().Name -Message 'The script uses redirection at script scope.' -Hint 'Remove the redirection, or move the expression into a function that the completer calls lazily.'
            return
        }

        Test-ImportSafeExpressionAst -ExpressionAst $CommandExpressionAst.Expression
    }

    function Test-ImportSafeCommandAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandAst] $CommandAst
        )

        if ($CommandAst.Redirections.Count -ne 0)
        {
            Add-Finding -Extent $CommandAst.Redirections[0].Extent -Construct $CommandAst.Redirections[0].GetType().Name -Message 'The script uses redirection at script scope.' -Hint 'Remove the redirection, or move the command into a function that the completer calls lazily.'
            return
        }

        $commandName = $CommandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script uses a non-literal top-level command.' -Hint 'Call commands by their literal name at script scope, or move the call into a function that the completer calls lazily.'
            return
        }

        if ($allowedImportCommands -notcontains $commandName)
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message "The script uses unsupported top-level command '$commandName'." -Hint "Only Set-StrictMode, Get-Variable, and Register-ArgumentCompleter may run at script scope. Move '$commandName' into a function that the completer calls lazily."
            return
        }

        if ($commandName -eq 'Register-ArgumentCompleter')
        {
            # Register-ArgumentCompleter arguments are validated separately below.
            return
        }

        foreach ($commandElement in ($CommandAst.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($null -ne $commandElement.Argument)
                {
                    Test-ImportSafeExpressionAst -ExpressionAst $commandElement.Argument
                }

                continue
            }

            Test-ImportSafeExpressionAst -ExpressionAst $commandElement
        }
    }

    function Test-ImportSafePipelineAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.PipelineAst] $PipelineAst,

            [Parameter()]
            [switch] $AllowExpression
        )

        if ($PipelineAst.Background)
        {
            Add-Finding -Extent $PipelineAst.Extent -Construct 'PipelineAst' -Message 'The script starts a background pipeline at script scope.' -Hint 'Remove the & background operator; Import-CompleterScript does not support background execution.'
            return
        }

        foreach ($pipelineElement in $PipelineAst.PipelineElements)
        {
            if ($pipelineElement -is [System.Management.Automation.Language.CommandAst])
            {
                Test-ImportSafeCommandAst -CommandAst $pipelineElement
                continue
            }

            if ($pipelineElement -is [System.Management.Automation.Language.CommandExpressionAst])
            {
                if ($AllowExpression)
                {
                    Test-ImportSafeCommandExpressionAst -CommandExpressionAst $pipelineElement
                    continue
                }

                Add-Finding -Extent $pipelineElement.Extent -Construct $pipelineElement.Expression.GetType().Name -Message "The script contains unsupported top-level expression '$($pipelineElement.Expression.GetType().Name)'." -Hint (Get-ImportSafeExpressionHint -ExpressionAst $pipelineElement.Expression)
                continue
            }

            Add-Finding -Extent $pipelineElement.Extent -Construct $pipelineElement.GetType().Name -Message "The script contains unsupported top-level syntax '$($pipelineElement.GetType().Name)'." -Hint $scriptScopeHint
        }
    }

    function Test-ImportSafeValueStatementAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementAst] $StatementAst
        )

        if ($StatementAst -is [System.Management.Automation.Language.PipelineAst])
        {
            Test-ImportSafePipelineAst -PipelineAst $StatementAst -AllowExpression
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.CommandExpressionAst])
        {
            Test-ImportSafeCommandExpressionAst -CommandExpressionAst $StatementAst
            return
        }

        Add-Finding -Extent $StatementAst.Extent -Construct $StatementAst.GetType().Name -Message "The script contains unsupported top-level syntax '$($StatementAst.GetType().Name)'." -Hint $scriptScopeHint
    }

    function Test-ImportSafeStatementAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementAst] $StatementAst,

            [Parameter()]
            [switch] $AllowAssignment
        )

        if ($StatementAst -is [System.Management.Automation.Language.FunctionDefinitionAst])
        {
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.IfStatementAst])
        {
            foreach ($clause in $StatementAst.Clauses)
            {
                if ($clause.Item1 -isnot [System.Management.Automation.Language.PipelineAst])
                {
                    Add-Finding -Extent $clause.Item1.Extent -Construct $clause.Item1.GetType().Name -Message "The script contains unsupported top-level syntax '$($clause.Item1.GetType().Name)'." -Hint $scriptScopeHint
                    continue
                }

                Test-ImportSafePipelineAst -PipelineAst $clause.Item1 -AllowExpression
                Test-ImportSafeStatementBlockAst -StatementBlockAst $clause.Item2
            }

            if ($null -ne $StatementAst.ElseClause)
            {
                Test-ImportSafeStatementBlockAst -StatementBlockAst $StatementAst.ElseClause
            }

            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.PipelineAst])
        {
            Test-ImportSafePipelineAst -PipelineAst $StatementAst
            return
        }

        if ($StatementAst -is [System.Management.Automation.Language.AssignmentStatementAst])
        {
            if (-not $AllowAssignment)
            {
                Add-Finding -Extent $StatementAst.Extent -Construct 'AssignmentStatementAst' -Message 'The script uses a top-level assignment.' -Hint 'Guard script-scope state with if (-not (Get-Variable -Name State -Scope Script -ErrorAction SilentlyContinue)) { $script:State = @{ ... } }, or initialize it lazily inside a function.'
                return
            }

            if ($StatementAst.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals)
            {
                Add-Finding -Extent $StatementAst.Extent -Construct 'AssignmentStatementAst' -Message "The script uses unsupported top-level operator '$($StatementAst.Operator)'." -Hint 'Use plain = assignment for script-scope state.'
                return
            }

            $target = $StatementAst.Left
            if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $target.Splatted -or
                -not ($target.VariablePath.IsUnqualified -or $target.VariablePath.IsScript))
            {
                Add-Finding -Extent $target.Extent -Construct $target.GetType().Name -Message "The script assigns to unsupported target '$($target.Extent.Text)'." -Hint 'Assign only to unqualified or $script: variables at script scope; drive-qualified and member targets change state outside the script at import time.'
                return
            }

            Test-ImportSafeValueStatementAst -StatementAst $StatementAst.Right
            return
        }

        Add-Finding -Extent $StatementAst.Extent -Construct $StatementAst.GetType().Name -Message "The script contains unsupported top-level syntax '$($StatementAst.GetType().Name)'." -Hint $scriptScopeHint
    }

    function Test-ImportSafeStatementBlockAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.StatementBlockAst] $StatementBlockAst
        )

        if ($StatementBlockAst.Traps.Count -ne 0)
        {
            Add-Finding -Extent $StatementBlockAst.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
        }

        foreach ($statement in $StatementBlockAst.Statements)
        {
            Test-ImportSafeStatementAst -StatementAst $statement -AllowAssignment
        }
    }

    function Test-RegisterArgumentCompleterCommandAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.CommandAst] $CommandAst
        )

        $ancestor = $CommandAst.Parent
        while ($null -ne $ancestor -and $ancestor -ne $Ast)
        {
            if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script registers a completer from inside a nested function or script block.' -Hint 'Move the Register-ArgumentCompleter call to script scope; Import-CompleterScript only captures script-scope registrations.'
                return
            }

            $ancestor = $ancestor.Parent
        }

        $currentParameter = $null
        $seenParameters = [ordered] @{}

        foreach ($commandElement in ($CommandAst.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -notin 'CommandName', 'ParameterName', 'Native', 'ScriptBlock')
                {
                    Add-Finding -Extent $commandElement.Extent -Construct 'CommandParameterAst' -Message "The script uses unsupported Register-ArgumentCompleter parameter '-$($commandElement.ParameterName)'." -Hint 'Use only -CommandName, -ParameterName, -Native, and -ScriptBlock.'
                    return
                }

                if ($null -ne $commandElement.Argument)
                {
                    if ($commandElement.ParameterName -eq 'Native')
                    {
                        Add-Finding -Extent $commandElement.Extent -Construct 'CommandParameterAst' -Message 'The script uses an argument for -Native.' -Hint 'Use the bare -Native switch.'
                        return
                    }

                    Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement.Argument -ParameterName $commandElement.ParameterName
                    $currentParameter = $null
                }
                elseif ($commandElement.ParameterName -eq 'Native')
                {
                    $currentParameter = $null
                }
                else
                {
                    $currentParameter = $commandElement.ParameterName
                }

                $seenParameters[$commandElement.ParameterName] = $true
                continue
            }

            if ($commandElement -is [System.Management.Automation.Language.VariableExpressionAst] -and $commandElement.Splatted)
            {
                Add-Finding -Extent $commandElement.Extent -Construct 'VariableExpressionAst' -Message 'The script uses argument splatting for Register-ArgumentCompleter.' -Hint 'Spell out -CommandName, -ParameterName or -Native, and -ScriptBlock explicitly.'
                return
            }

            if ([string]::IsNullOrWhiteSpace($currentParameter))
            {
                Add-Finding -Extent $commandElement.Extent -Construct $commandElement.GetType().Name -Message 'The script uses positional Register-ArgumentCompleter arguments.' -Hint 'Name every argument: -CommandName, -ParameterName or -Native, and -ScriptBlock.'
                return
            }

            Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement -ParameterName $currentParameter
            $currentParameter = $null
        }

        if (-not [string]::IsNullOrWhiteSpace($currentParameter))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message "The script is missing the argument for -$currentParameter." -Hint "Supply a literal value after -$currentParameter."
            return
        }

        if (-not $seenParameters.Contains('CommandName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script is missing -CommandName in a Register-ArgumentCompleter call.' -Hint 'Add -CommandName with a literal command name or a literal array of command names.'
        }

        if (-not $seenParameters.Contains('ScriptBlock'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script is missing -ScriptBlock in a Register-ArgumentCompleter call.' -Hint 'Add -ScriptBlock with a literal { ... } script block.'
        }

        if ($seenParameters.Contains('Native') -and $seenParameters.Contains('ParameterName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script combines -Native and -ParameterName.' -Hint 'Use -Native for a native command completer or -ParameterName for a command parameter completer, not both.'
        }

        if (-not $seenParameters.Contains('Native') -and -not $seenParameters.Contains('ParameterName'))
        {
            Add-Finding -Extent $CommandAst.Extent -Construct 'CommandAst' -Message 'The script does not identify whether the completer is native or parameter-based.' -Hint 'Add -Native for a native command completer or -ParameterName for a command parameter completer.'
        }
    }

    foreach ($usingStatement in @($Ast.UsingStatements))
    {
        if ($usingStatement.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Namespace)
        {
            Add-Finding -Extent $usingStatement.Extent -Construct 'UsingStatementAst' -Message "The script uses a 'using $($usingStatement.UsingStatementKind.ToString().ToLowerInvariant())' statement." -Hint 'Remove the using statement; only using namespace is supported. Load the module or assembly lazily inside a function with Import-Module or Add-Type.'
        }
    }

    if ($null -ne $Ast.ScriptRequirements)
    {
        if ($Ast.ScriptRequirements.RequiredModules.Count -gt 0)
        {
            Add-Finding -Extent $Ast.Extent -Construct 'ScriptRequirements' -Message "The script uses a '#requires -Modules' directive." -Hint 'Remove the directive; the required modules are imported, and their top-level code executes, when the script is dot-sourced. Import the module lazily inside a function instead.'
        }

        if ($Ast.ScriptRequirements.RequiredAssemblies.Count -gt 0)
        {
            Add-Finding -Extent $Ast.Extent -Construct 'ScriptRequirements' -Message "The script uses a '#requires -Assembly' directive." -Hint 'Remove the directive; the required assemblies are loaded when the script is dot-sourced. Load the assembly lazily inside a function with Add-Type instead.'
        }
    }

    foreach ($namedBlock in @($Ast.ParamBlock, $Ast.BeginBlock, $Ast.ProcessBlock, $Ast.DynamicParamBlock, $Ast.CleanBlock))
    {
        if ($null -ne $namedBlock)
        {
            Add-Finding -Extent $namedBlock.Extent -Construct $namedBlock.GetType().Name -Message "The script contains unsupported top-level syntax '$($namedBlock.GetType().Name)'." -Hint 'Remove the param, begin, process, dynamicparam, or clean block; a completer script is a flat script that defines functions and registers completers.'
        }
    }

    if ($Ast.EndBlock.Traps.Count -ne 0)
    {
        Add-Finding -Extent $Ast.EndBlock.Traps[0].Extent -Construct 'TrapStatementAst' -Message "The script contains unsupported top-level syntax 'TrapStatementAst'." -Hint 'Move trap statements into function bodies.'
    }

    foreach ($statement in @($Ast.EndBlock.Statements))
    {
        Test-ImportSafeStatementAst -StatementAst $statement
    }

    # A function definition keeps its scope qualifier in FunctionDefinitionAst.Name,
    # so 'function script:Get-Variable' shadows Get-Variable in the capture scope
    # while its Name is not 'Get-Variable'. Definitions are therefore compared by
    # their unqualified name: the text after the last scope or module qualifier.
    # Command calls are deliberately not normalized the same way, because a
    # qualified call such as 'script:Get-Variable' or 'Foo\Get-Variable' is not the
    # allowlisted built-in and the exact-match allowlist above already rejects it.
    $functionOverrides = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                (Get-UnqualifiedFunctionName -Name $node.Name) -in $allowedImportCommands
            },
            $true
        ))

    foreach ($functionOverride in $functionOverrides)
    {
        $unqualifiedName = Get-UnqualifiedFunctionName -Name $functionOverride.Name
        Add-Finding -Extent $functionOverride.Extent -Construct 'FunctionDefinitionAst' -Message "The script defines its own $($functionOverride.Name) function." -Hint "Rename the function; Import-CompleterScript only supports scripts that call the built-in $unqualifiedName directly, and a scope-qualified definition such as script:$unqualifiedName or global:$unqualifiedName shadows it in the same way."
    }

    $dotSourcedCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            },
            $true
        ))

    foreach ($dotSourcedCommand in $dotSourcedCommands)
    {
        Add-Finding -Extent $dotSourcedCommand.Extent -Construct 'CommandAst' -Message 'The script dot-sources another script.' -Hint 'Inline the dot-sourced content, or move the dot-source into a function that the completer calls lazily; Import-CompleterScript only supports self-contained completer scripts.'
    }

    $registerCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $true
        ))

    if ($registerCommands.Count -eq 0)
    {
        Add-Finding -Extent $Ast.Extent -Construct 'ScriptBlockAst' -Message 'The script does not contain a Register-ArgumentCompleter call.' -Hint 'Add a script-scope Register-ArgumentCompleter call with -CommandName, -ScriptBlock, and either -Native or -ParameterName.'
    }

    foreach ($registerCommand in $registerCommands)
    {
        Test-RegisterArgumentCompleterCommandAst -CommandAst $registerCommand
    }

    return $findings.ToArray()
}
<#
.SYNOPSIS
Warns once per process that a legacy command name is deprecated.

.DESCRIPTION
Emits a single Write-Warning per process for a legacy command name, naming
the replacement command and the about_CompleterActions_Migration topic. The
names that have already warned are tracked in the module-scope set created by
Bootstrap.ps1, so a profile that calls a legacy name many times sees the
warning once.

.PARAMETER LegacyName
The deprecated command name the caller used.

.PARAMETER NewName
The command that replaces it.

.EXAMPLE
PS> Write-CompleterDeprecationWarning -LegacyName 'Get-CompleterRegistration' -NewName 'Get-Completer'
#>
function Write-CompleterDeprecationWarning
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LegacyName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $NewName
    )

    if ($script:CompleterDeprecationWarningsIssued.Add($LegacyName))
    {
        Write-Warning -Message "$LegacyName is deprecated and will be removed in 3.0; use $NewName instead. See about_CompleterActions_Migration."
    }
}
# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new()
$script:CompleterDeprecationWarningsIssued = [System.Collections.Generic.HashSet[string]]::new()
New-Alias -Name 'Get-CompleterRegistration' -Value 'Get-CompleterRegistrationLegacy'
New-Alias -Name 'Register-CompleterRegistration' -Value 'Register-CompleterRegistrationLegacy'
New-Alias -Name 'Unregister-CompleterRegistration' -Value 'Unregister-CompleterRegistrationLegacy'
