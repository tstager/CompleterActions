<#
.SYNOPSIS
Creates the runtime stub registered for a lazy completer target.

.DESCRIPTION
Builds a script block, bound to this module's session state, that hands every
invocation to Invoke-CompleterLazyStub together with the target's normalized
key. The stub carries nothing else: the script path and trust tier live on the
managed record, so the stub text is the same shape for every lazy target and
the record stays the single source of truth. Binding through the module's
InvokeCommand is what lets the stub reach the module's private helpers when the
completion engine invokes it.

.PARAMETER Key
The normalized registration key of the lazy target.

.OUTPUTS
System.Management.Automation.ScriptBlock
#>
function New-CompleterLazyStub
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory script block.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    $escapedKey = $Key.Replace("'", "''")

    return $ExecutionContext.SessionState.InvokeCommand.NewScriptBlock("Invoke-CompleterLazyStub -Key '$escapedKey' -ArgumentList `$args")
}
