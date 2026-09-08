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
}

Describe 'Completer registration public API' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'testnative-managed' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-WhatIfTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayOne' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayNativeOne' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayNativeTwo' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'importfixture' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'importfixture.exe' -CompleterType 'Native'

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'testnative-managed' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-WhatIfTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayOne' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayNativeOne' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayNativeTwo' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'importfixture' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'importfixture.exe' -CompleterType 'Native'

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'registers a managed parameter completer and supports tab expansion' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
        }

        $registration = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $registration.CommandName | Should -Be 'Test-ManagedTool'
        $registration.ParameterName | Should -Be 'Name'
        $registration.CompleterType | Should -Be 'Parameter'
        $registration.Source | Should -Be 'Managed'
        $registration.IsManaged | Should -BeTrue
        $registration.IsRuntimeRegistered | Should -BeTrue

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        $state['Registrations']['test-managedtool:name'] | Should -Not -BeNullOrEmpty

        $inputScript = 'Test-ManagedTool -Name a'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length

        $completion.CompletionMatches.CompletionText | Should -Contain 'alpha'

        $discoveredRegistration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $discoveredRegistration.Source | Should -Be 'Managed'
        $discoveredRegistration.IsRuntimeRegistered | Should -BeTrue
    }

    It 'loads the about help topic for completer imports' {
        $help = Get-Help -Name 'about_Import_Completers' -ErrorAction Stop

        $help.Name | Should -Be 'about_Import_Completers'
        $help.Synopsis | Should -Match 'import standalone completer scripts'
    }

    It 'treats repeated registration with the same script block as idempotent' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('alpha', 'alpha', 'ParameterValue', 'alpha')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru
        $secondRegistration = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $secondRegistration.CommandName | Should -Be 'Test-ManagedTool'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
    }

    It 'registers a managed native completer' {
        $scriptBlock = {
            param($wordToComplete, $commandAst, $cursorPosition)

            [System.Management.Automation.CompletionResult]::new('beta', 'beta', 'ParameterValue', 'beta')
        }

        $registration = Register-CompleterRegistration -Native -CommandName 'testnative-managed' -ScriptBlock $scriptBlock -PassThru

        $registration.CommandName | Should -Be 'testnative-managed'
        $registration.ParameterName | Should -BeNullOrEmpty
        $registration.CompleterType | Should -Be 'Native'
        $registration.Source | Should -Be 'Managed'
        $registration.IsManaged | Should -BeTrue
        $registration.IsRuntimeRegistered | Should -BeTrue

        $resolvedRegistration = Get-CompleterRegistration -Native -CommandName 'testnative-managed'
        $resolvedRegistration.RegistrationKey | Should -Be 'testnative-managed'
        $resolvedRegistration.Source | Should -Be 'Managed'
    }

    It 'discovers unmanaged runtime registrations' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('gamma', 'gamma', 'ParameterValue', 'gamma')
        }

        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $registration = Get-CompleterRegistration -CommandName 'Test-UnmanagedTool' -ParameterName 'Name'

        $registration.CommandName | Should -Be 'Test-UnmanagedTool'
        $registration.Source | Should -Be 'Discovered'
        $registration.IsManaged | Should -BeFalse
        $registration.IsRuntimeRegistered | Should -BeTrue
        $registration.ScriptText | Should -Match 'gamma'
    }

    It 'unregisters managed registrations from module state and runtime' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('delta', 'delta', 'ParameterValue', 'delta')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $removedRegistration = Unregister-CompleterRegistration -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -Confirm:$false -PassThru

        $removedRegistration.CommandName | Should -Be 'Test-RemoveManagedTool'
        $removedRegistration.IsManaged | Should -BeTrue

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-CompleterRegistration -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        {
            Unregister-CompleterRegistration -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*No completer registration was found*'
    }

    It 'does not remove unmanaged runtime registrations without explicit confirmation' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('epsilon', 'epsilon', 'ParameterValue', 'epsilon')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        {
            Unregister-CompleterRegistration -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*-AllowUnmanaged*'

        $registration = Get-CompleterRegistration -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Discovered'
    }

    It 'can remove unmanaged runtime registrations when explicitly requested' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('epsilon', 'epsilon', 'ParameterValue', 'epsilon')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $removedRegistration = Unregister-CompleterRegistration -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru

        $removedRegistration.Source | Should -Be 'Discovered'
        $removedRegistration.IsManaged | Should -BeFalse
        Get-CompleterRegistration -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'supports WhatIf for registration without mutating state' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('zeta', 'zeta', 'ParameterValue', 'zeta')
        }

        Register-CompleterRegistration -CommandName 'Test-WhatIfTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -WhatIf

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-CompleterRegistration -CommandName 'Test-WhatIfTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'uses a concise default table view while preserving full properties for Format-List *' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('eta', 'eta', 'ParameterValue', 'eta')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $registration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $defaultOutput = $registration | Out-String -Width 4096
        $listOutput = $registration | Format-List * | Out-String -Width 4096

        $registration.ScriptBlock | Should -Not -BeNullOrEmpty
        $registration.ScriptText | Should -Match 'eta'

        $defaultOutput | Should -Match '(?m)^\s*Command\s+Parameter\s+Type\s+Source\s+State\s*$'
        $defaultOutput | Should -Match 'Test-ManagedTool'
        $defaultOutput | Should -Not -Match '(?m)^\s*ScriptBlock\s*:'
        $defaultOutput | Should -Not -Match '(?m)^\s*ScriptText\s*:'

        $listOutput | Should -Match '(?m)^\s*ScriptBlock\s*:'
        $listOutput | Should -Match '(?m)^\s*ScriptText\s*:'
    }

    It 'supports paging after merging managed and discovered registrations' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $pagedRegistrations = @(Get-CompleterRegistration -First 1 -Skip 1)

        $pagedRegistrations.Count | Should -Be 1
        $pagedRegistrations[0].Key | Should -Be 'test-unmanagedtool:name'
        $pagedRegistrations[0].Source | Should -Be 'Discovered'
    }

    It 'reports the live conflicted registration once when paging is used' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $registrations = @(Get-CompleterRegistration -IncludeTotalCount)
        $registration = @(Get-CompleterRegistration -First 1)[0]

        $registrations[0] | Should -Be ([uint64] 1)
        $registration.Key | Should -Be 'test-managedtool:name'
        $registration.Source | Should -Be 'Discovered'
        $registration.State | Should -Be 'Conflicted'
        $registration.ScriptText | Should -Match 'discovered'
    }

    It 'applies paging after filtering by source' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $managedRegistrations = @(Get-CompleterRegistration -ManagedOnly -First 1)
        $discoveredRegistrations = @(Get-CompleterRegistration -DiscoveredOnly -First 1)

        $managedRegistrations.Count | Should -Be 1
        $managedRegistrations[0].Source | Should -Be 'Managed'
        $managedRegistrations[0].Key | Should -Be 'test-managedtool:name'

        $discoveredRegistrations.Count | Should -Be 1
        $discoveredRegistrations[0].Source | Should -Be 'Discovered'
        $discoveredRegistrations[0].Key | Should -Be 'test-unmanagedtool:name'
    }

    It 'returns total count metadata before paged results' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $results = @(Get-CompleterRegistration -First 1 -IncludeTotalCount)

        $results.Count | Should -Be 2
        $results[0] | Should -BeOfType ([System.UInt64])
        $results[0] | Should -Be ([uint64] 2)
        $results[1].Key | Should -Be 'test-managedtool:name'
    }

    It 'returns no registrations when paging skips past the filtered result set' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru

        $results = @(Get-CompleterRegistration -ManagedOnly -First 1 -Skip 1)

        $results | Should -BeNullOrEmpty
    }

    It 'supports command and parameter arrays for registration and lookup' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('theta', 'theta', 'ParameterValue', 'theta')
        }

        $registrations = @(Register-CompleterRegistration -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' -ScriptBlock $scriptBlock -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')

        $resolvedRegistrations = @(Get-CompleterRegistration -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path')
        @($resolvedRegistrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')
    }

    It 'supports native command arrays for registration and lookup' {
        $scriptBlock = {
            param($wordToComplete, $commandAst, $cursorPosition)

            [System.Management.Automation.CompletionResult]::new('iota', 'iota', 'ParameterValue', 'iota')
        }

        $registrations = @(Register-CompleterRegistration -CommandName 'Test-ArrayNativeOne', 'Test-ArrayNativeTwo' -Native -ScriptBlock $scriptBlock -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arraynativeone', 'test-arraynativetwo')

        $resolvedRegistrations = @(Get-CompleterRegistration -CommandName 'Test-ArrayNativeOne', 'Test-ArrayNativeTwo' -Native)
        @($resolvedRegistrations.Key | Sort-Object) | Should -Be @('test-arraynativeone', 'test-arraynativetwo')
    }

    It 'supports property-name pipeline binding for get by key' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('kappa', 'kappa', 'ParameterValue', 'kappa')
        }

        $registration = Register-CompleterRegistration -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $resolved = [pscustomobject] @{ RegistrationKey = $registration.Key } | Get-CompleterRegistration

        $resolved.Key | Should -Be 'test-pipelinemanagedtool:name'
    }

    It 'supports pipeline unregister from get output' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('lambda', 'lambda', 'ParameterValue', 'lambda')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $removed = @(Get-CompleterRegistration -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' | Unregister-CompleterRegistration -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].Key | Should -Be 'test-pipelinemanagedtool:name'
        Get-CompleterRegistration -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'supports unregister input objects in batches' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('mu', 'mu', 'ParameterValue', 'mu')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' -ScriptBlock $scriptBlock -PassThru
        $registrations = @(Get-CompleterRegistration -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path')

        $removed = @($registrations | Unregister-CompleterRegistration -Confirm:$false -PassThru)

        $removed.Count | Should -Be 2
        Get-CompleterRegistration -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' | Should -BeNullOrEmpty
    }

    It 'supports register input objects with script blocks' {
        $inputObjects = @(
            [pscustomobject] @{
                CommandName = 'Test-ArrayOne'
                ParameterName = 'Name'
                ScriptBlock = {
                    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                    [System.Management.Automation.CompletionResult]::new('nu', 'nu', 'ParameterValue', 'nu')
                }
            },
            [pscustomobject] @{
                CommandName = 'Test-ArrayTwo'
                ParameterName = 'Path'
                ScriptBlock = {
                    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                    [System.Management.Automation.CompletionResult]::new('xi', 'xi', 'ParameterValue', 'xi')
                }
            }
        )

        $registrations = @($inputObjects | Register-CompleterRegistration -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')
    }

    It 'throws for invalid register input objects' {
        {
            [pscustomobject] @{ CommandName = 'Test-ArrayOne' } | Register-CompleterRegistration -PassThru
        } | Should -Throw '*Failed to resolve a completer target from InputObject*'
    }

    It 'imports supported completer scripts without mutating runtime and produces register-compatible objects' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $importedRegistrations = @(Import-CompleterScript -LiteralPath $fixturePath)

        $importedRegistrations.Count | Should -Be 2
        @($importedRegistrations.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
        $importedRegistrations[0].Source | Should -Be 'Imported'
        $importedRegistrations[0].Path | Should -Be $fixturePath
        $importedRegistrations[0].ScriptBlock.Module | Should -Not -BeNullOrEmpty

        Get-CompleterRegistration -Native -CommandName 'importfixture' | Should -BeNullOrEmpty

        $commandAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'importfixture a',
            [ref] $null,
            [ref] $null
        ).EndBlock.Statements[0].PipelineElements[0]

        $completionMatches = @(& $importedRegistrations[0].ScriptBlock 'a' $commandAst 15)
        $completionMatches.CompletionText | Should -Contain 'alpha'

        $registered = @($importedRegistrations | Register-CompleterRegistration -PassThru)
        $registered.Count | Should -Be 2
        @($registered.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
    }

    It 'rejects unsupported dynamic Register-ArgumentCompleter arguments during import' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\UnsupportedDynamicCompleter.ps1'

        {
            Import-CompleterScript -LiteralPath $fixturePath
        } | Should -Throw '*must use literal string values for -CommandName*'
    }

    It 'requires allow unmanaged for pipeline removal of discovered registrations' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('omicron', 'omicron', 'ParameterValue', 'omicron')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        {
            Get-CompleterRegistration -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' |
                Unregister-CompleterRegistration -Confirm:$false
        } | Should -Throw '*-AllowUnmanaged*'
    }

    It 'rolls back a fresh registration when the managed store write fails' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('new', 'new', 'ParameterValue', 'new')
        }

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-ManagedCompleterRegistration { throw 'forced managed-state failure' }
        }

        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        } | Should -Throw '*forced managed-state failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'restores the previous registration when a forced replacement fails to update the managed store' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $oldScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('old', 'old', 'ParameterValue', 'old')
        }

        $newScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('new', 'new', 'ParameterValue', 'new')
        }

        $original = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-ManagedCompleterRegistration { throw 'forced managed-state failure' }
        }

        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force
        } | Should -Throw '*forced managed-state failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        [object]::ReferenceEquals($state['Registrations']['test-managedtool:name'], $original) | Should -BeTrue

        $registration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Managed'
        $registration.State | Should -Be 'Active'
        $registration.ScriptText | Should -Match 'old'

        $inputScript = 'Test-ManagedTool -Name o'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('old')
    }

    It 'leaves the previous registration untouched when a forced replacement fails to write the runtime' {
        $oldScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('old', 'old', 'ParameterValue', 'old')
        }

        $newScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('new', 'new', 'ParameterValue', 'new')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-RuntimeCompleterRegistration { throw 'forced runtime-write failure' }
        }

        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force
        } | Should -Throw '*forced runtime-write failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        $state['Registrations']['test-managedtool:name'].ScriptText | Should -Match 'old'

        $registration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Managed'
        $registration.State | Should -Be 'Active'
        $registration.ScriptText | Should -Match 'old'
    }

    It 'reports a rollback failure separately from the registration failure' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('new', 'new', 'ParameterValue', 'new')
        }

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-ManagedCompleterRegistration { throw 'forced managed-state failure' }
            function script:Remove-RuntimeCompleterRegistration { throw 'forced rollback failure' }
        }

        $thrown = $null
        try
        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        }
        catch
        {
            $thrown = $_
        }

        $thrown | Should -Not -BeNullOrEmpty
        $thrown.Exception.Message | Should -Match 'forced managed-state failure'
        $thrown.Exception.Message | Should -Match 'Rollback of the previous runtime and managed state also failed'
        $thrown.Exception.Message | Should -Match 'forced rollback failure'
    }

    It 'treats a managed record as stale after the runtime is overwritten outside the module' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $oldScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('old', 'old', 'ParameterValue', 'old')
        }

        $externalScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock

        $inputScript = 'Test-ManagedTool -Name '
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        $liveRegistration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $liveRegistration.Source | Should -Be 'Discovered'
        $liveRegistration.State | Should -Be 'Conflicted'
        $liveRegistration.IsManaged | Should -BeFalse
        $liveRegistration.ScriptText | Should -Match 'external'

        $managedRegistration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ManagedOnly
        $managedRegistration.Source | Should -Be 'Managed'
        $managedRegistration.State | Should -Be 'Stale'
        $managedRegistration.IsRuntimeRegistered | Should -BeFalse
        $managedRegistration.ScriptText | Should -Match 'old'

        $discoveredRegistration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -DiscoveredOnly
        $discoveredRegistration.State | Should -Be 'Conflicted'
        $discoveredRegistration.ScriptText | Should -Match 'external'

        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock
        } | Should -Throw '*is stale*Use -Force*'

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        {
            Unregister-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*is stale*-AllowUnmanaged*'

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        $removed = Unregister-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru
        $removed.Source | Should -Be 'Discovered'
        $removed.ScriptText | Should -Match 'external'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'reconciles a stale managed record with a forced registration' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $oldScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('old', 'old', 'ParameterValue', 'old')
        }

        $externalScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
        }

        $newScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('new', 'new', 'ParameterValue', 'new')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock

        $registration = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force -PassThru

        $registration.State | Should -Be 'Active'

        $resolved = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $resolved.Source | Should -Be 'Managed'
        $resolved.State | Should -Be 'Active'
        $resolved.ScriptText | Should -Match 'new'

        $inputScript = 'Test-ManagedTool -Name '
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('new')
    }

    It 'treats a managed record as stale after the runtime entry is removed outside the module' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('old', 'old', 'ParameterValue', 'old')
        }

        $null = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'

        $registration = Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Managed'
        $registration.State | Should -Be 'Stale'
        $registration.IsRuntimeRegistered | Should -BeFalse

        Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -DiscoveredOnly | Should -BeNullOrEmpty

        {
            Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        } | Should -Throw '*is stale*Use -Force*'

        $reregistered = Register-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -Force -PassThru
        $reregistered.State | Should -Be 'Active'
        (Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name').State | Should -Be 'Active'

        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'

        $removed = Unregister-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' -Confirm:$false -PassThru
        $removed.Source | Should -Be 'Managed'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-CompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }
}
