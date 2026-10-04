<#
.SYNOPSIS
Asserts that the PowerShell runtime exposes every internal member CompleterActions needs.

.DESCRIPTION
CompleterActions reaches into non-public PowerShell runtime members to discover and
manage argument completers: the execution context field behind EngineIntrinsics and
the two completer dictionaries that execution context owns.

This probe runs once during module import. It asks the compiled engine access layer
(CompleterActions.Internal.EngineAccess) to resolve all of those members, so an engine
whose internals changed fails with a single terminating error that names the PowerShell
version and the unresolved members, instead of failing deep inside a later
registration or discovery call. On success the resolved handles are kept in module
state for Get-CompleterRuntime.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

.PARAMETER RuntimeExecutionContext
An already resolved execution context object to inspect for the completer
dictionaries. When supplied, the execution context resolution step is skipped. This
is primarily exposed for internal testing of compatibility guards.

.OUTPUTS
None

.EXAMPLE
Assert-CompleterRuntimeCapability

Verifies that the current engine exposes the completer runtime members and throws a
single terminating error when any of them cannot be resolved.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the error
message explicit about both the engine version and the unresolved members so a future
runtime change is diagnosable from the import failure alone.
#>
function Assert-CompleterRuntimeCapability
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics],

        [Parameter()]
        [object] $RuntimeExecutionContext
    )

    try
    {
        $engine = [CompleterActions.Internal.EngineAccess]::Create($EngineIntrinsics, $EngineIntrinsicsType, $RuntimeExecutionContext, $PSVersionTable.PSVersion)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }

    $script:CompleterEngine = $engine
}
