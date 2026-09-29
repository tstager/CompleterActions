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

    function Get-TestManagedRegistration
    {
        param(
            [Parameter(Mandatory)]
            [string] $Key
        )

        & (Get-Module -Name 'CompleterActions') {
            param($ManagedLookupKey)

            Find-ManagedCompleterRegistration -Key $ManagedLookupKey
        } $Key
    }

    function Write-TestResetScript
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string[]] $CommandName,

            [Parameter(Mandatory)]
            [string[]] $Value,

            # Adds a top-level command that the strict import grammar rejects and
            # the trusted tier runs, so a strict load of the script fails.
            [Parameter()]
            [switch] $NonStrict
        )

        $names = ($CommandName | ForEach-Object { "'$_'" }) -join ', '
        $values = ($Value | ForEach-Object { "'$_'" }) -join ', '
        $content = @"
Register-ArgumentCompleter -Native -CommandName $names -ScriptBlock {
    param(`$wordToComplete, `$commandAst, `$cursorPosition)

    `$null = `$commandAst, `$cursorPosition

    foreach (`$value in $values)
    {
        if (`$value -like "`$wordToComplete*")
        {
            [System.Management.Automation.CompletionResult]::new(`$value, `$value, 'ParameterValue', `$value)
        }
    }
}
"@

        if ($NonStrict)
        {
            $content = 'Get-Date | Out-Null' + [Environment]::NewLine + $content
        }

        $null = New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force
        Set-Content -LiteralPath $Path -Value $content -Encoding utf8
    }

    function Write-TestResetSet
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [hashtable[]] $Entry
        )

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('@{')
        $lines.Add('    Version = 1')
        $lines.Add('    Entries = @(')

        foreach ($entryItem in $Entry)
        {
            $lines.Add('        @{')
            $lines.Add("            Path    = '$($entryItem.Path)'")
            $lines.Add('            Trusted = $false')
            $lines.Add('            Targets = @(')

            foreach ($commandNameItem in $entryItem.CommandName)
            {
                $lines.Add("                @{ CommandName = '$commandNameItem'; Native = `$true }")
            }

            $lines.Add('            )')
            $lines.Add('        }')
        }

        $lines.Add('    )')
        $lines.Add('}')

        Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
    }

    function Invoke-TestResetPress
    {
        param(
            [Parameter(Mandatory)]
            [string] $CommandName
        )

        $inputScript = "$CommandName "
        @((TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length).CompletionMatches.CompletionText)
    }

    function Get-TestParameterSetSignature
    {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.CommandInfo] $Command
        )

        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

        foreach ($parameterSet in $Command.ParameterSets | Sort-Object -Property Name)
        {
            $parameters = foreach ($parameter in $parameterSet.Parameters | Sort-Object -Property Name)
            {
                if ($parameter.Name -in $commonParameters -or $parameter.Name -eq 'AllowUnmanaged')
                {
                    continue
                }

                '{0}:{1}:Mandatory={2}:ByValue={3}:ByPropertyName={4}:Aliases={5}' -f
                    $parameter.Name,
                    $parameter.ParameterType.FullName,
                    $parameter.IsMandatory,
                    $parameter.ValueFromPipeline,
                    $parameter.ValueFromPipelineByPropertyName,
                    ($parameter.Aliases -join ',')
            }

            '{0} (Default={1}): {2}' -f $parameterSet.Name, $parameterSet.IsDefault, ($parameters -join '; ')
        }
    }

    $script:ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
    $script:ResetCleanupTargets = @(
        'resetfixture', 'resetfixture.exe', 'resetfixturea', 'resetfixtureb', 'resetfixturec',
        'resetcase', 'resetnext', 'resetpending', 'resettrusted'
    ) | ForEach-Object { @{ CommandName = $_; CompleterType = 'Native' } }
}

