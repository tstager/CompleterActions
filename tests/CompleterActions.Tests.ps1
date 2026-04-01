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

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'testnative-managed' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-WhatIfTool' -ParameterName 'Name' -CompleterType 'Parameter'

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

        $defaultOutput | Should -Match '(?m)^\s*Command\s+Parameter\s+Type\s+Source\s*$'
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

    It 'keeps managed registrations preferred when paging is used' {
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

        $registration = @(Get-CompleterRegistration -First 1)[0]

        $registration.Key | Should -Be 'test-managedtool:name'
        $registration.Source | Should -Be 'Managed'
        $registration.ScriptText | Should -Match 'managed'
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
}
