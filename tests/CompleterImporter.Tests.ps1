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

    $script:CompleterImporterFixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportCompleterScript'
}

Describe 'Completer script importer public API' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in @(
            @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedTwo' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function Test-ImportedFixtureTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function Test-ImportedOne
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function Test-ImportedTwo
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }
    }

    AfterEach {
        foreach ($cleanupTarget in @(
            @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedTwo' -ErrorAction SilentlyContinue

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'returns objects with the shape Register-CompleterRegistration expects' {
        $imported = @(Import-CompleterScript -Path (Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ParameterCompleter.ps1'))

        $imported.Count | Should -Be 1
        $imported[0].PSTypeNames | Should -Contain 'CompleterActions.ImportedCompleterRegistration'
        $imported[0].CommandName | Should -Be 'Test-ImportedFixtureTool'
        $imported[0].ParameterName | Should -Be 'Name'
        $imported[0].Key | Should -Be 'test-importedfixturetool:name'
        $imported[0].RuntimeKey | Should -Be 'Test-ImportedFixtureTool:Name'
        $imported[0].CompleterType | Should -Be 'Parameter'
        $imported[0].ScriptBlock | Should -BeOfType ([scriptblock])
        $imported[0].ScriptText | Should -Match 'imported-alpha'
    }

    It 'pipes importer output into Register-CompleterRegistration and supports get and unregister' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ParameterCompleter.ps1'

        $registered = @(Import-CompleterScript -Path $fixturePath | Register-CompleterRegistration -PassThru)

        $registered.Count | Should -Be 1
        $registered[0].Source | Should -Be 'Managed'
        $registered[0].Key | Should -Be 'test-importedfixturetool:name'

        $inputScript = 'Test-ImportedFixtureTool -Name imported'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'imported-alpha'

        $resolved = Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
        $resolved.Source | Should -Be 'Managed'
        $resolved.Key | Should -Be 'test-importedfixturetool:name'

        $removed = @(Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Unregister-CompleterRegistration -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].Key | Should -Be 'test-importedfixturetool:name'
        Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'handles multiple command names from one registration call' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'MultiCommandCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')

        $registered = @($imported | Register-CompleterRegistration -PassThru)

        $registered.Count | Should -Be 2
        @($registered.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')

        $completionOneInput = 'Test-ImportedOne -Name imported'
        $completionOne = TabExpansion2 -InputScript $completionOneInput -CursorColumn $completionOneInput.Length
        $completionOne.CompletionMatches.CompletionText | Should -Contain 'imported-shared'

        $completionTwoInput = 'Test-ImportedTwo -Name imported'
        $completionTwo = TabExpansion2 -InputScript $completionTwoInput -CursorColumn $completionTwoInput.Length
        $completionTwo.CompletionMatches.CompletionText | Should -Contain 'imported-shared'
    }

    It 'imports native completer scripts that depend on helper functions and script scope' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
        @($imported.CompleterType | Select-Object -Unique) | Should -Be @('Native')

        $registered = @($imported | Register-CompleterRegistration -PassThru)

        $registered.Count | Should -Be 2
        @($registered.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')

        $inputScript = 'importfixture a'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'alpha'
    }

    It 'fails clearly for unsafe or unsupported script shapes' -TestCases @(
        @{
            Path = 'UnsafeTopLevelScript.ps1'
            Message = '*uses unsupported top-level command ''Get-Date''*'
        },
        @{
            Path = 'DynamicCommandName.ps1'
            Message = '*must use literal string values for -CommandName*'
        },
        @{
            Path = 'VariableScriptBlock.ps1'
            Message = '*must provide a literal script block for -ScriptBlock*'
        }
    ) {
        param(
            [string] $Path,
            [string] $Message
        )

        {
            Import-CompleterScript -Path (Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath $Path)
        } | Should -Throw $Message
    }
}
