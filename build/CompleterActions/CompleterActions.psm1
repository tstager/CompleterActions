<#
.SYNOPSIS
Gets completer registrations known to the module or discovered at runtime.

.DESCRIPTION
Returns completer registration records for all registrations, specific
registration keys, native command completers, or command parameter completers.
By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target and the managed record still matches the live runtime value.
When the runtime registration was replaced outside this module, the live
discovered value is returned with State 'Conflicted' instead; -ManagedOnly
returns the managed record with State 'Stale'. When the runtime registration
was removed outside this module, the managed record is returned with State
'Stale' and IsRuntimeRegistered false. The command accepts arrays for key,
command, and parameter lookup scenarios and supports property-name pipeline
binding for key-based and target-based lookups.

.PARAMETER Key
Gets the registrations that match one or more registration keys. A key without
a colon is treated as a native command. A key with a colon is treated as a
'Command:Parameter' target unless the text after its last colon contains a
path separator, in which case it is treated as a native command path such as
'C:\tools\example.exe'. Use -CommandName with -Native or -ParameterName when
the key shape is ambiguous.

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
'Active' for records that describe the live runtime value, 'Stale' for managed
records that no longer match the runtime, and 'Conflicted' for live runtime
values that replaced a managed registration outside this module.

.EXAMPLE
PS> Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-CompleterRegistration -Key 'git:checkout', 'git:branch'

