BeforeAll {
    # Save-CompleterScriptFile and New-CompleterScript both throw this text, so every test compares against this one format string.
    $script:AlreadyExistsFormat = "The file '{0}' already exists. Use -Force to overwrite it."
    $script:SelfCheckPrefix = 'New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. '

    $script:ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'

    # The section 2 skeleton block, character for character; <LINE2> and <SUBCOMMANDS> vary by case.
    $script:CargoSkeletonTemplate = @'
# cargo tab completion for PowerShell
<LINE2>

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name CargoCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:CargoCompletionCatalog = @{
<SUBCOMMANDS>
    }
}

function Complete-Cargo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Offer subcommands in the first argument position only; extend this function for options and values.
    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })
    if ($precedingElements.Count -gt 1) {
        return
    }

    foreach ($subcommand in $script:CargoCompletionCatalog.Subcommands) {
        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.Management.Automation.CompletionResult]::new($subcommand.Name, $subcommand.Name, 'ParameterValue', $subcommand.Description)
        }
    }
}

Register-ArgumentCompleter -Native -CommandName 'cargo', 'cargo.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cargo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
'@

    $script:CargoRows = @(
        [pscustomobject] @{ Name = 'build'; Description = 'Compile the current package' }
        [pscustomobject] @{ Name = 'check'; Description = "Analyze the current package and report errors, but don't build object files" }
    )

    # U+0027, U+2018, U+2019, U+201A, and U+201B, the single-quote characters the tokenizer accepts.
    $script:QuoteCharacters = @([char] 0x0027, [char] 0x2018, [char] 0x2019, [char] 0x201A, [char] 0x201B | ForEach-Object { [string] $_ })
}

