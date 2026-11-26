BeforeAll {
    $script:ManifestPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'CompleterActions.psd1'
    $script:HelpFixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/NewCompleterScript'

    function ConvertFrom-TestHelpOutput
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [byte[]] $Bytes
        )

        InModuleScope CompleterActions -Parameters @{ Bytes = $Bytes } {
            ConvertFrom-CompleterHelpOutput -Bytes $Bytes
        }
    }

    function ConvertTo-TestCleanHelpText
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        InModuleScope CompleterActions -Parameters @{ Text = $Text } {
            ConvertTo-CompleterCleanHelpText -Text $Text
        }
    }

    function ConvertFrom-TestHelpText
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        @(InModuleScope CompleterActions -Parameters @{ Text = $Text } {
            ConvertFrom-CompleterHelpText -Text $Text
        })
    }

    function ConvertFrom-TestHelpOption
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        @(InModuleScope CompleterActions -Parameters @{ Text = $Text } {
            ConvertFrom-CompleterHelpOption -Text $Text
        })
    }
}

Describe 'Help text decoding, cleaning, and parsing' {
    BeforeAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null
    }

    AfterAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'decodes UTF-16 LE without and with a byte-order mark to the same text' {
        $text = "Commands:`n  build  Compile`n"
        $plain = [System.Text.Encoding]::Unicode.GetBytes($text)
        $withMark = [byte[]] (@([byte] 0xFF, [byte] 0xFE) + $plain)

        ConvertFrom-TestHelpOutput -Bytes $plain | Should -BeExactly $text
        ConvertFrom-TestHelpOutput -Bytes $withMark | Should -BeExactly $text
    }

    It 'drops a UTF-8 byte-order mark' {
        $text = "caf$([char] 0xE9) Commands:`n"
        $bytes = [byte[]] (@([byte] 0xEF, [byte] 0xBB, [byte] 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($text))

        ConvertFrom-TestHelpOutput -Bytes $bytes | Should -BeExactly $text
    }

    It 'decodes the bytes 63 61 66 82 with the OEM code page on Windows and Latin-1 elsewhere' {
        $bytes = [byte[]] (0x63, 0x61, 0x66, 0x82)
        $expected = if ($IsWindows)
        {
            [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString([byte[]] (0x63, 0x61, 0x66, 0x82))
        }
        else
        {
            "caf$([char] 0x82)"
        }

        ConvertFrom-TestHelpOutput -Bytes $bytes | Should -BeExactly $expected
    }

    It 'removes a leading U+FEFF that a decoder leaves' {
        $bytes = [byte[]] (0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x41)

        ConvertFrom-TestHelpOutput -Bytes $bytes | Should -BeExactly 'A'
    }

    It 'cleans <Case>' -TestCases @(
        @{ Case = 'a CSI colour'; Text = "`e[1;32mbuild`e[0m  Compile"; Expected = 'build  Compile' }
        @{ Case = 'an OSC 8 hyperlink'; Text = "See `e]8;;https://example.com/docs`e\docs`e]8;;`e\ online"; Expected = 'See docs online' }
        @{ Case = 'a two-character escape'; Text = "`eMbuild`eD  Compile"; Expected = 'build  Compile' }
        @{ Case = 'a backspace overstrike'; Text = "`bb`bbu`bu_`bil`bld  Compile"; Expected = 'build  Compile' }
        @{ Case = 'CR LF'; Text = "Commands:`r`n  build  Compile`r`n"; Expected = "Commands:`n  build  Compile`n" }
        @{ Case = 'a CR progress line'; Text = "Loading 10%`rLoading 100%`rCommands:`n  build  Compile"; Expected = "Commands:`n  build  Compile" }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string] $Expected
        )

        ConvertTo-TestCleanHelpText -Text $Text | Should -BeExactly $Expected
    }

    It 'cleans a long nested backspace run in linear time' {
        $text = ('a' * 20000) + ([string] [char] 0x08 * 20000) + 'build'
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

        ConvertTo-TestCleanHelpText -Text $text | Should -BeExactly 'build'
        $elapsed.Stop()
        $elapsed.Elapsed.TotalSeconds | Should -BeLessThan 5
    }

    It 'parses the <Tool> capture to exactly its expected names in order' -TestCases @(
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
        param(
            [string] $Tool
        )

        $text = Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath "$Tool.txt") -Raw
        $expected = @(Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath "$Tool.names.txt"))

        $names = @(ConvertFrom-TestHelpText -Text (ConvertTo-TestCleanHelpText -Text $text) | ForEach-Object -MemberName Name)

        $names.Count | Should -Be $expected.Count
        $names -join "`n" | Should -BeExactly ($expected -join "`n")
    }

    It 'matches the header <Line>' -TestCases @(
        @{ Line = 'Commands:' }
        @{ Line = 'Common Commands:' }
        @{ Line = 'CORE COMMANDS' }
        @{ Line = 'SDK commands:' }
        @{ Line = 'Basic Commands (Beginner):' }
        @{ Line = 'Subcommands provided by plugins:' }
        @{ Line = 'The following commands are available:' }
        @{ Line = 'The commands are:' }
        @{ Line = '<Commands>' }
        @{ Line = 'Additional commands from bundled tools:' }
    ) {
        param(
            [string] $Line
        )

        $rows = ConvertFrom-TestHelpText -Text "$Line`n  build  Compile the package"

        $rows.Name | Should -BeExactly @('build')
    }

    It 'does not match <Line> as a header' -TestCases @(
        @{ Line = 'These are common Git commands used in various situations:' }
        @{ Line = 'Parameter List:' }
        @{ Line = 'Options:' }
    ) {
        param(
            [string] $Line
        )

        ConvertFrom-TestHelpText -Text "$Line`n  build  Compile the package" | Should -BeNullOrEmpty
    }

    It 'skips <Line> after a header' -TestCases @(
        @{ Line = '' }
        @{ Line = '=======' }
        @{ Line = '-------' }
    ) {
        param(
            [string] $Line
        )

        $rows = ConvertFrom-TestHelpText -Text "Commands:`n$Line`n  build  Compile the package"

        $rows.Name | Should -BeExactly @('build')
    }

    It 'reads an entry with the separator <Case>' -TestCases @(
        @{ Case = "': '"; Text = "Commands:`n  auth:   Authenticate gh`n  a : Add files"; Names = @('auth', 'a'); Descriptions = @('Authenticate gh', 'Add files') }
        @{ Case = "'-----'"; Text = "Commands:`n  query-----------Queries the status"; Names = @('query'); Descriptions = @('Queries the status') }
        @{ Case = "' - '"; Text = "Commands:`n  build - Compile the package"; Names = @('build'); Descriptions = @('Compile the package') }
        @{ Case = 'two spaces'; Text = "Commands:`n  build  Compile the package"; Names = @('build'); Descriptions = @('Compile the package') }
        @{ Case = 'tab'; Text = "Commands:`n  build`tCompile the package"; Names = @('build'); Descriptions = @('Compile the package') }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string[]] $Names,
            [string[]] $Descriptions
        )

        $rows = ConvertFrom-TestHelpText -Text $Text

        $rows.Name | Should -BeExactly $Names
        $rows.Description | Should -BeExactly $Descriptions
    }

    It 'drops a trailing star and comma-separated aliases from a name' {
        $text = "Commands:`n  ai*         Ask the agent`n  build, b    Compile`n  check, c, chk  Analyze"

        $rows = ConvertFrom-TestHelpText -Text $text

        $rows.Name | Should -BeExactly @('ai', 'build', 'check')
        $rows.Description | Should -BeExactly @('Ask the agent', 'Compile', 'Analyze')
    }

    It 'skips deeper continuation lines and wrapped or unknown lines without ending the section' {
        $text = @(
            'Commands:'
            '  query-----------Queries the status for a service, or'
            '                  enumerates the status for types of services.'
            '      nested  A deeper entry is a continuation'
            '  qmanagedaccount-Queries whether the service is a managed account.'
            '  check       Verify installed packages have compatible'
            'dependencies.'
            '  start-----------Starts a service.'
        ) -join "`n"

        $rows = ConvertFrom-TestHelpText -Text $text

        $rows.Name | Should -BeExactly @('query', 'check', 'start')
        $rows[0].Description | Should -BeExactly 'Queries the status for a service, or'
    }

    It 'ends a section at <Case>' -TestCases @(
        @{ Case = 'a blank line'; Text = "Commands:`n  build  Compile`n`n  test  Run the tests"; Names = @('build') }
        @{ Case = 'a header'; Text = "Commands:`n    build  Compile`nMore commands:`n  test  Run the tests`n    lint  Deeper, so a continuation"; Names = @('build', 'test') }
        @{ Case = 'a shallower entry'; Text = "  Commands:`n    build  Compile`n  test  Run the tests`n    lint  Check the style"; Names = @('build') }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string[]] $Names
        )

        $rows = ConvertFrom-TestHelpText -Text $Text

        $rows.Name | Should -BeExactly $Names
    }

    It 'keeps names in help order and drops case-insensitive duplicates' {
        $text = "Commands:`n  zeta  Last letter`n  alpha  First letter`n  Zeta  Duplicate`n  ALPHA  Duplicate`n  beta  Second letter"

        $rows = ConvertFrom-TestHelpText -Text $text

        $rows.Name | Should -BeExactly @('zeta', 'alpha', 'beta')
        $rows.Description | Should -BeExactly @('Last letter', 'First letter', 'Second letter')
    }

    It 'replaces control, format, and separator characters in a description and uses the name for an empty one' {
        $description = "Com`0pile$([char] 0x202E)the$([char] 0x200B)pack$([char] 0x2028)age$([char] 0x2029)now`t  done$([char] 0x7F)  "
        $text = "Commands:`n  build  $description`n  test:   "

        $rows = ConvertFrom-TestHelpText -Text $text

        $rows.Name | Should -BeExactly @('build', 'test')
        $rows[0].Description | Should -BeExactly 'Com pile the pack age now done'
        $rows[1].Description | Should -BeExactly 'test'
    }

    It 'returns no rows for help without a commands section' {
        $text = "Usage: rg [OPTIONS] PATTERN`n`nOptions:`n  -i, --ignore-case  Search case insensitively`n  --version  Print the version"

        ConvertFrom-TestHelpText -Text $text | Should -BeNullOrEmpty
        ConvertFrom-TestHelpText -Text '' | Should -BeNullOrEmpty

        $prose = "Options:`n    --one-file-system`n        example, in the command`n`n            rg --one-file-system /foo/bar`n`n        ripgrep  will search both paths"
        ConvertFrom-TestHelpText -Text $prose | Should -BeNullOrEmpty
    }
}

