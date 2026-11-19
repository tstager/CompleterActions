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
            if ([string]::Equals($candidateKey, $targetKey, [System.StringComparison]::OrdinalIgnoreCase))
            {
                $null = $registrations.Remove($candidateKey)
                break
            }
        }
    }

    function Invoke-TestBuildHelp
    {
        param(
            [Parameter(Mandatory)]
            [scriptblock] $Script
        )

        $manifestPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'build', 'CompleterActions', 'CompleterActions.psd1'))

        $output = & pwsh -NoProfile -NonInteractive -Command {
            param($ManifestPath, $ScriptText)

            $ErrorActionPreference = 'Stop'
            Import-Module -Name $ManifestPath -Force

            if ((Get-Module -Name 'CompleterActions').ModuleBase -ne (Split-Path -Path $ManifestPath -Parent))
            {
                throw 'wrong ModuleBase'
            }

            & ([scriptblock]::Create($ScriptText))
        } -args $manifestPath, $Script.ToString()

        if ($LASTEXITCODE -ne 0)
        {
            throw "Invoke-TestBuildHelp: the child pwsh exited with code $LASTEXITCODE."
        }

        $output
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
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayOne' -ParameterName 'Path' -CompleterType 'Parameter'
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
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ArrayOne' -ParameterName 'Path' -CompleterType 'Parameter'
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
        InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' } | Should -Not -BeNullOrEmpty

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

    It 'loads the about help topic for the 3.0 migration' {
        $help = Get-Help -Name 'about_CompleterActions_Migration' -ErrorAction Stop

        $help.Name | Should -Be 'about_CompleterActions_Migration'
        $help.Synopsis | Should -Match 'changed in CompleterActions 3.0.0'
    }

    It 'has the 3.0 migration guide' {
        $text = @(
            Invoke-TestBuildHelp -Script {
                Get-Help -Name 'about_CompleterActions_Migration' -ErrorAction Stop | Out-String -Width 4096
            }
        ) -join "`n"

        $text | Should -Match ([regex]::Escape('3.0'))
        foreach ($removedName in 'Get-CompleterRegistration', 'Register-CompleterRegistration', 'Unregister-CompleterRegistration', 'Get-CompleterRegistrationLegacy', 'Register-CompleterRegistrationLegacy', 'Unregister-CompleterRegistrationLegacy')
        {
            $text | Should -Match ('(?<![\w-]){0}(?![\w-])' -f [regex]::Escape($removedName)) -Because "the guide maps $removedName"
        }
        $text | Should -Match ([regex]::Escape('[CompleterActions.CompleterRegistration]'))
        $text | Should -Match 'PowerShellVersion'
        $text | Should -Match ([regex]::Escape('7.4'))

        $headings = @($text -split '\r?\n' | Where-Object { $_ -match '^\S' } | ForEach-Object { $_.TrimEnd() })
        $headings | Should -Be @('TOPIC', 'SYNOPSIS', 'LONG DESCRIPTION', 'REMOVED COMMANDS', 'PUBLIC TYPES', 'ENGINE FLOOR', 'THE GRAMMAR AT REGISTRATION AND IMPORT', 'CHECKLIST FOR A PROFILE', 'MOVING FROM 1.x', 'SEE ALSO')
    }

    It 'states the registration and import grammar check in <Topic>' -TestCases @(
        @{
            Topic    = 'about_Completer_Sets'
            Expected = @(
                'runs the grammar on that parse',
                'a script that fails the grammar is an invalid entry',
                'The grammar is not re-walked on a hash-matched entry'
            )
        }
        @{
            Topic    = 'about_Import_Completers'
            Expected = @(
                '`Register-Completer -Lazy` runs the grammar on the parse',
                '`Import-CompleterSet` reports such a script as an invalid entry'
            )
        }
    ) {
        param($Topic, $Expected)

        $text = @(
            Invoke-TestBuildHelp -Script ([scriptblock]::Create("Get-Help -Name '$Topic' -ErrorAction Stop | Out-String -Width 4096"))
        ) -join "`n"
        $flatText = $text -replace '\s+', ' '

        foreach ($expectedText in $Expected)
        {
            $flatText | Should -Match ([regex]::Escape($expectedText))
        }
    }

    It 'mentions the grammar at registration and import in the help of <Command>' -TestCases @(
        @{ Command = 'Register-Completer'; Expected = 'The strict grammar runs on that parse, so a script that fails it is refused' }
        @{ Command = 'Import-CompleterSet'; Expected = 'runs the strict import grammar on that parse' }
    ) {
        param($Command, $Expected)

        $text = @(
            Invoke-TestBuildHelp -Script ([scriptblock]::Create("Get-Help -Name '$Command' -Full -ErrorAction Stop | Out-String -Width 4096"))
        ) -join "`n"
        $flatText = $text -replace '\s+', ' '

        $flatText | Should -Match ([regex]::Escape($Expected))
    }

    It 'has the third-edition headings in <Topic>' -TestCases @(
        @{
            Topic       = 'about_Completer_Sets'
            Heading     = @('THE HASH AND THE FAST PATH', 'CHECKING FOR DRIFT WITH TEST-COMPLETERSET', 'COMPLETER SETS AS MODULES')
            Order       = @()
            Section     = 'COMPLETER SETS AS MODULES'
            SectionText = @('PrivateData.CompleterSet', 'Import-CompleterSet -Name')
        }
        @{
            Topic       = 'about_Import_Completers'
            Heading     = @('SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT', 'DISTRIBUTING COMPLETERS AS A MODULE')
            Order       = @('SCAFFOLDING A COMPLETER WITH NEW-COMPLETERSCRIPT', 'THE STRICT GRAMMAR')
            Section     = ''
            SectionText = @()
        }
    ) {
        param($Topic, $Heading, $Order, $Section, $SectionText)

        $topicPath = [System.IO.Path]::Combine($PSScriptRoot, '..', 'build', 'CompleterActions', 'en-US', "$Topic.help.txt")
        $lines = @(Get-Content -LiteralPath $topicPath)
        $headings = @($lines | Where-Object { $_ -match '^\S' })

        foreach ($expectedHeading in $Heading)
        {
            $headings | Should -Contain $expectedHeading
        }

        if ($Order.Count -gt 0)
        {
            $firstIndex = [System.Array]::IndexOf($headings, $Order[0])
            $secondIndex = [System.Array]::IndexOf($headings, $Order[1])

            $firstIndex | Should -BeGreaterOrEqual 0
            $secondIndex | Should -BeGreaterThan $firstIndex
        }

        if (-not [string]::IsNullOrEmpty($Section))
        {
            $start = [System.Array]::IndexOf($lines, $Section)
            $end = $start + 1
            while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\S')
            {
                $end++
            }

            $body = $lines[($start + 1)..($end - 1)] -join "`n"

            foreach ($expectedText in $SectionText)
            {
                $body | Should -Match ([regex]::Escape($expectedText))
            }
        }
    }

    It 'gives New-CompleterScript the section 2 synopsis and three examples' {
        $help = Invoke-TestBuildHelp -Script {
            $help = Get-Help -Name 'New-CompleterScript' -Examples -ErrorAction Stop

            [pscustomobject] @{
                Synopsis = [string] $help.Synopsis
                Examples = @($help.examples.example).Count
            }
        }

        $help.Synopsis | Should -BeExactly 'Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.'
        $help.Examples | Should -Be 3
    }

    It 'resolves help for Import-CompleterSet -Name' {
        $help = Invoke-TestBuildHelp -Script {
            $parameter = Get-Help -Name 'Import-CompleterSet' -Parameter 'Name' -ErrorAction Stop

            [pscustomobject] @{
                Name        = [string] $parameter.name
                Description = [string] (@($parameter.description | ForEach-Object Text) -join ' ')
            }
        }

        $help.Name | Should -BeExactly 'Name'
        $help.Description | Should -Not -BeNullOrEmpty
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

            @(Get-Completer -State Discovered, Conflicted).Key | Should -Not -Contain 'completeractionsglobalparam'
            Get-Completer -CommandName 'CompleterActionsGlobalParam' -Native | Should -BeNullOrEmpty

            $removed = @(Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false -PassThru)
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
        $registration = @(Get-Completer -State Conflicted -First 1)[0]

        $registrations[0] | Should -Be ([uint64] 2) -Because 'the replaced target counts its stale managed record and its conflicted live value once each'
        @($registrations[1..2].State) | Should -Be @('Stale', 'Conflicted')
        @($registrations[1..2].Key) | Should -Be @('test-managedtool:name', 'test-managedtool:name')
        $registration.Key | Should -Be 'test-managedtool:name'
        $registration.Source | Should -Be 'Discovered'
        $registration.State | Should -Be 'Conflicted'
        $registration.ScriptText | Should -Match 'discovered'
        @(Get-Completer -State Conflicted).Count | Should -Be 1
    }

    It 'applies paging after filtering by state' {
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

        $managedRegistrations = @(Get-Completer -State Active -First 1)
        $discoveredRegistrations = @(Get-Completer -State Discovered -First 1)

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

        $results = @(Get-Completer -State Active, Pending, Failed, Stale -First 1 -Skip 1)

        $results | Should -BeNullOrEmpty
    }

    It 'reports a bare Register-ArgumentCompleter registration as Discovered' {
        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock

        $registration = Get-Completer -CommandName 'Test-UnmanagedTool' -ParameterName 'Name'

        $registration.Source | Should -Be 'Discovered'
        $registration.State | Should -Be 'Discovered'
        $registration.IsManaged | Should -BeFalse
        $registration.IsRuntimeRegistered | Should -BeTrue
        @(Get-Completer -State Discovered).Key | Should -Contain 'test-unmanagedtool:name'
        @(Get-Completer -State Active).Key | Should -Not -Contain 'test-unmanagedtool:name'
    }

    It 'filters by the union of the given states and returns typed records' {
        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $discoveredScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('discovered', 'discovered', 'ParameterValue', 'discovered')
        }

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock
        $null = Register-Completer -CommandName 'testnative-managed' -Native -ScriptBlock $managedScriptBlock
        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $discoveredScriptBlock
        Invoke-TestRuntimeCompleterCleanup -CommandName 'testnative-managed' -CompleterType 'Native'

        $union = @(Get-Completer -State Discovered, Stale | Sort-Object -Property Key)

        @($union.Key) | Should -Be @('test-unmanagedtool:name', 'testnative-managed')
        @($union.State) | Should -Be @('Discovered', 'Stale')
        @(Get-Completer -State Active).Key | Should -Be @('test-managedtool:name')
        @(Get-Completer -State Pending, Failed, Conflicted) | Should -BeNullOrEmpty

        $union[0].PSObject.TypeNames[0] | Should -Be 'CompleterActions.CompleterRegistration'
        $union[0].State | Should -BeOfType ([System.Enum])
        { Get-Completer -State 'Bogus' } | Should -Throw '*Bogus*'
    }

    It 'no longer exposes ManagedOnly or DiscoveredOnly on Get-Completer' {
        $parameters = (Get-Command -Name 'Get-Completer').Parameters

        $parameters.ContainsKey('ManagedOnly') | Should -BeFalse
        $parameters.ContainsKey('DiscoveredOnly') | Should -BeFalse
        $parameters['State'].ParameterType.FullName | Should -Be 'CompleterActions.CompleterState[]'
        @($parameters['State'].ParameterSets.Keys) | Should -Be @('__AllParameterSets')
    }

    It 'sorts records by CompleterType, then CommandName, then ParameterName regardless of registration order' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('sorted', 'sorted', 'ParameterValue', 'sorted')
        }

        Register-ArgumentCompleter -CommandName 'Test-UnmanagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-ArrayNativeTwo' -Native -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Path', 'Name' -ScriptBlock $scriptBlock
        Register-ArgumentCompleter -CommandName 'Test-ArrayNativeOne' -Native -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $expectedKeys = @(
            'test-arraynativeone', 'test-arraynativetwo',
            'test-arrayone:name', 'test-arrayone:path', 'test-arraytwo:path', 'test-managedtool:name', 'test-unmanagedtool:name'
        )

        @(Get-Completer | Where-Object Key -in $expectedKeys).Key | Should -Be $expectedKeys
        @(Get-Completer -State Active, Discovered | Where-Object Key -in $expectedKeys).Key | Should -Be $expectedKeys
        @(Get-Completer -CommandName 'Test-ManagedTool', 'Test-ArrayOne', 'Test-ArrayOne' -ParameterName 'Name', 'Path', 'Name').Key | Should -Be @('test-arrayone:name', 'test-arrayone:path', 'test-managedtool:name')
    }

    It 'pages without skipping or duplicating an item when an unrelated target changes between pages' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('paged', 'paged', 'ParameterValue', 'paged')
        }

        $replacementScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('replaced', 'replaced', 'ParameterValue', 'replaced')
        }

        $null = Register-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name' -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' -ScriptBlock $scriptBlock
        $null = Register-Completer -CommandName 'Test-PipelineManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock

        $firstPage = @(Get-Completer -First 2)

        Unregister-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' -Confirm:$false
        $null = Register-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' -ScriptBlock $replacementScriptBlock

        $secondPage = @(Get-Completer -Skip 2 -First 2)

        @($firstPage.Key) | Should -Be @('test-arrayone:name', 'test-arraytwo:path')
        @($secondPage.Key) | Should -Be @('test-pipelineextratool:name', 'test-pipelinemanagedtool:name')
        @($firstPage.Key + $secondPage.Key | Select-Object -Unique).Count | Should -Be 4
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

    It 'rejects an input object whose ParameterName is an array instead of joining it into one target' {
        { [pscustomobject] @{ CommandName = 'Test-ArrayOne'; ParameterName = @('Name', 'Path') } | Get-Completer } | Should -Throw '*supplies 2 values for ParameterName*pass arrays to -CommandName and -ParameterName*'
        { [pscustomobject] @{ CommandName = @('Test-ArrayOne', 'Test-ArrayTwo'); ParameterName = 'Path' } | Unregister-Completer -Confirm:$false } | Should -Throw '*supplies 2 values for CommandName*'
    }

    It 'binds every piped object to the InputObject set of <Command>' -TestCases @(
        @{ Command = 'Get-Completer' }
    ) {
        param($Command)

        $command = Get-Command -Name $Command -Module 'CompleterActions'

        foreach ($parameterName in 'CommandName', 'ParameterName', 'Native')
        {
            @($command.Parameters[$parameterName].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }) | Should -BeNullOrEmpty -Because "InputObject binds every piped object by value, so property-name binding on $parameterName is unreachable"
        }
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

        $parameterAliases = @($command.Parameters.Values | ForEach-Object { $_.Aliases })
        foreach ($keyName in 'Key', 'RegistrationKey', 'RuntimeKey')
        {
            $parameterAliases | Should -Not -Contain $keyName -Because "the 1.x -Key parameter carried RegistrationKey as an alias, and CommandInfo.Parameters never lists aliases"
        }
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

    It 'removes every target when unfiltered get output includes a replaced target' {
        function Test-ManagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $managedScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('managed', 'managed', 'ParameterValue', 'managed')
        }

        $externalScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
        }

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        $null = Register-Completer -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name' -ScriptBlock $managedScriptBlock -PassThru
        Register-ArgumentCompleter -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock

        $records = @(Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name') + @(Get-Completer -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name')
        @($records.State) | Should -Be @('Stale', 'Conflicted', 'Active')

        $removed = @($records | Unregister-Completer -AllowUnmanaged -Confirm:$false -PassThru)

        @($removed.Key) | Should -Be @('test-managedtool:name', 'test-pipelineextratool:name') -Because 'the Conflicted twin of the Stale record names a key the same call already removed'
        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        Get-Completer -CommandName 'Test-PipelineExtraTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    Context 'decides a Stale and Conflicted pair once per call in a fresh process' {
        BeforeAll {
            $manifestPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'CompleterActions.psd1'
            $probeScript = @'
param([ValidateSet('WhatIf', 'Confirm')] [string] $Mode)

Import-Module -Name '{0}' -Force

function global:Test-TwinProbeTool
{{
    [CmdletBinding()]
    param(
        [string] $Name
    )
}}

$null = Register-Completer -CommandName 'Test-TwinProbeTool' -ParameterName 'Name' -ScriptBlock {{ 'managed' }}
Register-ArgumentCompleter -CommandName 'Test-TwinProbeTool' -ParameterName 'Name' -ScriptBlock {{ 'external' }}

$records = @(Get-Completer -CommandName 'Test-TwinProbeTool' -ParameterName 'Name')
"BEFORE=$(($records.State -join ','))"

if ($Mode -eq 'WhatIf')
{{
    $records | Unregister-Completer -AllowUnmanaged -WhatIf
}}
else
{{
    $records | Unregister-Completer -AllowUnmanaged -Confirm
}}

"AFTER=$((@(Get-Completer -CommandName 'Test-TwinProbeTool' -ParameterName 'Name').State -join ','))"
'@ -f $manifestPath

            $script:TwinProbePath = Join-Path -Path $TestDrive -ChildPath 'twin-probe.ps1'
            Set-Content -Path $script:TwinProbePath -Value $probeScript
        }

        It 'prints one WhatIf message for the pair' {
            $output = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $script:TwinProbePath -Mode WhatIf 2>&1)

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            $output | Should -Contain 'BEFORE=Stale,Conflicted'
            @($output | Where-Object { $_ -like 'What if: Performing the operation "Unregister completer registration" on target "Test-TwinProbeTool:Name".' }).Count | Should -Be 1
            $output | Should -Contain 'AFTER=Stale,Conflicted'
        }

        It 'does not prompt again for the Conflicted twin after the Stale record was declined' {
            $output = @('n', 'y' | & pwsh -NoProfile -NoLogo -File $script:TwinProbePath -Mode Confirm 2>&1)

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            $output | Should -Contain 'BEFORE=Stale,Conflicted'
            $joined = $output -join [Environment]::NewLine
            $joined | Should -Match '(?m)(?:^|"\):)n\s*$' -Because 'the host echoes each answer a prompt consumed, on its own line on Windows and after the prompt text on Linux'
            $joined | Should -Not -Match '(?m)(?:^|"\):)y\s*$' -Because 'the declined target must not be offered a second time, so the second answer is never read'
            $output | Should -Contain 'AFTER=Stale,Conflicted' -Because 'the second answer must not remove the target the first answer declined'
        }
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

        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $oldScriptBlock
        $original = InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' }

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
        [object]::ReferenceEquals((InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' }), $original) | Should -BeTrue

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
        (InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' }).ScriptText | Should -Match 'old'

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
        InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ArrayOne' -ParameterName 'Name' } | Should -Not -BeNullOrEmpty

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

        $kept = Get-Completer -CommandName 'Test-ArrayOne' -ParameterName 'Name' -State Active
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
        [object]::ReferenceEquals($registrations[0].ScriptBlock, $registrations[1].ScriptBlock) | Should -BeTrue

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

        $first = Get-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -State Active
        $first.Source | Should -Be 'Managed'
        $first.State | Should -Be 'Active'
        $first.ScriptText | Should -Match 'repeat'
    }

    It 'returns detached records, so editing a returned record leaves the managed state unchanged' {
        $scriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('kept', 'kept', 'ParameterValue', 'kept')
        }

        $registered = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock $scriptBlock -PassThru
        $registered.State = 'Failed'
        $registered.ScriptPath = Join-Path -Path $TestDrive -ChildPath 'edited-passthru.ps1'

        $queried = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name'
        @($queried | ForEach-Object { '{0}/{1}' -f $_.State, $_.Source }) | Should -Be @('Active/Managed') -Because 'editing a -PassThru record does not edit the managed record'
        $queried.ScriptPath | Should -BeNullOrEmpty

        $queried.State = 'Failed'
        $queried.ScriptPath = Join-Path -Path $TestDrive -ChildPath 'edited-query.ps1'
        $queried.LoadError = 'edited'

        $requeried = @(Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name')
        @($requeried | ForEach-Object { '{0}/{1}' -f $_.State, $_.Source }) | Should -Be @('Active/Managed') -Because 'editing a Get-Completer record does not edit the managed record'
        $requeried[0].ScriptPath | Should -BeNullOrEmpty
        $requeried[0].LoadError | Should -BeNullOrEmpty

        $stored = InModuleScope CompleterActions { Find-ManagedCompleterRegistration -CommandName 'Test-ManagedTool' -ParameterName 'Name' }
        [object]::ReferenceEquals($requeried[0], $stored) | Should -BeFalse

        foreach ($property in [CompleterActions.CompleterRegistration].GetProperties())
        {
            [object]::Equals($property.GetValue($requeried[0]), $property.GetValue($stored)) | Should -BeTrue -Because "the returned copy carries the managed record's $($property.Name)"
        }
    }

    It 'restores the untouched managed record when a pipeline failure undoes Unregister-Completer -PassThru' {
        $null = Register-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -ScriptBlock { 'kept' }

        {
            Unregister-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -Confirm:$false -PassThru | ForEach-Object {
                $_.State = 'Failed'
                $_.ScriptPath = Join-Path -Path $TestDrive -ChildPath 'edited-unregister.ps1'
                throw 'downstream failure'
            }
        } | Should -Throw '*downstream failure*'

        $records = @(Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name')
        @($records | ForEach-Object { '{0}/{1}' -f $_.State, $_.Source }) | Should -Be @('Active/Managed') -Because 'the rollback puts back the managed record, not the edited copy'
        $records[0].ScriptPath | Should -BeNullOrEmpty
    }

    It 'restores the untouched runtime completer when a pipeline failure undoes Unregister-Completer -AllowUnmanaged -PassThru' {
        function Test-RemoveUnmanagedTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $originalScriptBlock = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [System.Management.Automation.CompletionResult]::new('original', 'original', 'ParameterValue', 'original')
        }

        Register-ArgumentCompleter -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -ScriptBlock $originalScriptBlock

        {
            Unregister-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru | ForEach-Object {
                $_.ScriptBlock = { [System.Management.Automation.CompletionResult]::new('edited', 'edited', 'ParameterValue', 'edited') }
                $_.ScriptText = 'edited'
                throw 'downstream failure'
            }
        } | Should -Throw '*downstream failure*'

        $records = @(Get-Completer -CommandName 'Test-RemoveUnmanagedTool' -ParameterName 'Name')
        @($records | ForEach-Object { '{0}/{1}' -f $_.State, $_.Source }) | Should -Be @('Discovered/Discovered')
        [object]::ReferenceEquals($records[0].ScriptBlock, $originalScriptBlock) | Should -BeTrue -Because 'the rollback puts back the runtime script block, not the one set on the emitted copy'

        $inputScript = 'Test-RemoveUnmanagedTool -Name '
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Be @('original')
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

        $records = @(Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name')
        @($records.State) | Should -Be @('Stale', 'Conflicted') -Because 'a replaced target reports both the stale managed record and the conflicted live value'

        $liveRegistration = $records[1]
        $liveRegistration.Source | Should -Be 'Discovered'
        $liveRegistration.State | Should -Be 'Conflicted'
        $liveRegistration.IsManaged | Should -BeFalse
        $liveRegistration.ScriptText | Should -Match 'external'

        $managedRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -State Stale
        $managedRegistration.Source | Should -Be 'Managed'
        $managedRegistration.State | Should -Be 'Stale'
        $managedRegistration.IsRuntimeRegistered | Should -BeFalse
        $managedRegistration.ScriptText | Should -Match 'old'

        $discoveredRegistration = Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -State Conflicted
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

        Get-Completer -CommandName 'Test-ManagedTool' -ParameterName 'Name' -State Discovered, Conflicted | Should -BeNullOrEmpty

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

Describe 'Removed surface' {
    BeforeAll {
        $script:RemovedSurfaceRepoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:RemovedSurfaceManifestPath = Join-Path -Path $script:RemovedSurfaceRepoRoot -ChildPath 'CompleterActions.psd1'

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:RemovedSurfaceManifestPath -Force | Out-Null
    }

    AfterAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'exports exactly the eleven functions and no alias' {
        $expected = @(
            'Export-CompleterSet',
            'Get-Completer',
            'Import-CompleterScript',
            'Import-CompleterSet',
            'New-CompleterScript',
            'Register-Completer',
            'Reset-Completer',
            'Test-CompleterRegistration',
            'Test-CompleterScript',
            'Test-CompleterSet',
            'Unregister-Completer'
        )
        $manifestData = Import-PowerShellDataFile -Path $script:RemovedSurfaceManifestPath
        $commands = @(Get-Command -Module 'CompleterActions')

        @($manifestData.FunctionsToExport) | Should -Be $expected
        $manifestData.ContainsKey('AliasesToExport') | Should -BeTrue
        @($manifestData.AliasesToExport).Count | Should -Be 0
        $commands.Count | Should -Be 11
        @($commands | Where-Object CommandType -ne 'Function') | Should -BeNullOrEmpty
        @($commands.Name | Sort-Object) | Should -Be @($manifestData.FunctionsToExport)
    }

    It 'fails <Name> with CommandNotFoundException' -TestCases @(
        @{ Name = 'Get-CompleterRegistration' },
        @{ Name = 'Register-CompleterRegistration' },
        @{ Name = 'Unregister-CompleterRegistration' },
        @{ Name = 'Get-CompleterRegistrationLegacy' },
        @{ Name = 'Register-CompleterRegistrationLegacy' },
        @{ Name = 'Unregister-CompleterRegistrationLegacy' }
    ) {
        param($Name)

        # An installed 2.x CompleterActions on PSModulePath still exports these names and command discovery would
        # autoload it. Discovery ignores a local autoloading preference, so the global one is off for the call.
        $previousPreference = Get-Variable -Name 'PSModuleAutoLoadingPreference' -Scope Global -ErrorAction Ignore
        $thrown = $null
        Set-Variable -Name 'PSModuleAutoLoadingPreference' -Scope Global -Value 'None'

        try
        {
            & $Name
        }
        catch
        {
            $thrown = $_
        }
        finally
        {
            if ($previousPreference)
            {
                Set-Variable -Name 'PSModuleAutoLoadingPreference' -Scope Global -Value $previousPreference.Value
            }
            else
            {
                Remove-Variable -Name 'PSModuleAutoLoadingPreference' -Scope Global
            }
        }

        $thrown | Should -Not -BeNullOrEmpty -Because "$Name must no longer resolve"
        $thrown.Exception | Should -BeOfType ([System.Management.Automation.CommandNotFoundException])
        $thrown.Exception.Message | Should -BeLike "The term '$Name' is not recognized*"
    }

    It 'has no deprecated name left in the sources' {
        $repoRoot = $script:RemovedSurfaceRepoRoot
        $files = @(
            Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Filter '*.ps1' -File -Recurse
            Get-Item -LiteralPath @(
                (Join-Path -Path $repoRoot -ChildPath 'CompleterActions.psm1'),
                (Join-Path -Path $repoRoot -ChildPath 'CompleterActions.psd1'),
                (Join-Path -Path $repoRoot -ChildPath 'README.md'),
                (Join-Path -Path $repoRoot -ChildPath '.github/copilot-instructions.md')
            )
            Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'en-US') -Filter '*.txt' -File
            Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src/docs/CompleterActions') -Filter '*.md' -File
        )
        # The migration guide maps every old name; README keeps one history sentence about the removal.
        $allowed = @{
            'en-US/about_CompleterActions_Migration.help.txt' = '*'
            'README.md'                                       = '3.0 removed the 1.x names *'
        }

        $unexpected = @(
            $files |
                Select-String -Pattern 'CompleterRegistrationLegacy|Write-CompleterDeprecationWarning|CompleterDeprecationWarningsIssued|ManagedOnly|DiscoveredOnly' |
                ForEach-Object {
                    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $_.Path).Replace('\', '/')
                    if (-not ($allowed.ContainsKey($relativePath) -and $_.Line -like $allowed[$relativePath]))
                    {
                        '{0}:{1}: {2}' -f $relativePath, $_.LineNumber, $_.Line.Trim()
                    }
                }
        )

        $unexpected | Should -BeNullOrEmpty
        foreach ($removedFile in 'src/Public/Get-CompleterRegistrationLegacy.ps1', 'src/Public/Register-CompleterRegistrationLegacy.ps1', 'src/Public/Unregister-CompleterRegistrationLegacy.ps1', 'src/Private/Write-CompleterDeprecationWarning.ps1', 'tests/CompleterDeprecation.Tests.ps1')
        {
            Join-Path -Path $repoRoot -ChildPath $removedFile | Should -Not -Exist
        }
    }
}

Describe 'Packaged command help' {
    BeforeAll {
        function New-TestBuildStage
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only copies the build inputs into TestDrive.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string] $Name
            )

            # The build derives the module name from its folder, so the inputs are staged under a folder with that name.
            $repoRoot = Split-Path -Path $PSScriptRoot -Parent
            $stagingRoot = Join-Path -Path $TestDrive -ChildPath "$Name/CompleterActions"
            New-Item -Path $stagingRoot -ItemType Directory | Out-Null

            foreach ($buildInput in 'CompleterActions.build.ps1', 'CompleterActions.psd1', 'CompleterActions.Format.ps1xml', 'en-US', 'src')
            {
                Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath $buildInput) -Destination $stagingRoot -Recurse
            }

            foreach ($compilerOutput in 'src/Core/bin', 'src/Core/obj')
            {
                Remove-Item -LiteralPath (Join-Path -Path $stagingRoot -ChildPath $compilerOutput) -Recurse -Force -ErrorAction SilentlyContinue
            }

            $stagingRoot
        }
    }

    It 'points every packaged command at the generated MAML and renders it' {
        $commands = @(
            Invoke-TestBuildHelp -Script {
                foreach ($command in Get-Command -Module 'CompleterActions' -CommandType Function)
                {
                    $helpError = $null
                    try
                    {
                        $null = Get-Help -Name $command.Name -Full -ErrorAction Stop | Out-String -Width 4096
                    }
                    catch
                    {
                        $helpError = $_.Exception.Message
                    }

                    [pscustomobject] @{
                        Name         = $command.Name
                        MamlHelpFile = [string] $command.ScriptBlock.Ast.GetHelpContent().MamlHelpFile
                        HelpError    = [string] $helpError
                    }
                }
            }
        )
        $publicCommands = @(
            Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../src/Public') -Filter '*.ps1' |
                Sort-Object -Property BaseName |
                Select-Object -ExpandProperty BaseName
        )

        @($commands.Name | Sort-Object) | Should -Be $publicCommands
        foreach ($command in $commands)
        {
            $command.MamlHelpFile | Should -BeExactly 'CompleterActions-help.xml' -Because "the packaged $($command.Name) must carry a recognized .EXTERNALHELP directive"
            $command.HelpError | Should -BeNullOrEmpty -Because "Get-Help $($command.Name) -Full must render the MAML"
        }
    }

    It 'shows Reset-Completer wording that only the MAML has' {
        # Both sentences come from the maintained markdown help and are absent from the source comment help,
        # so finding them in the packaged Get-Help output shows the MAML was selected.
        $mamlOnlyPhrases = @(
            'the first of these rules that applies decides it'
            'whose script was deleted is therefore left alone without an error'
        )
        $sourceHelp = (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../src/Public/Reset-Completer.ps1') -Raw) -replace '\s+', ' '
        $text = (@(
                Invoke-TestBuildHelp -Script {
                    Get-Help -Name 'Reset-Completer' -Full -ErrorAction Stop | Out-String -Width 4096
                }
            ) -join "`n") -replace '\s+', ' '

        foreach ($phrase in $mamlOnlyPhrases)
        {
            $sourceHelp | Should -Not -Match ([regex]::Escape($phrase)) -Because 'the phrase must be unique to the MAML to show which help Get-Help selected'
            $text | Should -Match ([regex]::Escape($phrase))
        }
    }

    It 'links every packaged command online to its maintained markdown page and to no relative or pinned URI' {
        $links = @(
            Invoke-TestBuildHelp -Script {
                foreach ($command in Get-Command -Module 'CompleterActions' -CommandType Function)
                {
                    foreach ($link in (Get-Help -Name $command.Name -Full -ErrorAction Stop).relatedLinks.navigationLink)
                    {
                        [pscustomobject] @{
                            Name     = $command.Name
                            LinkText = [string] $link.linkText
                            Uri      = [string] $link.uri
                        }
                    }
                }
            }
        )
        $projectUri = (Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath '../CompleterActions.psd1')).PrivateData.PSData.ProjectUri
        $publicCommands = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../src/Public') -Filter '*.ps1' | Select-Object -ExpandProperty BaseName)

        foreach ($name in $publicCommands)
        {
            $onlineLink = @($links | Where-Object { $_.Name -eq $name })[0]

            $onlineLink.LinkText | Should -BeExactly 'Online Version' -Because "Get-Help -Online $name uses the first related link"
            $onlineLink.Uri | Should -BeExactly "$projectUri/blob/main/src/docs/CompleterActions/$name.md"
            Join-Path -Path $PSScriptRoot -ChildPath "../src/docs/CompleterActions/$name.md" | Should -Exist
        }

        foreach ($link in $links | Where-Object { $_.Uri })
        {
            $link.Uri | Should -Match '^https?://' -Because "Get-Help stops on a related link of $($link.Name) that is not absolute"
            $link.Uri | Should -Not -Match '/blob/[0-9a-f]{40}/' -Because "a related link of $($link.Name) must not point at one old commit"
        }
    }

    It 'documents in a full sentence each output type a packaged command declares, and no other' {
        $outputs = @(
            Invoke-TestBuildHelp -Script {
                foreach ($command in Get-Command -Module 'CompleterActions' -CommandType Function)
                {
                    $returnValues = @((Get-Help -Name $command.Name -Full -ErrorAction Stop).returnValues.returnValue)

                    [pscustomobject] @{
                        Name         = $command.Name
                        Declared     = @($command.OutputType.Name | Sort-Object)
                        Documented   = @($returnValues | ForEach-Object { [string] $_.type.name } | Sort-Object)
                        Descriptions = @($returnValues | ForEach-Object { ($_.description | ForEach-Object Text) -join ' ' })
                    }
                }
            }
        )

        $outputs | Should -Not -BeNullOrEmpty
        foreach ($command in $outputs)
        {
            @($command.Documented) | Should -Be @($command.Declared) -Because "the OUTPUTS of the packaged $($command.Name) must list its OutputType"
            foreach ($description in $command.Descriptions)
            {
                $description | Should -Match '\.\s*$' -Because "each OUTPUTS entry of $($command.Name) must say what the command returns"
            }
        }
    }

    It 'describes each parameter of a packaged command in Get-Help as the command declares it' {
        # The MAML is built from hand-maintained markdown, so only this comparison keeps installed Get-Help in step
        # with the parameters the commands declare. A PARAMETERS entry describes the parameter across all its sets, as
        # the MAML builder writes it: it takes pipeline input in any way one of its sets does, is required when any set
        # makes it mandatory, and names one position, which must be one of its sets' positions. The syntax test
        # checks each set on its own.
        $parameters = @(
            Invoke-TestBuildHelp -Script {
                $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

                foreach ($command in Get-Command -Module 'CompleterActions' -CommandType Function)
                {
                    $helpParameters = @((Get-Help -Name $command.Name -Full -ErrorAction Stop).parameters.parameter)
                    $names = @(@($command.Parameters.Keys) + @($helpParameters.name) | Where-Object { $_ -notin $commonParameters } | Sort-Object -Unique)

                    foreach ($name in $names)
                    {
                        $metadata = $command.Parameters[$name]
                        $help = @($helpParameters | Where-Object { $_.name -eq $name })
                        $sets = @(if ($null -ne $metadata) { $metadata.ParameterSets.Values })
                        $byValue = @($sets | Where-Object ValueFromPipeline).Count -gt 0
                        $byPropertyName = @($sets | Where-Object ValueFromPipelineByPropertyName).Count -gt 0

                        [pscustomobject] @{
                            Command               = $command.Name
                            Parameter             = $name
                            Declared              = $null -ne $metadata
                            HelpEntries           = $help.Count
                            PipelineInput         = [string] $help.pipelineInput
                            Required              = [string] $help.required
                            Position              = [string] $help.position
                            Aliases               = @(([string] $help.aliases) -split ',\s*' | Sort-Object) -join ', '
                            Type                  = [string] $help.type.name
                            DeclaredPipelineInput = if ($byValue -or $byPropertyName) { 'true ({0})' -f (@(if ($byValue) { 'ByValue' }; if ($byPropertyName) { 'ByPropertyName' }) -join ', ') } else { 'false' }
                            DeclaredRequired      = if (@($sets | Where-Object IsMandatory).Count -gt 0) { 'true' } else { 'false' }
                            DeclaredPositions     = @($sets | ForEach-Object { if ($_.Position -lt 0) { 'Named' } else { [string] $_.Position } } | Sort-Object -Unique)
                            DeclaredAliases       = if ($null -ne $metadata -and $metadata.Aliases.Count -gt 0) { @($metadata.Aliases | Sort-Object) -join ', ' } else { 'none' }
                            DeclaredType          = if ($null -ne $metadata) { $metadata.ParameterType.FullName } else { '' }
                        }
                    }
                }
            }
        )
        $publicCommands = @(
            Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../src/Public') -Filter '*.ps1' |
                Sort-Object -Property BaseName |
                Select-Object -ExpandProperty BaseName
        )

        @($parameters.Command | Sort-Object -Unique) | Should -Be $publicCommands
        $drift = @(
            foreach ($parameter in $parameters)
            {
                $target = '{0} -{1}' -f $parameter.Command, $parameter.Parameter

                if (-not $parameter.Declared)
                {
                    "$target is in Get-Help but not declared"
                    continue
                }

                if ($parameter.HelpEntries -ne 1)
                {
                    "$target has $($parameter.HelpEntries) Get-Help entries"
                    continue
                }

                if ($parameter.PipelineInput -ne $parameter.DeclaredPipelineInput)
                {
                    "$target pipeline input is '$($parameter.PipelineInput)' in Get-Help but '$($parameter.DeclaredPipelineInput)' declared"
                }

                if ($parameter.Required -ne $parameter.DeclaredRequired)
                {
                    "$target required is '$($parameter.Required)' in Get-Help but '$($parameter.DeclaredRequired)' declared"
                }

                if ($parameter.Position -notin $parameter.DeclaredPositions)
                {
                    "$target position is '$($parameter.Position)' in Get-Help but '$($parameter.DeclaredPositions -join "', '")' declared"
                }

                if ($parameter.Aliases -ne $parameter.DeclaredAliases)
                {
                    "$target aliases are '$($parameter.Aliases)' in Get-Help but '$($parameter.DeclaredAliases)' declared"
                }

                if ($parameter.Type -ne $parameter.DeclaredType)
                {
                    "$target type is '$($parameter.Type)' in Get-Help but '$($parameter.DeclaredType)' declared"
                }
            }
        )

        $drift | Should -BeNullOrEmpty
    }

    It 'shows each parameter set of a packaged command in its syntax with the required flags, positions and pipeline input the set declares' {
        # A set's syntax entry is the one that lists exactly the set's parameters, as parameter sets differ in them.
        $setParameters = @(
            Invoke-TestBuildHelp -Script {
                $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

                foreach ($command in Get-Command -Module 'CompleterActions' -CommandType Function)
                {
                    $syntaxItems = @((Get-Help -Name $command.Name -Full -ErrorAction Stop).syntax.syntaxItem)

                    foreach ($set in $command.ParameterSets)
                    {
                        $parameters = @($set.Parameters | Where-Object { $_.Name -notin $commonParameters })
                        $names = @($parameters.Name | Sort-Object) -join ', '
                        $items = @($syntaxItems | Where-Object { (@($_.parameter.name | Sort-Object) -join ', ') -eq $names })

                        foreach ($parameter in $parameters)
                        {
                            $help = @(if ($items.Count -eq 1) { $items[0].parameter | Where-Object { $_.name -eq $parameter.Name } })

                            [pscustomobject] @{
                                Command               = $command.Name
                                SetCount              = $command.ParameterSets.Count
                                SyntaxCount           = $syntaxItems.Count
                                Set                   = $set.Name
                                SetParameters         = $names
                                SyntaxItems           = $items.Count
                                Parameter             = $parameter.Name
                                Required              = [string] $help.required
                                Position              = [string] $help.position
                                PipelineInput         = [string] $help.pipelineInput
                                DeclaredRequired      = if ($parameter.IsMandatory) { 'true' } else { 'false' }
                                DeclaredPosition      = if ($parameter.Position -lt 0) { 'named' } else { [string] $parameter.Position }
                                DeclaredPipelineInput = if ($parameter.ValueFromPipeline -or $parameter.ValueFromPipelineByPropertyName) { 'true ({0})' -f (@(if ($parameter.ValueFromPipeline) { 'ByValue' }; if ($parameter.ValueFromPipelineByPropertyName) { 'ByPropertyName' }) -join ', ') } else { 'false' }
                            }
                        }
                    }
                }
            }
        )
        $publicCommands = @(
            Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../src/Public') -Filter '*.ps1' |
                Sort-Object -Property BaseName |
                Select-Object -ExpandProperty BaseName
        )

        @($setParameters.Command | Sort-Object -Unique) | Should -Be $publicCommands
        $drift = @(
            foreach ($command in $setParameters | Group-Object -Property Command)
            {
                if ($command.Group[0].SyntaxCount -ne $command.Group[0].SetCount)
                {
                    "$($command.Name) has $($command.Group[0].SyntaxCount) syntax entries for $($command.Group[0].SetCount) parameter sets"
                }
            }

            foreach ($parameter in $setParameters)
            {
                $target = '{0} -{1} in set {2}' -f $parameter.Command, $parameter.Parameter, $parameter.Set

                if ($parameter.SyntaxItems -ne 1)
                {
                    "set $($parameter.Set) of $($parameter.Command) ($($parameter.SetParameters)) has $($parameter.SyntaxItems) syntax entries"
                    continue
                }

                if ($parameter.Required -ne $parameter.DeclaredRequired)
                {
                    "$target required is '$($parameter.Required)' in the syntax but '$($parameter.DeclaredRequired)' declared"
                }

                if ($parameter.Position -ne $parameter.DeclaredPosition)
                {
                    "$target position is '$($parameter.Position)' in the syntax but '$($parameter.DeclaredPosition)' declared"
                }

                if ($parameter.PipelineInput -ne $parameter.DeclaredPipelineInput)
                {
                    "$target pipeline input is '$($parameter.PipelineInput)' in the syntax but '$($parameter.DeclaredPipelineInput)' declared"
                }
            }
        )

        @($drift | Select-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'replaces only the help that leads into each public command, in any layout, and keeps every other source line' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        $stagingRoot = New-TestBuildStage -Name 'layouts'
        $publicRoot = Join-Path -Path $stagingRoot -ChildPath 'src/Public'
        $helpLineLikeDeclaration = 'function names in this description are informational only.'

        # A help line that starts with the word 'function', which a line pattern takes for the declaration.
        $path = Join-Path -Path $publicRoot -ChildPath 'Get-Completer.ps1'
        $lines = [System.Collections.Generic.List[string]] @(Get-Content -LiteralPath $path)
        $lines.IndexOf('.DESCRIPTION') | Should -BeGreaterOrEqual 0
        $lines.Insert($lines.IndexOf('.DESCRIPTION') + 1, $helpLineLikeDeclaration)
        Set-Content -LiteralPath $path -Value $lines

        # A blank line between the help block and the declaration.
        $path = Join-Path -Path $publicRoot -ChildPath 'Unregister-Completer.ps1'
        $lines = [System.Collections.Generic.List[string]] @(Get-Content -LiteralPath $path)
        $lines.IndexOf('function Unregister-Completer') | Should -BeGreaterThan 0
        $lines.Insert($lines.IndexOf('function Unregister-Completer'), '')
        Set-Content -LiteralPath $path -Value $lines

        # Help written as line comments instead of a block.
        $path = Join-Path -Path $publicRoot -ChildPath 'Test-CompleterScript.ps1'
        $lines = @(Get-Content -LiteralPath $path)
        $helpEnd = [array]::IndexOf($lines, '#>')
        $lines[0] | Should -BeExactly '<#'
        Set-Content -LiteralPath $path -Value @(@($lines[1..($helpEnd - 1)] | ForEach-Object { "# $_" }) + $lines[($helpEnd + 1)..($lines.Count - 1)])

        # The help closes on the declaration's line.
        $path = Join-Path -Path $publicRoot -ChildPath 'Import-CompleterSet.ps1'
        $lines = @(Get-Content -LiteralPath $path)
        $declarationIndex = [array]::IndexOf($lines, 'function Import-CompleterSet')
        $lines[$declarationIndex - 1] | Should -BeExactly '#>'
        Set-Content -LiteralPath $path -Value @($lines[0..($declarationIndex - 2)] + "#> $($lines[$declarationIndex])" + $lines[($declarationIndex + 1)..($lines.Count - 1)])

        # A #requires line, and a statement that ends in a comment, each directly above the help.
        $requiresLine = '#requires -Version 7.4'
        $trailingComment = '# a comment that ends a statement'
        $statementLine = "`$script:BuildProbeMarker = 'kept'  $trailingComment"
        $path = Join-Path -Path $publicRoot -ChildPath 'Export-CompleterSet.ps1'
        Set-Content -LiteralPath $path -Value @(@($requiresLine) + @(Get-Content -LiteralPath $path))
        $path = Join-Path -Path $publicRoot -ChildPath 'Import-CompleterScript.ps1'
        Set-Content -LiteralPath $path -Value @(@($statementLine) + @(Get-Content -LiteralPath $path))

        # A helper function with its own comment help ahead of the command.
        $helperSynopsis = 'A helper defined ahead of the command.'
        $path = Join-Path -Path $publicRoot -ChildPath 'Test-CompleterSet.ps1'
        Set-Content -LiteralPath $path -Value @(@('<#', '.SYNOPSIS', $helperSynopsis, '#>', 'function Get-BuildProbeHelper { 1 }', '') + @(Get-Content -LiteralPath $path))

        # A comment a blank line above the help, which is outside the block PowerShell reads the help from.
        $regionLine = '#region BuildProbeRegion'
        $path = Join-Path -Path $publicRoot -ChildPath 'Register-Completer.ps1'
        Set-Content -LiteralPath $path -Value @(@($regionLine, '') + @(Get-Content -LiteralPath $path))

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($buildOutput -join [Environment]::NewLine)

        $packagedPath = Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions/CompleterActions.psm1'
        $tokens = $null
        $parseErrors = $null
        $packagedAst = [System.Management.Automation.Language.Parser]::ParseFile($packagedPath, [ref] $tokens, [ref] $parseErrors)

        @($parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
        $packagedText = Get-Content -LiteralPath $packagedPath -Raw
        $packagedText | Should -Not -Match ([regex]::Escape($helpLineLikeDeclaration))
        $packagedText | Should -Match "(?m)^$([regex]::Escape($requiresLine))\r?$"
        $packagedAst.ScriptRequirements.RequiredPSVersion | Should -Be ([version] '7.4') -Because 'the #requires line must stay a requirement of the packaged module'
        $packagedText | Should -Match "(?m)^$([regex]::Escape($statementLine))\r?$"
        $packagedText | Should -Match "(?m)^$([regex]::Escape($regionLine))\r?$"

        $functions = @($packagedAst.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
        $publicNames = @(Get-ChildItem -LiteralPath $publicRoot -Filter '*.ps1' | Select-Object -ExpandProperty BaseName)
        $privateNames = @(Get-ChildItem -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Private') -Filter '*.ps1' | Select-Object -ExpandProperty BaseName)

        @($functions | Where-Object Name -in $publicNames).Count | Should -Be $publicNames.Count
        @($functions | Where-Object Name -in $privateNames).Count | Should -Be $privateNames.Count

        foreach ($function in $functions | Where-Object Name -in $publicNames)
        {
            $leadingTokens = @($tokens | Where-Object { $_.Extent.EndOffset -le $function.Extent.StartOffset })
            $leadingComments = @(
                for ($index = $leadingTokens.Count - 1; $index -ge 0 -and $leadingTokens[$index].Kind -in 'Comment', 'NewLine'; $index--)
                {
                    if ($leadingTokens[$index].Kind -eq 'Comment')
                    {
                        $leadingTokens[$index].Text
                    }
                }
            )

            $leadingComments[0] -replace '\r', '' | Should -BeExactly "<#`n.EXTERNALHELP CompleterActions-help.xml`n#>"
            @($leadingComments | Select-Object -Skip 1 | Where-Object { $_ -notin $requiresLine, $trailingComment, $regionLine }) | Should -BeNullOrEmpty -Because "only the directive may lead into the packaged $($function.Name)"

            $help = $function.GetHelpContent()
            $help.MamlHelpFile | Should -BeExactly 'CompleterActions-help.xml'
            $help.Synopsis | Should -BeNullOrEmpty -Because "no comment may join the directive of the packaged $($function.Name)"
        }

        foreach ($function in $functions | Where-Object Name -in ($privateNames + 'Get-BuildProbeHelper'))
        {
            $help = $function.GetHelpContent()

            $help.MamlHelpFile | Should -BeNullOrEmpty
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "the packaged private $($function.Name) keeps its comment help"
        }

        @($functions | Where-Object Name -eq 'Get-BuildProbeHelper') | Should -HaveCount 1
        ($functions | Where-Object Name -eq 'Get-BuildProbeHelper').GetHelpContent().Synopsis.Trim() | Should -BeExactly $helperSynopsis

        $manifestPath = Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1'
        $imported = & pwsh -NoProfile -NonInteractive -Command {
            param($ManifestPath)

            $ErrorActionPreference = 'Stop'
            Import-Module -Name $ManifestPath -Force
            $commands = @(Get-Command -Module 'CompleterActions' -CommandType Function)

            [pscustomobject] @{
                Exported = @($commands.Name | Sort-Object)
                Maml     = @($commands | ForEach-Object { [string] $_.ScriptBlock.Ast.GetHelpContent().MamlHelpFile } | Sort-Object -Unique)
                Marker   = & (Get-Module -Name 'CompleterActions') { $script:BuildProbeMarker }
            }
        } -args $manifestPath

        $LASTEXITCODE | Should -Be 0
        @($imported.Exported) | Should -Be @($publicNames | Sort-Object) -Because 'the package must export every public command and no helper'
        @($imported.Maml) | Should -Be @('CompleterActions-help.xml')
        $imported.Marker | Should -BeExactly 'kept' -Because 'the statement above the help of Import-CompleterScript must run when the package is imported'
    }

    It 'hoists only the top-level using statements and keeps the other text on their lines and a string line that reads like one' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        # Several files share one using statement, which the package states once, and a here-string holds a line that a
        # line pattern takes for a using statement. Two using statements share their line with other text: the end of
        # a comment block, and a statement after a semicolon. Only the using statement's own text may move.
        $stagingRoot = New-TestBuildStage -Name 'using'
        $privateRoot = Join-Path -Path $stagingRoot -ChildPath 'src/Private'
        $usingLine = 'using namespace System.Text'
        Set-Content -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Get-BuildProbeLiteral.ps1') -Value @(
            'function Get-BuildProbeLiteral'
            '{'
            "    @'"
            $usingLine
            "'@"
            '}'
        )
        Set-Content -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Get-BuildProbeBuilder.ps1') -Value @(
            $usingLine
            ''
            "function Get-BuildProbeBuilder { [StringBuilder]::new('built').ToString() }"
        )
        Set-Content -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Get-BuildProbeShared.ps1') -Value @(
            $usingLine
            ''
            "function Get-BuildProbeShared { 'shared' }"
        )
        Set-Content -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Get-BuildProbeTail.ps1') -Value @(
            '<#'
            '.SYNOPSIS'
            'probe'
            "#> $usingLine"
            "function Get-BuildProbeTail { 'tail' }"
        )
        Set-Content -LiteralPath (Join-Path -Path $privateRoot -ChildPath 'Get-BuildProbeSuffix.ps1') -Value @(
            "$usingLine; `$script:BuildProbeSuffix = 'suffix'"
            'function Get-BuildProbeSuffix { $script:BuildProbeSuffix }'
        )

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine
        $LASTEXITCODE | Should -Be 0 -Because $buildOutput

        $packagedPath = Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions/CompleterActions.psm1'
        $tokens = $null
        $parseErrors = $null
        $packagedAst = [System.Management.Automation.Language.Parser]::ParseFile($packagedPath, [ref] $tokens, [ref] $parseErrors)

        @($parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
        @($packagedAst.UsingStatements.Extent.Text) | Should -Be @($usingLine)
        @(Get-Content -LiteralPath $packagedPath | Where-Object { $_ -eq $usingLine }) | Should -HaveCount 2 -Because 'the package states the using statement once and keeps the here-string line'

        $manifestPath = Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1'
        $imported = & pwsh -NoProfile -NonInteractive -Command {
            param($ManifestPath)

            $ErrorActionPreference = 'Stop'
            Import-Module -Name $ManifestPath -Force

            & (Get-Module -Name 'CompleterActions') {
                [pscustomobject] @{
                    Literal = Get-BuildProbeLiteral
                    Builder = Get-BuildProbeBuilder
                    Shared  = Get-BuildProbeShared
                    Tail    = Get-BuildProbeTail
                    Suffix  = Get-BuildProbeSuffix
                }
            }
        } -args $manifestPath

        $LASTEXITCODE | Should -Be 0
        $imported.Literal | Should -BeExactly $usingLine -Because 'the packaged function must return its here-string unchanged'
        $imported.Builder | Should -BeExactly 'built' -Because 'the hoisted using statement must still resolve the short type name'
        $imported.Shared | Should -BeExactly 'shared'
        $imported.Tail | Should -BeExactly 'tail' -Because 'the end of a comment block on a using line must stay, or the comment swallows the next function'
        $imported.Suffix | Should -BeExactly 'suffix' -Because 'a statement after a using statement on its line must stay in the package'
    }

    It 'fails the build when a public command is defined more than once' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        # Only the command's own definition carries the directive, so a second definition in its file, or one in any
        # other file that goes into the package after it, a private file or Bootstrap.ps1, would ship the command
        # without the MAML. A scope modifier on the name defines the same command.
        $stagingRoot = New-TestBuildStage -Name 'duplicates'
        Add-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Public/Get-Completer.ps1') -Value '', "function Get-Completer { 'second' }"
        Set-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Private/Get-BuildProbeShadow.ps1') -Value "function Reset-Completer { 'private' }"
        Add-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Bootstrap.ps1') -Value '', "function Test-CompleterSet { 'bootstrap' }", "function script:Unregister-Completer { 'bootstrap' }"

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine

        $LASTEXITCODE | Should -Not -Be 0 -Because $buildOutput
        $buildOutput | Should -Match "'Get-Completer' at [^'\r\n]*Get-Completer\.ps1:\d+, [^'\r\n]*Get-Completer\.ps1:\d+"
        $buildOutput | Should -Match "'Reset-Completer' at [^'\r\n]*Reset-Completer\.ps1:\d+, [^'\r\n]*Get-BuildProbeShadow\.ps1:1\b"
        $buildOutput | Should -Match "'Test-CompleterSet' at [^'\r\n]*Test-CompleterSet\.ps1:\d+, [^'\r\n]*Bootstrap\.ps1:\d+"
        $buildOutput | Should -Match "'Unregister-Completer' at [^'\r\n]*Unregister-Completer\.ps1:\d+, [^'\r\n]*Bootstrap\.ps1:\d+"
    }

    It 'fails the build when the sources name a public command on the Function: drive, under any condition' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        # Each write runs only when the package is imported into a session the build's import check does not match:
        # one with PSReadLine loaded, one with an environment variable set, or not at all, from a helper nothing
        # calls. Only the sources show them.
        $stagingRoot = New-TestBuildStage -Name 'drive'
        Set-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Private/Set-BuildProbeShadow.ps1') -Value @(
            'function Set-BuildProbeShadow'
            '{'
            "    New-Item -Path 'Function:\script:Test-CompleterSet' -Value { 'private' } -Force"
            '}'
        )
        Add-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Bootstrap.ps1') -Value @(
            ''
            "if (Get-Module -Name 'PSReadLine') { Set-Item -Path Function:Reset-Completer -Value { 'bootstrap' } }"
            "if (`$env:COMPLETERACTIONS_BUILD_PROBE) { `${function:Get-Completer} = { 'bootstrap' } }"
        )

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine

        $LASTEXITCODE | Should -Not -Be 0 -Because $buildOutput
        $buildOutput | Should -Match "'Reset-Completer' at [^'\r\n]*Reset-Completer\.ps1:\d+, [^'\r\n]*Bootstrap\.ps1:\d+"
        $buildOutput | Should -Match "'Get-Completer' at [^'\r\n]*Get-Completer\.ps1:\d+, [^'\r\n]*Bootstrap\.ps1:\d+"
        $buildOutput | Should -Match "'Test-CompleterSet' at [^'\r\n]*Test-CompleterSet\.ps1:\d+, [^'\r\n]*Set-BuildProbeShadow\.ps1:3\b"
    }

    It 'fails the build when the package replaces a public command while it loads' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        # A Function: path built at run time names no command the sources show, so only the imported package reveals
        # that the exported command lost the directive.
        $stagingRoot = New-TestBuildStage -Name 'replaced'
        Add-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Bootstrap.ps1') -Value '', "`$buildProbeName = 'Reset-Completer'", "Set-Item -Path `"Function:`$buildProbeName`" -Value { 'bootstrap' }"

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine

        $LASTEXITCODE | Should -Not -Be 0 -Because $buildOutput
        $buildOutput | Should -Match "'Reset-Completer' is defined at [^'\r\n]*CompleterActions\.psm1:\d+"
    }

    It 'publishes a version once and lets a rerun continue only when the repository holds the same package' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        if ($IsWindows -and $env:GITHUB_ACTIONS -ne 'true')
        {
            Set-ItResult -Skipped -Because 'the PSResourceGet store cannot be redirected on Windows'
        }

        # The release job publishes before it creates the GitHub release, so rerunning it after a later step failed runs
        # Publish_build again for a version the repository already holds, which PSGallery refuses. A rebuild on another
        # day changes only the manifest's Generated on line; any other difference must stop the release.
        $stagingRoot = New-TestBuildStage -Name 'publish'
        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine
        $LASTEXITCODE | Should -Be 0 -Because $buildOutput

        $packagePath = Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions'
        $packageManifest = Import-PowerShellDataFile -Path (Join-Path -Path $packagePath -ChildPath 'CompleterActions.psd1')
        $version = $packageManifest.ModuleVersion
        if (-not [string]::IsNullOrWhiteSpace($packageManifest.PrivateData.PSData.Prerelease))
        {
            $version = "$version-$($packageManifest.PrivateData.PSData.Prerelease)"
        }

        $repositoryPath = Join-Path -Path $TestDrive -ChildPath 'publish-repo'
        $dataHome = Join-Path -Path $TestDrive -ChildPath 'publish-xdg'
        New-Item -Path $repositoryPath, $dataHome -ItemType Directory | Out-Null
        $repositoryName = 'CaLocal-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $resultPath = Join-Path -Path $TestDrive -ChildPath 'publish-runs.json'

        $publishScriptPath = Join-Path -Path $TestDrive -ChildPath 'publish-runs.ps1'
        Set-Content -LiteralPath $publishScriptPath -Encoding utf8 -Value @'
