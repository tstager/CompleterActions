<#
.SYNOPSIS
Returns the string that identifies one completer target, kind included.

.DESCRIPTION
PowerShell keeps native and parameter completers in two runtime dictionaries,
each comparing its keys ordinally ignoring case. A target is therefore its kind
together with its RuntimeKey, the command name of a native completer or
'Command:Parameter' of a parameter completer, and two targets are the same
exactly when the runtime would store them under one entry.

The target's Key cannot stand in for that. It is the RuntimeKey folded to
lowercase, so a native command whose name contains a colon, such as an alias
named 'Get-Thing:Name', has the same Key as the parameter target Get-Thing /
Name, and the folding also merges names the runtime keeps apart: the Kelvin
sign (U+212A) lowercases to the letter k, yet the runtime holds 'Kelvin'
spelled with it and 'kelvin' as two entries.

The identity is the target kind, 'native' or 'parameter', a colon, and the
RuntimeKey with its casing kept. The kind never contains a colon, so the first
colon ends it and an identity of one kind never equals an identity of the
other. Identities compare as the runtime compares its keys, ordinally ignoring
case. A PowerShell hashtable literal, @{} or [ordered] @{}, already compares its
keys that way; any other collection of identities is built with
[System.StringComparer]::OrdinalIgnoreCase, and a single comparison uses
[string]::Equals with OrdinalIgnoreCase. PowerShell's -eq, -contains, and -in
operators compare culture-aware, which treats the Kelvin sign as K, so they are
never used on identities.

.PARAMETER Target
A completer target or registration record. It must expose RuntimeKey and
IsNative.

.OUTPUTS
System.String
Returns the identity, such as 'native:git' or 'parameter:Get-Item:Path'.

.EXAMPLE
PS> Get-CompleterTargetIdentity -Target (Resolve-CompleterTarget -CommandName 'Get-Item' -ParameterName 'Path')

Returns 'parameter:Get-Item:Path'.
#>
function Get-CompleterTargetIdentity
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $kind = if ($Target.IsNative) { 'native' } else { 'parameter' }

    return '{0}:{1}' -f $kind, [string] $Target.RuntimeKey
}
