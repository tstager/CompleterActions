# Sample native completer used by Import-CompleterScript tests.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name ImportFixtureState -Scope Script -ErrorAction SilentlyContinue))
{
    $script:ImportFixtureState = @{
        Values = @('alpha', 'beta')
    }
}

function Get-ImportFixtureCompletionResult
{
    param(
        [Parameter(Mandatory)]
        [string] $CompletionText
    )

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        'ParameterValue',
        $CompletionText
    )
}

function Complete-ImportFixture
{
    param(
        [string] $WordToComplete,
        [System.Management.Automation.Language.CommandAst] $CommandAst,
        [int] $CursorPosition
    )

    $null = $CommandAst, $CursorPosition

    foreach ($value in $script:ImportFixtureState.Values)
    {
        if ($value -like "$WordToComplete*")
        {
            Get-ImportFixtureCompletionResult -CompletionText $value
        }
    }
}

Register-ArgumentCompleter -Native -CommandName 'importfixture', 'importfixture.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-ImportFixture -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
