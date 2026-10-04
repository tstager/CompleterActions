<#
.SYNOPSIS
Resolves PowerShell's internal execution context object used for completer storage.

.DESCRIPTION
Asks the compiled engine access layer (CompleterActions.Internal.EngineAccess) for the
internal execution context object behind EngineIntrinsics that owns the runtime
completer dictionaries.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

.OUTPUTS
System.Object
#>
function Resolve-CompleterRuntimeExecutionContext
{
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics]
    )

    try
    {
        return [CompleterActions.Internal.EngineAccess]::ResolveExecutionContext($EngineIntrinsics, $EngineIntrinsicsType)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }
}
