<#
.SYNOPSIS
Gets completer registrations known to the module or discovered at runtime.

.DESCRIPTION
Returns completer registration records for all registrations, a specific
registration key, a native command completer, or a command parameter
completer. By default the command merges module-managed registrations with
runtime-discovered registrations and prefers the managed record when both refer
to the same target.

.PARAMETER Key
Gets the registration that matches a specific registration key.

.PARAMETER CommandName
Limits results to a specific command name for native or command-parameter
completers.

.PARAMETER ParameterName
Limits results to a specific parameter completer target.

.PARAMETER Native
Indicates that the lookup target is a native command completer instead of a
command parameter completer.

.PARAMETER ManagedOnly
Returns only registrations tracked by this module.

.PARAMETER DiscoveredOnly
Returns only registrations discovered from the current PowerShell runtime.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-CompleterRegistration -ManagedOnly

Lists only completer registrations that were registered through this module.
#>
function Get-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
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
        [switch] $Native,

        [Parameter()]
        [switch] $ManagedOnly,

        [Parameter()]
        [switch] $DiscoveredOnly
    )

    if ($ManagedOnly -and $DiscoveredOnly)
    {
        throw 'ManagedOnly and DiscoveredOnly cannot be used together.'
    }

    $managedRegistrations = @()
    $discoveredRegistrations = @()

    if (-not $DiscoveredOnly)
    {
        $managedRegistrations = switch ($PSCmdlet.ParameterSetName)
        {
            'All' { @(Find-ManagedCompleterRegistration) }
            'ByKey' { @(Find-ManagedCompleterRegistration -Key $Key) }
            'Native' { @(Find-ManagedCompleterRegistration -CommandName $CommandName -Native) }
            'CommandParameter' { @(Find-ManagedCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName) }
        }
    }

    if (-not $ManagedOnly)
    {
        $discoveredRegistrations = switch ($PSCmdlet.ParameterSetName)
        {
            'All' { @(Find-RuntimeCompleterRegistration) }
            'ByKey' { @(Find-RuntimeCompleterRegistration -Key $Key) }
            'Native' { @(Find-RuntimeCompleterRegistration -CommandName $CommandName -Native) }
            'CommandParameter' { @(Find-RuntimeCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName) }
        }
    }

    $registrationsByKey = [ordered] @{}

    foreach ($registration in $managedRegistrations)
    {
        if ($null -eq $registration)
        {
            continue
        }

        $registrationsByKey[[string] $registration.Key] = $registration
    }

    foreach ($registration in $discoveredRegistrations)
    {
        if ($null -eq $registration)
        {
            continue
        }

        if (-not $registrationsByKey.Contains([string] $registration.Key))
        {
            $registrationsByKey[[string] $registration.Key] = $registration
        }
    }

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
<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers a native or command-parameter argument completer with
Register-ArgumentCompleter and records the registration in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them.

.PARAMETER CommandName
Specifies the command name whose completer should be registered.

.PARAMETER ParameterName
Specifies the parameter name for a command-parameter completer registration.

.PARAMETER Native
Registers a native completer for the command instead of a parameter completer.

.PARAMETER ScriptBlock
Provides the completer script block to register.

.PARAMETER Force
Removes an existing managed or runtime registration for the same target before
registering the new completer.

.PARAMETER PassThru
Returns the managed registration record that was created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns a CompleterActions.CompleterRegistration record.

.EXAMPLE
PS> Register-CompleterRegistration -CommandName 'Test-Tool' -ParameterName 'Name' -ScriptBlock {
>>     param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
>>     [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
>> }

Registers a managed parameter completer for the Name parameter on Test-Tool.

.EXAMPLE
PS> Register-CompleterRegistration -CommandName 'git' -Native -ScriptBlock $nativeCompleter -Force -PassThru

Replaces any existing native completer registration for git and returns the new
managed registration record.
#>
function Register-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
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
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    $target = if ($PSCmdlet.ParameterSetName -eq 'Native')
    {
        Resolve-CompleterTarget -CommandName $CommandName -Native
    }
    else
    {
        Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
    }

    $existingManagedRegistration = Find-ManagedCompleterRegistration -Key $target.Key
    $existingRuntimeRegistration = Find-RuntimeCompleterRegistration -Key $target.Key

    if ($null -ne $existingManagedRegistration -and -not $Force)
    {
        if ($existingManagedRegistration.ScriptText -eq $ScriptBlock.ToString())
        {
            if ($PassThru)
            {
                return $existingManagedRegistration
            }

            return
        }

        throw "A module-managed completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if ($null -eq $existingManagedRegistration -and $null -ne $existingRuntimeRegistration -and -not $Force)
    {
        throw "A runtime completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
    {
        return
    }

    if ($Force)
    {
        if ($null -ne $existingManagedRegistration)
        {
            $null = Remove-ManagedCompleterRegistration -Key $target.Key
        }

        if ($null -ne $existingRuntimeRegistration)
        {
            $null = Remove-RuntimeCompleterRegistration -Key $target.Key
        }
    }

    if ($target.IsNative)
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -Native -ScriptBlock $ScriptBlock
    }
    else
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -ParameterName $target.ParameterName -ScriptBlock $ScriptBlock
    }

    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $ScriptBlock -Source 'Managed'
    $registration = Add-ManagedCompleterRegistration -Registration $registration

    if ($PassThru)
    {
        return $registration
    }
}
<#
.SYNOPSIS
Removes a completer registration from runtime and, when applicable, module state.

