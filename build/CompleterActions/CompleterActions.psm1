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
-CommandName selected a subset. A strict entry's targets are written in the
order the script registers them, with the script's casing. Trusted entries are
written with the targets the records carry, in record order, so a subset of a
trusted script's targets exports and imports as given.

Every entry also records a Hash of its script: 'SHA256:' followed by the
SHA-256 of the script's text with CR LF and lone CR line endings normalised to
LF, so the same script hashes to the same value on a Windows and a Linux
checkout. The hash is a cache key for the entry's targets, not a signature, and
readers that do not know the key ignore it. A strict script is read once for
both its targets and its hash. When a trusted script cannot be read, its entry
is written without a Hash, a warning names the script, and the export still
succeeds.

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
                $records.AddRange([psobject[]] @(Get-Completer -State Active, Pending, Failed, Stale | Where-Object { $_.PSObject.Properties['ScriptPath'] -and -not [string]::IsNullOrWhiteSpace([string] $_.ScriptPath) }))
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
                        Hash    = $null
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

                # One read serves both the target check and the Hash, so an edit
                # between two reads cannot give a Hash that does not describe the
                # checked targets.
                $parseResult = Get-CompleterScriptParseResult -LiteralPath $entry.Path
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $entry.Path -ParseResult $parseResult)
                $derivedKeys = @($derivedTargets | ForEach-Object { [string] $_.Key })
                $missingTargets = @($derivedKeys | Where-Object { -not $entry.Targets.Contains($_) })
                $unknownTargets = @($entry.Targets.Keys | Where-Object { $_ -notin $derivedKeys })

                if ($missingTargets.Count -eq 0 -and $unknownTargets.Count -eq 0)
                {
                    # The keys match, so only order and casing can differ. Writing the
                    # derived targets puts them in script order and script casing,
                    # which is what the import fast path reproduces.
                    $entry.Targets = [ordered] @{}

                    foreach ($derivedTarget in $derivedTargets)
                    {
                        $entry.Targets[[string] $derivedTarget.Key] = $derivedTarget
                    }

                    $entry.Hash = Get-CompleterScriptHash -Text $parseResult.Ast.Extent.Text
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
                # A trusted script is never parsed here, and 2.0.0 exported a trusted
                # entry whose file is missing, so an unreadable trusted script is
                # written without a Hash rather than failing the export.
                if ($entry.Trusted)
                {
                    try
                    {
                        $entry.Hash = Get-CompleterScriptHash -LiteralPath $entry.Path
                    }
                    catch
                    {
                        Write-Warning -Message "The script '$($entry.Path)' could not be read, so its entry was written without a Hash. $($_.Exception.GetBaseException().Message)"
                    }
                }

                $relativePath = [System.IO.Path]::GetRelativePath($outputDirectory, $entry.Path)
                $writtenPath = if ([System.IO.Path]::IsPathRooted($relativePath)) { $entry.Path } else { $relativePath.Replace('\', '/') }

                $lines.Add('        @{')
                $lines.Add("            Path    = '$($writtenPath.Replace("'", "''"))'")
                $lines.Add("            Trusted = `$$($entry.Trusted.ToString().ToLowerInvariant())")

                if ($null -ne $entry.Hash)
                {
                    $lines.Add("            Hash    = '$($entry.Hash)'")
                }

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
The command merges module-managed registrations with runtime-discovered
registrations and reports each record's State once, so -State can select any
subset. A managed record whose stored script is the live runtime value is
'Active', or 'Pending' while a lazy registration still waits for its first tab
press. A runtime value that no managed record describes is 'Discovered'. When
the runtime registration was replaced outside this module, the managed record
is returned with State 'Stale' and the live value with State 'Conflicted';
when it was removed outside this module, the managed record is 'Stale' with
IsRuntimeRegistered false. A lazy registration whose script failed to load is
'Failed'; it has no runtime entry and carries the error in LoadError. Without
-State every record is returned. Records are sorted by CompleterType, then
CommandName, then ParameterName before -Skip and -First are applied, so paging
across several calls stays stable while unrelated targets change; only a
target that sorts before the current window can shift it. The command accepts
arrays for command and parameter lookups, and records piped back from
Get-Completer or Import-CompleterScript resolve through their Key and IsNative
properties. Keys are output-only identifiers: a hand-typed key string is not
accepted, so name the target with -CommandName plus -Native or -ParameterName
instead.

Discovery covers the two target kinds this module manages: command-parameter
completers and native command completers. A completer registered with
Register-ArgumentCompleter -ParameterName alone, without -CommandName, applies
to every command with that parameter and is stored under the bare parameter
name; such registrations are not returned and are reported with -Verbose as
they are skipped, so they never prevent the supported registrations from being
listed.

.PARAMETER InputObject
Supplies one or more objects that describe the registrations to get, such as
records returned by Get-Completer or Import-CompleterScript. Every piped
object binds here. An input object describes one target: it exposes
CommandName with IsNative/Native or ParameterName, or a Key, RegistrationKey,
or RuntimeKey together with IsNative/Native. To look up several targets at
once, pass arrays to -CommandName and -ParameterName instead.

.PARAMETER CommandName
Limits results to one or more command names for native or command-parameter
completers.

.PARAMETER ParameterName
Limits results to one or more parameter completer targets.

.PARAMETER Native
Indicates that the lookup target is a native command completer instead of a
command parameter completer.

.PARAMETER State
Returns only the records whose State is one of the given values: Active,
Stale, Conflicted, Pending, Failed, or Discovered. Several values return the
union.

.OUTPUTS
CompleterActions.CompleterRegistration
Returns CompleterActions.CompleterRegistration records. The State property is
'Active' for managed records that describe the live runtime value,
'Discovered' for runtime values that no managed record describes, 'Pending'
for lazy registrations whose script has not loaded yet, 'Failed' for lazy
registrations whose script failed to load, 'Stale' for managed records that no
longer match the runtime, and 'Conflicted' for live runtime values that
replaced a managed registration outside this module. ScriptPath names the
completer script behind a lazy or imported registration and LoadError holds
the failure message of a Failed record.

.EXAMPLE
PS> Get-Completer -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-Completer -CommandName 'git' -ParameterName 'checkout', 'branch'

Gets multiple command-parameter completer registrations in a single call.

.EXAMPLE
PS> Get-Completer -State Pending, Failed

Lists the lazy registrations that have not loaded yet and the ones whose script
failed to load, with the failure message in LoadError.

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
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [CompleterActions.CompleterState[]] $State
    )

    begin
    {
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

            if ($targets.Count -eq 0)
            {
                $managedRegistrations = @(Find-ManagedCompleterRegistration)
                $discoveredRegistrations = @(Find-RuntimeCompleterRegistration)
            }
            else
            {
                foreach ($target in $targets)
                {
                    $managedRegistrations += @(Find-ManagedCompleterRegistration -Key $target.Key)
                    $discoveredRegistrations += @(Find-RuntimeCompleterRegistration -Key $target.Key)
                }
            }

            $snapshot = Get-CompleterRegistrationSnapshot

            foreach ($registration in $managedRegistrations)
            {
                if ($null -eq $registration)
                {
                    continue
                }

                $registrationState = Resolve-CompleterRegistrationState -Key $registration.Key -Snapshot $snapshot

                if ($registrationState.ManagedState -in 'Active', 'Pending', 'Failed')
                {
                    $registrationsByKey["Managed:$($registration.Key)"] = $registration
                }
                else
                {
                    $registrationsByKey["Managed:$($registration.Key)"] = New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -ImportModule $registration.ImportModule -State 'Stale' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted
                }

                if ($registrationState.ManagedState -in 'Stale', 'Failed' -and $null -ne $registrationState.RuntimeRegistration)
                {
                    $registrationsByKey["Discovered:$($registration.Key)"] = New-CompleterRegistrationRecord -Target $registrationState.RuntimeRegistration -ScriptBlock $registrationState.RuntimeRegistration.ScriptBlock -Source 'Discovered' -State 'Conflicted'
                }
            }

            foreach ($registration in $discoveredRegistrations)
            {
                if ($null -eq $registration -or $registrationsByKey.Contains("Managed:$($registration.Key)"))
                {
                    continue
                }

                $registrationsByKey["Discovered:$($registration.Key)"] = $registration
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

        if ($PSBoundParameters.ContainsKey('State'))
        {
            $registrations = @($registrations | Where-Object { $State -contains $_.State })
        }

        $registrations = @($registrations | Sort-Object -Property 'CompleterType', 'CommandName', 'ParameterName' -Stable)
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
CompleterActions.ImportedCompleterRegistration
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
    [OutputType('CompleterActions.ImportedCompleterRegistration')]
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
once, unless its Hash matches, and walks none of them; run
Test-CompleterScript over the repository to find grammar findings ahead of
time. When one or more entries are invalid the command throws a single error
that lists every problem and registers nothing. With -SkipInvalid each
problem is written as a warning instead and the valid entries register.

A strict entry that declares Targets and carries a Hash, as
Export-CompleterSet writes it, is not parsed when the Hash matches the
script's text: its declared Targets are registered as they are, and the
parse errors, the literal-argument check, and the comparison with the
script's targets are skipped because the export ran them against the same
text. Every other check still runs. An absent, unrecognised, or different
Hash, or a script that cannot be read for it, falls back to the parse, and a
stale Hash is not a warning. A hand-edited entry whose Hash still matches
registers its targets in the order and with the casing it declares, keeping
the first occurrence of a repeated key, where the parse would use the
script's order and casing. A trusted entry's Hash is ignored. With -Verbose
the command writes one line per valid entry saying how its targets were
read, and one summary line per set.

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
set's targets and retries Failed ones; Reset-Completer retries them without
re-importing the set.

With -Name the set comes from an installed completer set package: a module
whose manifest names its set file in PrivateData.CompleterSet, as
'<folder>/<file>.psd1' in a folder directly below the module folder, which
holds the manifest as its only .psd1. The module is found the way
Import-Module finds it, without loading it: the first $env:PSModulePath root
that has the module wins, and within it the highest version, which is used
even when its set is broken. The manifest is read as data, so the package's
RootModule, ScriptsToProcess, NestedModules, and RequiredModules never load or
run. Every name is resolved before any set is imported, and the set is then
imported as -LiteralPath imports it, with two rules for packages. An entry
whose script resolves outside the module folder is an invalid entry. A set
with trusted entries writes one warning per name that counts them. Installing
a completer set package and importing it by name is a decision to run its
scripts: each one runs at its first tab, under its entry's trust tier.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER Name
The names of installed completer set modules. Each name is taken literally: a
name containing *, ?, [, or ] fails the call before any name is resolved. The
parameter takes no pipeline input.

.PARAMETER SkipInvalid
Writes each invalid entry as a warning and registers the valid entries instead
of failing the whole set.

.PARAMETER Force
Replaces existing managed or runtime registrations for the targets in the set,
including Failed lazy records whose load should be retried; Reset-Completer
retries them without re-importing the set.

.OUTPUTS
CompleterActions.CompleterRegistration
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

.EXAMPLE
PS> Import-CompleterSet -Name PS_Completers

Registers every completer script in the set of the installed PS_Completers
package. After Install-PSResource PS_Completers this is the one line a profile
needs, with no path.
#>
function Import-CompleterSet
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
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
                elseif ($PSCmdlet.ParameterSetName -eq 'Path')
                {
                    foreach ($pathItem in $Path)
                    {
                        Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath
                    }
                }
            )

            $sets = @(
                if ($PSCmdlet.ParameterSetName -eq 'Name')
                {
                    foreach ($nameItem in $Name)
                    {
                        if ($nameItem -match '[*?\[\]]')
                        {
                            throw "Import-CompleterSet -Name does not accept wildcards. Received '$nameItem'."
                        }
                    }

                    foreach ($nameItem in $Name)
                    {
                        $setModule = Resolve-CompleterSetModule -Name $nameItem
                        @{ SetPath = $setModule.SetPath; Module = $setModule }
                    }
                }
                else
                {
                    foreach ($resolvedPath in $resolvedPaths)
                    {
                        @{ SetPath = $resolvedPath; Module = $null }
                    }
                }
            )

            foreach ($set in $sets)
            {
                $setPath = $set.SetPath
                $setModule = $set.Module
                $moduleParameters = @{}

                if ($null -ne $setModule)
                {
                    Write-Verbose -Message "Completer set module '$($setModule.Name)' $($setModule.Version) at '$($setModule.ModuleBase)': '$setPath'."
                    $moduleParameters = @{ ModuleName = $setModule.Name; ModuleBase = $setModule.ModuleBase }
                }

                $setDefinition = Import-CompleterSetDefinition -LiteralPath $setPath

                if ($null -ne $setModule)
                {
                    $trustedEntryCount = @($setDefinition.Entries.Where({ $_ -is [System.Collections.IDictionary] -and $_.Contains('Trusted') -and $_['Trusted'] -is [bool] -and $_['Trusted'] })).Count

                    if ($trustedEntryCount -gt 0)
                    {
                        Write-Warning -Message "The completer set module '$($setModule.Name)' $($setModule.Version) declares $trustedEntryCount trusted completer scripts, which run without the strict grammar check at first tab."
                    }
                }

                $snapshot = Get-CompleterRegistrationSnapshot
                $entryIndex = 0
                $staticEntries = @(
                    foreach ($rawEntry in $setDefinition.Entries)
                    {
                        $entryIndex++
                        Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $setDefinition.Directory @moduleParameters
                    }
                )
                $entries = @(Resolve-CompleterSetRegistration -Entry $staticEntries -Snapshot $snapshot -Force:$Force)

                $invalidEntries = @($entries.Where({ -not $_.IsValid }))

                if ($invalidEntries.Count -gt 0)
                {
                    $problemLines = @(
                        foreach ($entry in $invalidEntries)
                        {
                            $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $($entry.Index)" } else { "Entry $($entry.Index) ('$($entry.DeclaredPath)')" }

                            foreach ($problem in $entry.Problems)
                            {
                                '{0}: {1}' -f $entryLabel, $problem.Message
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

                $validEntries = @($entries.Where({ $_.IsValid }))

                foreach ($entry in $validEntries)
                {
                    Write-Verbose -Message "Entry $($entry.Index) ('$($entry.DeclaredPath)'): $($entry.ResolutionNote)"
                }

                $hashCount = @($validEntries.Where({ $_.TargetSource -eq 'Hash' })).Count
                $parsedCount = @($validEntries.Where({ $_.TargetSource -eq 'Parsed' })).Count
                $trustedCount = @($validEntries.Where({ $_.TargetSource -eq 'Trusted' })).Count
                Write-Verbose -Message "Completer set '$setPath': $hashCount entries from the hash, $parsedCount parsed, $trustedCount trusted."

                $confirmedEntries = @(
                    foreach ($entry in $validEntries)
                    {
                        if ($PSCmdlet.ShouldProcess($entry.Path, 'Import completer set entry'))
                        {
                            $entry
                        }
                    }
                )

                $registrations = @(foreach ($entry in $confirmedEntries) { $entry.Registrations })
                $conflicts = @(foreach ($entry in $confirmedEntries) { $entry.Conflicts })

                Add-CompleterRegistration -Registration $registrations -Conflict $conflicts -Snapshot $snapshot
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
Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.

.DESCRIPTION
Writes a native completer script for one or more command names: a guarded,
literal-only table of subcommands, a Complete-<Stem> function that offers them
in the first argument position, and one bare Register-ArgumentCompleter call
that names every target. The file passes Test-CompleterScript and imports with
Import-CompleterScript and Register-Completer -Lazy before the author edits it.

The first -CommandName value is the primary name: it names the functions and
the state variable, and it is the one probed. Every name must be a bare command
name. The target list follows the -CommandName order, and a name that does not
end in .exe, .cmd, .bat, .ps1, or .com is followed by the same name with .exe
appended, so -CommandName rg registers 'rg' and 'rg.exe'.

The subcommand table is seeded in one of three ways. By default the command
runs the primary name's help and parses its commands section. -HelpText parses
help text the author already captured and runs nothing. -NoProbe runs nothing
and writes an empty table.

The probe runs only an application that Get-Command resolves; a function,
alias, cmdlet, or script of that name is never run. On Windows it runs only
a .exe whose PE header marks a console program, so GUI programs, shims such as
npm.cmd, and app execution aliases are refused with a warning. The program
runs with the help argument alone, standard input closed, the temporary
directory as its working directory, and NO_COLOR set, under a 5-second limit.
Without -HelpArgument the probe passes --help; on Windows, when --help ran to
completion, gave no subcommand, and printed fewer than five non-blank lines,
/? runs once and its result is used. A run that does not exit in time, or that
leaves a process holding its output, is stopped and its output is not used.
-WhatIf and -Confirm name the program before anything runs.

Before anything is resolved, probed, or written, every -CommandName value,
-HelpArgument, and the -Path are checked: a name must keep a letter or digit
outside a trailing .exe, .cmd, .bat, .ps1, or .com, -HelpArgument must not
contain a line break, the path must end in .ps1, must not be a directory, and
its folder must exist, and the file must not exist unless -Force is given. The
script is written to a temporary file beside the target, checked with the
strict grammar Test-CompleterScript applies, and moved into place only when it
conforms and registers exactly the target list; otherwise nothing is written.
The file is UTF-8 without a byte-order mark, with the platform newline and a
final newline.

Every failure is a terminating error that begins 'Failed to create completer
script.', and a failed call leaves nothing at the path.

.PARAMETER CommandName
The native command names. The first is the primary name: it names the
functions and state, and it is the one probed.

.PARAMETER Path
The .ps1 file to write. A relative path is resolved against the current
location. The parent directory must exist.

.PARAMETER HelpArgument
The one argument the probe passes. When omitted the probe passes --help and,
on Windows, may fall back to /?. It must not contain a line break, because
line 2 of the script names it in a comment.

.PARAMETER HelpText
Help text the author already captured. Lines are accumulated across pipeline
input, joined with LF, cleaned, and parsed; nothing is run.
winget --help | New-CompleterScript winget .\winget_completer.ps1 binds here.

.PARAMETER NoProbe
Runs nothing and writes an empty subcommand table.

.PARAMETER Force
Overwrites an existing file.

.PARAMETER PassThru
Returns the written file as System.IO.FileInfo, so it pipes into
Test-CompleterScript and Import-CompleterScript. Without -PassThru the
command returns nothing.

.INPUTS
System.String
Help text lines, bound to -HelpText.

.OUTPUTS
System.IO.FileInfo
When -PassThru is used, returns the written script file.

.EXAMPLE
PS> New-CompleterScript -CommandName cargo -Path .\cargo_completer\cargo_completer.ps1 -PassThru | Test-CompleterScript

Writes the cargo skeleton seeded from 'cargo --help' and checks it; the
pipeline is empty.

.EXAMPLE
PS> winget --help | New-CompleterScript -CommandName winget -Path .\winget_completer\winget_completer.ps1

Seeds the table from help the author ran, for a command the probe will not
run.

.EXAMPLE
PS> New-CompleterScript -CommandName mytool -Path .\mytool_completer.ps1 -NoProbe -Force

Writes an empty skeleton without running anything, replacing an existing file.
#>
function New-CompleterScript
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Probe', ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]] $CommandName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(ParameterSetName = 'Probe')]
        [string] $HelpArgument,

        [Parameter(Mandatory, ParameterSetName = 'HelpText', ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]] $HelpText,

        [Parameter(Mandatory, ParameterSetName = 'NoProbe')]
        [switch] $NoProbe,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        try
        {
            $targetNames = @(ConvertTo-CompleterTargetName -CommandName $CommandName)

            # Line 2 of the script names the argument in a comment, which a line break would end.
            if ($HelpArgument.IndexOfAny([char[]] "`r`n") -ge 0)
            {
                throw '-HelpArgument must not contain a line break.'
            }

            $outputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

            if ([System.IO.Path]::GetExtension($outputPath) -ne '.ps1')
            {
                throw "Completer scripts must be .ps1 files. Received '$outputPath'."
            }

            if (Test-Path -LiteralPath $outputPath -PathType Container)
            {
                throw "Completer scripts must be file paths. '$outputPath' is a directory."
            }

            $outputDirectory = Split-Path -Path $outputPath -Parent

            if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
            {
                throw "The directory '$outputDirectory' does not exist."
            }

            if (-not $Force -and (Test-Path -LiteralPath $outputPath))
            {
                throw "The file '$outputPath' already exists. Use -Force to overwrite it."
            }
        }
        catch
        {
            # ThrowTerminatingError, unlike throw, is not silenced by -ErrorAction
            # SilentlyContinue or Ignore, so a failed check never lets end write.
            $exception = [System.InvalidOperationException]::new("Failed to create completer script. $($_.Exception.Message)", $_.Exception)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($exception, 'NewCompleterScriptFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Path))
        }

        $helpLines = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'HelpText')
        {
            foreach ($helpLine in $HelpText)
            {
                $helpLines.Add($helpLine)
            }
        }
    }

    end
    {
        try
        {
            $primaryName = $CommandName[0]
            $application = $null
            $action = 'Create completer script without running a program'

            if ($PSCmdlet.ParameterSetName -eq 'Probe')
            {
                $application = Resolve-CompleterHelpProbeApplication -Name $primaryName

                if ($application.CanRun)
                {
                    Write-Verbose -Message "Resolved '$primaryName' to the application '$($application.Path)'."

                    if ($PSBoundParameters.ContainsKey('HelpArgument'))
                    {
                        $action = "Create completer script, running '$($application.Path) $HelpArgument' to read its help"
                    }
                    elseif ($IsWindows)
                    {
                        $action = "Create completer script, running '$($application.Path) --help' and, if it is rejected, '/?' to read its help"
                    }
                    else
                    {
                        $action = "Create completer script, running '$($application.Path) --help' to read its help"
                    }
                }
                else
                {
                    Write-Verbose -Message "The probe will not run '$primaryName'. $($application.Warning)"
                }
            }

            if (-not $PSCmdlet.ShouldProcess($outputPath, $action))
            {
                return
            }

            # The call was confirmed once; the write that follows must not ask again.
            $ConfirmPreference = 'None'

            $subcommands = @()
            $skeletonParameters = @{}

            switch ($PSCmdlet.ParameterSetName)
            {
                'Probe'
                {
                    $probeParameters = @{
                        Application    = $application
                        TimeoutSeconds = $script:CompleterHelpProbeTimeoutSeconds
                    }

                    if ($PSBoundParameters.ContainsKey('HelpArgument'))
                    {
                        $probeParameters['HelpArgument'] = $HelpArgument
                    }

                    $probe = Get-CompleterHelpSubcommand @probeParameters

                    foreach ($warning in $probe.Warnings)
                    {
                        Write-Warning -Message $warning
                    }

                    foreach ($verboseLine in $probe.VerboseLines)
                    {
                        Write-Verbose -Message $verboseLine
                    }

                    $subcommands = @($probe.Subcommands)

                    if ($subcommands.Count -gt 0)
                    {
                        $skeletonParameters['SeedKind'] = 'Probe'
                        $skeletonParameters['ProbeArgument'] = $probe.Argument
                    }
                }

                'HelpText'
                {
                    $subcommands = @(ConvertFrom-CompleterHelpText -Text (ConvertTo-CompleterCleanHelpText -Text ($helpLines -join "`n")))
                    $skeletonParameters['SeedKind'] = 'HelpText'
                }
            }

            $lines = Get-CompleterScriptSkeleton -Name $primaryName -Stem (ConvertTo-CompleterScriptStem -Name $primaryName) -Target $targetNames -Subcommand $subcommands @skeletonParameters

            $file = Save-CompleterScriptFile -Line $lines -LiteralPath $outputPath -ExpectedTarget $targetNames -Force:$Force -Verbose:$false

            Write-Verbose -Message "Wrote '$($file.FullName)': $($targetNames.Count) targets, $($subcommands.Count) subcommands."

            if ($PassThru)
            {
                $file
            }
        }
        catch
        {
            $exception = [System.InvalidOperationException]::new("Failed to create completer script. $($_.Exception.Message)", $_.Exception)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($exception, 'NewCompleterScriptFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Path))
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
executed at registration time. The strict grammar runs on that parse, so a
script that fails it is refused with one line per finding before anything is
registered, under -WhatIf too; it runs again when the script loads, and a
script that no longer conforms by then moves to 'Failed'. With -Trusted the
script is dot-sourced as-is on first use and cannot be parsed safely, so the
targets must be supplied with -CommandName and -Native or -ParameterName.

If the script fails to load on the first tab press, the press returns no
completions, the runtime entry is removed so the completion engine's default
completion applies exactly as with no completer registered, and the managed
record moves to State 'Failed' with the error message in LoadError. Nothing is
written to the host. Registering the same target again with -Force retries the
load, or use Reset-Completer. Lazy loading runs entirely inside the ordinary
completer call; it never hooks key handlers, replaces TabExpansion2, or changes
PSReadLine options.

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
Under the strict tier the script is checked against the grammar before any
stub is registered.

.PARAMETER Trusted
Imports the script through the trusted tier on first use, dot-sourcing it as-is
without the strict grammar. The targets must be supplied with -CommandName and
-Native or -ParameterName because a trusted script is not parsed. The default
is the strict tier, which validates the script against the grammar when it is
registered and again when it loads.

.PARAMETER Force
Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value was
changed outside this module and a Failed lazy record whose load should be
retried; Reset-Completer retries that load without registering it again.

.PARAMETER PassThru
Returns the managed registration records that were created or reused.

.OUTPUTS
CompleterActions.CompleterRegistration
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
PS> Get-Completer -State Failed | Reset-Completer

Retries every lazy registration whose script failed to load, after the scripts
have been fixed.
#>
function Register-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
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
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $scriptPath

                    if ($parseResult.ParseErrors.Count -eq 0)
                    {
                        Assert-CompleterScriptConformance -LiteralPath $scriptPath -ParseResult $parseResult
                    }

                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath -ParseResult $parseResult)

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
.SYNOPSIS
Returns a Failed or Active script-backed completer to Pending, so its script loads again on the next tab press.

.DESCRIPTION
Re-arms a script-backed managed registration without re-importing the set it
came from. A script-backed registration is any managed record with a
ScriptPath: a lazy registration from Import-CompleterSet or Register-Completer
-Lazy, or an eager one from Import-CompleterScript | Register-Completer. The
targets are named by native command, command parameter target, or pipeline
InputObject values, and each target is decided once per call; a key seen
earlier in the same call is skipped.

A Failed record gets a new lazy stub in the runtime and becomes Pending, with
LoadError cleared and ScriptPath and Trusted kept. An Active record has its
live script block replaced by the stub and becomes Pending, with ImportModule
cleared. A Pending record is left alone without a confirmation prompt, and
-PassThru returns it unchanged. The next tab press follows the ordinary lazy
path: it imports the script under the record's tier, swaps in every Pending
sibling of the same script and tier, and moves them to Active, or moves the
pressed target to Failed again with the new LoadError. Only the targets named
are reset, so an Active sibling keeps its loaded script block until it is
reset itself. The script is not parsed and its targets are not re-derived.

A target that cannot be reset is reported as a non-terminating error, and the
command goes on with the next target or piped record: a registration the
module does not manage, a target with nothing registered, a stale record, a
Failed record whose live runtime value was created outside this module, a
record registered from a script block rather than a script file, and a record
whose script file no longer exists. Use -ErrorAction Stop to stop at the first
error. Each target is its own transaction: if writing the stub or the record
fails, the previous runtime value and managed record are restored. The command
writes only the runtime completer dictionaries and the module's managed table;
it never hooks key handlers, replaces TabExpansion2, or changes PSReadLine
options. To remove a registration instead of reloading it, use
Unregister-Completer.

.PARAMETER InputObject
Supplies one or more objects that describe registrations to reset. Input
objects expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies one or more command names whose completers should be reset.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer reset
targets.

.PARAMETER Native
Targets native completer registrations instead of command parameter completers.

.PARAMETER PassThru
Returns the Pending record of each target that was reset, and the unchanged
record of each target that was already Pending.

.OUTPUTS
CompleterActions.CompleterRegistration
When -PassThru is used, returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Get-Completer -State Failed | Reset-Completer

Re-arms every failed script-backed registration after the scripts were fixed,
and reports each record that cannot be reset.

.EXAMPLE
PS> Reset-Completer -CommandName git, git.exe -Native -PassThru

Reloads the git completer on the next tab press after the script was edited,
and returns the two Pending records.

.EXAMPLE
PS> Get-Completer -State Active, Failed | Where-Object ScriptPath -eq $path | Reset-Completer

Resets every target of one script.
#>
function Reset-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
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
        [switch] $PassThru
    )

    begin
    {
        $decidedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # A plain function, not an advanced one, so the error is written by
        # Reset-Completer itself: it names Reset-Completer and sets $? to false.
        function Write-CompleterResetError
        {
            param(
                [string] $Message,
                [System.Exception] $Exception,
                [object] $TargetObject
            )

            $PSCmdlet.WriteError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($Message, $Exception),
                    'CompleterResetFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $TargetObject
                )
            )
        }
    }

    process
    {
        $resolvedTargets = [System.Collections.Generic.List[psobject]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'InputObject')
        {
            foreach ($inputItem in $InputObject)
            {
                try
                {
                    $resolvedTargets.Add((Resolve-CompleterInputObject -InputObject $inputItem).Target)
                }
                catch
                {
                    Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception -TargetObject $inputItem
                }
            }
        }
        else
        {
            $targetParameters = @{ CommandName = $CommandName }

            if ($PSCmdlet.ParameterSetName -eq 'Native')
            {
                $targetParameters['Native'] = $true
            }
            else
            {
                $targetParameters['ParameterName'] = $ParameterName
            }

            try
            {
                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedTargets.Add($target)
                }
            }
            catch
            {
                Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception
            }
        }

        foreach ($target in $resolvedTargets)
        {
            if (-not $decidedKeys.Add($target.Key))
            {
                continue
            }

            # Every row that cannot be reset sets a reason instead of throwing,
            # so -ErrorVariable collects exactly one error per target.
            $reason = $null
            $failure = $null

            try
            {
                $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                $managedRegistration = $registrationState.ManagedRegistration
                $runtimeRegistration = $registrationState.RuntimeRegistration
                $managedState = $registrationState.ManagedState
                $runtimeKey = if ($null -ne $managedRegistration) { $managedRegistration.RuntimeKey } else { $target.RuntimeKey }

                $reason = if ($null -eq $managedRegistration -and $null -ne $runtimeRegistration)
                {
                    "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed, so it cannot be reset."
                }
                elseif ($null -eq $managedRegistration)
                {
                    'No completer registration was found for the requested target.'
                }
                elseif ($managedState -eq 'Pending')
                {
                    $null
                }
                elseif ($managedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                {
                    "The module-managed completer registration for '$runtimeKey' is $($managedState.ToLowerInvariant()) and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it."
                }
                elseif ($managedState -eq 'Stale')
                {
                    "The module-managed completer registration for '$runtimeKey' is stale. Use Register-Completer -Force to register it again."
                }
                elseif ([string]::IsNullOrWhiteSpace($managedRegistration.ScriptPath))
                {
                    "The completer registration '$runtimeKey' was registered from a script block, not a script file, so there is nothing to reload."
                }
                elseif (-not (Test-Path -LiteralPath $managedRegistration.ScriptPath -PathType Leaf))
                {
                    "The script '$($managedRegistration.ScriptPath)' for '$runtimeKey' no longer exists. Restore it, or remove the registration with Unregister-Completer."
                }

                if ($null -eq $reason)
                {
                    if ($managedState -eq 'Pending')
                    {
                        Write-Verbose -Message "The completer registration '$runtimeKey' is already pending."

                        if ($PassThru -and -not $WhatIfPreference)
                        {
                            $PSCmdlet.WriteObject($managedRegistration)
                        }
                    }
                    elseif ($PSCmdlet.ShouldProcess($runtimeKey, 'Reset completer registration'))
                    {
                        $registration = New-CompleterRegistrationRecord -Target $managedRegistration -ScriptBlock (New-CompleterLazyStub -Key $managedRegistration.Key) -Source 'Managed' -State 'Pending' -ScriptPath $managedRegistration.ScriptPath -Trusted:([bool] $managedRegistration.Trusted)
                        $conflict = [pscustomobject] [ordered] @{
                            Key                 = $registration.Key
                            ManagedRegistration = $managedRegistration
                            RuntimeRegistration = $runtimeRegistration
                            IsExisting          = $false
                            Problem             = $null
                        }

                        $storedRegistration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                        if ($PassThru)
                        {
                            $PSCmdlet.WriteObject($storedRegistration)
                        }
                    }
                }
            }
            catch
            {
                $failure = $_.Exception
                $reason = $_.Exception.Message
            }

            if ($null -ne $reason)
            {
                Write-CompleterResetError -Message "Failed to reset the completer '$($target.RuntimeKey)'. $reason" -Exception $failure -TargetObject $target.RuntimeKey
            }
        }
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
CompleterActions.CompleterScriptFinding
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
    [OutputType('CompleterActions.CompleterScriptFinding')]
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
set file, as in a staged package before it is published. When more than
one .psd1 there declares the set, the first in ordinal order of file name is
the manifest. A .psd1 that is not data declares nothing, and a folder that
cannot be listed holds no manifest. A set that no manifest declares gets no
PackageLayout finding. A package set is checked for four things, reported
in this order:

- Error, one per entry in set order, at the entry's Path: the Path is fully
  qualified, or resolves outside the module folder, so an installed copy of
  the package does not contain the script. A fully qualified path is an
  error even inside the module folder, because it names the source tree, not
  the installed copy.
- Error, one per file in ordinal order of file name: the module folder holds
  a .psd1 other than the manifest, so Publish-PSResource can take the wrong
  file as the manifest.
- Error: the set file's base name equals the module name, compared
  case-insensitively, so PSResourceGet can take the set as the module
  manifest when it saves or installs the package, even from a subfolder.
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
<#
.EXTERNALHELP CompleterActions-help.xml
#>
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
target fields, plus pipeline input from Get-Completer output; each target is
decided once per call, so the Conflicted twin of a Stale record is skipped
rather than confirmed again or reported as missing, and a declined
confirmation stands. Keys
are output-only identifiers: a hand-typed key string is not accepted, so name
the target with -CommandName plus -Native or -ParameterName instead. To reload
a Failed or Active script-backed registration instead of removing it, use
Reset-Completer.

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
CompleterActions.CompleterRegistration
When -PassThru is used, returns removed CompleterActions.CompleterRegistration
records.
#>
function Unregister-Completer
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
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
        $removedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

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
                if ($removedKeys.Contains($target.Key))
                {
                    continue
                }

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

                    $null = $removedKeys.Add($target.Key)

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
.SYNOPSIS
Writes a batch of completer registrations to the runtime and the managed state as one transaction.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved every
record's conflicts and confirmed the operation. Each record whose conflict
result reports IsExisting is not written; the managed record it already
matches is returned in its place. The batch is written in two passes: every
other record's script block is first added to the live completer dictionary,
in order, and only then is every such record stored in the managed
registration table, in order. The stored records are returned in the same
order as the input. With one record the two passes are the runtime write and
then the managed write of that record.

If any write fails, the batch is rolled back in reverse from the last record
whose runtime write was started: for each written record, the earlier runtime
value carried on its conflict result is put back or the new one removed, and
the earlier managed record is put back or the new one removed, so the session
ends exactly as it was before the batch. A managed write that fails therefore
also undoes the runtime values of the records after it, which the runtime pass
had already written. The error names the target whose write failed, and a
failure during the rollback is reported together with the original error so
the caller can say the target may be inconsistent. Register-Completer writes
each target through this helper on its own, so every target of a call stays
its own transaction, and Import-CompleterSet writes a whole set through it,
so an eager, a lazy, and a completer set registration share one write path.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records to store, in write order.
Each record's ScriptBlock is the value written to the runtime dictionary.

.PARAMETER Conflict
The results Resolve-CompleterRegistrationConflict returned for the same
records, in the same order. Their RuntimeRegistration and ManagedRegistration
are the state restored when a write fails.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot the records were resolved
against. Its RuntimeContext and Managed table are written through, so a batch
looks up the runtime dictionaries and the managed table once instead of once
per record. When it is omitted each write looks them up itself.

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
        [psobject[]] $Conflict,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($Registration.Count -ne $Conflict.Count)
    {
        throw "Each registration needs the conflict result resolved for it, but $($Registration.Count) registrations came with $($Conflict.Count) conflict results."
    }

    $runtimeParameters = @{}
    $managedParameters = @{}

    if ($null -ne $Snapshot)
    {
        $runtimeParameters['Runtime'] = $Snapshot.RuntimeContext
        $managedParameters['Table'] = $Snapshot.Managed
    }

    $storedRegistrations = [System.Collections.Generic.List[psobject]]::new()
    $runtimeIndex = -1
    $managedIndex = -1

    try
    {
        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            $runtimeIndex = $index
            $null = Add-RuntimeCompleterRegistration -Target $Registration[$index] -ScriptBlock $Registration[$index].ScriptBlock @runtimeParameters
        }

        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                $storedRegistrations.Add($Conflict[$index].ManagedRegistration)
                continue
            }

            $managedIndex = $index
            $storedRegistrations.Add((Add-ManagedCompleterRegistration -Registration $Registration[$index] @managedParameters))
        }

        return $storedRegistrations
    }
    catch
    {
        $registrationError = $_
        $failedIndex = if ($managedIndex -ge 0) { $managedIndex } else { $runtimeIndex }
        $failedRegistration = $Registration[$failedIndex]
        $rollbackErrors = [System.Collections.Generic.List[string]]::new()

        for ($index = $runtimeIndex; $index -ge 0; $index--)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            try
            {
                if ($null -ne $Conflict[$index].RuntimeRegistration)
                {
                    $null = Add-RuntimeCompleterRegistration -Target $Conflict[$index].RuntimeRegistration -ScriptBlock $Conflict[$index].RuntimeRegistration.ScriptBlock @runtimeParameters
                }
                else
                {
                    $null = Remove-RuntimeCompleterRegistration -Key $Registration[$index].Key
                }

                if ($null -ne $Conflict[$index].ManagedRegistration)
                {
                    $null = Add-ManagedCompleterRegistration -Registration $Conflict[$index].ManagedRegistration @managedParameters
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

.PARAMETER Table
The managed registration table to write to, as a registration snapshot
carries it in Managed. When it is omitted the module's table is looked up for
this call.

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
        [psobject] $Registration,

        [Parameter()]
        [System.Collections.IDictionary] $Table
    )

    process
    {
        if ($null -eq $Registration.PSObject.Properties['Key'] -or [string]::IsNullOrWhiteSpace([string] $Registration.Key))
        {
            throw 'Registration records must expose a non-empty Key property.'
        }

        try
        {
            $registrations = $Table

            if ($null -eq $registrations)
            {
                $registrations = Get-ManagedCompleterRegistrationTable
            }

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

.PARAMETER Runtime
The CompleterActions.CompleterRuntime object to write through, as a
registration snapshot carries it in RuntimeContext. When it is omitted the
runtime is looked up for this call. When the object's dictionary is null the
helper re-reads it from the execution context first, so a dictionary another
registration created after the snapshot is kept rather than replaced, and
creates one only when the context still has none. Either way the dictionary is
stored on this object, so every later write of the same batch reuses it.
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
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [psobject] $Runtime
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    if ($null -eq $Runtime)
    {
        $Runtime = Get-CompleterRuntime
    }

    $propertyName = if ($Target.IsNative) { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
    $dictionary = $Runtime.$propertyName

    if ($null -eq $dictionary)
    {
        $runtimeProperty = if ($Target.IsNative) { $Runtime.NativeProperty } else { $Runtime.CustomProperty }
        if ($null -eq $runtimeProperty)
        {
            throw "The current PowerShell runtime does not expose the '$propertyName' completer dictionary."
        }

        $dictionary = $runtimeProperty.GetValue($Runtime.ExecutionContext)
        if ($null -eq $dictionary)
        {
            $dictionary = [System.Collections.Generic.Dictionary[string, scriptblock]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $runtimeProperty.SetValue($Runtime.ExecutionContext, $dictionary)
        }

        $Runtime.$propertyName = $dictionary
    }

    return Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey) -Value $ScriptBlock
}
<#
.SYNOPSIS
Asserts that the PowerShell runtime exposes every internal member CompleterActions needs.

.DESCRIPTION
CompleterActions reaches into non-public PowerShell runtime members to discover and
manage argument completers: the execution context field behind EngineIntrinsics and
the two completer dictionaries that execution context owns.

This probe runs once during module import. It asks the compiled engine access layer
(CompleterActions.Internal.EngineAccess) to resolve all of those members, so an engine
whose internals changed fails with a single terminating error that names the PowerShell
version and the unresolved members, instead of failing deep inside a later
registration or discovery call. On success the resolved handles are kept in module
state for Get-CompleterRuntime.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

.PARAMETER RuntimeExecutionContext
An already resolved execution context object to inspect for the completer
dictionaries. When supplied, the execution context resolution step is skipped. This
is primarily exposed for internal testing of compatibility guards.

.OUTPUTS
None

.EXAMPLE
Assert-CompleterRuntimeCapability

Verifies that the current engine exposes the completer runtime members and throws a
single terminating error when any of them cannot be resolved.

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

    try
    {
        $engine = [CompleterActions.Internal.EngineAccess]::Create($EngineIntrinsics, $EngineIntrinsicsType, $RuntimeExecutionContext, $PSVersionTable.PSVersion)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }

    $script:CompleterEngine = $engine
}
<#
.SYNOPSIS
Throws when a completer script does not conform to the strict import grammar.

.DESCRIPTION
Runs Get-CompleterScriptFinding over a completer script and throws one error
that lists every Error finding with its line, column, construct, message, and
hint. Import-CompleterScript runs this gate under the strict tier, both for an
eager import and when a lazy stub loads its script on the first tab press, and
Register-Completer -Lazy runs it on the parse it derives the targets from, so
no strict path executes or registers a script the grammar rejects and every
path reports the same findings as Test-CompleterScript. A conforming script
returns without output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again; Register-Completer -Lazy passes the
parse it also derives the script's targets from.

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
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    $findings = @(Get-CompleterScriptFinding @PSBoundParameters | Where-Object -Property Severity -EQ -Value 'Error')

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
Decodes the bytes a help probe captured into text.

.DESCRIPTION
Applies the help decoding steps in order. Bytes that start with the UTF-16 LE
byte-order mark FF FE, or that contain U+0000 when decoded leniently as UTF-8,
are decoded as UTF-16 LE. Otherwise the bytes are decoded as strict UTF-8,
after skipping a UTF-8 byte-order mark. When strict UTF-8 fails, Windows
decodes with the OEM code page of the current culture and Linux and macOS
decode with Latin-1 (code page 28591). A leading U+FEFF left by any decoder is
removed last. The text is not cleaned; ConvertTo-CompleterCleanHelpText does
that.

.PARAMETER Bytes
The captured bytes of one output stream.

.OUTPUTS
System.String
#>
function ConvertFrom-CompleterHelpOutput
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]] $Bytes
    )

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE)
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    elseif ([System.Text.Encoding]::UTF8.GetString($Bytes).Contains([char] 0))
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    else
    {
        $offset = 0
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
        {
            $offset = 3
        }

        try
        {
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
        catch [System.Text.DecoderFallbackException]
        {
            $codePage = if ($IsWindows)
            {
                [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            }
            else
            {
                28591
            }

            $text = [System.Text.Encoding]::GetEncoding($codePage).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF)
    {
        $text = $text.Substring(1)
    }

    $text
}
<#
.SYNOPSIS
Parses the subcommand table out of cleaned help text.

.DESCRIPTION
Reads the text line by line with fixed rules. A section header is a whole line
of one to six words, optionally wrapped in angle brackets and followed by a
colon, one of which is command, commands, subcommand, or subcommands. After a
header, blank and underline lines are skipped and the first entry fixes the
section's indentation; any other line before the first entry ends the
section. Entries at that indentation are kept; deeper lines are
continuations and other non-entry lines are skipped. A blank line, a header,
or a shallower entry ends the section. Names keep help order and are
de-duplicated case-insensitively. Control, format, and line and paragraph
separator characters in a description become spaces, whitespace runs
collapse, and an empty description becomes the name.

.PARAMETER Text
Help text already cleaned by ConvertTo-CompleterCleanHelpText.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function ConvertFrom-CompleterHelpText
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $headerPattern = [regex]::new('^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$')
    $entryPattern = [regex]::new('^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$')
    $underlinePattern = [regex]::new('^\s*(?:=+|-+)\s*$')
    $headerWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('command', 'commands', 'subcommand', 'subcommands'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $inSection = $false
    $sectionIndent = -1

    foreach ($line in $Text.Split("`n"))
    {
        $header = $headerPattern.Match($line)
        if ($header.Success)
        {
            $isHeader = $false
            foreach ($word in $header.Groups['words'].Value.Split(' '))
            {
                if ($headerWords.Contains($word.Trim('(', ')', ',')))
                {
                    $isHeader = $true
                    break
                }
            }

            if ($isHeader)
            {
                $inSection = $true
                $sectionIndent = -1
                continue
            }
        }

        if (-not $inSection)
        {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line))
        {
            if ($sectionIndent -ge 0)
            {
                $inSection = $false
            }

            continue
        }

        if ($sectionIndent -lt 0)
        {
            if ($underlinePattern.IsMatch($line))
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                $inSection = $false
                continue
            }

            $sectionIndent = $entry.Groups['indent'].Length
        }
        else
        {
            $indent = $line.Length - $line.TrimStart(' ', "`t").Length
            if ($indent -gt $sectionIndent)
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                continue
            }

            if ($indent -lt $sectionIndent)
            {
                $inSection = $false
                continue
            }
        }

        $name = $entry.Groups['name'].Value
        if (-not $seen.Add($name))
        {
            continue
        }

        $description = [regex]::Replace($entry.Groups['desc'].Value, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', ' ')
        $description = [regex]::Replace($description, '\s+', ' ').Trim()
        if ($description.Length -eq 0)
        {
            $description = $name
        }

        [pscustomobject] [ordered] @{
            Name        = $name
            Description = $description
        }
    }
}
<#
.SYNOPSIS
Removes terminal formatting from help text.

.DESCRIPTION
Applies the help cleaning rules in order: CSI sequences, OSC sequences such as
titles and OSC 8 hyperlinks (only the link text remains), any remaining
two-character escape, backspace overstrikes, and carriage returns. CR LF
becomes LF, and then each line keeps only the text after its last remaining
CR, which removes progress lines. The probe output and -HelpText both go
through this cleaner before parsing. The result uses LF line endings.

.PARAMETER Text
The decoded help text.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterCleanHelpText
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $clean = [regex]::Replace($Text, '\e\[[0-9;?]*[ -/]*[@-~]', '')
    $clean = [regex]::Replace($clean, '\e\][^\a\e]*(?:\a|\e\\)', '')
    $clean = [regex]::Replace($clean, '\e[@-_]', '')

    # Removing [^\x08]\x08 until stable and then any remaining \x08 is done in
    # linear time: one regex pass removes the simple overstrikes, then a run of
    # n backspaces erases up to n characters before it, and the backspaces left
    # over are dropped. Pair removal gives the same result in any order.
    $clean = [regex]::Replace($clean, '[^\x08]\x08', '')
    $backspaceRuns = [regex]::Matches($clean, '\x08+')
    if ($backspaceRuns.Count -gt 0)
    {
        $builder = [System.Text.StringBuilder]::new($clean.Length)
        $start = 0
        foreach ($run in $backspaceRuns)
        {
            $null = $builder.Append($clean.Substring($start, $run.Index - $start))
            $builder.Length -= [System.Math]::Min($run.Length, $builder.Length)
            $start = $run.Index + $run.Length
        }

        $null = $builder.Append($clean.Substring($start))
        $clean = $builder.ToString()
    }

    $clean = $clean.Replace("`r`n", "`n")

    $lines = $clean.Split("`n")
    for ($index = 0; $index -lt $lines.Length; $index++)
    {
        $lastReturn = $lines[$index].LastIndexOf("`r")
        if ($lastReturn -ge 0)
        {
            $lines[$index] = $lines[$index].Substring($lastReturn + 1)
        }
    }

    $lines -join "`n"
}
<#
.SYNOPSIS
Derives the stem that names a generated completer script's state and function.

.DESCRIPTION
Drops one trailing .exe, .cmd, .bat, .ps1, or .com (compared
case-insensitively) from the primary command name, splits the rest on every
character that is not an ASCII letter or digit, upper-cases the first
character of each part with the invariant culture, and joins the parts. 'rg'
and 'rg.exe' give 'Rg', 'oh-my-posh' gives 'OhMyPosh', 'DSC' stays 'DSC', and
'7z' gives '7z'. The script names $script:<Stem>CompletionCatalog and
Complete-<Stem> after it.

.PARAMETER Name
The primary command name, already checked by ConvertTo-CompleterTargetName.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterScriptStem
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $baseName = $Name

    foreach ($suffix in '.exe', '.cmd', '.bat', '.ps1', '.com')
    {
        if ($baseName.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $baseName = $baseName.Substring(0, $baseName.Length - $suffix.Length)
            break
        }
    }

    $parts = [System.Text.RegularExpressions.Regex]::Split($baseName, '[^A-Za-z0-9]+') | Where-Object { $_.Length -gt 0 }

    -join @($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
}
<#
.SYNOPSIS
Escapes text for a single-quoted PowerShell string literal.

.DESCRIPTION
Doubles every character PowerShell's tokenizer accepts as a single-quote
delimiter: U+0027, U+2018, U+2019, U+201A, and U+201B. Help text such as
"don't" written with a typographic apostrophe would otherwise end the string.
Every other character is kept as is. The result goes between two U+0027
quotes.

.PARAMETER Value
The text to escape.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterSingleQuotedText
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $escaped = $Value

    foreach ($quote in [char] 0x0027, [char] 0x2018, [char] 0x2019, [char] 0x201A, [char] 0x201B)
    {
        $escaped = $escaped.Replace([string] $quote, [string] $quote + $quote)
    }

    $escaped
}
<#
.SYNOPSIS
Builds the native target list a generated completer script registers.

.DESCRIPTION
Checks every command name before building anything, and throws for the first
name that is not a bare command name: at least one ASCII letter or digit, no
path separators, spaces, quotes, or wildcard characters, no leading '-' or
'.', and no trailing '.' or '-'. A name that passes but whose stem would be
empty, such as '_.exe', whose only letters are its suffix, is then refused
with its own reason, so no function name is ever derived from an empty stem.
The list then follows the -CommandName order.
Each name is written as given, and a name that does not end in .exe, .cmd,
.bat, .ps1, or .com is followed by the same name with .exe appended. Names are
de-duplicated case-insensitively, keeping the first spelling, so 'rg' and
'rg', 'rg.exe' give the same list, and no bare name is derived from a suffixed
one.

.PARAMETER CommandName
The command names, primary name first.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterTargetName
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName
    )

    # The spec's pattern, with \z in place of $ so a trailing newline does not match.
    $commandNamePattern = '^(?=.*[A-Za-z0-9])[A-Za-z0-9_](?:[A-Za-z0-9._+-]*[A-Za-z0-9_+])?\z'

    foreach ($commandNameItem in $CommandName)
    {
        if (-not [System.Text.RegularExpressions.Regex]::IsMatch($commandNameItem, $commandNamePattern))
        {
            throw "'$commandNameItem' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters."
        }

        if ([string]::IsNullOrEmpty((ConvertTo-CompleterScriptStem -Name $commandNameItem)))
        {
            throw "The command name '$commandNameItem' has no letter or digit outside its suffix, so no function name can be derived from it."
        }
    }

    $suffixes = '.exe', '.cmd', '.bat', '.ps1', '.com'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetNames = [System.Collections.Generic.List[string]]::new()

    foreach ($commandNameItem in $CommandName)
    {
        $names = @($commandNameItem)
        $hasSuffix = @($suffixes | Where-Object { $commandNameItem.EndsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0

        if (-not $hasSuffix)
        {
            $names += '{0}.exe' -f $commandNameItem
        }

        foreach ($name in $names)
        {
            if ($seen.Add($name))
            {
                $targetNames.Add($name)
            }
        }
    }

    $targetNames.ToArray()
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
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered' -State Discovered))
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
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered' -State Discovered))
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
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) -Native) -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $runtime.NativeArgumentCompleters -Key ([string] $entryKey)) -Source 'Discovered' -State Discovered
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
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entryKey)) -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $runtime.CustomArgumentCompleters -Key ([string] $entryKey)) -Source 'Discovered' -State Discovered
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

    return New-CompleterRegistrationRecord -Target $target -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $target.RuntimeKey) -Source 'Discovered' -State Discovered
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
Reads a subcommand table by running a program's help.

