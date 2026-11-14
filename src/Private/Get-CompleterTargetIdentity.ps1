<#
.SYNOPSIS
Returns the string that identifies one completer target, kind included.

.DESCRIPTION
A target's Key is its command name for a native completer and
'Command:Parameter' for a parameter completer, folded to lowercase. A native
command whose name contains a colon, such as an alias named 'Get-Thing:Name',
therefore has the same Key as the parameter target Get-Thing / Name, although
PowerShell keeps the two in separate runtime dictionaries and completes them
independently. The Key alone cannot tell them apart, so the module never uses
it as an identity: the managed registration table is keyed by this identity,
and every lookup, deduplication, and removal compares it.

The identity is the target kind, 'native' or 'parameter', a colon, and the
lowercase Key. The kind never contains a colon, so the first colon ends it and
an identity of one kind never equals an identity of the other.

.PARAMETER Target
A completer target or registration record. It must expose Key and IsNative.

.OUTPUTS
System.String
Returns the identity, such as 'native:git' or 'parameter:get-item:path'.

.EXAMPLE
PS> Get-CompleterTargetIdentity -Target (Resolve-CompleterTarget -CommandName 'Get-Item' -ParameterName 'Path')

Returns 'parameter:get-item:path'.
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

    foreach ($requiredProperty in 'Key', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $kind = if ($Target.IsNative) { 'native' } else { 'parameter' }

    return '{0}:{1}' -f $kind, ([string] $Target.Key).ToLowerInvariant()
}
