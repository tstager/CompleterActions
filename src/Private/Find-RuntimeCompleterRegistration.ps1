<#
.SYNOPSIS
Finds completer registrations from the live PowerShell runtime dictionaries.

.DESCRIPTION
Queries the current session's runtime completer dictionaries and returns
registration records for discovered entries. Maintainers use this helper to
inspect the registrations that PowerShell is actually using, rather than only
the module's cached or intended state.

The lookup can enumerate all discovered registrations, or resolve one
command-parameter or native target, named by its parts or by a target or
record. A lookup searches only the runtime dictionary of the target's kind, so
a native command whose name has the same key as a parameter target, such as
'Get-Thing:Name' and Get-Thing / Name, never resolves to the other's entry.
The record carries the key casing the dictionary stores. Because the
underlying data comes from PowerShell runtime internals, the result represents
the current session only and depends on internal dictionary shapes remaining
stable.

A completer registered with Register-ArgumentCompleter -ParameterName alone,
without -CommandName, sits in the custom dictionary under the bare parameter
name. The module does not manage that target kind, so enumeration skips such
entries with a verbose message and parameter lookups never match them; they
cannot abort discovery of the supported targets.

.PARAMETER Target
The completer target or registration record to look up. It must expose
RuntimeKey and IsNative.

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
Find-RuntimeCompleterRegistration -Target $registration

Looks up the live runtime registration for the target of a managed record, in
the dictionary of that record's kind.

.NOTES
This helper reads PowerShell's live completer dictionaries through
Get-CompleterRuntime, which depends on runtime internals. Treat the discovered
results as implementation details for maintainers, not as a stable public
contract.
#>
function Find-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject], [System.Collections.Generic.List[object]])]
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

    $isNative = [bool] $lookupTarget.IsNative
    $dictionary = if ($isNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

    if ($null -eq $dictionary)
    {
        return
    }

    foreach ($entryKey in @($dictionary.Keys))
    {
        if ([string]::Equals([string] $entryKey, [string] $lookupTarget.RuntimeKey, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $storedTarget = if ($isNative) { Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) -Native } else { Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) }

            return New-CompleterRegistrationRecord -Target $storedTarget -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $entryKey)) -Source 'Discovered' -State Discovered
        }
    }
}