param($RepositoryName, $RepositoryPath, $BuildScriptPath, $PackagePath, $ResultPath)
$ErrorActionPreference = 'Stop'
# A folder repository ignores the key, but Publish-PSResource refuses an empty one.
$env:GalleryAPI = 'test-key'
$runs = [System.Collections.Generic.List[object]]::new()
Register-PSResourceRepository -Name $RepositoryName -Uri $RepositoryPath -Trusted
try
{
    foreach ($step in 'first', 'rebuilt', 'changed')
    {
        $manifestPath = Join-Path -Path $PackagePath -ChildPath 'CompleterActions.psd1'
        if ($step -eq 'rebuilt')
        {
            (Get-Content -LiteralPath $manifestPath) -replace '^# Generated on: .*$', '# Generated on: 1/2/2099' | Set-Content -LiteralPath $manifestPath
        }

        if ($step -eq 'changed')
        {
            Add-Content -LiteralPath (Join-Path -Path $PackagePath -ChildPath 'CompleterActions.psm1') -Value '# changed after publication'
        }

        $text = $null
        $failure = $null
        try
        {
            $text = Invoke-Build -File $BuildScriptPath -Task Publish_build -Repository $RepositoryName 6>&1 | Out-String
        }
        catch
        {
            $failure = $_.Exception.Message
        }

        $runs.Add([pscustomobject] @{
                Step     = $step
                Text     = $text
                Failure  = $failure
                Packages = @(Get-ChildItem -LiteralPath $RepositoryPath -File | ForEach-Object { "$($_.Name) $((Get-FileHash -LiteralPath $_.FullName).Hash)" })
            })
    }
}
finally
{
    Unregister-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue
}

