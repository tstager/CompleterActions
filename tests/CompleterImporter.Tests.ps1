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
            @{ CommandName = 'Test-ImportedArrayOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayOne'; ParameterName = 'Path'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayTwo'; ParameterName = 'Path'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' },
            @{ CommandName = 'locationfixture'; CompleterType = 'Native' },
            @{ CommandName = 'namespacefixture'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedTwo' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedArrayOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedArrayTwo' -ErrorAction SilentlyContinue

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

        function Test-ImportedArrayOne
        {
            [CmdletBinding()]
            param(
                [string] $Name,
                [string] $Path
            )
        }

        function Test-ImportedArrayTwo
        {
            [CmdletBinding()]
            param(
                [string] $Name,
                [string] $Path
            )
        }
    }

    AfterEach {
        foreach ($cleanupTarget in @(
            @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayOne'; ParameterName = 'Path'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
            @{ CommandName = 'Test-ImportedArrayTwo'; ParameterName = 'Path'; CompleterType = 'Parameter' },
            @{ CommandName = 'importfixture'; CompleterType = 'Native' },
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' },
            @{ CommandName = 'locationfixture'; CompleterType = 'Native' },
            @{ CommandName = 'namespacefixture'; CompleterType = 'Native' }
        ))
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedTwo' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedArrayOne' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\Test-ImportedArrayTwo' -ErrorAction SilentlyContinue

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'keeps the script location on the imported block so $PSScriptRoot and $PSCommandPath resolve (<Name>)' -TestCases @(
        @{ Name = 'strict'; Trusted = $false; Lazy = $false },
        @{ Name = 'trusted'; Trusted = $true; Lazy = $false },
        @{ Name = 'lazy'; Trusted = $false; Lazy = $true }
    ) {
        param(
            [bool] $Trusted,
            [bool] $Lazy
        )

        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ScriptLocationCompleter.ps1'
        $inputScript = 'locationfixture '

        . $fixturePath
        $direct = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($direct.CompletionMatches.CompletionText) | Should -Be @($script:CompleterImporterFixtureRoot, $fixturePath) -Because 'the dot-sourced script is the baseline'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'locationfixture' -CompleterType 'Native'

        if ($Lazy)
        {
            $null = Register-Completer -LiteralPath $fixturePath -Lazy
        }
        else
        {
            $imported = @(Import-CompleterScript -LiteralPath $fixturePath -Trusted:$Trusted)

            $imported.Count | Should -Be 1
            $imported[0].ScriptBlock.File | Should -Be $fixturePath
            $imported[0].ScriptBlock.Module | Should -Not -BeNullOrEmpty
            @(& $imported[0].ScriptBlock '' $null 0 | ForEach-Object { $_.CompletionText }) | Should -Be @($script:CompleterImporterFixtureRoot, $fixturePath)

            $null = $imported | Register-Completer
        }

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Be @($script:CompleterImporterFixtureRoot, $fixturePath)

        $record = Get-Completer -CommandName 'locationfixture' -Native
        $record.State | Should -Be 'Active'
        $record.ScriptBlock.File | Should -Be $fixturePath
        $record.ScriptBlock.Module | Should -Not -BeNullOrEmpty
        $record.Trusted | Should -Be $Trusted

        @(Test-CompleterRegistration -CommandName 'locationfixture' -Native -InputText $inputScript | ForEach-Object { $_.CompletionText }) | Should -Be @($script:CompleterImporterFixtureRoot, $fixturePath)
    }

    It 'resolves the types a top-level using namespace statement names inside the imported block (<Name>)' -TestCases @(
        @{ Name = 'strict'; Trusted = $false; Lazy = $false },
        @{ Name = 'trusted'; Trusted = $true; Lazy = $false },
        @{ Name = 'lazy'; Trusted = $false; Lazy = $true }
    ) {
        param(
            [bool] $Trusted,
            [bool] $Lazy
        )

        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'UsingNamespaceCompleter.ps1'
        $inputScript = 'namespacefixture ns-'
        $expected = @('ns-alpha', 'ns-beta')

        . $fixturePath
        $direct = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($direct.CompletionMatches.CompletionText) | Should -Be $expected -Because 'the dot-sourced script is the baseline'
        Invoke-TestRuntimeCompleterCleanup -CommandName 'namespacefixture' -CompleterType 'Native'
        Remove-Item -Path 'Function:\Get-UsingNamespaceCompletionValue' -ErrorAction SilentlyContinue

        if ($Lazy)
        {
            $null = Register-Completer -LiteralPath $fixturePath -Lazy
        }
        else
        {
            $imported = @(Import-CompleterScript -LiteralPath $fixturePath -Trusted:$Trusted)

            $imported.Count | Should -Be 1
            $imported[0].ScriptBlock.File | Should -Be $fixturePath
            @(& $imported[0].ScriptBlock 'ns-' $null 0 | ForEach-Object { $_.CompletionText }) | Should -Be $expected

            $null = $imported | Register-Completer
        }

        Get-Command -Name 'Get-UsingNamespaceCompletionValue' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty -Because 'the helper lives in the capture module, not the caller scope'

        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        @($completion.CompletionMatches.CompletionText) | Should -Be $expected

        $record = Get-Completer -CommandName 'namespacefixture' -Native
        $record.State | Should -Be 'Active'
        $record.Trusted | Should -Be $Trusted

        @(Test-CompleterRegistration -CommandName 'namespacefixture' -Native -InputText $inputScript | ForEach-Object { $_.CompletionText }) | Should -Be $expected
    }

    It 'returns objects with the shape Register-Completer expects' {
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

    It 'pipes importer output into Register-Completer and supports get and unregister' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ParameterCompleter.ps1'

        $registered = @(Import-CompleterScript -Path $fixturePath | Register-Completer -PassThru)

        $registered.Count | Should -Be 1
        $registered[0].Source | Should -Be 'Managed'
        $registered[0].Key | Should -Be 'test-importedfixturetool:name'

        $inputScript = 'Test-ImportedFixtureTool -Name imported'
        $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'imported-alpha'

        $resolved = Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
        $resolved.Source | Should -Be 'Managed'
        $resolved.Key | Should -Be 'test-importedfixturetool:name'

        $removed = @(Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Unregister-Completer -Confirm:$false -PassThru)

        $removed.Count | Should -Be 1
        $removed[0].Key | Should -Be 'test-importedfixturetool:name'
        Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'handles multiple command names from one registration call' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'MultiCommandCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')

        $registered = @($imported | Register-Completer -PassThru)

        $registered.Count | Should -Be 2
        @($registered.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')

        $completionOneInput = 'Test-ImportedOne -Name imported'
        $completionOne = TabExpansion2 -InputScript $completionOneInput -CursorColumn $completionOneInput.Length
        $completionOne.CompletionMatches.CompletionText | Should -Contain 'imported-shared'

        $completionTwoInput = 'Test-ImportedTwo -Name imported'
        $completionTwo = TabExpansion2 -InputScript $completionTwoInput -CursorColumn $completionTwoInput.Length
        $completionTwo.CompletionMatches.CompletionText | Should -Contain 'imported-shared'
    }

    It 'imports literal array expression target metadata and registers every resolved target' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ArrayExpressionCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @(
            'test-importedarrayone:name',
            'test-importedarraytwo:path'
        )

        $registered = @($imported | Register-Completer -PassThru)

        $registered.Count | Should -Be 2
        @($registered.Key | Sort-Object) | Should -Be @(
            'test-importedarrayone:name',
            'test-importedarraytwo:path'
        )

        $nameInputScript = 'Test-ImportedArrayOne -Name array'
        $nameCompletion = TabExpansion2 -InputScript $nameInputScript -CursorColumn $nameInputScript.Length
        $nameCompletion.CompletionMatches.CompletionText | Should -Contain 'array-target'

        $pathInputScript = 'Test-ImportedArrayTwo -Path array'
        $pathCompletion = TabExpansion2 -InputScript $pathInputScript -CursorColumn $pathInputScript.Length
        $pathCompletion.CompletionMatches.CompletionText | Should -Contain 'array-target'
    }

    It 'imports native completer scripts that depend on helper functions and script scope' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
        @($imported.CompleterType | Select-Object -Unique) | Should -Be @('Native')

        $registered = @($imported | Register-Completer -PassThru)

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
            Path = 'DynamicArrayExpressionCommandName.ps1'
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