Describe 'Completer script skeleton' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null

        # TestDrive lasts for the whole Describe, so each test writes into a folder of its own.
        $script:CaseFolder = Join-Path -Path $TestDrive -ChildPath ('case-{0}' -f [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:CaseFolder
    }

    AfterEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'builds the target list <Expected> from <CommandName>' -TestCases @(
        @{ CommandName = @('rg'); Expected = @('rg', 'rg.exe') }
        @{ CommandName = @('rg', 'rg.exe'); Expected = @('rg', 'rg.exe') }
        @{ CommandName = @('python3.12'); Expected = @('python3.12', 'python3.12.exe') }
        @{ CommandName = @('npm.cmd'); Expected = @('npm.cmd') }
        @{ CommandName = @('rg.exe'); Expected = @('rg.exe') }
        @{ CommandName = @('RG', 'rg'); Expected = @('RG', 'RG.exe') }
        @{ CommandName = @('tool.COM'); Expected = @('tool.COM') }
        @{ CommandName = @('x.bat'); Expected = @('x.bat') }
        @{ CommandName = @('y.ps1'); Expected = @('y.ps1') }
    ) {
        $actual = @(InModuleScope -ModuleName 'CompleterActions' -Parameters @{ CommandName = $CommandName } -ScriptBlock {
                param($CommandName)

                ConvertTo-CompleterTargetName -CommandName $CommandName
            })

        $actual.Count | Should -Be $Expected.Count
        ($actual -join '|') | Should -BeExactly ($Expected -join '|')
    }

    It 'rejects the command name <Name>' -TestCases @(
        @{ Name = '_' }
        @{ Name = '__' }
        @{ Name = 'foo.' }
        @{ Name = '-x' }
        @{ Name = 'a b' }
        @{ Name = 'C:\tools\rg' }
        @{ Name = 'rg*' }
        @{ Name = '.x' }
        @{ Name = 'x-' }
        @{ Name = '_.exe' }
    ) {
        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
                param($Name)

                ConvertTo-CompleterTargetName -CommandName 'rg', $Name
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ("'{0}' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." -f $Name)
    }

    It 'derives the stem <Stem> from <Name>' -TestCases @(
        @{ Name = 'rg'; Stem = 'Rg' }
        @{ Name = 'rg.exe'; Stem = 'Rg' }
        @{ Name = 'cargo-binstall'; Stem = 'CargoBinstall' }
        @{ Name = 'oh-my-posh'; Stem = 'OhMyPosh' }
        @{ Name = 'DSC'; Stem = 'DSC' }
        @{ Name = '7z'; Stem = '7z' }
        @{ Name = 'npm.cmd'; Stem = 'Npm' }
        @{ Name = 'TOOL.BAT'; Stem = 'TOOL' }
        @{ Name = 'x.ps1'; Stem = 'X' }
        @{ Name = 'y.com'; Stem = 'Y' }
    ) {
        $actual = InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
            param($Name)

            ConvertTo-CompleterScriptStem -Name $Name
        }

        $actual | Should -BeExactly $Stem
    }

    It 'doubles every single-quote character the tokenizer accepts' {
        $value = 'a{0}b{1}c{2}d{3}e{4}f' -f $script:QuoteCharacters

        $escaped = InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Value = $value } -ScriptBlock {
            param($Value)

            ConvertTo-CompleterSingleQuotedText -Value $Value
        }

        $doubled = @($script:QuoteCharacters | ForEach-Object { $_ + $_ })
        $escaped | Should -BeExactly ('a{0}b{1}c{2}d{3}e{4}f' -f $doubled)

        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput("'$escaped'", [ref] $null, [ref] $parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value | Should -BeExactly $value
    }

    It 'writes line 1 with the primary name as given for rg.exe' {
        $lines = @(InModuleScope -ModuleName 'CompleterActions' -ScriptBlock {
                Get-CompleterScriptSkeleton -Name 'rg.exe' -Stem (ConvertTo-CompleterScriptStem -Name 'rg.exe') -Target @(ConvertTo-CompleterTargetName -CommandName 'rg.exe') -Subcommand @()
            })

        $lines[0] | Should -BeExactly '# rg.exe tab completion for PowerShell'
    }

    It 'writes line 2 for <Case>' -TestCases @(
        @{
            Case       = 'probe'
            SeedKind   = 'Probe'
            Rows       = 'cargo'
            Line2      = "# Help-seeded native completer: the subcommand table was read from 'cargo --help' when the script was generated."
        }
        @{
            Case       = 'help text'
            SeedKind   = 'HelpText'
            Rows       = 'cargo'
            Line2      = '# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.'
        }
        @{
            Case       = 'empty table'
            SeedKind   = 'Probe'
            Rows       = 'none'
            Line2      = '# Native completer skeleton: add subcommands to the table and options to Complete-Cargo.'
        }
    ) {
        $subcommand = @(if ($Rows -eq 'cargo') { $script:CargoRows })
        $parameters = @{ SeedKind = $SeedKind; Subcommand = $subcommand }

        $lines = @(InModuleScope -ModuleName 'CompleterActions' -Parameters $parameters -ScriptBlock {
                param($SeedKind, $Subcommand)

                $skeletonParameters = @{
                    Name       = 'cargo'
                    Stem       = ConvertTo-CompleterScriptStem -Name 'cargo'
                    Target     = @(ConvertTo-CompleterTargetName -CommandName 'cargo')
                    Subcommand = @($Subcommand)
                    SeedKind   = $SeedKind
                }

                if ($SeedKind -eq 'Probe')
                {
                    $skeletonParameters['ProbeArgument'] = '--help'
                }

                Get-CompleterScriptSkeleton @skeletonParameters
            })

        $lines[1] | Should -BeExactly $Line2

        $subcommandText = if ($Rows -eq 'cargo')
        {
            @(
                '        Subcommands = @('
                "            @{ Name = 'build'; Description = 'Compile the current package' }"
                "            @{ Name = 'check'; Description = 'Analyze the current package and report errors, but don''t build object files' }"
                '        )'
            ) -join "`n"
        }
        else
        {
            '        Subcommands = @()'
        }

        $expected = @($script:CargoSkeletonTemplate.Replace('<LINE2>', $Line2).Replace('<SUBCOMMANDS>', $subcommandText) -split '\r?\n')
        $lines.Count | Should -Be $expected.Count
        ($lines -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'writes an empty table as Subcommands = @()' {
        $lines = @(InModuleScope -ModuleName 'CompleterActions' -ScriptBlock {
                Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @() -SeedKind 'HelpText'
            })

        @($lines | Where-Object { $_ -ceq '        Subcommands = @()' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -clike '*Subcommands = @(' -or $_ -clike '*@{ Name = *' }).Count | Should -Be 0
    }

    It 'writes a skeleton that Get-CompleterScriptFinding accepts and Get-CompleterScriptTarget reads back for <Case>' -TestCases @(
        @{
            Case        = 'empty table'
            CommandName = @('rg')
            Expected    = @('rg', 'rg.exe')
            Rows        = 'none'
        }
        @{
            Case        = '7z stem'
            CommandName = @('7z')
            Expected    = @('7z', '7z.exe')
            Rows        = 'one'
        }
        @{
            Case        = 'a tooltip containing all five quote characters'
            CommandName = @('quotetool', 'quotetool.cmd')
            Expected    = @('quotetool', 'quotetool.exe', 'quotetool.cmd')
            Rows        = 'quotes'
        }
    ) {
        $description = 'say {0}hello{1} and {2}bye{3} {4}now' -f $script:QuoteCharacters
        $subcommand = @(switch ($Rows)
        {
            'one' { [pscustomobject] @{ Name = 'a'; Description = 'Add files to archive' } }
            'quotes' { [pscustomobject] @{ Name = 'say'; Description = $description } }
        })

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath ('{0}_completer.ps1' -f $CommandName[0])
        $parameters = @{ CommandName = $CommandName; Subcommand = $subcommand; ScriptPath = $scriptPath }

        $result = InModuleScope -ModuleName 'CompleterActions' -Parameters $parameters -ScriptBlock {
            param($CommandName, $Subcommand, $ScriptPath)

            $stem = ConvertTo-CompleterScriptStem -Name $CommandName[0]
            $lines = Get-CompleterScriptSkeleton -Name $CommandName[0] -Stem $stem -Target @(ConvertTo-CompleterTargetName -CommandName $CommandName) -Subcommand @($Subcommand) -SeedKind 'HelpText'
            Set-Content -LiteralPath $ScriptPath -Value $lines -Encoding utf8

            [pscustomobject] @{
                Stem     = $stem
                Findings = @(Get-CompleterScriptFinding -LiteralPath $ScriptPath)
                Targets  = @(Get-CompleterScriptTarget -LiteralPath $ScriptPath)
            }
        }

        $result.Findings | Should -BeNullOrEmpty
        @($result.Targets | Where-Object { -not $_.IsNative }).Count | Should -Be 0
        (@($result.Targets.CommandName) -join '|') | Should -BeExactly ($Expected -join '|')

        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $null, [ref] $parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false).Name | Should -BeExactly ('Complete-{0}' -f $result.Stem)

        if ($Rows -eq 'quotes')
        {
            $stringValues = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object Value)
            $stringValues | Should -Contain $description
            @($stringValues | Where-Object { $_ -ceq $description }).Count | Should -Be 1
        }
    }

    It 'writes UTF-8 without a byte-order mark, platform newlines, and a final newline, identically twice' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cafe_completer.ps1'
        $parameters = @{ ScriptPath = $scriptPath }

        $result = InModuleScope -ModuleName 'CompleterActions' -Parameters $parameters -ScriptBlock {
            param($ScriptPath)

            $subcommand = @([pscustomobject] @{ Name = 'order'; Description = "Order a caf$([char] 0x00E9) cr$([char] 0x00E8)me" })
            $lines = @(Get-CompleterScriptSkeleton -Name 'cafe' -Stem 'Cafe' -Target 'cafe', 'cafe.exe' -Subcommand $subcommand -SeedKind 'HelpText')

            $first = Save-CompleterScriptFile -Line $lines -LiteralPath $ScriptPath -ExpectedTarget 'cafe', 'cafe.exe'
            $firstBytes = [System.IO.File]::ReadAllBytes($ScriptPath)
            $second = Save-CompleterScriptFile -Line $lines -LiteralPath $ScriptPath -ExpectedTarget 'cafe', 'cafe.exe' -Force
            $secondBytes = [System.IO.File]::ReadAllBytes($ScriptPath)

            [pscustomobject] @{
                Lines       = $lines
                First       = $first
                Second      = $second
                FirstBytes  = $firstBytes
                SecondBytes = $secondBytes
            }
        }

        $result.First | Should -BeOfType ([System.IO.FileInfo])
        $result.First.FullName | Should -Be $scriptPath
        $result.Second.FullName | Should -Be $scriptPath

        $bytes = $result.FirstBytes
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse

        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $text | Should -BeExactly ((@($result.Lines) -join [System.Environment]::NewLine) + [System.Environment]::NewLine)

        if ([System.Environment]::NewLine -eq "`n")
        {
            $text.Contains("`r") | Should -BeFalse
        }

        [System.Convert]::ToBase64String($result.SecondBytes) | Should -BeExactly ([System.Convert]::ToBase64String($bytes))
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It 'fails without -Force when the file appeared before the move, and leaves it unchanged' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        # The file appears while the temporary file is checked, after any check a caller made before the call.
        Mock -CommandName 'Get-CompleterScriptFinding' -ModuleName 'CompleterActions' -MockWith {
            [System.IO.File]::WriteAllText(($LiteralPath -replace '\.[0-9a-f]{8}\.tmp\z', ''), 'existing content')
        }

        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ ScriptPath = $scriptPath } -ScriptBlock {
                param($ScriptPath)

                $lines = @(Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @())
                Save-CompleterScriptFile -Line $lines -LiteralPath $ScriptPath -ExpectedTarget 'rg', 'rg.exe'
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ($script:AlreadyExistsFormat -f $scriptPath)
        Should -Invoke -CommandName 'Get-CompleterScriptFinding' -ModuleName 'CompleterActions' -Times 1 -Exactly
        [System.IO.File]::ReadAllText($scriptPath) | Should -BeExactly 'existing content'
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It 'resolves a relative path against the current location' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        Push-Location -LiteralPath $script:CaseFolder
        try
        {
            $written = InModuleScope -ModuleName 'CompleterActions' -ScriptBlock {
                $lines = @(Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @())
                Save-CompleterScriptFile -Line $lines -LiteralPath 'rg_completer.ps1' -ExpectedTarget 'rg', 'rg.exe'
            }
        }
        finally
        {
            Pop-Location
        }

        $written.FullName | Should -Be $scriptPath
        Test-Path -LiteralPath $scriptPath | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It 'deletes the temporary file and throws the self-check text for a non-conforming line list' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ ScriptPath = $scriptPath } -ScriptBlock {
                param($ScriptPath)

                $lines = [System.Collections.Generic.List[string]]::new()
                $lines.AddRange([string[]] @(Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @()))
                $lines.Insert(4, '$script:RgCompletionCatalog = @{ Subcommands = @() }')
                Save-CompleterScriptFile -Line $lines.ToArray() -LiteralPath $ScriptPath -ExpectedTarget 'rg', 'rg.exe'
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ($script:SelfCheckPrefix + 'The script uses a top-level assignment.')
        Test-Path -LiteralPath $scriptPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 0
    }

    It 'reports a target mismatch through the self-check text' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ ScriptPath = $scriptPath } -ScriptBlock {
                param($ScriptPath)

                $lines = @(Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @())
                Save-CompleterScriptFile -Line $lines -LiteralPath $ScriptPath -ExpectedTarget 'rg'
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ($script:SelfCheckPrefix + "The script registers 'rg', 'rg.exe', not 'rg'.")
        Test-Path -LiteralPath $scriptPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 0
    }
}

