BeforeAll {
    # Save-CompleterScriptFile and New-CompleterScript both throw this text, so every test compares against this one format string.
    $script:AlreadyExistsFormat = "The file '{0}' already exists. Use -Force to overwrite it."
    $script:SelfCheckPrefix = 'New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. '

    $script:ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'

    # The section 2 skeleton block, character for character; <LINE2>, <SUBCOMMANDS>, and <OPTIONS> vary by case.
    $script:CargoSkeletonTemplate = @'
# cargo tab completion for PowerShell
<LINE2>

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name CargoCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:CargoCompletionCatalog = @{
<SUBCOMMANDS>
<OPTIONS>
    }
}

function Complete-Cargo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Offer options in any position once the word starts with '-' or '/'.
    if ($wordToComplete.StartsWith('-') -or $wordToComplete.StartsWith('/')) {
        foreach ($option in $script:CargoCompletionCatalog.Options) {
            if ($option.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($option.Name, $option.Name, 'ParameterName', $option.Description)
            }
        }
    }

    # Offer subcommands in the first argument position only; extend this function for values.
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

    $script:CargoOptionRows = @(
        [pscustomobject] @{ Name = '-V'; Description = 'Print version info and exit' }
        [pscustomobject] @{ Name = '--version'; Description = 'Print version info and exit' }
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
    ) {
        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
                param($Name)

                ConvertTo-CompleterTargetName -CommandName 'rg', $Name
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ("'{0}' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters." -f $Name)
    }

    It 'rejects the command name <Name>, whose stem would be empty' -TestCases @(
        @{ Name = '_.exe' }
        @{ Name = '__.cmd' }
        @{ Name = '_+.COM' }
    ) {
        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
                param($Name)

                ConvertTo-CompleterTargetName -CommandName 'rg', $Name
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ("The command name '{0}' has no letter or digit outside its suffix, so no function name can be derived from it." -f $Name)
    }

    It 'derives the stem <Stem> from <Name>' -TestCases @(
        @{ Name = 'rg'; Stem = 'Rg' }
        @{ Name = 'rg.exe'; Stem = 'Rg' }
        @{ Name = 'cargo-binstall'; Stem = 'CargoBinstall_f8016b04' }
        @{ Name = 'oh-my-posh'; Stem = 'OhMyPosh_f9e5f36d' }
        @{ Name = 'ca-tool'; Stem = 'CaTool_8f74ce7e' }
        @{ Name = 'ca-tool.exe'; Stem = 'CaTool_8f74ce7e' }
        @{ Name = 'ca_tool'; Stem = 'CaTool_014e186e' }
        @{ Name = '_a'; Stem = 'A_34fb7160' }
        @{ Name = 'DSC'; Stem = 'DSC' }
        @{ Name = '7z'; Stem = '7z' }
        @{ Name = 'npm.cmd'; Stem = 'Npm_a04d41f6' }
        @{ Name = 'TOOL.BAT'; Stem = 'TOOL_5bf9d4ff' }
        @{ Name = 'x.ps1'; Stem = 'X_8cc8bc96' }
        @{ Name = 'y.com'; Stem = 'Y_8746a35c' }
        @{ Name = 'tool.cmd.exe'; Stem = 'ToolCmd_1e235eff' }
    ) {
        $actual = InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
            param($Name)

            ConvertTo-CompleterScriptStem -Name $Name
        }

        $actual | Should -BeExactly $Stem
    }

    It 'derives a distinct stem, ignoring case, for each name that differs only in punctuation or suffix' {
        $names = 'catool', 'ca-tool', 'ca_tool', 'ca.tool', 'ca+tool', 'c-atool', 'cat-ool', 'g', 'g+', 'g++', 'a', '_a', 'tool', 'tool.cmd', 'tool.bat', 'tool.ps1', 'tool.com', 'tool.cmd.exe'

        $stems = @(InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Names = $names } -ScriptBlock {
                param($Names)

                $Names | ForEach-Object { ConvertTo-CompleterScriptStem -Name $_ }
            })

        $stems.Count | Should -Be $names.Count
        @($stems | Sort-Object -Unique).Count | Should -Be $names.Count
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

    It 'writes line 2 and the tables for <Case>' -TestCases @(
        @{
            Case     = 'a probe with subcommands'
            SeedKind = 'Probe'
            Rows     = 'subcommands'
            Line2    = "# Help-seeded native completer: the tables were read from 'cargo --help' when the script was generated."
        }
        @{
            Case     = 'a probe with options only'
            SeedKind = 'Probe'
            Rows     = 'options'
            Line2    = "# Help-seeded native completer: the tables were read from 'cargo --help' when the script was generated."
        }
        @{
            Case     = 'help text with subcommands'
            SeedKind = 'HelpText'
            Rows     = 'subcommands'
            Line2    = '# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.'
        }
        @{
            Case     = 'help text with options only'
            SeedKind = 'HelpText'
            Rows     = 'options'
            Line2    = '# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.'
        }
        @{
            Case     = 'help text with both tables'
            SeedKind = 'HelpText'
            Rows     = 'both'
            Line2    = '# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.'
        }
        @{
            Case     = 'empty tables'
            SeedKind = 'Probe'
            Rows     = 'none'
            Line2    = '# Native completer skeleton: add subcommands and options to the tables.'
        }
    ) {
        $subcommand = @(if ($Rows -in 'subcommands', 'both') { $script:CargoRows })
        $option = @(if ($Rows -in 'options', 'both') { $script:CargoOptionRows })
        $parameters = @{ SeedKind = $SeedKind; Subcommand = $subcommand; Option = $option }

        $lines = @(InModuleScope -ModuleName 'CompleterActions' -Parameters $parameters -ScriptBlock {
                param($SeedKind, $Subcommand, $Option)

                $skeletonParameters = @{
                    Name       = 'cargo'
                    Stem       = ConvertTo-CompleterScriptStem -Name 'cargo'
                    Target     = @(ConvertTo-CompleterTargetName -CommandName 'cargo')
                    Subcommand = @($Subcommand)
                    Option     = @($Option)
                    SeedKind   = $SeedKind
                }

                if ($SeedKind -eq 'Probe')
                {
                    $skeletonParameters['ProbeArgument'] = '--help'
                }

                Get-CompleterScriptSkeleton @skeletonParameters
            })

        $lines[1] | Should -BeExactly $Line2

        $subcommandText = if ($subcommand.Count -gt 0)
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

        $optionText = if ($option.Count -gt 0)
        {
            @(
                '        Options = @('
                "            @{ Name = '-V'; Description = 'Print version info and exit' }"
                "            @{ Name = '--version'; Description = 'Print version info and exit' }"
                '        )'
            ) -join "`n"
        }
        else
        {
            '        Options = @()'
        }

        $expected = @($script:CargoSkeletonTemplate.Replace('<LINE2>', $Line2).Replace('<SUBCOMMANDS>', $subcommandText).Replace('<OPTIONS>', $optionText) -split '\r?\n')
        $lines.Count | Should -Be $expected.Count
        ($lines -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'refuses option rows without a seed kind' {
        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Option = $script:CargoOptionRows } -ScriptBlock {
                param($Option)

                Get-CompleterScriptSkeleton -Name 'cargo' -Stem 'Cargo' -Target 'cargo', 'cargo.exe' -Subcommand @() -Option $Option
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly 'A non-empty subcommand or option table needs -SeedKind HelpText, or -SeedKind Probe with -ProbeArgument.'
    }

    It 'writes empty tables as Subcommands = @() and Options = @()' {
        $lines = @(InModuleScope -ModuleName 'CompleterActions' -ScriptBlock {
                Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @() -SeedKind 'HelpText'
            })

        @($lines | Where-Object { $_ -ceq '        Subcommands = @()' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -ceq '        Options = @()' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -clike '*Subcommands = @(' -or $_ -clike '*Options = @(' -or $_ -clike '*@{ Name = *' }).Count | Should -Be 0
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
        # The pwsh running the suite. A test that hands the bare name pwsh to
        # New-CompleterScript puts $PSHOME first on PATH in the process that
        # resolves it, because the first pwsh on PATH can be an app execution
        # alias, and a child pwsh puts the alias folder back at the front.
        $script:PwshPath = Join-Path -Path $PSHOME -ChildPath ($IsWindows ? 'pwsh.exe' : 'pwsh')
        $script:SkeletonLine2 = '# Native completer skeleton: add subcommands and options to the tables.'
        $script:HelpTextLine2 = '# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.'

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

        function Get-TestExpectedOption
        {
            param(
                [Parameter(Mandatory)]
                [string] $Tool
            )

            @(Get-Content -LiteralPath (Join-Path -Path $script:CaptureFolder -ChildPath "$Tool.options.txt") | Where-Object { $_.Length -gt 0 })
        }

        # Reads the catalog hashtable of a generated script without running it.
        function Get-TestCatalog
        {
            param(
                [Parameter(Mandatory)]
                [string] $LiteralPath
            )

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $null, [ref] $null)
            $assignment = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -clike '$script:*CompletionCatalog' }, $true)
            $assignment.Right.Expression.SafeGetValue()
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
                [string] $Fixture = 'none',

                [Parameter()]
                [switch] $Documentation
            )

            $documentationArgument = @(if ($Documentation) { '-Documentation' })
            @(& $script:PwshPath -NoProfile -NoLogo -NonInteractive -File $script:WhatIfChildPath -ManifestPath $script:ManifestPath -Case $Case -CommandName $CommandName -Target $Target -Fixture $Fixture @documentationArgument 2>&1)
        }

        $script:WhatIfChildPath = Join-Path -Path $TestDrive -ChildPath 'new-completerscript-whatif.ps1'
        Set-Content -LiteralPath $script:WhatIfChildPath -Encoding utf8 -Value @'
