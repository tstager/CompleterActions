<#
.SYNOPSIS
Runs tab completion for an input against a registered completer target.

.DESCRIPTION
Resolves one or more completer targets, confirms that each one has a live
runtime registration, and runs TabExpansion2 for the supplied input text. The
completion matches are returned as CompleterActions.CompletionMatch records that
carry the target key alongside CompletionText, ListItemText, ResultType, and
ToolTip, so the same check that used to be done by hand after every registration
can be scripted and asserted on.

The command only reads the completion engine. It does not change any
registration, and it never touches PSReadLine.

.PARAMETER InputObject
Supplies one or more objects that describe completer targets, such as the
records returned by Get-CompleterRegistration or Import-CompleterScript. Input
objects must expose target metadata through Key, RegistrationKey, RuntimeKey,
or CommandName/ParameterName plus IsNative/Native.

.PARAMETER Key
Identifies the targets by registration key. A key without a colon is treated
as a native command. A key with a colon is treated as a 'Command:Parameter'
target unless the text after its last colon contains a path separator, in which
case it is treated as a native command path such as 'C:\tools\example.exe'.

.PARAMETER CommandName
Specifies one or more command names for native or command-parameter completer
targets.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer targets.

.PARAMETER Native
Indicates that the targets are native command completers instead of command
parameter completers.

.PARAMETER InputText
The command line to complete, exactly as it would be typed at the prompt.

.PARAMETER CursorPosition
The zero-based cursor position within InputText at which completion runs. The
default is the end of the input.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.CompletionMatch records, one per completion match,
with Key, RuntimeKey, CommandName, ParameterName, CompleterType, InputText,
CursorPosition, CompletionText, ListItemText, ResultType, and ToolTip
properties. Nothing is returned when the completer yields no matches.

.EXAMPLE
PS> Test-CompleterRegistration -CommandName git -Native -InputText 'git che'

Returns the completion matches the registered git completer produces for
'git che', such as checkout, cherry, and cherry-pick.

.EXAMPLE
PS> Get-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name | Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'

Verifies a registration record returned by Get-CompleterRegistration by
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
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('RegistrationKey')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Key,

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
    }

    process
    {
        $resolvedTargets = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'ByKey'
                    {
                        $targetParameters['Key'] = $Key
                        break
                    }

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

                $resolvedTargets = @(Resolve-CompleterTargetList @targetParameters)
            }

            foreach ($target in $resolvedTargets)
            {
                if ($null -eq (Find-RuntimeCompleterRegistration -Key $target.Key))
                {
                    throw "No runtime completer registration exists for '$($target.RuntimeKey)'. Register the completer before testing it."
                }

                $completion = TabExpansion2 -InputScript $InputText -CursorColumn $resolvedCursorPosition

                foreach ($completionMatch in @($completion.CompletionMatches))
                {
                    $PSCmdlet.WriteObject(
                        [pscustomobject] [ordered] @{
                            PSTypeName     = 'CompleterActions.CompletionMatch'
                            Key            = [string] $target.Key
                            RuntimeKey     = [string] $target.RuntimeKey
                            CommandName    = [string] $target.CommandName
                            ParameterName  = if ($target.IsNative) { $null } else { [string] $target.ParameterName }
                            CompleterType  = if ($target.IsNative) { 'Native' } else { 'Parameter' }
                            InputText      = $InputText
                            CursorPosition = $resolvedCursorPosition
                            CompletionText = $completionMatch.CompletionText
                            ListItemText   = $completionMatch.ListItemText
                            ResultType     = $completionMatch.ResultType
                            ToolTip        = $completionMatch.ToolTip
                        }
                    )
                }
            }
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedTargets = @()
        }
    }
}