Gets multiple completer registrations by key in a single call.
#>
function Get-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('RegistrationKey')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

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
            if ($PSCmdlet.ParameterSetName -ne 'All')
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'ByKey'
                    {
                        $targetParameters['Key'] = $Key
                        break
                    }

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

                if ($registrationState.ManagedState -eq 'Active')
                {
                    $registrationsByKey[[string] $registration.Key] = $registration
                }
                elseif ($ManagedOnly -or $null -eq $registrationState.RuntimeRegistration)
                {
                    $registrationsByKey[[string] $registration.Key] = New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -ImportModule $registration.ImportModule -State 'Stale'
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

                    if ($registrationState.ManagedState -eq 'Active')
                    {
                        continue
                    }

                    if ($registrationState.ManagedState -eq 'Stale')
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
.SYNOPSIS
Imports self-contained completer scripts into registration input objects.

.DESCRIPTION
Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows Register-ArgumentCompleter, and emits objects that
can be piped directly to Register-CompleterRegistration -InputObject.

Import-CompleterScript is safe by default for supported script shapes: it rejects
unsupported Register-ArgumentCompleter patterns during AST validation and avoids
mutating the live runtime completer tables during import. Imported ScriptBlock
objects keep the temporary module context that contains helper functions and
script-scope state defined by the source script.

Compatible completer scripts must be self-contained and must keep script scope
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

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.ImportedCompleterRegistration records compatible with
Register-CompleterRegistration -InputObject.

.EXAMPLE
PS> Import-CompleterScript -Path .\7z_completer.ps1 | Register-CompleterRegistration -PassThru

Imports a supported completer script and immediately registers the imported
completer definitions through the module's managed registration API.

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
        [string[]] $LiteralPath
    )

    process
    {
        $resolvedPaths = @()

        try
        {
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
                    throw "Completer script imports require a file path. '$resolvedPath' is a directory."
                }

                if ($file.Extension -ne '.ps1')
                {
                    throw "Completer script imports require .ps1 files. Received '$resolvedPath'."
                }

                $parseResult = Get-CompleterScriptParseResult -LiteralPath $file.FullName
                $null = Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $file.FullName
                $importSession = Import-CompleterScriptDefinition -LiteralPath $file.FullName

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
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $file.FullName -ImportModule $importSession.Module)
                        )
                    }
                }
            }
        }
        catch
        {
            throw "Failed to import completer script. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedPaths = @()
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

.PARAMETER InputObject
Supplies one or more objects that describe completer targets. Input objects must
expose target metadata through Key, RegistrationKey, RuntimeKey, or
CommandName/ParameterName plus IsNative/Native, and must expose a ScriptBlock
property whose value is a script block. When only a key is supplied and no
IsNative/Native property is present, a key without a colon is treated as a
native command, and a key with a colon is treated as a 'Command:Parameter'
target unless the text after its last colon contains a path separator, in which
case it is treated as a native command path such as 'C:\tools\example.exe'. An
explicit IsNative/Native property always wins.

.PARAMETER CommandName
Specifies one or more command names whose completers should be registered.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer
registrations.

.PARAMETER Native
Registers native completers for the commands instead of parameter completers.

.PARAMETER ScriptBlock
Provides the completer script block to register. When multiple targets are
supplied through arrays, the same script block is reused for each target.

.PARAMETER Force
Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value was
changed outside this module.

.PARAMETER PassThru
Returns the managed registration records that were created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns CompleterActions.CompleterRegistration records.
#>
function Register-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject[]] $InputObject,

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

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedInputs = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedInputs = @($InputObject | Resolve-CompleterInputObject -RequireScriptBlock)
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
                    }
                }
            }

            foreach ($resolvedInput in $resolvedInputs)
            {
                $target = $resolvedInput.Target
                $targetScriptBlock = $resolvedInput.ScriptBlock
                $targetImportModule = $resolvedInput.ImportModule
                $existingManagedRegistration = $null
                $existingRuntimeRegistration = $null
                $registration = $null
                $rollbackError = $null

                try
                {
                    $registrationState = Resolve-CompleterRegistrationState -Key $target.Key
                    $existingManagedRegistration = $registrationState.ManagedRegistration
                    $existingRuntimeRegistration = $registrationState.RuntimeRegistration

                    if ($null -ne $existingManagedRegistration -and -not $Force)
                    {
                        if ($registrationState.ManagedState -eq 'Stale')
                        {
                            throw "The module-managed completer registration for '$($target.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
                        }

                        if ($existingManagedRegistration.ScriptText -eq $targetScriptBlock.ToString())
                        {
                            if ($PassThru)
                            {
                                $PSCmdlet.WriteObject($existingManagedRegistration)
                            }

                            continue
                        }

                        throw "A module-managed completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
                    }

                    if ($null -eq $existingManagedRegistration -and $null -ne $existingRuntimeRegistration -and -not $Force)
                    {
                        throw "A runtime completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
                    }

                    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
                    {
                        continue
                    }

                    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $targetScriptBlock -Source 'Managed' -ImportModule $targetImportModule

                    try
                    {
                        $null = Add-RuntimeCompleterRegistration -Target $target -ScriptBlock $targetScriptBlock
                        $registration = Add-ManagedCompleterRegistration -Registration $registration
                    }
                    catch
                    {
                        try
                        {
                            if ($null -ne $existingRuntimeRegistration)
                            {
                                $null = Add-RuntimeCompleterRegistration -Target $existingRuntimeRegistration -ScriptBlock $existingRuntimeRegistration.ScriptBlock
                            }
                            else
                            {
                                $null = Remove-RuntimeCompleterRegistration -Key $target.Key
                            }

                            if ($null -ne $existingManagedRegistration)
                            {
                                $null = Add-ManagedCompleterRegistration -Registration $existingManagedRegistration
                            }
                            else
                            {
                                $null = Remove-ManagedCompleterRegistration -Key $target.Key
                            }
                        }
                        catch
                        {
                            $rollbackError = $_
                        }

                        throw
                    }

                    if ($PassThru)
                    {
                        $PSCmdlet.WriteObject($registration)
                    }
                }
                catch
                {
                    if ($null -ne $rollbackError)
                    {
                        throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message) Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($rollbackError.Exception.Message)"
                    }

                    throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $existingManagedRegistration = $null
                    $existingRuntimeRegistration = $null
                    $registration = $null
                    $rollbackError = $null
                    $targetImportModule = $null
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
Removes completer registrations from runtime and, when applicable, module state.

.DESCRIPTION
Removes completer registrations identified by registration key, native command,
command parameter target, or pipeline InputObject values. Managed registrations
are removed from both the PowerShell runtime and the module's registration
table. Runtime-only registrations require -AllowUnmanaged before they can be
removed. The same gate applies when a managed record is stale because the
runtime registration was replaced outside this module: the live value is only
removed with -AllowUnmanaged, and the stale managed record is dropped with it.
When the runtime registration was already removed outside this module, only
the stale managed record remains and it is removed without the gate. The
command supports array inputs for keys and target fields, plus pipeline input
from Get-CompleterRegistration output.

.PARAMETER InputObject
Supplies one or more objects that describe registrations to remove. Input
objects can expose Key, RegistrationKey, RuntimeKey, or
CommandName/ParameterName plus IsNative/Native.

.PARAMETER Key
Removes the registrations that match one or more registration keys. A key
without a colon is treated as a native command. A key with a colon is treated
as a 'Command:Parameter' target unless the text after its last colon contains
a path separator, in which case it is treated as a native command path such as
'C:\tools\example.exe'. Use -CommandName with -Native or -ParameterName when
the key shape is ambiguous.

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
function Unregister-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByKey', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('RegistrationKey')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

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
                    'ByKey'
                    {
                        $targetParameters['Key'] = $Key
                        break
                    }

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

                    if ($registrationState.ManagedState -eq 'Active')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($registrationState.ManagedState -eq 'Stale' -and $null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The module-managed completer registration for '$($runtimeRegistration.RuntimeKey)' is stale: the runtime registration was replaced outside this module. Re-run with -AllowUnmanaged to remove the live runtime registration and the stale managed record."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    elseif ($registrationState.ManagedState -eq 'Stale')
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
                foreach ($entry in $runtime.NativeArgumentCompleters.GetEnumerator())
                {
                    if ((Get-CompleterRegistrationKey -RuntimeKey ([string] $entry.Key)) -eq $normalizedKey)
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key) -Native) -ScriptBlock $entry.Value -Source 'Discovered'
                    }
                }
            }

            if ($null -ne $runtime.CustomArgumentCompleters)
            {
                foreach ($entry in $runtime.CustomArgumentCompleters.GetEnumerator())
                {
                    if ((Get-CompleterRegistrationKey -RuntimeKey ([string] $entry.Key)) -eq $normalizedKey)
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key)) -ScriptBlock $entry.Value -Source 'Discovered'
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
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope.

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

    if ($parseErrors.Count -gt 0)
    {
        $errorSummary = @($parseErrors |
            Select-Object -First 3 |
            ForEach-Object {
                'line {0}, column {1}: {2}' -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
            }) -join '; '

        throw "Completer script '$LiteralPath' could not be parsed. $errorSummary"
    }

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
target script can run without mutating the live runtime completer tables. The
captured registration definitions preserve the imported script block behavior and
module scope so helper functions and script state remain available later.

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
                    $capturedScriptBlock = $ExecutionContext.SessionState.InvokeCommand.NewScriptBlock($ScriptBlock.ToString())

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
Creates an internal completer registration record object.

