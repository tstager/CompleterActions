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
Get-CompleterRegistration or Import-CompleterScript resolve through their Key
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
records returned by Get-CompleterRegistration or Import-CompleterScript. An
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
PS> Get-CompleterRegistration -CommandName 'git' -Native

Gets the registration record for the native completer currently associated with
git.

.EXAMPLE
PS> Get-CompleterRegistration -CommandName 'git' -ParameterName 'checkout', 'branch'

Gets multiple command-parameter completer registrations in a single call.

.EXAMPLE
PS> Import-CompleterScript -LiteralPath .\git_completer.ps1 | Get-CompleterRegistration

Gets the live registrations for the targets a completer script defines by
piping its import records back in.
#>
function Get-CompleterRegistration
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