Describe 'Reset-Completer' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:ResetCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name $script:ManifestPath -Force | Out-Null
    }

    AfterEach {
        foreach ($cleanupTarget in $script:ResetCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'returns a Failed record to Pending and loads the fixed script on the next tab press' {
        $setRoot = Join-Path -Path $TestDrive -ChildPath 'FailedSet'
        $scriptPath = Join-Path -Path $setRoot -ChildPath 'reset_completer/reset_completer.ps1'
        $setPath = Join-Path -Path $setRoot -ChildPath 'completers.psd1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture', 'resetfixture.exe' -Value 'first-one'
        Write-TestResetSet -Path $setPath -Entry @{ Path = 'reset_completer/reset_completer.ps1'; CommandName = 'resetfixture', 'resetfixture.exe' }

        $imported = @(Import-CompleterSet -LiteralPath $setPath)
        @($imported.State) | Should -Be @('Pending', 'Pending')

        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture', 'resetfixture.exe' -Value 'first-one' -NonStrict
        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Not -Contain 'first-one'
        @(Get-Completer -State Failed).Key | Should -Be @('resetfixture')

        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture', 'resetfixture.exe' -Value 'fixed-one', 'fixed-two'
        Get-Completer -State Failed | Reset-Completer

        Get-Completer -State Failed | Should -BeNullOrEmpty
        $reset = Get-Completer -CommandName 'resetfixture' -Native
        $reset.State | Should -Be 'Pending'
        $reset.LoadError | Should -BeNullOrEmpty
        $reset.ScriptPath | Should -Be $scriptPath

        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('fixed-one', 'fixed-two')
        (Get-Completer -CommandName 'resetfixture' -Native).State | Should -Be 'Active'
        (Get-Completer -CommandName 'resetfixture.exe' -Native).State | Should -Be 'Active' -Because 'the Pending sibling of the same script is swapped from the same load'
    }

    It 'resets every resettable record piped from Get-Completer -State Failed and reports the rest' {
        $setRoot = Join-Path -Path $TestDrive -ChildPath 'MixedSet'
        $setPath = Join-Path -Path $setRoot -ChildPath 'completers.psd1'
        $entries = foreach ($name in 'resetfixturea', 'resetfixtureb', 'resetfixturec')
        {
            @{ Path = "$name/$name.ps1"; CommandName = $name }
        }

        foreach ($entryItem in $entries)
        {
            Write-TestResetScript -Path (Join-Path -Path $setRoot -ChildPath $entryItem.Path) -CommandName $entryItem.CommandName -Value 'value-one'
        }

        Write-TestResetSet -Path $setPath -Entry $entries
        $null = Import-CompleterSet -LiteralPath $setPath

        foreach ($entryItem in $entries)
        {
            Write-TestResetScript -Path (Join-Path -Path $setRoot -ChildPath $entryItem.Path) -CommandName $entryItem.CommandName -Value 'value-one' -NonStrict
            $null = Invoke-TestResetPress -CommandName $entryItem.CommandName
        }

        @(Get-Completer -State Failed).Key | Should -Be @('resetfixturea', 'resetfixtureb', 'resetfixturec')

        Write-TestResetScript -Path (Join-Path -Path $setRoot -ChildPath 'resetfixturec/resetfixturec.ps1') -CommandName 'resetfixturec' -Value 'fixed-c'
        Register-ArgumentCompleter -Native -CommandName 'resetfixturea' -ScriptBlock { 'outside' }
        Remove-Item -LiteralPath (Join-Path -Path $setRoot -ChildPath 'resetfixtureb/resetfixtureb.ps1')

        Get-Completer -State Failed | Reset-Completer -ErrorVariable resetErrors -ErrorAction SilentlyContinue

        $resetErrors.Count | Should -Be 2
        foreach ($resetError in $resetErrors)
        {
            $resetError.Exception.Message | Should -BeLike 'Failed to reset the completer*'
        }

        $resetErrors[0].Exception.Message | Should -BeLike "Failed to reset the completer 'resetfixturea'. *created outside this module*"
        $resetErrors[1].Exception.Message | Should -BeLike "Failed to reset the completer 'resetfixtureb'. The script * no longer exists*"
        (Get-Completer -CommandName 'resetfixturec' -Native).State | Should -Be 'Pending' -Because 'an error on an earlier record does not stop the call'
        @(Get-Completer -State Failed).Key | Should -Be @('resetfixturea', 'resetfixtureb')
        Invoke-TestResetPress -CommandName 'resetfixturec' | Should -Be @('fixed-c')
    }

    It 'returns an Active lazily loaded record to Pending with LoadError and ImportModule cleared' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'before-edit'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy

        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('before-edit')
        $active = Get-Completer -CommandName 'resetfixture' -Native
        $active.State | Should -Be 'Active'
        $active.ImportModule | Should -Not -BeNullOrEmpty

        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'after-edit'
        $records = @(Reset-Completer -CommandName 'resetfixture' -Native -PassThru)

        $records.Count | Should -Be 1
        $records[0].PSTypeNames | Should -Contain 'CompleterActions.CompleterRegistration'
        $records[0].State | Should -Be 'Pending'
        $records[0].LoadError | Should -BeNullOrEmpty
        $records[0].ImportModule | Should -BeNullOrEmpty
        $records[0].ScriptPath | Should -Be $scriptPath
        $records[0].Trusted | Should -BeFalse
        $records[0].IsRuntimeRegistered | Should -BeTrue
        $records[0].ScriptText | Should -Match 'Invoke-CompleterLazyStub'
        [object]::ReferenceEquals((Get-TestRuntimeScriptBlock -Key 'resetfixture'), $records[0].ScriptBlock) | Should -BeTrue

        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('after-edit')
        (Get-Completer -CommandName 'resetfixture' -Native).State | Should -Be 'Active'
    }

    Context 'in a fresh process' {
        BeforeAll {
            $probeScript = @'
param(
    [ValidateSet('WhatIf', 'ConfirmPending')] [string] $Mode,
    [string] $ScriptRoot
)

Import-Module -Name '{0}' -Force

function Write-ProbeScript
{{
    param([string] $Path, [string] $CommandName)

    Set-Content -LiteralPath $Path -Encoding utf8 -Value @"
Register-ArgumentCompleter -Native -CommandName '$CommandName' -ScriptBlock {{
    [System.Management.Automation.CompletionResult]::new('probe', 'probe', 'ParameterValue', 'probe')
}}
"@
}}

$activePath = Join-Path -Path $ScriptRoot -ChildPath 'resetfixture.ps1'
$pendingPath = Join-Path -Path $ScriptRoot -ChildPath 'resetpending.ps1'
Write-ProbeScript -Path $activePath -CommandName 'resetfixture'
Write-ProbeScript -Path $pendingPath -CommandName 'resetpending'
$null = Register-Completer -LiteralPath $activePath -Lazy
$pending = Register-Completer -LiteralPath $pendingPath -Lazy -PassThru
$null = TabExpansion2 -InputScript 'resetfixture ' -CursorColumn 13
$active = Get-Completer -CommandName 'resetfixture' -Native
"BEFORE=$($active.State),$((Get-Completer -CommandName 'resetpending' -Native).State)"

if ($Mode -eq 'WhatIf')
{{
    $returned = @(Reset-Completer -CommandName 'resetfixture', 'resetpending' -Native -PassThru -WhatIf)
    "RETURNED=$($returned.Count)"
}}
else
{{
    $returned = @(Reset-Completer -CommandName 'resetpending' -Native -PassThru -Confirm -Verbose 4>&1)
    "RETURNED=$(@($returned | Where-Object {{ $_ -is [System.Management.Automation.VerboseRecord] }}).Count) verbose, $(@($returned | Where-Object PSTypeNames -Contains 'CompleterActions.CompleterRegistration').Count) records"
    $returned | Where-Object {{ $_ -is [System.Management.Automation.VerboseRecord] }} | ForEach-Object {{ "VERBOSE=$($_.Message)" }}
    "SAMEPENDING=$([object]::ReferenceEquals(($returned | Where-Object PSTypeNames -Contains 'CompleterActions.CompleterRegistration'), $pending))"
}}

$after = Get-Completer -CommandName 'resetfixture' -Native
"AFTER=$($after.State),$((Get-Completer -CommandName 'resetpending' -Native).State)"
"SAMEACTIVE=$([object]::ReferenceEquals($after, $active))"
'@ -f $script:ManifestPath

            $script:ResetProbePath = Join-Path -Path $TestDrive -ChildPath 'reset-probe.ps1'
            Set-Content -LiteralPath $script:ResetProbePath -Value $probeScript
        }

        It 'prints the WhatIf line and changes nothing' {
            $scriptRoot = Join-Path -Path $TestDrive -ChildPath 'WhatIfProbe'
            $null = New-Item -ItemType Directory -Path $scriptRoot -Force

            $output = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $script:ResetProbePath -Mode WhatIf -ScriptRoot $scriptRoot 2>&1)

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            $output | Should -Contain 'BEFORE=Active,Pending'
            @($output | Where-Object { $_ -like 'What if: *' }) | Should -Be @('What if: Performing the operation "Reset completer registration" on target "resetfixture".') -Because 'the Pending target is left alone without ShouldProcess'
            $output | Should -Contain 'RETURNED=0'
            $output | Should -Contain 'AFTER=Active,Pending'
            $output | Should -Contain 'SAMEACTIVE=True'
        }

        It 'leaves a Pending target alone without ShouldProcess and returns it with -PassThru' {
            $scriptRoot = Join-Path -Path $TestDrive -ChildPath 'PendingProbe'
            $null = New-Item -ItemType Directory -Path $scriptRoot -Force

            # -Confirm in a -NonInteractive process fails the call if ShouldProcess prompts.
            $output = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $script:ResetProbePath -Mode ConfirmPending -ScriptRoot $scriptRoot 2>&1)

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            ($output -join [Environment]::NewLine) | Should -Not -Match 'ShouldProcess|NonInteractive|Confirm' -Because 'a Pending target must not be offered to ShouldProcess'
            $output | Should -Contain 'RETURNED=1 verbose, 1 records'
            $output | Should -Contain "VERBOSE=The completer registration 'resetpending' is already pending."
            $output | Should -Contain 'SAMEPENDING=True'
            $output | Should -Contain 'AFTER=Active,Pending'
        }
    }

    It 'writes a non-terminating error for <Case>' -TestCases @(
        @{
            Case     = 'a Discovered target'
            Setup    = { param($ScriptPath) $null = $ScriptPath; Register-ArgumentCompleter -Native -CommandName 'resetcase' -ScriptBlock { 'outside' } }
            Expected = "The completer registration 'resetcase' is not module-managed, so it cannot be reset."
        }
        @{
            Case     = 'a script-block Active target'
            Setup    = { param($ScriptPath) $null = $ScriptPath; $null = Register-Completer -CommandName 'resetcase' -Native -ScriptBlock { 'managed' } }
            Expected = "The completer registration 'resetcase' was registered from a script block, not a script file, so there is nothing to reload."
        }
        @{
            Case     = 'a Stale target whose runtime value was removed'
            Setup    = {
                param($ScriptPath)
                $null = Register-Completer -LiteralPath $ScriptPath -Lazy
                Invoke-TestRuntimeCompleterCleanup -CommandName 'resetcase' -CompleterType 'Native'
            }
            Expected = "The module-managed completer registration for 'resetcase' is stale. Use Register-Completer -Force to register it again."
        }
        @{
            Case     = 'a Stale target with a value created outside the module'
            Setup    = {
                param($ScriptPath)
                $null = Register-Completer -LiteralPath $ScriptPath -Lazy
                Register-ArgumentCompleter -Native -CommandName 'resetcase' -ScriptBlock { 'outside' }
            }
            Expected = "The module-managed completer registration for 'resetcase' is stale and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it."
        }
        @{
            Case     = 'a Failed target re-registered outside the module'
            Setup    = {
                param($ScriptPath)
                $null = Register-Completer -LiteralPath $ScriptPath -Lazy
                Write-TestResetScript -Path $ScriptPath -CommandName 'resetcase' -Value 'case-value' -NonStrict
                $null = Invoke-TestResetPress -CommandName 'resetcase'
                Register-ArgumentCompleter -Native -CommandName 'resetcase' -ScriptBlock { 'outside' }
            }
            Expected = "The module-managed completer registration for 'resetcase' is failed and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it."
        }
        @{
            Case     = 'a target with nothing registered'
            Setup    = { param($ScriptPath) $null = $ScriptPath }
            Expected = 'No completer registration was found for the requested target.'
        }
        @{
            Case     = 'a target whose script no longer exists'
            Setup    = {
                param($ScriptPath)
                $null = Register-Completer -LiteralPath $ScriptPath -Lazy
                $null = Invoke-TestResetPress -CommandName 'resetcase'
                Remove-Item -LiteralPath $ScriptPath
            }
            Expected = "The script '{0}' for 'resetcase' no longer exists. Restore it, or remove the registration with Unregister-Completer."
        }
    ) {
        $caseScriptPath = Join-Path -Path $TestDrive -ChildPath 'resetcase.ps1'
        $nextScriptPath = Join-Path -Path $TestDrive -ChildPath 'resetnext.ps1'
        Write-TestResetScript -Path $caseScriptPath -CommandName 'resetcase' -Value 'case-value'
        Write-TestResetScript -Path $nextScriptPath -CommandName 'resetnext' -Value 'next-value'
        $null = Register-Completer -LiteralPath $nextScriptPath -Lazy
        Invoke-TestResetPress -CommandName 'resetnext' | Should -Be @('next-value')

        & $Setup $caseScriptPath

        $records = @(Reset-Completer -CommandName 'resetcase', 'resetnext' -Native -PassThru -ErrorVariable resetErrors -ErrorAction SilentlyContinue)
        $succeeded = $?

        $succeeded | Should -BeFalse
        $resetErrors.Count | Should -Be 1
        $resetErrors[0].Exception.Message | Should -BeExactly ("Failed to reset the completer 'resetcase'. " + ($Expected -f $caseScriptPath))
        $resetErrors[0].FullyQualifiedErrorId | Should -Be 'CompleterResetFailed,Reset-Completer'
        $resetErrors[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
        @($records.Key) | Should -Be @('resetnext') -Because 'the next target still runs after the error'
        (Get-Completer -CommandName 'resetnext' -Native).State | Should -Be 'Pending'
    }

    It 'leaves a Pending record whose script was deleted alone without an error' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'resetfixture.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'pending-value'
        $pending = Register-Completer -LiteralPath $scriptPath -Lazy -PassThru
        $stub = Get-TestRuntimeScriptBlock -Key 'resetfixture'
        Remove-Item -LiteralPath $scriptPath

        $records = @(Reset-Completer -CommandName 'resetfixture' -Native -PassThru -ErrorVariable resetErrors)

        $resetErrors | Should -BeNullOrEmpty
        $records.Count | Should -Be 1
        [object]::ReferenceEquals($records[0], $pending) | Should -BeTrue
        [object]::ReferenceEquals((Get-TestManagedRegistration -Key 'resetfixture'), $pending) | Should -BeTrue
        [object]::ReferenceEquals((Get-TestRuntimeScriptBlock -Key 'resetfixture'), $stub) | Should -BeTrue
    }

    It 'resets only the named targets and leaves an Active sibling loaded' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture', 'resetfixture.exe' -Value 'sibling-value'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy
        $null = Invoke-TestResetPress -CommandName 'resetfixture'

        $sibling = Get-Completer -CommandName 'resetfixture.exe' -Native
        $sibling.State | Should -Be 'Active'
        $siblingBlock = Get-TestRuntimeScriptBlock -Key 'resetfixture.exe'

        $null = Reset-Completer -CommandName 'resetfixture' -Native

        (Get-Completer -CommandName 'resetfixture' -Native).State | Should -Be 'Pending'
        (Get-Completer -CommandName 'resetfixture.exe' -Native).State | Should -Be 'Active'
        [object]::ReferenceEquals((Get-TestManagedRegistration -Key 'resetfixture.exe'), $sibling) | Should -BeTrue
        [object]::ReferenceEquals((Get-TestRuntimeScriptBlock -Key 'resetfixture.exe'), $siblingBlock) | Should -BeTrue
    }

    It 'decides a key once per call' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'once-value'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy
        $null = Invoke-TestResetPress -CommandName 'resetfixture'
        $active = Get-Completer -CommandName 'resetfixture' -Native

        $records = @(@($active, $active) | Reset-Completer -PassThru)
        $records.Count | Should -Be 1
        $records[0].State | Should -Be 'Pending'

        $named = @(Reset-Completer -CommandName 'resetfixture', 'RESETFIXTURE', 'resetcase', 'ResetCase' -Native -PassThru -ErrorVariable resetErrors -ErrorAction SilentlyContinue)
        $named.Count | Should -Be 1 -Because 'the second spelling of a Pending key is skipped'
        $resetErrors.Count | Should -Be 1 -Because 'a key that failed is not reported twice'
    }

    It 'restores the previous runtime value and managed record when the reset write fails' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'kept-value'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy
        $null = Invoke-TestResetPress -CommandName 'resetfixture'
        $active = Get-TestManagedRegistration -Key 'resetfixture'
        $activeBlock = Get-TestRuntimeScriptBlock -Key 'resetfixture'
        $active.State | Should -Be 'Active'

        & (Get-Module -Name 'CompleterActions') {
            $script:OriginalAddManagedCompleterRegistration = ${function:Add-ManagedCompleterRegistration}

            function script:Add-ManagedCompleterRegistration
            {
                param($Registration)

                if ($Registration.State -eq 'Pending')
                {
                    throw 'forced reset failure'
                }

                & $script:OriginalAddManagedCompleterRegistration -Registration $Registration
            }
        }

        # The error stream, not -ErrorVariable: the write helper's own throw,
        # caught inside Reset-Completer, is also collected by -ErrorVariable.
        $resetErrors = @(Reset-Completer -CommandName 'resetfixture' -Native -ErrorAction Continue 2>&1)

        $resetErrors.Count | Should -Be 1
        $resetErrors[0].Exception.Message | Should -BeExactly "Failed to reset the completer 'resetfixture'. Failed to register the completer 'resetfixture'. forced reset failure"
        [object]::ReferenceEquals((Get-TestManagedRegistration -Key 'resetfixture'), $active) | Should -BeTrue
        [object]::ReferenceEquals((Get-TestRuntimeScriptBlock -Key 'resetfixture'), $activeBlock) | Should -BeTrue
        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('kept-value')
    }

    It 'reports an input object it cannot resolve and continues with the next' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'input-value'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy
        $null = Invoke-TestResetPress -CommandName 'resetfixture'
        $active = Get-Completer -CommandName 'resetfixture' -Native

        # The error stream, not -ErrorVariable: the resolver's own throw, caught
        # inside Reset-Completer, is also collected by -ErrorVariable.
        $output = @(Reset-Completer -InputObject @([pscustomobject] @{ Key = 'resetfixture' }, $active) -PassThru -ErrorAction Continue 2>&1)
        $succeeded = $?
        $resetErrors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $records = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

        $succeeded | Should -BeFalse
        $resetErrors.Count | Should -Be 1
        $resetErrors[0].Exception.Message | Should -BeLike "Failed to reset the completer. Failed to resolve a completer target from InputObject. InputObject supplies the key 'resetfixture' without an IsNative or Native property.*"
        @($records.Key) | Should -Be @('resetfixture')
        $records[0].State | Should -Be 'Pending'
    }

    It 'stops at the first error with -ErrorAction Stop' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'reset_completer.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'stop-value'
        $null = Register-Completer -LiteralPath $scriptPath -Lazy
        $null = Invoke-TestResetPress -CommandName 'resetfixture'

        {
            Reset-Completer -CommandName 'resetcase', 'resetfixture' -Native -ErrorAction Stop
        } | Should -Throw "Failed to reset the completer 'resetcase'. No completer registration was found for the requested target."

        (Get-Completer -CommandName 'resetfixture' -Native).State | Should -Be 'Active' -Because 'the call stopped before the second target'
    }

    It 'mirrors the parameter sets of Unregister-Completer apart from -AllowUnmanaged' {
        $reset = Get-Command -Name 'Reset-Completer'
        $unregister = Get-Command -Name 'Unregister-Completer'

        @($reset.ParameterSets.Name | Sort-Object) | Should -Be @('CommandParameter', 'InputObject', 'Native')
        $reset.DefaultParameterSet | Should -Be $unregister.DefaultParameterSet
        $reset.Parameters.ContainsKey('AllowUnmanaged') | Should -BeFalse
        @(Get-TestParameterSetSignature -Command $reset) | Should -Be @(Get-TestParameterSetSignature -Command $unregister)
        @($reset.OutputType.Name) | Should -Be @('CompleterActions.CompleterRegistration')

        $binding = $reset.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $binding.SupportsShouldProcess | Should -BeTrue
        $binding.ConfirmImpact | Should -Be 'Medium'
    }

    It 'reloads a trusted record under the trusted tier' {
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'resettrusted.ps1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resettrusted' -Value 'trusted-one' -NonStrict
        $null = Register-Completer -LiteralPath $scriptPath -Lazy -Trusted -CommandName 'resettrusted' -Native
        Invoke-TestResetPress -CommandName 'resettrusted' | Should -Be @('trusted-one')

        Write-TestResetScript -Path $scriptPath -CommandName 'resettrusted' -Value 'trusted-two' -NonStrict
        $record = Reset-Completer -CommandName 'resettrusted' -Native -PassThru

        $record.State | Should -Be 'Pending'
        $record.Trusted | Should -BeTrue
        Invoke-TestResetPress -CommandName 'resettrusted' | Should -Be @('trusted-two') -Because 'the strict tier would reject the script'

        $loaded = Get-Completer -CommandName 'resettrusted' -Native
        $loaded.State | Should -Be 'Active'
        $loaded.Trusted | Should -BeTrue
        $loaded.LoadError | Should -BeNullOrEmpty
    }

    It 'leaves PSReadLine key handlers unchanged across Reset-Completer, the reloading tab press, and Test-CompleterSet' {
        Import-Module -Name 'PSReadLine' -ErrorAction SilentlyContinue

        if ($null -eq (Get-Module -Name 'PSReadLine'))
        {
            Set-ItResult -Skipped -Because 'PSReadLine is not loaded in this session'
        }

        $before = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        $setRoot = Join-Path -Path $TestDrive -ChildPath 'NeutralSet'
        $scriptPath = Join-Path -Path $setRoot -ChildPath 'reset_completer/reset_completer.ps1'
        $setPath = Join-Path -Path $setRoot -ChildPath 'completers.psd1'
        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'first-one'
        Write-TestResetSet -Path $setPath -Entry @{ Path = 'reset_completer/reset_completer.ps1'; CommandName = 'resetfixture' }
        $null = Import-CompleterSet -LiteralPath $setPath
        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('first-one')

        Write-TestResetScript -Path $scriptPath -CommandName 'resetfixture' -Value 'second-one'
        Reset-Completer -CommandName 'resetfixture' -Native
        Invoke-TestResetPress -CommandName 'resetfixture' | Should -Be @('second-one')
        $null = @(Test-CompleterSet -LiteralPath $setPath)

        $after = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }
}
