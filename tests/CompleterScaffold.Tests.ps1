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
        Set-Content -LiteralPath $scriptPath -Value 'existing content' -Encoding utf8
        $before = [System.IO.File]::ReadAllBytes($scriptPath)

        $thrown = {
            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ ScriptPath = $scriptPath } -ScriptBlock {
                param($ScriptPath)

                $lines = @(Get-CompleterScriptSkeleton -Name 'rg' -Stem 'Rg' -Target 'rg', 'rg.exe' -Subcommand @())
                Save-CompleterScriptFile -Line $lines -LiteralPath $ScriptPath -ExpectedTarget 'rg', 'rg.exe'
            }
        } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeExactly ($script:AlreadyExistsFormat -f $scriptPath)
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($scriptPath)) | Should -BeExactly ([System.Convert]::ToBase64String($before))
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
