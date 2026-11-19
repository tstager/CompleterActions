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

    It 'reports a <Block> block in a script with no end block and keeps checking later paths' -TestCases @(
        @{ Block = 'begin' },
        @{ Block = 'process' },
        @{ Block = 'dynamicparam' },
        @{ Block = 'clean' }
    ) {
        param(
            [string] $Block
        )

        $namedBlockPath = Join-Path -Path $TestDrive -ChildPath ('{0}Only_completer.ps1' -f $Block)
        Set-Content -LiteralPath $namedBlockPath -Value ('{0} {{ }}' -f $Block) -Encoding utf8
        $nonConformingPath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'GuardedObjectStateCompleter.ps1'

        $findings = @(Test-CompleterScript -LiteralPath $namedBlockPath, $nonConformingPath)

        @($findings | Where-Object -Property Path -EQ -Value $namedBlockPath).Construct | Should -Be @('NamedBlockAst', 'ScriptBlockAst')
        @($findings | Where-Object -Property Path -EQ -Value $nonConformingPath).Construct | Should -Be @('ConvertExpressionAst')
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

    It 'reports a registration PowerShell cannot bind because it <Name>' -TestCases @(
        @{
            Name         = 'repeats -CommandName'
            Registration = "Register-ArgumentCompleter -CommandName 'unbound' -CommandName 'unbound.exe' -Native -ScriptBlock { 'ok' }"
            Offending    = "-CommandName 'unbound.exe'"
            Message      = "The script specifies Register-ArgumentCompleter parameter '-CommandName' more than once."
        },
        @{
            Name         = 'repeats -Native'
            Registration = "Register-ArgumentCompleter -Native -CommandName 'unbound' -Native -ScriptBlock { 'ok' }"
            Offending    = "-Native -ScriptBlock"
            Message      = "The script specifies Register-ArgumentCompleter parameter '-Native' more than once."
        },
        @{
            Name         = 'gives -CommandName no value before -Native'
            Registration = "Register-ArgumentCompleter -CommandName -Native -ScriptBlock { 'ok' }"
            Offending    = '-CommandName'
            Message      = 'The script is missing the argument for -CommandName.'
        },
        @{
            Name         = 'gives -ParameterName no value before -ScriptBlock'
            Registration = "Register-ArgumentCompleter -CommandName 'Test-UnboundTool' -ParameterName -ScriptBlock { 'ok' }"
            Offending    = '-ParameterName'
            Message      = 'The script is missing the argument for -ParameterName.'
        }
    ) {
        param(
            [string] $Name,
            [string] $Registration,
            [string] $Offending,
            [string] $Message
        )

        $scriptPath = Join-Path -Path $TestDrive -ChildPath (($Name -replace '[^A-Za-z0-9]+', '-') + '_completer.ps1')
        Set-Content -LiteralPath $scriptPath -Value $Registration -Encoding utf8

        $findings = @(Test-CompleterScript -LiteralPath $scriptPath)

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Construct | Should -Be 'CommandParameterAst'
        $findings[0].Line | Should -Be 1
        $findings[0].Column | Should -Be ($Registration.IndexOf($Offending) + 1)
        $findings[0].Message | Should -Be $Message
        { Import-CompleterScript -LiteralPath $scriptPath } | Should -Throw '*does not conform to the strict import grammar*'
    }

    It 'compares Register-ArgumentCompleter parameter names as PowerShell does under the tr-TR culture' {
        $repeatPath = Join-Path -Path $TestDrive -ChildPath 'tr-repeat_completer.ps1'
        $repeat = "Register-ArgumentCompleter -CommandName 'unbound' -Native -ScriptBlock { 'ok' } -SCRIPTBLOCK { 'ok' }"
        Set-Content -LiteralPath $repeatPath -Value $repeat -Encoding utf8
        $upperPath = Join-Path -Path $TestDrive -ChildPath 'tr-upper_completer.ps1'
        Set-Content -LiteralPath $upperPath -Value "Register-ArgumentCompleter -COMMANDNAME 'unbound' -NATIVE -SCRIPTBLOCK { 'ok' }" -Encoding utf8

        $originalCulture = [System.Globalization.CultureInfo]::CurrentCulture
        try
        {
            [System.Globalization.CultureInfo]::CurrentCulture = 'tr-TR'
            $repeatFindings = @(Test-CompleterScript -LiteralPath $repeatPath)
            $upperFindings = @(Test-CompleterScript -LiteralPath $upperPath)
        }
        finally
        {
            [System.Globalization.CultureInfo]::CurrentCulture = $originalCulture
        }

        $repeatFindings.Count | Should -Be 1
        $repeatFindings[0].Construct | Should -Be 'CommandParameterAst'
        $repeatFindings[0].Column | Should -Be ($repeat.IndexOf('-SCRIPTBLOCK') + 1)
        $repeatFindings[0].Message | Should -Be "The script specifies Register-ArgumentCompleter parameter '-SCRIPTBLOCK' more than once."
        $upperFindings.Count | Should -Be 0
    }

    It 'reports a registration that gives <Name>' -TestCases @(
        @{
            Name         = '-CommandName an empty string'
            Registration = "Register-ArgumentCompleter -CommandName '' -Native -ScriptBlock { 'ok' }"
            Offending    = "''"
            Parameter    = 'CommandName'
        },
        @{
            Name         = '-CommandName an array with an empty element'
            Registration = "Register-ArgumentCompleter -CommandName @('unbound', '') -Native -ScriptBlock { 'ok' }"
            Offending    = "'')"
            Parameter    = 'CommandName'
        },
        @{
            Name         = '-ParameterName an empty string'
            Registration = "Register-ArgumentCompleter -CommandName 'Test-UnboundTool' -ParameterName '' -ScriptBlock { 'ok' }"
            Offending    = "''"
            Parameter    = 'ParameterName'
        },
        @{
            Name         = '-CommandName a blank string'
            Registration = "Register-ArgumentCompleter -CommandName ' ' -Native -ScriptBlock { 'ok' }"
            Offending    = "' '"
            Parameter    = 'CommandName'
        }
    ) {
        param(
            [string] $Name,
            [string] $Registration,
            [string] $Offending,
            [string] $Parameter
        )

        $scriptPath = Join-Path -Path $TestDrive -ChildPath (($Name -replace '[^A-Za-z0-9]+', '-') + '_completer.ps1')
        Set-Content -LiteralPath $scriptPath -Value $Registration -Encoding utf8

        $findings = @(Test-CompleterScript -LiteralPath $scriptPath)

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Construct | Should -Be 'StringConstantExpressionAst'
        $findings[0].Column | Should -Be ($Registration.IndexOf($Offending) + 1)
        $findings[0].Message | Should -Be "The script uses an empty or blank name for -$Parameter."
        { Import-CompleterScript -LiteralPath $scriptPath } | Should -Throw '*does not conform to the strict import grammar*'
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
        Get-Completer -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'imports the trusted-only fixture with -Trusted and registers a working completer' {
        $fixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'TrustedOnlyCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath -Trusted)

        $imported.Count | Should -Be 1
        $imported[0].PSTypeNames | Should -Contain 'CompleterActions.ImportedCompleterRegistration'
        $imported[0].Key | Should -Be 'test-trustedfixturetool:name'
        $imported[0].Trusted | Should -BeTrue
        $imported[0].ScriptBlock.Module | Should -Not -BeNullOrEmpty
        Get-Completer -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        $registered = @($imported | Register-Completer -PassThru)

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

Describe 'Test-CompleterRegistration' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in @(
            @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-ImportedFixtureTool' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-ImportedFixtureTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $null = Import-CompleterScript -Path (Join-Path -Path $script:ImportFixtureRoot -ChildPath 'ParameterCompleter.ps1') | Register-Completer
        $null = Import-CompleterScript -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'ImportableNativeCompleter.ps1') | Register-Completer
    }

    AfterEach {
        foreach ($cleanupTarget in @(
            @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'returns the completion matches for a registered parameter completer' {
        $matches = @(Test-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' -InputText 'Test-ImportedFixtureTool -Name imported')

        $matches.Count | Should -Be 1
        $matches[0].PSTypeNames | Should -Contain 'CompleterActions.CompletionMatch'
        $matches[0].Key | Should -Be 'test-importedfixturetool:name'
        $matches[0].RuntimeKey | Should -Be 'Test-ImportedFixtureTool:Name'
        $matches[0].CompleterType | Should -Be 'Parameter'
        $matches[0].InputText | Should -Be 'Test-ImportedFixtureTool -Name imported'
        $matches[0].CursorPosition | Should -Be 39
        $matches[0].CompletionText | Should -Be 'imported-alpha'
        $matches[0].ListItemText | Should -Be 'imported-alpha'
        $matches[0].ResultType | Should -Be 'ParameterValue'
        $matches[0].ToolTip | Should -Be 'imported-alpha'
    }

    It 'returns the completion matches for a registered native completer' {
        $matches = @(Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture a')

        @($matches.CompletionText) | Should -Be @('alpha')
        $matches[0].CompleterType | Should -Be 'Native'
        $matches[0].RuntimeKey | Should -Be 'importfixture'
    }

    It 'accepts a piped registration record and a key-bearing input object with a native indicator' {
        $piped = @(Get-Completer -CommandName 'importfixture' -Native | Test-CompleterRegistration -InputText 'importfixture b')
        @($piped.CompletionText) | Should -Be @('beta')

        $byKey = @(Test-CompleterRegistration -InputObject ([pscustomobject] @{ Key = 'importfixture'; IsNative = $true }) -InputText 'importfixture b')
        @($byKey.CompletionText) | Should -Be @('beta')
    }

    It 'pipes a <Kind> completion match back into the target-taking commands' -TestCases @(
        @{ Kind = 'native'; IsNative = $true; Key = 'importfixture'; Run = { Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture a' } },
        @{ Kind = 'parameter'; IsNative = $false; Key = 'test-importedfixturetool:name'; Run = { Test-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' -InputText 'Test-ImportedFixtureTool -Name imported' } }
    ) {
        param($IsNative, $Key, $Run)

        $match = @(& $Run)[0]
        $match.IsNative | Should -Be $IsNative

        @($match | Get-Completer).Key | Should -Be $Key
        @($match | Test-CompleterRegistration -InputText $match.InputText).Key | Should -Be $Key
        @($match | Unregister-Completer -Confirm:$false -PassThru).Key | Should -Be $Key
        $match | Get-Completer | Should -BeNullOrEmpty
    }

    It 'defaults the cursor to the end of the input and honours an explicit position' {
        $default = @(Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture ')
        @($default.CompletionText) | Should -Be @('alpha', 'beta')
        $default[0].CursorPosition | Should -Be 14

        $explicit = @(Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture a trailing' -CursorPosition 15)
        @($explicit.CompletionText) | Should -Be @('alpha')
        $explicit[0].CursorPosition | Should -Be 15
    }

    It 'returns nothing when the completer yields no matches' {
        @(Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture zzz') | Should -BeNullOrEmpty
    }

    It 'throws when the target has no runtime registration' {
        {
            Test-CompleterRegistration -CommandName 'Test-NotRegisteredTool' -ParameterName 'Name' -InputText 'Test-NotRegisteredTool -Name a'
        } | Should -Throw '*No runtime completer registration exists*'
    }

    It 'refuses more than one target per call instead of stamping one completion onto every target (<Name>)' -TestCases @(
        @{ Name = 'input object array'; Run = { Test-CompleterRegistration -InputObject @([pscustomobject] @{ CommandName = 'importfixture'; IsNative = $true }, [pscustomobject] @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name' }) -InputText 'importfixture a' } },
        @{ Name = 'array command name'; Run = { Test-CompleterRegistration -CommandName 'importfixture', 'Test-ImportedFixtureTool' -Native -InputText 'importfixture a' } },
        @{ Name = 'piped records'; Run = { @(Get-Completer -CommandName 'importfixture' -Native) + @(Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name') | Test-CompleterRegistration -InputText 'importfixture a' } }
    ) {
        param($Run)

        $caught = $null
        $output = @(try { & $Run } catch { $caught = $_ })

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -BeLike "*one completer target per call*2 targets resolved: 'importfixture', 'Test-ImportedFixtureTool*'*"
        $output | Should -BeNullOrEmpty
    }

    It 'rejects a cursor position past the end of the input' {
        {
            Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture a' -CursorPosition 99
        } | Should -Throw '*past the end of InputText*'
    }

    It 'leaves PSReadLine key handlers unchanged' {
        Import-Module -Name 'PSReadLine' -ErrorAction SilentlyContinue

        if ($null -eq (Get-Module -Name 'PSReadLine'))
        {
            Set-ItResult -Skipped -Because 'PSReadLine is not loaded in this session'
        }

        $before = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        $null = @(Test-CompleterRegistration -CommandName 'importfixture' -Native -InputText 'importfixture a')

        $after = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }
}

Describe 'Test-CompleterScript literal target arrays' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'reports a -<Parameter> array expression that <Name>' -TestCases @(
        @{
            Name         = 'redirects the error stream to a file'
            Parameter    = 'CommandName'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('arraytarget' 2> '{MarkerPath}') -ScriptBlock { 'ok' }"
        },
        @{
            Name         = 'redirects the success stream of an array to a file'
            Parameter    = 'CommandName'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('arraytarget', 'arraytarget.exe' > '{MarkerPath}') -ScriptBlock { 'ok' }"
        },
        @{
            Name         = 'redirects every stream to a file'
            Parameter    = 'CommandName'
            Registration = "Register-ArgumentCompleter -CommandName @('Test-ArrayTargetTool' *> '{MarkerPath}') -ParameterName 'Name' -ScriptBlock { 'ok' }"
        },
        @{
            Name         = 'appends to a file'
            Parameter    = 'ParameterName'
            Registration = "Register-ArgumentCompleter -CommandName 'Test-ArrayTargetTool' -ParameterName @('Name' >> '{MarkerPath}') -ScriptBlock { 'ok' }"
        },
        @{
            Name         = 'merges the error stream'
            Parameter    = 'CommandName'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('arraytarget' 2>&1) -ScriptBlock { 'ok' }"
        },
        @{
            Name         = 'runs in a background pipeline'
            Parameter    = 'CommandName'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('arraytarget' &) -ScriptBlock { 'ok' }"
        }
    ) {
        param(
            [string] $Name,
            [string] $Parameter,
            [string] $Registration
        )

        $fileBaseName = $Name -replace '[^A-Za-z0-9]+', '-'
        $markerPath = Join-Path -Path $TestDrive -ChildPath ('{0}.marker' -f $fileBaseName)
        $scriptPath = Join-Path -Path $TestDrive -ChildPath ('{0}_completer.ps1' -f $fileBaseName)
        $markerBytes = [System.Text.Encoding]::UTF8.GetBytes('CompleterActions disposable marker')
        $escapedMarkerPath = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($markerPath)

        [System.IO.File]::WriteAllBytes($markerPath, $markerBytes)
        Set-Content -LiteralPath $scriptPath -Value $Registration.Replace('{MarkerPath}', $escapedMarkerPath) -Encoding utf8

        $findings = @(Test-CompleterScript -LiteralPath $scriptPath)

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Construct | Should -Be 'ArrayExpressionAst'
        $findings[0].Line | Should -Be 1
        $findings[0].Column | Should -Be ($Registration.IndexOf('@(') + 1)
        $findings[0].Message | Should -Be ('The script must use literal string values for -{0}.' -f $Parameter)
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($markerPath)) | Should -Be ([System.Convert]::ToBase64String($markerBytes))
    }

    It 'still accepts single-element and multi-element literal target arrays' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'literal-arrays_completer.ps1'
        Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @(
            "Register-ArgumentCompleter -Native -CommandName @('arraytarget') -ScriptBlock { 'ok' }",
            "Register-ArgumentCompleter -Native -CommandName @('arraytarget', 'arraytarget.exe') -ScriptBlock { 'ok' }",
            "Register-ArgumentCompleter -CommandName @('Test-ArrayTargetTool') -ParameterName @('Name', 'Path') -ScriptBlock { 'ok' }"
        )

        @(Test-CompleterScript -LiteralPath $scriptPath) | Should -BeNullOrEmpty
    }
}