ConvertTo-Json -InputObject $runs.ToArray() -Depth 3 | Set-Content -LiteralPath $ResultPath -Encoding utf8
'@

        $savedDataHome = $env:XDG_DATA_HOME
        try
        {
            if (-not $IsWindows)
            {
                $env:XDG_DATA_HOME = $dataHome
            }

            $publishOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $publishScriptPath -RepositoryName $repositoryName -RepositoryPath $repositoryPath -BuildScriptPath $buildScriptPath -PackagePath $packagePath -ResultPath $resultPath 2>&1) -join [Environment]::NewLine
            $publishExitCode = $LASTEXITCODE
        }
        finally
        {
            $env:XDG_DATA_HOME = $savedDataHome
        }

        $publishExitCode | Should -Be 0 -Because $publishOutput
        $runs = @(Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json)
        $runs.Step | Should -Be @('first', 'rebuilt', 'changed')

        $runs[0].Failure | Should -BeNullOrEmpty
        @($runs[0].Packages) | Should -HaveCount 1
        @($runs[0].Packages)[0] | Should -BeLike "CompleterActions.$version.nupkg *"

        $runs[1].Failure | Should -BeNullOrEmpty -Because 'a rebuild of the published version continues the release'
        $runs[1].Text | Should -Match "already holds CompleterActions $([regex]::Escape($version)) with the same files as '[^'\r\n]+', so nothing was published\."
        @($runs[1].Packages) | Should -Be @($runs[0].Packages) -Because 'the rerun must not publish the version again'

        $runs[2].Failure | Should -Match "already holds CompleterActions $([regex]::Escape($version)), and that copy differs from '[^'\r\n]+' in CompleterActions\.psm1\. A published version cannot be replaced"
        @($runs[2].Packages) | Should -Be @($runs[0].Packages) -Because 'a different package must not replace the published one'
    }

    It 'builds a package that writes to the host while it loads' {
        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to build the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to build the packaged module'
        }

        # The import check reads what its pwsh returns, and host text comes back with it; that text is no finding.
        $stagingRoot = New-TestBuildStage -Name 'host'
        Add-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'src/Bootstrap.ps1') -Value '', "Write-Host 'build probe host text'", "Write-Information 'build probe information' -InformationAction Continue"

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1) -join [Environment]::NewLine

        $LASTEXITCODE | Should -Be 0 -Because $buildOutput
    }
}

