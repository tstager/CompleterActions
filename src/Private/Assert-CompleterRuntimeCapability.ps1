<#
.SYNOPSIS
Asserts that the PowerShell runtime exposes every internal member CompleterActions needs.

.DESCRIPTION
CompleterActions reaches into non-public PowerShell runtime members to discover and
manage argument completers: the execution context field behind EngineIntrinsics and
the two completer dictionaries that execution context owns.

This probe resolves all of those members once during module import so an engine whose
internals changed fails with a single terminating error that names the PowerShell
version and the unresolved members, instead of failing deep inside a later
registration or discovery call.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to reflect against. This is primarily exposed for
internal testing of compatibility guards.

.PARAMETER RuntimeExecutionContext
An already resolved execution context object to inspect for the completer
dictionaries. When supplied, the execution context resolution step is skipped. This
is primarily exposed for internal testing of compatibility guards.

.OUTPUTS
None

.EXAMPLE
Assert-CompleterRuntimeCapability

Verifies that the current engine exposes the reflected completer runtime members and
throws a single terminating error when any of them cannot be resolved.

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

    $missingMembers = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $RuntimeExecutionContext)
    {
        try
        {
            $RuntimeExecutionContext = Resolve-CompleterRuntimeExecutionContext -EngineIntrinsics $EngineIntrinsics -EngineIntrinsicsType $EngineIntrinsicsType
        }
        catch
        {
            $missingMembers.Add('System.Management.Automation.EngineIntrinsics._context')
        }
    }

    if ($missingMembers.Count -eq 0)
    {
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
        $runtimeExecutionContextType = $RuntimeExecutionContext.GetType()

        foreach ($propertyName in 'CustomArgumentCompleters', 'NativeArgumentCompleters')
        {
            if ($null -eq $runtimeExecutionContextType.GetProperty($propertyName, $bindingFlags))
            {
                $missingMembers.Add("$($runtimeExecutionContextType.FullName).$propertyName")
            }
        }
    }

    if ($missingMembers.Count -gt 0)
    {
        $missingMemberList = $missingMembers -join "', '"

        throw "CompleterActions cannot run on PowerShell $($PSVersionTable.PSVersion): the required runtime member(s) '$missingMemberList' could not be resolved. Completer discovery depends on PowerShell internals; check for a module update that supports this engine version."
    }
}
