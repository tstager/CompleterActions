<#
.SYNOPSIS
Finds managed completer registrations from module state.

.DESCRIPTION
Returns registration records from the module's in-memory registration table.
Callers can enumerate all records, look up the record of a target or of
another record, or look up a record by command and parameter target details.
Every lookup names the target kind, because a native target and a parameter
target can share a Key; the table is keyed by Get-CompleterTargetIdentity.

.PARAMETER Target
The completer target or registration record whose managed record to retrieve.
It must expose Key and IsNative.

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
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

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

    $lookupTarget = switch ($PSCmdlet.ParameterSetName)
    {
        'Target' { $Target }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
    }

    $identity = Get-CompleterTargetIdentity -Target $lookupTarget

    if (-not $registrations.Contains($identity))
    {
        return
    }

    return $registrations[$identity]
}
