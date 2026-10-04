Describe 'Completer public types' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        $script:Module = Import-Module -Name (Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1') -Force -PassThru
    }

    AfterAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'constructs <TypeName> with the record property names in order and the full type name first' -TestCases @(
        @{
            TypeName   = 'CompleterActions.CompleterRegistration'
            Properties = @(
                'Key', 'RegistrationKey', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'CompleterType',
                'TargetType', 'Source', 'State', 'IsManaged', 'IsRuntimeRegistered', 'ScriptPath', 'Trusted', 'LoadError',
                'ImportModule', 'ScriptBlock', 'ScriptText'
            )
        }
        @{
            TypeName   = 'CompleterActions.ImportedCompleterRegistration'
            Properties = @(
                'Key', 'RegistrationKey', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'Native', 'CompleterType',
                'TargetType', 'Source', 'Trusted', 'Path', 'SourcePath', 'ImportModule', 'ScriptBlock', 'ScriptText'
            )
        }
        @{
            TypeName   = 'CompleterActions.CompleterScriptFinding'
            Properties = @('Path', 'Line', 'Column', 'Severity', 'Construct', 'Message', 'Hint')
        }
        @{
            TypeName   = 'CompleterActions.CompletionMatch'
            Properties = @(
                'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'CompleterType', 'InputText',
                'CursorPosition', 'CompletionText', 'ListItemText', 'ResultType', 'ToolTip'
            )
        }
    ) {
        $instance = ([type] $TypeName)::new()

        @($instance.PSObject.TypeNames) | Should -Be @($TypeName, 'System.Object')
        @($instance.PSObject.Properties.Name) | Should -Be $Properties
    }

    It 'defaults every string property of <TypeName> to an empty string and keeps it so when $null is assigned' -TestCases @(
        @{ TypeName = 'CompleterActions.CompleterRegistration' }
        @{ TypeName = 'CompleterActions.ImportedCompleterRegistration' }
        @{ TypeName = 'CompleterActions.CompleterScriptFinding' }
        @{ TypeName = 'CompleterActions.CompletionMatch' }
    ) {
        $type = [type] $TypeName
        $stringProperties = @($type.GetProperties() | Where-Object PropertyType -EQ ([string]) | ForEach-Object Name)
        $instance = $type::new()

        $stringProperties | Should -Not -BeNullOrEmpty

        foreach ($propertyName in $stringProperties)
        {
            $instance.$propertyName | Should -BeExactly '' -Because "$TypeName.$propertyName defaults to an empty string"

            $instance.$propertyName = 'value'
            $instance.$propertyName = $null

            $instance.$propertyName | Should -BeExactly '' -Because "assigning `$null to $TypeName.$propertyName stores an empty string"
        }
    }

    It 'defaults ImportModule and ScriptBlock to null' {
        foreach ($instance in [CompleterActions.CompleterRegistration]::new(), [CompleterActions.ImportedCompleterRegistration]::new())
        {
            $instance.ImportModule | Should -BeNull
            $instance.ScriptBlock | Should -BeNull
        }
    }

    It 'defines the CompleterState and CompleterType enums with the roadmap values and integer order' {
        [enum]::GetNames([CompleterActions.CompleterState]) | Should -Be @('Active', 'Stale', 'Conflicted', 'Pending', 'Failed', 'Discovered')
        [enum]::GetValues([CompleterActions.CompleterState]) | ForEach-Object { [int] $_ } | Should -Be @(0, 1, 2, 3, 4, 5)
        [enum]::GetNames([CompleterActions.CompleterType]) | Should -Be @('Native', 'Parameter')
        [enum]::GetValues([CompleterActions.CompleterType]) | ForEach-Object { [int] $_ } | Should -Be @(0, 1)
    }

    Context 'with a registration made in the test' {
        BeforeEach {
            $null = Register-Completer -CommandName 'Test-PublicTypeTool' -ParameterName 'Name' -ScriptBlock { 'alpha' }
        }

        AfterEach {
            $null = Unregister-Completer -CommandName 'Test-PublicTypeTool' -ParameterName 'Name' -Confirm:$false
        }

        It 'is a CompleterActions.CompleterRegistration by -is from outside the module for a Get-Completer record' {
            $record = Get-Completer -CommandName 'Test-PublicTypeTool' -ParameterName 'Name'

            $record | Should -HaveCount 1
            $record -is [CompleterActions.CompleterRegistration] | Should -BeTrue
        }

        It 'binds -State from a string, compares to a string and to an integer, and serializes as an integer unless -EnumsAsStrings' {
            $record = Get-Completer -CommandName 'Test-PublicTypeTool' -ParameterName 'Name' -State 'Active'

            $record | Should -HaveCount 1
            $record.State | Should -BeOfType ([CompleterActions.CompleterState])
            $record.State -eq 'Active' | Should -BeTrue
            $record.State -eq 0 | Should -BeTrue
            $record | Select-Object -Property State | ConvertTo-Json -Compress | Should -BeExactly '{"State":0}'
            $record | Select-Object -Property State | ConvertTo-Json -Compress -EnumsAsStrings | Should -BeExactly '{"State":"Active"}'
        }

        It "renders a registration and a finding through the format file's views" {
            $registrationOutput = Get-Completer -CommandName 'Test-PublicTypeTool' -ParameterName 'Name' | Out-String -Width 4096
            $findingPath = Join-Path -Path $TestDrive -ChildPath 'demo_completer.ps1'
            $findingOutput = [CompleterActions.CompleterScriptFinding] @{
                Path      = $findingPath
                Line      = 3
                Column    = 5
                Severity  = 'Error'
                Construct = 'CommandAst'
                Message   = 'A message.'
                Hint      = 'A hint.'
            } | Out-String -Width 4096

            $registrationOutput | Should -Match '(?m)^\s*Command\s+Parameter\s+Type\s+Source\s+State\s+ScriptPath\s+LoadError\s*$'
            $registrationOutput | Should -Match 'Test-PublicTypeTool'
            $findingOutput | Should -Match ('(?m)^\s*Path: ' + [regex]::Escape($findingPath) + '\s*$')
            $findingOutput | Should -Match '(?m)^Construct\s*: CommandAst\s*$'
        }
    }

    It 'declares the 2.2.0 output type name on <Command>' -TestCases @(
        @{ Command = 'Export-CompleterSet'; TypeName = 'System.IO.FileInfo' }
        @{ Command = 'Get-Completer'; TypeName = 'CompleterActions.CompleterRegistration' }
        @{ Command = 'Import-CompleterScript'; TypeName = 'CompleterActions.ImportedCompleterRegistration' }
        @{ Command = 'Import-CompleterSet'; TypeName = 'CompleterActions.CompleterRegistration' }
        @{ Command = 'New-CompleterScript'; TypeName = 'System.IO.FileInfo' }
        @{ Command = 'Register-Completer'; TypeName = 'CompleterActions.CompleterRegistration' }
        @{ Command = 'Reset-Completer'; TypeName = 'CompleterActions.CompleterRegistration' }
        @{ Command = 'Test-CompleterRegistration'; TypeName = 'CompleterActions.CompletionMatch' }
        @{ Command = 'Test-CompleterScript'; TypeName = 'CompleterActions.CompleterScriptFinding' }
        @{ Command = 'Test-CompleterSet'; TypeName = 'CompleterActions.CompleterScriptFinding' }
        @{ Command = 'Unregister-Completer'; TypeName = 'CompleterActions.CompleterRegistration' }
    ) {
        @((Get-Command -Name $Command -Module 'CompleterActions').OutputType.Name) | Should -Be @($TypeName)
    }

    It 'loads CompleterActions.Core 3.0.0.0 from under ModuleBase referencing System.Management.Automation 7.4.0.0 and exports no cmdlet' {
        # A fresh process, because an earlier test file may already have loaded the assembly from the other layout.
        $manifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1'
        $probeOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command {
                param($ManifestPath)

                $ErrorActionPreference = 'Stop'
                $module = Import-Module -Name $ManifestPath -Force -PassThru
                $assembly = [CompleterActions.CompleterRegistration].Assembly

                [pscustomobject] @{
                    Name                = $assembly.GetName().Name
                    Version             = $assembly.GetName().Version.ToString()
                    Location            = $assembly.Location
                    ModuleBase          = $module.ModuleBase
                    EngineVersion       = ($assembly.GetReferencedAssemblies() | Where-Object Name -EQ 'System.Management.Automation').Version.ToString()
                    CmdletCount         = @(Get-Command -Module 'CompleterActions' -CommandType Cmdlet).Count
                    ExportedCmdletCount = @($module.ExportedCmdlets.Keys).Count
                } | ConvertTo-Json -Compress
            } -args $manifestPath 2>&1)

        $LASTEXITCODE | Should -Be 0 -Because ($probeOutput -join [Environment]::NewLine)
        $probe = $probeOutput[-1] | ConvertFrom-Json

        $probe.Name | Should -Be 'CompleterActions.Core'
        $probe.Version | Should -Be '3.0.0.0'
        $probe.Location | Should -Be (Join-Path -Path (Join-Path -Path $probe.ModuleBase -ChildPath 'lib') -ChildPath 'CompleterActions.Core.dll')
        $probe.EngineVersion | Should -Be '7.4.0.0'
        $probe.CmdletCount | Should -Be 0
        $probe.ExportedCmdletCount | Should -Be 0
    }

    It 'imports the <Layout> module in a fresh profile-free process' -TestCases @(
        @{ Layout = 'source'; ManifestPath = 'CompleterActions.psd1' }
        @{ Layout = 'packaged'; ManifestPath = 'build/CompleterActions/CompleterActions.psd1' }
    ) {
        $manifestFullPath = Join-Path -Path $script:RepoRoot -ChildPath $ManifestPath
        $importOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Import-Module -Name '$manifestFullPath' -ErrorAction Stop; (Get-Module -Name CompleterActions).ModuleBase" 2>&1)

        $LASTEXITCODE | Should -Be 0 -Because ($importOutput -join [Environment]::NewLine)
        $importOutput[-1] | Should -Be (Split-Path -Path $manifestFullPath -Parent)
    }

    It 're-imports with -Force in the same process after Remove-Module' {
        $manifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1'

        Remove-Module -Name 'CompleterActions' -Force
        $script:Module = Import-Module -Name $manifestPath -Force -PassThru

        $script:Module.ModuleBase | Should -Be $script:RepoRoot
        Get-Command -Name 'Get-Completer' -Module 'CompleterActions' | Should -Not -BeNullOrEmpty
        [CompleterActions.CompleterRegistration]::new() -is [CompleterActions.CompleterRegistration] | Should -BeTrue
    }
}
