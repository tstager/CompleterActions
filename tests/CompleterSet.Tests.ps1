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
    $script:SetFixtureRoot = Join-Path -Path $script:FixtureRoot -ChildPath 'CompleterSet'
    $script:HashFixturePath = Join-Path -Path $script:SetFixtureRoot -ChildPath 'HashFixture.ps1'
    $script:NoHashFixtureRoot = Join-Path -Path $script:SetFixtureRoot -ChildPath 'NoHash'
    $script:HashLinePattern = "^\s{12}Hash    = 'SHA256:[0-9A-F]{64}'$"
    $script:SetCleanupTargets = @(
        @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-LazyStrictSetTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-UnsafeTool'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-ImportedOne'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-ImportedTwo'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'importfixture'; CompleterType = 'Native' },
        @{ CommandName = 'importfixture.exe'; CompleterType = 'Native' },
        @{ CommandName = 'hashfixture'; CompleterType = 'Native' },
        @{ CommandName = 'HashFixture.exe'; CompleterType = 'Native' },
        @{ CommandName = 'setfixturealpha'; CompleterType = 'Native' },
        @{ CommandName = 'setfixturealpha.exe'; CompleterType = 'Native' },
        @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'setfixtureprobe'; CompleterType = 'Native' },
        @{ CommandName = 'setfixtureextra'; CompleterType = 'Native' },
        @{ CommandName = 'setfixtureforged'; CompleterType = 'Native' }
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
            $data.Entries[0].Path | Should -Be 'scripts/Native.ps1' -Because 'a forward slash keeps the set file portable across platforms'
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

        It 'refuses a strict subset registration that Import-CompleterSet could not read back and writes nothing' {
            $subset = Register-Completer -LiteralPath $script:NativeFixturePath -Lazy -CommandName 'importfixture.exe' -Native -PassThru
            $subset.State | Should -Be 'Pending'

            $thrown = { $subset | Export-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match ([regex]::Escape("The strict entry for '$script:NativeFixturePath' cannot be imported as a set entry"))
            $thrown.Exception.Message | Should -Match "Missing: 'importfixture'\."
            $thrown.Exception.Message | Should -Not -Match 'importfixture\.exe'
            $thrown.Exception.Message | Should -Match 'Nothing was written'
            Test-Path -LiteralPath $script:SetPath | Should -BeFalse

            { Export-CompleterSet -Path $script:SetPath } | Should -Throw "*Missing: 'importfixture'.*" -Because 'the default export of every managed registration hits the same rule'
            Test-Path -LiteralPath $script:SetPath | Should -BeFalse

            $null = Register-Completer -LiteralPath $script:NativeFixturePath -Lazy -CommandName 'importfixture' -Native -PassThru
            Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            @($data.Entries).Count | Should -Be 1
            @($data.Entries[0].Targets.CommandName | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')

            Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false
            $reimported = @(Import-CompleterSet -LiteralPath $script:SetPath)
            @($reimported.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe')
        }

        It 'refuses a strict record for a target the script does not register' {
            $record = [pscustomobject] @{
                CommandName = 'importfixture.cmd'
                IsNative    = $true
                ScriptPath  = $script:NativeFixturePath
                Trusted     = $false
            }

            $thrown = { $record | Export-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match "Missing: 'importfixture', 'importfixture\.exe'\."
            $thrown.Exception.Message | Should -Match "Not registered by the script: 'importfixture\.cmd'\."
            Test-Path -LiteralPath $script:SetPath | Should -BeFalse
        }

        It 'exports a trusted subset registration as given and imports it back' {
            $subset = Register-Completer -LiteralPath $script:NativeFixturePath -Lazy -Trusted -CommandName 'importfixture.exe' -Native -PassThru

            $subset | Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            $data.Entries[0].Trusted | Should -BeTrue
            @($data.Entries[0].Targets.CommandName) | Should -Be @('importfixture.exe')

            $subset | Unregister-Completer -Confirm:$false
            $reimported = @(Import-CompleterSet -LiteralPath $script:SetPath)
            @($reimported.Key) | Should -Be @('importfixture.exe')
            $reimported[0].Trusted | Should -BeTrue
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

        It 'writes a Hash between Trusted and Targets for every strict and trusted entry' {
            $records = @(Import-CompleterScript -Path $script:HashFixturePath) +
                @(Import-CompleterScript -Path $script:ParameterFixturePath) +
                @(Import-CompleterScript -Path $script:TrustedFixturePath -Trusted)

            $records | Export-CompleterSet -Path $script:SetPath

            $lines = @(Get-Content -LiteralPath $script:SetPath)
            $hashIndexes = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^\s*Hash\s*=' })

            $hashIndexes.Count | Should -Be 3

            foreach ($hashIndex in $hashIndexes)
            {
                $lines[$hashIndex] | Should -MatchExactly $script:HashLinePattern
                $lines[$hashIndex - 1] | Should -MatchExactly '^\s{12}Trusted = \$(true|false)$'
                $lines[$hashIndex + 1] | Should -MatchExactly '^\s{12}Targets = @\($'
            }

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath

            foreach ($entry in $data.Entries)
            {
                $scriptPath = [System.IO.Path]::GetFullPath($entry.Path, $script:SetRoot)
                $expectedHash = & (Get-Module -Name 'CompleterActions') { param($LiteralPath) Get-CompleterScriptHash -LiteralPath $LiteralPath } $scriptPath

                $entry.Hash | Should -BeExactly $expectedHash -Because "the entry for '$scriptPath' hashes that script"
            }
        }

        It 'writes the 2.0.0 export text once the Hash lines are removed' {
            $setFolder = Join-Path -Path $script:SetRoot -ChildPath 'NoHash'
            Copy-Item -LiteralPath $script:NoHashFixtureRoot -Destination $setFolder -Recurse
            $outputPath = Join-Path -Path $setFolder -ChildPath 'completers.psd1'
            $expected = @(Get-Content -LiteralPath $outputPath)

            $records = @(Register-Completer -LiteralPath (Join-Path -Path $setFolder -ChildPath 'alpha_completer' -AdditionalChildPath 'alpha_completer.ps1') -Lazy -PassThru) +
                @(Register-Completer -LiteralPath (Join-Path -Path $setFolder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1') -Lazy -PassThru)

            $records | Export-CompleterSet -Path $outputPath

            $written = @(Get-Content -LiteralPath $outputPath)

            @($written | Where-Object { $_ -match '^\s*Hash\s*=' }).Count | Should -Be 2
            @($written | Where-Object { $_ -notmatch '^\s*Hash\s*=' }) | Should -BeExactly $expected -Because 'the checked-in NoHash set is what 2.0.0 wrote for the same records, and Hash is the only line 2.1.0 adds'
        }

        It 'hashes LF, CRLF, UTF-8 BOM plus CRLF, and lone-CR copies of one script to the same value' {
            $text = [System.IO.File]::ReadAllText($script:HashFixturePath).Replace("`r`n", "`n")
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            $variants = [ordered] @{
                'lf.ps1'       = $utf8.GetBytes($text)
                'crlf.ps1'     = $utf8.GetBytes($text.Replace("`n", "`r`n"))
                'bom-crlf.ps1' = [byte[]] (@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes($text.Replace("`n", "`r`n")))
                'cr.ps1'       = $utf8.GetBytes($text.Replace("`n", "`r"))
            }

            $hashes = foreach ($variantName in $variants.Keys)
            {
                $variantPath = Join-Path -Path $script:SetRoot -ChildPath $variantName
                [System.IO.File]::WriteAllBytes($variantPath, $variants[$variantName])

                & (Get-Module -Name 'CompleterActions') { param($LiteralPath) Get-CompleterScriptHash -LiteralPath $LiteralPath } $variantPath
            }

            @($variants.Values | ForEach-Object { [System.Convert]::ToBase64String($_) } | Select-Object -Unique).Count | Should -Be 4 -Because 'the four copies differ on disk'
            @($hashes).Count | Should -Be 4
            @($hashes | Select-Object -Unique).Count | Should -Be 1
            $hashes[0] | Should -MatchExactly '^SHA256:[0-9A-F]{64}$'
        }

        It 'hashes the checked-in hash fixture to its recorded literal' {
            # Cross-checked with: git cat-file blob :tests/Fixtures/CompleterSet/HashFixture.ps1 | sha256sum
            # The index blob is LF without a byte-order mark, which is the normalised
            # form the Hash describes, so the literal holds on CRLF and LF checkouts.
            $expectedHash = 'SHA256:170A3987A41EF7ED650911ED953487441C9EC47C1C7DD4C1C4096D469F66E6B1'

            $hash = & (Get-Module -Name 'CompleterActions') { param($LiteralPath) Get-CompleterScriptHash -LiteralPath $LiteralPath } $script:HashFixturePath

            $hash | Should -BeExactly $expectedHash

            Import-CompleterScript -Path $script:HashFixturePath | Export-CompleterSet -Path $script:SetPath

            (Import-PowerShellDataFile -LiteralPath $script:SetPath).Entries[0].Hash | Should -BeExactly $expectedHash
        }

        It "writes a strict entry's targets in script order and script casing when the records arrive in another order" {
            $null = Register-Completer -LiteralPath $script:HashFixturePath -Lazy -PassThru
            $sorted = @(Get-Completer -State Active, Pending, Failed, Stale | Where-Object { $_.CommandName -like 'hashfixture*' })

            @($sorted.CommandName) | Should -BeExactly @('hashfixture', 'HashFixture.exe') -Because 'Get-Completer sorts by CommandName, which is not the order the script registers them in'

            Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            @($data.Entries[0].Targets.CommandName) | Should -BeExactly @('HashFixture.exe', 'hashfixture')

            $reordered = @(
                [pscustomobject] @{ CommandName = 'HASHFIXTURE'; IsNative = $true; ScriptPath = $script:HashFixturePath; Trusted = $false }
                [pscustomobject] @{ CommandName = 'hashfixture.EXE'; IsNative = $true; ScriptPath = $script:HashFixturePath; Trusted = $false }
            )

            $reordered | Export-CompleterSet -Path $script:SetPath

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            @($data.Entries[0].Targets.CommandName) | Should -BeExactly @('HashFixture.exe', 'hashfixture')
            @($data.Entries[0].Targets.Native | Select-Object -Unique) | Should -Be @($true)
        }

        It 'writes a trusted entry whose script is missing without Hash, warns once, and still succeeds' {
            $missingPath = Join-Path -Path $script:SetRoot -ChildPath 'missing_completer.ps1'
            $records = @(Import-CompleterScript -Path $script:ParameterFixturePath) + @(
                [pscustomobject] @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name'; ScriptPath = $missingPath; Trusted = $true }
            )

            $written = $records | Export-CompleterSet -Path $script:SetPath -PassThru -WarningVariable exportWarnings -WarningAction SilentlyContinue

            $written.FullName | Should -Be $script:SetPath
            @($exportWarnings).Count | Should -Be 1
            [string] $exportWarnings[0] | Should -Match ('^' + [regex]::Escape("The script '$missingPath' could not be read, so its entry was written without a Hash. ") + '\S')

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            @($data.Entries).Count | Should -Be 2

            $trustedEntry = $data.Entries | Where-Object { $_.Trusted }
            $trustedEntry.ContainsKey('Hash') | Should -BeFalse
            $trustedEntry.Path | Should -Be 'missing_completer.ps1'
            @($trustedEntry.Targets.CommandName) | Should -Be @('Test-TrustedFixtureTool')

            ($data.Entries | Where-Object { -not $_.Trusted }).Hash | Should -MatchExactly '^SHA256:[0-9A-F]{64}$'
        }

        It 'reads each strict script once for both its targets and its hash' {
            $records = @(Import-CompleterScript -Path $script:NativeFixturePath) +
                @(Import-CompleterScript -Path $script:ParameterFixturePath) +
                @(Import-CompleterScript -Path $script:TrustedFixturePath -Trusted)

            & (Get-Module -Name 'CompleterActions') {
                $script:TestParseCount = 0
                $script:TestHashReadCount = 0
                $script:TestParseFunction = ${function:Get-CompleterScriptParseResult}
                $script:TestHashFunction = ${function:Get-CompleterScriptHash}

                function script:Get-CompleterScriptParseResult
                {
                    param($LiteralPath)

                    $script:TestParseCount++
                    & $script:TestParseFunction -LiteralPath $LiteralPath
                }

                function script:Get-CompleterScriptHash
                {
                    param($Text, $LiteralPath)

                    if ($PSBoundParameters.ContainsKey('LiteralPath'))
                    {
                        $script:TestHashReadCount++
                    }

                    & $script:TestHashFunction @PSBoundParameters
                }
            }

            $records | Export-CompleterSet -Path $script:SetPath

            $counts = & (Get-Module -Name 'CompleterActions') {
                [pscustomobject] @{
                    Parses    = $script:TestParseCount
                    HashReads = $script:TestHashReadCount
                }
            }

            $counts.Parses | Should -Be 2 -Because 'each of the two strict scripts is parsed once for its targets'
            $counts.HashReads | Should -Be 1 -Because 'only the trusted script is read for its hash; a strict script is hashed from its parse'

            $data = Import-PowerShellDataFile -LiteralPath $script:SetPath
            @($data.Entries | Where-Object { $_.Hash -match '^SHA256:[0-9A-F]{64}$' }).Count | Should -Be 3
        }
    }

    Context 'Import-CompleterSet' {
        It 'restores the same targets as Pending records after an Export then Import round trip and loads them on first tab' {
            $imported = @(Import-CompleterScript -Path $script:ParameterFixturePath) +
                @(Import-CompleterScript -Path $script:NativeFixturePath) +
                @(Import-CompleterScript -Path $script:TrustedFixturePath -Trusted)
            $imported | Export-CompleterSet -Path $script:SetPath

            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            @($registered.Key | Sort-Object) | Should -Be @($imported.Key | Sort-Object)
            $registered[0].PSTypeNames | Should -Contain 'CompleterActions.CompleterRegistration'
            @($registered.State | Select-Object -Unique) | Should -Be @('Pending')
            @((Get-Completer -State Active, Pending, Failed, Stale).Key | Sort-Object) | Should -Be @($imported.Key | Sort-Object)

            $trustedInput = 'Test-TrustedFixtureTool -Name trusted'
            $trustedCompletion = TabExpansion2 -InputScript $trustedInput -CursorColumn $trustedInput.Length
            $trustedCompletion.CompletionMatches.CompletionText | Should -Contain 'trusted-alpha'

            $nativeInput = 'importfixture a'
            $nativeCompletion = TabExpansion2 -InputScript $nativeInput -CursorColumn $nativeInput.Length
            $nativeCompletion.CompletionMatches.CompletionText | Should -Contain 'alpha'

            (Get-Completer -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name').State | Should -Be 'Active'
            (Get-Completer -CommandName 'importfixture' -Native).State | Should -Be 'Active'
            (Get-Completer -CommandName 'importfixture.exe' -Native).State | Should -Be 'Active'
            (Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name').State | Should -Be 'Pending'
        }

        It 'round-trips a lazily imported set through Get-Completer and Export-CompleterSet' {
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )
            $null = @(Import-CompleterSet -Path $script:SetPath)

            $exportPath = Join-Path -Path $script:SetRoot -ChildPath 'exported.psd1'
            Get-Completer -State Active, Pending, Failed, Stale | Export-CompleterSet -Path $exportPath

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

            Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false

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

            $failed = Get-Completer -CommandName 'Test-LazyStrictSetTool' -ParameterName 'Name'
            $failed.State | Should -Be 'Failed'
            $failed.IsRuntimeRegistered | Should -BeFalse
            $failed.ScriptPath | Should -Be $script:ThrowingStrictFixturePath
            $failed.LoadError | Should -Match 'CompleterActionsLazyFixtureMissing'
            Get-Completer -CommandName 'Test-LazyStrictSetTool' -ParameterName 'Name' -State Discovered, Conflicted | Should -BeNullOrEmpty

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

            $failed = Get-Completer -CommandName 'Test-UnsafeTool' -ParameterName 'Name'
            $failed.State | Should -Be 'Failed'
            $failed.LoadError | Should -Match 'does not conform to the strict import grammar'
            $failed.LoadError | Should -Match 'Get-Date'
            Get-Completer -CommandName 'Test-UnsafeTool' -ParameterName 'Name' -State Discovered, Conflicted | Should -BeNullOrEmpty
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

        It 'accepts a backslash separator in a relative path on every platform' {
            $scriptFolder = Join-Path -Path $script:SetRoot -ChildPath 'scripts'
            New-Item -Path $scriptFolder -ItemType Directory | Out-Null
            Copy-Item -LiteralPath $script:ParameterFixturePath -Destination (Join-Path -Path $scriptFolder -ChildPath 'Backslash.ps1')
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = 'scripts\Backslash.ps1' }"

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            $registered.Count | Should -Be 1
            $registered[0].ScriptPath | Should -Be (Join-Path -Path $scriptFolder -ChildPath 'Backslash.ps1')
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

            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
            Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
        }

        It 'reports a strict entry whose declared Targets do not match the script' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath'; Targets = @( @{ CommandName = 'Test-ImportedFixtureTool'; ParameterName = 'Other' } ) }"

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw "*The declared Targets do not match the script. Declared: 'Test-ImportedFixtureTool:Other'. Script registers: 'Test-ImportedFixtureTool:Name'.*"
            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
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
            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty

            $registered = @(Import-CompleterSet -Path $script:SetPath -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)

            @($registered.Key | Sort-Object) | Should -Be @('test-importedone:name', 'test-importedtwo:name')
            @($registered.Trusted | Select-Object -Unique) | Should -Be @($false)
            @($warnings | Where-Object { $_.Message -match "skipped Entry 2 \(.*\): Target 'Test-ImportedOne:Name' is also listed by entry 1\." }).Count | Should -Be 1
        }

        It 'reports targets that already carry a different registration up front and registers nothing without -Force' {
            $null = Register-Completer -LiteralPath $script:NativeFixturePath -Lazy -Trusted -CommandName 'importfixture' -Native
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:NativeFixturePath' }"
            )

            $thrown = { Import-CompleterSet -Path $script:SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match "Entry 2 \(.*ImportableNativeCompleter\.ps1.\): A module-managed completer registration already exists for 'importfixture'\. Use -Force to replace it\."
            $thrown.Exception.Message | Should -Not -Match 'Entry 1 \('
            Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty
            @((Get-Completer -State Active, Pending, Failed, Stale).Key) | Should -Be @('importfixture')

            $skipped = @(Import-CompleterSet -Path $script:SetPath -SkipInvalid -WarningAction SilentlyContinue)

            @($skipped.Key) | Should -Be @('test-importedfixturetool:name')
            (Get-Completer -CommandName 'importfixture' -Native).Trusted | Should -BeTrue

            $forced = @(Import-CompleterSet -Path $script:SetPath -Force)

            @($forced.Key | Sort-Object) | Should -Be @('importfixture', 'importfixture.exe', 'test-importedfixturetool:name')
            (Get-Completer -CommandName 'importfixture' -Native).Trusted | Should -BeFalse
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

            @(Get-Completer -State Active, Pending, Failed, Stale).Count | Should -Be 3
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

            (Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name').Source | Should -Be 'Managed'
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
            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty

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

            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
            Get-Completer -CommandName 'importfixture', 'importfixture.exe' -Native | Should -BeNullOrEmpty
            Get-Completer -CommandName 'Test-TrustedFixtureTool' -ParameterName 'Name' | Should -BeNullOrEmpty

            $restored = Get-Completer -CommandName 'Test-ImportedFixtureTool' -ParameterName 'Name'
            $restored.Source | Should -Be 'Discovered'
            [object]::ReferenceEquals($restored.ScriptBlock, $externalScriptBlock) | Should -BeTrue

            $inputScript = 'Test-ImportedFixtureTool -Name '
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            @($completion.CompletionMatches.CompletionText) | Should -Be @('external')
        }

        It 'returns the records in set order and keeps a reused record in its place' {
            $existing = Register-Completer -LiteralPath $script:ParameterFixturePath -Lazy -PassThru
            Write-TestCompleterSet -Path $script:SetPath -Entry @(
                "@{ Path = '$script:NativeFixturePath' }"
                "@{ Path = '$script:ParameterFixturePath' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            )

            $registered = @(Import-CompleterSet -Path $script:SetPath)

            @($registered.Key) | Should -Be @('importfixture', 'importfixture.exe', 'test-importedfixturetool:name', 'test-trustedfixturetool:name')
            [object]::ReferenceEquals($registered[2], $existing) | Should -BeTrue
            @($registered.State | Select-Object -Unique) | Should -Be @('Pending')
            @(Get-Completer -State Active, Pending, Failed, Stale).Count | Should -Be 4
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
            $counts.States | Should -Be 1 -Because 'the set resolves every target in one state pass'
        }

        It 'reads the set through Import-PowerShellDataFile only and never evaluates set content' {
            $probePath = Join-Path -Path $script:SetRoot -ChildPath 'probe.txt'
            Set-Content -LiteralPath $script:SetPath -Value "@{ Version = 1; Entries = @( (New-Item -ItemType File -Path '$probePath') ) }" -Encoding utf8

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*dynamic expressions*'

            Test-Path -LiteralPath $probePath | Should -BeFalse
            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty

            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath' }"
            Mock -CommandName 'Import-PowerShellDataFile' -ModuleName 'CompleterActions' -MockWith { throw 'reader sentinel' }

            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*reader sentinel*'
            Should -Invoke -CommandName 'Import-PowerShellDataFile' -ModuleName 'CompleterActions' -Times 1 -Exactly
        }

        It 'supports WhatIf without importing or registering anything' {
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:ParameterFixturePath' }"

            Import-CompleterSet -Path $script:SetPath -WhatIf | Should -BeNullOrEmpty

            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
        }

        It 'rejects files that are not .psd1 and sets without Version 1 or Entries' {
            $jsonPath = Join-Path -Path $script:SetRoot -ChildPath 'completers.json'
            Set-Content -LiteralPath $jsonPath -Value '{}' -Encoding utf8
            { Import-CompleterSet -Path $jsonPath } | Should -Throw '*must be .psd1 files*'

            Set-Content -LiteralPath $script:SetPath -Value "@{ Version = 2; Entries = @( @{ Path = '$script:ParameterFixturePath' } ) }" -Encoding utf8
            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*must declare Version = 1*'

            Set-Content -LiteralPath $script:SetPath -Value '@{ Version = 1; Entries = @() }' -Encoding utf8
            { Import-CompleterSet -Path $script:SetPath } | Should -Throw '*has no Entries*'

            Get-Completer -State Active, Pending, Failed, Stale | Should -BeNullOrEmpty
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
            (Get-Completer -CommandName 'importfixture' -Native).State | Should -Be 'Active'
            Get-Completer -State Active, Pending, Failed, Stale | Export-CompleterSet -Path (Join-Path -Path $script:SetRoot -ChildPath 'again.psd1')

            $after = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

            $before.Count | Should -BeGreaterThan 0
            $after | Should -Be $before
        }
    }

    Context 'Import-CompleterSet fast path' {
        BeforeAll {
            function Build-TestHashedSet
            {
                $setFolder = Join-Path -Path $script:SetRoot -ChildPath 'NoHash'
                Copy-Item -LiteralPath $script:NoHashFixtureRoot -Destination $setFolder -Recurse
                $alphaPath = Join-Path -Path $setFolder -ChildPath 'alpha_completer' -AdditionalChildPath 'alpha_completer.ps1'
                $betaPath = Join-Path -Path $setFolder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1'
                $setPath = Join-Path -Path $setFolder -ChildPath 'completers.psd1'

                @(
                    [pscustomobject] @{ CommandName = 'setfixturealpha'; IsNative = $true; ScriptPath = $alphaPath; Trusted = $false }
                    [pscustomobject] @{ CommandName = 'setfixturealpha.exe'; IsNative = $true; ScriptPath = $alphaPath; Trusted = $false }
                    [pscustomobject] @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name'; ScriptPath = $betaPath; Trusted = $false }
                ) | Export-CompleterSet -Path $setPath

                $data = Import-PowerShellDataFile -LiteralPath $setPath

                [pscustomobject] @{
                    Folder    = $setFolder
                    SetPath   = $setPath
                    AlphaPath = $alphaPath
                    BetaPath  = $betaPath
                    AlphaHash = $data.Entries[0].Hash
                    BetaHash  = $data.Entries[1].Hash
                }
            }

            function Get-TestExpectedRecordText
            {
                param(
                    [Parameter(Mandatory)]
                    [psobject] $Set
                )

                @(
                    "setfixturealpha|setfixturealpha|Pending|$($Set.AlphaPath)|False"
                    "setfixturealpha.exe|setfixturealpha.exe|Pending|$($Set.AlphaPath)|False"
                    "test-setfixturebeta:name|Test-SetFixtureBeta:Name|Pending|$($Set.BetaPath)|False"
                )
            }

            function ConvertTo-TestRecordText
            {
                param(
                    [Parameter()]
                    [object[]] $Record
                )

                @($Record | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.Key, $_.RuntimeKey, $_.State, $_.ScriptPath, $_.Trusted })
            }

            function Enable-TestParseCounter
            {
                & (Get-Module -Name 'CompleterActions') {
                    $script:TestTargetCalls = [System.Collections.Generic.List[string]]::new()
                    $script:TestParseCalls = [System.Collections.Generic.List[string]]::new()
                    $script:TestTargetFunction = ${function:Get-CompleterScriptTarget}
                    $script:TestParseFunction = ${function:Get-CompleterScriptParseResult}

                    function script:Get-CompleterScriptTarget
                    {
                        param($LiteralPath, $ParseResult)

                        $script:TestTargetCalls.Add($LiteralPath)
                        & $script:TestTargetFunction @PSBoundParameters
                    }

                    function script:Get-CompleterScriptParseResult
                    {
                        param($LiteralPath)

                        $script:TestParseCalls.Add($LiteralPath)
                        & $script:TestParseFunction @PSBoundParameters
                    }
                }
            }

            function Get-TestParseCall
            {
                & (Get-Module -Name 'CompleterActions') {
                    [pscustomobject] @{
                        Targets = @($script:TestTargetCalls)
                        Parses  = @($script:TestParseCalls)
                    }
                }
            }

            function Invoke-TestVerboseImport
            {
                param(
                    [Parameter(Mandatory)]
                    [string[]] $LiteralPath
                )

                $output = @(Import-CompleterSet -LiteralPath $LiteralPath -Verbose 4>&1)

                [pscustomobject] @{
                    Records = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                    Verbose = @(
                        $output |
                            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^(Entry \d+ |Completer set )' } |
                            ForEach-Object { $_.Message }
                    )
                }
            }

            function Clear-TestSetHashLine
            {
                param(
                    [Parameter(Mandatory)]
                    [string] $LiteralPath
                )

                $lines = @(Get-Content -LiteralPath $LiteralPath | Where-Object { $_ -notmatch '^\s*Hash\s*=' })
                Set-Content -LiteralPath $LiteralPath -Value $lines -Encoding utf8
            }
        }

        It 'imports the checked-in set without Hash with the records 2.0.0 produced' {
            $setFolder = Join-Path -Path $script:SetRoot -ChildPath 'NoHash'
            Copy-Item -LiteralPath $script:NoHashFixtureRoot -Destination $setFolder -Recurse
            $setPath = Join-Path -Path $setFolder -ChildPath 'completers.psd1'
            $alphaPath = Join-Path -Path $setFolder -ChildPath 'alpha_completer' -AdditionalChildPath 'alpha_completer.ps1'
            $betaPath = Join-Path -Path $setFolder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1'
            Enable-TestParseCounter

            $output = @(Import-CompleterSet -LiteralPath $setPath -Verbose -WarningVariable importWarnings -ErrorVariable importErrors 4>&1)
            $succeeded = $?

            $succeeded | Should -BeTrue
            @($importWarnings).Count | Should -Be 0
            @($importErrors).Count | Should -Be 0

            $records = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
            ConvertTo-TestRecordText -Record $records | Should -BeExactly @(
                "setfixturealpha|setfixturealpha|Pending|$alphaPath|False"
                "setfixturealpha.exe|setfixturealpha.exe|Pending|$alphaPath|False"
                "test-setfixturebeta:name|Test-SetFixtureBeta:Name|Pending|$betaPath|False"
            )

            $calls = Get-TestParseCall
            $calls.Targets | Should -Be @($alphaPath, $betaPath)
            $calls.Parses | Should -Be @($alphaPath, $betaPath)

            $verbose = @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^Entry \d+ ' } | ForEach-Object { $_.Message })
            $verbose | Should -BeExactly @(
                "Entry 1 ('alpha_completer/alpha_completer.ps1'): no hash; parsed the script."
                "Entry 2 ('beta_completer/beta_completer.ps1'): no hash; parsed the script."
            )
        }

        It 'skips the parse for every strict entry whose Hash matches' {
            $set = Build-TestHashedSet
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $set.SetPath

            $calls = Get-TestParseCall
            $calls.Targets.Count | Should -Be 0
            $calls.Parses.Count | Should -Be 0
            $result.Verbose | Should -BeExactly @(
                "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash matches; targets read from the set."
                "Entry 2 ('beta_completer/beta_completer.ps1'): hash matches; targets read from the set."
                "Completer set '$($set.SetPath)': 2 entries from the hash, 0 parsed, 0 trusted."
            )
            ConvertTo-TestRecordText -Record $result.Records | Should -BeExactly (Get-TestExpectedRecordText -Set $set)
        }

        It 'parses only the strict entry whose script changed since export' {
            $set = Build-TestHashedSet
            Add-Content -LiteralPath $set.AlphaPath -Value '# Edited after the set was exported.' -Encoding utf8
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $set.SetPath

            $calls = Get-TestParseCall
            $calls.Targets | Should -Be @($set.AlphaPath)
            $calls.Parses | Should -Be @($set.AlphaPath)
            $result.Verbose[0] | Should -BeExactly "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash differs; parsed the script."
            $result.Verbose[1] | Should -BeExactly "Entry 2 ('beta_completer/beta_completer.ps1'): hash matches; targets read from the set."
            ConvertTo-TestRecordText -Record $result.Records | Should -BeExactly (Get-TestExpectedRecordText -Set $set)
        }

        It 'parses every strict entry of the same set once its Hash lines are removed' {
            $set = Build-TestHashedSet
            Clear-TestSetHashLine -LiteralPath $set.SetPath
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $set.SetPath

            $calls = Get-TestParseCall
            $calls.Targets | Should -Be @($set.AlphaPath, $set.BetaPath)
            $calls.Parses | Should -Be @($set.AlphaPath, $set.BetaPath)
            $result.Verbose | Should -BeExactly @(
                "Entry 1 ('alpha_completer/alpha_completer.ps1'): no hash; parsed the script."
                "Entry 2 ('beta_completer/beta_completer.ps1'): no hash; parsed the script."
                "Completer set '$($set.SetPath)': 0 entries from the hash, 2 parsed, 0 trusted."
            )
        }

        It 'returns the same records from the hashed, edited, and unhashed runs' {
            $set = Build-TestHashedSet

            $hashed = ConvertTo-TestRecordText -Record @(Import-CompleterSet -LiteralPath $set.SetPath)
            Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false

            Add-Content -LiteralPath $set.AlphaPath -Value '# Edited after the set was exported.' -Encoding utf8
            $edited = ConvertTo-TestRecordText -Record @(Import-CompleterSet -LiteralPath $set.SetPath)
            Get-Completer -State Active, Pending, Failed, Stale | Unregister-Completer -Confirm:$false

            Clear-TestSetHashLine -LiteralPath $set.SetPath
            $unhashed = ConvertTo-TestRecordText -Record @(Import-CompleterSet -LiteralPath $set.SetPath)

            $hashed | Should -BeExactly (Get-TestExpectedRecordText -Set $set)
            $edited | Should -BeExactly $hashed
            $unhashed | Should -BeExactly $hashed
        }

        It 'follows declared order and first casing for a hand-edited entry whose Hash still matches' {
            $set = Build-TestHashedSet
            Write-TestCompleterSet -Path $set.SetPath -Entry (
                "@{ Path = 'alpha_completer/alpha_completer.ps1'; Trusted = `$false; Hash = '$($set.AlphaHash)'; " +
                "Targets = @( @{ CommandName = 'SetFixtureAlpha.EXE'; Native = `$true }, @{ CommandName = 'setfixturealpha'; Native = `$true }, @{ CommandName = 'setfixturealpha.exe'; Native = `$true } ) }"
            )
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $set.SetPath

            $calls = Get-TestParseCall
            $calls.Targets.Count | Should -Be 0
            $calls.Parses.Count | Should -Be 0
            $result.Verbose[0] | Should -BeExactly "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash matches; targets read from the set."
            ConvertTo-TestRecordText -Record $result.Records | Should -BeExactly @(
                "setfixturealpha.exe|SetFixtureAlpha.EXE|Pending|$($set.AlphaPath)|False"
                "setfixturealpha|setfixturealpha|Pending|$($set.AlphaPath)|False"
            )
        }

        It 'treats a <Case> Hash as absent and parses the script without a problem' -TestCases @(
            @{ Case = 'SHA512:abc'; HashText = "'SHA512:abc'" }
            @{ Case = 'SHA256: plus 63 digits'; HashText = "'SHA256:$('A' * 63)'" }
            @{ Case = 'non-string 42'; HashText = '42' }
        ) {
            $set = Build-TestHashedSet
            Write-TestCompleterSet -Path $set.SetPath -Entry (
                "@{ Path = 'alpha_completer/alpha_completer.ps1'; Hash = $HashText; " +
                "Targets = @( @{ CommandName = 'setfixturealpha'; Native = `$true }, @{ CommandName = 'setfixturealpha.exe'; Native = `$true } ) }"
            )
            Enable-TestParseCounter

            $output = @(Import-CompleterSet -LiteralPath $set.SetPath -Verbose -WarningVariable importWarnings -ErrorVariable importErrors 4>&1)
            $succeeded = $?

            $succeeded | Should -BeTrue
            @($importWarnings).Count | Should -Be 0
            @($importErrors).Count | Should -Be 0

            $calls = Get-TestParseCall
            $calls.Targets | Should -Be @($set.AlphaPath)
            $calls.Parses | Should -Be @($set.AlphaPath)

            $verbose = @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^Entry \d+ ' } | ForEach-Object { $_.Message })
            $verbose | Should -BeExactly "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash not recognised; parsed the script."

            $records = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
            @($records.Key) | Should -BeExactly @('setfixturealpha', 'setfixturealpha.exe')
        }

        It 'still reports <Case> on the fast path' -TestCases @(
            @{
                Case       = 'a missing file'
                Mutation   = 'MissingFile'
                Pattern    = 'Entry 2 \(''beta_completer/beta_completer\.ps1''\): The file ''.*beta_completer\.ps1'' does not exist\.'
                Parses     = 0
                Registered = 0
            }
            @{
                Case       = 'a malformed target'
                Mutation   = 'MalformedTarget'
                Pattern    = 'Entry 2 \(''beta_completer/beta_completer\.ps1''\): Target ''Test-SetFixtureBeta'' must declare Native = \$true or a ParameterName\.'
                Parses     = 1
                Registered = 0
            }
            @{
                Case       = 'a target listed by two entries'
                Mutation   = 'DuplicateTarget'
                Pattern    = 'Entry 3 \(''alpha_completer/alpha_completer\.ps1''\): Target ''setfixturealpha'' is also listed by entry 1\.'
                Parses     = 0
                Registered = 0
            }
            @{
                Case       = 'an existing registration without -Force'
                Mutation   = 'Conflict'
                Pattern    = 'Entry 1 \(''alpha_completer/alpha_completer\.ps1''\): A module-managed completer registration already exists for ''setfixturealpha''\. Use -Force to replace it\.'
                Parses     = 0
                Registered = 1
            }
        ) {
            $set = Build-TestHashedSet

            switch ($Mutation)
            {
                'MissingFile'
                {
                    Remove-Item -LiteralPath $set.BetaPath
                }
                'MalformedTarget'
                {
                    $lines = @(Get-Content -LiteralPath $set.SetPath) -replace "; ParameterName = 'Name'", ''
                    Set-Content -LiteralPath $set.SetPath -Value $lines -Encoding utf8
                }
                'DuplicateTarget'
                {
                    $alphaEntry = "@{ Path = 'alpha_completer/alpha_completer.ps1'; Hash = '$($set.AlphaHash)'; Targets = @( @{ CommandName = 'setfixturealpha'; Native = `$true }, @{ CommandName = 'setfixturealpha.exe'; Native = `$true } ) }"
                    Write-TestCompleterSet -Path $set.SetPath -Entry @(
                        $alphaEntry
                        "@{ Path = 'beta_completer/beta_completer.ps1'; Hash = '$($set.BetaHash)'; Targets = @( @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name' } ) }"
                        $alphaEntry
                    )
                }
                'Conflict'
                {
                    $null = Register-Completer -LiteralPath $set.AlphaPath -Lazy -Trusted -CommandName 'setfixturealpha' -Native
                }
            }

            Enable-TestParseCounter

            $thrown = { Import-CompleterSet -LiteralPath $set.SetPath } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -Match 'has 1 invalid entry and nothing was registered'
            $thrown.Exception.Message | Should -Match $Pattern

            $calls = Get-TestParseCall
            $calls.Targets.Count | Should -Be $Parses
            $calls.Parses.Count | Should -Be $Parses
            @(Get-Completer -State Active, Pending, Failed, Stale).Count | Should -Be $Registered
        }

        It 'falls through to the parse path when the script cannot be read for the hash' {
            $set = Build-TestHashedSet
            Enable-TestParseCounter
            Mock -CommandName 'Get-CompleterScriptHash' -ModuleName 'CompleterActions' -MockWith { throw 'hash read sentinel' }

            $result = Invoke-TestVerboseImport -LiteralPath $set.SetPath

            Should -Invoke -CommandName 'Get-CompleterScriptHash' -ModuleName 'CompleterActions' -Times 2 -Exactly
            $calls = Get-TestParseCall
            $calls.Targets | Should -Be @($set.AlphaPath, $set.BetaPath)
            $calls.Parses | Should -Be @($set.AlphaPath, $set.BetaPath)
            $result.Verbose | Should -BeExactly @(
                "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash differs; parsed the script."
                "Entry 2 ('beta_completer/beta_completer.ps1'): hash differs; parsed the script."
                "Completer set '$($set.SetPath)': 0 entries from the hash, 2 parsed, 0 trusted."
            )
            ConvertTo-TestRecordText -Record $result.Records | Should -BeExactly (Get-TestExpectedRecordText -Set $set)
        }

        It 'writes one verbose line per entry and one summary line per set' {
            $set = Build-TestHashedSet
            $zeroHash = 'SHA256:' + ('0' * 64)
            Write-TestCompleterSet -Path $set.SetPath -Entry @(
                "@{ Path = 'alpha_completer/alpha_completer.ps1'; Hash = '$($set.AlphaHash)'; Targets = @( @{ CommandName = 'setfixturealpha'; Native = `$true }, @{ CommandName = 'setfixturealpha.exe'; Native = `$true } ) }"
                "@{ Path = 'beta_completer/beta_completer.ps1'; Hash = '$zeroHash'; Targets = @( @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name' } ) }"
                "@{ Path = '$script:ParameterFixturePath'; Hash = '$zeroHash' }"
                "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Hash = '$zeroHash'; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
                "@{ Path = 'missing_completer.ps1'; Hash = '$zeroHash'; Targets = @( @{ CommandName = 'setfixtureprobe'; Native = `$true } ) }"
            )
            $secondPath = Join-Path -Path $script:SetRoot -ChildPath 'second.psd1'
            Write-TestCompleterSet -Path $secondPath -Entry "@{ Path = '$script:HashFixturePath'; Targets = @( @{ CommandName = 'HashFixture.exe'; Native = `$true }, @{ CommandName = 'hashfixture'; Native = `$true } ) }"

            $output = @(Import-CompleterSet -LiteralPath $set.SetPath, $secondPath -SkipInvalid -Verbose -WarningAction SilentlyContinue 4>&1)

            $records = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
            $records.Count | Should -Be 7

            $verbose = @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^(Entry \d+ |Completer set )' } | ForEach-Object { $_.Message })
            $verbose | Should -BeExactly @(
                "Entry 1 ('alpha_completer/alpha_completer.ps1'): hash matches; targets read from the set."
                "Entry 2 ('beta_completer/beta_completer.ps1'): hash differs; parsed the script."
                "Entry 3 ('$script:ParameterFixturePath'): no Targets; parsed the script."
                "Entry 4 ('$script:TrustedFixturePath'): trusted; targets read from the set."
                "Completer set '$($set.SetPath)': 1 entries from the hash, 2 parsed, 1 trusted."
                "Entry 1 ('$script:HashFixturePath'): no hash; parsed the script."
                "Completer set '$secondPath': 0 entries from the hash, 1 parsed, 0 trusted."
            ) -Because 'an entry with a problem gets no line and is not counted'
        }

        It 'ignores Hash on a trusted entry and never reads its script' {
            $trustedHash = & (Get-Module -Name 'CompleterActions') { param($LiteralPath) Get-CompleterScriptHash -LiteralPath $LiteralPath } $script:TrustedFixturePath
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = '$script:TrustedFixturePath'; Trusted = `$true; Hash = '$trustedHash'; Targets = @( @{ CommandName = 'Test-TrustedFixtureTool'; ParameterName = 'Name' } ) }"
            Enable-TestParseCounter
            Mock -CommandName 'Get-CompleterScriptHash' -ModuleName 'CompleterActions' -MockWith { throw 'hash read sentinel' }

            $result = Invoke-TestVerboseImport -LiteralPath $script:SetPath

            Should -Invoke -CommandName 'Get-CompleterScriptHash' -ModuleName 'CompleterActions' -Times 0 -Exactly
            $calls = Get-TestParseCall
            $calls.Targets.Count | Should -Be 0
            $calls.Parses.Count | Should -Be 0
            $result.Verbose | Should -BeExactly @(
                "Entry 1 ('$script:TrustedFixturePath'): trusted; targets read from the set."
                "Completer set '$script:SetPath': 0 entries from the hash, 0 parsed, 1 trusted."
            )
            ConvertTo-TestRecordText -Record $result.Records | Should -BeExactly "test-trustedfixturetool:name|Test-TrustedFixtureTool:Name|Pending|$script:TrustedFixturePath|True"
        }

        It 'never executes a non-conforming script whose entry took the fast path' {
            $probeFolder = Join-Path -Path $script:SetRoot -ChildPath 'probe'
            New-Item -Path $probeFolder -ItemType Directory | Out-Null
            $probeScript = Join-Path -Path $probeFolder -ChildPath 'probe_completer.ps1'
            $probeFile = Join-Path -Path $script:SetRoot -ChildPath 'probe-executed.txt'
            Set-Content -LiteralPath $probeScript -Encoding utf8 -Value @(
                "New-Item -ItemType File -Path '$probeFile' | Out-Null"
                ''
                "Register-ArgumentCompleter -Native -CommandName 'setfixtureprobe' -ScriptBlock {"
                '    param($wordToComplete, $commandAst, $cursorPosition)'
                ''
                '    $null = $wordToComplete, $commandAst, $cursorPosition'
                ''
                "    [System.Management.Automation.CompletionResult]::new('probe', 'probe', 'ParameterValue', 'probe')"
                '}'
            )

            [pscustomobject] @{ CommandName = 'setfixtureprobe'; IsNative = $true; ScriptPath = $probeScript; Trusted = $false } | Export-CompleterSet -Path $script:SetPath
            (Import-PowerShellDataFile -LiteralPath $script:SetPath).Entries[0].Hash | Should -MatchExactly '^SHA256:[0-9A-F]{64}$' -Because 'the export derives targets without running the grammar walk'
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $script:SetPath

            $result.Verbose[0] | Should -BeExactly "Entry 1 ('probe/probe_completer.ps1'): hash matches; targets read from the set."
            $calls = Get-TestParseCall
            $calls.Parses.Count | Should -Be 0
            $result.Records[0].State | Should -Be 'Pending'
            Test-Path -LiteralPath $probeFile | Should -BeFalse

            $inputScript = 'setfixtureprobe p'
            $completion = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length
            @($completion.CompletionMatches.CompletionText) | Should -Not -Contain 'probe'

            $failed = Get-Completer -CommandName 'setfixtureprobe' -Native
            $failed.State | Should -Be 'Failed'
            $failed.LoadError | Should -Match 'does not conform to the strict import grammar'
            $failed.LoadError | Should -Match 'New-Item'
            Test-Path -LiteralPath $probeFile | Should -BeFalse
        }

        It 'fails a target the script does not register on its first press when a hand-written Hash matches' {
            $extraScript = Join-Path -Path $script:SetRoot -ChildPath 'extra_completer.ps1'
            Set-Content -LiteralPath $extraScript -Encoding utf8 -Value @(
                "Register-ArgumentCompleter -Native -CommandName 'setfixtureextra' -ScriptBlock {"
                '    param($wordToComplete, $commandAst, $cursorPosition)'
                ''
                '    $null = $wordToComplete, $commandAst, $cursorPosition'
                ''
                "    [System.Management.Automation.CompletionResult]::new('extra', 'extra', 'ParameterValue', 'extra')"
                '}'
            )
            $extraHash = & (Get-Module -Name 'CompleterActions') { param($LiteralPath) Get-CompleterScriptHash -LiteralPath $LiteralPath } $extraScript
            Write-TestCompleterSet -Path $script:SetPath -Entry "@{ Path = 'extra_completer.ps1'; Hash = '$extraHash'; Targets = @( @{ CommandName = 'setfixtureextra'; Native = `$true }, @{ CommandName = 'setfixtureforged'; Native = `$true } ) }"
            Enable-TestParseCounter

            $result = Invoke-TestVerboseImport -LiteralPath $script:SetPath

            $result.Verbose[0] | Should -BeExactly "Entry 1 ('extra_completer.ps1'): hash matches; targets read from the set."
            $calls = Get-TestParseCall
            $calls.Parses.Count | Should -Be 0
            @($result.Records.Key) | Should -BeExactly @('setfixtureextra', 'setfixtureforged')
            @($result.Records.State | Select-Object -Unique) | Should -Be @('Pending')

            $inputScript = 'setfixtureforged '
            $null = TabExpansion2 -InputScript $inputScript -CursorColumn $inputScript.Length

            $failed = Get-Completer -CommandName 'setfixtureforged' -Native
            $failed.State | Should -Be 'Failed'
            $failed.LoadError | Should -Match ([regex]::Escape("The script '$extraScript' did not register a completer for 'setfixtureforged'."))
        }
    }

    It 'loads the about help topic for completer sets' {
        $help = Get-Help -Name 'about_Completer_Sets' -ErrorAction Stop

        $help.Name | Should -Be 'about_Completer_Sets'
        $help.Synopsis | Should -Match 'completer set'
    }
}
