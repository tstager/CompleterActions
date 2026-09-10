BeforeAll {
    function Invoke-TestRuntimeCompleterCleanup
    {
        param(
            [Parameter(Mandatory)]
            [string] $CommandName,

            [Parameter()]
            [string] $ParameterName,

            [Parameter(Mandatory)]
            [ValidateSet('Parameter', 'Native')]
            [string] $CompleterType
        )

        $engineField = $ExecutionContext.GetType().GetField(
            '_context',
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        )

        if ($null -eq $engineField)
        {
            return
        }

        $engineExecutionContext = $engineField.GetValue($ExecutionContext)
        if ($null -eq $engineExecutionContext)
        {
            return
        }

        $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor
            [System.Reflection.BindingFlags]::NonPublic -bor
            [System.Reflection.BindingFlags]::Public

        $propertyName = if ($CompleterType -eq 'Native') { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
        $property = $engineExecutionContext.GetType().GetProperty($propertyName, $bindingFlags)
        if ($null -eq $property)
        {
            return
        }

        $registrations = $property.GetValue($engineExecutionContext)
        $targetKey = if ($CompleterType -eq 'Native') { $CommandName } else { '{0}:{1}' -f $CommandName, $ParameterName }

        foreach ($candidateKey in @($registrations.Keys))
        {
            if ($candidateKey -ieq $targetKey)
            {
                $null = $registrations.Remove($candidateKey)
                break
            }
        }
    }

    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures'
    $script:ImportFixtureRoot = Join-Path -Path $script:FixtureRoot -ChildPath 'ImportCompleterScript'
}

Describe 'Test-CompleterScript' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'returns no findings for the conforming fixture <Name>' -TestCases @(
        @{ Name = 'ImportableNativeCompleter.ps1'; Folder = 'Fixtures' },
        @{ Name = 'ParameterCompleter.ps1'; Folder = 'Fixtures\ImportCompleterScript' },
        @{ Name = 'MultiCommandCompleter.ps1'; Folder = 'Fixtures\ImportCompleterScript' },
        @{ Name = 'ArrayExpressionCompleter.ps1'; Folder = 'Fixtures\ImportCompleterScript' }
    ) {
        param(
            [string] $Name,
            [string] $Folder
        )

        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path $Folder -ChildPath $Name)

        @(Test-CompleterScript -Path $fixturePath) | Should -BeNullOrEmpty
        @(Test-CompleterScript -LiteralPath $fixturePath | Where-Object -Property Severity -EQ -Value 'Error') | Should -BeNullOrEmpty
    }

    It 'pins a finding to the offending construct with a line, column, and hint' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'GuardedObjectStateCompleter.ps1'

        $findings = @(Test-CompleterScript -Path $fixturePath)

        $findings.Count | Should -Be 1
        $findings[0].PSTypeNames | Should -Contain 'CompleterActions.CompleterScriptFinding'
        $findings[0].Path | Should -Be $fixturePath
        $findings[0].Line | Should -Be 6
        $findings[0].Column | Should -Be 41
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Construct | Should -Be 'ConvertExpressionAst'
        $findings[0].Message | Should -Match 'ConvertExpressionAst'
        $findings[0].Hint | Should -Match 'Move the \[pscustomobject\] literal into a lazy initializer inside a function'
    }

    It 'reports every strict-grammar finding in a script instead of stopping at the first' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'TrustedOnlyCompleter.ps1'

        $findings = @(Test-CompleterScript -Path $fixturePath)

        @($findings.Line) | Should -Be @(7, 26)
        @($findings.Construct) | Should -Be @('AssignmentStatementAst', 'TryStatementAst')
        @($findings.Severity | Select-Object -Unique) | Should -Be @('Error')
        $findings[0].Hint | Should -Match 'Get-Variable'
        $findings[1].Hint | Should -Match 'function that the completer calls lazily'
    }

    It 'reports parse errors as findings without checking the grammar' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'ParseErrorCompleter.ps1'
        Set-Content -LiteralPath $scriptPath -Value 'function {' -Encoding utf8

        $findings = @(Test-CompleterScript -Path $scriptPath)

        $findings.Count | Should -BeGreaterThan 0
        @($findings.Construct | Select-Object -Unique) | Should -Be @('ParseError')
        $findings[0].Line | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Hint | Should -Match 'syntax error'
    }

    It 'accepts FileInfo objects from Get-ChildItem' {
        $findings = @(Get-ChildItem -Path $script:ImportFixtureRoot -Filter '*.ps1' -File | Test-CompleterScript)

        $findings.Count | Should -BeGreaterThan 0
        @($findings.Path | Sort-Object -Unique) | Should -Contain (Join-Path -Path $script:ImportFixtureRoot -ChildPath 'UnsafeTopLevelScript.ps1')
        @($findings.Path | Sort-Object -Unique) | Should -Not -Contain (Join-Path -Path $script:ImportFixtureRoot -ChildPath 'ParameterCompleter.ps1')
    }

    It 'reports the same findings the strict importer refuses on' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'GuardedObjectStateCompleter.ps1'
        $finding = Test-CompleterScript -Path $fixturePath

        $importError = { Import-CompleterScript -Path $fixturePath } | Should -Throw -PassThru

        $importError.Exception.Message | Should -Match 'does not conform to the strict import grammar'
        $importError.Exception.Message | Should -Match ('Line {0}, column {1} \({2}\)' -f $finding.Line, $finding.Column, $finding.Construct)
        $importError.Exception.Message | Should -Match ([regex]::Escape($finding.Message))
        $importError.Exception.Message | Should -Match ([regex]::Escape($finding.Hint))
    }

    It 'rejects directories and files that are not scripts' {
        { Test-CompleterScript -Path $script:ImportFixtureRoot } | Should -Throw '*is a directory*'

        $textPath = Join-Path -Path $TestDrive -ChildPath 'notes.txt'
        Set-Content -LiteralPath $textPath -Value 'not a script' -Encoding utf8

        { Test-CompleterScript -Path $textPath } | Should -Throw '*must be .ps1 files*'
    }
}

Describe 'Import-CompleterScript trusted tier' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Remove-Item -Path 'Function:\global:Test-TrustedFixtureTool' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-TrustedFixtureTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }
    }

    AfterEach {
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Remove-Item -Path 'Function:\global:Test-TrustedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'still rejects the trusted-only fixture under the strict tier' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'TrustedOnlyCompleter.ps1'

        { Import-CompleterScript -Path $fixturePath } | Should -Throw '*does not conform to the strict import grammar*'
        Get-CompleterRegistration -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'imports the trusted-only fixture with -Trusted and registers a working completer' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'TrustedOnlyCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath -Trusted)

        $imported.Count | Should -Be 1
        $imported[0].PSTypeNames | Should -Contain 'CompleterActions.ImportedCompleterRegistration'
        $imported[0].Key | Should -Be 'test-trustedfixturetool:name'
        $imported[0].Trusted | Should -BeTrue
        $imported[0].ScriptBlock.Module | Should -Not -BeNullOrEmpty
        Get-CompleterRegistration -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        $registered = @($imported | Register-CompleterRegistration -PassThru)

        $registered.Count | Should -Be 1
        $registered[0].Key | Should -Be 'test-trustedfixturetool:name'

        $inputScript = 'Test-TrustedFixtureTool -Name trusted'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'trusted-alpha'
        $completion.CompletionMatches.CompletionText | Should -Contain 'trusted-beta'
    }

    It 'marks strict imports as not trusted' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'ParameterCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 1
        $imported[0].Trusted | Should -BeFalse
    }
}
