# Sample completer that only imports through the trusted tier: it initializes
# script state with a top-level [pscustomobject] assignment and wraps the
# registration in try/catch, both of which the strict grammar rejects.

Set-StrictMode -Version 2.0

$script:TrustedFixtureState = [pscustomobject] @{
    Values = @('trusted-alpha', 'trusted-beta')
}

function Complete-TrustedFixture
{
    param(
        [string] $WordToComplete
    )

    foreach ($value in $script:TrustedFixtureState.Values)
    {
        if ($value -like "$WordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
        }
    }
}

try
{
    Register-ArgumentCompleter -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters

        Complete-TrustedFixture -WordToComplete $wordToComplete
    }
}
catch
{
    Write-Warning -Message "Trusted fixture registration failed. $($_.Exception.Message)"
}
