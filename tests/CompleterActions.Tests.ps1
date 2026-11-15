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

        $first = Get-Completer -CommandName 'Test-ArrayTwo' -ParameterName 'Path' -State Active
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