.DESCRIPTION
Decides what the help probe runs and turns each run's outcome into a table,
warnings, and verbose lines.

An application whose CanRun is false runs nothing; its Warning is returned.
Otherwise the program runs once with -HelpArgument, or with --help when
-HelpArgument is not given. On Windows, without -HelpArgument, /? runs once
more only when the --help run exited, yielded no subcommand, and its cleaned
text has fewer than five non-blank lines; the /? result is then used. No /?
runs after a timeout, a start failure, or held output, so one call returns at
most one warning.

A run that timed out, whose output a descendant held, or that failed to start
gives its warning and an empty table, and adds no probe verbose line, because
the line's exit code, characters, and subcommands describe a run that exited.
For a run that exited, the text is standard output, or standard error when
standard output is empty or whitespace after decoding; the exit code decides
nothing. The text is decoded, cleaned, and parsed with the help text helpers,
and the run adds one probe verbose line.

Warnings and verbose lines are returned as data; this helper writes no
stream.

.PARAMETER Application
The record Resolve-CompleterHelpProbeApplication returned for the primary
name.

.PARAMETER HelpArgument
The one argument to pass. When omitted the probe passes --help, and on
Windows may fall back to /?.

.PARAMETER TimeoutSeconds
The deadline for each run, in seconds.