.DESCRIPTION
Builds the PSCustomObject stored in the managed registration table. The helper
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
the value PowerShell is currently using. 'Stale' marks a managed record whose
stored script no longer matches the runtime because the target was replaced or
removed outside this module. 'Conflicted' marks a discovered runtime value that
shadows a stale managed record for the same target.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns a CompleterActions.CompleterRegistration record suitable for internal storage.

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
    [OutputType([pscustomobject])]
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
        [ValidateSet('Active', 'Stale', 'Conflicted')]
        [string] $State = 'Active'
    )

    foreach ($requiredProperty in 'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'TargetType')
    {
        if ($Target.PSObject.Properties.Match($requiredProperty).Count -eq 0)
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $registration = [pscustomobject] [ordered] @{
        PSTypeName          = 'CompleterActions.CompleterRegistration'
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
        IsRuntimeRegistered = $State -ne 'Stale'
        ImportModule        = $ImportModule
        ScriptBlock         = $ScriptBlock
        ScriptText          = $ScriptBlock.ToString()
    }

    return $registration
}
<#
.SYNOPSIS
Creates a Register-CompleterRegistration-compatible import object.

.DESCRIPTION
Builds the public object emitted by Import-CompleterScript. The resulting object
captures normalized target metadata plus the imported ScriptBlock object from the
temporary import module so callers can pipe it directly into
Register-CompleterRegistration -InputObject.

.PARAMETER Target
The normalized completer target metadata.

.PARAMETER ScriptBlock
The imported completer script block.

.PARAMETER SourcePath
The source completer script path.

.PARAMETER ImportModule
The temporary module that owns the imported script block context.

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
    [OutputType([pscustomobject])]
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
        [System.Management.Automation.PSModuleInfo] $ImportModule
    )

    [pscustomobject] [ordered] @{
        PSTypeName      = 'CompleterActions.ImportedCompleterRegistration'
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
registration records and custom objects that expose either key-based target
properties or command/parameter metadata.

.PARAMETER InputObject
The object to resolve into a completer target.

.PARAMETER RequireScriptBlock
Requires the input object to expose a ScriptBlock property whose value is a
script block.

.OUTPUTS
CompleterActions.ResolvedInputObject

.EXAMPLE
Resolve-CompleterInputObject -InputObject $registration

Resolves a completer registration object returned by Get-CompleterRegistration
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
        $runtimeKey = $null
        $commandName = $null
        $parameterName = $null
        $hasNativeIndicator = $false
        $isNative = $false
        $scriptBlock = $null
        $importModule = $null
        $target = $null

        try
        {
            foreach ($propertyName in 'Key', 'RegistrationKey', 'RuntimeKey')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                {
                    if ($propertyName -eq 'RuntimeKey')
                    {
                        $runtimeKey = [string] $property.Value
                    }
                    else
                    {
                        $keyValue = [string] $property.Value
                    }

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
            elseif (-not [string]::IsNullOrWhiteSpace($runtimeKey))
            {
                if ($hasNativeIndicator -and $isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $runtimeKey -Native
                }
                elseif ($hasNativeIndicator -and -not $isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $runtimeKey
                }
                elseif (Test-CompleterNativeKeyShape -Key $runtimeKey)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $runtimeKey -Native
                }
                else
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $runtimeKey
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($keyValue))
            {
                if ($hasNativeIndicator -and $isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue -Native
                }
                elseif ($hasNativeIndicator -and -not $isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue
                }
                elseif (Test-CompleterNativeKeyShape -Key $keyValue)
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
                throw 'InputObject must expose Key, RegistrationKey, RuntimeKey, or CommandName.'
            }

            [pscustomobject] [ordered] @{
                PSTypeName = 'CompleterActions.ResolvedInputObject'
                InputObject = $InputObject
                Target = $target
                ScriptBlock = $scriptBlock
                ImportModule = $importModule
            }
        }
        catch
        {
            throw "Failed to resolve a completer target from InputObject. $($_.Exception.Message)"
        }
        finally
        {
            $keyValue = $null
            $runtimeKey = $null
            $commandName = $null
            $parameterName = $null
            $scriptBlock = $null
            $importModule = $null
            $target = $null
        }
    }
}
<#
.SYNOPSIS
Reconciles a managed registration record with the live runtime value for a target.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for a
normalized key and reports whether the managed record still describes what
PowerShell is actually using. A managed record is authoritative only while the
runtime holds the same script block, or a script block with identical text.
When the runtime value was replaced or removed outside this module, the managed
record is reported as stale so public commands can surface the live value,
refuse silent reuse, and apply the unmanaged-removal gate.

