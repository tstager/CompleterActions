$script:LegacyCommands = @(
    @{ Alias = 'Get-CompleterRegistration'; Target = 'Get-CompleterRegistrationLegacy'; NewName = 'Get-Completer' }
    @{ Alias = 'Register-CompleterRegistration'; Target = 'Register-CompleterRegistrationLegacy'; NewName = 'Register-Completer' }
    @{ Alias = 'Unregister-CompleterRegistration'; Target = 'Unregister-CompleterRegistrationLegacy'; NewName = 'Unregister-Completer' }
)

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ManifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1'
    $script:LegacyAliases = @('Get-CompleterRegistration', 'Register-CompleterRegistration', 'Unregister-CompleterRegistration')

    Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    Import-Module -Name $script:ManifestPath -Force | Out-Null
}

AfterAll {
    Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Unregister-Completer -Confirm:$false
    Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
}

Describe 'Legacy command aliases' {
    It 'exports the three legacy names as aliases alongside the functions' {
        $commands = Get-Command -Module 'CompleterActions'
        $manifestData = Import-PowerShellDataFile -Path $script:ManifestPath

        @($commands | Where-Object CommandType -eq 'Alias' | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be $script:LegacyAliases
        @($manifestData.AliasesToExport | Sort-Object) | Should -Be $script:LegacyAliases
        @($commands | Where-Object CommandType -eq 'Function').Count | Should -Be 11
    }

    It 'resolves <Alias> to <Target>' -TestCases $script:LegacyCommands {
        $alias = Get-Alias -Name $Alias

        $alias.ReferencedCommand.Name | Should -Be $Target
        $alias.ModuleName | Should -Be 'CompleterActions'
    }

    It 'forwards help for <Alias> to <NewName>' -TestCases $script:LegacyCommands {
        (Get-Help -Name $Alias).Name | Should -Be $NewName
    }

    Context 'warns once per process' {
        BeforeAll {
            $probeScript = @'
$ErrorActionPreference = 'Stop'
Import-Module -Name '{0}' -Force
$scriptBlock = {{ param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters) }}
Register-Completer -CommandName 'Test-DeprecationProbe' -ParameterName 'Name' -ScriptBlock $scriptBlock

$getWarnings = $null
$null = Get-CompleterRegistration -WarningVariable getWarnings -WarningAction SilentlyContinue
$null = Get-CompleterRegistration -ManagedOnly -WarningVariable +getWarnings -WarningAction SilentlyContinue

$registerWarnings = $null
Register-CompleterRegistration -CommandName 'Test-DeprecationProbe' -ParameterName 'Path' -ScriptBlock $scriptBlock -WhatIf -WarningVariable registerWarnings -WarningAction SilentlyContinue
Register-CompleterRegistration -CommandName 'Test-DeprecationProbe' -ParameterName 'Path' -ScriptBlock $scriptBlock -WhatIf -WarningVariable +registerWarnings -WarningAction SilentlyContinue

$unregisterWarnings = $null
Unregister-CompleterRegistration -CommandName 'Test-DeprecationProbe' -ParameterName 'Name' -WhatIf -WarningVariable unregisterWarnings -WarningAction SilentlyContinue
Unregister-CompleterRegistration -CommandName 'Test-DeprecationProbe' -ParameterName 'Name' -WhatIf -WarningVariable +unregisterWarnings -WarningAction SilentlyContinue

[pscustomobject] @{{
    'Get-CompleterRegistration'        = @($getWarnings | ForEach-Object {{ $_.Message }})
    'Register-CompleterRegistration'   = @($registerWarnings | ForEach-Object {{ $_.Message }})
    'Unregister-CompleterRegistration' = @($unregisterWarnings | ForEach-Object {{ $_.Message }})
}} | ConvertTo-Json -Compress
'@ -f $script:ManifestPath

            $probePath = Join-Path -Path $TestDrive -ChildPath 'deprecation-probe.ps1'
            Set-Content -Path $probePath -Value $probeScript
            $script:ProbeOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $probePath 2>&1)
            $script:ProbeExitCode = $LASTEXITCODE
        }

        It 'emits exactly one warning for <Alias> across two calls in a fresh process' -TestCases $script:LegacyCommands {
            $script:ProbeExitCode | Should -Be 0 -Because ($script:ProbeOutput -join [Environment]::NewLine)
            $warnings = @(($script:ProbeOutput[-1] | ConvertFrom-Json).$Alias)

            $warnings.Count | Should -Be 1
            $warnings[0] | Should -Be "$Alias is deprecated and will be removed in 3.0; use $NewName instead. See about_CompleterActions_Migration."
        }
    }

    Context 'forwards to the new commands' {
        BeforeAll {
            $script:DeprecationScriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
            }
        }

        AfterEach {
            Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Unregister-Completer -Confirm:$false
        }

        It 'does not register through the Register alias with -WhatIf' {
            Register-CompleterRegistration -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -ScriptBlock $script:DeprecationScriptBlock -WhatIf -WarningAction SilentlyContinue

            Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'registers through the Register alias and returns a typed record with -PassThru' {
            $record = Register-CompleterRegistration -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -ScriptBlock $script:DeprecationScriptBlock -PassThru -WarningAction SilentlyContinue

            $record.PSObject.TypeNames[0] | Should -Be 'CompleterActions.CompleterRegistration'
            $record.Source | Should -Be 'Managed'
            (Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name').Key | Should -Be $record.Key
        }

        It 'does not remove through the Unregister alias with -WhatIf, including piped records' {
            Register-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -ScriptBlock $script:DeprecationScriptBlock

            Unregister-CompleterRegistration -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -WhatIf -WarningAction SilentlyContinue
            Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Unregister-CompleterRegistration -WhatIf -WarningAction SilentlyContinue

            Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Should -Not -BeNullOrEmpty
        }

        It 'removes a piped record through the Unregister alias' {
            Register-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -ScriptBlock $script:DeprecationScriptBlock

            $removed = Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Unregister-CompleterRegistration -PassThru -WarningAction SilentlyContinue

            $removed.CommandName | Should -Be 'Test-DeprecationTool'
            Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'round-trips a record and the deprecated Only switches through the Get alias' {
            Register-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' -ScriptBlock $script:DeprecationScriptBlock

            $piped = @(Get-Completer -CommandName 'Test-DeprecationTool' -ParameterName 'Name' | Get-CompleterRegistration -WarningAction SilentlyContinue)
            $managed = @(Get-CompleterRegistration -ManagedOnly -WarningAction SilentlyContinue)
            $discovered = @(Get-CompleterRegistration -DiscoveredOnly -WarningAction SilentlyContinue)

            $piped.Count | Should -Be 1
            $piped[0].CommandName | Should -Be 'Test-DeprecationTool'
            $managed.CommandName | Should -Contain 'Test-DeprecationTool'
            @($managed | Where-Object Source -ne 'Managed') | Should -BeNullOrEmpty
            $discovered.CommandName | Should -Not -Contain 'Test-DeprecationTool'
        }
    }
}
