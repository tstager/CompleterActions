<#
.SYNOPSIS
Resolves a Key or RegistrationKey of a given kind to the registered target it belongs to.

.DESCRIPTION
A record's Key and RegistrationKey are its RuntimeKey folded to lowercase, and
the folding merges names the runtime keeps apart: the Kelvin sign (U+212A)
lowercases to the letter k, so 'Kelvin' spelled with it and 'kelvin' have one
key but are two runtime entries. A key therefore cannot be used as a runtime
key. This helper looks for the targets of the given kind, in the managed table
and in the runtime dictionary of that kind, whose RuntimeKey folds to the key,
and returns the target of the one it finds. When the key belongs to more than
one of them it throws rather than pick one, and when it belongs to none the
key itself is taken as the runtime key, since no registered name can be meant.

.PARAMETER Key
The folded key, such as a record's Key or RegistrationKey.

.PARAMETER Native
Resolves the key among native targets instead of parameter targets.

.OUTPUTS
CompleterActions.CompleterTarget

.EXAMPLE
PS> Resolve-CompleterKeyTarget -Key 'kelvin' -Native

Returns the native target 'kelvin' or 'Kelvin', whichever one is registered,
and throws when both are.
#>
function Resolve-CompleterKeyTarget
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch selects the kind of target the key is resolved among.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [switch] $Native
    )

    $foldedKey = $Key.ToLowerInvariant()
    $runtime = Get-CompleterRuntime
    $dictionary = if ($Native) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
    $candidateKeys = @(
        if ($null -ne $dictionary)
        {
            $dictionary.Keys
        }

        foreach ($registration in @(Find-ManagedCompleterRegistration))
        {
            if ([bool] $registration.IsNative -eq [bool] $Native)
            {
                $registration.RuntimeKey
            }
        }
    )

    $matchingKeys = [System.Collections.Generic.List[string]]::new()
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($candidateKey in $candidateKeys)
    {
        $runtimeKey = [string] $candidateKey

        if ([string]::Equals($runtimeKey.ToLowerInvariant(), $foldedKey, [System.StringComparison]::Ordinal) -and $seenKeys.Add($runtimeKey))
        {
            $matchingKeys.Add($runtimeKey)
        }
    }

    $kind = if ($Native) { 'native' } else { 'parameter' }

    if ($matchingKeys.Count -gt 1)
    {
        throw "The key '$Key' belongs to $($matchingKeys.Count) registered $kind targets, $(@($matchingKeys | ForEach-Object { "'$_'" }) -join ', '), which differ in characters that lowercasing merges, so it cannot name one of them. Supply RuntimeKey, or CommandName with IsNative or ParameterName, to name the target exactly."
    }

    $runtimeKey = if ($matchingKeys.Count -eq 1) { $matchingKeys[0] } else { $Key }

    if ($Native)
    {
        return Resolve-CompleterTarget -RuntimeKey $runtimeKey -Native
    }

    return Resolve-CompleterTarget -RuntimeKey $runtimeKey
}