.PARAMETER Key
The normalized or runtime key for the completer target to reconcile.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns an object with ManagedRegistration, RuntimeRegistration, and
ManagedState ('None', 'Active', or 'Stale') properties. The registration
properties hold the exact stored objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Key 'get-item:path'

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.
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
        [string] $Key
    )

    $managedRegistration = Find-ManagedCompleterRegistration -Key $Key
    $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $Key

    $managedState = if ($null -eq $managedRegistration)
    {
        'None'
    }
    elseif ($null -ne $runtimeRegistration -and
        ([object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock) -or
            $managedRegistration.ScriptText -eq $runtimeRegistration.ScriptText))
    {
        'Active'
    }
    else
    {
        'Stale'
    }

    return [pscustomobject] [ordered] @{
        Key                 = $Key
        ManagedRegistration = $managedRegistration
        RuntimeRegistration = $runtimeRegistration
        ManagedState        = $managedState
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

.PARAMETER Key
One or more normalized or runtime keys to resolve.

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
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

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
        'ByKey'
        {
            foreach ($keyItem in $Key)
            {
                if (Test-CompleterNativeKeyShape -Key $keyItem)
                {
                    Resolve-CompleterTarget -RuntimeKey $keyItem -Native
                    continue
                }

                Resolve-CompleterTarget -RuntimeKey $keyItem
            }

            break
        }

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
Determines whether a key-only input should be treated as a native completer target.

.DESCRIPTION
Applies the module's shared rule for classifying a key when no explicit native
indicator is available. A key without a colon is a native command name. A key
with a colon is still native when the text after its last colon contains a path
separator, because a 'Command:Parameter' key never contains a path separator in
its parameter part; this covers drive-qualified paths such as
'C:\tools\example.exe' with either separator. Every other colon-bearing key,
including a drive-qualified path followed by ':Parameter', is a
command-parameter target.

.PARAMETER Key
The registration or runtime key to classify.

.OUTPUTS
System.Boolean
Returns $true when the key should be resolved as a native completer target.

.EXAMPLE
Test-CompleterNativeKeyShape -Key 'C:\tools\example.exe'

Returns $true because the key is a drive-qualified native path.

.EXAMPLE
Test-CompleterNativeKeyShape -Key 'Get-Item:Path'

Returns $false because the key is a command-parameter key.

.NOTES
Resolve-CompleterTargetList and Resolve-CompleterInputObject both use this
helper so key-only inputs classify identically on every public path.
#>
function Test-CompleterNativeKeyShape
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

    if ($Key -notmatch ':')
    {
        return $true
    }

    $parameterPart = $Key.Substring($Key.LastIndexOf(':') + 1)

    return $parameterPart.IndexOfAny([char[]] @('\', '/')) -ge 0
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
registration target and script block.

.PARAMETER Ast
The parsed script AST to validate.

.PARAMETER LiteralPath
The source path for error reporting.

.OUTPUTS
System.Boolean
#>
function Test-CompleterScriptAst
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    function Test-IsSupportedRegisterArgumentAst
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.Language.Ast] $ArgumentAst,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ParameterName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path
        )

        function Test-IsSupportedLiteralStringArrayExpressionAst
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [System.Management.Automation.Language.ArrayExpressionAst] $ExpressionAst,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $AstParameterName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $AstPath
            )

            $statementBlockAst = $ExpressionAst.SubExpression
            if ($statementBlockAst.Traps.Count -ne 0 -or $statementBlockAst.Statements.Count -ne 1)
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $pipelineAst = $statementBlockAst.Statements[0]
            if ($pipelineAst -isnot [System.Management.Automation.Language.PipelineAst] -or $pipelineAst.PipelineElements.Count -ne 1)
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $commandExpressionAst = $pipelineAst.PipelineElements[0]
            if ($commandExpressionAst -isnot [System.Management.Automation.Language.CommandExpressionAst])
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            $arrayLiteralAst = $commandExpressionAst.Expression
            if ($arrayLiteralAst -isnot [System.Management.Automation.Language.ArrayLiteralAst])
            {
                throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            foreach ($element in $arrayLiteralAst.Elements)
            {
                if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    throw "Completer script '$AstPath' must use literal string values for -$AstParameterName. Non-literal value found at line $($ExpressionAst.Extent.StartLineNumber)."
                }
            }
        }

        switch ($ParameterName)
        {
            'CommandName'
            {
                if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
                {
                    foreach ($element in $ArgumentAst.Elements)
                    {
                        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            throw "Completer script '$Path' must use literal string values for -CommandName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                        }
                    }

                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
                {
                    Test-IsSupportedLiteralStringArrayExpressionAst -ExpressionAst $ArgumentAst -AstParameterName $ParameterName -AstPath $Path
                    return
                }

                throw "Completer script '$Path' must use literal string values for -CommandName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
            }

            'ParameterName'
            {
                if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst])
                {
                    foreach ($element in $ArgumentAst.Elements)
                    {
                        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            throw "Completer script '$Path' must use literal string values for -ParameterName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                        }
                    }

                    return
                }

                if ($ArgumentAst -is [System.Management.Automation.Language.ArrayExpressionAst])
                {
                    Test-IsSupportedLiteralStringArrayExpressionAst -ExpressionAst $ArgumentAst -AstParameterName $ParameterName -AstPath $Path
                    return
                }

                throw "Completer script '$Path' must use literal string values for -ParameterName. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
            }

            'ScriptBlock'
            {
                if ($ArgumentAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst])
                {
                    throw "Completer script '$Path' must provide a literal script block for -ScriptBlock. Non-literal value found at line $($ArgumentAst.Extent.StartLineNumber)."
                }

                return
            }
        }
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
    # through them, so anything they do not recognize is rejected before the
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
                throw "Completer script '$LiteralPath' uses argument splatting at line $($ExpressionAst.Extent.StartLineNumber). Import-CompleterScript requires explicit top-level command arguments."
            }

            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
        {
            foreach ($nestedExpression in $ExpressionAst.NestedExpressions)
            {
                if ($nestedExpression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $nestedExpression.Splatted)
                {
                    throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($nestedExpression.GetType().Name)' at line $($nestedExpression.Extent.StartLineNumber)."
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
                throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($ExpressionAst.Extent.StartLineNumber)."
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
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($ExpressionAst.TokenKind)' at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Child
            return
        }

        if ($ExpressionAst -is [System.Management.Automation.Language.BinaryExpressionAst])
        {
            if ($ExpressionAst.Operator -notin $allowedTopLevelOperators)
            {
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($ExpressionAst.Operator)' at line $($ExpressionAst.Extent.StartLineNumber)."
            }

            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Left
            Test-ImportSafeExpressionAst -ExpressionAst $ExpressionAst.Right
            return
        }

        throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($ExpressionAst.GetType().Name)' at line $($ExpressionAst.Extent.StartLineNumber). Import-CompleterScript only supports literal values, variables, and simple comparisons outside function bodies and registered script blocks."
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
            throw "Completer script '$LiteralPath' uses redirection at line $($CommandExpressionAst.Extent.StartLineNumber). Import-CompleterScript does not support top-level redirection."
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
            throw "Completer script '$LiteralPath' uses redirection at line $($CommandAst.Extent.StartLineNumber). Import-CompleterScript does not support top-level redirection."
        }

        $commandName = $CommandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName))
        {
            throw "Completer script '$LiteralPath' uses a non-literal top-level command at line $($CommandAst.Extent.StartLineNumber)."
        }

        if ($allowedImportCommands -notcontains $commandName)
        {
            throw "Completer script '$LiteralPath' uses unsupported top-level command '$commandName' at line $($CommandAst.Extent.StartLineNumber)."
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
            throw "Completer script '$LiteralPath' starts a background pipeline at line $($PipelineAst.Extent.StartLineNumber). Import-CompleterScript does not support background execution."
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

                throw "Completer script '$LiteralPath' contains unsupported top-level expression '$($pipelineElement.Expression.GetType().Name)' at line $($pipelineElement.Extent.StartLineNumber). Import-CompleterScript only supports Set-StrictMode, Get-Variable, and Register-ArgumentCompleter commands at script scope."
            }

            throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($pipelineElement.GetType().Name)' at line $($pipelineElement.Extent.StartLineNumber)."
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

        throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($StatementAst.GetType().Name)' at line $($StatementAst.Extent.StartLineNumber)."
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
                    throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($clause.Item1.GetType().Name)' at line $($clause.Item1.Extent.StartLineNumber)."
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
                throw "Completer script '$LiteralPath' uses a top-level assignment at line $($StatementAst.Extent.StartLineNumber). Import-CompleterScript only supports assignments inside importer-safe if statements."
            }

            if ($StatementAst.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals)
            {
                throw "Completer script '$LiteralPath' uses unsupported top-level operator '$($StatementAst.Operator)' at line $($StatementAst.Extent.StartLineNumber)."
            }

            $target = $StatementAst.Left
            if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $target.Splatted -or
                -not ($target.VariablePath.IsUnqualified -or $target.VariablePath.IsScript))
            {
                throw "Completer script '$LiteralPath' assigns to unsupported target '$($target.Extent.Text)' at line $($target.Extent.StartLineNumber). Import-CompleterScript only supports assignments to unqualified or script-scope variables."
            }

            Test-ImportSafeValueStatementAst -StatementAst $StatementAst.Right
            return
        }

        throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($StatementAst.GetType().Name)' at line $($StatementAst.Extent.StartLineNumber)."
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
            throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($StatementBlockAst.Traps[0].Extent.StartLineNumber)."
        }

        foreach ($statement in $StatementBlockAst.Statements)
        {
            Test-ImportSafeStatementAst -StatementAst $statement -AllowAssignment
        }
    }

    foreach ($usingStatement in @($Ast.UsingStatements))
    {
        if ($usingStatement.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Namespace)
        {
            throw "Completer script '$LiteralPath' uses a 'using $($usingStatement.UsingStatementKind.ToString().ToLowerInvariant())' statement at line $($usingStatement.Extent.StartLineNumber). Import-CompleterScript only supports 'using namespace' statements."
        }
    }

    if ($null -ne $Ast.ScriptRequirements)
    {
        if ($Ast.ScriptRequirements.RequiredModules.Count -gt 0)
        {
            throw "Completer script '$LiteralPath' uses a '#requires -Modules' directive. Import-CompleterScript does not support '#requires -Modules' because the required modules are imported, and their top-level code executes, when the script is dot-sourced."
        }

        if ($Ast.ScriptRequirements.RequiredAssemblies.Count -gt 0)
        {
            throw "Completer script '$LiteralPath' uses a '#requires -Assembly' directive. Import-CompleterScript does not support '#requires -Assembly' because the required assemblies are loaded when the script is dot-sourced."
        }
    }

    foreach ($namedBlock in @($Ast.ParamBlock, $Ast.BeginBlock, $Ast.ProcessBlock, $Ast.DynamicParamBlock, $Ast.CleanBlock))
    {
        if ($null -ne $namedBlock)
        {
            throw "Completer script '$LiteralPath' contains unsupported top-level syntax '$($namedBlock.GetType().Name)' at line $($namedBlock.Extent.StartLineNumber)."
        }
    }

    if ($Ast.EndBlock.Traps.Count -ne 0)
    {
        throw "Completer script '$LiteralPath' contains unsupported top-level syntax 'TrapStatementAst' at line $($Ast.EndBlock.Traps[0].Extent.StartLineNumber)."
    }

    foreach ($statement in @($Ast.EndBlock.Statements))
    {
        Test-ImportSafeStatementAst -StatementAst $statement
    }

    $functionOverrides = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in $allowedImportCommands
            },
            $true
        ))

    if ($functionOverrides.Count -gt 0)
    {
        $lineNumber = $functionOverrides[0].Extent.StartLineNumber
        throw "Completer script '$LiteralPath' defines its own $($functionOverrides[0].Name) function at line $lineNumber. Import-CompleterScript only supports scripts that call the built-in command name directly."
    }

    $dotSourcedCommands = @($Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            },
            $true
        ))

    if ($dotSourcedCommands.Count -gt 0)
    {
        $lineNumber = $dotSourcedCommands[0].Extent.StartLineNumber
        throw "Completer script '$LiteralPath' dot-sources another script at line $lineNumber. Import-CompleterScript only supports self-contained completer scripts."
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
        throw "Completer script '$LiteralPath' does not contain a Register-ArgumentCompleter call."
    }

    foreach ($registerCommand in $registerCommands)
    {
        $ancestor = $registerCommand.Parent
        while ($null -ne $ancestor -and $ancestor -ne $Ast)
        {
            if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
            {
                throw "Completer script '$LiteralPath' registers a completer from inside a nested function or script block at line $($registerCommand.Extent.StartLineNumber). Import-CompleterScript only supports script-scope Register-ArgumentCompleter calls."
            }

            $ancestor = $ancestor.Parent
        }

        $currentParameter = $null
        $seenParameters = [ordered] @{}

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -notin 'CommandName', 'ParameterName', 'Native', 'ScriptBlock')
                {
                    throw "Completer script '$LiteralPath' uses unsupported Register-ArgumentCompleter parameter '-$($commandElement.ParameterName)' at line $($commandElement.Extent.StartLineNumber). Supported import parameters are -CommandName, -ParameterName, -Native, and -ScriptBlock."
                }

                if ($null -ne $commandElement.Argument)
                {
                    if ($commandElement.ParameterName -eq 'Native')
                    {
                        throw "Completer script '$LiteralPath' uses an argument for -Native at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript only supports the bare -Native switch."
                    }

                    Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement.Argument -ParameterName $commandElement.ParameterName -Path $LiteralPath
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
                throw "Completer script '$LiteralPath' uses argument splatting at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript requires explicit Register-ArgumentCompleter parameters."
            }

            if ([string]::IsNullOrWhiteSpace($currentParameter))
            {
                throw "Completer script '$LiteralPath' uses positional Register-ArgumentCompleter arguments at line $($commandElement.Extent.StartLineNumber). Import-CompleterScript requires explicit parameter names."
            }

            Test-IsSupportedRegisterArgumentAst -ArgumentAst $commandElement -ParameterName $currentParameter -Path $LiteralPath
            $currentParameter = $null
        }

        if (-not [string]::IsNullOrWhiteSpace($currentParameter))
        {
            throw "Completer script '$LiteralPath' is missing the argument for -$currentParameter at line $($registerCommand.Extent.StartLineNumber)."
        }

        if (-not $seenParameters.Contains('CommandName'))
        {
            throw "Completer script '$LiteralPath' is missing -CommandName in a Register-ArgumentCompleter call at line $($registerCommand.Extent.StartLineNumber)."
        }

        if (-not $seenParameters.Contains('ScriptBlock'))
        {
            throw "Completer script '$LiteralPath' is missing -ScriptBlock in a Register-ArgumentCompleter call at line $($registerCommand.Extent.StartLineNumber)."
        }

        if ($seenParameters.Contains('Native') -and $seenParameters.Contains('ParameterName'))
        {
            throw "Completer script '$LiteralPath' combines -Native and -ParameterName at line $($registerCommand.Extent.StartLineNumber). Import-CompleterScript only supports the standard Register-ArgumentCompleter parameter sets."
        }

        if (-not $seenParameters.Contains('Native') -and -not $seenParameters.Contains('ParameterName'))
        {
            throw "Completer script '$LiteralPath' does not identify whether the completer is native or parameter-based at line $($registerCommand.Extent.StartLineNumber). Use -Native or -ParameterName."
        }
    }

    return $true
}
