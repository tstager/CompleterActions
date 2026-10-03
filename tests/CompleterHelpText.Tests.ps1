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
