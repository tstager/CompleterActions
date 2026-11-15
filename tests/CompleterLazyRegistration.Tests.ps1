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

            # No fixture's native command name contains a colon, so a key with one is a parameter target.
            $lookupTarget = if ($RuntimeLookupKey.Contains(':')) { Resolve-CompleterTarget -RuntimeKey $RuntimeLookupKey } else { Resolve-CompleterTarget -RuntimeKey $RuntimeLookupKey -Native }
            $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $lookupTarget

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
        $records = @(Register-Completer -Path $script:NativeFixturePath -Lazy -PassThru)

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

        $resolved = Get-Completer -CommandName 'importfixture' -Native
        $resolved.State | Should -Be 'Pending'
        $resolved.Source | Should -Be 'Managed'

        @(Get-Completer -State Pending).Count | Should -Be 2
        Get-Completer -CommandName 'importfixture' -Native -State Discovered, Conflicted | Should -BeNullOrEmpty
    }

    It 'loads the script on the first tab press and later presses hit the real script block' {
        $null = Register-Completer -Path $script:NativeFixturePath -Lazy

        $stub = Get-TestRuntimeScriptBlock -Key 'importfixture'
        $siblingStub = Get-TestRuntimeScriptBlock -Key 'importfixture.exe'

        $inputScript = 'importfixture a'
        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('alpha')

        $loaded = Get-TestRuntimeScriptBlock -Key 'importfixture'
        [object]::ReferenceEquals($stub, $loaded) | Should -BeFalse
        $loaded.ToString() | Should -Match 'Complete-ImportFixture'
        $loaded.Module | Should -Not -BeNullOrEmpty

        $record = Get-Completer -CommandName 'importfixture' -Native
        $record.State | Should -Be 'Active'
        $record.Source | Should -Be 'Managed'
        $record.ScriptPath | Should -Be $script:NativeFixturePath
        [object]::ReferenceEquals($record.ScriptBlock, $loaded) | Should -BeTrue

        $siblingLoaded = Get-TestRuntimeScriptBlock -Key 'importfixture.exe'
        [object]::ReferenceEquals($siblingStub, $siblingLoaded) | Should -BeFalse
        (Get-Completer -CommandName 'importfixture.exe' -Native).State | Should -Be 'Active'
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

        $records = @(Register-Completer -LiteralPath $scriptPath -Lazy -PassThru)
        $records.Count | Should -Be 1
        $records[0].State | Should -Be 'Pending'

        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('last-definition')

        $loaded = Get-Completer -CommandName 'lazyduplicate' -Native
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

        $records = @(Register-Completer -LiteralPath $scriptPath -Lazy -PassThru)
        @($records.Key | Sort-Object) | Should -Be @('lazyoverlap', 'lazyoverlap.exe')

        $exeInput = 'lazyoverlap.exe '
        $firstExeCompletion = TabExpansion2 -InputScript $exeInput -CursorColumn $exeInput.Length
        @($firstExeCompletion.CompletionMatches.CompletionText) | Should -Be @('exe-definition')

        (Get-Completer -CommandName 'lazyoverlap.exe' -Native).State | Should -Be 'Active'
        (Get-Completer -CommandName 'lazyoverlap' -Native).State | Should -Be 'Active' -Because 'the sibling is swapped from the same import'
        (Get-TestRuntimeScriptBlock -Key 'lazyoverlap').ToString() | Should -Match 'shared-definition'

        $plainInput = 'lazyoverlap '
        $plainCompletion = TabExpansion2 -InputScript $plainInput -CursorColumn $plainInput.Length
        @($plainCompletion.CompletionMatches.CompletionText) | Should -Be @('shared-definition')

        $secondExeCompletion = TabExpansion2 -InputScript $exeInput -CursorColumn $exeInput.Length
        @($secondExeCompletion.CompletionMatches.CompletionText) | Should -Be @('exe-definition')
    }

    It 'requires explicit targets for -Trusted' {
        {
            Register-Completer -Path $script:ThrowingFixturePath -Lazy -Trusted
        } | Should -Throw '*-Trusted lazy registration requires explicit targets*'

        Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
    }

    It 'accepts explicit strict targets the script registers and rejects ones it does not' {
        $records = @(Register-Completer -Path $script:NativeFixturePath -Lazy -CommandName 'importfixture.exe' -Native -PassThru)

        $records.Count | Should -Be 1
        $records[0].Key | Should -Be 'importfixture.exe'
        Get-Completer -CommandName 'importfixture' -Native | Should -BeNullOrEmpty

        {
            Register-Completer -Path $script:NativeFixturePath -Lazy -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        } | Should -Throw "*does not register a completer for 'Test-LazyStrictTool:Name'*It registers: 'importfixture', 'importfixture.exe'*"
    }

    It 'marks the record Failed, removes the runtime entry, and leaves default completion working when the script throws on first tab' {
        $fallbackMarker = Join-Path -Path $TestDrive -ChildPath 'lazy-fallback-marker.txt'
        Set-Content -LiteralPath $fallbackMarker -Value 'marker' -Encoding utf8

        $record = Register-Completer -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -PassThru
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

        $failed = Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $failed.State | Should -Be 'Failed'
        $failed.Source | Should -Be 'Managed'
        $failed.IsRuntimeRegistered | Should -BeFalse
        $failed.ScriptPath | Should -Be $script:ThrowingFixturePath
        $failed.LoadError | Should -Match 'lazy fixture import failure'

        @(Get-Completer -State Failed).Key | Should -Be @('test-lazytrustedtool:name')
        Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -State Discovered, Conflicted | Should -BeNullOrEmpty
    }

    It 'returns nothing and writes nothing to the error stream when the stub itself is invoked for a script that fails to load' {
        $null = Register-Completer -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $stub = Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name'

        $output = @(& $stub 'Test-LazyTrustedTool' 'Name' '' $null @{} 2>&1)

        $output | Should -BeNullOrEmpty
        (Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name').State | Should -Be 'Failed'
    }

    It 'loads a script once and keeps it Active when it requests completion for its own target while loading' {
        $null = Register-Completer -LiteralPath $script:ReentrantFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
        $stub = Get-TestRuntimeScriptBlock -Key 'test-lazytrustedtool:name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $firstCompletion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($firstCompletion.CompletionMatches.CompletionText) | Should -Be @('reentrant-alpha')

        $env:CompleterActionsReentrantNestedResult | Should -Not -BeNullOrEmpty
        @($env:CompleterActionsReentrantNestedResult -split '\|') | Should -Not -Contain 'reentrant-alpha'

        $record = Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'
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

        $record = Register-Completer -LiteralPath $scriptPath -Lazy -PassThru
        $record.Key | Should -Be 'test-lazystricttool:name'
        $record.State | Should -Be 'Pending'

        Add-Content -LiteralPath $scriptPath -Value 'Get-Date | Out-Null' -Encoding utf8

        $inputScript = 'Test-LazyStrictTool -Name strict'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Not -Contain 'strict-alpha'

        $failed = Get-Completer -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        $failed.State | Should -Be 'Failed'
        $failed.LoadError | Should -Match 'does not conform to the strict import grammar'
        $failed.LoadError | Should -Match 'Get-Date'
        Get-TestRuntimeScriptBlock -Key 'test-lazystricttool:name' | Should -BeNullOrEmpty
    }

    It 'refuses to re-register a Failed record without -Force and retries the load with -Force' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyRetryCompleter.ps1'
        Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-alpha'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy

        Add-Content -LiteralPath $scriptPath -Value 'Get-Date | Out-Null' -Encoding utf8

        $inputScript = 'Test-LazyStrictTool -Name strict'
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        (Get-Completer -CommandName 'Test-LazyStrictTool' -ParameterName 'Name').State | Should -Be 'Failed'

        Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-fixed'

        {
            Register-Completer -LiteralPath $scriptPath -Lazy
        } | Should -Throw '*failed to load*Use -Force to retry*'

        (Get-Completer -CommandName 'Test-LazyStrictTool' -ParameterName 'Name').State | Should -Be 'Failed'

        $retried = Register-Completer -LiteralPath $scriptPath -Lazy -Force -PassThru
        $retried.State | Should -Be 'Pending'
        $retried.LoadError | Should -BeNullOrEmpty
        $retried.IsRuntimeRegistered | Should -BeTrue

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Be @('strict-fixed')

        $loaded = Get-Completer -CommandName 'Test-LazyStrictTool' -ParameterName 'Name'
        $loaded.State | Should -Be 'Active'
        $loaded.ScriptText | Should -Match 'strict-fixed'
    }

    It 'treats re-registering the same lazy script without -Force as idempotent' {
        $first = @(Register-Completer -Path $script:NativeFixturePath -Lazy -PassThru)
        $second = @(Register-Completer -Path $script:NativeFixturePath -Lazy -PassThru)

        $second.Count | Should -Be 2
        [object]::ReferenceEquals($first[0], $second[0]) | Should -BeTrue

        {
            Register-Completer -Path $script:NativeFixturePath -Lazy -Trusted -CommandName 'importfixture' -Native
        } | Should -Throw '*already exists*Use -Force*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 2
    }

    It 'supports WhatIf without registering a stub' {
        Register-Completer -Path $script:NativeFixturePath -Lazy -WhatIf

        Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
        Get-TestRuntimeScriptBlock -Key 'importfixture' | Should -BeNullOrEmpty
    }

    It 'unregisters Pending and Failed lazy registrations' {
        $null = Register-Completer -Path $script:NativeFixturePath -Lazy
        $null = Register-Completer -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        (Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name').State | Should -Be 'Failed'

        $removedPending = @(Get-Completer -CommandName 'importfixture', 'importfixture.exe' -Native | Unregister-Completer -Confirm:$false -PassThru)
        $removedPending.Count | Should -Be 2
        @($removedPending.State | Select-Object -Unique) | Should -Be @('Pending')
        Get-TestRuntimeScriptBlock -Key 'importfixture' | Should -BeNullOrEmpty
        Get-Completer -CommandName 'importfixture' -Native | Should -BeNullOrEmpty

        $removedFailed = Unregister-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' -Confirm:$false -PassThru
        $removedFailed.State | Should -Be 'Failed'
        Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
    }

    It 'carries ScriptPath and Trusted from Import-CompleterScript records onto managed records' {
        $fixturePath = Join-Path -Path $script:FixtureRoot -ChildPath (Join-Path -Path 'ImportCompleterScript' -ChildPath 'ParameterCompleter.ps1')

        $registered = @(Import-CompleterScript -Path $fixturePath | Register-Completer -PassThru)

        $registered.Count | Should -Be 1
        $registered[0].State | Should -Be 'Active'
        $registered[0].ScriptPath | Should -Be $fixturePath
        $registered[0].Trusted | Should -BeFalse
        $registered[0].LoadError | Should -BeNullOrEmpty

        $resolved = Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
        $resolved.ScriptPath | Should -Be $fixturePath
    }

    It 'shows ScriptPath and LoadError in the default table view' {
        $null = Register-Completer -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $inputScript = 'Test-LazyTrustedTool -Name '
        $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length

        $output = Get-Completer -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name' | Out-String -Width 4096

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

        $null = Register-Completer -Path $script:NativeFixturePath -Lazy
        $null = Register-Completer -LiteralPath $script:ThrowingFixturePath -Lazy -Trusted -CommandName 'Test-LazyTrustedTool' -ParameterName 'Name'

        $null = TabExpansion2 -InputScript 'importfixture a' -CursorColumn 15
        $null = TabExpansion2 -InputScript 'Test-LazyTrustedTool -Name ' -CursorColumn 27
        $null = @(Get-Completer -State Active, Pending, Failed, Stale)
        Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false

        $after = Get-TestPSReadLineKeyHandlerSnapshot

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }

    Describe 'Grammar at registration' {
        BeforeEach {
            Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -CompleterType 'Parameter'
            $script:UnsafeScriptPath = Join-Path -Path $TestDrive -ChildPath 'UnsafeTopLevelScript.ps1'
            Copy-Item -LiteralPath (Join-Path -Path $script:FixtureRoot -ChildPath 'ImportCompleterScript' -AdditionalChildPath 'UnsafeTopLevelScript.ps1') -Destination $script:UnsafeScriptPath -Force
            $script:UnsafeConformanceLine = "Completer script '$script:UnsafeScriptPath' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is."
        }

        AfterEach {
            Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -CompleterType 'Parameter'
        }

        It 'fails a strict lazy registration of a non-conforming script with the conformance text and registers nothing' {
            $thrown = { Register-Completer -LiteralPath $script:UnsafeScriptPath -Lazy -ErrorAction Continue } | Should -Throw -PassThru

            $lines = @($thrown.Exception.Message -split [regex]::Escape([Environment]::NewLine))
            $lines[0] | Should -BeExactly $script:UnsafeConformanceLine -Because 'the conformance error is thrown unwrapped, without the Failed to register prefix'
            $lines[1] | Should -BeLike 'Line 1, column 1 (CommandAst): *'
            $lines.Count | Should -Be 3 -Because 'the fixture gives two CommandAst findings, one line each'
            Get-Completer -CommandName 'Test-UnsafeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
            Get-TestRuntimeScriptBlock -Key 'test-unsafetool:name' | Should -BeNullOrEmpty
        }

        It 'fails the same way under -WhatIf' {
            $thrown = { Register-Completer -LiteralPath $script:UnsafeScriptPath -Lazy -WhatIf -ErrorAction Continue } | Should -Throw -PassThru

            @($thrown.Exception.Message -split [regex]::Escape([Environment]::NewLine))[0] | Should -BeExactly $script:UnsafeConformanceLine
            Register-Completer -LiteralPath $script:UnsafeScriptPath -Lazy -Trusted -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -WhatIf
            Get-Completer -CommandName 'Test-UnsafeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
            Get-TestRuntimeScriptBlock -Key 'test-unsafetool:name' | Should -BeNullOrEmpty
        }

        It 'registers the same script as Pending with -Trusted' {
            $record = Register-Completer -LiteralPath $script:UnsafeScriptPath -Lazy -Trusted -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -PassThru

            $record.Key | Should -Be 'test-unsafetool:name'
            $record.State | Should -Be 'Pending'
            $record.Trusted | Should -BeTrue
            $record.ScriptPath | Should -Be $script:UnsafeScriptPath
            (Get-Completer -CommandName 'Test-UnsafeTool' -ParameterName 'Name').State | Should -Be 'Pending'
        }

        It 'parses the script once on the registration path' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'LazyParseOnceCompleter.ps1'
            Write-TestStrictCompleterScript -Path $scriptPath -CompletionText 'strict-alpha'

            & (Get-Module -Name 'CompleterActions') {
                $script:TestParseCount = 0
                $script:TestParseFunction = ${function:Get-CompleterScriptParseResult}

                function script:Get-CompleterScriptParseResult
                {
                    param($LiteralPath)

                    $script:TestParseCount++
                    & $script:TestParseFunction -LiteralPath $LiteralPath
                }
            }

            $record = Register-Completer -LiteralPath $scriptPath -Lazy -PassThru

            $record.State | Should -Be 'Pending'
            & (Get-Module -Name 'CompleterActions') { $script:TestParseCount } | Should -Be 1 -Because 'the grammar and the target derivation share one parse'
        }
    }

    Context 'Typographic apostrophes in lazy stubs' {
        BeforeAll {
            # Each name pairs the ASCII apostrophe with one typographic single-quote character the
            # tokenizer accepts, written as code points so this file stays ASCII.
            $script:LazyQuoteNames = @(0x2018, 0x2019, 0x201A, 0x201B | ForEach-Object { "lazy'{0}quote" -f [char] $_ })
        }

        AfterEach {
            foreach ($lazyQuoteName in $script:LazyQuoteNames)
            {
                Invoke-TestRuntimeCompleterCleanup -CommandName $lazyQuoteName -CompleterType 'Native'
            }
        }

        It 'registers a target named with U+0027 and U+<Code> lazily and activates it on the first completion' -ForEach @(
            @{ Code = '2018' }
            @{ Code = '2019' }
            @{ Code = '201A' }
            @{ Code = '201B' }
        ) {
            $quote = [string] [char] [Convert]::ToInt32($Code, 16)
            $targetName = "lazy'{0}quote" -f $quote
            $quotedTarget = $targetName.Replace("'", "''").Replace($quote, $quote + $quote)
            $scriptPath = Join-Path -Path $TestDrive -ChildPath "LazyQuote$Code.ps1"
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @"
Register-ArgumentCompleter -Native -CommandName '$quotedTarget' -ScriptBlock {
    param(`$wordToComplete, `$commandAst, `$cursorPosition)

    `$null = `$wordToComplete, `$commandAst, `$cursorPosition

    [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
}
"@

            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty

            $record = Register-Completer -LiteralPath $scriptPath -Lazy -PassThru

            $record.Key | Should -BeExactly $targetName
            $record.State | Should -Be 'Pending'

            $inputScript = "& '$quotedTarget' a"
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length

            @($completion.CompletionMatches.CompletionText) | Should -Be @('alpha')
            (Get-Completer -CommandName $targetName -Native).State | Should -Be 'Active'
        }
    }
}

Describe 'Lazy registration of a native command that shares a parameter target key' {
    BeforeAll {
        $script:LazyIdentityCleanupTargets = @(
            @{ CommandName = 'Test-LazyIdentityTool'; ParameterName = 'Name'; CompleterType = 'Parameter' }
            @{ CommandName = 'Test-LazyIdentityTool:Name'; CompleterType = 'Native' }
        )

        $script:LazyIdentityNativeText = @'
Register-ArgumentCompleter -Native -CommandName 'Test-LazyIdentityTool:Name' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $null = $wordToComplete, $commandAst, $cursorPosition
    'native-result'
}
'@

        $script:LazyIdentityParameterText = @'
Register-ArgumentCompleter -CommandName 'Test-LazyIdentityTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
    'parameter-result'
}
'@

        function Get-TestLazyIdentityCompletion
        {
            $inputScript = 'Test-LazyIdentityTool -Name '
            @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText)
        }

        function Get-TestLazyIdentityState
        {
            @(
                @(Get-Completer -CommandName 'Test-LazyIdentityTool:Name' -Native) + @(Get-Completer -CommandName 'Test-LazyIdentityTool' -ParameterName 'Name') |
                    ForEach-Object { '{0}/{1}' -f $_.CompleterType, $_.State }
            )
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:LazyIdentityCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-LazyIdentityTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }
    }

    AfterEach {
        foreach ($cleanupTarget in $script:LazyIdentityCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-LazyIdentityTool' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'registers both kinds from one script and swaps each target its own script block' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity_both_completer.ps1'
        Set-Content -LiteralPath $scriptPath -Value ($script:LazyIdentityNativeText + [Environment]::NewLine + $script:LazyIdentityParameterText) -Encoding utf8

        $records = @(Register-Completer -LiteralPath $scriptPath -Lazy -PassThru)

        @($records | ForEach-Object { '{0}/{1}' -f $_.CompleterType, $_.State }) | Should -Be @('Native/Pending', 'Parameter/Pending')

        Get-TestLazyIdentityCompletion | Should -Be @('parameter-result')
        Get-TestLazyIdentityState | Should -Be @('Native/Active', 'Parameter/Active') -Because 'one load swaps every Pending target of the script'
        (Get-Completer -CommandName 'Test-LazyIdentityTool:Name' -Native).ScriptText | Should -Match 'native-result'
        (Get-Completer -CommandName 'Test-LazyIdentityTool' -ParameterName 'Name').ScriptText | Should -Match 'parameter-result'
    }

    It 'registers the two kinds from separate scripts and loads only the script of the target pressed' {
        $nativePath = Join-Path -Path $TestDrive -ChildPath 'identity_native_completer.ps1'
        $parameterPath = Join-Path -Path $TestDrive -ChildPath 'identity_parameter_completer.ps1'
        Set-Content -LiteralPath $nativePath -Value $script:LazyIdentityNativeText -Encoding utf8
        Set-Content -LiteralPath $parameterPath -Value $script:LazyIdentityParameterText -Encoding utf8

        $null = Register-Completer -LiteralPath $nativePath -Lazy
        $null = Register-Completer -LiteralPath $parameterPath -Lazy

        Get-TestLazyIdentityState | Should -Be @('Native/Pending', 'Parameter/Pending')
        Get-TestLazyIdentityCompletion | Should -Be @('parameter-result')
        Get-TestLazyIdentityState | Should -Be @('Native/Pending', 'Parameter/Active')
    }
}

Describe 'Lazy registration of native names that lowercase to the same key, or of scripts whose paths differ only in case' {
    BeforeAll {
        # The Kelvin sign (U+212A) lowercases to the letter k, so both Kelvin names
        # have one lowercase key, yet the runtime keeps them as two entries.
        $script:LazyKelvinLetterName = 'Test-LazyKelvinTool'
        $script:LazyKelvinSignName = 'Test-Lazy{0}elvinTool' -f [char] 0x212A

        $script:LazyLookalikeCleanupTargets = @(
            @{ CommandName = $script:LazyKelvinLetterName; CompleterType = 'Native' }
            @{ CommandName = $script:LazyKelvinSignName; CompleterType = 'Native' }
            @{ CommandName = 'test-lazycasex'; CompleterType = 'Native' }
            @{ CommandName = 'test-lazycasey'; CompleterType = 'Native' }
        )

        function Write-TestLazyNativeScript
        {
            param(
                [Parameter(Mandatory)]
                [string] $Path,

                [Parameter(Mandatory)]
                [string[]] $CommandName,

                [Parameter(Mandatory)]
                [string] $Result
            )

            $text = foreach ($commandNameItem in $CommandName)
            {
                "Register-ArgumentCompleter -Native -CommandName '$commandNameItem' -ScriptBlock {"
                '    param($wordToComplete, $commandAst, $cursorPosition)'
                ''
                '    $null = $wordToComplete, $commandAst, $cursorPosition'
                "    '$Result'"
                '}'
            }

            Set-Content -LiteralPath $Path -Value $text -Encoding utf8
        }

        function Get-TestLazyNativeCompletion
        {
            param(
                [Parameter(Mandatory)]
                [string] $CommandName
            )

            $inputScript = "$CommandName "
            @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText)
        }

        function Get-TestLazyNativeState
        {
            param(
                [Parameter(Mandatory)]
                [string[]] $CommandName
            )

            @(
                foreach ($commandNameItem in $CommandName)
                {
                    @(Get-Completer -CommandName $commandNameItem -Native | ForEach-Object { [string] $_.State })
                }
            )
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:LazyLookalikeCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        foreach ($cleanupTarget in $script:LazyLookalikeCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'registers a script for each Kelvin name and loads only the script of the name pressed' {
        $letterPath = Join-Path -Path $TestDrive -ChildPath 'kelvin_letter_completer.ps1'
        $signPath = Join-Path -Path $TestDrive -ChildPath 'kelvin_sign_completer.ps1'
        Write-TestLazyNativeScript -Path $letterPath -CommandName $script:LazyKelvinLetterName -Result 'letter-lazy'
        Write-TestLazyNativeScript -Path $signPath -CommandName $script:LazyKelvinSignName -Result 'sign-lazy'
        $names = $script:LazyKelvinLetterName, $script:LazyKelvinSignName

        $null = Register-Completer -LiteralPath $letterPath -Lazy
        $null = Register-Completer -LiteralPath $signPath -Lazy

        Get-TestLazyNativeState -CommandName $names | Should -Be @('Pending', 'Pending')
        Get-TestLazyNativeCompletion -CommandName $script:LazyKelvinSignName | Should -Be @('sign-lazy')
        Get-TestLazyNativeState -CommandName $names | Should -Be @('Pending', 'Active') -Because 'the stub carries the name it was registered for, not its lowercase key'
        Get-TestLazyNativeCompletion -CommandName $script:LazyKelvinLetterName | Should -Be @('letter-lazy')
        Get-TestLazyNativeState -CommandName $names | Should -Be @('Active', 'Active')
    }

    It 'keeps a sibling registered from the other file pending when one file loads on a case-sensitive file system' -Skip:($IsWindows -or $IsMacOS) {
        $upperPath = Join-Path -Path $TestDrive -ChildPath 'Lazy_case_completer.ps1'
        $lowerPath = Join-Path -Path $TestDrive -ChildPath 'lazy_case_completer.ps1'
        Write-TestLazyNativeScript -Path $upperPath -CommandName 'test-lazycasex', 'test-lazycasey' -Result 'upper'
        Write-TestLazyNativeScript -Path $lowerPath -CommandName 'test-lazycasex', 'test-lazycasey' -Result 'lower'

        $null = Register-Completer -LiteralPath $upperPath -Lazy -CommandName 'test-lazycasex' -Native
        $null = Register-Completer -LiteralPath $lowerPath -Lazy -CommandName 'test-lazycasey' -Native

        Get-TestLazyNativeCompletion -CommandName 'test-lazycasex' | Should -Be @('upper')
        Get-TestLazyNativeState -CommandName 'test-lazycasex', 'test-lazycasey' | Should -Be @('Active', 'Pending') -Because 'the sibling belongs to another file, so loading this one must not swap it'
        Get-TestLazyNativeCompletion -CommandName 'test-lazycasey' | Should -Be @('lower')
    }

    # Safety guard: sibling paths now compare the way the file system does, and on a
    # case-insensitive one that must keep swapping a sibling registered through another
    # spelling of the file, so this passes before and after that change; its Linux
    # sibling above fails before it.
    It 'swaps a sibling registered through another spelling of the same file on a case-insensitive file system' -Skip:(-not ($IsWindows -or $IsMacOS)) {
        $path = Join-Path -Path $TestDrive -ChildPath 'lazy_case_completer.ps1'
        $otherSpelling = Join-Path -Path $TestDrive -ChildPath 'LAZY_CASE_COMPLETER.PS1'
        Write-TestLazyNativeScript -Path $path -CommandName 'test-lazycasex', 'test-lazycasey' -Result 'one'

        $null = Register-Completer -LiteralPath $path -Lazy -CommandName 'test-lazycasex' -Native
        $null = Register-Completer -LiteralPath $otherSpelling -Lazy -CommandName 'test-lazycasey' -Native

        Get-TestLazyNativeCompletion -CommandName 'test-lazycasex' | Should -Be @('one')
        Get-TestLazyNativeState -CommandName 'test-lazycasex', 'test-lazycasey' | Should -Be @('Active', 'Active') -Because 'both spellings name one file, so one load swaps both targets'
    }
}