.OUTPUTS
CompleterActions.CompleterHelpSubcommandResult
Returns a record with Subcommands (the parsed rows, in help order), Argument
(the argument of the last run that exited, whose result was used, or null
when no run exited; a /? run that does not exit leaves it at --help),
Warnings, and VerboseLines.
#>
function Get-CompleterHelpSubcommand
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Application,

        [Parameter()]
        [string] $HelpArgument,

        [Parameter(Mandatory)]
        [double] $TimeoutSeconds
    )

    $subcommands = @()
    $argument = $null
    $warnings = [System.Collections.Generic.List[string]]::new()
    $verboseLines = [System.Collections.Generic.List[string]]::new()

    if (-not $Application.CanRun)
    {
        $warnings.Add($Application.Warning)
    }
    else
    {
        $hasHelpArgument = $PSBoundParameters.ContainsKey('HelpArgument')
        $runArgument = if ($hasHelpArgument) { $HelpArgument } else { '--help' }
        $limit = $TimeoutSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)

        while ($true)
        {
            $result = Invoke-CompleterHelpProcess -FilePath $Application.Path -ArgumentList @($runArgument) -TimeoutSeconds $TimeoutSeconds

            switch ($result.Status)
            {
                'TimedOut'
                {
                    $warnings.Add("'$($Application.Name) $runArgument' did not exit within $limit seconds and was stopped, so its help was not used.")
                }
                'HeldOutput'
                {
                    $warnings.Add("'$($Application.Name) $runArgument' exited but left a process holding its output, so its help was not used.")
                }
                'StartFailed'
                {
                    $warnings.Add("'$($Application.Path)' was not run: $($result.StartError). Pass captured help with -HelpText.")
                }
            }

            if ($result.Status -ne 'Exited')
            {
                break
            }

            $text = ConvertFrom-CompleterHelpOutput -Bytes $result.StandardOutput
            if ([string]::IsNullOrWhiteSpace($text))
            {
                $text = ConvertFrom-CompleterHelpOutput -Bytes $result.StandardError
            }

            $cleanText = ConvertTo-CompleterCleanHelpText -Text $text
            $subcommands = @(ConvertFrom-CompleterHelpText -Text $cleanText)
            $argument = $runArgument
            $verboseLines.Add("Probed '$($Application.Path) $argument': exit $($result.ExitCode), $($text.Length) characters, $($subcommands.Count) subcommands, $($result.ElapsedMilliseconds) ms.")

            $tryFallback = $IsWindows -and -not $hasHelpArgument -and $argument -eq '--help' -and $subcommands.Count -eq 0
            if (-not $tryFallback)
            {
                break
            }

            $nonBlankLines = @($cleanText.Split("`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
            if ($nonBlankLines -ge 5)
            {
                break
            }

            $runArgument = '/?'
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName   = 'CompleterActions.CompleterHelpSubcommandResult'
        Subcommands  = $subcommands
        Argument     = $argument
        Warnings     = $warnings.ToArray()
        VerboseLines = $verboseLines.ToArray()
    }
}
<#
.SYNOPSIS
Reads the Subsystem field of a Windows program's PE header.

.DESCRIPTION
Opens the file with File.OpenRead, reads at most its first 4096 bytes, and
returns the optional header's Subsystem value: 2 for a Windows GUI program, 3
for a Windows console program, and other values for other images. No process
is started to inspect the file.

The reader checks the MZ signature, follows e_lfanew (the Int32 at 0x3C) to
the PE\0\0 signature, checks the optional-header magic (0x10B for PE32, 0x20B
for PE32+), and reads Subsystem as the UInt16 at e_lfanew + 24 + 68, an offset
that is the same in PE32 and PE32+. A file too short for that, a wrong
signature or magic, and any failure to open or read the file, such as an app
execution alias or a file another handle holds exclusively, return null. The
reader never throws.

.PARAMETER LiteralPath
The full path of the file to read.

.OUTPUTS
System.Int32
Returns the Subsystem value, or null when the header cannot be read.
#>
function Get-CompleterPESubsystem
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $buffer = [byte[]]::new(4096)
    $count = 0

    try
    {
        $stream = [System.IO.File]::OpenRead($LiteralPath)
        try
        {
            while ($count -lt $buffer.Length)
            {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -eq 0)
                {
                    break
                }

                $count += $read
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }
    catch
    {
        Write-Debug -Message "The program header of '$LiteralPath' could not be read. $($_.Exception.Message)"
        return $null
    }

    if ($count -lt 0x40 -or $buffer[0] -ne 0x4D -or $buffer[1] -ne 0x5A)
    {
        return $null
    }

    $peOffset = [System.BitConverter]::ToInt32($buffer, 0x3C)
    if ($peOffset -lt 0 -or ([long] $peOffset + 94) -gt $count)
    {
        return $null
    }

    if ($buffer[$peOffset] -ne 0x50 -or $buffer[$peOffset + 1] -ne 0x45 -or $buffer[$peOffset + 2] -ne 0 -or $buffer[$peOffset + 3] -ne 0)
    {
        return $null
    }

    $magic = [System.BitConverter]::ToUInt16($buffer, $peOffset + 24)
    if ($magic -ne 0x10B -and $magic -ne 0x20B)
    {
        return $null
    }

    [int] [System.BitConverter]::ToUInt16($buffer, $peOffset + 24 + 68)
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
dictionaries: its views describe the session at the moment it was taken and
are meant to be consumed before the same batch writes, and the batch then
writes through its RuntimeContext and Managed table instead of looking them
up again for every target. Parameter-only entries of the
custom dictionary, registered with Register-ArgumentCompleter -ParameterName
alone, are left out of the index because the module does not manage them and
a native-shaped key must never resolve against one.

.OUTPUTS
CompleterActions.CompleterRegistrationSnapshot
Returns an object with Managed, the managed registration table; Runtime, one
view per runtime dictionary in the order Find-RuntimeCompleterRegistration
searches them, native first; and RuntimeContext, the
CompleterActions.CompleterRuntime object the views were read from. Each view
carries IsNative, the Dictionary, and Keys, a case-insensitive map from a key
to the casing the dictionary stores.

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
        PSTypeName     = 'CompleterActions.CompleterRegistrationSnapshot'
        Managed        = Get-ManagedCompleterRegistrationTable
        Runtime        = $views
        RuntimeContext = $runtime
    }
}
<#
.SYNOPSIS
Gets the current session's completer runtime dictionaries from PowerShell internals.