param(
    [string] $ManifestPath,
    [string] $Case,
    [string] $CommandName,
    [string] $Target,
    [string] $Fixture,
    [switch] $Documentation
)

# A child pwsh puts the alias folder back at the front of PATH, so the pin is made here.
$env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $env:PATH
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
    'Default' { New-CompleterScript -CommandName $CommandName -Path $Target -Documentation:$Documentation -WhatIf }
    'HelpArgument' { New-CompleterScript -CommandName $CommandName -Path $Target -HelpArgument $Fixture -Documentation:$Documentation -WhatIf }
    'HelpText' { 'Commands:', '  build    Compile' | New-CompleterScript -CommandName $CommandName -Path $Target -Documentation:$Documentation -WhatIf }
    'NoProbe' { New-CompleterScript -CommandName $CommandName -Path $Target -NoProbe -Documentation:$Documentation -WhatIf }
}

'COUNT={0}' -f (& (Get-Module -Name 'CompleterActions') { $script:TestProbeCount })
'EXISTS={0}' -f (Test-Path -LiteralPath $Target)
'MDEXISTS={0}' -f (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($Target, '.md')))
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

    It 'seeds the option table of the option-only rg from the rg capture, with the help-text line 2 and no warning' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        $file = New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -PassThru -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeNullOrEmpty
        $file | Test-CompleterScript | Should -BeNullOrEmpty
        Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty

        $lines = @(Get-Content -LiteralPath $file.FullName)
        $lines[0] | Should -BeExactly '# rg tab completion for PowerShell'
        $lines[1] | Should -BeExactly $script:HelpTextLine2
        @($lines | Where-Object { $_ -ceq '        Subcommands = @()' }).Count | Should -Be 1

        $catalog = Get-TestCatalog -LiteralPath $file.FullName
        @($catalog.Subcommands).Count | Should -Be 0
        (@($catalog.Options | ForEach-Object { $_.Name }) -join "`n") | Should -BeExactly ((Get-TestExpectedOption -Tool 'rg') -join "`n")
        @($catalog.Options | ForEach-Object { $_.Name }) | Should -Contain '--regexp'
        (@(Import-CompleterScript -LiteralPath $file.FullName).CommandName -join '|') | Should -BeExactly 'rg|rg.exe'
    }

    It 'writes the cargo golden file from the cargo capture' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cargo_completer.ps1'

        New-CompleterScript -CommandName 'cargo' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'cargo')

        $expected = [System.IO.File]::ReadAllText((Join-Path -Path $script:CaptureFolder -ChildPath 'cargo_completer.expected.ps1')).Replace("`r`n", "`n")
        $actual = [System.IO.File]::ReadAllText($scriptPath).Replace("`r`n", "`n")
        $actual | Should -BeExactly $expected
    }

    It 'writes a conforming script for the <Tool> capture with exactly its expected subcommand and option names, that imports and registers lazily with the same targets and writes no warning' -TestCases @(
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
        @{ Tool = 'du' }
    ) {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath "$($Tool)_completer.ps1"
        $expectedTargets = @($Tool, "$Tool.exe")

        try
        {
            $file = New-CompleterScript -CommandName $Tool -Path $scriptPath -HelpText (Get-TestCapture -Tool $Tool) -PassThru -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -BeNullOrEmpty
            Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty

            $catalog = Get-TestCatalog -LiteralPath $file.FullName
            (@($catalog.Subcommands | ForEach-Object { $_.Name }) -join "`n") | Should -BeExactly ((Get-TestExpectedName -Tool $Tool) -join "`n")
            (@($catalog.Options | ForEach-Object { $_.Name }) -join "`n") | Should -BeExactly ((Get-TestExpectedOption -Tool $Tool) -join "`n")
            @(Get-Content -LiteralPath $file.FullName | Where-Object { $_ -clike '            @{ Name = *' }).Count | Should -Be (@(Get-TestExpectedName -Tool $Tool).Count + @(Get-TestExpectedOption -Tool $Tool).Count)

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

    It 'offers build and bench for cargo b, --version for cargo --ver, and no subcommand after cargo build' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cargo_completer.ps1'

        try
        {
            $file = New-CompleterScript -CommandName 'cargo' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'cargo') -PassThru
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo b').CompletionText | Should -Be @('build', 'bench')

            $version = @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo --ver' -TargetOnly)
            $version.CompletionText | Should -Contain '--version'
            @($version | Where-Object { $_.ResultType -ne [System.Management.Automation.CompletionResultType]::ParameterName }).Count | Should -Be 0

            $afterBuild = @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo build ')
            @($afterBuild | Where-Object { $_.CompletionText -in (Get-TestExpectedName -Tool 'cargo') }).Count | Should -Be 0
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'cargo', 'cargo.exe'
        }
    }

    It 'offers rg options for <InputText> with ResultType ParameterName' -TestCases @(
        @{ InputText = 'rg --reg' }
        @{ InputText = 'rg foo --reg' }
    ) {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        try
        {
            $file = New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -PassThru
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            $completions = @(Test-CompleterRegistration -CommandName 'rg' -Native -InputText $InputText -TargetOnly)

            $completions.CompletionText | Should -Contain '--regexp'
            $completions.CompletionText | Should -Contain '--regex-size-limit'
            @($completions | Where-Object { -not $_.CompletionText.StartsWith('--reg', [System.StringComparison]::OrdinalIgnoreCase) }).Count | Should -Be 0
            @($completions | Where-Object { $_.ResultType -ne [System.Management.Automation.CompletionResultType]::ParameterName }).Count | Should -Be 0
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'rg', 'rg.exe'
        }
    }

    It 'offers <Expected> from the target for <Case>' -TestCases @(
        @{ Case = 'an empty word'; InputText = 'catool '; Expected = 'build' }
        @{ Case = 'a slash word that matches an option'; InputText = 'catool /x'; Expected = '/X' }
        @{ Case = 'a slash word that matches no option'; InputText = 'catool /usr'; Expected = '' }
        @{ Case = 'a dash word that matches no option'; InputText = 'catool --zz'; Expected = '' }
        @{ Case = 'a dash word after the first argument'; InputText = 'catool build -'; Expected = '-a,--all' }
    ) {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'catool_completer.ps1'
        $helpText = @('Options:', '  -a, --all    Show all', '  /X           Extended', '', 'Commands:', '  build    Compile') -join "`n"

        try
        {
            $file = New-CompleterScript -CommandName 'catool' -Path $scriptPath -HelpText $helpText -PassThru
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            (@((Get-TestCatalog -LiteralPath $file.FullName).Options | ForEach-Object { $_.Name }) -join ',') | Should -BeExactly '-a,--all,/X'
            (@(Test-CompleterRegistration -CommandName 'catool' -Native -InputText $InputText -TargetOnly).CompletionText -join ',') | Should -BeExactly $Expected
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'catool', 'catool.exe'
        }
    }

    It 'offers nothing from the target for rg followed by a space' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        try
        {
            $file = New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -PassThru
            $null = Register-Completer -LiteralPath $file.FullName -Lazy

            @(Test-CompleterRegistration -CommandName 'rg' -Native -InputText 'rg ' -TargetOnly) | Should -BeNullOrEmpty
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'rg', 'rg.exe'
        }
    }

    It 'still passes Test-CompleterScript and completes cargo b with the script 3.0.1 generated' {
        $oldScript = Join-Path -Path $script:CaptureFolder -ChildPath 'cargo_completer.3.0.1.ps1'
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'cargo_completer.ps1'
        Copy-Item -LiteralPath $oldScript -Destination $scriptPath

        try
        {
            (Get-TestCatalog -LiteralPath $scriptPath).ContainsKey('Options') | Should -BeFalse
            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
            $null = Register-Completer -LiteralPath $scriptPath -Lazy

            @(Test-CompleterRegistration -CommandName 'cargo' -Native -InputText 'cargo b' -TargetOnly).CompletionText | Should -Be @('build', 'bench')
        }
        finally
        {
            Remove-TestNativeRegistration -CommandName 'cargo', 'cargo.exe'
        }
    }

    It 'completes each command from its own table when the scripts for <Names> are all dot-sourced' -TestCases @(
        @{ Names = @('ca-tool', 'ca_tool'); Words = @('dashonly', 'underonly') }
        @{ Names = @('tool', 'tool.cmd', 'tool.bat'); Words = @('exeonly', 'cmdonly', 'batonly') }
    ) {
        $paths = for ($index = 0; $index -lt $Names.Count; $index++)
        {
            $path = Join-Path -Path $script:CaseFolder -ChildPath ('{0}_completer.ps1' -f ($Names[$index] -replace '\.', '_'))
            'Commands:', ('  {0}    Only {1} has this' -f $Words[$index], $Names[$index]) | New-CompleterScript -CommandName $Names[$index] -Path $path
            $path
        }

        Test-CompleterScript -LiteralPath $paths | Should -BeNullOrEmpty

        # A profile dot-sources each script into one scope; a runspace of its own keeps these registrations out of the test session.
        $powershell = [powershell]::Create()
        try
        {
            $null = $powershell.AddScript({
                    param($Paths, $Names)

                    foreach ($path in $Paths)
                    {
                        . $path
                    }

                    foreach ($name in $Names)
                    {
                        $inputText = '{0} ' -f $name
                        (TabExpansion2 -inputScript $inputText -cursorColumn $inputText.Length).CompletionMatches.CompletionText -join '|'
                    }
                }).AddArgument([string[]] $paths).AddArgument([string[]] $Names)
            $completions = @($powershell.Invoke())

            $powershell.Streams.Error | Should -BeNullOrEmpty
            $completions | Should -Be $Words
        }
        finally
        {
            $powershell.Dispose()
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
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $verbose = @(New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $probeLinePattern = '^Probed ''{0} --help'': exit 0, \d+ characters, \d+ subcommands, \d+ options, \d+ ms\.$' -f [regex]::Escape($script:PwshPath)
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
            $idPath = Join-Path -Path $script:CaseFolder -ChildPath 'descendant.txt'
            $savedPath = $env:PATH

            try
            {
                if ($Outcome -eq 'a timeout')
                {
                    $commandName = 'pwsh'
                    $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
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
                    $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
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
            @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly $script:SkeletonLine2
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
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly $script:SkeletonLine2
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
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly $script:SkeletonLine2
    }

    It 'runs nothing, writes nothing, and names the path and program under -WhatIf' {
        $markerPath = Join-Path -Path $script:CaseFolder -ChildPath 'marker.txt'
        $fixture = Join-Path -Path $script:CaseFolder -ChildPath 'marker-help.ps1'
        Set-Content -LiteralPath $fixture -Encoding utf8 -Value ("Set-Content -LiteralPath '{0}' -Value 'ran'" -f $markerPath)
        $target = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'

        $output = Invoke-TestWhatIfChild -Case 'HelpArgument' -CommandName 'pwsh' -Target $target -Fixture $fixture

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
        $output | Should -Contain 'COUNT=0'
        $output | Should -Contain 'EXISTS=False'
        Test-Path -LiteralPath $markerPath | Should -BeFalse
        $whatIfLine = 'What if: Performing the operation "Create completer script, running ''{0} {1}'' to read its help" on target "{2}".' -f $script:PwshPath, $fixture, $target
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

        $target = Join-Path -Path $script:CaseFolder -ChildPath "$($CommandName)_completer.ps1"
        $output = Invoke-TestWhatIfChild -Case $Child -CommandName $CommandName -Target $target -Fixture 'help'

        $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
        $output | Should -Contain 'COUNT=0'
        $output | Should -Contain 'EXISTS=False'
        $action = if ($Action.StartsWith('running')) { 'Create completer script, ' + $Action.Replace('<pwsh>', $script:PwshPath) } else { 'Create completer script ' + $Action }
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

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -WhatIf } | Should -Throw -PassThru
        }
        finally
        {
            $env:PATH = $savedPath
        }

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
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $result = New-TestExitedResult -Text "Commands:`n  build    Compile the project`n"
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                [System.IO.File]::WriteAllText($scriptPath, 'appeared during the probe')
                $result
            }.GetNewClosure())

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument '--help' } | Should -Throw -PassThru
        }
        finally
        {
            $env:PATH = $savedPath
        }

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
        @{ Case = 'the name _.exe'; CommandName = '_.exe'; Leaf = 'x_completer.ps1'; Reason = "The command name '_.exe' has no letter or digit outside its suffix, so no function name can be derived from it." }
        @{ Case = 'the name __.cmd'; CommandName = '__.cmd'; Leaf = 'x_completer.ps1'; Reason = "The command name '__.cmd' has no letter or digit outside its suffix, so no function name can be derived from it." }
    ) {
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:CaseFolder -ChildPath 'folder.ps1')
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath $Leaf.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
        $expectedReason = $Reason.Replace('<case>', $script:CaseFolder) -f [System.IO.Path]::DirectorySeparatorChar

        $thrown = { New-CompleterScript -CommandName $CommandName -Path $scriptPath -NoProbe } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + $expectedReason)
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Recurse -File -Force).Count | Should -Be 0
    }

    It 'writes Complete-A_34fb7160 for the name _a, whose letter is outside any suffix' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'a_completer.ps1'

        New-CompleterScript -CommandName '_a' -Path $scriptPath -NoProbe

        $text = Get-Content -LiteralPath $scriptPath -Raw
        $text | Should -BeLikeExactly '*function Complete-A_34fb7160 {*'
        $text | Should -BeLikeExactly "*-CommandName '_a', '_a.exe' -ScriptBlock*"
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
    }

    It 'fails a -HelpArgument that holds <Case>, before anything runs or is written' -TestCases @(
        @{ Case = 'a carriage return'; HelpArgument = "--he`rlp" }
        @{ Case = 'a line feed'; HelpArgument = "--he`nlp" }
        @{ Case = 'a CR LF pair'; HelpArgument = "--he`r`nlp" }
    ) {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $result = New-TestExitedResult -Text "Commands:`n  build    Compile the project`n"
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                $result
            }.GetNewClosure())

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument $HelpArgument } | Should -Throw -PassThru
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $thrown.Exception.Message | Should -BeExactly 'Failed to create completer script. -HelpArgument must not contain a line break.'
        @(Get-TestProbeRun).Count | Should -Be 0
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

        $output = @(& $script:PwshPath -NoProfile -NoLogo -NonInteractive -File $childPath -ManifestPath $script:ManifestPath -CommandName $CommandName -Target $scriptPath -Action $Action 2>&1 | ForEach-Object { "$_" })

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
                param($Name, $Stem, $Target, $Subcommand, $Option, $SeedKind, $ProbeArgument)

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

    It 'fails with the self-check text and leaves neither file when the composer emits a cast in the option table' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestSkeletonOriginal = ${function:Get-CompleterScriptSkeleton}
            function script:Get-CompleterScriptSkeleton
            {
                param($Name, $Stem, $Target, $Subcommand, $Option, $SeedKind, $ProbeArgument)

                $script:TestSkeletonLines = @(& $script:TestSkeletonOriginal @PSBoundParameters)
                $optionsLine = [array]::IndexOf($script:TestSkeletonLines, '        Options = @(')
                $script:TestSkeletonLines[$optionsLine + 1] = $script:TestSkeletonLines[$optionsLine + 1].Replace('@{ Name', '[ordered]@{ Name')
                $script:TestSkeletonLines
            }
        }

        $thrown = { New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -Documentation } | Should -Throw -PassThru

        $castLine = & (Get-Module -Name 'CompleterActions') { $script:TestSkeletonLines | Where-Object { $_.Contains('[ordered]@{ Name') } }
        @($castLine).Count | Should -Be 1
        $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + $script:SelfCheckPrefix + "The script contains unsupported top-level expression 'ConvertExpressionAst'.")
        @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 0
    }

    It 'writes the resolved-application, probe, and wrote verbose lines with the subcommand and option counts' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $helpText = "Options:`n  -h, --help     Print help`n  -V, --version  Print version`n  -q             Be quiet`n`nCommands:`n  build    Compile the project`n  test     Run the tests`n"
        $result = New-TestExitedResult -Text $helpText
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                $result
            }.GetNewClosure())

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $verbose = @(New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument '--help' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $verbose.Count | Should -Be 4 -Because ($verbose -join [System.Environment]::NewLine)
        $verbose[0] | Should -BeExactly ("Resolved 'pwsh' to the application '{0}'." -f $script:PwshPath)
        $verbose[1] | Should -BeExactly ('Performing the operation "Create completer script, running ''{0} --help'' to read its help" on target "{1}".' -f $script:PwshPath, $scriptPath)
        $verbose[2] | Should -BeExactly ("Probed '{0} --help': exit 0, {1} characters, 2 subcommands, 5 options, 12 ms." -f $script:PwshPath, $helpText.Length)
        $verbose[3] | Should -BeExactly ("Wrote '{0}': 2 targets, 2 subcommands, 5 options." -f $scriptPath)
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ("# Help-seeded native completer: the tables were read from 'pwsh --help' when the script was generated.")
        (@((Get-TestCatalog -LiteralPath $scriptPath).Options | ForEach-Object { $_.Name }) -join ',') | Should -BeExactly '-h,--help,-V,--version,-q'
    }

    It 'seeds the tables and line 2 from a probe that yields options and no subcommand' {
        $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
        $result = New-TestExitedResult -Text "  -a, --all    Show all`n  -b, --brief  Be brief`n"
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                $result
            }.GetNewClosure())

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
            $verbose = @(New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        }
        finally
        {
            $env:PATH = $savedPath
        }

        (@(Get-TestProbeRun | ForEach-Object { $_.ArgumentList[0] }) -join ',') | Should -BeExactly '--help'
        @($verbose | Where-Object { $_ -ceq ("Wrote '{0}': 2 targets, 0 subcommands, 4 options." -f $scriptPath) }).Count | Should -Be 1 -Because ($verbose -join [System.Environment]::NewLine)
        @(Get-Content -LiteralPath $scriptPath)[1] | Should -BeExactly ("# Help-seeded native completer: the tables were read from 'pwsh --help' when the script was generated.")
        Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
    }

    It 'shows the three parameter sets of section 2 with -Documentation in each' {
        $syntax = @((Get-Command -Name 'New-CompleterScript' -Syntax) -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })

        $syntax | Should -Be @(
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> [-HelpArgument <string>] [-Documentation] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> -HelpText <string[]> [-Documentation] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
            'New-CompleterScript [-CommandName] <string[]> [-Path] <string> -NoProbe [-Documentation] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
        )
    }

    Context 'Documentation' {
        It 'writes the markdown file beside the script with the three section 3 lines for rg' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'

            New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Documentation

            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
            $lines = @(Get-Content -LiteralPath $markdownPath)
            $lines | Should -Be @(
                '# rg completer'
                ''
                '## What it completes'
                ''
                '`rg_completer.ps1` registers a native PowerShell completer for `rg` and `rg.exe`.'
            )
            @($lines | Where-Object { $_.Length -gt 0 }).Count | Should -Be 3
        }

        It 'names every target of a two-name call in registration order' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'fd_completer.ps1'

            New-CompleterScript -CommandName 'fd', 'fdfind' -Path $scriptPath -NoProbe -Documentation

            $lines = @(Get-Content -LiteralPath (Join-Path -Path $script:CaseFolder -ChildPath 'fd_completer.md'))
            $lines[0] | Should -BeExactly '# fd completer'
            $lines[4] | Should -BeExactly '`fd_completer.ps1` registers a native PowerShell completer for `fd`, `fd.exe`, `fdfind`, and `fdfind.exe`.'
        }

        It 'names a single target alone' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'npm_completer.ps1'

            New-CompleterScript -CommandName 'npm.cmd' -Path $scriptPath -NoProbe -Documentation

            @(Get-Content -LiteralPath (Join-Path -Path $script:CaseFolder -ChildPath 'npm_completer.md'))[4] | Should -BeExactly '`npm_completer.ps1` registers a native PowerShell completer for `npm.cmd`.'
        }

        It 'writes UTF-8 without a byte-order mark, platform newlines, and a final newline, identically twice' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'

            New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -Documentation
            $first = [System.IO.File]::ReadAllBytes($markdownPath)
            New-CompleterScript -CommandName 'rg' -Path $scriptPath -HelpText (Get-TestCapture -Tool 'rg') -Documentation -Force
            $second = [System.IO.File]::ReadAllBytes($markdownPath)

            ($first.Length -ge 3 -and $first[0] -eq 0xEF -and $first[1] -eq 0xBB -and $first[2] -eq 0xBF) | Should -BeFalse
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($first)
            $expected = @(
                '# rg completer'
                ''
                '## What it completes'
                ''
                '`rg_completer.ps1` registers a native PowerShell completer for `rg` and `rg.exe`.'
            ) -join [System.Environment]::NewLine
            $text | Should -BeExactly ($expected + [System.Environment]::NewLine)
            [System.Convert]::ToBase64String($second) | Should -BeExactly ([System.Convert]::ToBase64String($first))
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
        }

        It 'fails before anything is resolved when the markdown file exists without -Force, and replaces both files with -Force' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'pwsh_completer.md'
            [System.IO.File]::WriteAllText($markdownPath, 'existing markdown')

            & (Get-Module -Name 'CompleterActions') {
                $script:TestResolveCount = 0
                function script:Resolve-CompleterHelpProbeApplication
                {
                    param($Name)

                    $script:TestResolveCount++
                }
            }

            $savedPath = $env:PATH
            try
            {
                $env:PATH = $PSHOME + [System.IO.Path]::PathSeparator + $savedPath
                $thrown = { New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -Documentation } | Should -Throw -PassThru
            }
            finally
            {
                $env:PATH = $savedPath
            }

            $thrown.Exception.Message | Should -BeExactly ('Failed to create completer script. ' + ($script:AlreadyExistsFormat -f $markdownPath))
            (& (Get-Module -Name 'CompleterActions') { $script:TestResolveCount }) | Should -Be 0
            Test-Path -LiteralPath $scriptPath | Should -BeFalse
            [System.IO.File]::ReadAllText($markdownPath) | Should -BeExactly 'existing markdown'

            [System.IO.File]::WriteAllText($scriptPath, 'existing script')
            New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Documentation -Force

            @(Get-Content -LiteralPath $scriptPath)[0] | Should -BeExactly '# rg tab completion for PowerShell'
            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
            @(Get-Content -LiteralPath $markdownPath)[0] | Should -BeExactly '# rg completer'
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
        }

        It 'fails before anything runs when a directory sits at the markdown path, <Case>, and writes neither file' -TestCases @(
            @{ Case = 'without -Force'; Force = $false }
            @{ Case = 'with -Force'; Force = $true }
        ) {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'
            $null = New-Item -ItemType Directory -Path $markdownPath

            $thrown = { New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Documentation -Force:$Force } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -BeExactly ("Failed to create completer script. Documentation files must be file paths. '{0}' is a directory." -f $markdownPath)
            Test-Path -LiteralPath $scriptPath | Should -BeFalse
            Test-Path -LiteralPath $markdownPath -PathType Leaf | Should -BeFalse
            Get-ChildItem -LiteralPath $markdownPath -Force | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Force | ForEach-Object Name) | Should -Be @('rg_completer.md')
        }

        It 'fails with the was-written text when the markdown move fails, and keeps the script' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'

            InModuleScope -ModuleName 'CompleterActions' -ScriptBlock {
                $script:TestMoveOriginal = ${function:Move-CompleterScriptFile}
                $script:TestMoves = [System.Collections.Generic.List[string]]::new()
                function script:Move-CompleterScriptFile
                {
                    param($LiteralPath, $Destination, [switch] $Force)

                    $script:TestMoves.Add($Destination)
                    if ($Destination.EndsWith('.md'))
                    {
                        throw 'the test made the markdown move fail'
                    }

                    & $script:TestMoveOriginal @PSBoundParameters
                }
            }

            $thrown = { New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Documentation } | Should -Throw -PassThru

            $thrown.Exception.Message | Should -BeExactly ("Failed to create completer script. The script '{0}' was written, but its documentation file '{1}' was not: the test made the markdown move fail" -f $scriptPath, $markdownPath)
            (@(InModuleScope -ModuleName 'CompleterActions' -ScriptBlock { $script:TestMoves.ToArray() }) -join '|') | Should -BeExactly (@($scriptPath, $markdownPath) -join '|')
            Test-Path -LiteralPath $scriptPath | Should -BeTrue
            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
            Test-Path -LiteralPath $markdownPath | Should -BeFalse
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Filter '*.tmp' -Force).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 1
        }

        It 'neither opens nor changes an existing markdown file without the switch' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'
            [System.IO.File]::WriteAllText($markdownPath, 'existing markdown')
            $written = [datetime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
            [System.IO.File]::SetLastWriteTimeUtc($markdownPath, $written)

            # An exclusive handle makes any open of the file by the command fail.
            $handle = [System.IO.File]::Open($markdownPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            try
            {
                New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe
            }
            finally
            {
                $handle.Dispose()
            }

            Test-CompleterScript -LiteralPath $scriptPath | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($markdownPath) | Should -BeExactly 'existing markdown'
            [System.IO.File]::GetLastWriteTimeUtc($markdownPath) | Should -Be $written
        }

        It 'returns only the script FileInfo with -PassThru and writes the markdown verbose line after the script one' {
            $scriptPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.ps1'
            $markdownPath = Join-Path -Path $script:CaseFolder -ChildPath 'rg_completer.md'

            $output = @(New-CompleterScript -CommandName 'rg' -Path $scriptPath -NoProbe -Documentation -PassThru -Verbose 4>&1)

            $files = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
            $files.Count | Should -Be 1
            $files[0] | Should -BeOfType ([System.IO.FileInfo])
            $files[0].FullName | Should -Be $scriptPath
            Test-Path -LiteralPath $markdownPath | Should -BeTrue

            $verbose = @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
            $verbose[-2] | Should -BeExactly ("Wrote '{0}': 2 targets, 0 subcommands, 0 options." -f $scriptPath)
            $verbose[-1] | Should -BeExactly ("Wrote '{0}'." -f $markdownPath)
        }

        It 'writes neither file and names the documentation in the action under -WhatIf for <Case>' -TestCases @(
            @{ Case = 'the default probe on Windows'; Platform = 'Windows'; Child = 'Default'; CommandName = 'pwsh'; Action = ", running '<pwsh> --help' and, if it is rejected, '/?' to read its help" }
            @{ Case = 'the default probe on Linux and macOS'; Platform = 'Unix'; Child = 'Default'; CommandName = 'pwsh'; Action = ", running '<pwsh> --help' to read its help" }
            @{ Case = '-HelpArgument'; Platform = 'Any'; Child = 'HelpArgument'; CommandName = 'pwsh'; Action = ", running '<pwsh> help' to read its help" }
            @{ Case = 'the HelpText set'; Platform = 'Any'; Child = 'HelpText'; CommandName = 'fx'; Action = ' without running a program' }
            @{ Case = 'the NoProbe set'; Platform = 'Any'; Child = 'NoProbe'; CommandName = 'fx'; Action = ' without running a program' }
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

            $target = Join-Path -Path $script:CaseFolder -ChildPath "$($CommandName)_completer.ps1"
            $output = Invoke-TestWhatIfChild -Case $Child -CommandName $CommandName -Target $target -Fixture 'help' -Documentation

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
            $output | Should -Contain 'COUNT=0'
            $output | Should -Contain 'EXISTS=False'
            $output | Should -Contain 'MDEXISTS=False'
            $whatIfLine = 'What if: Performing the operation "Create completer script and documentation{0}" on target "{1}".' -f $Action.Replace('<pwsh>', $script:PwshPath), $target
            @($output | Where-Object { $_ -ceq $whatIfLine }).Count | Should -Be 1 -Because ($output -join [System.Environment]::NewLine)
            @(Get-ChildItem -LiteralPath $script:CaseFolder -Force).Count | Should -Be 0
        }
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
