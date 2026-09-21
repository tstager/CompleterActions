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
        [CompleterState[]] $State
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