.DESCRIPTION
Builds the runtime wrapper object from the engine access handles that
Assert-CompleterRuntimeCapability resolved at import: the execution context object
that owns the runtime completer dictionaries and the handles of its two dictionary
properties. Maintainers use this helper when they need authoritative access to the
live CustomArgumentCompleters and NativeArgumentCompleters collections that
Register-ArgumentCompleter populates.

The dictionaries are read through the handles on every call, so a dictionary the
engine creates after import is seen.

This helper depends on non-public PowerShell runtime details. It is therefore
intended only for internal module plumbing.

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

    $engine = $script:CompleterEngine

    if ($null -eq $engine -or $null -eq $engine.CustomProperty -or $null -eq $engine.NativeProperty)
    {
        throw 'The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.'
    }

    $runtime = [pscustomobject] [ordered] @{
        PSTypeName               = 'CompleterActions.CompleterRuntime'
        ExecutionContext         = $engine.ExecutionContext
        CustomProperty           = $engine.CustomProperty
        CustomArgumentCompleters = $engine.CustomProperty.GetValue($engine.ExecutionContext)
        NativeProperty           = $engine.NativeProperty
        NativeArgumentCompleters = $engine.NativeProperty.GetValue($engine.ExecutionContext)
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

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again, so a caller that also derives the
script's targets from the same parse reads the file once.

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
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    if (-not $PSBoundParameters.ContainsKey('ParseResult'))
    {
        $ParseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    }

    if ($ParseResult.ParseErrors.Count -gt 0)
    {
        foreach ($parseError in $ParseResult.ParseErrors)
        {
            New-CompleterScriptFinding -Path $LiteralPath -Extent $parseError.Extent -Construct 'ParseError' -Message $parseError.Message -Hint 'Fix the syntax error; the completer shape is only checked once the script parses.'
        }

        return
    }

    Test-CompleterScriptAst -Ast $ParseResult.Ast -LiteralPath $LiteralPath
}
<#
.SYNOPSIS
Computes the set file Hash of a completer script's text.

