function Get-CompleterRuntime
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
    $engineIntrinsicsField = [System.Management.Automation.EngineIntrinsics].GetField('_context', $bindingFlags)

    if ($null -eq $engineIntrinsicsField)
    {
        throw 'Unable to access the PowerShell execution context field required for completer runtime discovery.'
    }

    $runtimeExecutionContext = $engineIntrinsicsField.GetValue($ExecutionContext)

    if ($null -eq $runtimeExecutionContext)
    {
        throw 'Unable to resolve the current PowerShell execution context.'
    }

    $runtimeExecutionContextType = $runtimeExecutionContext.GetType()
    $customArgumentCompletersProperty = $runtimeExecutionContextType.GetProperty('CustomArgumentCompleters', $bindingFlags)
    $nativeArgumentCompletersProperty = $runtimeExecutionContextType.GetProperty('NativeArgumentCompleters', $bindingFlags)

    if ($null -eq $customArgumentCompletersProperty -or $null -eq $nativeArgumentCompletersProperty)
    {
        throw 'The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.'
    }

    $runtime = [pscustomobject] [ordered] @{
        PSTypeName               = 'CompleterActions.CompleterRuntime'
        ExecutionContext         = $runtimeExecutionContext
        CustomArgumentCompleters = $customArgumentCompletersProperty.GetValue($runtimeExecutionContext)
        NativeArgumentCompleters = $nativeArgumentCompletersProperty.GetValue($runtimeExecutionContext)
    }

    return $runtime
}
