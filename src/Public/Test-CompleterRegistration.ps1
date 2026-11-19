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

Every match the engine returns is reported, and FromTarget tells whether the
target's own completer produced it. A match with FromTarget set to $false came
from somewhere else: another completer, because the input or the cursor
position completes a different parameter or command, or the engine's own
fallback completion, such as file names, which the engine offers when the
target's completer returns nothing. Assert on the matches whose FromTarget is
$true to verify the registration itself.

One input text invokes one completer, so each call tests exactly one target.
The target parameters accept the same shapes as Get-Completer so
registration records and property-bound values pipe in, but the command throws
when more than one target resolves in a single call.

To see what the target's completer produces, the command puts an observer in
front of the target's runtime entry for the duration of the completion. The
observer puts the original entry back before it hands the call on, so the
completer runs exactly as it does at the prompt, and the command puts it back
itself when the engine never calls the completer. The command does not
otherwise change any registration, and it never touches PSReadLine.

Because the completer really runs, testing a Pending lazy registration loads
it as the first tab press would: its script is imported, and the registration,
with any Pending registration of the same script, becomes Active, or Failed
when the load fails.

.PARAMETER InputObject
Supplies an object that describes the completer target, such as a record
returned by Get-Completer or Import-CompleterScript. The object
must expose CommandName with IsNative/Native or ParameterName, or a Key,
RegistrationKey, or RuntimeKey together with IsNative/Native.
CommandName, or RuntimeKey, names the target exactly. Key and
RegistrationKey are folded to lowercase, so an object that has only one of
them names the target whose runtime key is that key, apart from letter case,
whether or not it is registered. Such an object is rejected while a
registered target of its kind has the key under a name that the lowercasing
merged into it, such as a name spelled with the Kelvin sign (U+212A) for a
key spelled with the letter k.

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
CursorPosition, CompletionText, ListItemText, ResultType, ToolTip, and
FromTarget properties. Nothing is returned when the engine yields no matches.
Matches the engine returns without the target's completer, such as fallback
file names, are returned with FromTarget set to $false.

.EXAMPLE
PS> Test-CompleterRegistration -CommandName git -Native -InputText 'git che'

Returns the completion matches the registered git completer produces for
'git che', such as checkout, cherry, and cherry-pick.

.EXAMPLE
PS> Get-Completer -CommandName Invoke-DemoTool -ParameterName Name | Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'

Verifies a registration record returned by Get-Completer by
completing an argument for its parameter.

.EXAMPLE
PS> $matches = Test-CompleterRegistration -CommandName git -Native -InputText 'git che' | Where-Object FromTarget
$matches.CompletionText | Should -Contain 'checkout'

Asserts inside a Pester test on the matches the git completer produced
itself, so a match the engine supplied without it cannot satisfy the
assertion.

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

            $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $target

            if ($null -eq $runtimeRegistration)
            {
                throw "No runtime completer registration exists for '$($target.RuntimeKey)'. Register the completer before testing it."
            }

            # TabExpansion2 reports what the engine completed, not which completer
            # produced it, so the target's entry is fronted by an observer that
            # records the target's own output. The observer puts the original
            # entry back before it delegates, so the completer, including a lazy
            # stub that checks it still owns its entry, runs as it would at the
            # prompt.
            $runtime = Get-CompleterRuntime
            $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
            $runtimeKey = $runtimeRegistration.RuntimeKey
            $completerScriptBlock = $runtimeRegistration.ScriptBlock
            $targetOutput = [System.Collections.Generic.List[object]]::new()
            $observer = {
                $dictionary[$runtimeKey] = $completerScriptBlock

                foreach ($result in $completerScriptBlock.Invoke($args))
                {
                    $targetOutput.Add($result)
                    $result
                }
            }.GetNewClosure()

            $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey -Value $observer

            try
            {
                $completion = TabExpansion2 -InputScript $InputText -CursorColumn $resolvedCursorPosition
            }
            finally
            {
                if ([object]::ReferenceEquals((Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey), $observer))
                {
                    $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey -Value $completerScriptBlock
                }
            }

            # The engine keeps a CompletionResult a completer emits and turns any
            # other output into one whose CompletionText is the output's text.
            $targetCompletionTexts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

            foreach ($output in $targetOutput)
            {
                if ($null -eq $output)
                {
                    continue
                }

                $null = $targetCompletionTexts.Add($(if ($output -is [System.Management.Automation.CompletionResult]) { $output.CompletionText } else { $output.ToString() }))
            }

            foreach ($completionMatch in @($completion.CompletionMatches))
            {
                $PSCmdlet.WriteObject((New-CompletionMatch -Target $target -CompletionResult $completionMatch -InputText $InputText -CursorPosition $resolvedCursorPosition -FromTarget:$targetCompletionTexts.Contains($completionMatch.CompletionText)))
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