.DESCRIPTION
Returns 'SHA256:' followed by 64 uppercase hexadecimal digits: the SHA-256 of
the script's decoded text after every CR LF pair, and then every remaining lone
CR, is replaced with LF, encoded as UTF-8 without a byte-order mark. The same
script therefore hashes to one value whether it is checked out with CRLF on
Windows or LF on Linux, and whether or not it carries a byte-order mark.

-Text hashes text that is already decoded, such as a parse result's
Ast.Extent.Text, so a caller that has parsed the script does not read it a
second time. -LiteralPath reads the file with File.ReadAllText, which decodes
UTF-8 unless a byte-order mark names another encoding, as PowerShell's parser
does. ReadAllText resolves a relative path against the process directory, so
callers pass a full path.

.PARAMETER Text
The decoded script text to hash.

.PARAMETER LiteralPath
The full path of the script file to read and hash.

.OUTPUTS
System.String
#>
function Get-CompleterScriptHash
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'LiteralPath')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        $Text = [System.IO.File]::ReadAllText($LiteralPath)
    }

    $normalizedText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try
    {
        $digest = $sha256.ComputeHash($bytes)
    }
    finally
    {
        $sha256.Dispose()
    }

    'SHA256:' + ([System.BitConverter]::ToString($digest) -replace '-', '')
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
Composes the lines of a generated native completer script.

.DESCRIPTION
Returns the skeleton New-CompleterScript writes, one string per line and
without line endings: the two comment lines, Set-StrictMode, one guarded
literal-only state block holding the subcommand table, a Complete-<Stem>
completion function that offers the table in the first argument position, and
one bare script-scope Register-ArgumentCompleter call with a literal
-CommandName list. Every string literal is single-quoted with its quote
characters doubled. The
output names no date, version, or machine path, so the same input always gives
the same lines. The generated code uses four-space indentation and opening
braces on the same line, because it belongs to the author's repository.

.PARAMETER Name
The primary command name, as given. Line 1 names it, and so does line 2 of a
probe-seeded script.

.PARAMETER Stem
The stem from ConvertTo-CompleterScriptStem.

.PARAMETER Target
The target list from ConvertTo-CompleterTargetName.

.PARAMETER Subcommand
The subcommand rows, each with a Name and a Description, in help order. An
empty list writes an empty table and the skeleton line 2.

.PARAMETER SeedKind
Where a non-empty table came from: Probe or HelpText. It picks line 2.

.PARAMETER ProbeArgument
The argument whose output seeded the table. Required with -SeedKind Probe. It
must not contain a line break, which would end the line 2 comment.

