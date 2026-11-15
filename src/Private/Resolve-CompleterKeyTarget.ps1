<#
.SYNOPSIS
Resolves a Key or RegistrationKey of a given kind to the one target it can name.

.DESCRIPTION
A record's Key and RegistrationKey are its RuntimeKey folded to lowercase, and
the folding merges names the runtime keeps apart: the Kelvin sign (U+212A)
lowercases to the letter k, so 'Kelvin' spelled with it and 'kelvin' have one
key but are two runtime entries. A key therefore names only the target whose
runtime key is the key itself, compared ordinally ignoring case as the runtime
compares it, and only while no other target could be meant. This helper looks
for the targets of the given kind, in the managed table and in the runtime
dictionary of that kind, whose RuntimeKey folds to the key. When one of them
has a name the runtime keeps apart from the key, such as the Kelvin-sign
spelling for the key 'kelvin', it throws rather than pick a target: that
target and the one the key spells are both meant. Otherwise the key names the
registered target with that name, keeping its spelling, or the target the key
spells when none is registered.

.PARAMETER Key
The folded key, such as a record's Key or RegistrationKey.

.PARAMETER Native
Resolves the key among native targets instead of parameter targets.

.OUTPUTS
CompleterActions.CompleterTarget

.EXAMPLE
PS> Resolve-CompleterKeyTarget -Key 'kelvin' -Native

Returns the native target 'kelvin', and throws while a native target spelled
with the Kelvin sign (U+212A) is registered, whether or not 'kelvin' is.
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

    $exactNaming = 'Supply RuntimeKey, or CommandName with IsNative or ParameterName, to name the target exactly.'

    if ($matchingKeys.Count -gt 1)
    {
        throw "The key '$Key' belongs to $($matchingKeys.Count) registered $kind targets, $(@($matchingKeys | ForEach-Object { "'$_'" }) -join ', '), which differ in characters that lowercasing merges, so it cannot name one of them. $exactNaming"
    }

    if ($matchingKeys.Count -eq 1 -and -not [string]::Equals($matchingKeys[0], $Key, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "The key '$Key' belongs to the registered $kind target '$($matchingKeys[0])', whose name differs from the key in characters that lowercasing merges, so the key could also name the $kind target '$Key'. $exactNaming"
    }

    $runtimeKey = if ($matchingKeys.Count -eq 1) { $matchingKeys[0] } else { $Key }

    if ($Native)
    {
        return Resolve-CompleterTarget -RuntimeKey $runtimeKey -Native
    }

    return Resolve-CompleterTarget -RuntimeKey $runtimeKey
}
