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
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
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
            @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
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

    It 'imports literal array expression target metadata and registers every resolved target' {
        $fixturePath = Join-Path -Path $script:CompleterImporterFixtureRoot -ChildPath 'ArrayExpressionCompleter.ps1'

        $imported = @(Import-CompleterScript -Path $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @(
            'test-importedarrayone:name',
            'test-importedarraytwo:path'
        )

        $registered = @($imported | Register-CompleterRegistration -PassThru)

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
        Get-CompleterRegistration -CommandName 'Test-ImportProbeTool' -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'confirms the <Name> probe fires when the script runs without validation' -TestCases $adversarialImportCases {
        param(
            [string] $Name,
            [string] $Script
        )

        $adversarial = Write-AdversarialImportScript -Name $Name -Script $Script

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeFalse

        $output = @(& { . $adversarial.ScriptPath })
        foreach ($item in $output)
        {
            if ($item -is [System.IDisposable])
            {
                $item.Dispose()
            }
        }

        Test-ImportProbeFired -ProbePath $adversarial.ProbePath | Should -BeTrue
    }

    It 'still imports the guarded script-state initialization shape' {
        $fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\ImportableNativeCompleter.ps1'

        $imported = @(Import-CompleterScript -LiteralPath $fixturePath)

        $imported.Count | Should -Be 2
        @($imported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
    }
}