Describe 'Registration identity' {
    BeforeAll {
        # The Kelvin sign (U+212A) lowercases to the letter k, so both Kelvin names
        # below have the key 'test-kelvintool', yet the runtime compares its keys
        # ordinally ignoring case and keeps them as two entries.
        $script:KelvinLetterName = 'Test-KelvinTool'
        $script:KelvinSignName = 'Test-{0}elvinTool' -f [char] 0x212A

        # The runtime takes the final sigma (U+03C2) and the sigma (U+03C3) for one
        # another, but lowercasing keeps them apart, so this key names the final-sigma
        # name without being its lowercase form.
        $script:FinalSigmaName = 'Test-Sigma{0}Tool' -f [char] 0x03C2
        $script:SigmaKey = 'test-sigma{0}tool' -f [char] 0x03C3

        $script:IdentityCleanupTargets = @(
            @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; CompleterType = 'Parameter' }
            @{ CommandName = 'Test-IdentityTool:Name'; CompleterType = 'Native' }
            @{ CommandName = 'importfixture'; CompleterType = 'Native' }
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
            @{ CommandName = $script:KelvinLetterName; CompleterType = 'Native' }
            @{ CommandName = $script:KelvinSignName; CompleterType = 'Native' }
            @{ CommandName = $script:KelvinLetterName; ParameterName = 'Name'; CompleterType = 'Parameter' }
            @{ CommandName = $script:KelvinSignName; ParameterName = 'Name'; CompleterType = 'Parameter' }
            @{ CommandName = $script:FinalSigmaName; CompleterType = 'Native' }
        )

        function Get-TestIdentityCompletion
        {
            $inputScript = 'Test-IdentityTool -Name '
            @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText)
        }

        function Get-TestIdentityState
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Parameter', 'Native')]
                [string] $CompleterType
            )

            $records = if ($CompleterType -eq 'Native')
            {
                @(Get-Completer -CommandName 'Test-IdentityTool:Name' -Native)
            }
            else
            {
                @(Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name')
            }

            @($records | ForEach-Object { '{0}/{1}/{2}' -f $_.CompleterType, $_.State, $_.ScriptText.Trim() })
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:IdentityCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-IdentityTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }
    }

    AfterEach {
        foreach ($cleanupTarget in $script:IdentityCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-IdentityTool' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    Context 'ownership is the exact script block, not its text' {
        BeforeAll {
            function Get-TestIdentityClosure
            {
                param(
                    [Parameter(Mandatory)]
                    [string] $Value
                )

                { $Value }.GetNewClosure()
            }
        }

        It 'reports an equal-text closure that replaced a managed closure as Stale and Conflicted and gates its removal' {
            $managed = Get-TestIdentityClosure -Value 'alpha'
            $external = Get-TestIdentityClosure -Value 'beta'
            $managed.ToString() | Should -BeExactly $external.ToString() -Because 'the closures differ only in their captured value'

            Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $managed
            Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $external

            Get-TestIdentityCompletion | Should -Be @('beta')
            Get-TestIdentityState -CompleterType Parameter | Should -Be @('Parameter/Stale/$Value', 'Parameter/Conflicted/$Value')

            {
                Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            } | Should -Throw '*is stale*-AllowUnmanaged*'

            Get-TestIdentityCompletion | Should -Be @('beta') -Because 'the refused removal leaves the live value alone'

            $removed = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru
            [object]::ReferenceEquals($removed.ScriptBlock, $external) | Should -BeTrue
            Get-TestIdentityState -CompleterType Parameter | Should -BeNullOrEmpty
        }

        It 'refuses to replace a managed closure with an equal-text closure without -Force' {
            $first = Get-TestIdentityClosure -Value 'alpha'
            $second = Get-TestIdentityClosure -Value 'beta'

            Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $second
            } | Should -Throw '*already exists*Use -Force*'

            Get-TestIdentityCompletion | Should -Be @('alpha')

            $forced = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $second -Force -PassThru
            [object]::ReferenceEquals($forced.ScriptBlock, $second) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('beta')
            Get-TestIdentityState -CompleterType Parameter | Should -Be @('Parameter/Active/$Value')
        }

        It 'treats script blocks whose text differs only in case as different completers' {
            $upper = [scriptblock]::Create("'Value'")
            $lower = [scriptblock]::Create("'value'")

            Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $upper

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $lower
            } | Should -Throw '*already exists*Use -Force*'

            Get-TestIdentityCompletion | Should -BeExactly @('Value')

            Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $lower

            Get-TestIdentityCompletion | Should -BeExactly @('value')
            Get-TestIdentityState -CompleterType Parameter | Should -BeExactly @("Parameter/Stale/'Value'", "Parameter/Conflicted/'value'")

            {
                Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            } | Should -Throw '*is stale*-AllowUnmanaged*'
        }

        # Safety guard: ownership moved from text to the exact script block, and this pins
        # the two reuse paths the rewritten comparison must keep, equal unbound text and
        # a re-import of the same script, so it passes before and after that change.
        It 'reuses the managed record for equal unbound text and for a re-imported script' {
            $first = [scriptblock]::Create("'same'")
            $second = [scriptblock]::Create("'same'")

            $firstRecord = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first -PassThru
            $secondRecord = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $second -PassThru

            [object]::ReferenceEquals($secondRecord.ScriptBlock, $firstRecord.ScriptBlock) | Should -BeTrue -Because 'two unbound script blocks with the same text are the same completer'
            Get-TestIdentityState -CompleterType Parameter | Should -Be @("Parameter/Active/'same'")

            $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ImportableNativeCompleter.ps1'
            $imported = @(Import-CompleterScript -LiteralPath $fixturePath | Register-Completer -PassThru)
            $reimported = @(Import-CompleterScript -LiteralPath $fixturePath | Register-Completer -PassThru)

            $imported.Count | Should -Be 2
            $reimported.Count | Should -Be 2

            for ($index = 0; $index -lt $imported.Count; $index++)
            {
                [object]::ReferenceEquals($reimported[$index].ScriptBlock, $imported[$index].ScriptBlock) | Should -BeTrue -Because 'importing and registering the same script again is a no-op, although each import binds its script blocks to a new module'
            }

            @(Get-Completer -CommandName 'importfixture', 'importfixture.exe' -Native | ForEach-Object { [string] $_.State }) | Should -Be @('Active', 'Active')
        }

        # Safety guard: the rewritten comparison binds equal text to its module and file,
        # and this pins that one module instance registering the same text from the same
        # file stays a no-op, so it passes before and after that change.
        It 'reuses the managed record for equal text bound to the same module and defined in the same file' {
            $maker = New-Module -Name 'TestIdentityMaker' -ScriptBlock {
                function Get-TestIdentityBlock { { 'same' } }
                Export-ModuleMember
            }

            $first = & $maker { Get-TestIdentityBlock }
            $second = & $maker { Get-TestIdentityBlock }

            [object]::ReferenceEquals($first, $second) | Should -BeFalse -Because 'each call creates a new script block'
            [object]::ReferenceEquals($first.Module, $maker) | Should -BeTrue
            [object]::ReferenceEquals($second.Module, $maker) | Should -BeTrue
            $second.File | Should -BeExactly $first.File

            $firstRecord = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first -PassThru
            $secondRecord = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $second -PassThru

            [object]::ReferenceEquals($secondRecord.ScriptBlock, $firstRecord.ScriptBlock) | Should -BeTrue -Because 'a script block with the same text, bound to the same module and defined in the same file, is the same completer'
            Get-TestIdentityState -CompleterType Parameter | Should -Be @("Parameter/Active/'same'")
            Get-TestIdentityCompletion | Should -Be @('same')
        }

        It 'treats equal text defined in another file as a different completer' {
            $firstPath = Join-Path -Path $TestDrive -ChildPath 'identity-first.ps1'
            $secondPath = Join-Path -Path $TestDrive -ChildPath 'identity-second.ps1'
            Set-Content -LiteralPath $firstPath -Value "{ 'same' }" -Encoding utf8
            Set-Content -LiteralPath $secondPath -Value "{ 'same' }" -Encoding utf8
            $first = & $firstPath
            $second = & $secondPath
            $first.ToString() | Should -BeExactly $second.ToString()

            Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $second
            } | Should -Throw '*already exists*Use -Force*' -Because 'the file that defines a script block is part of its context, whatever its text'
        }
    }

    Context 'a native command whose name has the same key as a parameter target' {
        It 'returns only the kind each Get-Completer lookup names, and both from an unfiltered lookup' {
            Register-ArgumentCompleter -Native -CommandName 'Test-IdentityTool:Name' -ScriptBlock { 'native-result' }
            Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }

            Get-TestIdentityState -CompleterType Parameter | Should -Be @("Parameter/Discovered/'parameter-result'")
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Discovered/'native-result'")

            $all = @(Get-Completer | Where-Object -Property 'CommandName' -Like -Value 'Test-IdentityTool*')
            @($all | ForEach-Object { [string] $_.CompleterType }) | Should -Be @('Native', 'Parameter')
            @($all.Key | Select-Object -Unique) | Should -Be @('test-identitytool:name') -Because 'the two targets share the key, which is why the kind is part of their identity'
        }

        It 'registers both kinds side by side without -Force' {
            $parameter = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' } -PassThru
            $native = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-result' } -PassThru

            $native.CompleterType | Should -Be 'Native'
            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $parameter.ScriptBlock) | Should -BeTrue
            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool:Name' -Native).ScriptBlock, $native.ScriptBlock) | Should -BeTrue
            Get-TestIdentityState -CompleterType Parameter | Should -Be @("Parameter/Active/'parameter-result'")
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-result'")
            Get-TestIdentityCompletion | Should -Be @('parameter-result')

            $state = InModuleScope CompleterActions {
                Get-CompleterActionState
            }

            $state['Registrations'].Count | Should -Be 2
        }

        It 'replaces only the kind Register-Completer -Force names' {
            $parameter = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' } -PassThru
            $null = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-first' } -Force

            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $parameter.ScriptBlock) | Should -BeTrue -Because 'a forced native registration must not replace the parameter record'
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-first'")

            $null = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-second' } -Force

            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-second'")
            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $parameter.ScriptBlock) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('parameter-result')

            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-second' } -Force

            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-second'")
            Get-TestIdentityCompletion | Should -Be @('parameter-second')
        }

        It 'removes only the kind Unregister-Completer names' {
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }
            $null = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-result' }

            $removed = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false -PassThru

            $removed.CompleterType | Should -Be 'Parameter'
            Get-TestIdentityState -CompleterType Parameter | Should -BeNullOrEmpty
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-result'")

            {
                Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            } | Should -Throw '*No completer registration was found*'

            $null = Unregister-Completer -CommandName 'Test-IdentityTool:Name' -Native -Confirm:$false
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }

            {
                Unregister-Completer -CommandName 'Test-IdentityTool:Name' -Native -Confirm:$false
            } | Should -Throw '*No completer registration was found*' -Because 'a native removal must not find the parameter registration'

            Get-TestIdentityState -CompleterType Parameter | Should -Be @("Parameter/Active/'parameter-result'")

            $null = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            Register-ArgumentCompleter -Native -CommandName 'Test-IdentityTool:Name' -ScriptBlock { 'native-result' }
            Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }

            $removedUnmanaged = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -AllowUnmanaged -Confirm:$false -PassThru

            $removedUnmanaged.CompleterType | Should -Be 'Parameter'
            Get-TestIdentityState -CompleterType Parameter | Should -BeNullOrEmpty
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Discovered/'native-result'")
        }
    }

    Context 'two native names that lowercase to the same key' {
        BeforeAll {
            function Get-TestKelvinState
            {
                @(
                    Get-Completer |
                        Where-Object { $_.IsNative -and $_.Key -eq 'test-kelvintool' } |
                        ForEach-Object {
                            $spelling = if ([string]::Equals($_.CommandName, $script:KelvinSignName, [System.StringComparison]::Ordinal)) { 'sign' } else { 'letter' }
                            '{0}/{1}/{2}' -f $spelling, $_.State, $_.ScriptText.Trim()
                        } |
                        Sort-Object
                )
            }

            function Get-TestKelvinCompletion
            {
                param(
                    [Parameter(Mandatory)]
                    [string] $CommandName
                )

                $inputScript = "$CommandName "
                @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText)
            }
        }

        It 'finds and removes only the name each command is given' {
            $letter = Register-Completer -CommandName $script:KelvinLetterName -Native -ScriptBlock { 'letter-result' } -PassThru
            $letter.Key | Should -BeExactly 'test-kelvintool'

            @(Get-Completer -CommandName $script:KelvinSignName -Native) | Should -BeNullOrEmpty -Because 'the runtime does not complete the Kelvin-sign name with the letter name''s completer'

            {
                Unregister-Completer -CommandName $script:KelvinSignName -Native -Confirm:$false
            } | Should -Throw '*No completer registration was found*'

            Get-TestKelvinState | Should -Be @("letter/Active/'letter-result'")
        }

        It 'registers both names side by side without -Force and removes each one alone' {
            $letter = Register-Completer -CommandName $script:KelvinLetterName -Native -ScriptBlock { 'letter-result' } -PassThru
            $sign = Register-Completer -CommandName $script:KelvinSignName -Native -ScriptBlock { 'sign-result' } -PassThru

            $sign.Key | Should -BeExactly $letter.Key -Because 'the two names share the lowercase key, which is why the key is not their identity'
            [object]::ReferenceEquals((Get-Completer -CommandName $script:KelvinLetterName -Native).ScriptBlock, $letter.ScriptBlock) | Should -BeTrue
            [object]::ReferenceEquals((Get-Completer -CommandName $script:KelvinSignName -Native).ScriptBlock, $sign.ScriptBlock) | Should -BeTrue
            Get-TestKelvinState | Should -Be @("letter/Active/'letter-result'", "sign/Active/'sign-result'")
            Get-TestKelvinCompletion -CommandName $script:KelvinLetterName | Should -Be @('letter-result')
            Get-TestKelvinCompletion -CommandName $script:KelvinSignName | Should -Be @('sign-result')

            $removed = Unregister-Completer -CommandName $script:KelvinSignName -Native -Confirm:$false -PassThru

            [string]::Equals($removed.CommandName, $script:KelvinSignName, [System.StringComparison]::Ordinal) | Should -BeTrue
            $removed.ScriptText.Trim() | Should -BeExactly "'sign-result'"
            Get-TestKelvinState | Should -Be @("letter/Active/'letter-result'")
            Get-TestKelvinCompletion -CommandName $script:KelvinLetterName | Should -Be @('letter-result')
        }

        It 'refuses an object that names only a key two native targets share, on every -InputObject command' {
            $null = Register-Completer -CommandName $script:KelvinLetterName -Native -ScriptBlock { 'letter-result' }
            $null = Register-Completer -CommandName $script:KelvinSignName -Native -ScriptBlock { 'sign-result' }
            $keyOnly = Get-Completer -CommandName $script:KelvinSignName -Native | Select-Object -Property Key, IsNative
            $keyOnly.Key | Should -BeExactly 'test-kelvintool'
            $refusal = "*The key 'test-kelvintool' belongs to 2 registered native targets*Supply RuntimeKey, or CommandName*"

            { $keyOnly | Unregister-Completer -Confirm:$false } | Should -Throw $refusal
            { $keyOnly | Get-Completer } | Should -Throw $refusal
            { $keyOnly | Reset-Completer -Confirm:$false -ErrorAction Stop } | Should -Throw $refusal
            { $keyOnly | Test-CompleterRegistration -InputText 'x ' } | Should -Throw $refusal
            { [pscustomobject] @{ RegistrationKey = 'test-kelvintool'; IsNative = $true; ScriptBlock = { 'other' } } | Register-Completer -Force } | Should -Throw $refusal
            { [pscustomobject] @{ Key = 'test-kelvintool'; IsNative = $true; SourcePath = (Join-Path -Path $TestDrive -ChildPath 'kelvin.ps1') } | Export-CompleterSet -Path (Join-Path -Path $TestDrive -ChildPath 'kelvin.psd1') } | Should -Throw $refusal
            Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath 'kelvin.psd1') | Should -BeFalse -Because 'a refused export writes no set file'

            Get-TestKelvinState | Should -Be @("letter/Active/'letter-result'", "sign/Active/'sign-result'")

            $removed = Get-Completer -CommandName $script:KelvinSignName -Native | Select-Object -Property RuntimeKey, IsNative | Unregister-Completer -Confirm:$false -PassThru

            [string]::Equals($removed.RuntimeKey, $script:KelvinSignName, [System.StringComparison]::Ordinal) | Should -BeTrue -Because 'RuntimeKey names the target exactly'
            Get-TestKelvinState | Should -Be @("letter/Active/'letter-result'")

            $keyOnly | Get-Completer | ForEach-Object { [string]::Equals($_.RuntimeKey, $script:KelvinLetterName, [System.StringComparison]::Ordinal) } | Should -BeTrue -Because 'the key now belongs to one registered target'
            $null = $keyOnly | Unregister-Completer -Confirm:$false
            Get-TestKelvinState | Should -BeNullOrEmpty
        }

        It 'refuses an object that names only a key two parameter targets share' {
            $null = Register-Completer -CommandName $script:KelvinLetterName -ParameterName 'Name' -ScriptBlock { 'letter-result' }
            $null = Register-Completer -CommandName $script:KelvinSignName -ParameterName 'Name' -ScriptBlock { 'sign-result' }
            $keyOnly = Get-Completer -CommandName $script:KelvinSignName -ParameterName 'Name' | Select-Object -Property Key, IsNative

            { $keyOnly | Unregister-Completer -Confirm:$false } | Should -Throw "*The key 'test-kelvintool:name' belongs to 2 registered parameter targets*"

            $removed = Get-Completer -CommandName $script:KelvinSignName -ParameterName 'Name' | Select-Object -Property RuntimeKey, IsNative | Unregister-Completer -Confirm:$false -PassThru

            [string]::Equals($removed.CommandName, $script:KelvinSignName, [System.StringComparison]::Ordinal) | Should -BeTrue
            $remaining = @(Get-Completer | Where-Object { -not $_.IsNative -and $_.Key -eq 'test-kelvintool:name' })
            $remaining.Count | Should -Be 1
            [string]::Equals($remaining[0].CommandName, $script:KelvinLetterName, [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        It 'refuses an object that names only a key a registered target holds under another spelling, on every -InputObject command' {
            $null = Register-Completer -CommandName $script:KelvinSignName -Native -ScriptBlock { 'sign-result' }
            $keyOnly = [pscustomobject] @{ Key = 'test-kelvintool'; IsNative = $true }
            $refusal = "*The key 'test-kelvintool' belongs to the registered native target '$script:KelvinSignName'*could also name the native target 'test-kelvintool'*Supply RuntimeKey, or CommandName*"
            $setPath = Join-Path -Path $TestDrive -ChildPath 'kelvin-sign.psd1'

            { [pscustomobject] @{ Key = 'test-kelvintool'; IsNative = $true; ScriptBlock = { 'letter-from-key' } } | Register-Completer -Force } | Should -Throw $refusal
            { $keyOnly | Unregister-Completer -Confirm:$false } | Should -Throw $refusal
            { $keyOnly | Get-Completer } | Should -Throw $refusal
            { $keyOnly | Reset-Completer -Confirm:$false -ErrorAction Stop } | Should -Throw $refusal
            { $keyOnly | Test-CompleterRegistration -InputText 'x ' } | Should -Throw $refusal
            { [pscustomobject] @{ Key = 'test-kelvintool'; IsNative = $true; SourcePath = (Join-Path -Path $TestDrive -ChildPath 'kelvin.ps1') } | Export-CompleterSet -Path $setPath } | Should -Throw $refusal
            Test-Path -LiteralPath $setPath | Should -BeFalse -Because 'a refused export writes no set file'

            Get-TestKelvinState | Should -Be @("sign/Active/'sign-result'") -Because 'the forced registration neither replaced the Kelvin-sign target nor created the letter one'
            Get-TestKelvinCompletion -CommandName $script:KelvinSignName | Should -Be @('sign-result')

            $spelled = [pscustomobject] @{ Key = $script:KelvinSignName; IsNative = $true } | Get-Completer
            [string]::Equals($spelled.RuntimeKey, $script:KelvinSignName, [System.StringComparison]::Ordinal) | Should -BeTrue -Because 'a key spelled as the registered name names that target'

            $null = Unregister-Completer -CommandName $script:KelvinSignName -Native -Confirm:$false
            $letter = [pscustomobject] @{ Key = 'test-kelvintool'; IsNative = $true; ScriptBlock = { 'letter-from-key' } } | Register-Completer -PassThru

            [string]::Equals($letter.RuntimeKey, 'test-kelvintool', [System.StringComparison]::Ordinal) | Should -BeTrue -Because 'with no other spelling registered the key names the target it spells'
            Get-TestKelvinState | Should -Be @("letter/Active/'letter-from-key'")
        }

        It 'refuses an object that names only a key a registered parameter target holds under another spelling' {
            $null = Register-Completer -CommandName $script:KelvinSignName -ParameterName 'Name' -ScriptBlock { 'sign-result' }
            $keyOnly = [pscustomobject] @{ Key = 'test-kelvintool:name'; IsNative = $false }

            { $keyOnly | Unregister-Completer -Confirm:$false } | Should -Throw "*The key 'test-kelvintool:name' belongs to the registered parameter target*could also name the parameter target 'test-kelvintool:name'*"

            $remaining = @(Get-Completer | Where-Object { -not $_.IsNative -and $_.Key -eq 'test-kelvintool:name' })
            $remaining.Count | Should -Be 1
            [string]::Equals($remaining[0].CommandName, $script:KelvinSignName, [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        It 'lists and removes both unmanaged runtime entries' {
            Register-ArgumentCompleter -Native -CommandName $script:KelvinLetterName -ScriptBlock { 'letter-result' }
            Register-ArgumentCompleter -Native -CommandName $script:KelvinSignName -ScriptBlock { 'sign-result' }

            Get-TestKelvinState | Should -Be @("letter/Discovered/'letter-result'", "sign/Discovered/'sign-result'")

            $removed = @(Unregister-Completer -CommandName $script:KelvinLetterName, $script:KelvinSignName -Native -AllowUnmanaged -Confirm:$false -PassThru)

            $removed.Count | Should -Be 2
            Get-TestKelvinState | Should -BeNullOrEmpty
        }
    }

    Context 'a key the runtime takes for a registered name that lowercasing does not reach' {
        It 'names the registered target and keeps its spelling' {
            [string]::Equals($script:FinalSigmaName.ToLowerInvariant(), $script:SigmaKey, [System.StringComparison]::Ordinal) | Should -BeFalse -Because 'lowercasing keeps the final sigma'
            [string]::Equals($script:FinalSigmaName, $script:SigmaKey, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue -Because 'the runtime takes the two sigmas for one another'

            $null = Register-Completer -CommandName $script:FinalSigmaName -Native -ScriptBlock { 'final-result' }
            $keyOnly = [pscustomobject] @{ Key = $script:SigmaKey; IsNative = $true }

            $found = $keyOnly | Get-Completer
            [string]::Equals($found.RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::Ordinal) | Should -BeTrue

            {
                [pscustomobject] @{ Key = $script:SigmaKey; IsNative = $true; ScriptBlock = { 'from-key' } } | Register-Completer
            } | Should -Throw '*already exists*Use -Force*'

            $forced = [pscustomobject] @{ Key = $script:SigmaKey; IsNative = $true; ScriptBlock = { 'from-key' } } | Register-Completer -Force -PassThru

            [string]::Equals($forced.RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::Ordinal) | Should -BeTrue -Because 'the key names the registered target, so the record keeps the spelling the runtime entry has'
            $records = @(Get-Completer | Where-Object { $_.IsNative -and [string]::Equals($_.RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::OrdinalIgnoreCase) })
            $records.Count | Should -Be 1
            $records[0].State | Should -Be 'Active'
            [string]::Equals($records[0].RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::Ordinal) | Should -BeTrue
            $inputScript = "$script:FinalSigmaName "
            @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText) | Should -Be @('from-key')

            $removed = $keyOnly | Unregister-Completer -Confirm:$false -PassThru

            [string]::Equals($removed.RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::Ordinal) | Should -BeTrue
            @(Get-Completer | Where-Object { $_.IsNative -and [string]::Equals($_.RuntimeKey, $script:FinalSigmaName, [System.StringComparison]::OrdinalIgnoreCase) }) | Should -BeNullOrEmpty
        }
    }

    Context 'a script path compares the way the file system does' {
        BeforeAll {
            $script:IdentityScriptText = "Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'same' }"
        }

        It 'treats two scripts whose paths differ only in case as two scripts on a case-sensitive file system' -Skip:($IsWindows -or $IsMacOS) {
            $upperPath = Join-Path -Path $TestDrive -ChildPath 'Identity_completer.ps1'
            $lowerPath = Join-Path -Path $TestDrive -ChildPath 'identity_completer.ps1'
            Set-Content -LiteralPath $upperPath -Value $script:IdentityScriptText -Encoding utf8
            Set-Content -LiteralPath $lowerPath -Value $script:IdentityScriptText -Encoding utf8

            $null = Import-CompleterScript -LiteralPath $upperPath | Register-Completer

            {
                Import-CompleterScript -LiteralPath $lowerPath | Register-Completer
            } | Should -Throw '*already exists*Use -Force*'

            Split-Path -Path (Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptPath -Leaf | Should -BeExactly 'Identity_completer.ps1'

            $null = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            $null = Register-Completer -LiteralPath $upperPath -Lazy

            {
                Register-Completer -LiteralPath $lowerPath -Lazy
            } | Should -Throw '*already exists*Use -Force*'

            $pending = Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name'
            $pending.State | Should -Be 'Pending'
            Split-Path -Path $pending.ScriptPath -Leaf | Should -BeExactly 'Identity_completer.ps1'
        }

        # Safety guard: script paths now compare the way the file system does, and on a
        # case-insensitive one that must keep two spellings of one file as one script, so
        # this passes before and after that change; its Linux sibling above fails before it.
        It 'treats two spellings of one script path as the same script on a case-insensitive file system' -Skip:(-not ($IsWindows -or $IsMacOS)) {
            $path = Join-Path -Path $TestDrive -ChildPath 'identity_completer.ps1'
            $otherSpelling = Join-Path -Path $TestDrive -ChildPath 'IDENTITY_COMPLETER.PS1'
            Set-Content -LiteralPath $path -Value $script:IdentityScriptText -Encoding utf8

            $imported = Import-CompleterScript -LiteralPath $path | Register-Completer -PassThru
            $reimported = Import-CompleterScript -LiteralPath $otherSpelling | Register-Completer -PassThru

            [object]::ReferenceEquals($reimported.ScriptBlock, $imported.ScriptBlock) | Should -BeTrue -Because 'both spellings name one file'

            $null = Unregister-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -Confirm:$false
            $lazy = Register-Completer -LiteralPath $path -Lazy -PassThru
            $lazyAgain = Register-Completer -LiteralPath $otherSpelling -Lazy -PassThru

            [object]::ReferenceEquals($lazyAgain.ScriptBlock, $lazy.ScriptBlock) | Should -BeTrue
        }
    }

    Context 'a script path on an input object does not vouch for its script block' {
        It 'refuses an equal-text script block that is not bound to the imported script without -Force' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-trusted.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @'
$value = 'alpha'
Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $value }
'@

            $imported = @(Import-CompleterScript -LiteralPath $scriptPath -Trusted)
            $record = $imported | Register-Completer -PassThru
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $closure = & {
                param(
                    [string] $value
                )

                [scriptblock]::Create($record.ScriptText).GetNewClosure()
            } 'beta'
            $unbound = [scriptblock]::Create($record.ScriptText)
            $closure.ToString() | Should -BeExactly $record.ScriptText
            $pathClaim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = $closure; ScriptPath = $scriptPath; Trusted = $true }
            $moduleClaim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = $closure; ScriptPath = $scriptPath; Trusted = $true; ImportModule = $imported[0].ImportModule }

            { $pathClaim | Register-Completer } | Should -Throw '*already exists*Use -Force*'
            { $moduleClaim | Register-Completer } | Should -Throw '*already exists*Use -Force*' -Because 'the closure is not bound to the module the import created'
            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $unbound
            } | Should -Throw '*already exists*Use -Force*' -Because 'an unbound block does not see the $value the script set'

            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $record.ScriptBlock) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $reimported = Import-CompleterScript -LiteralPath $scriptPath -Trusted | Register-Completer -PassThru
            [object]::ReferenceEquals($reimported.ScriptBlock, $record.ScriptBlock) | Should -BeTrue -Because 'importing and registering the same script again is still a no-op'

            $forced = $pathClaim | Register-Completer -Force -PassThru
            [object]::ReferenceEquals($forced.ScriptBlock, $closure) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('beta')
        }

        It 'refuses a closure of the imported script block itself without -Force' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-closure.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @'
$value = 'alpha'
Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $value }
'@

            $imported = @(Import-CompleterScript -LiteralPath $scriptPath -Trusted)
            $record = $imported | Register-Completer -PassThru
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $closure = & {
                param(
                    [string] $value
                )

                $record.ScriptBlock.GetNewClosure()
            } 'beta'
            $closure.ToString() | Should -BeExactly $record.ScriptText
            $closure.File | Should -BeExactly $record.ScriptBlock.File -Because 'the closure keeps the file of the block it was made from, so only its binding tells the two apart'
            $pathClaim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = $closure; ScriptPath = $scriptPath; Trusted = $true }
            $moduleClaim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = $closure; ScriptPath = $scriptPath; Trusted = $true; ImportModule = $imported[0].ImportModule }

            { $pathClaim | Register-Completer } | Should -Throw '*already exists*Use -Force*'
            { $moduleClaim | Register-Completer } | Should -Throw '*already exists*Use -Force*' -Because 'the closure is bound to a module of its own, not to the module the import created'

            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $record.ScriptBlock) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $forced = $pathClaim | Register-Completer -Force -PassThru
            [object]::ReferenceEquals($forced.ScriptBlock, $closure) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('beta')
        }

        It 'does not take an ImportModule property as proof that a script block was imported' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-provenance.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value @'
