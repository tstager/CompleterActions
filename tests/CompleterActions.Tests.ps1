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
        Invoke-TestRuntimeCompleterCleanup -CommandName 'C:\completeractions-tests\drive-tool.exe' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'C:/completeractions-tests/drive-script.ps1' -ParameterName 'Name' -CompleterType 'Parameter'

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
        Invoke-TestRuntimeCompleterCleanup -CommandName 'C:\completeractions-tests\drive-tool.exe' -CompleterType 'Native'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'C:/completeractions-tests/drive-script.ps1' -ParameterName 'Name' -CompleterType 'Parameter'

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

        $registration = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

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

        $discoveredRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru
        $secondRegistration = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

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

        $registration = Register-Completer -Native -CommandName 'testnative-managed' -ScriptBlock $scriptBlock -PassThru

        $registration.CommandName | Should -Be 'testnative-managed'
        $registration.ParameterName | Should -BeNullOrEmpty
        $registration.CompleterType | Should -Be 'Native'
        $registration.Source | Should -Be 'Managed'
        $registration.IsManaged | Should -BeTrue
        $registration.IsRuntimeRegistered | Should -BeTrue

        $resolvedRegistration = Get-Completer -Native -CommandName 'testnative-managed'
        $resolvedRegistration.RegistrationKey | Should -Be 'testnative-managed'
        $resolvedRegistration.Source | Should -Be 'Managed'
    }

    It 'discovers unmanaged runtime registrations' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('gamma', 'gamma', 'ParameterValue', 'gamma')
        }

        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $registration = Get-Completer -CommandName 'Test-UnmanagedTool' -ParameterName 'Name'

        $registration.CommandName | Should -Be 'Test-UnmanagedTool'
        $registration.Source | Should -Be 'Discovered'
        $registration.IsManaged | Should -BeFalse
        $registration.IsRuntimeRegistered | Should -BeTrue
        $registration.ScriptText | Should -Match 'gamma'
    }

    It 'lists managed native and parameter registrations alongside a parameter-only registration made outside the module' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name,
                [string] $CompleterActionsGlobalParam
            )
        }

        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $nativeScriptBlock = {
            param($wordToComplete, $commandAst, $cursorPosition)

            [System.Management.Automation.CompletionResult]::new('native', 'native', 'ParameterValue', 'native')
        }

        $parameterOnlyScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('global-parameter', 'global-parameter', 'ParameterValue', 'global-parameter')
        }

        Register-ArgumentCompleter -ParameterName 'CompleterActionsGlobalParam' -ScriptBlock $parameterOnlyScriptBlock

        try
        {
            $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock
            $null = Register-Completer -CommandName 'testnative-managed' -Native -ScriptBlock $nativeScriptBlock

            $registrations = @(Get-Completer -Verbose 4>&1)
            $verboseMessages = @($registrations | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            $records = @($registrations | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })

            @($records.Key) | Should -Contain 'test-managedtool:name'
            @($records.Key) | Should -Contain 'testnative-managed'
            @($records.Key) | Should -Not -Contain 'completeractionsglobalparam'
            @($verboseMessages | Where-Object { $_ -match "parameter-only completer registration 'CompleterActionsGlobalParam'" }).Count | Should -Be 1

            @(Get-Completer -DiscoveredOnly).Key | Should -Not -Contain 'completeractionsglobalparam'
            Get-Completer -CommandName 'CompleterActionsGlobalParam' -Native | Should -BeNullOrEmpty

            $removed = @(Get-Completer -ManagedOnly | Unregister-Completer -Confirm:$false -PassThru)
            @($removed.Key | Sort-Object) | Should -Be @('test-managedtool:name', 'testnative-managed')

            $inputScript = 'Test-ManagedTool -CompleterActionsGlobalParam '
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            $completion.CompletionMatches.CompletionText | Should -Contain 'global-parameter' -Because 'the parameter-only registration is left untouched'
        }
        finally
        {
            & (Get-Module -Name 'CompleterActions') {
                $null = (Get-CompleterRuntime).CustomArgumentCompleters.Remove('CompleterActionsGlobalParam')
            }
        }
    }

    It 'unregisters managed registrations from module state and runtime' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('delta', 'delta', 'ParameterValue', 'delta')
        }

        $null = Register-Completer -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $removedRegistration = Unregister-Completer -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -Confirm:$false -PassThru

        $removedRegistration.CommandName | Should -Be 'Test-RemoveManagedTool'
        $removedRegistration.IsManaged | Should -BeTrue

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty

        {
            Unregister-Completer -CommandName 'Test-RemoveManagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*No completer registration was found*'
    }

    It 'does not remove unmanaged runtime registrations without explicit confirmation' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('epsilon', 'epsilon', 'ParameterValue', 'epsilon')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        {
            Unregister-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*-AllowUnmanaged*'

        $registration = Get-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Discovered'
    }

    It 'can remove unmanaged runtime registrations when explicitly requested' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('epsilon', 'epsilon', 'ParameterValue', 'epsilon')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $removedRegistration = Unregister-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru

        $removedRegistration.Source | Should -Be 'Discovered'
        $removedRegistration.IsManaged | Should -BeFalse
        Get-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'supports WhatIf for registration without mutating state' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('zeta', 'zeta', 'ParameterValue', 'zeta')
        }

        Register-Completer -CommandName 'Test-WhatIfTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -WhatIf

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-WhatIfTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'uses a concise default table view while preserving full properties for Format-List *' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('eta', 'eta', 'ParameterValue', 'eta')
        }

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $registration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $defaultOutput = $registration | Out-String -Width 4096
        $listOutput = $registration | Format-List * | Out-String -Width 4096

        $registration.ScriptBlock | Should -Not -BeNullOrEmpty
        $registration.ScriptText | Should -Match 'eta'

        $defaultOutput | Should -Match '(?m)^\s*Command\s+Parameter\s+Type\s+Source\s+State\s+ScriptPath\s+LoadError\s*$'
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $pagedRegistrations = @(Get-Completer -First 1 -Skip 1)

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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $registrations = @(Get-Completer -IncludeTotalCount)
        $registration = @(Get-Completer -First 1)[0]

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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $managedRegistrations = @(Get-Completer -ManagedOnly -First 1)
        $discoveredRegistrations = @(Get-Completer -DiscoveredOnly -First 1)

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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $results = @(Get-Completer -First 1 -IncludeTotalCount)

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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru

        $results = @(Get-Completer -ManagedOnly -First 1 -Skip 1)

        $results | Should -BeNullOrEmpty
    }

    It 'supports command and parameter arrays for registration and lookup' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('theta', 'theta', 'ParameterValue', 'theta')
        }

        $registrations = @(Register-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' -ScriptBlock $scriptBlock -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')

        $resolvedRegistrations = @(Get-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path')
        @($resolvedRegistrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')
    }

    It 'supports native command arrays for registration and lookup' {
        $scriptBlock = {
            param($wordToComplete, $commandAst, $cursorPosition)

            [System.Management.Automation.CompletionResult]::new('iota', 'iota', 'ParameterValue', 'iota')
        }

        $registrations = @(Register-Completer -CommandName 'Test-ArrayNativeOne', 'Test-ArrayNativeTwo' -Native -ScriptBlock $scriptBlock -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arraynativeone', 'test-arraynativetwo')

        $resolvedRegistrations = @(Get-Completer -CommandName 'Test-ArrayNativeOne', 'Test-ArrayNativeTwo' -Native)
        @($resolvedRegistrations.Key | Sort-Object) | Should -Be @('test-arraynativeone', 'test-arraynativetwo')
    }

    It 'resolves registration records piped back into get through their key and native indicator' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('kappa', 'kappa', 'ParameterValue', 'kappa')
        }

        $registration = Register-Completer -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $resolved = @($registration | Get-Completer)
        $resolved.Count | Should -Be 1
        $resolved[0].Key | Should -Be 'test-pipelinemanagedtool:name'

        $byKeyAndIndicator = @([pscustomobject] @{ RegistrationKey = $registration.Key; IsNative = $false } | Get-Completer)
        $byKeyAndIndicator.Count | Should -Be 1
        $byKeyAndIndicator[0].Key | Should -Be 'test-pipelinemanagedtool:name'
    }

    It 'rejects a bare key input object with no native indicator on <Command>' -TestCases @(
        @{ Command = 'Get-Completer'; Run = { [pscustomobject] @{ RegistrationKey = 'test-pipelinemanagedtool:name' } | Get-Completer } },
        @{ Command = 'Register-Completer'; Run = { [pscustomobject] @{ Key = 'Test-PipelineManagedTool:Name'; ScriptBlock = { 'kappa' } } | Register-Completer } },
        @{ Command = 'Unregister-Completer'; Run = { [pscustomobject] @{ RuntimeKey = 'Test-PipelineManagedTool:Name' } | Unregister-Completer -Confirm:$false } },
        @{ Command = 'Test-CompleterRegistration'; Run = { [pscustomobject] @{ Key = 'test-pipelinemanagedtool:name' } | Test-CompleterRegistration -InputText 'Test-PipelineManagedTool -Name k' } }
    ) {
        param($Run)

        $Run | Should -Throw '*without an IsNative or Native property*about_CompleterActions_Migration*'
    }

    It 'no longer exposes a typed Key parameter on <Command>' -TestCases @(
        @{ Command = 'Get-Completer' },
        @{ Command = 'Unregister-Completer' },
        @{ Command = 'Test-CompleterRegistration' }
    ) {
        param($Command)

        $command = Get-Command -Name $Command -Module 'CompleterActions'

        $command.Parameters.ContainsKey('Key') | Should -BeFalse
        $command.Parameters.ContainsKey('RegistrationKey') | Should -BeFalse
        $command.ParameterSets.Name | Should -Not -Contain 'ByKey'
    }

    It 'supports pipeline unregister from get output' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('lambda', 'lambda', 'ParameterValue', 'lambda')
        }

        $null = Register-Completer -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru

        $removed = @(Get-Completer -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' | Unregister-Completer -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].Key | Should -Be 'test-pipelinemanagedtool:name'
        Get-Completer -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'supports unregister input objects in batches' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('mu', 'mu', 'ParameterValue', 'mu')
        }

        $null = Register-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' -ScriptBlock $scriptBlock -PassThru
        $registrations = @(Get-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path')

        $removed = @($registrations | Unregister-Completer -Confirm:$false -PassThru)

        $removed.Count | Should -Be 2
        Get-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' | Should -BeNullOrEmpty
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

        $registrations = @($inputObjects | Register-Completer -PassThru)

        $registrations.Count | Should -Be 2
        @($registrations.Key | Sort-Object) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')
    }

    It 'throws for invalid register input objects' {
        {
            [pscustomobject] @{ CommandName = 'Test-ArrayOne' } | Register-Completer -PassThru
        } | Should -Throw '*Failed to resolve a completer target from InputObject*'
    }

    It 'registers, finds, and removes a drive-qualified native path supplied as an explicit native target' {
        $nativePath = 'C:\completeractions-tests\drive-tool.exe'
        $scriptBlock = {
            param($wordToComplete, $commandAst, $cursorPosition)

            [System.Management.Automation.CompletionResult]::new('drivealpha', 'drivealpha', 'ParameterValue', 'drivealpha')
        }

        $registration = [pscustomobject] @{ CommandName = $nativePath; IsNative = $true; ScriptBlock = $scriptBlock } | Register-Completer -PassThru

        $registration.Key | Should -Be $nativePath.ToLowerInvariant()
        $registration.CommandName | Should -Be $nativePath
        $registration.ParameterName | Should -BeNullOrEmpty
        $registration.CompleterType | Should -Be 'Native'
        $registration.IsRuntimeRegistered | Should -BeTrue

        $inputScript = '{0} d' -f $nativePath
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'drivealpha'

        $found = Get-Completer -CommandName $nativePath -Native
        $found.CompleterType | Should -Be 'Native'
        $found.CommandName | Should -Be $nativePath
        $found.Source | Should -Be 'Managed'
        ($registration | Get-Completer).Key | Should -Be $found.Key

        $removed = @(Unregister-Completer -CommandName $nativePath -Native -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].CompleterType | Should -Be 'Native'
        Get-Completer -CommandName $nativePath -Native | Should -BeNullOrEmpty

        $completionAfterRemoval = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completionAfterRemoval.CompletionMatches.CompletionText | Should -Not -Contain 'drivealpha'
    }

    It 'registers a forward-slash drive-qualified script path with an explicit parameter name as a parameter target' {
        $key = 'C:/completeractions-tests/drive-script.ps1:Name'
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('drivescript', 'drivescript', 'ParameterValue', 'drivescript')
        }

        $registration = [pscustomobject] @{ CommandName = 'C:/completeractions-tests/drive-script.ps1'; ParameterName = 'Name'; ScriptBlock = $scriptBlock } | Register-Completer -PassThru

        $registration.CompleterType | Should -Be 'Parameter'
        $registration.CommandName | Should -Be 'C:/completeractions-tests/drive-script.ps1'
        $registration.ParameterName | Should -Be 'Name'
        $registration.Key | Should -Be $key.ToLowerInvariant()
        $registration.IsRuntimeRegistered | Should -BeTrue

        $runtimeTables = InModuleScope CompleterActions {
            $runtime = Get-CompleterRuntime

            [pscustomobject] @{
                InParameterTable = Test-CompleterRuntimeDictionaryKey -Dictionary $runtime.CustomArgumentCompleters -Key 'C:/completeractions-tests/drive-script.ps1:Name'
                InNativeTable    = Test-CompleterRuntimeDictionaryKey -Dictionary $runtime.NativeArgumentCompleters -Key 'C:/completeractions-tests/drive-script.ps1:Name'
            }
        }

        $runtimeTables.InParameterTable | Should -BeTrue
        $runtimeTables.InNativeTable | Should -BeFalse

        $found = Get-Completer -CommandName 'C:/completeractions-tests/drive-script.ps1' -ParameterName 'Name'
        $found.Source | Should -Be 'Managed'
        $found.Key | Should -Be $key.ToLowerInvariant()

        $removed = @($registration | Unregister-Completer -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].CompleterType | Should -Be 'Parameter'
        Get-Completer -CommandName 'C:/completeractions-tests/drive-script.ps1' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'resolves a key input object only through its native indicator, never its shape' {
        $results = InModuleScope CompleterActions {
            foreach ($key in 'Get-Item:Path', 'git', 'C:\tools\example.exe', 'C:/scripts/Do-Thing.ps1:Name')
            {
                foreach ($propertyName in 'Key', 'RegistrationKey', 'RuntimeKey')
                {
                    $bareError = $null
                    try { $null = [pscustomobject] @{ $propertyName = $key } | Resolve-CompleterInputObject } catch { $bareError = $_.Exception.Message }

                    [pscustomobject] @{
                        Key          = $key
                        PropertyName = $propertyName
                        BareError    = $bareError
                        NativeType   = ([pscustomobject] @{ $propertyName = $key; IsNative = $true } | Resolve-CompleterInputObject).Target.TargetType
                    }
                }
            }
        }

        $results.Count | Should -Be 12

        foreach ($result in $results)
        {
            $result.BareError | Should -BeLike "*supplies the key '$($result.Key)' without an IsNative or Native property*about_CompleterActions_Migration*"
            $result.NativeType | Should -Be 'Native'
        }

        $parameterTypes = InModuleScope CompleterActions {
            @(
                ([pscustomobject] @{ Key = 'Get-Item:Path'; IsNative = $false } | Resolve-CompleterInputObject).Target.TargetType
                ([pscustomobject] @{ RuntimeKey = 'C:/scripts/Do-Thing.ps1:Name'; Native = $false } | Resolve-CompleterInputObject).Target.TargetType
            )
        }

        $parameterTypes | Should -Be @('CommandParameter', 'CommandParameter')
    }

    It 'no longer resolves target lists from keys' {
        InModuleScope CompleterActions {
            (Get-Command -Name Resolve-CompleterTargetList).Parameters.ContainsKey('Key') | Should -BeFalse
            Get-Command -Name Test-CompleterNativeKeyShape -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'imports supported completer scripts without mutating runtime and produces register-compatible objects' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $importedRegistrations = @(Import-CompleterScript -LiteralPath $fixturePath)

        $importedRegistrations.Count | Should -Be 2
        @($importedRegistrations.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
        $importedRegistrations[0].Source | Should -Be 'Imported'
        $importedRegistrations[0].Path | Should -Be $fixturePath
        $importedRegistrations[0].ScriptBlock.Module | Should -Not -BeNullOrEmpty

        Get-Completer -Native -CommandName 'importfixture' | Should -BeNullOrEmpty

        $commandAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'importfixture a',
            [ref] $null,
            [ref] $null
        ).EndBlock.Statements[0].PipelineElements[0]

        $completionMatches = @(& $importedRegistrations[0].ScriptBlock 'a' $commandAst 15)
        $completionMatches.CompletionText | Should -Contain 'alpha'

        $registered = @($importedRegistrations | Register-Completer -PassThru)
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
            Get-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' |
                Unregister-Completer -Confirm:$false
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
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        } | Should -Throw '*forced managed-state failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
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

        $original = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-ManagedCompleterRegistration { throw 'forced managed-state failure' }
        }

        {
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force
        } | Should -Throw '*forced managed-state failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        [object]::ReferenceEquals($state['Registrations']['test-managedtool:name'], $original) | Should -BeTrue

        $registration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru

        & (Get-Module -Name 'CompleterActions') {
            function script:Add-RuntimeCompleterRegistration { throw 'forced runtime-write failure' }
        }

        {
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force
        } | Should -Throw '*forced runtime-write failure*'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        $state['Registrations']['test-managedtool:name'].ScriptText | Should -Match 'old'

        $registration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
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
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
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

    It 'keeps the earlier targets of one call when a later target fails to write' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('batch', 'batch', 'ParameterValue', 'batch')
        }

        & (Get-Module -Name 'CompleterActions') {
            $script:TestManagedWriteFunction = ${function:Add-ManagedCompleterRegistration}

            function script:Add-ManagedCompleterRegistration
            {
                param($Registration)

                if ($Registration.Key -eq 'test-arraytwo:path')
                {
                    throw 'forced write failure'
                }

                & $script:TestManagedWriteFunction -Registration $Registration
            }
        }

        $thrown = {
            Register-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayTwo' -ParameterName 'Name', 'Path' -ScriptBlock $scriptBlock
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -Be "Failed to register the completer 'Test-ArrayTwo:Path'. forced write failure"

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1
        $state['Registrations'].Contains('test-arrayone:name') | Should -BeTrue

        $kept = Get-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name'
        $kept.Source | Should -Be 'Managed'
        $kept.State | Should -Be 'Active'
        Get-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' | Should -BeNullOrEmpty
    }

    It 'keeps the earlier targets of one call when a later target conflicts' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $externalScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
        }

        Register-ArgumentCompleter -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -ScriptBlock $externalScriptBlock

        {
            Register-Completer -InputObject @(
                [pscustomobject] @{ CommandName = 'Test-ArrayOne'; ParameterName = 'Name'; ScriptBlock = $scriptBlock },
                [pscustomobject] @{ CommandName = 'Test-ArrayTwo'; ParameterName = 'Path'; ScriptBlock = $scriptBlock }
            )
        } | Should -Throw "*Failed to register the completer 'Test-ArrayTwo:Path'. A runtime completer registration already exists for 'Test-ArrayTwo:Path'. Use -Force to replace it.*"

        $kept = Get-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' -ManagedOnly
        $kept.Source | Should -Be 'Managed'
        $kept.State | Should -Be 'Active'
        $kept.ScriptText | Should -Match 'managed'

        $external = Get-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path'
        $external.Source | Should -Be 'Discovered'
        $external.ScriptText | Should -Match 'external'
    }

    It 'resolves a repeated target under -WhatIf on its own and returns nothing for it' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('repeat', 'repeat', 'ParameterValue', 'repeat')
        }

        $registrations = @(Register-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayOne' -ParameterName 'Name', 'Name' -ScriptBlock $scriptBlock -WhatIf -PassThru)

        $registrations.Count | Should -Be 0

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'resolves a target repeated within one call against the earlier registration of that call' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('repeat', 'repeat', 'ParameterValue', 'repeat')
        }

        $registrations = @(Register-Completer -CommandName 'Test-ArrayOne', 'Test-ArrayOne' -ParameterName 'Name', 'Name' -ScriptBlock $scriptBlock -PassThru)

        $registrations.Count | Should -Be 2
        [object]::ReferenceEquals($registrations[0], $registrations[1]) | Should -BeTrue

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 1

        $otherScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('other', 'other', 'ParameterValue', 'other')
        }

        {
            Register-Completer -InputObject @(
                [pscustomobject] @{ CommandName = 'Test-ArrayTwo'; ParameterName = 'Path'; ScriptBlock = $scriptBlock },
                [pscustomobject] @{ CommandName = 'Test-ArrayTwo'; ParameterName = 'Path'; ScriptBlock = $otherScriptBlock }
            )
        } | Should -Throw "*Failed to register the completer 'Test-ArrayTwo:Path'. A module-managed completer registration already exists for 'Test-ArrayTwo:Path'. Use -Force to replace it.*"

        $first = Get-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -ManagedOnly
        $first.Source | Should -Be 'Managed'
        $first.State | Should -Be 'Active'
        $first.ScriptText | Should -Match 'repeat'
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock

        $inputScript = 'Test-ManagedTool -Name '
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        $liveRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $liveRegistration.Source | Should -Be 'Discovered'
        $liveRegistration.State | Should -Be 'Conflicted'
        $liveRegistration.IsManaged | Should -BeFalse
        $liveRegistration.ScriptText | Should -Match 'external'

        $managedRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ManagedOnly
        $managedRegistration.Source | Should -Be 'Managed'
        $managedRegistration.State | Should -Be 'Stale'
        $managedRegistration.IsRuntimeRegistered | Should -BeFalse
        $managedRegistration.ScriptText | Should -Match 'old'

        $discoveredRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -DiscoveredOnly
        $discoveredRegistration.State | Should -Be 'Conflicted'
        $discoveredRegistration.ScriptText | Should -Match 'external'

        {
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock
        } | Should -Throw '*is stale*Use -Force*'

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        {
            Unregister-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -Confirm:$false
        } | Should -Throw '*is stale*-AllowUnmanaged*'

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('external')

        $removed = Unregister-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru
        $removed.Source | Should -Be 'Discovered'
        $removed.ScriptText | Should -Match 'external'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock

        $registration = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $newScriptBlock -Force -PassThru

        $registration.State | Should -Be 'Active'

        $resolved = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'

        $registration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        $registration.Source | Should -Be 'Managed'
        $registration.State | Should -Be 'Stale'
        $registration.IsRuntimeRegistered | Should -BeFalse

        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -DiscoveredOnly | Should -BeNullOrEmpty

        {
            Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        } | Should -Throw '*is stale*Use -Force*'

        $reregistered = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -Force -PassThru
        $reregistered.State | Should -Be 'Active'
        (Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name').State | Should -Be 'Active'

        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ManagedTool' -ParameterName 'Name' -CompleterType 'Parameter'

        $removed = Unregister-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -Confirm:$false -PassThru
        $removed.Source | Should -Be 'Managed'

        $state = InModuleScope CompleterActions {
            Get-CompleterActionState
        }

        $state['Registrations'].Count | Should -Be 0
        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }
}