Describe 'New-CompleterScript' {
    BeforeAll {
        $script:CaptureFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\NewCompleterScript'
        $script:PwshApplicationPath = (Get-Command -Name 'pwsh' -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
        $script:SkeletonLine2Format = '# Native completer skeleton: add subcommands to the table and options to Complete-{0}.'
        $script:HelpTextLine2 = '# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.'

        # Copies cmd.exe and rewrites the UInt16 Subsystem field at e_lfanew + 92.
        function New-TestPatchedExe
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only writes a file in TestDrive.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string] $Path,

                [Parameter(Mandatory)]
                [int] $Subsystem
            )

            $bytes = [System.IO.File]::ReadAllBytes($env:ComSpec)
            $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
            [System.BitConverter]::GetBytes([uint16] $Subsystem).CopyTo($bytes, $peOffset + 92)
            [System.IO.File]::WriteAllBytes($Path, $bytes)
        }

        function Write-TestShellScript
        {
            param(
                [Parameter(Mandatory)]
                [string] $Path,

                [Parameter(Mandatory)]
                [string[]] $Line
            )

            [System.IO.File]::WriteAllText($Path, (($Line -join "`n") + "`n"))
            & chmod 755 $Path
        }

        # Replaces Invoke-CompleterHelpProcess in module scope with a shim that
        # records each run. Without -Fake it passes through to the real runner;
        # -NoProfile then puts -NoProfile -NonInteractive -File in front of the
        # probe argument, so a user profile cannot slow a 'pwsh <file>' run.
        # -Fake replaces the runner with a script block that returns a result.
        function Install-TestRunnerShim
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only replaces a function in the imported test module.')]
            [CmdletBinding()]
            param(
                [Parameter()]
                [switch] $NoProfile,

                [Parameter()]
                [scriptblock] $Fake
            )

            & (Get-Module -Name 'CompleterActions') {
                param($NoProfile, $Fake)

                $script:TestProbeRuns = [System.Collections.Generic.List[object]]::new()
                $script:TestRunnerNoProfile = $NoProfile
                $script:TestRunnerFake = $Fake
                $script:TestRunnerOriginal = ${function:Invoke-CompleterHelpProcess}

                function script:Invoke-CompleterHelpProcess
                {
                    param($FilePath, $ArgumentList, $TimeoutSeconds)

                    if ($null -ne $script:TestRunnerFake)
                    {
                        $result = & $script:TestRunnerFake $FilePath $ArgumentList $TimeoutSeconds
                    }
                    else
                    {
                        $arguments = @($ArgumentList)
                        if ($script:TestRunnerNoProfile)
                        {
                            $arguments = @('-NoProfile', '-NonInteractive', '-File') + $arguments
                        }

                        $result = & $script:TestRunnerOriginal -FilePath $FilePath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds
                    }

                    $script:TestProbeRuns.Add([pscustomobject] @{
                            FilePath     = $FilePath
                            ArgumentList = @($ArgumentList)
                            Status       = $result.Status
                        })
                    $result
                }
            } $NoProfile.IsPresent $Fake
        }

        function Get-TestProbeRun
        {
            & (Get-Module -Name 'CompleterActions') {
                $script:TestProbeRuns.ToArray()
            }
        }

        function New-TestExitedResult
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only builds a runner result.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string] $Text
            )

            [pscustomobject] @{
                Status              = 'Exited'
                ExitCode            = 0
                StandardOutput      = [System.Text.Encoding]::UTF8.GetBytes($Text)
                StandardError       = [byte[]]::new(0)
                ElapsedMilliseconds = [long] 12
                ProcessId           = 4242
                StartError          = $null
            }
        }

        function Get-TestCapture
        {
            param(
                [Parameter(Mandatory)]
                [string] $Tool
            )

            # -Raw keeps a lone CR, which plain Get-Content would split on.
            Get-Content -LiteralPath (Join-Path -Path $script:CaptureFolder -ChildPath "$Tool.txt") -Raw
        }

        function Get-TestExpectedName
        {
            param(
                [Parameter(Mandatory)]
                [string] $Tool
            )

            @(Get-Content -LiteralPath (Join-Path -Path $script:CaptureFolder -ChildPath "$Tool.names.txt") | Where-Object { $_.Length -gt 0 })
        }

        function Remove-TestNativeRegistration
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only removes registrations the test made.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string[]] $CommandName
            )

            Unregister-Completer -CommandName $CommandName -Native -AllowUnmanaged -Confirm:$false -ErrorAction SilentlyContinue
        }

        function Invoke-TestWhatIfChild
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Default', 'HelpArgument', 'HelpText', 'NoProbe')]
                [string] $Case,

                [Parameter(Mandatory)]
                [string] $CommandName,

                [Parameter(Mandatory)]
                [string] $Target,

                [Parameter()]
                [string] $Fixture = 'none'
            )

            @(& pwsh -NoProfile -NoLogo -NonInteractive -File $script:WhatIfChildPath -ManifestPath $script:ManifestPath -Case $Case -CommandName $CommandName -Target $Target -Fixture $Fixture 2>&1)
        }

        $script:WhatIfChildPath = Join-Path -Path $TestDrive -ChildPath 'new-completerscript-whatif.ps1'
        Set-Content -LiteralPath $script:WhatIfChildPath -Encoding utf8 -Value @'