.OUTPUTS
System.String
#>
function Get-CompleterScriptSkeleton
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Stem,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Target,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Subcommand,

        [Parameter()]
        [ValidateSet('Probe', 'HelpText')]
        [string] $SeedKind,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('\A[^\r\n]*\z')]
        [string] $ProbeArgument
    )

    $catalogName = '{0}CompletionCatalog' -f $Stem
    $functionName = 'Complete-{0}' -f $Stem

    if ($Subcommand.Count -eq 0)
    {
        $sourceLine = '# Native completer skeleton: add subcommands to the table and options to {0}.' -f $functionName
    }
    elseif ($SeedKind -eq 'Probe' -and $PSBoundParameters.ContainsKey('ProbeArgument'))
    {
        $sourceLine = "# Help-seeded native completer: the subcommand table was read from '{0} {1}' when the script was generated." -f $Name, $ProbeArgument
    }
    elseif ($SeedKind -eq 'HelpText')
    {
        $sourceLine = '# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.'
    }
    else
    {
        throw 'A non-empty subcommand table needs -SeedKind HelpText, or -SeedKind Probe with -ProbeArgument.'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('# {0} tab completion for PowerShell' -f $Name))
    $lines.Add($sourceLine)
    $lines.Add('')
    $lines.Add('Set-StrictMode -Version 2.0')
    $lines.Add('')
    $lines.Add(('if (-not (Get-Variable -Name {0} -Scope Script -ErrorAction Ignore)) {{' -f $catalogName))
    $lines.Add(('    $script:{0} = @{{' -f $catalogName))

    if ($Subcommand.Count -eq 0)
    {
        $lines.Add('        Subcommands = @()')
    }
    else
    {
        $lines.Add('        Subcommands = @(')

        foreach ($row in $Subcommand)
        {
            $lines.Add(("            @{{ Name = '{0}'; Description = '{1}' }}" -f (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Name)), (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Description))))
        }

        $lines.Add('        )')
    }

    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('function {0} {{' -f $functionName))
    $lines.Add('    param(')
    $lines.Add('        [string]$wordToComplete,')
    $lines.Add('        [System.Management.Automation.Language.CommandAst]$commandAst,')
    $lines.Add('        [int]$cursorPosition')
    $lines.Add('    )')
    $lines.Add('')
    $lines.Add('    # Offer subcommands in the first argument position only; extend this function for options and values.')
    $lines.Add('    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })')
    $lines.Add('    if ($precedingElements.Count -gt 1) {')
    $lines.Add('        return')
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add(('    foreach ($subcommand in $script:{0}.Subcommands) {{' -f $catalogName))
    $lines.Add('        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {')
    $lines.Add("            [System.Management.Automation.CompletionResult]::new(`$subcommand.Name, `$subcommand.Name, 'ParameterValue', `$subcommand.Description)")
    $lines.Add('        }')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('Register-ArgumentCompleter -Native -CommandName {0} -ScriptBlock {{' -f (@($Target | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', ')))
    $lines.Add('    param($wordToComplete, $commandAst, $cursorPosition)')
    $lines.Add('')
    $lines.Add(('    {0} -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition' -f $functionName))
    $lines.Add('}')

    $lines.ToArray()
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
The literal path to the completer script file. Error messages name it.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not read again, so a caller that also needs the
script's text, such as Export-CompleterSet for its Hash, reads the file once.

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
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    if (-not $PSBoundParameters.ContainsKey('ParseResult'))
    {
        $ParseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    }

    if ($ParseResult.ParseErrors.Count -gt 0)
    {
        $parseError = $ParseResult.ParseErrors[0]
        throw "The script '$LiteralPath' does not parse, so its targets cannot be derived. Line $($parseError.Extent.StartLineNumber), column $($parseError.Extent.StartColumnNumber): $($parseError.Message)"
    }

    $registerCommands = @($ParseResult.Ast.FindAll(
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
Finds the source positions of a completer set file's entries.

.DESCRIPTION
Parses the set file with the PowerShell parser, never evaluating it, and
returns the position of the Entries key and, for each element of the Entries
array, the element's own extent (the entry's @{ for a hashtable) and the
extents of its Path value, Hash key and value, and Targets key.
Test-CompleterSet uses them to point a finding at the part of the set that
needs fixing.

The elements are walked the way Import-CompleterSetDefinition reads them, so
the positions line up with its entry numbers: an Entries array written with
one element per line and one written with commas both work, and a $null
element is skipped because the definition reader drops it before the entries
are numbered.

.PARAMETER LiteralPath
The full path of the completer set file.

.OUTPUTS
CompleterActions.CompleterSetEntryExtent
Returns one record with EntriesExtent, the extent of the Entries key or of the
whole set when the key cannot be found, and Entries, one record per element
in set order with Extent, PathExtent, HashExtent, and TargetsExtent. An
extent the element does not have is null.
#>
function Get-CompleterSetEntryExtent
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
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $tokens, [ref] $parseErrors)

    # Output of a statement enumerates arrays, as the data reader's @() and
    # pipeline do; the elements of a comma array are not enumerated again.
    $getStatementElement = $null
    $getOutputElement = {
        param($Expression)

        if ($Expression -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            foreach ($element in $Expression.Elements)
            {
                if (-not ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.VariablePath.UserPath -eq 'null'))
                {
                    $element
                }
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            foreach ($statement in $Expression.SubExpression.Statements)
            {
                & $getStatementElement $statement
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ParenExpressionAst])
        {
            & $getStatementElement $Expression.Pipeline
        }
        elseif (-not ($Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and $Expression.VariablePath.UserPath -eq 'null'))
        {
            $Expression
        }
    }
    $getStatementElement = {
        param($Statement)

        if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and
            $Statement.PipelineElements.Count -eq 1 -and
            $Statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst])
        {
            & $getOutputElement $Statement.PipelineElements[0].Expression
        }
        else
        {
            $Statement
        }
    }

    $findKeyValue = {
        param($Hashtable, $Name)

        foreach ($keyValuePair in $Hashtable.KeyValuePairs)
        {
            if ($keyValuePair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $keyValuePair.Item1.Value -eq $Name)
            {
                return $keyValuePair
            }
        }
    }

    $setHashtable = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    $entriesPair = if ($null -ne $setHashtable) { & $findKeyValue $setHashtable 'Entries' }
    $entryExtents = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $entriesPair)
    {
        foreach ($element in @(& $getStatementElement $entriesPair.Item2))
        {
            $pathPair = $null
            $hashPair = $null
            $targetsPair = $null

            if ($element -is [System.Management.Automation.Language.HashtableAst])
            {
                $pathPair = & $findKeyValue $element 'Path'
                $hashPair = & $findKeyValue $element 'Hash'
                $targetsPair = & $findKeyValue $element 'Targets'
            }

            $entryExtents.Add([pscustomobject] [ordered] @{
                    Extent        = $element.Extent
                    PathExtent    = if ($null -ne $pathPair) { $pathPair.Item2.Extent } else { $null }
                    HashExtent    = if ($null -ne $hashPair) { $hashPair.Item2.Extent } else { $null }
                    TargetsExtent = if ($null -ne $targetsPair) { $targetsPair.Item1.Extent } else { $null }
                })
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterSetEntryExtent'
        EntriesExtent = if ($null -ne $entriesPair) { $entriesPair.Item1.Extent } else { $ast.Extent }
        Entries       = $entryExtents.ToArray()
    }
}
<#
.SYNOPSIS
Checks one completer set against the scripts on disk and returns its drift findings.

.DESCRIPTION
Runs the checks shared with Import-CompleterSet for every entry of a set that
Import-CompleterSetDefinition has read, and adds the checks only a drift
report needs. Each entry goes through Resolve-CompleterSetEntry -Verify, the
static phase of an import with the fast path turned off, so a strict script
is parsed once and its current hash and targets come from that one parse. A
trusted script is never parsed; its hash is read from the file.

The static phase's problems become MissingScript, InvalidEntry,
UnreadableTargets, and TargetMismatch findings with import's problem text.
DuplicateTarget follows import's claiming rule without the session: entries
are walked in set order, an entry with no Error finding claims its targets,
and a later entry that lists a claimed target gets import's duplicate text.
The declared Hash is then compared with the script's current hash
(HashMismatch), or reported as MissingHash or InvalidHash. Last, every file
under the set's directory that matches -Filter and that no entry lists, hidden
files included, is an UnlistedScript finding, compared case-insensitively on Windows and
case-sensitively elsewhere.

With Package, the set is a package set, and Get-CompleterSetPackageFinding
adds its PackageLayout findings after every entry's findings and before the
UnlistedScript findings. Without it the findings are exactly the plain set's.

Nothing here reads or writes the session's registrations or runs a script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.PARAMETER Package
The record Get-CompleterSetPackage returned for the set, when a module
manifest declares it.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the findings in set order, each entry's in the order MissingScript,
InvalidEntry, UnreadableTargets, TargetMismatch, DuplicateTarget,
HashMismatch, MissingHash, InvalidHash, then, for a package set, the
PackageLayout findings, followed by the UnlistedScript findings sorted by
path. Path is the set file for every finding.
#>
function Get-CompleterSetFinding
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Filter,

        [Parameter()]
        [psobject] $Package
    )

    $regenerateHint = 'Regenerate the set with Export-CompleterSet.'
    $hints = @{
        MissingScript     = 'Restore the script or remove the entry, then regenerate the set.'
        InvalidEntry      = 'Fix the entry in the set, or regenerate the set with Export-CompleterSet.'
        UnreadableTargets = 'Run Test-CompleterScript on the script, or mark the entry Trusted and list its targets.'
        TargetMismatch    = 'Regenerate the set with Export-CompleterSet; a strict entry must list every target its script registers.'
    }
    $hints['DuplicateTarget'] = $hints['TargetMismatch']

    $setPath = $SetDefinition.Path
    $extents = Get-CompleterSetEntryExtent -LiteralPath $setPath
    $pathComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $listedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    $claimedTargets = @{}
    $resolvedEntries = [System.Collections.Generic.List[object]]::new()
    $entryIndex = 0

    foreach ($rawEntry in $SetDefinition.Entries)
    {
        $entryIndex++
        $entry = Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $SetDefinition.Directory -Verify
        $resolvedEntries.Add($entry)
        $entryExtent = $extents.Entries[$entryIndex - 1]
        $findings = [System.Collections.Generic.List[object]]::new()

        if ($null -ne $entry.Path)
        {
            $null = $listedPaths.Add($entry.Path)
        }

        $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $entryIndex" } else { "Entry $entryIndex ('$($entry.DeclaredPath)')" }
        $entryStart = $entryExtent.Extent
        $pathStart = if ($null -ne $entryExtent.PathExtent) { $entryExtent.PathExtent } else { $entryStart }
        $hashStart = if ($null -ne $entryExtent.HashExtent) { $entryExtent.HashExtent } else { $entryStart }
        $targetsStart = if ($null -ne $entryExtent.TargetsExtent) { $entryExtent.TargetsExtent } else { $entryStart }
        $problemExtents = @{
            MissingScript     = $pathStart
            InvalidEntry      = $entryStart
            UnreadableTargets = $pathStart
            TargetMismatch    = $targetsStart
        }

        foreach ($kind in 'MissingScript', 'InvalidEntry', 'UnreadableTargets', 'TargetMismatch')
        {
            foreach ($problem in @($entry.Problems | Where-Object { $_.Kind -eq $kind }))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $problemExtents[$kind] -Construct $kind -Message "${entryLabel}: $($problem.Message)" -Hint $hints[$kind]))
            }
        }

        # $entry.Targets is the list import checks, so an entry with an Error
        # finding, such as a malformed target, can still report a duplicate.
        foreach ($target in @($entry.Targets))
        {
            if ($claimedTargets.Contains([string] $target.Key))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $targetsStart -Construct 'DuplicateTarget' -Message "${entryLabel}: Target '$($target.RuntimeKey)' is also listed by entry $($claimedTargets[[string] $target.Key])." -Hint $hints['DuplicateTarget']))
            }
        }

        if ($findings.Count -eq 0)
        {
            foreach ($target in @($entry.Targets))
            {
                $claimedTargets[[string] $target.Key] = $entryIndex
            }
        }

        if ($rawEntry -is [System.Collections.IDictionary])
        {
            if (-not $rawEntry.Contains('Hash'))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $entryStart -Construct 'MissingHash' -Severity Warning -Message "${entryLabel}: The entry has no Hash, so a change to its script cannot be detected." -Hint $regenerateHint))
            }
            elseif (-not (Test-CompleterSetHashFormat -Value $entry.DeclaredHash))
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'InvalidHash' -Severity Warning -Message "${entryLabel}: The Hash '$($entry.DeclaredHash)' is not 'SHA256:' followed by 64 hexadecimal digits, so it is ignored." -Hint $regenerateHint))
            }
            elseif ($null -ne $entry.ActualHash -and $entry.ActualHash -ne [string] $entry.DeclaredHash)
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'HashMismatch' -Severity Warning -Message "${entryLabel}: The script has changed since the set was written. Declared: $($entry.DeclaredHash). Script: $($entry.ActualHash)." -Hint $regenerateHint))
            }
        }

        $findings
    }

    if ($null -ne $Package)
    {
        Get-CompleterSetPackageFinding -SetDefinition $SetDefinition -Package $Package -Entry $resolvedEntries.ToArray()
    }

    $unlistedScripts = @(
        Get-ChildItem -LiteralPath $SetDefinition.Directory -Filter $Filter -File -Recurse -Force -ErrorAction Stop |
            Where-Object { -not $listedPaths.Contains($_.FullName) } |
            Sort-Object -Property FullName
    )

    foreach ($unlistedScript in $unlistedScripts)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extents.EntriesExtent -Construct 'UnlistedScript' -Severity Warning -Message "The script '$($unlistedScript.FullName)' matches '$Filter', but no entry of the set lists it." -Hint $regenerateHint
    }
}
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
<#
.EXTERNALHELP CompleterActions-help.xml
#>
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
<#
.SYNOPSIS
Checks a package set against the package layout and returns its PackageLayout findings.

.DESCRIPTION
Runs the four package-layout checks for a completer set whose module
manifest Get-CompleterSetPackage found, in this order:

- Error, per entry in set order: the entry's Path is fully qualified, or it
  resolves outside the module folder. The folder is compared with a trailing
  separator, case-insensitively on Windows and macOS and case-sensitively on
  Linux. The finding points at the entry's Path value.
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

