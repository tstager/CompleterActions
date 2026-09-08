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
