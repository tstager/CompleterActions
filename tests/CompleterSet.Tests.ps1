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

    function Write-TestCompleterSet
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string[]] $Entry
        )

        $content = @(
            '@{'
            '    Version = 1'
            '    Entries = @('
            foreach ($entryText in $Entry) { "        $entryText" }
            '    )'
            '}'
        )

        Set-Content -LiteralPath $Path -Value $content -Encoding utf8
    }

    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures'
    $script:ImportFixtureRoot = Join-Path -Path $script:FixtureRoot -ChildPath 'ImportCompleterScript'
    $script:ParameterFixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'ParameterCompleter.ps1'
    $script:MultiFixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'MultiCommandCompleter.ps1'
    $script:NativeFixturePath = Join-Path -Path $script:FixtureRoot -ChildPath 'ImportableNativeCompleter.ps1'
    $script:TrustedFixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'TrustedOnlyCompleter.ps1'
    $script:UnsafeFixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'UnsafeTopLevelScript.ps1'
    $script:DynamicFixturePath = Join-Path -Path $script:ImportFixtureRoot -ChildPath 'DynamicCommandName.ps1'
    $script:ThrowingStrictFixturePath = Join-Path -Path $script:FixtureRoot -ChildPath (Join-Path -Path 'LazyRegistration' -ChildPath 'ThrowingStrictCompleter.ps1')
    $script:SetCleanupTargets = @(
        @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-LazyStrictSetTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-UnsafeTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-ImportedTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'importfixture'; CompleterType = 'Native' },
        @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' }
    )
}

