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

    function Get-TestRuntimeScriptBlock
    {
        param(
            [Parameter(Mandatory)]
            [string] $Key
        )

        & (Get-Module -Name 'CompleterActions') {
            param($RuntimeLookupKey)

            $runtimeRegistration = Find-RuntimeCompleterRegistration -Key $RuntimeLookupKey

            if ($null -ne $runtimeRegistration)
            {
                $runtimeRegistration.ScriptBlock
            }
        } $Key
    }

    function Write-TestStrictCompleterScript
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $CompletionText
        )

        $content = @"
Register-ArgumentCompleter -CommandName 'Test-LazyStrictTool' -ParameterName 'Name' -ScriptBlock {
    param(`$commandName, `$parameterName, `$wordToComplete, `$commandAst, `$fakeBoundParameters)

    `$null = `$commandName, `$parameterName, `$wordToComplete, `$commandAst, `$fakeBoundParameters

    [System.Management.Automation.CompletionResult]::new('$CompletionText', '$CompletionText', 'ParameterValue', '$CompletionText')
}
"@

        Set-Content -LiteralPath $Path -Value $content -Encoding utf8
    }

    function Get-TestPSReadLineKeyHandlerSnapshot
    {
        @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })
    }

    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures'
    $script:NativeFixturePath = Join-Path -Path $script:FixtureRoot -ChildPath 'ImportableNativeCompleter.ps1'
    $script:ThrowingFixturePath = Join-Path -Path $script:FixtureRoot -ChildPath (Join-Path -Path 'LazyRegistration' -ChildPath 'ThrowingTrustedCompleter.ps1')
    $script:ReentrantFixturePath = Join-Path -Path $script:FixtureRoot -ChildPath (Join-Path -Path 'LazyRegistration' -ChildPath 'ReentrantTrustedCompleter.ps1')
    $script:LazyCleanupTargets = @(
        @{ CommandName = 'importfixture'; CompleterType = 'Native' },
        @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' },
        @{ CommandName = 'lazyduplicate'; CompleterType = 'Native' },
        @{ CommandName = 'lazyoverlap'; CompleterType = 'Native' },
        @{ CommandName = 'lazyoverlap.exe'; CompleterType = 'Native' },
        @{ CommandName = 'Test-LazyStrictTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-LazyTrustedTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' }
    )
}

Describe 'Lazy completer registration' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:LazyCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-LazyStrictTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-LazyTrustedTool' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-LazyStrictTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function global:Test-LazyTrustedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }
    }

    AfterEach {
        foreach ($cleanupTarget in $script:LazyCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-LazyStrictTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-LazyTrustedTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Env:\CompleterActionsReentrantNestedResult' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'registers a strict script lazily with targets derived from the AST and reports Pending' {
        $records = @(Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -PassThru)

        $records.Count | Should -Be 2
        @($records.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')

        foreach ($record in $records)
        {
            $record.PSTypeNames | Should -Contain 'CompleterActions.CompleterRegistration'
            $record.State | Should -Be 'Pending'
            $record.Source | Should -Be 'Managed'
            $record.IsManaged | Should -BeTrue
            $record.IsRuntimeRegistered | Should -BeTrue
            $record.ScriptPath | Should -Be $script:NativeFixturePath
            $record.Trusted | Should -BeFalse
            $record.LoadError | Should -BeNullOrEmpty
            $record.ScriptText | Should -Match 'Invoke-CompleterLazyStub'
        }

        Get-TestRuntimeScriptBlock -Key 'importfixture' | Should -Not -BeNullOrEmpty

        $resolved = Get-CompleterRegistration -CommandName 'importfixture' -Native
        $resolved.State | Should -Be 'Pending'
        $resolved.Source | Should -Be 'Managed'

        @(Get-CompleterRegistration -ManagedOnly | Where-Object State -EQ 'Pending').Count | Should -Be 2
        Get-CompleterRegistration -CommandName 'importfixture' -Native -DiscoveredOnly | Should -BeNullOrEmpty
    }

    It 'loads the script on the first tab press and later presses hit the real script block' {
        $null = Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy

        $stub = Get-TestRuntimeScriptBlock -Key 'importfixture'
        $siblingStub = Get-TestRuntimeScriptBlock -Key 'importfixture.exe'

        $inputScript = 'importfixture a'
        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('alpha')

        $loaded = Get-TestRuntimeScriptBlock -Key 'importfixture'
        [object]::ReferenceEquals($stub, $loaded) | Should -BeFalse
        $loaded.ToString() | Should -Match 'Complete-ImportFixture'
        $loaded.Module | Should -Not -BeNullOrEmpty

        $record = Get-CompleterRegistration -CommandName 'importfixture' -Native
        $record.State | Should -Be 'Active'
        $record.Source | Should -Be 'Managed'
        $record.ScriptPath | Should -Be $script:NativeFixturePath
        [object]::ReferenceEquals($record.ScriptBlock, $loaded) | Should -BeTrue

        $siblingLoaded = Get-TestRuntimeScriptBlock -Key 'importfixture.exe'
        [object]::ReferenceEquals($siblingStub, $siblingLoaded) | Should -BeFalse
        (Get-CompleterRegistration -CommandName 'importfixture.exe' -Native).State | Should -Be 'Active'
        [object]::ReferenceEquals($loaded.Module, $siblingLoaded.Module) | Should -BeTrue

        $secondInput = 'importfixture b'
        $secondCompletion = TabExpansion2 -InputScript $secondInput -CursorColumn $secondInput.Length
        @($secondCompletion.CompletionMatches.CompletionText) | Should -Be @('beta')
        [object]::ReferenceEquals($loaded, (Get-TestRuntimeScriptBlock -Key 'importfixture')) | Should -BeTrue

        $verified = @(Test-CompleterRegistration -CommandName 'importfixture.exe' -Native -InputText 'importfixture.exe a')
        @($verified.CompletionText) | Should -Be @('alpha')
    }

    It 'loads the last definition when a script registers the same target twice, on the first press and after it' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyDuplicateCompleter.ps1'
        Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @'
Register-ArgumentCompleter -CommandName 'lazyduplicate' -Native -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('first-definition', 'first-definition', 'ParameterValue', 'first-definition')
}

Register-ArgumentCompleter -CommandName 'lazyduplicate' -Native -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('last-definition', 'last-definition', 'ParameterValue', 'last-definition')
}
'@

        $inputScript = 'lazyduplicate '

        . $scriptPath
        $direct = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($direct.CompletionMatches.CompletionText) | Should -Be @('last-definition') -Because 'dot-sourcing lets the last Register-ArgumentCompleter call win'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'lazyduplicate' -CompleterType 'Native'

        $records = @(Register-CompleterRegistration -LiteralPath $scriptPath -Lazy -PassThru)
        $records.Count | Should -Be 1
        $records[0].State | Should -Be 'Pending'

        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('last-definition')

        $loaded = Get-CompleterRegistration -CommandName 'lazyduplicate' -Native
        $loaded.State | Should -Be 'Active'
        $loaded.ScriptText | Should -Match 'last-definition'
        (Get-TestRuntimeScriptBlock -Key 'lazyduplicate').ToString() | Should -Match 'last-definition'

        $secondCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($secondCompletion.CompletionMatches.CompletionText) | Should -Be @('last-definition')
    }

    It 'applies last-wins per target when command-name arrays overlap and swaps the sibling from the same import' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyOverlapCompleter.ps1'
        Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @'
Register-ArgumentCompleter -CommandName 'lazyoverlap', 'lazyoverlap.exe' -Native -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('shared-definition', 'shared-definition', 'ParameterValue', 'shared-definition')
}

Register-ArgumentCompleter -CommandName 'lazyoverlap.exe' -Native -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('exe-definition', 'exe-definition', 'ParameterValue', 'exe-definition')
}
'@

        $records = @(Register-CompleterRegistration -LiteralPath $scriptPath -Lazy -PassThru)
        @($records.Key | Sort-Object) | Should -Be @('lazyoverlap', 'lazyoverlap.exe')

        $exeInput = 'lazyoverlap.exe '
        $firstExeCompletion = TabExpansion2 -InputScript $exeInput -CursorColumn $exeInput.Length
        @($firstExeCompletion.CompletionMatches.CompletionText) | Should -Be @('exe-definition')

        (Get-CompleterRegistration -CommandName 'lazyoverlap.exe' -Native).State | Should -Be 'Active'
        (Get-CompleterRegistration -CommandName 'lazyoverlap' -Native).State | Should -Be 'Active' -Because 'the sibling is swapped from the same import'
        (Get-TestRuntimeScriptBlock -Key 'lazyoverlap').ToString() | Should -Match 'shared-definition'

        $plainInput = 'lazyoverlap '
        $plainCompletion = TabExpansion2 -InputScript $plainInput -CursorColumn $plainInput.Length
        @($plainCompletion.CompletionMatches.CompletionText) | Should -Be @('shared-definition')

        $secondExeCompletion = TabExpansion2 -InputScript $exeInput -CursorColumn $exeInput.Length
        @($secondExeCompletion.CompletionMatches.CompletionText) | Should -Be @('exe-definition')
    }

    It 'requires explicit targets for -Trusted' {
        {
            Register-CompleterRegistration -Path $script:ThrowingFixturePath -Lazy -Trusted
        } | Should -Throw '*-Trusted lazy registration requires explicit targets*'

        Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
    }

    It 'accepts explicit strict targets the script registers and rejects ones it does not' {
        $records = @(Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -CommandName 'importfixture.exe' -Native -PassThru)

        $records.Count | Should -Be 1
        $records[0].Key | Should -Be 'importfixture.exe'
        Get-CompleterRegistration -CommandName 'importfixture' -Native | Should -BeNullOrEmpty

        {
            Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        } | Should -Throw "*does not register a completer for 'Test-LazyStrictTool:Name'*It registers: 'importfixture', 'importfixture.exe'*"
    }

    It 'marks the record Failed, removes the runtime entry, and leaves default completion working when the script throws on first tab' {
        $fallbackMarker = Join-Path -Path $TestDrive -ChildPath 'lazy-fallback-marker.txt'
        Set-Content -LiteralPath $fallbackMarker -Value 'marker' -Encoding utf8

        $record = Register-CompleterRegistration -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -PassThru
        $record.State | Should -Be 'Pending'
        $record.Trusted | Should -BeTrue

        $inputScript = 'Test-LazyTrustedTool -Name '

        Push-Location -LiteralPath $TestDrive
        try
        {
            $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            $secondCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        }
        finally
        {
            Pop-Location
        }

        @($firstCompletion.CompletionMatches.CompletionText) | Should -Not -Contain 'never'
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Contain (Join-Path -Path '.' -ChildPath 'lazy-fallback-marker.txt')
        @($secondCompletion.CompletionMatches.CompletionText) | Should -Contain (Join-Path -Path '.' -ChildPath 'lazy-fallback-marker.txt')

        Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name' | Should -BeNullOrEmpty

        $failed = Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $failed.State | Should -Be 'Failed'
        $failed.Source | Should -Be 'Managed'
        $failed.IsRuntimeRegistered | Should -BeFalse
        $failed.ScriptPath | Should -Be $script:ThrowingFixturePath
        $failed.LoadError | Should -Match 'lazy fixture import failure'

        @(Get-CompleterRegistration -ManagedOnly | Where-Object State -EQ 'Failed').Key | Should -Be @('test-lazytrustedtool:name')
        Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -DiscoveredOnly | Should -BeNullOrEmpty
    }

    It 'returns nothing and writes nothing to the error stream when the stub itself is invoked for a script that fails to load' {
        $null = Register-CompleterRegistration -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $stub = Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name'

        $output = @(& $stub 'Test-LazyTrustedTool' 'Name' '' $null @{} 2>&1)

        $output | Should -BeNullOrEmpty
        (Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name').State | Should -Be 'Failed'
    }

    It 'loads a script once and keeps it Active when it requests completion for its own target while loading' {
        $null = Register-CompleterRegistration -LiteralPath $script:ReentrantFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $stub = Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('reentrant-alpha')

        $env:CompleterActionsReentrantNestedResult | Should -Not -BeNullOrEmpty
        @($env:CompleterActionsReentrantNestedResult -split '\|') | Should -Not -Contain 'reentrant-alpha'

        $record = Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $record.State | Should -Be 'Active'
        $record.LoadError | Should -BeNullOrEmpty

        $loaded = Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name'
        [object]::ReferenceEquals($stub, $loaded) | Should -BeFalse
        $loaded.ToString() | Should -Match 'reentrant-alpha'
        [object]::ReferenceEquals($record.ScriptBlock, $loaded) | Should -BeTrue

        $secondCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($secondCompletion.CompletionMatches.CompletionText) | Should -Be @('reentrant-alpha')

        InModuleScope CompleterActions {
            $script:CompleterLazyLoadsInProgress.Count | Should -Be 0
        }
    }

    It 'marks a strict registration Failed when the script no longer conforms at first tab' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyStrictCompleter.ps1'
        Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-alpha'

        $record = Register-CompleterRegistration -LiteralPath $scriptPath -Lazy -PassThru
        $record.Key | Should -Be 'test-lazystricttool:name'
        $record.State | Should -Be 'Pending'

        Add-Content -LiteralPath $scriptPath -Value 'Get-Date | Out-Null' -Encoding utf8

        $inputScript = 'Test-LazyStrictTool -Name strict'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Not -Contain 'strict-alpha'

        $failed = Get-CompleterRegistration -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        $failed.State | Should -Be 'Failed'
        $failed.LoadError | Should -Match 'does not conform to the strict import grammar'
        $failed.LoadError | Should -Match 'Get-Date'
        Get-TestRuntimeScriptBlock -Key 'test-lazystricttool:name' | Should -BeNullOrEmpty
    }

    It 'refuses to re-register a Failed record without -Force and retries the load with -Force' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyRetryCompleter.ps1'
        Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-alpha'
        $null = Register-CompleterRegistration -LiteralPath $scriptPath -Lazy

        Add-Content -LiteralPath $scriptPath -Value 'Get-Date | Out-Null' -Encoding utf8

        $inputScript = 'Test-LazyStrictTool -Name strict'
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        (Get-CompleterRegistration -CommandName 'Test-LazyStrictTool' -ParameterName 'Name').State | Should -Be 'Failed'

        Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-fixed'

        {
            Register-CompleterRegistration -LiteralPath $scriptPath -Lazy
        } | Should -Throw '*failed to load*Use -Force to retry*'

        (Get-CompleterRegistration -CommandName 'Test-LazyStrictTool' -ParameterName 'Name').State | Should -Be 'Failed'

        $retried = Register-CompleterRegistration -LiteralPath $scriptPath -Lazy -Force -PassThru
        $retried.State | Should -Be 'Pending'
        $retried.LoadError | Should -BeNullOrEmpty
        $retried.IsRuntimeRegistered | Should -BeTrue

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Be @('strict-fixed')

        $loaded = Get-CompleterRegistration -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        $loaded.State | Should -Be 'Active'
        $loaded.ScriptText | Should -Match 'strict-fixed'
    }

    It 'treats re-registering the same lazy script without -Force as idempotent' {
        $first = @(Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -PassThru)
        $second = @(Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -PassThru)

        $second.Count | Should -Be 2
        [object]::ReferenceEquals($first[0], $second[0]) | Should -BeTrue

        {
            Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -Trusted -CommandName 'importfixture' -Native
        } | Should -Throw '*already exists*Use -Force*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 2
    }

    It 'supports WhatIf without registering a stub' {
        Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy -WhatIf

        Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
        Get-TestRuntimeScriptBlock -Key 'importfixture' | Should -BeNullOrEmpty
    }

    It 'unregisters Pending and Failed lazy registrations' {
        $null = Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy
        $null = Register-CompleterRegistration -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        (Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name').State | Should -Be 'Failed'

        $removedPending = @(Get-CompleterRegistration -CommandName 'importfixture', 'importfixture.exe' -Native | Unregister-CompleterRegistration -Confirm:$false -PassThru)
        $removedPending.Count | Should -Be 2
        @($removedPending.State | Select-Object -Unique) | Should -Be @('Pending')
        Get-TestRuntimeScriptBlock -Key 'importfixture' | Should -BeNullOrEmpty
        Get-CompleterRegistration -CommandName 'importfixture' -Native | Should -BeNullOrEmpty

        $removedFailed = Unregister-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -Confirm:$false -PassThru
        $removedFailed.State | Should -Be 'Failed'
        Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
    }

    It 'carries ScriptPath and Trusted from Import-CompleterScript records onto managed records' {
        $fixturePath = Join-Path -Path $script:FixtureRoot -ChildPath (Join-Path -Path 'ImportCompleterScript' -ChildPath 'ParameterCompleter.ps1')

        $registered = @(Import-CompleterScript -Path $fixturePath | Register-CompleterRegistration -PassThru)

        $registered.Count | Should -Be 1
        $registered[0].State | Should -Be 'Active'
        $registered[0].ScriptPath | Should -Be $fixturePath
        $registered[0].Trusted | Should -BeFalse
        $registered[0].LoadError | Should -BeNullOrEmpty

        $resolved = Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
        $resolved.ScriptPath | Should -Be $fixturePath
    }

    It 'shows ScriptPath and LoadError in the default table view' {
        $null = Register-CompleterRegistration -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length

        $output = Get-CompleterRegistration -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' | Out-String -Width 4096

        $output | Should -Match '(?m)^\s*Command\s+Parameter\s+Type\s+Source\s+State\s+ScriptPath\s+LoadError\s*$'
        $output | Should -Match 'Failed'
        $output | Should -Match ([regex]::Escape($script:ThrowingFixturePath))
        $output | Should -Match 'lazy fixture import failure'
    }

    It 'leaves PSReadLine key handlers unchanged across lazy registration, first tab, and removal' {
        Import-Module -Name 'PSReadLine' -ErrorAction SilentlyContinue

        if ($null -eq (Get-Module -Name 'PSReadLine'))
        {
            Set-ItResult -Skipped -Because 'PSReadLine is not loaded in this session'
        }

        $before = Get-TestPSReadLineKeyHandlerSnapshot

        $null = Register-CompleterRegistration -Path $script:NativeFixturePath -Lazy
        $null = Register-CompleterRegistration -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $null = TabExpansion2 -InputScript 'importfixture a' -CursorColumn 15
        $null = TabExpansion2 -InputScript 'Test-LazyTrustedTool -Name ' -CursorColumn 27
        $null = @(Get-CompleterRegistration -ManagedOnly)
        Get-CompleterRegistration -ManagedOnly | Unregister-CompleterRegistration -Confirm:$false

        $after = Get-TestPSReadLineKeyHandlerSnapshot

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }
}