.DESCRIPTION
Removes a completer registration identified by registration key, native command,
or command parameter target. Managed registrations are removed from both the
PowerShell runtime and the module's registration table. Runtime-only
registrations require -AllowUnmanaged before they can be removed.

.PARAMETER Key
Removes the registration that matches a specific registration key.

.PARAMETER CommandName
Specifies the command name whose completer should be removed.

.PARAMETER ParameterName
Specifies the parameter name for a command-parameter completer removal target.

.PARAMETER Native
Targets a native completer registration instead of a command parameter
completer.

.PARAMETER AllowUnmanaged
Allows removal of a runtime registration that is not tracked by this module.

.PARAMETER PassThru
Returns the registration record that was removed.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns the removed CompleterActions.CompleterRegistration
record.

.EXAMPLE
PS> Unregister-CompleterRegistration -CommandName 'Test-Tool' -ParameterName 'Name' -Confirm:$false

Removes the managed parameter completer for Test-Tool Name without prompting.

.EXAMPLE
PS> Unregister-CompleterRegistration -CommandName 'git' -Native -AllowUnmanaged -Confirm:$false -PassThru

Removes a native runtime completer for git even if it was not registered
through this module, and returns the removed record.
#>
function Unregister-CompleterRegistration
<#
.EXTERNALHELP CompleterActions-help.xml
#>
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByKey', ConfirmImpact = 'Medium')]
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
        [switch] $Native,

        [Parameter()]
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    $lookup = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -Key $Key
                Runtime = Find-RuntimeCompleterRegistration -Key $Key
            }
            break
        }

        'Native'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -CommandName $CommandName -Native
                Runtime = Find-RuntimeCompleterRegistration -CommandName $CommandName -Native
            }
            break
        }

        'CommandParameter'
        {
            [ordered] @{
                Managed = Find-ManagedCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName
                Runtime = Find-RuntimeCompleterRegistration -CommandName $CommandName -ParameterName $ParameterName
            }
            break
        }
    }

    $managedRegistration = $lookup['Managed']
    $runtimeRegistration = $lookup['Runtime']
    if ($null -ne $managedRegistration)
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
        $registrationToRemove = $null
    }

    if ($null -eq $registrationToRemove)
    {
        throw 'No completer registration was found for the requested target.'
    }

    if (-not $PSCmdlet.ShouldProcess($registrationToRemove.RuntimeKey, 'Unregister completer registration'))
    {
        return
    }

    $removedRuntimeRegistration = $null
    $removedManagedRegistration = $null

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
        if ($null -ne $removedManagedRegistration)
        {
            return $removedManagedRegistration
        }

        return $removedRuntimeRegistration
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

        $registrations = Get-ManagedCompleterRegistrationTable
        $registrations[[string] $Registration.Key] = $Registration

        return $registrations[[string] $Registration.Key]
    }
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

    if ($null -eq $dictionary -or -not $dictionary.ContainsKey($target.RuntimeKey))
    {
        return
    }

    return New-CompleterRegistrationRecord -Target $target -ScriptBlock $dictionary[$target.RuntimeKey] -Source 'Discovered'
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
    $engineIntrinsicsField = [System.Management.Automation.EngineIntrinsics].GetField('_context', $bindingFlags)

    if ($null -eq $engineIntrinsicsField)
    {
        throw 'Unable to access the PowerShell execution context field required for completer runtime discovery.'
    }

    $runtimeExecutionContext = $engineIntrinsicsField.GetValue($ExecutionContext)

    if ($null -eq $runtimeExecutionContext)
    {
        throw 'Unable to resolve the current PowerShell execution context.'
    }

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
        CustomArgumentCompleters = $customArgumentCompletersProperty.GetValue($runtimeExecutionContext)
        NativeArgumentCompleters = $nativeArgumentCompletersProperty.GetValue($runtimeExecutionContext)
    }

    return $runtime
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
        [string] $Source = 'Managed'
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
        IsManaged           = $Source -eq 'Managed'
        IsRuntimeRegistered = $true
        ScriptBlock         = $ScriptBlock
        ScriptText          = $ScriptBlock.ToString()
    }

    return $registration
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

    if (-not $dictionary.ContainsKey($target.RuntimeKey))
    {
        return
    }

    $removedRegistration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $dictionary[$target.RuntimeKey] -Source 'Discovered'
    $dictionary.Remove($target.RuntimeKey)

    return $removedRegistration
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