Path is the set file for every finding. Nothing is imported or run.

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
<#
.EXTERNALHELP CompleterActions-help.xml
#>
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
    $moduleBase = $Package.ModuleBase
    $manifestPath = $Package.ManifestPath
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $moduleBasePrefix = $moduleBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $extents = Get-CompleterSetEntryExtent -LiteralPath $setPath
    $lineOne = [string] (Get-Content -LiteralPath $setPath -TotalCount 1)
    $positionOne = [System.Management.Automation.Language.ScriptPosition]::new($setPath, 1, 1, $lineOne)
    $extentOne = [System.Management.Automation.Language.ScriptExtent]::new($positionOne, $positionOne)

    foreach ($setEntry in $Entry)
    {
        if ([string]::IsNullOrWhiteSpace($setEntry.DeclaredPath))
        {
            continue
        }

        if ([System.IO.Path]::IsPathFullyQualified($setEntry.DeclaredPath) -or -not $setEntry.Path.StartsWith($moduleBasePrefix, $pathComparison))
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
Runs a program once to read its help, under one deadline.

.DESCRIPTION
Starts the program with UseShellExecute off, no window, the arguments in
ArgumentList so no shell parses them, standard input redirected and closed at
once, the temporary directory as the working directory, and the session's
environment plus NO_COLOR=1.

Standard output and standard error are read concurrently as bytes, one
ReadAsync per stream at a time. Each stream keeps its first 1 MiB (1048576
bytes) and keeps draining after that, discarding the rest, so a chatty
program never blocks on a full pipe. The reads are polled from this thread
with Task.WaitAny and a timeout, so no callback runs PowerShell code and no
wait is unbounded.

One deadline, fixed at start, covers the process and both reads. A process
still running at the deadline is killed with its descendants (Kill($true)),
waited for up to 1 second, and its output is dropped: TimedOut. When the
process has exited, the reads get until 1 second later or the deadline,
whichever is earlier; a read still open then means a descendant holds the
pipe, so the streams are closed, Kill($true) is attempted, and the output is
dropped: HeldOutput. An exception from Process.Start gives StartFailed with
the exception's message. Otherwise the result is Exited, with both streams'
bytes and the exit code; the exit code decides nothing here.

This helper writes no warning or verbose stream; its caller turns the status
into messages.

.PARAMETER FilePath
The full path of the program to run.

.PARAMETER ArgumentList
The arguments, each passed as one argument without shell parsing.

.PARAMETER TimeoutSeconds
The deadline in seconds, measured from the start of the run.

.OUTPUTS
CompleterActions.CompleterHelpProcessResult
Returns a record with Status (Exited, TimedOut, HeldOutput, or StartFailed),
ExitCode (null unless Exited), StandardOutput and StandardError (byte arrays,
empty unless Exited), ElapsedMilliseconds, ProcessId (null for StartFailed),
and StartError (the Process.Start exception message, or null).
#>
function Invoke-CompleterHelpProcess
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [ValidateRange(0.001, 3600)]
        [double] $TimeoutSeconds
    )

    $streamCap = 1048576
    $readSize = 65536
    $pollMilliseconds = 50

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $startInfo.Environment['NO_COLOR'] = '1'
    foreach ($argument in $ArgumentList)
    {
        $startInfo.ArgumentList.Add($argument)
    }

    $status = $null
    $exitCode = $null
    $processId = $null
    $startError = $null
    $readers = @()
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = $TimeoutSeconds * 1000

    try
    {
        try
        {
            $null = $process.Start()
        }
        catch
        {
            $exception = $_.Exception
            if ($exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $exception.InnerException)
            {
                $exception = $exception.InnerException
            }

            $status = 'StartFailed'
            $startError = $exception.Message
        }

        if ($null -eq $status)
        {
            $processId = $process.Id
            $process.StandardInput.Close()

            $readers = @(
                foreach ($stream in @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream))
                {
                    $buffer = [byte[]]::new($readSize)
                    [pscustomobject] @{
                        Stream = $stream
                        Buffer = $buffer
                        Data   = [System.IO.MemoryStream]::new()
                        Task   = $stream.ReadAsync($buffer, 0, $readSize)
                        Done   = $false
                    }
                }
            )

            $readDeadline = $deadline
            $exitSeen = $false
            while ($true)
            {
                $pending = @($readers | Where-Object { -not $_.Done })
                if ($pending.Count -eq 0)
                {
                    break
                }

                $now = $stopwatch.Elapsed.TotalMilliseconds
                if (-not $exitSeen -and $process.HasExited)
                {
                    $exitSeen = $true
                    $readDeadline = [System.Math]::Min($now + 1000, $deadline)
                }

                if ($now -ge $readDeadline)
                {
                    $status = if ($exitSeen) { 'HeldOutput' } else { 'TimedOut' }
                    break
                }

                $wait = [int] [System.Math]::Ceiling([System.Math]::Min($readDeadline - $now, $pollMilliseconds))
                $tasks = [System.Threading.Tasks.Task[]] @($pending | ForEach-Object { $_.Task })
                $null = [System.Threading.Tasks.Task]::WaitAny($tasks, $wait)

                foreach ($reader in $pending)
                {
                    if (-not $reader.Task.IsCompleted)
                    {
                        continue
                    }

                    $read = 0
                    if ($reader.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion)
                    {
                        $read = $reader.Task.Result
                    }

                    if ($read -le 0)
                    {
                        $reader.Done = $true
                        continue
                    }

                    $keep = [System.Math]::Min($read, $streamCap - $reader.Data.Length)
                    if ($keep -gt 0)
                    {
                        $reader.Data.Write($reader.Buffer, 0, $keep)
                    }

                    $reader.Task = $reader.Stream.ReadAsync($reader.Buffer, 0, $readSize)
                }
            }

            if ($null -eq $status)
            {
                $remaining = [int] [System.Math]::Max(0, [System.Math]::Ceiling($deadline - $stopwatch.Elapsed.TotalMilliseconds))
                if ($process.WaitForExit($remaining))
                {
                    $status = 'Exited'
                    $exitCode = $process.ExitCode
                }
                else
                {
                    $status = 'TimedOut'
                }
            }

            if ($status -eq 'HeldOutput')
            {
                foreach ($reader in $readers)
                {
                    $reader.Stream.Dispose()
                }
            }

            if ($status -ne 'Exited')
            {
                try
                {
                    $process.Kill($true)
                }
                catch
                {
                    Write-Debug -Message "Stopping process $processId failed. $($_.Exception.Message)"
                }

                if ($status -eq 'TimedOut')
                {
                    $null = $process.WaitForExit(1000)
                }
            }
        }
    }
    finally
    {
        foreach ($reader in $readers)
        {
            $reader.Stream.Dispose()
        }

        $process.Dispose()
    }

    $standardOutput = [byte[]]::new(0)
    $standardError = [byte[]]::new(0)
    if ($status -eq 'Exited')
    {
        $standardOutput = $readers[0].Data.ToArray()
        $standardError = $readers[1].Data.ToArray()
    }

    [pscustomobject] [ordered] @{
        PSTypeName          = 'CompleterActions.CompleterHelpProcessResult'
        Status              = $status
        ExitCode            = $exitCode
        StandardOutput      = $standardOutput
        StandardError       = $standardError
        ElapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        ProcessId           = $processId
        StartError          = $startError
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
a managed registration whose value PowerShell is currently using. 'Discovered'
marks a runtime value that no managed record describes. 'Pending' marks a lazy
registration whose runtime value is still the stub that loads the script on
first use.
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
        [CompleterActions.CompleterState] $State = 'Active',

        [Parameter()]
        [string] $ScriptPath,

        [Parameter()]
        [switch] $Trusted,

        [Parameter()]
        [string] $LoadError
    )

    foreach ($requiredProperty in 'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'TargetType')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $registration = [CompleterActions.CompleterRegistration]::new()
    $registration.Key = [string] $Target.Key
    $registration.RegistrationKey = [string] $Target.Key
    $registration.RuntimeKey = [string] $Target.RuntimeKey
    $registration.CommandName = [string] $Target.CommandName
    $registration.ParameterName = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
    $registration.IsNative = [bool] $Target.IsNative
    $registration.CompleterType = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
    $registration.TargetType = [string] $Target.TargetType
    $registration.Source = $Source
    $registration.State = $State
    $registration.IsManaged = $Source -eq 'Managed'
    $registration.IsRuntimeRegistered = $State -notin 'Stale', 'Failed'
    $registration.ScriptPath = if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $null } else { $ScriptPath }
    $registration.Trusted = [bool] $Trusted
    $registration.LoadError = if ([string]::IsNullOrWhiteSpace($LoadError)) { $null } else { $LoadError }
    $registration.ImportModule = $ImportModule
    $registration.ScriptBlock = $ScriptBlock
    $registration.ScriptText = $ScriptBlock.ToString()

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

    [CompleterActions.CompleterScriptFinding] @{
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

    [CompleterActions.CompletionMatch] @{
        Key            = [string] $Target.Key
        RuntimeKey     = [string] $Target.RuntimeKey
        CommandName    = [string] $Target.CommandName
        ParameterName  = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative       = [bool] $Target.IsNative
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

    [CompleterActions.ImportedCompleterRegistration] @{
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
        $removedRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $removedScriptBlock -Source 'Discovered' -State Discovered

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
Resolves the program a help probe would run and decides whether it may run.

.DESCRIPTION
Resolves the name with Get-Command -CommandType Application and takes the
first match, so a function, alias, cmdlet, or script of that name is never
chosen. The name is escaped with [WildcardPattern]::Escape, so it is matched
literally: a name with *, ?, or brackets never resolves some other program.
-ErrorAction Ignore keeps a missing command from throwing under
$ErrorActionPreference = 'Stop'. Nothing is run.

On Windows the resolved file may run only when it is a .exe whose PE header
reads as Subsystem 3 (Windows CUI). Any other file gets a reason: a GUI
program (Subsystem 2), another subsystem, an unreadable header, no file
extension, or an extension that only runs through cmd.exe. On Linux and macOS
every resolved application may run.

The warning text is returned as data; this helper writes no stream.

.PARAMETER Name
The command name to resolve, as the author gave it.

.OUTPUTS
CompleterActions.CompleterHelpProbeApplication
Returns a record with Name (as given), Path (the resolved file, or null when
nothing was found), CanRun, and Warning (the not-found or not-run text, or
null when the application may run).
#>
function Resolve-CompleterHelpProbeApplication
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $application = Get-Command -Name ([WildcardPattern]::Escape($Name)) -CommandType Application -ErrorAction Ignore | Select-Object -First 1

    $path = $null
    $warning = $null
    if ($null -eq $application)
    {
        $warning = "The command '$Name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand."
    }
    else
    {
        $path = $application.Path
        if ($IsWindows)
        {
            $extension = [System.IO.Path]::GetExtension($path)
            $reason = $null
            if ([string]::Equals($extension, '.exe', [System.StringComparison]::OrdinalIgnoreCase))
            {
                $subsystem = Get-CompleterPESubsystem -LiteralPath $path
                if ($null -eq $subsystem)
                {
                    $reason = 'its program header could not be read'
                }
                elseif ($subsystem -eq 2)
                {
                    $reason = 'it is a Windows GUI program'
                }
                elseif ($subsystem -ne 3)
                {
                    $reason = "it is not a Windows console program (subsystem $subsystem)"
                }
            }
            elseif ($extension.Length -eq 0)
            {
                $reason = 'it has no file extension'
            }
            else
            {
                $reason = "it is a $($extension.ToLowerInvariant()) file, which only runs through cmd.exe"
            }

            if ($null -ne $reason)
            {
                $warning = "'$path' was not run: $reason. Run '$Name --help' yourself and pass the text with -HelpText."
            }
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterHelpProbeApplication'
        Name       = $Name
        Path       = $path
        CanRun     = $null -ne $path -and $null -eq $warning
        Warning    = $warning
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
together with IsNative/Native. An input object describes one target, so a
CommandName or ParameterName that holds several values is rejected rather
than joined into one name. Keys are output-only identifiers, so a key
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

            foreach ($propertyName in 'CommandName', 'ParameterName')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and @($property.Value).Count -gt 1)
                {
                    throw "InputObject supplies $(@($property.Value).Count) values for $propertyName. An input object describes one target; pass arrays to -CommandName and -ParameterName instead."
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
Reconciles the records through one Resolve-CompleterRegistrationState pass,
or through the states the caller already resolved for them, and applies the
module's replacement rules in one place. Without -Force an existing managed
record blocks a registration when it is stale, when its lazy load failed, or
when it describes a different completer, and an unmanaged runtime
registration blocks it as well. A managed record that already
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
problem; Resolve-CompleterSetRegistration resolves an entry's records together and
collects the problems, so a completer set is validated against the same rules
its registrations are held to.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records that are about to be
written, in the order they will be written.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted, one is taken for this call.

.PARAMETER RegistrationState
The rows Resolve-CompleterRegistrationState already returned for these records,
one per record in the same order. When it is supplied no state pass is made
here, so a caller that resolves many batches against one snapshot can resolve
every key in one pass and hand each batch its slice.

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
        [AllowEmptyCollection()]
        [psobject[]] $RegistrationState,

        [Parameter()]
        [switch] $Force
    )

    if ($Registration.Count -eq 0)
    {
        return
    }

    $registrationStates = $RegistrationState

    if (-not $PSBoundParameters.ContainsKey('RegistrationState'))
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Key @($Registration | ForEach-Object { [string] $_.Key }) -Snapshot $Snapshot)
    }

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
                RuntimeRegistration = New-CompleterRegistrationRecord -Target $plannedRegistration -ScriptBlock $plannedRegistration.ScriptBlock -Source 'Discovered' -State Discovered
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
        $normalizedKey = $keyItem.ToLowerInvariant()
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
            $runtimeRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary -Key $storedKey) -Source 'Discovered' -State Discovered
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
Asks the compiled engine access layer (CompleterActions.Internal.EngineAccess) for the
internal execution context object behind EngineIntrinsics that owns the runtime
completer dictionaries.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

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

    try
    {
        return [CompleterActions.Internal.EngineAccess]::ResolveExecutionContext($EngineIntrinsics, $EngineIntrinsicsType)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }
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
Resolve-CompleterSetRegistration can reconcile with the session, collecting
every problem instead of stopping at the first so the caller can report all
of them at once. This is the static phase of a set import: it reads only the
entry and the file system, never the session's registrations, so its result
does not depend on what is registered. A Path that is not fully qualified, a
drive-relative form such as C:scripts\x.ps1 included, resolves against the
set file's directory rather than the current location. Trusted defaults to
false. Trusted entries must declare Targets because the script is not parsed.
Strict entries must register their targets with literal arguments so the
targets can be derived from the parsed script and, when the entry also
declares Targets, the two lists must match; the strict import grammar itself
runs when the script loads. A strict script is parsed at most once here and
the targets it yields are the ones the import registers. The script is never
executed.

The fast path skips that parse. When a strict entry has no problem so far,
declares Targets, and carries a Hash whose form Test-CompleterSetHashFormat
recognises, the script's text is hashed and compared with it. On a match the
declared Targets are used as they are, in declared order and de-duplicated by
Key with the first occurrence kept, because the export that wrote the Hash
derived those targets from the same text. An absent, unrecognised, or
different Hash, or a script that cannot be read for its hash, falls through
to the parse, so such an entry gets exactly the problems it would get with
no Hash at all. A trusted entry's Hash is ignored and its script is not read.

When ModuleBase is given, as Import-CompleterSet -Name gives it, the
resolved path must lie inside that folder, compared with a trailing separator
and with the platform's case rule (case-insensitive on Windows and macOS,
case-sensitive on Linux). An entry outside it gets the OutsideModule problem
and no existence, extension, hash, or parse check, so its file is never
opened.