Describe 'Completer sets' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:SetCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-TrustedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-LazyStrictSetTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-UnsafeTool' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1') -Force | Out-Null

        function global:Test-ImportedFixtureTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function global:Test-TrustedFixtureTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function global:Test-LazyStrictSetTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        function global:Test-UnsafeTool
        {
            [CmdletBinding()]
            param(
                [string] $Name
            )
        }

        $script:SetRoot = Join-Path -Path $TestDrive -ChildPath ('sets-{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:SetRoot -ItemType Directory | Out-Null
        $script:SetPath = Join-Path -Path $script:SetRoot -ChildPath 'completers.psd1'
    }

    AfterEach {
        foreach ($cleanupTarget in $script:SetCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Item -Path 'Function:\global:Test-ImportedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-TrustedFixtureTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-LazyStrictSetTool' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Function:\global:Test-UnsafeTool' -ErrorAction SilentlyContinue
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    Context 'Export-CompleterSet' {
        It 'writes the set schema with a path relative to the set file and one target per registration' {
            $scriptFolder = Join-Path -Path $script:SetRoot -ChildPath 'scripts'
            New-Item -Path $scriptFolder -ItemType Directory | Out-Null
            $scriptPath = Join-Path -Path $scriptFolder -ChildPath 'Native.ps1'
            Copy-Item -LiteralPath $script:NativeFixturePath -Destination $scriptPath

            $written = Import-CompleterScript -Path $scriptPath | Export-CompleterSet -Path $script:SetPath -PassThru

            $written.FullName | Should -Be $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath

            $data.Version | Should -Be 1
            @($data.Entries).Count | Should -Be 1
            $data.Entries[0].Path | Should -Be (Join-Path -Path 'scripts' -ChildPath 'Native.ps1')
            $data.Entries[0].Trusted | Should -BeFalse
            @($data.Entries[0].Targets.CommandName | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
            @($data.Entries[0].Targets.Native | Select-Object -Unique) | Should -Be @($true)
        }

        It 'records the trust tier per script and groups targets by script' {
            $records = @(Import-CompleterScript -Path $script:ParameterFixturePath) + @(Import-CompleterScript -Path $script:TrustedFixturePath -Trusted)

            $records | Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath

            @($data.Entries).Count | Should -Be 2

            $strictEntry = $data.Entries | Where-Object { -not $_.Trusted }
            $strictEntry.Targets[0].CommandName | Should -Be 'Test-ImportedFixtureTool'
            $strictEntry.Targets[0].ParameterName | Should -Be 'Name'
            [System.IO.Path]::GetFullPath($strictEntry.Path, $script:SetRoot) | Should -Be $script:ParameterFixturePath

            $trustedEntry = $data.Entries | Where-Object { $_.Trusted }
            $trustedEntry.Targets[0].CommandName | Should -Be 'Test-TrustedFixtureTool'
            [System.IO.Path]::GetFullPath($trustedEntry.Path, $script:SetRoot) | Should -Be $script:TrustedFixturePath
        }

        It 'accepts managed registration records that expose ScriptPath and Trusted' {
            $record = [pscustomobject] @{
                CommandName = 'importfixture'
                IsNative    = $true
                ScriptPath  = $script:NativeFixturePath
                Trusted     = $true
            }

            $record | Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath

            @($data.Entries).Count | Should -Be 1
            $data.Entries[0].Trusted | Should -BeTrue
            $data.Entries[0].Targets[0].CommandName | Should -Be 'importfixture'
            $data.Entries[0].Targets[0].Native | Should -BeTrue
        }

        It 'throws when nothing with a script path is available to export' {
            { Export-CompleterSet -Path $script:SetPath } | Should -Throw '*No registrations with a script path*'
            Test-Path -LiteralPath $script:SetPath | Should -BeFalse

            $scriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
            }

            {
                [pscustomobject] @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; ScriptBlock = $scriptBlock } | Export-CompleterSet -Path $script:SetPath
            } | Should -Throw '*ScriptPath or SourcePath*'
        }

        It 'requires a .psd1 path' {
            {
                Import-CompleterScript -Path $script:ParameterFixturePath | Export-CompleterSet -Path (Join-Path -Path $script:SetRoot -ChildPath 'completers.json')
            } | Should -Throw '*must be .psd1 files*'
        }

        It 'supports WhatIf without writing the file' {
            Import-CompleterScript -Path $script:ParameterFixturePath | Export-CompleterSet -Path $script:SetPath -WhatIf

            Test-Path -LiteralPath $script:SetPath | Should -BeFalse
        }
    }

    Context 'Import-CompleterSet' {
        It 'restores the same targets as Pending records after an Export then Import round trip and loads them on first tab' {
            $imported = @(Import-CompleterScript -Path $script:ParameterFixturePath) +
                @(Import-CompleterScript -Path $script:NativeFixturePath) +
                @(Import-CompleterScript -Path $script:TrustedFixturePath -Trusted)
            $imported | Export-CompleterSet -Path $script:SetPath

            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            @($registered.Key | Sort-Object) | Should -Be @($imported.Key | Sort-Object)
            $registered[0].PSTypeNames | Should -Contain 'CompleterActions.CompleterRegistration'
            @($registered.State | Select-Object -Unique) | Should -Be @('Pending')
            @((Get-CompleterRegistration -ManagedOnly).Key | Sort-Object) | Should -Be @($imported.Key | Sort-Object)

            $trustedInput = 'Test-TrustedFixtureTool -Name trusted'
            $trustedCompletion = TabExpansion2 -InputScript $trustedInput -CursorColumn $trustedInput.Length
            $trustedCompletion.CompletionMatches.CompletionText | Should -Contain 'trusted-alpha'

            $nativeInput = 'importfixture a'
            $nativeCompletion = TabExpansion2 -InputScript $nativeInput -CursorColumn $nativeInput.Length
            $nativeCompletion.CompletionMatches.CompletionText | Should -Contain 'alpha'

            (Get-CompleterRegistration -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name').State | Should -Be 'Active'
            (Get-CompleterRegistration -CommandName 'importfixture' -Native).State | Should -Be 'Active'
            (Get-CompleterRegistration -CommandName 'importfixture.exe' -Native).State | Should -Be 'Active'
            (Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name').State | Should -Be 'Pending'
        }

        It 'round-trips a lazily imported set through Get-CompleterRegistration and Export-CompleterSet' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )
            $null = @(Import-CompleterSet -Path $script:SetPath)

            $exportPath = Join-Path -Path $script:SetRoot -ChildPath 'exported.psd1'
            Get-CompleterRegistration -ManagedOnly | Export-CompleterSet -Path $exportPath

            $exported = Import-PowerShellDataFile -LiteralPath $exportPath
            $entriesByScript = @{}

            foreach ($entry in $exported.Entries)
            {
                $entriesByScript[[System.IO.Path]::GetFullPath($entry.Path, $script:SetRoot)] = $entry
            }

            @($entriesByScript.Keys | Sort-Object) | Should -Be @($script:NativeFixturePath, $script:TrustedFixturePath | Sort-Object)
            $entriesByScript[$script:NativeFixturePath].Trusted | Should -BeFalse
            @($entriesByScript[$script:NativeFixturePath].Targets.CommandName | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
            $entriesByScript[$script:TrustedFixturePath].Trusted | Should -BeTrue
            $entriesByScript[$script:TrustedFixturePath].Targets[0].CommandName | Should -Be 'Test-TrustedFixtureTool'
            $entriesByScript[$script:TrustedFixturePath].Targets[0].ParameterName | Should -Be 'Name'

            Get-CompleterRegistration -ManagedOnly | Unregister-CompleterRegistration -Confirm:$false

            $reimported = @(Import-CompleterSet -Path $exportPath)

            @($reimported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe', 'test-trustedfixturetool:name')
            @($reimported.State | Select-Object -Unique) | Should -Be @('Pending')
        }

        It 'marks a strict entry Failed and leaves default completion working when its script throws while loading' {
            $fallbackMarker = Join-Path -Path $script:SetRoot -ChildPath 'set-fallback-marker.txt'
            Set-Content -LiteralPath $fallbackMarker -Value 'marker' -Encoding utf8
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ThrowingStrictFixturePath' }"

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-lazystrictsettool:name'
            $registered[0].State | Should -Be 'Pending'

            $inputScript = 'Test-LazyStrictSetTool -Name '

            Push-Location -LiteralPath $script:SetRoot
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
            @($firstCompletion.CompletionMatches.CompletionText) | Should -Contain (Join-Path -Path '.' -ChildPath 'set-fallback-marker.txt')
            @($secondCompletion.CompletionMatches.CompletionText) | Should -Contain (Join-Path -Path '.' -ChildPath 'set-fallback-marker.txt')

            $failed = Get-CompleterRegistration -CommandName 'Test-LazyStrictSetTool' -ParameterName 'Name'
            $failed.State | Should -Be 'Failed'
            $failed.IsRuntimeRegistered | Should -BeFalse
            $failed.ScriptPath | Should -Be $script:ThrowingStrictFixturePath
            $failed.LoadError | Should -Match 'CompleterActionsLazyFixtureMissing'
            Get-CompleterRegistration -CommandName 'Test-LazyStrictSetTool' -ParameterName 'Name' -DiscoveredOnly | Should -BeNullOrEmpty

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*failed to load*Use -Force to retry*'

            $retried = @(Import-CompleterSet -Path $script:SetPath -Force)
            $retried[0].State | Should -Be 'Pending'
            $retried[0].LoadError | Should -BeNullOrEmpty
        }

        It 'registers a strict entry that breaks the grammar as Pending and fails it with the findings on first tab' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:UnsafeFixturePath' }"

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-unsafetool:name'
            $registered[0].State | Should -Be 'Pending'

            $inputScript = 'Test-UnsafeTool -Name un'
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            @($completion.CompletionMatches.CompletionText) | Should -Not -Contain 'unsafe'

            $failed = Get-CompleterRegistration -CommandName 'Test-UnsafeTool' -ParameterName 'Name'
            $failed.State | Should -Be 'Failed'
            $failed.LoadError | Should -Match 'does not conform to the strict import grammar'
            $failed.LoadError | Should -Match 'Get-Date'
            Get-CompleterRegistration -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -DiscoveredOnly | Should -BeNullOrEmpty
        }

        It 'resolves relative paths against the set file directory, not the current location' {
            $scriptFolder = Join-Path -Path $script:SetRoot -ChildPath 'scripts'
            New-Item -Path $scriptFolder -ItemType Directory | Out-Null
            Copy-Item -LiteralPath $script:ParameterFixturePath -Destination (Join-Path -Path $scriptFolder -ChildPath 'Relative.ps1')
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = 'scripts/Relative.ps1' }"

            Push-Location -LiteralPath $TestDrive
            try
            {
                $registered = @(Import-CompleterSet -Path $script:SetPath)
            }
            finally
            {
                Pop-Location
            }

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-importedfixturetool:name'
        }

        It 'resolves a drive-relative path against the set file directory, not the current location' {
            $driveRoot = [System.IO.Path]::GetPathRoot($script:SetRoot)

            if ($driveRoot -notmatch '^[A-Za-z]:\\$')
            {
                Set-ItResult -Skipped -Because 'drive-relative paths exist only on Windows drives'
            }

            $scriptFolder = Join-Path -Path $script:SetRoot -ChildPath 'scripts'
            New-Item -Path $scriptFolder -ItemType Directory | Out-Null
            $scriptPath = Join-Path -Path $scriptFolder -ChildPath 'DriveRelative.ps1'
            Copy-Item -LiteralPath $script:ParameterFixturePath -Destination $scriptPath
            $driveRelativePath = $driveRoot.TrimEnd('\') + 'scripts\DriveRelative.ps1'

            [System.IO.Path]::IsPathRooted($driveRelativePath) | Should -BeTrue
            [System.IO.Path]::IsPathFullyQualified($driveRelativePath) | Should -BeFalse
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$driveRelativePath' }"

            Push-Location -LiteralPath $TestDrive
            try
            {
                $registered = @(Import-CompleterSet -Path $script:SetPath)
            }
            finally
            {
                Pop-Location
            }

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-importedfixturetool:name'
            $registered[0].ScriptPath | Should -Be $scriptPath
        }

        It 'reports every invalid entry in one error and registers nothing' {
            Set-Content -LiteralPath (Join-Path -Path $script:SetRoot -ChildPath 'notes.txt') -Value 'not a script' -Encoding utf8
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = 'missing.ps1' }"
                "@{ Path = 'notes.txt' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true }"
                "@{ Path = '$script:DynamicFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
            )

            $thrown = { Import-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match 'has 4 invalid entries and nothing was registered'
            $thrown.Exception.Message | Should -Match "Entry 1 \('missing\.ps1'\): The file '.*missing\.ps1' does not exist\."
            $thrown.Exception.Message | Should -Match "Entry 2 \('notes\.txt'\): The file '.*notes\.txt' is not a \.ps1 script\."
            $thrown.Exception.Message | Should -Match 'Entry 3 \(.*TrustedOnlyCompleter\.ps1.\): Trusted entries must declare Targets'
            $thrown.Exception.Message | Should -Match "Entry 4 \(.*DynamicCommandName\.ps1.\): The script '.*DynamicCommandName\.ps1' does not use a literal -CommandName argument at line 1, column \d+"
            $thrown.Exception.Message | Should -Not -Match 'Entry 5'

            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
            Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'reports a strict entry whose declared Targets do not match the script' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath'; Targets = @( @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Other' } ) }"

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw "*The declared Targets do not match the script. Declared: 'Test-ImportedFixtureTool:Other'. Script registers: 'Test-ImportedFixtureTool:Name'.*"
            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
        }

        It 'reports a target listed by two entries before registering anything' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:MultiFixturePath' }"
                "@{ Path = '$script:MultiFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name' } ) }"
            )

            $thrown = { Import-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match 'has 1 invalid entry and nothing was registered'
            $thrown.Exception.Message | Should -Match "Entry 2 \(.*MultiCommandCompleter\.ps1.\): Target 'Test-ImportedOne:Name' is also listed by entry 1\."
            $thrown.Exception.Message | Should -Not -Match 'Entry 1 \('
            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty

            $registered = @(Import-CompleterSet -Path $script:SetPath -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)

            @($registered.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')
            @($registered.Trusted | Select-Object -Unique) | Should -Be @($false)
            @($warnings | Where-Object { $_.Message -match "skipped Entry 2 \(.*\): Target 'Test-ImportedOne:Name' is also listed by entry 1\." }).Count | Should -Be 1
        }

        It 'reports targets that already carry a different registration up front and registers nothing without -Force' {
            $null = Register-CompleterRegistration -LiteralPath $script:NativeFixturePath -Lazy -Trusted -CommandName 'importfixture' -Native
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:NativeFixturePath' }"
            )

            $thrown = { Import-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match "Entry 2 \(.*ImportableNativeCompleter\.ps1.\): A module-managed completer registration already exists for 'importfixture'\. Use -Force to replace it\."
            $thrown.Exception.Message | Should -Not -Match 'Entry 1 \('
            Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
            @((Get-CompleterRegistration -ManagedOnly).Key) | Should -Be @('importfixture')

            $skipped = @(Import-CompleterSet -Path $script:SetPath -SkipInvalid -WarningAction SilentlyContinue)

            @($skipped.Key) | Should -Be @('test-importedfixturetool:name')
            (Get-CompleterRegistration -CommandName 'importfixture' -Native).Trusted | Should -BeTrue

            $forced = @(Import-CompleterSet -Path $script:SetPath -Force)

            @($forced.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe', 'test-importedfixturetool:name')
            (Get-CompleterRegistration -CommandName 'importfixture' -Native).Trusted | Should -BeFalse
        }

        It 'reuses the Pending records when the same set is imported again without -Force' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )

            $first = @(Import-CompleterSet -Path $script:SetPath)
            $second = @(Import-CompleterSet -Path $script:SetPath)

            @($second.Key | Sort-Object) | Should -Be @($first.Key | Sort-Object)

            foreach ($record in $second)
            {
                [object]::ReferenceEquals($record, ($first | Where-Object -Property Key -EQ -Value $record.Key)) | Should -BeTrue
            }

            @(Get-CompleterRegistration -ManagedOnly).Count | Should -Be 3
        }

        It 'registers the valid entries and warns about the rest with -SkipInvalid' {
            Set-Content -LiteralPath (Join-Path -Path $script:SetRoot -ChildPath 'notes.txt') -Value 'not a script' -Encoding utf8
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = 'missing.ps1' }"
                "@{ Path = 'notes.txt' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true }"
                "@{ Path = '$script:DynamicFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
            )

            $registered = @(Import-CompleterSet -Path $script:SetPath -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-importedfixturetool:name'

            $warningText = @($warnings | ForEach-Object { $_.Message })
            @($warningText | Where-Object { $_ -match "skipped Entry 1 \('missing\.ps1'\)" }).Count | Should -Be 1
            @($warningText | Where-Object { $_ -match "skipped Entry 2 \('notes\.txt'\)" }).Count | Should -Be 1
            @($warningText | Where-Object { $_ -match 'skipped Entry 3 \(.*\): Trusted entries must declare Targets' }).Count | Should -Be 1
            @($warningText | Where-Object { $_ -match 'skipped Entry 4 \(.*\): The script .* does not use a literal -CommandName argument' }).Count | Should -Be 1
            @($warningText | Where-Object { $_ -match 'Entry 5' }).Count | Should -Be 0

            (Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name').Source | Should -Be 'Managed'
        }

        It 'registers a trusted entry through the trusted tier when it declares its targets' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            $registered.Count | Should -Be 1
            $registered[0].Key | Should -Be 'test-trustedfixturetool:name'

            $inputScript = 'Test-TrustedFixtureTool -Name trusted'
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            $completion.CompletionMatches.CompletionText | Should -Contain 'trusted-beta'
        }

        It 'passes -Force through to replace an existing runtime registration' {
            $externalScriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

                [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
            }

            Register-ArgumentCompleter -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath' }"

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw "*Entry 1 (*): A runtime completer registration already exists for 'Test-ImportedFixtureTool:Name'. Use -Force to replace it.*"
            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty

            $registered = @(Import-CompleterSet -Path $script:SetPath -Force)

            $registered.Count | Should -Be 1
            $registered[0].Source | Should -Be 'Managed'

            $inputScript = 'Test-ImportedFixtureTool -Name imported'
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            $completion.CompletionMatches.CompletionText | Should -Be @('imported-alpha')
        }

        It 'parses a strict entry once, during validation, and registers the targets that parse derived' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )
            Mock -CommandName 'Get-CompleterScriptTarget' -ModuleName 'CompleterActions' -MockWith {
                & (Get-Module -Name 'CompleterActions') { Resolve-CompleterTarget -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' }
            }

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            Should -Invoke -CommandName 'Get-CompleterScriptTarget' -ModuleName 'CompleterActions' -Times 1 -Exactly
            @($registered.Key) | Should -Be @('test-importedfixturetool:name', 'test-trustedfixturetool:name')
            @($registered.State | Select-Object -Unique) | Should -Be @('Pending')
            $registered[0].ScriptPath | Should -Be $script:ParameterFixturePath
            $registered[0].Trusted | Should -BeFalse
            $registered[1].ScriptPath | Should -Be $script:TrustedFixturePath
            $registered[1].Trusted | Should -BeTrue
        }

        It 'rolls back every entry of the set when a later entry fails to write' {
            $externalScriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters

                [System.Management.Automation.CompletionResult]::new('external', 'external', 'ParameterValue', 'external')
            }

            Register-ArgumentCompleter -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' -ScriptBlock $externalScriptBlock
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )
            & (Get-Module -Name 'CompleterActions') {
                $script:TestManagedWriteFunction = ${function:Add-ManagedCompleterRegistration}

                function script:Add-ManagedCompleterRegistration
                {
                    param($Registration)

                    if ($Registration.Key -eq 'test-trustedfixturetool:name')
                    {
                        throw 'forced batch failure'
                    }

                    & $script:TestManagedWriteFunction -Registration $Registration
                }
            }

            $thrown = { Import-CompleterSet -Path $script:SetPath -Force } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Be "Failed to import completer set. Failed to register the completer 'Test-TrustedFixtureTool:Name'. forced batch failure"

            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
            Get-CompleterRegistration -CommandName 'importfixture', 'importfixture.exe' -Native | Should -BeNullOrEmpty
            Get-CompleterRegistration -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty

            $restored = Get-CompleterRegistration -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
            $restored.Source | Should -Be 'Discovered'
            [object]::ReferenceEquals($restored.ScriptBlock, $externalScriptBlock) | Should -BeTrue

            $inputScript = 'Test-ImportedFixtureTool -Name '
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            @($completion.CompletionMatches.CompletionText) | Should -Be @('external')
        }

        It 'returns the records in set order and keeps a reused record in its place' {
            $existing = Register-CompleterRegistration -LiteralPath $script:ParameterFixturePath -Lazy -PassThru
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            @($registered.Key) | Should -Be @('importfixture', 'importfixture.exe', 'test-importedfixturetool:name', 'test-trustedfixturetool:name')
            [object]::ReferenceEquals($registered[2], $existing) | Should -BeTrue
            @($registered.State | Select-Object -Unique) | Should -Be @('Pending')
            @(Get-CompleterRegistration -ManagedOnly).Count | Should -Be 4
        }

        It 'reads the session registrations once and resolves each entry against that snapshot' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )

            & (Get-Module -Name 'CompleterActions') {
                $script:TestSnapshotCount = 0
                $script:TestStateCount = 0
                $script:TestSnapshotFunction = ${function:Get-CompleterRegistrationSnapshot}
                $script:TestStateFunction = ${function:Resolve-CompleterRegistrationState}

                function script:Get-CompleterRegistrationSnapshot
                {
                    $script:TestSnapshotCount++
                    & $script:TestSnapshotFunction
                }

                function script:Resolve-CompleterRegistrationState
                {
                    param($Key, $Snapshot)

                    $script:TestStateCount++
                    & $script:TestStateFunction -Key $Key -Snapshot $Snapshot
                }
            }

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            $registered.Count | Should -Be 4

            $counts = & (Get-Module -Name 'CompleterActions') {
                [pscustomobject] @{
                    Snapshots = $script:TestSnapshotCount
                    States    = $script:TestStateCount
                }
            }

            $counts.Snapshots | Should -Be 1
            $counts.States | Should -Be 3 -Because 'each entry resolves its targets in one pass against the shared snapshot'
        }

        It 'reads the set through Import-PowerShellDataFile only and never evaluates set content' {
            $probePath = Join-Path -Path $script:SetRoot -ChildPath 'probe.txt'
            Set-Content -LiteralPath $script:SetPath -Value "@{ Version = 1; Entries = @( (New-Item -ItemType File -Path '$probePath') ) }" -Encoding utf8

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*dynamic expressions*'

            Test-Path -LiteralPath $probePath | Should -BeFalse
            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty

            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath' }"
            Mock -CommandName 'Import-PowerShellDataFile' -ModuleName 'CompleterActions' -MockWith { throw 'reader sentinel' }

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*reader sentinel*'
            Should -Invoke -CommandName 'Import-PowerShellDataFile' -ModuleName 'CompleterActions' -Times 1 -Exactly
        }

        It 'supports WhatIf without importing or registering anything' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath' }"

            Import-CompleterSet -Path $script:SetPath -WhatIf | Should -BeNullOrEmpty

            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
        }

        It 'rejects files that are not .psd1 and sets without Version 1 or Entries' {
            $jsonPath = Join-Path -Path $script:SetRoot -ChildPath 'completers.json'
            Set-Content -LiteralPath $jsonPath -Value '{}' -Encoding utf8
            { Import-CompleterSet -Path $jsonPath } | Should -Throw '*must be .psd1 files*'

            Set-Content -LiteralPath $script:SetPath -Value "@{ Version = 2; Entries = @( @{ Path = '$script:ParameterFixturePath' } ) }" -Encoding utf8
            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*must declare Version = 1*'

            Set-Content -LiteralPath $script:SetPath -Value '@{ Version = 1; Entries = @() }' -Encoding utf8
            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*has no Entries*'

            Get-CompleterRegistration -ManagedOnly | Should -BeNullOrEmpty
        }

        It 'leaves PSReadLine key handlers unchanged across import, first tab, and export' {
            Import-Module -Name 'PSReadLine' -ErrorAction SilentlyContinue

            if ($null -eq (Get-Module -Name 'PSReadLine'))
            {
                Set-ItResult -Skipped -Because 'PSReadLine is not loaded in this session'
            }

            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:NativeFixturePath' }"
            )

            $before = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

            $null = @(Import-CompleterSet -Path $script:SetPath)
            $null = TabExpansion2 -InputScript 'importfixture a' -CursorColumn 15
            (Get-CompleterRegistration -CommandName 'importfixture' -Native).State | Should -Be 'Active'
            Get-CompleterRegistration -ManagedOnly | Export-CompleterSet -Path (Join-Path -Path $script:SetRoot -ChildPath 'again.psd1')

            $after = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

            $before.Count | Should -BeGreaterThan 0
            $after | Should -Be $before
        }
    }

    It 'loads the about help topic for completer sets' {
        $help = Get-Help -Name 'about_Completer_Sets' -ErrorAction Stop

        $help.Name | Should -Be 'about_Completer_Sets'
        $help.Synopsis | Should -Match 'completer set'
    }
}