$value = 'alpha'
Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $value }
'@

            $imported = @(Import-CompleterScript -LiteralPath $scriptPath -Trusted)
            $record = $imported | Register-Completer -PassThru
            [object]::ReferenceEquals($record.ImportModule, $imported[0].ImportModule) | Should -BeTrue -Because 'the managed record of an imported block names the capture module the import ran the script in'

            $closure = & {
                param(
                    [string] $value
                )

                $imported[0].ScriptBlock.GetNewClosure()
            } 'beta'
            $selfClaim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = $closure; SourcePath = $scriptPath; Trusted = $true; ImportModule = $closure.Module }
            [object]::ReferenceEquals($closure.Module, $selfClaim.ImportModule) | Should -BeTrue -Because 'the claim names the very module its script block is bound to'

            { $selfClaim | Register-Completer } | Should -Throw '*already exists*Use -Force*' -Because 'only the import itself vouches for a capture module'
            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $record.ScriptBlock) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $forced = $selfClaim | Register-Completer -Force -PassThru
            [object]::ReferenceEquals($forced.ScriptBlock, $closure) | Should -BeTrue
            $forced.ImportModule | Should -BeNullOrEmpty -Because 'the claimed ImportModule is not carried onto the managed record'
            Get-TestIdentityCompletion | Should -Be @('beta')

            $retiered = @(Import-CompleterScript -LiteralPath $scriptPath -Trusted)
            $retiered[0].Trusted = $false
            $strictClaim = $retiered | Register-Completer -Force -PassThru
            $strictClaim.ImportModule | Should -BeNullOrEmpty -Because 'the import ran the script under the trusted tier, not the tier the record now claims'
        }

        It 'does not take a script block bound to the capture module as one the import emitted' {
            $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ImportableNativeCompleter.ps1'
            $imported = @(Import-CompleterScript -LiteralPath $fixturePath)
            $capture = $imported[0].ImportModule
            $minted = $capture.NewBoundScriptBlock({ 'minted' })
            [object]::ReferenceEquals($minted.Module, $capture) | Should -BeTrue -Because 'any caller can bind a script block to the capture module an imported record exposes'

            $claim = [pscustomobject] @{ CommandName = 'importfixture'; IsNative = $true; ScriptBlock = $minted; SourcePath = $imported[0].SourcePath; Trusted = $false; ImportModule = $capture }
            $record = $claim | Register-Completer -PassThru

            $record.ImportModule | Should -BeNullOrEmpty -Because 'the import did not emit the minted script block'
            {
                Register-Completer -LiteralPath $fixturePath -Lazy
            } | Should -Throw '*already exists*Use -Force*' -Because 'the record does not hold what the script imported, so registering the script lazily is not a no-op over it'
            @((TabExpansion2 -InputScript 'importfixture ' -CursorColumn 14).CompletionMatches.CompletionText) | Should -Be @('minted')

            $own = @($imported | Register-Completer -Force -PassThru)
            [object]::ReferenceEquals($own[0].ImportModule, $capture) | Should -BeTrue -Because 'the script blocks the import emitted are still its own'
            $lazy = @(Register-Completer -LiteralPath $fixturePath -Lazy -PassThru)
            [object]::ReferenceEquals($lazy[0].ScriptBlock, $own[0].ScriptBlock) | Should -BeTrue -Because 'the record now holds what the script imported under the same tier'
        }

        # Safety guard: pins the documented treatment of a module that other code creates
        # under a capture module's name, so it passes before and after
        # about_Import_Completers states it.
        It 'treats a module that other code creates under a capture module''s name as any other module with that name' {
            $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ImportableNativeCompleter.ps1'
            $imported = @(Import-CompleterScript -LiteralPath $fixturePath)
            $own = @($imported | Register-Completer -PassThru)
            $capture = $imported[0].ImportModule
            $namesake = New-Module -Name $capture.Name -ScriptBlock { Export-ModuleMember }
            $rebound = $namesake.NewBoundScriptBlock($imported[0].ScriptBlock)
            [object]::ReferenceEquals($rebound.Module, $capture) | Should -BeFalse
            $rebound.ToString() | Should -BeExactly $own[0].ScriptText
            $rebound.File | Should -BeExactly $imported[0].ScriptBlock.File

            $claim = [pscustomobject] @{ CommandName = $imported[0].CommandName; IsNative = $true; ScriptBlock = $rebound; SourcePath = $imported[0].SourcePath; Trusted = $false }
            $replaced = $claim | Register-Completer -PassThru

            [object]::ReferenceEquals($replaced.ScriptBlock, $rebound) | Should -BeTrue -Because 'a block from another module with the name of the live record''s module and the same text, file, ScriptPath, and tier replaces the record without -Force'
            [object]::ReferenceEquals((Get-Completer -CommandName $imported[0].CommandName -Native).ScriptBlock, $rebound) | Should -BeTrue
            $replaced.ImportModule | Should -BeNullOrEmpty -Because 'the import did not emit the rebound script block'
            {
                Register-Completer -LiteralPath $fixturePath -Lazy
            } | Should -Throw '*already exists*Use -Force*' -Because 'the record no longer holds what the script imported'
            {
                Import-CompleterScript -LiteralPath $fixturePath | Register-Completer
            } | Should -Throw '*already exists*Use -Force*' -Because 'importing the script again runs it in a capture module with a new name'
        }

        It 'refuses a lazy registration over an active record that only names the script path without -Force' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-lazy.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value "Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'from-file' }"

            $claim = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = { 'hand-built' }; ScriptPath = $scriptPath }
            $null = $claim | Register-Completer

            {
                Register-Completer -LiteralPath $scriptPath -Lazy
            } | Should -Throw '*already exists*Use -Force*'

            Get-TestIdentityCompletion | Should -Be @('hand-built')

            $imported = Import-CompleterScript -LiteralPath $scriptPath | Register-Completer -Force -PassThru
            $lazy = Register-Completer -LiteralPath $scriptPath -Lazy -PassThru

            [object]::ReferenceEquals($lazy.ScriptBlock, $imported.ScriptBlock) | Should -BeTrue -Because 'the active record already loaded that script under the same tier'
            $lazy.State | Should -Be 'Active'
            Get-TestIdentityCompletion | Should -Be @('from-file')
        }
    }

    Context 'a module that registers its completer again' {
        It 'replaces the managed record with the block of the module imported again, and refuses its closures without -Force' {
            $modulePath = Join-Path -Path $TestDrive -ChildPath 'TestIdentityProbe.psm1'
            Set-Content -LiteralPath $modulePath -Encoding utf8 -Value @'
param(
    [string] $Value
)

$script:value = $Value

function Register-TestIdentityProbe
{
    Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $script:value } -PassThru
}

function Register-TestIdentityProbeClosure
{
    Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $script:value }.GetNewClosure() -PassThru
}
'@

            try
            {
                $probe = Import-Module -Name $modulePath -ArgumentList 'alpha' -Force -PassThru
                $first = Register-TestIdentityProbe
                [object]::ReferenceEquals($first.ScriptBlock.Module, $probe) | Should -BeTrue
                [object]::ReferenceEquals((Register-TestIdentityProbe).ScriptBlock, $first.ScriptBlock) | Should -BeTrue -Because 'the same module instance registering the same text again is a no-op'
                Get-TestIdentityCompletion | Should -Be @('alpha')

                $reimportedProbe = Import-Module -Name $modulePath -ArgumentList 'beta' -Force -PassThru
                [object]::ReferenceEquals($reimportedProbe, $probe) | Should -BeFalse
                $second = Register-TestIdentityProbe

                [object]::ReferenceEquals($second.ScriptBlock, $first.ScriptBlock) | Should -BeFalse -Because 'the new instance of the module holds its own state'
                [object]::ReferenceEquals($second.ScriptBlock.Module, $reimportedProbe) | Should -BeTrue
                [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $second.ScriptBlock) | Should -BeTrue
                Get-TestIdentityState -CompleterType Parameter | Should -Be @('Parameter/Active/$script:value')
                Get-TestIdentityCompletion | Should -Be @('beta') -Because 'completion runs in the module that is loaded now'

                {
                    Register-TestIdentityProbeClosure
                } | Should -Throw '*already exists*Use -Force*' -Because 'a closure is bound to a module of its own'
            }
            finally
            {
                Remove-Module -Name 'TestIdentityProbe' -Force -ErrorAction SilentlyContinue
            }

            Get-TestIdentityCompletion | Should -Be @('beta')
        }

        It 'replaces the managed record without -Force when the module is imported again with the same arguments' {
            $modulePath = Join-Path -Path $TestDrive -ChildPath 'TestIdentitySameArgument.psm1'
            Set-Content -LiteralPath $modulePath -Encoding utf8 -Value @'
param(
    [string] $Value
)

$script:value = $Value

function Register-TestIdentitySameArgument
{
    Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { $script:value } -PassThru
}
'@

            try
            {
                $probe = Import-Module -Name $modulePath -ArgumentList 'alpha' -Force -PassThru
                $first = Register-TestIdentitySameArgument

                $reimportedProbe = Import-Module -Name $modulePath -ArgumentList 'alpha' -Force -PassThru
                [object]::ReferenceEquals($reimportedProbe, $probe) | Should -BeFalse
                $second = Register-TestIdentitySameArgument

                [object]::ReferenceEquals($second.ScriptBlock, $first.ScriptBlock) | Should -BeFalse -Because 'the owner ruling has a new instance replace the record, not reuse it, even with the same arguments'
                [object]::ReferenceEquals($second.ScriptBlock.Module, $reimportedProbe) | Should -BeTrue
                [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $second.ScriptBlock) | Should -BeTrue -Because 'the runtime block is the new instance''s'
                Get-TestIdentityState -CompleterType Parameter | Should -Be @('Parameter/Active/$script:value')
                Get-TestIdentityCompletion | Should -Be @('alpha')
                [object]::ReferenceEquals((Register-TestIdentitySameArgument).ScriptBlock, $second.ScriptBlock) | Should -BeTrue -Because 'the instance that owns the record registering again is a no-op'
            }
            finally
            {
                Remove-Module -Name 'TestIdentitySameArgument' -Force -ErrorAction SilentlyContinue
            }
        }

        It 'replaces the record of an earlier instance of a module with the same name, and refuses equal text from a module with another name' {
            $makerBody = {
                param(
                    [string] $Value
                )

                $script:value = $Value

                function Get-TestIdentityBlock { { $script:value } }
                Export-ModuleMember
            }

            $firstMaker = New-Module -Name 'TestIdentityMakerA' -ScriptBlock $makerBody -ArgumentList 'alpha'
            $againMaker = New-Module -Name 'TestIdentityMakerA' -ScriptBlock $makerBody -ArgumentList 'beta'
            $otherMaker = New-Module -Name 'TestIdentityMakerB' -ScriptBlock $makerBody -ArgumentList 'gamma'
            $first = & $firstMaker { Get-TestIdentityBlock }
            $again = & $againMaker { Get-TestIdentityBlock }
            $other = & $otherMaker { Get-TestIdentityBlock }
            $again.File | Should -BeExactly $first.File
            $other.File | Should -BeExactly $first.File

            $record = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first -PassThru
            Get-TestIdentityCompletion | Should -Be @('alpha')

            $replaced = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $again -PassThru

            [object]::ReferenceEquals($replaced.ScriptBlock, $record.ScriptBlock) | Should -BeFalse -Because 'the block of the other instance would run with that instance''s state'
            [object]::ReferenceEquals((Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name').ScriptBlock, $again) | Should -BeTrue
            Get-TestIdentityState -CompleterType Parameter | Should -Be @('Parameter/Active/$script:value')
            Get-TestIdentityCompletion | Should -Be @('beta')

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $other
            } | Should -Throw '*already exists*Use -Force*'

            Get-TestIdentityCompletion | Should -Be @('beta')
        }

        # Safety guard: these pin the limits of the owner-ruled replacement by a new module
        # instance, so they pass before and after it; the text case fails if the rule stops
        # comparing the script block's text.
        It 'still needs -Force for a block from a new instance of a module with the same name that differs in <Difference>' -ForEach @(
            @{ Difference = 'text' }
            @{ Difference = 'ScriptPath' }
            @{ Difference = 'tier' }
        ) {
            $makerBody = {
                param(
                    [string] $Value
                )

                $script:value = $Value

                function Get-TestIdentityBlock { { $script:value } }
                function Get-TestIdentityChangedBlock { { "changed $script:value" } }
                Export-ModuleMember
            }

            $firstMaker = New-Module -Name 'TestIdentityMakerC' -ScriptBlock $makerBody -ArgumentList 'alpha'
            $againMaker = New-Module -Name 'TestIdentityMakerC' -ScriptBlock $makerBody -ArgumentList 'beta'
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock (& $firstMaker { Get-TestIdentityBlock })

            $candidate = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; ScriptBlock = (& $againMaker { Get-TestIdentityBlock }) }

            switch ($Difference)
            {
                'text' { $candidate.ScriptBlock = & $againMaker { Get-TestIdentityChangedBlock } }
                'ScriptPath' { $candidate | Add-Member -NotePropertyName 'ScriptPath' -NotePropertyValue (Join-Path -Path $TestDrive -ChildPath 'identity-claimed.ps1') }
                'tier' { $candidate | Add-Member -NotePropertyName 'Trusted' -NotePropertyValue $true }
            }

            [object]::ReferenceEquals($candidate.ScriptBlock.Module, $againMaker) | Should -BeTrue

            { $candidate | Register-Completer } | Should -Throw '*already exists*Use -Force*'
            Get-TestIdentityCompletion | Should -Be @('alpha') -Because 'the record of the first instance stays in place'
        }

        # Safety guard: pins that the file defining the block bounds the owner-ruled
        # replacement by a new module instance, so it passes before and after that rule.
        It 'still needs -Force for a block from a module with the same name that is defined in another file' {
            $makerText = "New-Module -Name 'TestIdentityMakerD' -ScriptBlock { function Get-TestIdentityBlock { { 'same' } }; Export-ModuleMember }"
            $firstPath = Join-Path -Path $TestDrive -ChildPath 'identity-maker-first.ps1'
            $otherPath = Join-Path -Path $TestDrive -ChildPath 'identity-maker-other.ps1'
            Set-Content -LiteralPath $firstPath -Value $makerText -Encoding utf8
            Set-Content -LiteralPath $otherPath -Value $makerText -Encoding utf8
            $first = & (& $firstPath) { Get-TestIdentityBlock }
            $other = & (& $otherPath) { Get-TestIdentityBlock }
            $other.Module.Name | Should -BeExactly $first.Module.Name
            $other.ToString() | Should -BeExactly $first.ToString()
            $other.File | Should -Not -Be $first.File

            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $other
            } | Should -Throw '*already exists*Use -Force*'
        }

        # Safety guard: pins the documented precondition that the owner-ruled replacement
        # by a new module instance applies only to a live record, so it passes before and
        # after the help states it.
        It 'still needs -Force for a block from a new instance of a module with the same name over a stale record' {
            $makerBody = {
                param(
                    [string] $Value
                )

                $script:value = $Value

                function Get-TestIdentityBlock { { $script:value } }
                Export-ModuleMember
            }

            $first = & (New-Module -Name 'TestIdentityMakerE' -ScriptBlock $makerBody -ArgumentList 'alpha') { Get-TestIdentityBlock }
            $again = & (New-Module -Name 'TestIdentityMakerE' -ScriptBlock $makerBody -ArgumentList 'beta') { Get-TestIdentityBlock }
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $first
            Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'outside' }

            {
                Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $again
            } | Should -Throw '*is stale*Use -Force*'
            Get-TestIdentityCompletion | Should -Be @('outside')

            $forced = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock $again -Force -PassThru
            [object]::ReferenceEquals($forced.ScriptBlock, $again) | Should -BeTrue
            Get-TestIdentityCompletion | Should -Be @('beta')
        }
    }

    Context 'kind and tier written as text' {
        It 'reads IsNative from a record exported with Export-Csv and acts on that kind only' {
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }
            $null = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-result' }
            $csvPath = Join-Path -Path $TestDrive -ChildPath 'identity.csv'
            Get-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' | Export-Csv -LiteralPath $csvPath
            $row = Import-Csv -LiteralPath $csvPath

            $row.IsNative | Should -BeExactly 'False'
            @($row | Get-Completer | ForEach-Object { [string] $_.CompleterType }) | Should -Be @('Parameter')

            $removed = $row | Unregister-Completer -Confirm:$false -PassThru

            $removed.CompleterType | Should -Be 'Parameter'
            Get-TestIdentityState -CompleterType Parameter | Should -BeNullOrEmpty
            Get-TestIdentityState -CompleterType Native | Should -Be @("Native/Active/'native-result'")
        }

        It 'reads Trusted written as text and rejects text that is not a Boolean' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-text.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value "Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'from-row' }"

            $strict = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = 'false'; ScriptBlock = { 'from-row' }; ScriptPath = $scriptPath; Trusted = 'FALSE' } |
                Register-Completer -PassThru
            $strict.CompleterType | Should -Be 'Parameter'
            $strict.Trusted | Should -BeFalse

            $trusted = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = 'False'; ScriptBlock = { 'from-row' }; ScriptPath = $scriptPath; Trusted = ' True ' } |
                Register-Completer -Force -PassThru
            $trusted.Trusted | Should -BeTrue

            $empty = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = ''; ScriptBlock = { 'from-row' }; Trusted = '' } |
                Register-Completer -Force -PassThru
            $empty.CompleterType | Should -Be 'Parameter' -Because 'empty text counts as False'
            $empty.Trusted | Should -BeFalse

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = 'no' } | Get-Completer
            } | Should -Throw "*'no' for IsNative, which is not a Boolean value*"

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = { 'from-row' }; Trusted = 'yes' } | Register-Completer -Force
            } | Should -Throw "*'yes' for Trusted, which is not a Boolean value*"

            Get-TestIdentityState -CompleterType Native | Should -BeNullOrEmpty
        }

        It 'exports the tier a record exported with Export-Csv was written with, and rejects text that is not a Boolean' {
            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-export.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value "Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'from-set' }"
            $csvPath = Join-Path -Path $TestDrive -ChildPath 'identity-export.csv'
            Import-CompleterScript -LiteralPath $scriptPath | Select-Object -Property CommandName, ParameterName, IsNative, SourcePath, Trusted | Export-Csv -LiteralPath $csvPath
            $row = Import-Csv -LiteralPath $csvPath
            $row.Trusted | Should -BeExactly 'False'

            $strictSetPath = Join-Path -Path $TestDrive -ChildPath 'identity-strict.psd1'
            $row | Export-CompleterSet -Path $strictSetPath
            $strictEntry = (Import-PowerShellDataFile -LiteralPath $strictSetPath).Entries[0]
            $strictEntry.Trusted | Should -BeExactly $false -Because "the text 'False' is the strict tier"
            @($strictEntry.Targets | ForEach-Object { '{0}/{1}' -f $_.CommandName, $_.ParameterName }) | Should -Be @('Test-IdentityTool/Name')

            $trustedSetPath = Join-Path -Path $TestDrive -ChildPath 'identity-trusted.psd1'
            [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = 'False'; SourcePath = $scriptPath; Trusted = 'true' } | Export-CompleterSet -Path $trustedSetPath
            (Import-PowerShellDataFile -LiteralPath $trustedSetPath).Entries[0].Trusted | Should -BeExactly $true

            $badSetPath = Join-Path -Path $TestDrive -ChildPath 'identity-bad.psd1'
            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; SourcePath = $scriptPath; Trusted = 'nope' } | Export-CompleterSet -Path $badSetPath
            } | Should -Throw "*'nope' for Trusted, which is not a Boolean value*"
            Test-Path -LiteralPath $badSetPath | Should -BeFalse
        }

        It 'reads True or False with white space around it and counts white-space text as False' {
            $null = Register-Completer -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'parameter-result' }
            $null = Register-Completer -CommandName 'Test-IdentityTool:Name' -Native -ScriptBlock { 'native-result' }

            @([pscustomobject] @{ CommandName = 'Test-IdentityTool:Name'; IsNative = " True`t" } | Get-Completer | ForEach-Object { [string] $_.CompleterType }) |
                Should -Be @('Native')
            @([pscustomobject] @{ RuntimeKey = 'Test-IdentityTool:Name'; IsNative = ' false ' } | Get-Completer | ForEach-Object { [string] $_.CompleterType }) |
                Should -Be @('Parameter')
            @([pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; Native = " `t " } | Get-Completer | ForEach-Object { [string] $_.CompleterType }) |
                Should -Be @('Parameter') -Because 'text that is only white space counts as False'

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = ' yes ' } | Get-Completer
            } | Should -Throw "*' yes ' for IsNative, which is not a Boolean value*"
        }

        It 'rejects a collection or another kind of object for the kind or tier and registers nothing' {
            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; Native = @($false, $false); ScriptBlock = { 'from-row' }; Trusted = @($false, $false) } |
                    Register-Completer
            } | Should -Throw '*a collection for Native, which takes a single Boolean value*'

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; ScriptBlock = { 'from-row' }; Trusted = @($false) } |
                    Register-Completer
            } | Should -Throw '*a collection for Trusted, which takes a single Boolean value*'

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool:Name'; IsNative = [pscustomobject] @{ Value = $false } } | Get-Completer
            } | Should -Throw '*type System.Management.Automation.PSCustomObject for IsNative, which is not a Boolean value*'

            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; Native = [System.Int128]::Zero } | Get-Completer
            } | Should -Throw '*type System.Int128 for Native, which is not a Boolean value*' -Because 'a cast to Boolean reads an Int128 zero as True'

            Get-TestIdentityState -CompleterType Parameter | Should -BeNullOrEmpty
            Get-TestIdentityState -CompleterType Native | Should -BeNullOrEmpty

            $scriptPath = Join-Path -Path $TestDrive -ChildPath 'identity-collection.ps1'
            Set-Content -LiteralPath $scriptPath -Encoding utf8 -Value "Register-ArgumentCompleter -CommandName 'Test-IdentityTool' -ParameterName 'Name' -ScriptBlock { 'from-set' }"
            $setPath = Join-Path -Path $TestDrive -ChildPath 'identity-collection.psd1'
            {
                [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = $false; SourcePath = $scriptPath; Trusted = @($false, $false) } | Export-CompleterSet -Path $setPath
            } | Should -Throw '*a collection for Trusted, which takes a single Boolean value*'
            Test-Path -LiteralPath $setPath | Should -BeFalse
        }

        It 'reads a Boolean, switch, number, or null for the kind and tier' {
            $parameter = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; Native = 0; ScriptBlock = { 'from-row' }; Trusted = $null } |
                Register-Completer -PassThru
            $parameter.CompleterType | Should -Be 'Parameter'
            $parameter.Trusted | Should -BeFalse

            $trusted = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; IsNative = [switch]::new($false); ScriptBlock = { 'from-row' }; Trusted = 1 } |
                Register-Completer -Force -PassThru
            $trusted.CompleterType | Should -Be 'Parameter'
            $trusted.Trusted | Should -BeTrue

            $native = [pscustomobject] @{ CommandName = 'Test-IdentityTool:Name'; Native = [switch]::new($true); ScriptBlock = { 'native-result' }; Trusted = $false } |
                Register-Completer -PassThru
            $native.CompleterType | Should -Be 'Native'
            $native.Trusted | Should -BeFalse

            $bigParameter = [pscustomobject] @{ CommandName = 'Test-IdentityTool'; ParameterName = 'Name'; Native = 0n; ScriptBlock = { 'from-row' }; Trusted = 1n } |
                Register-Completer -Force -PassThru
            $bigParameter.CompleterType | Should -Be 'Parameter' -Because 'a BigInteger zero is False'
            $bigParameter.Trusted | Should -BeTrue

            $bigNative = [pscustomobject] @{ CommandName = 'Test-IdentityTool:Name'; Native = 1n; ScriptBlock = { 'native-result' }; Trusted = 0n } |
                Register-Completer -Force -PassThru
            $bigNative.CompleterType | Should -Be 'Native'
            $bigNative.Trusted | Should -BeFalse
        }
    }
}

