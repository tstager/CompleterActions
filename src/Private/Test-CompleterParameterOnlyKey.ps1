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