Describe 'Completer script importer top-level validation' {
    $adversarialImportCases = @(
        @{
            Name    = 'static method call'
            Message = '*unsupported top-level expression ''InvokeMemberExpressionAst''*'
            Script  = @'
[System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')

{Registration}
'@
        },
        @{
            Name    = 'instance method call'
            Message = '*unsupported top-level expression ''InvokeMemberExpressionAst''*'
            Script  = @'
$ExecutionContext.InvokeCommand.InvokeScript('$env:COMPLETERACTIONS_IMPORT_PROBE = ''executed''')

{Registration}
'@
        },
        @{
            Name    = 'subexpression'
            Message = '*unsupported top-level expression ''SubExpressionAst''*'
            Script  = @'
$(Set-Item -Path 'Env:COMPLETERACTIONS_IMPORT_PROBE' -Value 'executed')

{Registration}
'@
        },
        @{
            Name    = 'type conversion expression'
            Message = '*unsupported top-level expression ''ConvertExpressionAst''*'
            Script  = @'
[System.IO.StreamWriter] '{ProbePath}'

{Registration}
'@
        },
        @{
            Name    = 'top-level assignment'
            Message = '*uses a top-level assignment*'
            Script  = @'
$env:COMPLETERACTIONS_IMPORT_PROBE = 'executed'

{Registration}
'@
        },
        @{
            Name    = 'side effect inside an if condition'
            Message = '*unsupported top-level expression ''InvokeMemberExpressionAst''*'
            Script  = @'
if ($null -eq [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process'))
{
    {Registration}
}
'@
        },
        @{
            Name    = 'side effect inside an if body'
            Message = '*unsupported top-level expression ''InvokeMemberExpressionAst''*'
            Script  = @'
if ($null -eq (Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue))
{
    [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')
}

{Registration}
'@
        },
        @{
            Name    = 'drive-qualified assignment inside an if body'
            Message = '*assigns to unsupported target ''$env:COMPLETERACTIONS_IMPORT_PROBE''*'
            Script  = @'
if ($null -eq (Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue))
{
    $env:COMPLETERACTIONS_IMPORT_PROBE = 'executed'
}

{Registration}
'@
        },
        @{
            Name    = 'method call as an if body assignment value'
            Message = '*unsupported top-level expression ''InvokeMemberExpressionAst''*'
            Script  = @'
if ($null -eq (Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue))
{
    $script:ImportProbeState = [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')
}

{Registration}
'@
        },
        @{
            Name    = 'shadowed allow-listed command'
            Message = '*defines its own Get-Variable function*'
            Script  = @'
function Get-Variable
{
    [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')
}

if (-not (Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue))
{
    $script:ImportProbeState = @{}
}

{Registration}
'@
        },
        @{
            Name             = 'script-scoped shadow of an allow-listed command'
            Message          = '*defines its own script:Get-Variable function*'
            IsolateExecution = $true
            Script           = @'
function script:Get-Variable
{
    Set-Content -LiteralPath '{ProbePath}' -Value 'executed'
}

Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue

{Registration}
'@
        },
        @{
            Name             = 'local-scoped shadow of an allow-listed command'
            Message          = '*defines its own local:Get-Variable function*'
            IsolateExecution = $true
            Script           = @'
function local:Get-Variable
{
    Set-Content -LiteralPath '{ProbePath}' -Value 'executed'
}

Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue

{Registration}
'@
        },
        @{
            Name             = 'global-scoped shadow of an allow-listed command'
            Message          = '*defines its own global:Get-Variable function*'
            IsolateExecution = $true
            Script           = @'
function global:Get-Variable
{
    Set-Content -LiteralPath '{ProbePath}' -Value 'executed'
}

Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue

{Registration}
'@
        },
        @{
            Name    = 'redirection'
            Message = '*uses redirection*'
            Script  = @'
Get-Variable -Name 'PSScriptRoot' > '{ProbePath}'

{Registration}
'@
        },
        @{
            Name    = 'param block default value'
            Message = '*unsupported top-level syntax ''ParamBlockAst''*'
            Script  = @'
param(
    $ImportProbe = [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')
)

{Registration}
'@
        },
        @{
            Name    = 'begin block'
            Message = '*unsupported top-level syntax ''NamedBlockAst''*'
            Script  = @'
begin
{
    [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')
}

end
{
    {Registration}
}
'@
        },
        @{
            Name    = 'begin block without an end block'
            Message = '*unsupported top-level syntax ''NamedBlockAst''*'
            Script  = @'
begin
{
    [System.Environment]::SetEnvironmentVariable('COMPLETERACTIONS_IMPORT_PROBE', 'executed', 'Process')

    {Registration}
}
'@
        }
    )

    BeforeAll {
        $script:ProbeRegistration = @'
Register-ArgumentCompleter -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
}
'@

        function Write-AdversarialImportScript
        {
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter(Mandatory)]
                [string] $Script
            )

            $fileBaseName = $Name -replace '[^A-Za-z0-9]+', '-'
            $probePath = Join-Path -Path $TestDrive -ChildPath ('{0}.probe' -f $fileBaseName)
            $scriptPath = Join-Path -Path $TestDrive -ChildPath ('{0}.ps1' -f $fileBaseName)
            $content = $Script.Replace('{ProbePath}', $probePath).Replace('{Registration}', $script:ProbeRegistration)

            Set-Content -LiteralPath $scriptPath -Value $content -Encoding utf8

            [pscustomobject] @{
                ScriptPath = $scriptPath
                ProbePath  = $probePath
            }
        }

        function Test-ImportProbeFired
        {
            param(
                [Parameter(Mandatory)]
                [string] $ProbePath
            )

            return ($null -ne $env:COMPLETERACTIONS_IMPORT_PROBE) -or (Test-Path -LiteralPath $ProbePath)
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        $env:COMPLETERACTIONS_IMPORT_PROBE = $null
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' -CompleterType 'Parameter'

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
    }

    AfterEach {
        $env:COMPLETERACTIONS_IMPORT_PROBE = $null
        Invoke-TestRuntimeCompleterCleanup -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' -CompleterType 'Parameter'
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'rejects a <Name> before the script executes' -TestCases $adversarialImportCases {
        param(
            [string] $Name,
            [string] $Message,
            [string] $Script
        )

        $adversarial = Write-AdversarialImportScript -Name $Name -Script $Script

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse

        {
            Import-CompleterScript -LiteralPath $adversarial.ScriptPath
        } | Should -Throw $Message

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse
        Get-Completer -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'confirms the <Name> probe fires when the script runs without validation' -TestCases $adversarialImportCases {
        param(
            [string] $Name,
            [string] $Script,
            [bool] $IsolateExecution
        )

        $adversarial = Write-AdversarialImportScript -Name $Name -Script $Script

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse

        if ($IsolateExecution)
        {
            # A script- or global-scoped shadow of Get-Variable would outlive this
            # test and break every later Get-Variable call in the run, so the
            # unvalidated execution happens in a throwaway process. The probe is a
            # file marker for these cases so the effect is visible from here.
            $null = & pwsh -NoProfile -NonInteractive -Command ". '$($adversarial.ScriptPath)'" 2>&1
        }
        else
        {
            $output = @(& { . $adversarial.ScriptPath })
            foreach ($item in $output)
            {
                if ($item -is [System.IDisposable])
                {
                    $item.Dispose()
                }
            }
        }

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeTrue
    }

    Context 'helper definition scope' {
        BeforeEach {
            Remove-Item -LiteralPath 'Function:\Test-ImportProbeHelper' -ErrorAction SilentlyContinue
        }

        AfterEach {
            Remove-Item -LiteralPath 'Function:\Test-ImportProbeHelper' -ErrorAction SilentlyContinue
        }

        It 'rejects a <Name> and leaves the caller''s function table unchanged' -TestCases @(
            @{
                Name   = 'global-scoped helper definition'
                Script = @'
function global:Test-ImportProbeHelper
{
    'helper'
}

{Registration}
'@
            },
            @{
                Name   = 'GLOBAL-scoped (upper-case) helper definition'
                Script = @'
function GLOBAL:Test-ImportProbeHelper
{
    'helper'
}

{Registration}
'@
            },
            @{
                Name   = 'global-scoped helper definition inside an if body'
                Script = @'
if (-not (Get-Variable -Name 'ImportProbeState' -Scope Script -ErrorAction SilentlyContinue))
{
    function global:Test-ImportProbeHelper
    {
        'helper'
    }
}

{Registration}
'@
            }
        ) {
            param(
                [string] $Name,
                [string] $Script
            )

            $adversarial = Write-AdversarialImportScript -Name $Name -Script $Script

            $findings = @(Test-CompleterScript -LiteralPath $adversarial.ScriptPath)
            $findings.Count | Should -Be 1
            $findings[0].Construct | Should -Be 'FunctionDefinitionAst'
            $findings[0].Message | Should -BeLike '*defines function ''global:Test-ImportProbeHelper'' in the global scope*'

            {
                Import-CompleterScript -LiteralPath $adversarial.ScriptPath
            } | Should -Throw '*defines function ''global:Test-ImportProbeHelper'' in the global scope*'

            Test-Path -LiteralPath 'Function:\Test-ImportProbeHelper' | Should -BeFalse
            Get-Completer -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'confirms a global-scoped helper definition reaches the caller''s function table when the script runs without validation' {
            $adversarial = Write-AdversarialImportScript -Name 'global-scoped helper definition' -Script @'
function global:Test-ImportProbeHelper
{
    'helper'
}

{Registration}
'@

            $null = & { . $adversarial.ScriptPath }

            Test-Path -LiteralPath 'Function:\Test-ImportProbeHelper' | Should -BeTrue
        }

        It 'still imports <Name> helpers and keeps them inside the import scope' -TestCases @(
            @{ Name = 'unqualified'; Qualifier = '' },
            @{ Name = 'script-scoped'; Qualifier = 'script:' },
            @{ Name = 'local-scoped'; Qualifier = 'local:' },
            @{ Name = 'private-scoped'; Qualifier = 'private:' }
        ) {
            param(
                [string] $Name,
                [string] $Qualifier
            )

            $supported = Write-AdversarialImportScript -Name "$Name helper definition" -Script (
                "function $($Qualifier)Test-ImportProbeHelper`n{`n    'helper'`n}`n`n{Registration}"
            )

            Test-CompleterScript -LiteralPath $supported.ScriptPath | Should -BeNullOrEmpty

            $imported = @(Import-CompleterScript -LiteralPath $supported.ScriptPath)

            $imported.Count | Should -Be 1
            $imported[0].Key | Should -Be 'test-importprobetool:name'
            Test-Path -LiteralPath 'Function:\Test-ImportProbeHelper' | Should -BeFalse
            & (Get-Module -Name 'CompleterActions') {
                Get-Command -Name 'Test-ImportProbeHelper' -ErrorAction SilentlyContinue
            } | Should -BeNullOrEmpty
        }

        It 'keeps helpers and the capture shim from replacing module commands or disabling the strict gate' {
            $shadowing = Write-AdversarialImportScript -Name 'module command shadowing helpers' -Script @'
function Get-CompleterScriptFinding
{
}

{Registration}
'@
            $violating = Write-AdversarialImportScript -Name 'strict violation after shadowing' -Script @'
Set-Content -LiteralPath '{ProbePath}' -Value 'ran'

{Registration}
'@
            $module = Get-Module -Name 'CompleterActions'
            $findingDefinition = & $module { (Get-Command -Name 'Get-CompleterScriptFinding' -CommandType Function).Definition }

            Test-CompleterScript -LiteralPath $shadowing.ScriptPath | Should -BeNullOrEmpty
            @(Import-CompleterScript -LiteralPath $shadowing.ScriptPath).Count | Should -Be 1

            & $module { (Get-Command -Name 'Get-CompleterScriptFinding' -CommandType Function).Definition } | Should -BeExactly $findingDefinition
            & $module { (Get-Command -Name 'Register-ArgumentCompleter').CommandType } | Should -Be 'Cmdlet'

            {
                Import-CompleterScript -LiteralPath $violating.ScriptPath
            } | Should -Throw '*does not conform to the strict import grammar*'
            Test-ImportProbeFired -ProbePath $violating.ProbePath | Should -BeFalse
        }
    }

    It 'still imports the guarded script-state initialization shape' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $imported = @(Import-CompleterScript -LiteralPath $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
    }

    Context 'script requirements' {
        BeforeEach {
            $script:RequiresProbeModulePath = Join-Path -Path $TestDrive -ChildPath 'CompleterActionsRequiresProbe.psm1'
            Set-Content -LiteralPath $script:RequiresProbeModulePath -Value '$env:COMPLETERACTIONS_IMPORT_PROBE = ''executed''' -Encoding utf8
        }

        AfterEach {
            Remove-Module -Name 'CompleterActionsRequiresProbe' -Force -ErrorAction SilentlyContinue
        }

        It 'rejects a #requires -Modules directive before the required module executes' {
            $adversarial = Write-AdversarialImportScript -Name 'requires modules directive' -Script (
                "#requires -Modules '{0}'`n`n{{Registration}}" -f $script:RequiresProbeModulePath
            )

            Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse

            {
                Import-CompleterScript -LiteralPath $adversarial.ScriptPath
            } | Should -Throw '*uses a ''#requires -Modules'' directive*'

            Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse
            Get-Module -Name 'CompleterActionsRequiresProbe' | Should -BeNullOrEmpty
            Get-Completer -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'confirms the #requires -Modules probe fires when the script runs without validation' {
            $adversarial = Write-AdversarialImportScript -Name 'requires modules directive' -Script (
                "#requires -Modules '{0}'`n`n{{Registration}}" -f $script:RequiresProbeModulePath
            )

            Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse

            $null = @(& { . $adversarial.ScriptPath })

            Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeTrue
        }

        It 'rejects a #requires -Assembly directive' {
            $adversarial = Write-AdversarialImportScript -Name 'requires assembly directive' -Script (
                "#requires -Assembly '{0}'`n`n{{Registration}}" -f (Join-Path -Path $TestDrive -ChildPath 'CompleterActionsRequiresProbe.dll')
            )

            {
                Import-CompleterScript -LiteralPath $adversarial.ScriptPath
            } | Should -Throw '*uses a ''#requires -Assembly'' directive*'
        }

        It 'still imports a script with a #requires -Version directive' {
            $supported = Write-AdversarialImportScript -Name 'requires version directive' -Script "#requires -Version 7.0`n`n{Registration}"

            $imported = @(Import-CompleterScript -LiteralPath $supported.ScriptPath)

            $imported.Count | Should -Be 1
            $imported[0].Key | Should -Be 'test-importprobetool:name'
        }
    }
}

Describe 'Completer script importer literal target arrays' {
    # Each target array is an array expression whose pipeline does more than yield its strings.
    # The strict grammar must refuse it before the capture module runs the script.
    $literalTargetArrayCases = @(
        @{
            Name         = 'native target that redirects the error stream to a file'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('importarraytarget' 2> '{MarkerPath}') -ScriptBlock { 'ok' }"
            WritesMarker = $true
        },
        @{
            Name         = 'native target array that redirects the success stream to a file'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('importarraytarget', 'importarraytarget.exe' > '{MarkerPath}') -ScriptBlock { 'ok' }"
            WritesMarker = $true
        },
        @{
            Name         = 'colon-bound native target that redirects to a file'
            Registration = "Register-ArgumentCompleter -Native -CommandName:@('importarraytarget' 2> '{MarkerPath}') -ScriptBlock { 'ok' }"
            WritesMarker = $true
        },
        @{
            Name         = 'parameter command target that redirects every stream to a file'
            Registration = "Register-ArgumentCompleter -CommandName @('Test-ImportArrayTargetTool' *> '{MarkerPath}') -ParameterName 'Name' -ScriptBlock { 'ok' }"
            WritesMarker = $true
        },
        @{
            Name         = 'parameter name that appends to a file'
            Registration = "Register-ArgumentCompleter -CommandName 'Test-ImportArrayTargetTool' -ParameterName @('Name' >> '{MarkerPath}') -ScriptBlock { 'ok' }"
            WritesMarker = $true
        },
        @{
            Name         = 'native target in a background pipeline'
            Registration = "Register-ArgumentCompleter -Native -CommandName @('importarraytarget' &) -ScriptBlock { 'ok' }"
            WritesMarker = $false
        }
    )

    BeforeAll {
        $script:LiteralTargetArrayMarkerBytes = [System.Text.Encoding]::UTF8.GetBytes('CompleterActions disposable marker')

        function Write-LiteralTargetArrayScript
        {
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter(Mandatory)]
                [string] $Registration
            )

            $fileBaseName = $Name -replace '[^A-Za-z0-9]+', '-'
            $markerPath = Join-Path -Path $TestDrive -ChildPath ('{0}.marker' -f $fileBaseName)
            $scriptPath = Join-Path -Path $TestDrive -ChildPath ('{0}_completer.ps1' -f $fileBaseName)
            $escapedMarkerPath = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($markerPath)

            [System.IO.File]::WriteAllBytes($markerPath, $script:LiteralTargetArrayMarkerBytes)
            Set-Content -LiteralPath $scriptPath -Value $Registration.Replace('{MarkerPath}', $escapedMarkerPath) -Encoding utf8

            [pscustomobject] @{
                ScriptPath = $scriptPath
                MarkerPath = $markerPath
            }
        }

        function Get-LiteralTargetArrayMarker
        {
            param(
                [Parameter(Mandatory)]
                [string] $MarkerPath
            )

            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($MarkerPath))
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null
        $script:LiteralTargetArrayJobIds = @(Get-Job | ForEach-Object -MemberName Id)
    }

    AfterEach {
        Get-Job | Where-Object -Property Id -NotIn -Value $script:LiteralTargetArrayJobIds | Remove-Job -Force
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'refuses a <Name> and leaves the marker byte-identical' -TestCases $literalTargetArrayCases {
        param(
            [string] $Name,
            [string] $Registration
        )

        $fixture = Write-LiteralTargetArrayScript -Name $Name -Registration $Registration
        $markerBefore = Get-LiteralTargetArrayMarker -MarkerPath $fixture.MarkerPath

        {
            Import-CompleterScript -LiteralPath $fixture.ScriptPath
        } | Should -Throw '*does not conform to the strict import grammar*'

        Get-LiteralTargetArrayMarker -MarkerPath $fixture.MarkerPath | Should -Be $markerBefore
        @(Get-Job | Where-Object -Property Id -NotIn -Value $script:LiteralTargetArrayJobIds) | Should -BeNullOrEmpty
        Get-Completer -CommandName 'importarraytarget', 'importarraytarget.exe' -Native | Should -BeNullOrEmpty
        Get-Completer -CommandName 'Test-ImportArrayTargetTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'confirms the <Name> marker changes when the script runs without validation' -TestCases $literalTargetArrayCases.Where({ $_.WritesMarker }) {
        param(
            [string] $Name,
            [string] $Registration
        )

        $fixture = Write-LiteralTargetArrayScript -Name $Name -Registration $Registration
        $markerBefore = Get-LiteralTargetArrayMarker -MarkerPath $fixture.MarkerPath

        # The unvalidated run happens in a throwaway process so its registration and
        # binding errors stay out of this one.
        $null = & ([System.Environment]::ProcessPath) -NoProfile -NonInteractive -File $fixture.ScriptPath 2>&1

        Get-LiteralTargetArrayMarker -MarkerPath $fixture.MarkerPath | Should -Not -Be $markerBefore
    }
}