Describe 'Option parsing' {
    BeforeAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null
    }

    AfterAll {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'parses the <Tool> capture to exactly its expected option and subcommand names in order' -TestCases @(
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
        param(
            [string] $Tool
        )

        $text = Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath "$Tool.txt") -Raw
        $expectedOptions = @(Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath "$Tool.options.txt"))
        $expectedSubcommands = @(Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath "$Tool.names.txt"))
        $cleanText = ConvertTo-TestCleanHelpText -Text $text

        $options = @(ConvertFrom-TestHelpOption -Text $cleanText | ForEach-Object -MemberName Name)
        $subcommands = @(ConvertFrom-TestHelpText -Text $cleanText | ForEach-Object -MemberName Name)

        $options.Count | Should -Be $expectedOptions.Count
        $options -join "`n" | Should -BeExactly ($expectedOptions -join "`n")
        $subcommands -join "`n" | Should -BeExactly ($expectedSubcommands -join "`n")
    }

    It 'takes the description of a row without one from the next deeper line in the rg and pip captures' {
        $rgText = Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath 'rg.txt') -Raw
        $pipText = Get-Content -LiteralPath (Join-Path -Path $script:HelpFixtureRoot -ChildPath 'pip.txt') -Raw

        $rg = @(ConvertFrom-TestHelpOption -Text (ConvertTo-TestCleanHelpText -Text $rgText))
        $pip = @(ConvertFrom-TestHelpOption -Text (ConvertTo-TestCleanHelpText -Text $pipText))

        $rg[0].Name | Should -BeExactly '-e'
        $rg[0].Description | Should -BeExactly 'A pattern to search for. This option can be provided multiple times,'
        $rg[1].Name | Should -BeExactly '--regexp'
        $rg[1].Description | Should -BeExactly $rg[0].Description
        ($pip | Where-Object -Property Name -CEQ -Value '--keyring-provider').Description | Should -BeExactly 'Enable the credential lookup via the keyring'
    }

    It 'opens a section at a heading only when its next non-blank line is an option line' {
        $prose = @('Options:', '  Some prose comes first.', '  -a  Alpha') -join "`n"
        $direct = @('Options:', '', '  -a  Alpha') -join "`n"

        ConvertFrom-TestHelpOption -Text $prose | Should -BeNullOrEmpty
        (ConvertFrom-TestHelpOption -Text $direct).Name | Should -BeExactly @('-a')
    }

    It 'opens a section at a heading whose first line is a bare --, which gives no row' {
        $withHeading = @('<Switches>', '  -- : Stop switches parsing', ' See the note.', '  -x : Exclude') -join "`n"
        $withoutHeading = @('Switches follow.', '  -- : Stop switches parsing', ' See the note.', '  -x : Exclude') -join "`n"

        $rows = ConvertFrom-TestHelpOption -Text $withHeading

        $rows.Name | Should -BeExactly @('-x')
        $rows.Description | Should -BeExactly @('Exclude')
        ConvertFrom-TestHelpOption -Text $withoutHeading | Should -BeNullOrEmpty
    }

    It 'opens a section without a heading at <Case>' -TestCases @(
        @{ Case = 'two option lines at one indent'; Text = (@('Usage: tool [OPTION]...', '', '  -a, --all  Show all', '  -b  Be brief') -join "`n"); Names = @('-a', '--all', '-b') }
        @{ Case = 'two option lines with a blank line between'; Text = (@('  -a  Show all', '', '  -b  Be brief') -join "`n"); Names = @('-a', '-b') }
        @{ Case = 'a single option line'; Text = (@('Usage: tool', '', '  -a, --all  Show all', '', 'More text.') -join "`n"); Names = @() }
        @{ Case = 'two option lines at different indents'; Text = (@('  -a  Show all', '    -b  Be brief') -join "`n"); Names = @() }
        @{ Case = 'two option lines with a prose line at the row indent between'; Text = (@('  -a  Alpha', '  Some prose at the row indent.', '  -b  Beta') -join "`n"); Names = @('-a', '-b') }
        @{ Case = 'two option lines with a heading-shaped prose line at the row indent between'; Text = (@('Usage: x', '  -a  A', '  Some prose here', '  -b  B') -join "`n"); Names = @('-a', '-b') }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string[]] $Names
        )

        $rows = @(ConvertFrom-TestHelpOption -Text $Text | ForEach-Object -MemberName Name)

        $rows -join ' ' | Should -BeExactly ($Names -join ' ')
    }

    It 'opens no second section at a heading-shaped description line and reads no deeper example line' {
        $text = @(
            'OPTIONS:'
            '    --alpha'
            '        flag again:'
            '        --beta  An example, not a row'
            '        --delta  Another example'
        ) -join "`n"

        $rows = ConvertFrom-TestHelpOption -Text $text

        $rows.Name | Should -BeExactly @('--alpha')
        $rows.Description | Should -BeExactly @('flag again:')
    }

    It 'reads no single-dash line deeper than the section indent' {
        $text = @(
            '<Switches>'
            '  -m{Parameters} : set compression Method'
            '    -mmt[N] : set number of CPU threads'
            '    -mx[N] : set compression level'
            '  -o{Directory} : set Output directory'
        ) -join "`n"

        $rows = ConvertFrom-TestHelpOption -Text $text

        $rows.Name | Should -BeExactly @('-m', '-o')
        $rows.Description | Should -BeExactly @('set compression Method', 'set Output directory')
    }

    It 'does not end a section at a blank line or a deeper line between rows' {
        $text = @(
            'Parameter List:'
            '    /Create         Creates a new scheduled task.'
            '                    Wrapped prose.'
            ''
            '    /Delete         Deletes the scheduled task(s).'
        ) -join "`n"

        (ConvertFrom-TestHelpOption -Text $text).Name | Should -BeExactly @('/Create', '/Delete')
    }

    It 'ends a section at <Case>' -TestCases @(
        @{ Case = 'a line at heading indent'; Text = (@('Options:', '  -a  Alpha', 'See the manual for more.', '  -b  Beta') -join "`n"); Names = @('-a') }
        @{ Case = 'a line shallower than the rows of a section without a heading'; Text = (@('  -a  Alpha', '  -b  Beta', ' See more.', '  -c  Gamma') -join "`n"); Names = @('-a', '-b') }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string[]] $Names
        )

        (ConvertFrom-TestHelpOption -Text $Text).Name | Should -BeExactly $Names
    }

    It 'ends a name at the first other character and reads -. as a short name' {
        $text = @('Options:', '  -v, --verbose...  Use verbose output', '  -., --hidden      Search hidden files') -join "`n"

        $rows = ConvertFrom-TestHelpOption -Text $text

        $rows.Name | Should -BeExactly @('-v', '--verbose', '-.', '--hidden')
        $rows.Description | Should -BeExactly @('Use verbose output', 'Use verbose output', 'Search hidden files', 'Search hidden files')
    }

    It 'reads long-only lines four columns deep as rows only when no row at the section indent starts with --' {
        $cargo = @(
            'Options:'
            '  -V, --version  Print version info'
            '      --list     List installed commands'
            '        --deeper Not four columns deeper'
            '  -h, --help     Print help'
        ) -join "`n"
        $rg = @(
            'OPTIONS:'
            '    --pre=COMMAND'
            '        --no-pre disables this.'
            '    -z, --search-zip'
            '        Search in compressed files.'
        ) -join "`n"

        $cargoRows = ConvertFrom-TestHelpOption -Text $cargo
        $rgRows = ConvertFrom-TestHelpOption -Text $rg

        $cargoRows.Name | Should -BeExactly @('-V', '--version', '--list', '-h', '--help')
        $rgRows.Name | Should -BeExactly @('--pre', '-z', '--search-zip')
        $rgRows[0].Description | Should -BeExactly '--no-pre disables this.'
    }

    It 'reads long-only lines four columns deep as rows when the only -- lines at the section indent are <Case>' -TestCases @(
        @{ Case = 'a bare --'; Text = (@('<Switches>', '  -- : Stop switches parsing', '  -a  Alpha', '      --deep  Deep long') -join "`n") }
        @{ Case = 'under a commands heading'; Text = (@('<Switches>', '  -a  Alpha', '  Commands:', '  build  Compile', '  --list  x', '', '      --deep  Deep long') -join "`n") }
    ) {
        param(
            [string] $Case,
            [string] $Text
        )

        $rows = ConvertFrom-TestHelpOption -Text $Text

        $rows.Name | Should -BeExactly @('-a', '--deep')
        $rows.Description | Should -BeExactly @('Alpha', 'Deep long')
    }

    It 'reads no single-dash line four columns deeper when no row at the section indent starts with --, and takes it as a description' {
        $deeper = @(
            'Options:'
            '  -V, --version  Print version info'
            '      -x  Deeper single dash'
            '  -h, --help     Print help'
        ) -join "`n"
        $description = @(
            'Options:'
            '  -q'
            '      -x  Deeper single dash'
            '  -h  Print help'
        ) -join "`n"

        $deeperRows = ConvertFrom-TestHelpOption -Text $deeper
        $descriptionRows = ConvertFrom-TestHelpOption -Text $description

        $deeperRows.Name | Should -BeExactly @('-V', '--version', '-h', '--help')
        $descriptionRows.Name | Should -BeExactly @('-q', '-h')
        $descriptionRows.Description | Should -BeExactly @('-x Deeper single dash', 'Print help')
    }

    It 'reads <Row> as the names <Names> and drops the placeholder' -TestCases @(
        @{ Row = '-x, --long <ARG>  Desc'; Names = @('-x', '--long') }
        @{ Row = '-x,--long  Desc'; Names = @('-x', '--long') }
        @{ Row = '--long=VALUE  Desc'; Names = @('--long') }
        @{ Row = '--long[=VALUE]  Desc'; Names = @('--long') }
        @{ Row = '-e PATTERN, --regexp=PATTERN  Desc'; Names = @('-e', '--regexp') }
        @{ Row = '--context string  Desc'; Names = @('--context') }
        @{ Row = '-ao{a|s}  Desc'; Names = @('-ao') }
        @{ Row = '-bb[0-3] : Desc'; Names = @('-bb') }
        @{ Row = '/X  Desc'; Names = @('/X') }
        @{ Row = '-?,--help  Desc'; Names = @('-?', '--help') }
        @{ Row = '-x, not-a-name  Desc'; Names = @('-x') }
        @{ Row = '-x <ARG>, --long  Desc'; Names = @('-x', '--long') }
        @{ Row = '-ao{a|s}, --overwrite  Desc'; Names = @('-ao', '--overwrite') }
        @{ Row = '-bb[0-3], --level  Desc'; Names = @('-bb', '--level') }
        @{ Row = '--long=VALUE, -l  Desc'; Names = @('--long', '-l') }
        @{ Row = '--long[=VALUE], -l  Desc'; Names = @('--long', '-l') }
        @{ Row = '-c string, --context  Desc'; Names = @('-c', '--context') }
    ) {
        param(
            [string] $Row,
            [string[]] $Names
        )

        $rows = ConvertFrom-TestHelpOption -Text "Options:`n  $Row"

        $rows.Name | Should -BeExactly $Names
        @($rows.Description | Select-Object -Unique) | Should -BeExactly @('Desc')
    }

    It 'takes the next non-blank deeper line as the description of a row without one, and the name when that line is a row or not deeper' {
        $deeper = @(
            'Options:'
            '  --keyring-provider <keyring_provider>'
            '              Enable the credential lookup via the keyring'
            '              library if user input is allowed.'
            '  --proxy <proxy>  Specify a proxy'
        ) -join "`n"
        $none = @(
            'Options:'
            '  -h, --help'
            '      --list'
            '  -q'
            '  -z  '
        ) -join "`n"
        $afterBlank = @(
            'Options:'
            '  -a'
            ''
            '      Deeper description'
            '  -b  Beta'
        ) -join "`n"
        $sameIndent = @(
            'Options:'
            '  -q'
            '  Prose line same indent'
            '  -z  Zed'
        ) -join "`n"

        $deeperRows = ConvertFrom-TestHelpOption -Text $deeper
        $noneRows = ConvertFrom-TestHelpOption -Text $none
        $afterBlankRows = ConvertFrom-TestHelpOption -Text $afterBlank
        $sameIndentRows = ConvertFrom-TestHelpOption -Text $sameIndent

        $deeperRows.Name | Should -BeExactly @('--keyring-provider', '--proxy')
        $deeperRows.Description | Should -BeExactly @('Enable the credential lookup via the keyring', 'Specify a proxy')
        $noneRows.Name | Should -BeExactly @('-h', '--help', '--list', '-q', '-z')
        $noneRows.Description | Should -BeExactly @('-h', '--help', '--list', '-q', '-z')
        $afterBlankRows.Name | Should -BeExactly @('-a', '-b')
        $afterBlankRows.Description | Should -BeExactly @('Deeper description', 'Beta')
        $sameIndentRows.Name | Should -BeExactly @('-q', '-z')
        $sameIndentRows.Description | Should -BeExactly @('-q', 'Zed')
    }

    It 'reads the separator <Case> and cleans the description' -TestCases @(
        @{ Case = "' : '"; Row = '-a : Add files to archive'; Description = 'Add files to archive' }
        @{ Case = 'a tab'; Row = "-b`tRun the benchmark"; Description = 'Run the benchmark' }
        @{ Case = 'two spaces'; Row = "-c  Com`0pile$([char] 0x202E)the$([char] 0x2028)package  now  "; Description = 'Com pile the package now' }
    ) {
        param(
            [string] $Case,
            [string] $Row,
            [string] $Description
        )

        (ConvertFrom-TestHelpOption -Text "Options:`n  $Row").Description | Should -BeExactly $Description
    }

    It 'keeps -c and -C and keeps a repeated --help once, with its first description' {
        $text = @(
            'Options:'
            '  -c, --count    Count matches'
            '  -C, --context  Show context'
            '  --help         Print help'
            '  -h, --help     Print help again'
        ) -join "`n"

        $rows = ConvertFrom-TestHelpOption -Text $text

        $rows.Name | Should -BeExactly @('-c', '--count', '-C', '--context', '--help', '-h')
        ($rows | Where-Object -Property Name -CEQ -Value '--help').Description | Should -BeExactly 'Print help'
    }

    It 'reads options beside a commands section: <Case>' -TestCases @(
        @{ Case = 'option lines under a commands heading'; Text = (@('Commands:', '  build  Compile the package', '  --flag  Not an option row', '  /X  A subcommand row', '', '  --after  Alone after the section') -join "`n"); Options = @(); Subcommands = @('build', '/X') }
        @{ Case = 'slash lines after a commands section has ended'; Text = (@('Commands:', '  build  Compile the package', '', '  /copy  Copy entries', '  /move  Move entries') -join "`n"); Options = @('/copy', '/move'); Subcommands = @('build') }
        @{ Case = 'an option heading that follows a commands section without a blank line'; Text = (@('Commands:', '  build  Compile the package', 'Options:', '  -h, --help  Print help') -join "`n"); Options = @('-h', '--help'); Subcommands = @('build') }
        @{ Case = 'a shallower entry ends the commands section'; Text = (@('Commands:', '    build  Compile', '  /copy  Copy entries', '  /move  Move entries') -join "`n"); Options = @('/copy', '/move'); Subcommands = @('build') }
        @{ Case = 'a blank line before the first entry does not end it'; Text = (@('Commands:', '', '  build  Compile', '  -a  Alpha', '  -b  Beta') -join "`n"); Options = @(); Subcommands = @('build') }
    ) {
        param(
            [string] $Case,
            [string] $Text,
            [string[]] $Options,
            [string[]] $Subcommands
        )

        @(ConvertFrom-TestHelpOption -Text $Text | ForEach-Object -MemberName Name) -join ' ' | Should -BeExactly ($Options -join ' ')
        @(ConvertFrom-TestHelpText -Text $Text | ForEach-Object -MemberName Name) -join ' ' | Should -BeExactly ($Subcommands -join ' ')
    }

    It 'classifies <Line> as the subcommand parser does' -TestCases @(
        @{ Line = 'Commands:'; Kind = 'Commands' }
        @{ Line = 'Common Commands:'; Kind = 'Commands' }
        @{ Line = 'CORE COMMANDS'; Kind = 'Commands' }
        @{ Line = '<Commands>'; Kind = 'Commands' }
        @{ Line = 'Basic Commands (Beginner):'; Kind = 'Commands' }
        @{ Line = 'Subcommands provided by plugins:'; Kind = 'Commands' }
        @{ Line = 'The following commands are available:'; Kind = 'Commands' }
        @{ Line = 'Command that control debugging'; Kind = 'Commands' }
        @{ Line = 'Options:'; Kind = 'Options' }
        @{ Line = 'Global Options:'; Kind = 'Options' }
        @{ Line = 'FLAGS'; Kind = 'Options' }
        @{ Line = 'General Options:'; Kind = 'Options' }
        @{ Line = 'OUTPUT MODES:'; Kind = 'Options' }
        @{ Line = '<Switches>'; Kind = 'Options' }
        @{ Line = 'Parameter List:'; Kind = 'Options' }
        @{ Line = 'The following options are available:'; Kind = 'Options' }
        @{ Line = 'One two three four five six:'; Kind = 'Options' }
        @{ Line = 'One two three four five six seven:'; Kind = 'Neither' }
        @{ Line = 'These are common Git commands used in various situations:'; Kind = 'Neither' }
        @{ Line = 'Commands that operate on entries in a store'; Kind = 'Neither' }
        @{ Line = 'Mandatory arguments to long options are mandatory.'; Kind = 'Neither' }
    ) {
        param(
            [string] $Line,
            [string] $Kind
        )

        $subcommands = @(ConvertFrom-TestHelpText -Text "$Line`n  build  Compile the package")
        $options = @(ConvertFrom-TestHelpOption -Text "$Line`n  -x  Exclude")

        ($subcommands.Count -gt 0) | Should -Be ($Kind -eq 'Commands')
        ($options.Count -gt 0) | Should -Be ($Kind -eq 'Options')
    }

    It 'returns no rows for empty text or help without an option line' {
        ConvertFrom-TestHelpOption -Text '' | Should -BeNullOrEmpty
        ConvertFrom-TestHelpOption -Text "Commands:`n  build  Compile`n  test  Run the tests" | Should -BeNullOrEmpty
    }
}
