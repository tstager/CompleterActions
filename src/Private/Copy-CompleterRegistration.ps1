<#
.SYNOPSIS
Copies a completer registration record so the copy can leave the module.

.DESCRIPTION
Returns a new CompleterRegistration instance with every property of the input
record. The public commands emit these copies instead of the records stored in
the managed registration table, so a caller that edits an emitted record never
changes module state. The copy is shallow: ScriptBlock and ImportModule still
reference the live script block and its module.

.PARAMETER Registration
The CompleterRegistration record to copy.

.OUTPUTS
CompleterActions.CompleterRegistration
Returns a detached copy of each input record.

.EXAMPLE
PS> Find-ManagedCompleterRegistration -Target $target | Copy-CompleterRegistration

Returns a copy of the managed record for a target that a caller may edit
without changing the managed table.
#>
function Copy-CompleterRegistration
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [CompleterActions.CompleterRegistration[]] $Registration
    )

    process
    {
        foreach ($record in $Registration)
        {
            $copy = [CompleterActions.CompleterRegistration]::new()
            $copy.Key = $record.Key
            $copy.RegistrationKey = $record.RegistrationKey
            $copy.RuntimeKey = $record.RuntimeKey
            $copy.CommandName = $record.CommandName
            $copy.ParameterName = $record.ParameterName
            $copy.IsNative = $record.IsNative
            $copy.CompleterType = $record.CompleterType
            $copy.TargetType = $record.TargetType
            $copy.Source = $record.Source
            $copy.State = $record.State
            $copy.IsManaged = $record.IsManaged
            $copy.IsRuntimeRegistered = $record.IsRuntimeRegistered
            $copy.ScriptPath = $record.ScriptPath
            $copy.Trusted = $record.Trusted
            $copy.LoadError = $record.LoadError
            $copy.ImportModule = $record.ImportModule
            $copy.ScriptBlock = $record.ScriptBlock
            $copy.ScriptText = $record.ScriptText

            $copy
        }
    }
}
