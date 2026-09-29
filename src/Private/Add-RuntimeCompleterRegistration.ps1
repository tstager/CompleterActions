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

.PARAMETER Runtime
The CompleterActions.CompleterRuntime object to write through, as a
registration snapshot carries it in RuntimeContext. When it is omitted the
runtime is looked up for this call. A dictionary the helper creates is also
stored on this object, so every later write of the same batch reuses it
instead of creating another.
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
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [psobject] $Runtime
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    if ($null -eq $Runtime)
    {
        $Runtime = Get-CompleterRuntime
    }

    $propertyName = if ($Target.IsNative) { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
    $dictionary = $Runtime.$propertyName

    if ($null -eq $dictionary)
    {
        $runtimeProperty = if ($Target.IsNative) { $Runtime.NativeProperty } else { $Runtime.CustomProperty }
        if ($null -eq $runtimeProperty)
        {
            throw "The current PowerShell runtime does not expose the '$propertyName' completer dictionary."
        }

        $dictionary = [System.Collections.Generic.Dictionary[string, scriptblock]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $runtimeProperty.SetValue($Runtime.ExecutionContext, $dictionary)
        $Runtime.$propertyName = $dictionary
    }

    $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey) -Value $ScriptBlock

    return Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey)
}