Describe 'Startup benchmark tool' {
    # Code points keep this file ASCII. Each typographic quote alone, and all five together, must
    # come back unchanged from the child script's literals.
    It 'writes child scripts that parse back to paths holding <Name>' -ForEach @(
        @{ Name = 'U+2018'; Codes = @(0x2018) }
        @{ Name = 'U+2019'; Codes = @(0x2019) }
        @{ Name = 'U+201A'; Codes = @(0x201A) }
        @{ Name = 'U+201B'; Codes = @(0x201B) }
        @{ Name = 'every single-quote character the tokenizer accepts'; Codes = @(0x0027, 0x2018, 0x2019, 0x201A, 0x201B) }
    ) {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $toolPath = Join-Path -Path $repoRoot -ChildPath 'tools' -AdditionalChildPath 'Measure-CompleterStartup.ps1'

        # The tool dot-sources the module's quoting helper; load it the same way, then
        # define the tool's own quoting and child-script helpers from its source.
        . (Join-Path -Path $repoRoot -ChildPath 'src' -AdditionalChildPath 'Private', 'ConvertTo-CompleterSingleQuotedText.ps1')
        $toolAst = [System.Management.Automation.Language.Parser]::ParseFile($toolPath, [ref] $null, [ref] $null)
        $helpers = @($toolAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in 'ConvertTo-SingleQuoted', 'ConvertTo-TimedScript' }, $false))
        $helpers.Count | Should -Be 2

        foreach ($helper in $helpers)
        {
            . ([scriptblock]::Create($helper.Extent.Text))
        }

        $quotes = -join @($Codes | ForEach-Object { [char] $_ })
        $modulePath = Join-Path -Path $TestDrive -ChildPath "module $quotes" -AdditionalChildPath 'CompleterActions.psd1'
        $setPath = Join-Path -Path $TestDrive -ChildPath "set $quotes" -AdditionalChildPath 'startup.psd1'

        $childScript = ConvertTo-TimedScript -Module $modulePath -Body "Import-CompleterSet -LiteralPath $(ConvertTo-SingleQuoted -Value $setPath) -Force | Out-Null"

        $parseErrors = $null
        $childAst = [System.Management.Automation.Language.Parser]::ParseInput($childScript, [ref] $null, [ref] $parseErrors)

        $parseErrors | Should -BeNullOrEmpty
        $commands = @($childAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in 'Import-Module', 'Import-CompleterSet' }, $true))
        @($commands | ForEach-Object { $_.CommandElements[2].Value }) | Should -BeExactly @($modulePath, $setPath)
    }
}
