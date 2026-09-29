@{
    Version = 1
    Entries = @(
        @{
            Path    = 'alpha_completer/alpha_completer.ps1'
            Trusted = $false
            Targets = @(
                @{ CommandName = 'setfixturealpha'; Native = $true }
                @{ CommandName = 'setfixturealpha.exe'; Native = $true }
            )
        }
        @{
            Path    = 'beta_completer/beta_completer.ps1'
            Trusted = $false
            Targets = @(
                @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name' }
            )
        }
    )
}
