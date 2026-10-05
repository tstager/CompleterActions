<#
.SYNOPSIS
Gets the current session's completer runtime dictionaries from PowerShell internals.

.DESCRIPTION
Builds the runtime wrapper object from the engine access handles that
Assert-CompleterRuntimeCapability resolved at import: the execution context object
that owns the runtime completer dictionaries and the handles of its two dictionary
properties. Maintainers use this helper when they need authoritative access to the
live CustomArgumentCompleters and NativeArgumentCompleters collections that
Register-ArgumentCompleter populates.

The dictionaries are read through the handles on every call, so a dictionary the
engine creates after import is seen.

This helper depends on non-public PowerShell runtime details. It is therefore
intended only for internal module plumbing.

.OUTPUTS
CompleterActions.CompleterRuntime

.EXAMPLE
Get-CompleterRuntime

Returns the current runtime wrapper object so a maintainer can inspect the live
completer dictionaries during module development or debugging.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the
error messages explicit so failures are diagnosable when runtime implementation
details change across PowerShell releases.
#>
function Get-CompleterRuntime
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $engine = $script:CompleterEngine

    if ($null -eq $engine -or $null -eq $engine.CustomProperty -or $null -eq $engine.NativeProperty)
    {
        throw 'The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.'
    }

    $runtime = [pscustomobject] [ordered] @{
        PSTypeName               = 'CompleterActions.CompleterRuntime'
        ExecutionContext         = $engine.ExecutionContext
        CustomProperty           = $engine.CustomProperty
        CustomArgumentCompleters = $engine.CustomProperty.GetValue($engine.ExecutionContext)
        NativeProperty           = $engine.NativeProperty
        NativeArgumentCompleters = $engine.NativeProperty.GetValue($engine.ExecutionContext)
    }

    return $runtime
}
