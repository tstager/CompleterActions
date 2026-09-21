Describe 'Completer classes' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        $script:Module = Import-Module -Name (Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1') -Force -PassThru
    }

    AfterAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'constructs <ClassName> with the record property names and the dotted type name first' -TestCases @(
        @{
            ClassName  = 'CompleterRegistration'
            TypeName   = 'CompleterActions.CompleterRegistration'
            Properties = @(
                'Key', 'RegistrationKey', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'CompleterType',
                'TargetType', 'Source', 'State', 'IsManaged', 'IsRuntimeRegistered', 'ScriptPath', 'Trusted', 'LoadError',
                'ImportModule', 'ScriptBlock', 'ScriptText'
            )
        }
        @{
            ClassName  = 'ImportedCompleterRegistration'
            TypeName   = 'CompleterActions.ImportedCompleterRegistration'
            Properties = @(
                'Key', 'RegistrationKey', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'Native', 'CompleterType',
                'TargetType', 'Source', 'Trusted', 'Path', 'SourcePath', 'ImportModule', 'ScriptBlock', 'ScriptText'
            )
        }
        @{
            ClassName  = 'CompleterScriptFinding'
            TypeName   = 'CompleterActions.CompleterScriptFinding'
            Properties = @('Path', 'Line', 'Column', 'Severity', 'Construct', 'Message', 'Hint')
        }
        @{
            ClassName  = 'CompletionMatch'
            TypeName   = 'CompleterActions.CompletionMatch'
            Properties = @(
                'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'CompleterType', 'InputText',
                'CursorPosition', 'CompletionText', 'ListItemText', 'ResultType', 'ToolTip'
            )
        }
    ) {
        $instance = & $script:Module ([scriptblock]::Create("[$ClassName]::new()"))

        $instance.PSObject.TypeNames[0] | Should -Be $TypeName
        $instance.PSObject.TypeNames[1] | Should -Be $ClassName
        @($instance.PSObject.Properties.Name) | Should -Be $Properties
    }

    It 'defaults the module and script block references to null' {
        $registration = & $script:Module { [CompleterRegistration]::new() }
        $imported = & $script:Module { [ImportedCompleterRegistration]::new() }

        $registration.ImportModule | Should -BeNull
        $registration.ScriptBlock | Should -BeNull
        $registration.ParameterName | Should -BeNullOrEmpty
        $imported.ImportModule | Should -BeNull
        $imported.ScriptBlock | Should -BeNull
    }

    It 'defines the CompleterState and CompleterType enums with the roadmap values' {
        & $script:Module { [enum]::GetNames([CompleterState]) } | Should -Be @('Active', 'Stale', 'Conflicted', 'Pending', 'Failed', 'Discovered')
        & $script:Module { [enum]::GetNames([CompleterType]) } | Should -Be @('Native', 'Parameter')
    }

    It 'keeps the classes private to the module session state' {
        { [CompleterRegistration]::new() } | Should -Throw
    }

    It 'parses <Name> on its own without type errors' -TestCases @(
        Get-ChildItem -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Classes') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $parseErrors)

        @($parseErrors | ForEach-Object { "$($_.ErrorId) at line $($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty -Because 'PSScriptAnalyzer parses each file alone, so every type a class uses must be defined in the same file'
    }

    It 'defines every class and enum before the first function in the packaged module' {
        $builtModuleLines = @(Get-Content -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath 'build/CompleterActions/CompleterActions.psm1'))
        $firstFunctionLine = ($builtModuleLines | Select-String -Pattern '^\s*function\b' | Select-Object -First 1).LineNumber

        foreach ($definition in 'enum CompleterState', 'enum CompleterType', 'class CompleterRegistration', 'class ImportedCompleterRegistration', 'class CompleterScriptFinding', 'class CompletionMatch')
        {
            $definitionMatch = $builtModuleLines | Select-String -Pattern "^$definition\b" | Select-Object -First 1

            $definitionMatch | Should -Not -BeNullOrEmpty -Because "the packaged module must define '$definition'"
            $definitionMatch.LineNumber | Should -BeLessThan $firstFunctionLine -Because "'$definition' must be defined before the first function"
        }
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
}