param(
    [string] $ManifestPath,
    [string] $Case,
    [string] $CommandName,
    [string] $Target,
    [string] $Fixture
)

$ErrorActionPreference = 'Stop'
Import-Module -Name $ManifestPath -Force

& (Get-Module -Name 'CompleterActions') {
    $script:TestProbeCount = 0
    $script:TestRunnerOriginal = ${function:Invoke-CompleterHelpProcess}

    function script:Invoke-CompleterHelpProcess
    {
        param($FilePath, $ArgumentList, $TimeoutSeconds)

        $script:TestProbeCount++
        & $script:TestRunnerOriginal -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds
    }
}

switch ($Case)
{
    'Default' { New-CompleterScript -CommandName $CommandName -Path $Target -WhatIf }
    'HelpArgument' { New-CompleterScript -CommandName $CommandName -Path $Target -HelpArgument $Fixture -WhatIf }
    'HelpText' { 'Commands:', '  build    Compile' | New-CompleterScript -CommandName $CommandName -Path $Target -WhatIf }
    'NoProbe' { New-CompleterScript -CommandName $CommandName -Path $Target -NoProbe -WhatIf }
}

'COUNT={0}' -f (& (Get-Module -Name 'CompleterActions') { $script:TestProbeCount })
'EXISTS={0}' -f (Test-Path -LiteralPath $Target)
'@
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null

        # TestDrive lasts for the whole Describe, so each test writes into a folder of its own.
        $script:CaseFolder = Join-Path -Path $TestDrive -ChildPath ('case-{0}' -f [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:CaseFolder
    }

    AfterEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'writes a conforming rg skeleton from the rg capture with an empty table, the skeleton line 2, and no warning' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        $file = New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -PassThru -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
        $file | Test-CompleterScript | Should -BeNullOrEmpty
        Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty

        $lines = @(Get-Content -LiteralPath $file.FullName)
        $lines[0] | Should -BeExactly '# rg tab completion for PowerShell'
        $lines[1] | Should -BeExactly ($script:SkeletonLine2Format -f 'Rg')
        @($lines | Where-Object { $_ -ceq '        Subcommands = @()' }).Count | Should -Be 1
        (@(Import-CompleterScript -LiteralPath $file.FullName).CommandName -join '|') | Should -BeExactly 'rg|rg.exe'
    }

    It 'writes the cargo golden file from the cargo capture' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cargo_completer.ps1'

        New-CompleterScript -CommandName 'cargo' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'cargo')

        $expected = [System.IO.File]::ReadAllText((Join-Path -Path $script:CaptureFolder -ChildPath 'cargo_completer.expected.ps1')).Replace("`r`n", "`n")
        $actual = [System.IO.File]::ReadAllText($scriptPath).Replace("`r`n", "`n")
        $actual | Should -BeExactly $expected
    }

    It 'writes a conforming script for the <Tool> capture that imports and registers lazily with the same targets and writes no warning' -TestCases @(
        @{ Tool = 'cargo' }
        @{ Tool = 'docker' }
        @{ Tool = 'gh' }
        @{ Tool = 'go' }
        @{ Tool = '7z' }
        @{ Tool = 'sc' }
        @{ Tool = 'bcdedit' }
        @{ Tool = 'rustup' }
        @{ Tool = 'pip' }
        @{ Tool = 'kubectl' }
        @{ Tool = 'winget' }
        @{ Tool = 'git' }
        @{ Tool = 'rg' }
        @{ Tool = 'schtasks' }
    ) {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath "$($Tool)_completer.ps1"
        $expectedTargets = @($Tool, "$Tool.exe")

        try
        {
            $file = New-CompleterScript -CommandName $Tool -Path $scriptPath -HelpText (Get-TestCapture -Tool $Tool) -PassThru -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -BeNullOrEmpty
            Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty
            @(Get-Content -LiteralPath $file.FullName | Where-Object { $_ -clike '            @{ Name = *' }).Count | Should -Be @(Get-TestExpectedName -Tool $Tool).Count

            $imported = @(Import-CompleterScript -LiteralPath $file.FullName)
            $imported.Count | Should -Be $expectedTargets.Count
            ($imported.CommandName -join '|') | Should -BeExactly ($expectedTargets -join '|')

            $registered = @(Register-Completer -LiteralPath $file.FullName -Lazy -PassThru)
            ($registered.CommandName -join '|') | Should -BeExactly ($expectedTargets -join '|')
            @($registered | Where-Object { -not $_.IsNative }).Count | Should -Be 0
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName $expectedTargets
        }
    }

    It 'offers build and bench for cargo b and no subcommand after cargo build' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cargo_completer.ps1'

        try
        {
            $file = New-CompleterScript -CommandName 'cargo' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'cargo') -PassThru
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo b').CompletionText | Should -Be @('build', 'bench')

            $afterBuild = @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo build ')
            @($afterBuild | Where-Object { $_.CompletionText -in (Get-TestExpectedName -Tool 'cargo') }).Count | Should -Be 0
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'cargo', 'cargo.exe'
        }
    }

    It 'round-trips quotes and cleans control, format, separator, and escape characters in every tooltip' {
        $escape = [string] [char] 0x1B
        $quotes = 'Don{0}t {1}quote{2} {3}this{4} here' -f [char] 0x0027, [char] 0x2018, [char] 0x2019, [char] 0x201A, [char] 0x201B
        $letters = 'Caf{0} na{1}ve {2}r{3}' -f [char] 0x00E9, [char] 0x00EF, [char] 0x00C6, [char] 0x00F8
        $helpText = @(
            'Usage: caquote <command>'
            ('Loading |{0}Loading /{0}' -f "`r")
            ''
            'Commands:'
            ('  quote     {0}' -f $quotes)
            ('  tab       Before{0}after' -f "`t")
            ('  nul       Before{0}after' -f [char] 0x0000)
            ('  format    Before{0}after{1}end{2}tail' -f [char] 0x202E, [char] 0x200B, [char] 0x2028)
            ('  color     {0}[31mRed{0}[0m text' -f $escape)
            ('  link      See {0}]8;;https://example.com{0}\the docs{0}]8;;{0}\ here' -f $escape)
            ('  progress  Working 10%{0}  progress  Done loading' -f "`r")
            ('  letters   {0}' -f $letters)
        ) -join "`n"

        $expected = [ordered] @{
            quote    = $quotes
            tab      = 'Before after'
            nul      = 'Before after'
            format   = 'Before after end tail'
            color    = 'Red text'
            link     = 'See the docs here'
            progress = 'Done loading'
            letters  = $letters
        }

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'caquote_completer.ps1'

        try
        {
            $file = New-CompleterScript -CommandName 'caquote' -Path $scriptPath -HelpText $helpText -PassThru
            Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            $completions = @(Test-CompleterRegistration -CommandName 'caquote' -Native -InputText 'caquote ')

            ($completions.CompletionText -join '|') | Should -BeExactly (@($expected.Keys) -join '|')
            foreach ($completion in $completions)
            {
                $completion.ToolTip | Should -BeExactly $expected[$completion.CompletionText] -Because "the tooltip of '$($completion.CompletionText)' must equal its cleaned description"
            }
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'caquote', 'caquote.exe'
        }
    }

    It 'writes a conforming pwsh script from a real probe' {
        if ($null -eq $script:PwshApplicationPath)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'

        $verbose = @(New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)

        $probeLinePattern = '^Probed ''{0} --help'': exit 0, \d+ characters, \d+ subcommands, \d+ ms\.$' -f [regex]::Escape($script:PwshApplicationPath)
        @($verbose | Where-Object { $_ -match $probeLinePattern }).Count | Should -Be 1
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
    }

    Context 'Run outcomes' {
        AfterEach {
            if ($null -ne $script:ScaffoldDescendantId)
            {
                Stop-Process -Id $script:ScaffoldDescendantId -Force -ErrorAction Ignore
                Wait-Process -Id $script:ScaffoldDescendantId -Timeout 10 -ErrorAction Ignore
                $script:ScaffoldDescendantId = $null
            }
        }

        It 'writes the skeleton line after <Outcome> with its warning' -TestCases @(
            @{ Outcome = 'a timeout' }
            @{ Outcome = 'held output' }
        ) {
            $script:ScaffoldDescendantId = $null
            $usesPwsh = $Outcome -eq 'a timeout' -or $IsWindows
            if ($usesPwsh -and $null -eq $script:PwshApplicationPath)
            {
                Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
                return
            }

            $idPath = Join-Path -Path $script:CaseFolder -ChildPath 'descendant.txt'
            $savedPath = $env:PATH

            try
            {
                if ($Outcome -eq 'a timeout')
                {
                    $commandName = 'pwsh'
                    $fixture = Join-Path -Path $script:CaseFolder -ChildPath 'sleep-help.ps1'
                    Set-Content -LiteralPath $fixture -Encoding utf8 -Value 'Start-Sleep -Seconds 60', 'exit 0'
                    & (Get-Module -Name 'CompleterActions') { $script:CompleterHelpProbeTimeoutSeconds = 0.05 }
                    Install-TestRunnerShim -NoProfile
                    $expectedWarning = "'pwsh $fixture' did not exit within 0.05 seconds and was stopped, so its help was not used."
                    $parameters = @{ HelpArgument = $fixture }
                }
                elseif ($IsWindows)
                {
                    $commandName = 'pwsh'
                    $fixture = Join-Path -Path $script:CaseFolder -ChildPath 'held-help.ps1'
                    Set-Content -LiteralPath $fixture -Encoding utf8 -Value @(
                        '$descendant = Start-Process -NoNewWindow -FilePath ''ping.exe'' -ArgumentList ''-n'', ''15'', ''127.0.0.1'' -PassThru'
                        ('Set-Content -LiteralPath ''{0}'' -Value $descendant.Id' -f $idPath)
                        'exit 0'
                    )
                    Install-TestRunnerShim -NoProfile
                    $expectedWarning = "'pwsh $fixture' exited but left a process holding its output, so its help was not used."
                    $parameters = @{ HelpArgument = $fixture }
                }
                else
                {
                    $commandName = 'caheldscaffold'
                    Write-TestShellScript -Path (Join-Path -Path $script:CaseFolder -ChildPath $commandName) -Line '#!/bin/sh', 'sleep 30 &', ('echo $! > ''{0}''' -f $idPath), 'exit 0'
                    $env:PATH = $script:CaseFolder + [System.IO.Path]::PathSeparator + $savedPath
                    $expectedWarning = "'caheldscaffold --help' exited but left a process holding its output, so its help was not used."
                    $parameters = @{}
                }

                $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath "$($commandName)_completer.ps1"
                New-CompleterScript -CommandName $commandName -Path $scriptPath @parameters -WarningVariable warnings -WarningAction SilentlyContinue
            }
            finally
            {
                $env:PATH = $savedPath
                if (Test-Path -LiteralPath $idPath)
                {
                    $script:ScaffoldDescendantId = [int] (Get-Content -LiteralPath $idPath -TotalCount 1)
                }
            }

            @($warnings | ForEach-Object Message) | Should -Be @($expectedWarning)
            $stem = & (Get-Module -Name 'CompleterActions') { param($Name) ConvertTo-CompleterScriptStem -Name $Name } $commandName
            @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ($script:SkeletonLine2Format -f $stem)
            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
        }
    }

    It 'warns it is a Windows GUI program for the patched GUI copy on PATH and still writes the file' {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the PE and extension checks apply on Windows only'
            return
        }

        $applicationPath = Join-Path -Path $script:CaseFolder -ChildPath 'caguiscaffold.exe'
        New-TestPatchedExe -Path $applicationPath -Subsystem 2
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'caguiscaffold_completer.ps1'

        Install-TestRunnerShim
        $savedPath = $env:PATH
        try
        {
            $env:PATH = $script:CaseFolder + [System.IO.Path]::PathSeparator + $savedPath
            New-CompleterScript -CommandName 'caguiscaffold' -Path $scriptPath -WarningVariable warnings -WarningAction SilentlyContinue
        }
        finally
        {
            $env:PATH = $savedPath
        }

        @(Get-TestProbeRun).Count | Should -Be 0
        @($warnings | ForEach-Object Message) | Should -Be @("'$applicationPath' was not run: it is a Windows GUI program. Run 'caguiscaffold --help' yourself and pass the text with -HelpText.")
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ($script:SkeletonLine2Format -f 'Caguiscaffold')
    }

    It 'never runs a .cmd fixture and leaves its marker absent' {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the PE and extension checks apply on Windows only'
            return
        }

        $markerPath = Join-Path -Path $script:CaseFolder -ChildPath 'marker.txt'
        Set-Content -LiteralPath (Join-Path -Path $script:CaseFolder -ChildPath 'cacmdscaffold.cmd') -Value '@echo off', ('echo ran> "{0}"' -f $markerPath) -Encoding ascii
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cacmdscaffold_completer.ps1'

        Install-TestRunnerShim
        $savedPath = $env:PATH
        try
        {
            $env:PATH = $script:CaseFolder + [System.IO.Path]::PathSeparator + $savedPath
            New-CompleterScript -CommandName 'cacmdscaffold' -Path $scriptPath -WarningVariable warnings -WarningAction SilentlyContinue
        }
        finally
        {
            $env:PATH = $savedPath
        }

        @(Get-TestProbeRun).Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        $warnings[0].Message | Should -BeLike '*which only runs through cmd.exe*'
        Test-Path -LiteralPath $markerPath | Should -BeFalse
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
    }

    It 'never runs a global function or alias named like the command' {
        $markerPath = Join-Path -Path $script:CaseFolder -ChildPath 'marker.txt'
        $functionName = 'cafuncscaffold{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8)
        $aliasName = 'caaliasscaffold{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8)

        Set-Item -Path "Function:\global:$functionName" -Value ([scriptblock]::Create("Set-Content -LiteralPath '$markerPath' -Value 'ran'"))
        Set-Alias -Name $aliasName -Value $functionName -Scope Global

        Install-TestRunnerShim
        try
        {
            foreach ($name in $functionName, $aliasName)
            {
                $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath "$($name)_completer.ps1"
                New-CompleterScript -CommandName $name -Path $scriptPath -WarningVariable warnings -WarningAction SilentlyContinue

                @($warnings | ForEach-Object Message) | Should -Be @("The command '$name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand.")
                Test-Path -LiteralPath $scriptPath | Should -BeTrue
            }
        }
        finally
        {
            Remove-Alias -Name $aliasName -Scope Global -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        @(Get-TestProbeRun).Count | Should -Be 0
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }

    It 'warns was not found as an application, writes the skeleton, and does not throw under ErrorActionPreference Stop' {
        $name = 'zz_nonexistent_{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8)
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'zz_completer.ps1'

        $ErrorActionPreference = 'Stop'
        New-CompleterScript -CommandName $name -Path $scriptPath -WarningVariable warnings -WarningAction SilentlyContinue

        @($warnings | ForEach-Object Message) | Should -Be @("The command '$name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand.")
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
        $stem = & (Get-Module -Name 'CompleterActions') { param($Name) ConvertTo-CompleterScriptStem -Name $Name } $name
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ($script:SkeletonLine2Format -f $stem)
    }

    It 'runs nothing, writes nothing, and names the path and program under -WhatIf' {
        if ($null -eq $script:PwshApplicationPath)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $markerPath = Join-Path -Path $script:CaseFolder -ChildPath 'marker.txt'
        $fixture = Join-Path -Path $script:CaseFolder -ChildPath 'marker-help.ps1'
        Set-Content -LiteralPath $fixture -Encoding utf8 -Value ("Set-Content -LiteralPath '{0}' -Value 'ran'" -f $markerPath)
        $target = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'

        $output = Invoke-TestWhatIfChild -Case 'HelpArgument' -CommandName 'pwsh' -Target $target -Fixture $fixture

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
        $output | Should -Contain 'COUNT=0'
        $output | Should -Contain 'EXISTS=False'
        Test-Path -LiteralPath $markerPath | Should -BeFalse
        $whatIfLine = 'What if: Performing the operation "Create completer script, running ''{0} {1}'' to read its help" on target "{2}".' -f $script:PwshApplicationPath, $fixture, $target
        @($output | Where-Object { $_ -ceq $whatIfLine }).Count | Should -Be 1
    }

    It 'asks ShouldProcess with the action for <Case>' -TestCases @(
        @{ Case = 'the default probe on Windows'; Platform = 'Windows'; Child = 'Default'; CommandName = 'pwsh'; Action = "running '<pwsh> --help' and, if it is rejected, '/?' to read its help" }
        @{ Case = 'the default probe on Linux and macOS'; Platform = 'Unix'; Child = 'Default'; CommandName = 'pwsh'; Action = "running '<pwsh> --help' to read its help" }
        @{ Case = '-HelpArgument'; Platform = 'Any'; Child = 'HelpArgument'; CommandName = 'pwsh'; Action = "running '<pwsh> help' to read its help" }
        @{ Case = 'the HelpText set'; Platform = 'Any'; Child = 'HelpText'; CommandName = 'fx'; Action = 'without running a program' }
        @{ Case = 'the NoProbe set'; Platform = 'Any'; Child = 'NoProbe'; CommandName = 'fx'; Action = 'without running a program' }
        @{ Case = 'a command not found'; Platform = 'Any'; Child = 'Default'; CommandName = 'zz_nonexistent_whatif'; Action = 'without running a program' }
    ) {
        if ($Platform -eq 'Windows' -and -not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the /? fallback runs on Windows only'
            return
        }

        if ($Platform -eq 'Unix' -and $IsWindows)
        {
            Set-ItResult -Skipped -Because 'this case asserts the Linux and macOS text'
            return
        }

        if ($CommandName -eq 'pwsh' -and $null -eq $script:PwshApplicationPath)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $target = Join-Path -Path $script:CaseFolder -ChildPath "$($CommandName)_completer.ps1"
        $output = Invoke-TestWhatIfChild -Case $Child -CommandName $CommandName -Target $target -Fixture 'help'

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
        $output | Should -Contain 'COUNT=0'
        $output | Should -Contain 'EXISTS=False'
        $action = if ($Action.StartsWith('running')) { 'Create completer script, ' + $Action.Replace('<pwsh>', $script:PwshApplicationPath) } else { 'Create completer script ' + $Action }
        $whatIfLine = 'What if: Performing the operation "{0}" on target "{1}".' -f $action, $target
        @($output | Where-Object { $_ -ceq $whatIfLine }).Count | Should -Be 1 -Because ($output -join [System.Environment]::NewLine)
    }

    It 'fails step 1 under -WhatIf before anything is resolved' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        Set-Content -LiteralPath $scriptPath -Value 'existing content'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestResolveCount = 0
            function script:Resolve-CompleterHelpProbeApplication
            {
                param($Name)

                $script:TestResolveCount++
            }
        }

        $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -WhatIf } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + ($script:AlreadyExistsFormat -f $scriptPath))
        (& (Get-Module -Name 'CompleterActions') { $script:TestResolveCount }) | Should -Be 0
        Get-Content -LiteralPath $scriptPath -Raw | Should -BeExactly ('existing content' + [System.Environment]::NewLine)
    }

    It 'refuses an existing file without -Force and replaces it with -Force' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
        Set-Content -LiteralPath $scriptPath -Value 'existing content'

        $thrown = { New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + ($script:AlreadyExistsFormat -f $scriptPath))
        Get-Content -LiteralPath $scriptPath -Raw | Should -BeExactly ('existing content' + [System.Environment]::NewLine)

        New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Force

        @(Get-Content -LiteralPath $scriptPath)[0] | Should -BeExactly '# rg tab completion for PowerShell'
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It 'fails when the file appears during the probe and leaves no .tmp file' {
        if ($null -eq $script:PwshApplicationPath)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $result = New-TestExitedResult -Text "Commands:`n  build    Compile the project`n"
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                [System.IO.File]::WriteAllText($scriptPath, 'appeared during the probe')
                $result
            }.GetNewClosure())

        $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument '--help' } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + ($script:AlreadyExistsFormat -f $scriptPath))
        @(Get-TestProbeRun).Count | Should -Be 1
        [System.IO.File]::ReadAllText($scriptPath) | Should -BeExactly 'appeared during the probe'
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It 'fails <Case> with its section 2 text wrapped in Failed to create completer script' -TestCases @(
        @{ Case = 'a missing directory'; CommandName = 'rg'; Leaf = 'missing\rg_completer.ps1'; Reason = "The directory '<case>{0}missing' does not exist." }
        @{ Case = 'a non-.ps1 path'; CommandName = 'rg'; Leaf = 'rg_completer.txt'; Reason = "Completer scripts must be .ps1 files. Received '<case>{0}rg_completer.txt'." }
        @{ Case = 'a directory path'; CommandName = 'rg'; Leaf = 'folder.ps1'; Reason = "Completer scripts must be file paths. '<case>{0}folder.ps1' is a directory." }
        @{ Case = 'the name _'; CommandName = '_'; Leaf = 'x_completer.ps1'; Reason = "'_' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." }
        @{ Case = 'the name foo.'; CommandName = 'foo.'; Leaf = 'x_completer.ps1'; Reason = "'foo.' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." }
        @{ Case = 'the name -x'; CommandName = '-x'; Leaf = 'x_completer.ps1'; Reason = "'-x' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." }
        @{ Case = 'the name a b'; CommandName = 'a b'; Leaf = 'x_completer.ps1'; Reason = "'a b' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." }
        @{ Case = 'the name C:\tools\rg'; CommandName = 'C:\tools\rg'; Leaf = 'x_completer.ps1'; Reason = "'C:\tools\rg' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." }
    ) {
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:CaseFolder -ChildPath 'folder.ps1')
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath $Leaf.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
        $expectedReason = $Reason.Replace('<case>', $script:CaseFolder) -f [System.IO.Path]::DirectorySeparatorChar

        $thrown = { New-CompleterScript -CommandName $CommandName -Path $scriptPath -NoProbe } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + $expectedReason)
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Recurse -File -Force).Count | Should -Be 0
    }

    It 'leaves nothing at the path for <Case> when the failure is silenced with -ErrorAction <Action>' -TestCases @(
        @{ Case = 'a non-.ps1 path'; Action = 'SilentlyContinue'; CommandName = 'rg'; Leaf = 'rg_completer.txt' }
        @{ Case = 'a non-.ps1 path'; Action = 'Ignore'; CommandName = 'rg'; Leaf = 'rg_completer.txt' }
        @{ Case = 'a missing directory'; Action = 'SilentlyContinue'; CommandName = 'rg'; Leaf = 'missing\rg_completer.ps1' }
        @{ Case = 'the name a b'; Action = 'SilentlyContinue'; CommandName = 'a b'; Leaf = 'x_completer.ps1' }
        @{ Case = 'an existing file without -Force'; Action = 'SilentlyContinue'; CommandName = 'rg'; Leaf = 'rg_completer.ps1'; Existing = $true }
    ) {
        # A child process, because any enclosing try, Pester's included, makes even
        # a silenced throw terminate; the call must run as a bare statement.
        $childPath = Join-Path -Path $TestDrive -ChildPath 'new-completerscript-silenced.ps1'
        Set-Content -LiteralPath $childPath -Encoding utf8 -Value @'
param(
    [string] $ManifestPath,
    [string] $CommandName,
    [string] $Target,
    [string] $Action
)

Import-Module -Name $ManifestPath -Force
$Error.Clear()
New-CompleterScript -CommandName $CommandName -Path $Target -NoProbe -PassThru -ErrorAction $Action
'ERROR={0}' -f $Error[0].Exception.Message
'@

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath $Leaf.Replace('\', [System.IO.Path]::DirectorySeparatorChar)

        if ($Existing)
        {
            Set-Content -LiteralPath $scriptPath -Value 'existing content'
        }

        $output = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $childPath -ManifestPath $script:ManifestPath -CommandName $CommandName -Target $scriptPath -Action $Action 2>&1 | ForEach-Object { "$_" })

        $errorLines = @($output | Where-Object { $_ -like 'ERROR=*' })
        $errorLines.Count | Should -Be 1 -Because ($output -join [System.Environment]::NewLine)
        $errorLines[0] | Should -BeLike 'ERROR=Failed to create completer script. *'

        if ($Existing)
        {
            Get-Content -LiteralPath $scriptPath -Raw | Should -BeExactly ('existing content' + [System.Environment]::NewLine)
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Recurse -File -Force).Count | Should -Be 1
        }
        else
        {
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Recurse -File -Force).Count | Should -Be 0
        }
    }

    It 'returns a FileInfo only with -PassThru' {
        $withoutPassThru = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
        $withPassThru = Join-Path -Path $script:CaseFolder -ChildPath 'fd_completer.ps1'

        $none = @(New-CompleterScript -CommandName 'rg' -Path $withoutPassThru -NoProbe)
        $file = New-CompleterScript -CommandName 'fd' -Path $withPassThru -NoProbe -PassThru

        $none.Count | Should -Be 0
        Test-Path -LiteralPath $withoutPassThru | Should -BeTrue
        $file | Should -BeOfType ([System.IO.FileInfo])
        $file.FullName | Should -Be $withPassThru
    }

    It 'pipes the -PassThru FileInfo into Import-CompleterScript' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        $records = @(New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -PassThru | Import-CompleterScript)

        ($records.CommandName -join '|') | Should -BeExactly 'rg|rg.exe'
        @($records | Where-Object { $_.SourcePath -ne $scriptPath }).Count | Should -Be 0
    }

    It 'resolves a relative -Path against the current location' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        Push-Location -LiteralPath $script:CaseFolder
        try
        {
            $file = New-CompleterScript -CommandName 'rg' -Path 'rg_completer.ps1' -NoProbe -PassThru
        }
        finally
        {
            Pop-Location
        }

        $file.FullName | Should -Be $scriptPath
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
    }

    It 'joins piped help lines before parsing' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'fx_completer.ps1'

        'Commands:', '', '  build    Compile' | New-CompleterScript -CommandName 'fx' -Path $scriptPath

        $lines = @(Get-Content -LiteralPath $scriptPath)
        $lines[1] | Should -BeExactly $script:HelpTextLine2
        @($lines | Where-Object { $_ -clike '            @{ Name = *' }) | Should -Be @("            @{ Name = 'build'; Description = 'Compile' }")
    }

    It 'fails with the self-check text and leaves no file when the composer emits a top-level assignment' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestSkeletonOriginal = ${function:Get-CompleterScriptSkeleton}
            function script:Get-CompleterScriptSkeleton
            {
                param($Name, $Stem, $Target, $Subcommand, $SeedKind, $ProbeArgument)

                $lines = [System.Collections.Generic.List[string]]::new()
                $lines.AddRange([string[]] @(& $script:TestSkeletonOriginal @PSBoundParameters))
                $lines.Insert(4, '$script:RgCompletionCatalog = @{ Subcommands = @() }')
                $lines.ToArray()
            }
        }

        $thrown = { New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + $script:SelfCheckPrefix + 'The script uses a top-level assignment.')
        Test-Path -LiteralPath $scriptPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 0
    }

    It 'writes the resolved-application, probe, and wrote verbose lines' {
        if ($null -eq $script:PwshApplicationPath)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $helpText = "Commands:`n  build    Compile the project`n  test     Run the tests`n"
        $result = New-TestExitedResult -Text $helpText
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                $result
            }.GetNewClosure())

        $verbose = @(New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument '--help' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)

        $verbose.Count | Should -Be 4 -Because ($verbose -join [System.Environment]::NewLine)
        $verbose[0] | Should -BeExactly ("Resolved 'pwsh' to the application '{0}'." -f $script:PwshApplicationPath)
        $verbose[1] | Should -BeExactly ('Performing the operation "Create completer script, running ''{0} --help'' to read its help" on target "{1}".' -f $script:PwshApplicationPath, $scriptPath)
        $verbose[2] | Should -BeExactly ("Probed '{0} --help': exit 0, {1} characters, 2 subcommands, 12 ms." -f $script:PwshApplicationPath, $helpText.Length)
        $verbose[3] | Should -BeExactly ("Wrote '{0}': 2 targets, 2 subcommands." -f $scriptPath)
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ("# Help-seeded native completer: the subcommand table was read from 'pwsh --help' when the script was generated.")
    }

    It 'shows the three parameter sets of section 2' {
        $syntax = @((Get-Command -Name 'New-CompleterScript' -Syntax) -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })

        $syntax | Should -Be @(
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> [-HelpArgument <string>] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> -HelpText <string[]> [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> -NoProbe [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
        )
    }

    It 'resolves its help with the section 2 synopsis' {
        # A comment-help line that starts with a dot and a word invalidates the whole help block.
        (Get-Help -Name 'New-CompleterScript' -Full).Synopsis | Should -BeExactly 'Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.'
    }

    It 'declares ConfirmImpact Low, SupportsShouldProcess, and OutputType FileInfo' {
        $command = Get-Command -Name 'New-CompleterScript'
        $binding = @($command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] })

        $binding.Count | Should -Be 1
        $binding[0].SupportsShouldProcess | Should -BeTrue
        $binding[0].ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Low)
        $binding[0].DefaultParameterSetName | Should -BeExactly 'Probe'
        @($command.OutputType.Type) | Should -Be @([System.IO.FileInfo])
    }
}
