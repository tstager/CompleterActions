<#
.SYNOPSIS
Adds or replaces a runtime completer registration in PowerShell's live dictionaries.

.DESCRIPTION
Writes directly to the runtime completer dictionaries that back TabExpansion2. The
helper initializes the relevant dictionary when PowerShell has not created it yet,
which keeps imported and ordinary completer registrations on the same runtime path.

.PARAMETER Target
The completer target or registration object. It must expose RuntimeKey and IsNative.

.PARAMETER ScriptBlock
The completer script block to register.
#>
function Add-RuntimeCompleterRegistration
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates the live completer runtime dictionaries on behalf of public commands.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($Target.PSObject.Properties.Match($requiredProperty).Count -eq 0)
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic, Public'
    $runtime = Get-CompleterRuntime
    $propertyName = if ($Target.IsNative) { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
    $dictionary = $runtime.$propertyName

    if ($null -eq $dictionary)
    {
        $runtimeExecutionContextType = $runtime.ExecutionContext.GetType()
        $runtimeProperty = $runtimeExecutionContextType.GetProperty($propertyName, $bindingFlags)
        if ($null -eq $runtimeProperty)
        {
            throw "The current PowerShell runtime does not expose the '$propertyName' completer dictionary."
        }

        $dictionary = [System.Collections.Generic.Dictionary[string, scriptblock]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $runtimeProperty.SetValue($runtime.ExecutionContext, $dictionary)
    }

    $dictionary[[string] $Target.RuntimeKey] = $ScriptBlock

    return $dictionary[[string] $Target.RuntimeKey]
}
