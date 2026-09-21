<#
.SYNOPSIS
Runs tab completion for an input against a registered completer target.

.DESCRIPTION
Resolves a completer target, confirms that it has a live runtime registration,
and runs TabExpansion2 for the supplied input text. The completion matches are
returned as CompleterActions.CompletionMatch records that carry the target key
alongside CompletionText, ListItemText, ResultType, and ToolTip, so the same
check that used to be done by hand after every registration can be scripted
and asserted on.

One input text invokes one completer, so each call tests exactly one target.
The target parameters accept the same shapes as Get-Completer so
registration records and property-bound values pipe in, but the command throws
when more than one target resolves in a single call.

The command only reads the completion engine. It does not change any
registration, and it never touches PSReadLine.

.PARAMETER InputObject
Supplies an object that describes the completer target, such as a record
returned by Get-Completer or Import-CompleterScript. The object
must expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.

.PARAMETER CommandName
Specifies the command name of the native or command-parameter completer
target.

.PARAMETER ParameterName
Specifies the parameter name of the command-parameter completer target.

.PARAMETER Native
Indicates that the target is a native command completer instead of a command
parameter completer.

.PARAMETER InputText
The command line to complete, exactly as it would be typed at the prompt. It
must invoke the target's command, because the matches come from whatever
command the text names.

.PARAMETER CursorPosition
The zero-based cursor position within InputText at which completion runs. The
default is the end of the input.

.OUTPUTS
CompleterActions.CompletionMatch
Returns CompleterActions.CompletionMatch records, one per completion match,
with Key, RuntimeKey, CommandName, ParameterName, CompleterType, InputText,
CursorPosition, CompletionText, ListItemText, ResultType, and ToolTip
properties. Nothing is returned when the completer yields no matches.

.EXAMPLE
PS> Test-CompleterRegistration -CommandName git -Native -InputText 'git che'

Returns the completion matches the registered git completer produces for
'git che', such as checkout, cherry, and cherry-pick.

.EXAMPLE
PS> Get-Completer -CommandName Invoke-DemoTool -ParameterName Name | Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'

Verifies a registration record returned by Get-Completer by
completing an argument for its parameter.

.NOTES
Completion runs from the module's scope, so the commands named in InputText
must be resolvable from the global scope, as they are in an interactive
session. Functions defined in a script's local scope are not visible to the
completion engine when it is invoked from this command.
#>
function Test-CompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition
    )

    begin
    {
        $resolvedCursorPosition = if ($PSBoundParameters.ContainsKey('CursorPosition')) { $CursorPosition } else { $InputText.Length }

        if ($resolvedCursorPosition -gt $InputText.Length)
        {
            throw "CursorPosition $resolvedCursorPosition is past the end of InputText, which has $($InputText.Length) characters."
        }

        $resolvedTargets = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets.AddRange([object[]] @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target }))
                return
            }

            $targetParameters = @{}

            switch ($PSCmdlet.ParameterSetName)
            {
                'Native'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['Native'] = $true
                    break
                }

                'CommandParameter'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['ParameterName'] = $ParameterName
                    break
                }
            }

            $resolvedTargets.AddRange([object[]] @(Resolve-CompleterTargetList @targetParameters))
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
    }

    end
    {
        try
        {
            if ($resolvedTargets.Count -ne 1)
            {
                $targetList = ($resolvedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                throw "Test-CompleterRegistration tests one completer target per call because InputText can only invoke one completer, but $($resolvedTargets.Count) targets resolved: $targetList. Call it once per target."
            }

            $target = $resolvedTargets[0]

            if ($null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
            {
                throw "No runtime completer registration exists for '$($target.RuntimeKey)'. Register the completer before testing it."
            }

            $completion = TabExpansion2 -InputScript $InputText -CursorColumn $resolvedCursorPosition

            foreach ($completionMatch in @($completion.CompletionMatches))
            {
                $PSCmdlet.WriteObject((New-CompletionMatch -Target $target -CompletionResult $completionMatch -InputText $InputText -CursorPosition $resolvedCursorPosition))
            }
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedTargets.Clear()
        }
    }
}