Each problem is a hashtable with Kind and Message. Kind is InvalidEntry,
MissingScript, OutsideModule, UnreadableTargets, or TargetMismatch; Message
is the text Import-CompleterSet reports.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.PARAMETER Verify
Disables the fast path, so every strict entry whose script is usable is
parsed once, and records the script's actual hash and parse-derived targets
for drift checks. A trusted entry's script is read for its hash but still not
parsed.

.PARAMETER ModuleName
The installed module folder's name, used in the OutsideModule problem.

.PARAMETER ModuleBase
The full path of the module folder the entry's script must stay inside.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns a record with Index, DeclaredPath, Path, Trusted, Targets,
DeclaredHash (the entry's raw Hash value, or null), TargetSource (Trusted for
a trusted entry, Hash for a strict entry that took the fast path, Parsed for
a strict entry whose script was parsed, or null when neither applies),
ResolutionNote (the text Import-CompleterSet writes as the entry's verbose
line, or null for an entry with a problem or under -Verify), Problems, and
IsValid. Registrations and Conflicts are empty until
Resolve-CompleterSetRegistration fills them. With -Verify the record also
carries ActualHash, the Hash of the script as it is now or null when it is
missing or cannot be read (the parser's FileReadError included, whose empty
text would otherwise hash as a change), and DerivedTargets, the targets the parse derived,
empty for a trusted entry or a failed parse.
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

        [Parameter()]
        [switch] $Verify,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleBase
    )

    $problems = [System.Collections.Generic.List[hashtable]]::new()
    $moduleBasePrefix = $null
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ($PSBoundParameters.ContainsKey('ModuleBase'))
    {
        $moduleBasePrefix = $ModuleBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    }
    $declaredPath = $null
    $resolvedPath = $null
    $hasHash = $false
    $declaredHash = $null
    $actualHash = $null
    $derivedTargets = @()
    $targetSource = $null
    $resolutionNote = $null
    $scriptIsUsable = $false
    $trusted = $false
    $declaredTargets = $null
    $targets = @()

    if ($Entry -isnot [System.Collections.IDictionary])
    {
        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'The entry is not a hashtable with Path, Trusted, and Targets keys.' })
    }
    else
    {
        if ($Entry.Contains('Hash'))
        {
            $hasHash = $true
            $declaredHash = $Entry['Hash']
        }

        if (-not $Entry.Contains('Path') -or [string]::IsNullOrWhiteSpace([string] $Entry['Path']))
        {
            $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'The entry has no Path.' })
        }
        else
        {
            $declaredPath = [string] $Entry['Path']
            $resolvedPath = [System.IO.Path]::GetFullPath($declaredPath.Replace('\', '/'), $SetDirectory)

            if ($null -ne $moduleBasePrefix -and -not $resolvedPath.StartsWith($moduleBasePrefix, $pathComparison))
            {
                $problems.Add(@{ Kind = 'OutsideModule'; Message = "the script '$resolvedPath' is outside the module '$ModuleName' at '$ModuleBase'" })
            }
            elseif (-not [System.IO.File]::Exists($resolvedPath))
            {
                $problems.Add(@{ Kind = 'MissingScript'; Message = "The file '$resolvedPath' does not exist." })
            }
            elseif ([System.IO.Path]::GetExtension($resolvedPath) -ne '.ps1')
            {
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = "The file '$resolvedPath' is not a .ps1 script." })
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
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Trusted must be $true or $false.' })
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
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Each target must be a hashtable with CommandName and either Native = $true or ParameterName.' })
                        continue
                    }

                    $commandName = if ($targetEntry.Contains('CommandName')) { [string] $targetEntry['CommandName'] } else { $null }

                    if ([string]::IsNullOrWhiteSpace($commandName))
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'A target has no CommandName.' })
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
                            $problems.Add(@{ Kind = 'InvalidEntry'; Message = "Target '$commandName' must declare Native = `$true or a ParameterName." })
                        }
                    }
                    catch
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = $_.Exception.Message })
                    }
                }
            )
        }

        if ($trusted)
        {
            $targetSource = 'Trusted'

            if ($null -eq $declaredTargets)
            {
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Trusted entries must declare Targets, because a trusted script is not parsed for them.' })
            }
            else
            {
                $targets = $declaredTargets
            }

            $resolutionNote = 'trusted; targets read from the set.'

            if ($Verify -and $scriptIsUsable)
            {
                try
                {
                    $actualHash = Get-CompleterScriptHash -LiteralPath $resolvedPath
                }
                catch
                {
                    $actualHash = $null
                }
            }
        }
        elseif ($scriptIsUsable)
        {
            $hashMatches = $false

            if ($null -eq $declaredTargets)
            {
                $resolutionNote = 'no Targets; parsed the script.'
            }
            elseif (-not $hasHash)
            {
                $resolutionNote = 'no hash; parsed the script.'
            }
            elseif (-not (Test-CompleterSetHashFormat -Value $declaredHash))
            {
                $resolutionNote = 'hash not recognised; parsed the script.'
            }
            elseif ($problems.Count -eq 0 -and -not $Verify)
            {
                $resolutionNote = 'hash differs; parsed the script.'

                try
                {
                    $hashMatches = (Get-CompleterScriptHash -LiteralPath $resolvedPath) -ieq [string] $declaredHash
                }
                catch
                {
                    $hashMatches = $false
                }
            }

            if ($hashMatches)
            {
                $targetSource = 'Hash'
                $resolutionNote = 'hash matches; targets read from the set.'
                $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
                $targets = @(
                    foreach ($declaredTarget in $declaredTargets)
                    {
                        if ($seenKeys.Add([string] $declaredTarget.Key))
                        {
                            $declaredTarget
                        }
                    }
                )
            }
            else
            {
                $targetSource = 'Parsed'

                try
                {
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $resolvedPath

                    if ($Verify -and -not @($parseResult.ParseErrors | Where-Object { $_.ErrorId -eq 'FileReadError' }))
                    {
                        $actualHash = Get-CompleterScriptHash -Text $parseResult.Ast.Extent.Text
                    }

                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $resolvedPath -ParseResult $parseResult)
                }
                catch
                {
                    $problems.Add(@{ Kind = 'UnreadableTargets'; Message = $_.Exception.Message })
                }
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
                        $problems.Add(@{ Kind = 'TargetMismatch'; Message = "The declared Targets do not match the script. Declared: $declaredList. Script registers: $derivedList." })
                    }
                    else
                    {
                        $targets = $derivedTargets
                    }
                }
            }
        }
    }

    $record = [pscustomobject] [ordered] @{
        PSTypeName     = 'CompleterActions.CompleterSetEntry'
        Index          = $Index
        DeclaredPath   = $declaredPath
        Path           = $resolvedPath
        Trusted        = $trusted
        DeclaredHash   = $declaredHash
        TargetSource   = $targetSource
        ResolutionNote = if ($problems.Count -eq 0 -and -not $Verify) { $resolutionNote } else { $null }
        Targets        = @($targets)
        Registrations  = @()
        Conflicts      = @()
        Problems       = @($problems)
        IsValid        = $problems.Count -eq 0
    }

    if ($Verify)
    {
        $record | Add-Member -NotePropertyName 'ActualHash' -NotePropertyValue $actualHash
        $record | Add-Member -NotePropertyName 'DerivedTargets' -NotePropertyValue @($derivedTargets)
    }

    $record
}
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
<#
.EXTERNALHELP CompleterActions-help.xml
#>
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
<#
.SYNOPSIS
Reconciles the statically resolved entries of one completer set with the session's registrations.

.DESCRIPTION
The session phase of a set import. For each entry that
Resolve-CompleterSetEntry produced, in set order, it builds the Pending
records, one lazy stub per target, and holds them to the rules
Register-Completer applies through Resolve-CompleterRegistrationConflict
against the snapshot the whole set shares. A target that already carries a
different registration is a Conflict problem unless -Force is given, and a
target that an earlier valid entry of the same set already claimed is always
a DuplicateTarget problem. An entry with no problem claims its targets for
the entries after it. The entry's Registrations and Conflicts are what
Import-CompleterSet writes, so the session's registrations are read once per
set.

Every target of the set is reconciled with the session in one
Resolve-CompleterRegistrationState pass, in set order. Each entry's conflicts
are then decided on its own slice of that pass, so an entry is planned
exactly as if it were resolved alone and a target two entries share stays a
DuplicateTarget problem, not a conflict with the earlier entry. When no entry
resolved a target there is nothing to reconcile and no pass is made.

Each entry record is completed in place: Registrations and Conflicts are
filled, the session problems are appended after the entry's static ones, and
IsValid is recomputed.

.PARAMETER Entry
The CompleterActions.CompleterSetEntry records of one set, in set order.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot, shared by every entry of
the set, that the entries' targets are reconciled against.

.PARAMETER Force
Indicates that the set is imported with -Force, so existing registrations for
its targets are replaced rather than reported.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns each entry record, in set order, with Registrations, the Conflicts
resolved for them in the same order, Problems, and IsValid.
#>
function Resolve-CompleterSetRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Entry,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    $entryRegistrations = [System.Collections.Generic.List[object]]::new()
    $keys = [System.Collections.Generic.List[string]]::new()

    foreach ($entryItem in $Entry)
    {
        $registrations = @(
            foreach ($target in @($entryItem.Targets))
            {
                New-CompleterRegistrationRecord -Target $target -ScriptBlock (New-CompleterLazyStub -Key $target.Key) -Source 'Managed' -State 'Pending' -ScriptPath $entryItem.Path -Trusted:$entryItem.Trusted
            }
        )

        $entryRegistrations.Add($registrations)

        foreach ($registration in $registrations)
        {
            $keys.Add([string] $registration.Key)
        }
    }

    $registrationStates = @()

    if ($keys.Count -gt 0)
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Key $keys.ToArray() -Snapshot $Snapshot)
    }

    $claimedTargets = @{}
    $stateIndex = 0

    for ($entryIndex = 0; $entryIndex -lt $Entry.Count; $entryIndex++)
    {
        $entryItem = $Entry[$entryIndex]
        $problems = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($problem in $entryItem.Problems)
        {
            $problems.Add($problem)
        }

        $targets = @($entryItem.Targets)
        $registrations = $entryRegistrations[$entryIndex]
        $conflicts = @()

        if ($registrations.Count -gt 0)
        {
            $stateSlice = $registrationStates[$stateIndex..($stateIndex + $registrations.Count - 1)]
            $stateIndex += $registrations.Count
            $conflicts = @(Resolve-CompleterRegistrationConflict -Registration $registrations -RegistrationState $stateSlice -Force:$Force)
        }

        for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++)
        {
            $target = $targets[$targetIndex]

            if ($null -ne $conflicts[$targetIndex].Problem)
            {
                $problems.Add(@{ Kind = 'Conflict'; Message = $conflicts[$targetIndex].Problem })
            }

            if ($claimedTargets.Contains([string] $target.Key))
            {
                $problems.Add(@{ Kind = 'DuplicateTarget'; Message = "Target '$($target.RuntimeKey)' is also listed by entry $($claimedTargets[[string] $target.Key])." })
            }
        }

        if ($problems.Count -eq 0)
        {
            foreach ($target in $targets)
            {
                $claimedTargets[[string] $target.Key] = $entryItem.Index
            }
        }

        $entryItem.Registrations = $registrations
        $entryItem.Conflicts = $conflicts
        $entryItem.Problems = @($problems)
        $entryItem.IsValid = $problems.Count -eq 0
        $entryItem
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

    $resolvedKey = $RuntimeKey.ToLowerInvariant()

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
The .ps1 file to write. A relative path is resolved against the current
PowerShell location. The caller checks that the folder exists and that the
path is not a directory (New-CompleterScript step 1); the helper reports
neither case in its own words.

.PARAMETER ExpectedTarget
The target list the script must register, in order.

.PARAMETER Force
Overwrites an existing file at the path.

.OUTPUTS
System.IO.FileInfo
#>
function Save-CompleterScriptFile
<#
.EXTERNALHELP CompleterActions-help.xml
#>
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

    # Set-Content resolves against the PowerShell location, File.Move against the process directory.
    $LiteralPath = [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($LiteralPath))
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
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $temporaryPath | Where-Object IsNative | ForEach-Object { [string] $_.CommandName })
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
registration target and script block. The walk runs in the compiled
CompleterActions.Internal.StrictGrammar class; every unsupported construct it
returns is reported as a CompleterActions.CompleterScriptFinding record, in the
order the walk found it. A conforming script produces no output.

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

    try
    {
        $grammarFindings = [CompleterActions.Internal.StrictGrammar]::Test($Ast)
    }
    catch
    {
        # A static-method exception arrives wrapped in a MethodInvocationException whose
        # message names the method; the base exception carries the walk's own text.
        throw $_.Exception.GetBaseException().Message
    }

    foreach ($grammarFinding in $grammarFindings)
    {
        New-CompleterScriptFinding -Path $LiteralPath -Extent $grammarFinding.Extent -Construct $grammarFinding.Construct -Message $grammarFinding.Message -Hint $grammarFinding.Hint
    }
}
<#
.SYNOPSIS
Tests whether a set entry's Hash value has a form this module recognises.

.DESCRIPTION
Returns $true only for a string made of the prefix 'SHA256:' and 64
hexadecimal digits, compared case-insensitively. Any other value, including a
non-string, an empty string, or an unknown prefix such as 'SHA512:', returns
$false, so a reader treats the Hash as absent and falls back to parsing the
script instead of failing.

.PARAMETER Value
The Hash value read from a set entry.

.OUTPUTS
System.Boolean
#>
function Test-CompleterSetHashFormat
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [object] $Value
    )

    $Value -is [string] -and [regex]::IsMatch($Value, '\ASHA256:[0-9A-F]{64}\z', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new()
$script:CompleterHelpProbeTimeoutSeconds = 5
