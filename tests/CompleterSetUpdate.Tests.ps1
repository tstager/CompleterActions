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

    # The set file Hash rule, computed here rather than by the module: SHA-256 of
    # the text with CR LF and lone CR made LF, as UTF-8 without a byte-order mark.
    function Get-TestScriptHash
    {
        param(
            [Parameter(Mandatory)]
            [string] $LiteralPath
        )

        $text = [System.IO.File]::ReadAllText($LiteralPath).Replace("`r`n", "`n").Replace("`r", "`n")
        'SHA256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.UTF8Encoding]::new($false).GetBytes($text)))
    }

    function Write-TestCompleterScript
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $CommandName,

            [Parameter()]
            [string] $ParameterName
        )

        $null = New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force
        $lines = if ($ParameterName)
        {
            "Register-ArgumentCompleter -CommandName '$CommandName' -ParameterName '$ParameterName' -ScriptBlock {"
            '    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)'
            ''
            '    $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters'
        }
        else
        {
            "Register-ArgumentCompleter -Native -CommandName '$CommandName' -ScriptBlock {"
            '    param($wordToComplete, $commandAst, $cursorPosition)'
            ''
            '    $null = $commandAst, $cursorPosition'
        }

        Set-Content -LiteralPath $Path -Encoding utf8 -Value @(
            $lines
            ''
            "    foreach (`$value in '$CommandName-one', '$CommandName-two')"
            '    {'
            '        if ($value -like "$wordToComplete*")'
            '        {'
            "            [System.Management.Automation.CompletionResult]::new(`$value, `$value, 'ParameterValue', `$value)"
            '        }'
            '    }'
            '}'
        )
    }

    function Add-TestRegistration
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $CommandName
        )

        Add-Content -LiteralPath $Path -Value "Register-ArgumentCompleter -Native -CommandName '$CommandName' -ScriptBlock { param(`$w, `$c, `$p) }" -Encoding utf8
    }

    # Replaces the value of the Entry-th line that sets Key, in the layout Export-CompleterSet writes.
    function Edit-TestEntryValue
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [int] $Entry,

            [Parameter(Mandatory)]
            [string] $Key,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Value
        )

        $lines = @(Get-Content -LiteralPath $Path)
        $seen = 0

        for ($index = 0; $index -lt $lines.Count; $index++)
        {
            if ($lines[$index] -match "^\s*$Key\s*=")
            {
                $seen++

                if ($seen -eq $Entry)
                {
                    $lines[$index] = $lines[$index].Substring(0, $lines[$index].IndexOf('=') + 1) + " $Value"
                    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
                    return
                }
            }
        }

        throw "The set has no line $Entry that sets $Key."
    }

    function Clear-TestEntryLine
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [int] $Entry,

            [Parameter(Mandatory)]
            [string] $Key
        )

        $lines = @(Get-Content -LiteralPath $Path)
        $seen = 0
        $removeIndex = -1

        for ($index = 0; $index -lt $lines.Count; $index++)
        {
            if ($lines[$index] -match "^\s*$Key\s*=")
            {
                $seen++

                if ($seen -eq $Entry)
                {
                    $removeIndex = $index
                }
            }
        }

        Set-Content -LiteralPath $Path -Encoding utf8 -Value @(for ($index = 0; $index -lt $lines.Count; $index++) { if ($index -ne $removeIndex) { $lines[$index] } })
    }

    # Dates the file in the past, so a write, even of the same bytes, shows in its timestamp.
    function Get-TestFileState
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path
        )

        [System.IO.File]::SetLastWriteTimeUtc($Path, [datetime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        Get-TestCurrentFileState -Path $Path
    }

    function Get-TestCurrentFileState
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path
        )

        '{0}|{1}' -f [System.IO.File]::GetLastWriteTimeUtc($Path).Ticks, [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }

    function Get-TestSkippedWarning
    {
        param(
            [Parameter(Mandatory)]
            [CompleterActions.CompleterScriptFinding] $Finding,

            [Parameter(Mandatory)]
            [string] $Label,

            [Parameter(Mandatory)]
            [string] $SetPath
        )

        $Finding.Message.StartsWith("${Label}: ", [System.StringComparison]::Ordinal) | Should -BeTrue -Because 'the warning repeats the finding without its label'
        "$Label of '$SetPath' was not updated: $($Finding.Message.Substring($Label.Length + 2)) Regenerate the set with Export-CompleterSet."
    }

    function Get-TestTemporaryFile
    {
        @(Get-ChildItem -LiteralPath $script:Folder -Filter '*.tmp' -File -Recurse -Force)
    }

    function Enable-TestUpdateCounter
    {
        & (Get-Module -Name 'CompleterActions') {
            $script:TestSourceReads = [System.Collections.Generic.List[string]]::new()
            $script:TestSaves = [System.Collections.Generic.List[string]]::new()
            $script:TestReadFunction = ${function:Import-CompleterSetDefinition}
            $script:TestSaveFunction = ${function:Save-CompleterSetFile}

            function script:Import-CompleterSetDefinition
            {
                param($LiteralPath, [switch] $IncludeSource)

                if ($IncludeSource)
                {
                    $script:TestSourceReads.Add($LiteralPath)
                }

                & $script:TestReadFunction @PSBoundParameters
            }

            function script:Save-CompleterSetFile
            {
                param($Bytes, $LiteralPath)

                $script:TestSaves.Add($LiteralPath)
                & $script:TestSaveFunction @PSBoundParameters
            }
        }
    }

    function Get-TestUpdateCounter
    {
        & (Get-Module -Name 'CompleterActions') {
            [pscustomobject] @{
                Reads = @($script:TestSourceReads)
                Saves = @($script:TestSaves)
            }
        }
    }

    # The lines of a hand-written set of the three scripts, with <ALPHAHASH> where the first entry's Hash value goes.
    function Get-TestShapeLine
    {
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Export', 'OneLine', 'Commented')]
            [string] $Layout,

            [Parameter(Mandatory)]
            [string] $BetaHash,

            [Parameter(Mandatory)]
            [string] $GammaHash
        )

        $entries = @(
            @{ Path = 'alpha_completer/alpha_completer.ps1'; Hash = '<ALPHAHASH>'; Target = "@{ CommandName = 'caupdatealpha'; Native = `$true }" }
            @{ Path = 'beta_completer/beta_completer.ps1'; Hash = "'$BetaHash'"; Target = "@{ CommandName = 'caupdatebeta'; Native = `$true }" }
            @{ Path = 'gamma_completer/gamma_completer.ps1'; Hash = "'$GammaHash'"; Target = "@{ CommandName = 'Test-CaUpdateGamma'; ParameterName = 'Name' }" }
        )

        if ($Layout -eq 'Commented')
        {
            '# A set kept by hand: r' + [char] 0x00E9 + 'sum' + [char] 0x00E9 + ' ' + [char] 0x2014 + ' three scripts.'
        }

        '@{'
        '    Version = 1'
        '    Entries = @('

        foreach ($entry in $entries)
        {
            if ($Layout -eq 'OneLine')
            {
                "        @{ Path = '$($entry.Path)'; Hash = $($entry.Hash); Targets = @( $($entry.Target) ) }"
                continue
            }

            if ($Layout -eq 'Commented')
            {
                '        <# ' + [char] 0x00FC + 'n' + [char] 0x00EF + 'code before the entry #>'
            }

            '        @{'
            "            Path    = '$($entry.Path)'"
            '            Trusted = $false'
            $hashLine = "            Hash    = $($entry.Hash)"
            if ($Layout -eq 'Commented') { "$hashLine   # written by hand" } else { $hashLine }
            '            Targets = @('
            "                $($entry.Target)"
            '            )'
            '        }'
        }

        '    )'
        '}'
    }

    $script:ManifestPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'))
    $script:PwshPath = Join-Path -Path $PSHOME -ChildPath ($IsWindows ? 'pwsh.exe' : 'pwsh')
    $script:UpdateCleanupTargets = @(
        @{ CommandName = 'caupdatealpha'; CompleterType = 'Native' },
        @{ CommandName = 'caupdatebeta'; CompleterType = 'Native' },
        @{ CommandName = 'caupdatedelta'; CompleterType = 'Native' },
        @{ CommandName = 'Test-CaUpdateGamma'; ParameterName = 'Name'; CompleterType = 'Parameter' }
    )
}

Describe 'Update-CompleterSet' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:UpdateCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name $script:ManifestPath -Force | Out-Null

        $caseRoot = Join-Path -Path $TestDrive -ChildPath ('update-{0}' -f ([guid]::NewGuid().ToString('N')))
        $script:Folder = Join-Path -Path $caseRoot -ChildPath 'set'
        $script:AlphaPath = Join-Path -Path $script:Folder -ChildPath 'alpha_completer' -AdditionalChildPath 'alpha_completer.ps1'
        $script:BetaPath = Join-Path -Path $script:Folder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1'
        $script:GammaPath = Join-Path -Path $script:Folder -ChildPath 'gamma_completer' -AdditionalChildPath 'gamma_completer.ps1'
        $script:SetPath = Join-Path -Path $script:Folder -ChildPath 'completers.psd1'

        Write-TestCompleterScript -Path $script:AlphaPath -CommandName 'caupdatealpha'
        Write-TestCompleterScript -Path $script:BetaPath -CommandName 'caupdatebeta'
        Write-TestCompleterScript -Path $script:GammaPath -CommandName 'Test-CaUpdateGamma' -ParameterName 'Name'

        $script:Records = @(
            [pscustomobject] @{ CommandName = 'caupdatealpha'; IsNative = $true; ScriptPath = $script:AlphaPath; Trusted = $false }
            [pscustomobject] @{ CommandName = 'caupdatebeta'; IsNative = $true; ScriptPath = $script:BetaPath; Trusted = $false }
            [pscustomobject] @{ CommandName = 'Test-CaUpdateGamma'; ParameterName = 'Name'; ScriptPath = $script:GammaPath; Trusted = $false }
        )
        $script:Records | Export-CompleterSet -Path $script:SetPath
    }

    AfterEach {
        foreach ($cleanupTarget in $script:UpdateCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    Context 'Drift is repaired in place' {
        It 'repairs a comment added to one script through the pipeline from Test-CompleterSet, inside that Hash value only' {
            $beforeBytes = [System.IO.File]::ReadAllBytes($script:SetPath)
            $beforeText = [System.IO.File]::ReadAllText($script:SetPath)
            $oldHash = Get-TestScriptHash -LiteralPath $script:BetaPath
            Add-Content -LiteralPath $script:BetaPath -Value '# a comment line' -Encoding utf8
            $newHash = Get-TestScriptHash -LiteralPath $script:BetaPath

            Test-CompleterSet -LiteralPath $script:SetPath | Update-CompleterSet -WarningVariable updateWarnings

            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            $updateWarnings | Should -BeNullOrEmpty
            $afterBytes = [System.IO.File]::ReadAllBytes($script:SetPath)
            $afterBytes.Length | Should -Be $beforeBytes.Length
            [System.Convert]::ToHexString($afterBytes) | Should -BeExactly ([System.Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes($beforeText.Replace($oldHash, $newHash))))
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }
    }

    Context 'What is updated' {
        It 'rewrites the Hash of an entry whose script text changed, with no warning' {
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            $oldHash = Get-TestScriptHash -LiteralPath $script:AlphaPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings

            $updateWarnings | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly $before.Replace($oldHash, (Get-TestScriptHash -LiteralPath $script:AlphaPath))
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'rewrites a malformed Hash' {
            Edit-TestEntryValue -Path $script:SetPath -Entry 2 -Key 'Hash' -Value "'SHA512:abc'"
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            @((Test-CompleterSet -LiteralPath $script:SetPath).Construct) | Should -Be @('InvalidHash')

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings

            $updateWarnings | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly $before.Replace("'SHA512:abc'", "'$(Get-TestScriptHash -LiteralPath $script:BetaPath)'")
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'rewrites several Hash values that change the length of the text in one set' {
            Edit-TestEntryValue -Path $script:SetPath -Entry 1 -Key 'Hash' -Value "'x'"
            Edit-TestEntryValue -Path $script:SetPath -Entry 2 -Key 'Hash' -Value "'SHA512:abc'"
            Add-Content -LiteralPath $script:GammaPath -Value '# drift' -Encoding utf8
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            $gammaOldHash = ([regex]::Matches($before, "'(SHA256:[0-9A-F]{64})'") | Select-Object -Last 1).Groups[1].Value

            Update-CompleterSet -LiteralPath $script:SetPath

            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly $before.Replace("'x'", "'$(Get-TestScriptHash -LiteralPath $script:AlphaPath)'").Replace("'SHA512:abc'", "'$(Get-TestScriptHash -LiteralPath $script:BetaPath)'").Replace($gammaOldHash, (Get-TestScriptHash -LiteralPath $script:GammaPath))
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'does not update an entry whose script gained a registration, warns with the TargetMismatch text, and does not write the file' {
            Add-TestRegistration -Path $script:AlphaPath -CommandName 'caupdatedelta'
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath | Where-Object Construct -EQ 'TargetMismatch')
            $finding.Count | Should -Be 1
            $expected = Get-TestSkippedWarning -Finding $finding[0] -Label "Entry 1 ('alpha_completer/alpha_completer.ps1')" -SetPath $script:SetPath
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings -WarningAction SilentlyContinue

            @($updateWarnings.Message) | Should -Be @($expected)
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'does not update an entry whose script was deleted and warns with the MissingScript text' {
            Remove-Item -LiteralPath $script:BetaPath
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath | Where-Object Construct -EQ 'MissingScript')
            $finding.Count | Should -Be 1
            $expected = Get-TestSkippedWarning -Finding $finding[0] -Label "Entry 2 ('beta_completer/beta_completer.ps1')" -SetPath $script:SetPath
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings -WarningAction SilentlyContinue

            @($updateWarnings.Message) | Should -Be @($expected)
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'does not update an entry that lists a target an earlier entry lists, whether or not its script changed, and warns with the DuplicateTarget text' {
            $deltaPath = Join-Path -Path $script:Folder -ChildPath 'delta_completer' -AdditionalChildPath 'delta_completer.ps1'
            Write-TestCompleterScript -Path $deltaPath -CommandName 'caupdatealpha'
            @($script:Records) + [pscustomobject] @{ CommandName = 'caupdatealpha'; IsNative = $true; ScriptPath = $deltaPath; Trusted = $false } |
                Export-CompleterSet -Path $script:SetPath
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath | Where-Object Construct -EQ 'DuplicateTarget')
            $finding.Count | Should -Be 1
            $expected = Get-TestSkippedWarning -Finding $finding[0] -Label "Entry 4 ('delta_completer/delta_completer.ps1')" -SetPath $script:SetPath
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable unchangedWarnings -WarningAction SilentlyContinue
            Add-Content -LiteralPath $deltaPath -Value '# drift' -Encoding utf8
            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable changedWarnings -WarningAction SilentlyContinue

            @($unchangedWarnings.Message) | Should -Be @($expected)
            @($changedWarnings.Message) | Should -Be @($expected)
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'does not add a Hash to an entry without one and counts it in one warning' {
            Clear-TestEntryLine -Path $script:SetPath -Entry 2 -Key 'Hash'
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings -WarningAction SilentlyContinue

            @($updateWarnings.Message) | Should -Be @("Entries of '$script:SetPath' without a Hash were not updated: 1. Regenerate the set with Export-CompleterSet to add them.")
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'rewrites the Hash of a trusted entry whose script changed, with one trusted-entry warning' {
            Edit-TestEntryValue -Path $script:SetPath -Entry 1 -Key 'Trusted' -Value '$true'
            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable unchangedWarnings
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            $oldHash = Get-TestScriptHash -LiteralPath $script:AlphaPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings -WarningAction SilentlyContinue

            $unchangedWarnings | Should -BeNullOrEmpty -Because 'only a trusted entry that is updated is warned about'
            @($updateWarnings.Message) | Should -Be @("Entry 1 ('alpha_completer/alpha_completer.ps1') of '$script:SetPath' is trusted, so its Targets were not checked against the script.")
            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly $before.Replace($oldHash, (Get-TestScriptHash -LiteralPath $script:AlphaPath))
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'leaves a matching Hash written in lower case untouched and does not write the file' {
            Edit-TestEntryValue -Path $script:SetPath -Entry 1 -Key 'Hash' -Value "'$((Get-TestScriptHash -LiteralPath $script:AlphaPath).ToLowerInvariant())'"
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings

            $updateWarnings | Should -BeNullOrEmpty
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'warns about a new script under the folder with the UnlistedScript text and leaves the set unchanged' {
            $newPath = Join-Path -Path $script:Folder -ChildPath 'new_completer' -AdditionalChildPath 'new_completer.ps1'
            Write-TestCompleterScript -Path $newPath -CommandName 'caupdatenew'
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath)
            @($finding.Construct) | Should -Be @('UnlistedScript')
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable updateWarnings -WarningAction SilentlyContinue

            @($updateWarnings.Message) | Should -Be @("$($finding[0].Message) Add it with Export-CompleterSet.")
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'scans for unlisted scripts with -Filter, so only a script that matches it is warned about' {
            $otherPath = Join-Path -Path $script:Folder -ChildPath 'c' -AdditionalChildPath 'gamma_other.ps1'
            Write-TestCompleterScript -Path $otherPath -CommandName 'caupdateother'
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath -Filter '*_other.ps1')
            @($finding.Construct) | Should -Be @('UnlistedScript')
            $state = Get-TestFileState -Path $script:SetPath

            Update-CompleterSet -LiteralPath $script:SetPath -WarningVariable defaultWarnings -WarningAction SilentlyContinue
            Update-CompleterSet -LiteralPath $script:SetPath -Filter '*_other.ps1' -WarningVariable otherWarnings -WarningAction SilentlyContinue
            Update-CompleterSet -LiteralPath $script:SetPath -Filter 'alpha*' -WarningVariable alphaWarnings -WarningAction SilentlyContinue

            $defaultWarnings | Should -BeNullOrEmpty
            @($otherWarnings.Message) | Should -Be @("$($finding[0].Message) Add it with Export-CompleterSet.")
            $alphaWarnings | Should -BeNullOrEmpty -Because 'the only script that matches alpha* is listed'
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'rewrites one of two changed entries, warns for the one whose targets changed, and returns the file with -PassThru' {
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            $oldHash = Get-TestScriptHash -LiteralPath $script:AlphaPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            Add-TestRegistration -Path $script:BetaPath -CommandName 'caupdatedelta'
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath | Where-Object Construct -EQ 'TargetMismatch')
            $expected = Get-TestSkippedWarning -Finding $finding[0] -Label "Entry 2 ('beta_completer/beta_completer.ps1')" -SetPath $script:SetPath

            $output = @(Update-CompleterSet -LiteralPath $script:SetPath -PassThru -WarningVariable updateWarnings -WarningAction SilentlyContinue)

            @($updateWarnings.Message) | Should -Be @($expected)
            $output.Count | Should -Be 1
            $output[0] | Should -BeOfType ([System.IO.FileInfo])
            $output[0].FullName | Should -Be $script:SetPath
            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly $before.Replace($oldHash, (Get-TestScriptHash -LiteralPath $script:AlphaPath))
            @((Test-CompleterSet -LiteralPath $script:SetPath).Construct) | Should -Be @('TargetMismatch', 'HashMismatch')
        }

        It 'returns nothing without -PassThru' {
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8

            Update-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'writes one verbose line per updated entry and one per set' {
            $cleanPath = Join-Path -Path $script:Folder -ChildPath 'clean.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $cleanPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            Add-Content -LiteralPath $script:GammaPath -Value '# drift' -Encoding utf8
            Update-CompleterSet -LiteralPath $cleanPath

            $verbose = @(Update-CompleterSet -LiteralPath $script:SetPath, $cleanPath -Verbose 4>&1 | ForEach-Object Message | Where-Object { $_ -like 'Updated *' })

            $verbose | Should -Be @(
                "Updated the Hash of entry 1 ('alpha_completer/alpha_completer.ps1') in '$script:SetPath'."
                "Updated the Hash of entry 3 ('gamma_completer/gamma_completer.ps1') in '$script:SetPath'."
                "Updated 2 of 3 entries in '$script:SetPath'."
                "Updated 0 of 3 entries in '$cleanPath'."
            )
        }

        It 'trusts no position a finding carries and reads the set again' {
            $oldHash = Get-TestScriptHash -LiteralPath $script:AlphaPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)
            $findings.Count | Should -Be 1
            $before = [System.IO.File]::ReadAllText($script:SetPath)
            $prefix = "# moved down$([Environment]::NewLine)# by two lines$([Environment]::NewLine)"
            [System.IO.File]::WriteAllText($script:SetPath, $prefix + $before)

            Update-CompleterSet -InputObject $findings

            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($script:SetPath) | Should -BeExactly ($prefix + $before.Replace($oldHash, (Get-TestScriptHash -LiteralPath $script:AlphaPath)))
        }
    }

    Context 'Bytes' {
        It 'keeps every byte outside the replaced Hash value for a set <Shape>' -TestCases @(
            @{ Shape = 'with CR LF line endings'; NewLine = "`r`n"; Preamble = $false; Layout = 'Export'; Quote = 'Single' }
            @{ Shape = 'with LF line endings'; NewLine = "`n"; Preamble = $false; Layout = 'Export'; Quote = 'Single' }
            @{ Shape = 'with a UTF-8 byte-order mark'; NewLine = "`r`n"; Preamble = $true; Layout = 'Commented'; Quote = 'Single' }
            @{ Shape = 'whose Hash shares a line with Path'; NewLine = "`n"; Preamble = $false; Layout = 'OneLine'; Quote = 'Single' }
            @{ Shape = 'with comments and a double-quoted Hash'; NewLine = "`r`n"; Preamble = $false; Layout = 'Commented'; Quote = 'Double' }
            @{ Shape = 'whose Hash is a here-string'; NewLine = "`n"; Preamble = $false; Layout = 'Export'; Quote = 'HereString' }
        ) {
            $shapePath = Join-Path -Path $script:Folder -ChildPath 'shape.psd1'
            $oldHash = Get-TestScriptHash -LiteralPath $script:AlphaPath
            $lines = @(Get-TestShapeLine -Layout $Layout -BetaHash (Get-TestScriptHash -LiteralPath $script:BetaPath) -GammaHash (Get-TestScriptHash -LiteralPath $script:GammaPath))
            $template = ($lines -join $NewLine) + $NewLine
            $oldValue = switch ($Quote)
            {
                'Single' { "'$oldHash'" }
                'Double' { """$oldHash""" }
                'HereString' { "@'$NewLine$oldHash$NewLine'@" }
            }
            $encoding = [System.Text.UTF8Encoding]::new($Preamble)
            [System.IO.File]::WriteAllBytes($shapePath, [byte[]] ($encoding.GetPreamble() + $encoding.GetBytes($template.Replace('<ALPHAHASH>', $oldValue))))
            Test-CompleterSet -LiteralPath $shapePath | Should -BeNullOrEmpty -Because 'the hand-written set must match its scripts before the change'
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $newHash = Get-TestScriptHash -LiteralPath $script:AlphaPath

            Update-CompleterSet -LiteralPath $shapePath -WarningVariable updateWarnings

            $updateWarnings | Should -BeNullOrEmpty
            [System.Convert]::ToHexString([System.IO.File]::ReadAllBytes($shapePath)) | Should -BeExactly ([System.Convert]::ToHexString([byte[]] ($encoding.GetPreamble() + $encoding.GetBytes($template.Replace('<ALPHAHASH>', "'$newHash'")))))
            Test-CompleterSet -LiteralPath $shapePath | Should -BeNullOrEmpty
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'refuses a set with an invalid UTF-8 byte with the round-trip text and leaves it unchanged' {
            $badPath = Join-Path -Path $script:Folder -ChildPath 'bad.psd1'
            $lines = @(Get-TestShapeLine -Layout 'Export' -BetaHash (Get-TestScriptHash -LiteralPath $script:BetaPath) -GammaHash (Get-TestScriptHash -LiteralPath $script:GammaPath))
            $text = (@($lines) -join "`n").Replace('<ALPHAHASH>', "'$(Get-TestScriptHash -LiteralPath $script:AlphaPath)'") + "`n"
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllBytes($badPath, [byte[]] ($utf8.GetBytes("# a byte that is not UTF-8: ") + [byte] 0xFF + $utf8.GetBytes("`n$text")))
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $state = Get-TestFileState -Path $badPath
            $caught = $null

            try
            {
                Update-CompleterSet -LiteralPath $badPath
            }
            catch
            {
                $caught = $_
            }

            $caught.Exception.Message | Should -BeExactly "Failed to update completer set. '$badPath' cannot be rewritten without changing bytes outside its Hash values, because its text does not round-trip in its encoding. Regenerate the set with Export-CompleterSet."
            Get-TestCurrentFileState -Path $badPath | Should -BeExactly $state
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'fails with the not-equivalent text and leaves the set unchanged when the splice <Case>' -TestCases @(
            @{ Case = 'drops an entry'; Splice = { param($Text, $Replacement) $null = $Replacement; (@($Text -split "`n") | Where-Object { $_ -notmatch 'gamma_completer' }) -join "`n" } }
            @{ Case = 'leaves the Hash as it was'; Splice = { param($Text, $Replacement) $null = $Replacement; $Text } }
        ) {
            $onePath = Join-Path -Path $script:Folder -ChildPath 'one.psd1'
            $lines = @(Get-TestShapeLine -Layout 'OneLine' -BetaHash (Get-TestScriptHash -LiteralPath $script:BetaPath) -GammaHash (Get-TestScriptHash -LiteralPath $script:GammaPath))
            [System.IO.File]::WriteAllText($onePath, ((@($lines) -join "`n").Replace('<ALPHAHASH>', "'$(Get-TestScriptHash -LiteralPath $script:AlphaPath)'") + "`n"))
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $state = Get-TestFileState -Path $onePath

            & (Get-Module -Name 'CompleterActions') {
                param($Splice)

                Set-Item -Path 'function:script:Set-CompleterSetHashText' -Value $Splice
            } $Splice

            $caught = $null

            try
            {
                Update-CompleterSet -LiteralPath $onePath
            }
            catch
            {
                $caught = $_
            }

            $caught.Exception.Message | Should -BeExactly 'Failed to update completer set. Update-CompleterSet did not produce an equivalent set, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues.'
            Get-TestCurrentFileState -Path $onePath | Should -BeExactly $state
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'refuses a result over the set file limit with the text Export-CompleterSet uses and writes nothing' {
            Edit-TestEntryValue -Path $script:SetPath -Entry 1 -Key 'Hash' -Value "'x'"
            $length = (Get-Item -LiteralPath $script:SetPath).Length
            & (Get-Module -Name 'CompleterActions') { param($Bytes) $script:CompleterSetMaxFileBytes = $Bytes } ($length + 10)
            $state = Get-TestFileState -Path $script:SetPath
            $caught = $null

            try
            {
                Update-CompleterSet -LiteralPath $script:SetPath
            }
            catch
            {
                $caught = $_
            }

            $caught.Exception.Message | Should -BeExactly "Failed to update completer set. The set would be $($length + 70) bytes, larger than the $($length + 10)-byte limit for completer set files, so Import-CompleterSet could not read it. Export the registrations as several sets. Nothing was written."
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'replaces the set by a move, so a hard link to the old file still holds the old bytes' {
            $oldBytes = [System.IO.File]::ReadAllBytes($script:SetPath)
            $newBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("@{ Version = 1 }`n")
            $oldLinkPath = Join-Path -Path $script:Folder -ChildPath 'old.psd1'
            $null = New-Item -ItemType HardLink -Path $oldLinkPath -Target $script:SetPath

            $written = & (Get-Module -Name 'CompleterActions') { param($Bytes, $Path) Save-CompleterSetFile -Bytes $Bytes -LiteralPath $Path } $newBytes $script:SetPath

            $written.FullName | Should -Be $script:SetPath
            [System.Convert]::ToHexString([System.IO.File]::ReadAllBytes($oldLinkPath)) | Should -BeExactly ([System.Convert]::ToHexString($oldBytes)) -Because 'an in-place write would change the file the hard link shares'
            [System.Convert]::ToHexString([System.IO.File]::ReadAllBytes($script:SetPath)) | Should -BeExactly ([System.Convert]::ToHexString($newBytes))
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'leaves no temporary file and the destination as it was when the replacing move fails' {
            $directoryPath = Join-Path -Path $script:Folder -ChildPath 'occupied.psd1'
            $null = New-Item -ItemType Directory -Path $directoryPath
            $caught = $null

            try
            {
                & (Get-Module -Name 'CompleterActions') { param($Path) Save-CompleterSetFile -Bytes ([byte[]] (0x40, 0x7B, 0x7D)) -LiteralPath $Path } $directoryPath
            }
            catch
            {
                $caught = $_
            }

            $caught | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $directoryPath -PathType Container | Should -BeTrue
            Get-ChildItem -LiteralPath $directoryPath -Force | Should -BeNullOrEmpty
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'writes a set reached through a symbolic link at the link''s target and keeps the link' {
            $linkPath = Join-Path -Path $script:Folder -ChildPath 'link.psd1'
            $null = New-Item -ItemType SymbolicLink -Path $linkPath -Target $script:SetPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            @((Test-CompleterSet -LiteralPath $linkPath).Construct) | Should -Be @('HashMismatch')

            $output = @(Update-CompleterSet -LiteralPath $linkPath -PassThru)

            $output.Count | Should -Be 1
            $output[0].FullName | Should -Be $linkPath
            (Get-Item -LiteralPath $linkPath -Force).LinkType | Should -Be 'SymbolicLink'
            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            Test-CompleterSet -LiteralPath $linkPath | Should -BeNullOrEmpty
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }
    }

    Context 'Binding and surface' {
        It 'updates each of two piped sets once, however many findings each has' {
            $secondPath = Join-Path -Path $script:Folder -ChildPath 'second.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $secondPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            Add-Content -LiteralPath $script:BetaPath -Value '# drift' -Encoding utf8
            Add-Content -LiteralPath $script:GammaPath -Value '# drift' -Encoding utf8
            @(Test-CompleterSet -LiteralPath $script:SetPath, $secondPath).Count | Should -Be 6
            Enable-TestUpdateCounter

            Test-CompleterSet -LiteralPath $script:SetPath, $secondPath | Update-CompleterSet

            $counter = Get-TestUpdateCounter
            $counter.Reads | Should -Be @($script:SetPath, $secondPath)
            $counter.Saves | Should -Be @($script:SetPath, $secondPath)
            Test-CompleterSet -LiteralPath $script:SetPath, $secondPath | Should -BeNullOrEmpty
        }

        It 'neither reads nor writes a clean set piped from Test-CompleterSet, and reads a clean set given by -Path without writing it' {
            $state = Get-TestFileState -Path $script:SetPath
            Enable-TestUpdateCounter

            Test-CompleterSet -LiteralPath $script:SetPath | Update-CompleterSet
            $piped = Get-TestUpdateCounter
            Update-CompleterSet -Path $script:SetPath
            $byPath = Get-TestUpdateCounter

            $piped.Reads | Should -BeNullOrEmpty
            $piped.Saves | Should -BeNullOrEmpty
            $byPath.Reads | Should -Be @($script:SetPath)
            $byPath.Saves | Should -BeNullOrEmpty
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'updates a set whose name holds brackets through <Route>' -TestCases @(
            @{ Route = 'the pipeline from Test-CompleterSet -LiteralPath' }
            @{ Route = '-LiteralPath' }
        ) {
            $bracketPath = Join-Path -Path $script:Folder -ChildPath 'set[1].psd1'
            $plainPath = Join-Path -Path $script:Folder -ChildPath 'set1.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $bracketPath
            Copy-Item -LiteralPath $script:SetPath -Destination $plainPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $plainState = Get-TestFileState -Path $plainPath

            if ($Route -eq '-LiteralPath')
            {
                Update-CompleterSet -LiteralPath $bracketPath
            }
            else
            {
                Test-CompleterSet -LiteralPath $bracketPath | Update-CompleterSet
            }

            Test-CompleterSet -LiteralPath $bracketPath | Should -BeNullOrEmpty
            Get-TestCurrentFileState -Path $plainPath | Should -BeExactly $plainState -Because 'the brackets are not a wildcard that matches set1.psd1'
        }

        It 'expands a wildcard in -Path to every set it matches' {
            $secondPath = Join-Path -Path $script:Folder -ChildPath 'second.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $secondPath
            Add-Content -LiteralPath $script:BetaPath -Value '# drift' -Encoding utf8
            @(Test-CompleterSet -LiteralPath $script:SetPath, $secondPath).Count | Should -Be 2

            $output = @(Update-CompleterSet -Path (Join-Path -Path $script:Folder -ChildPath '*.psd1') -PassThru)

            @($output.FullName | Sort-Object) | Should -Be @(@($script:SetPath, $secondPath) | Sort-Object)
            Test-CompleterSet -LiteralPath $script:SetPath, $secondPath | Should -BeNullOrEmpty
        }

        It 'binds a <Kind> from the pipeline to -Path' -TestCases @(
            @{ Kind = 'string' }
            @{ Kind = 'FileInfo' }
        ) {
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8

            if ($Kind -eq 'string')
            {
                $script:SetPath | Update-CompleterSet
            }
            else
            {
                Get-Item -LiteralPath $script:SetPath | Update-CompleterSet
            }

            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
        }

        It 'binds a finding given positionally to -Path as text' {
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            $finding = @(Test-CompleterSet -LiteralPath $script:SetPath)[0]
            $state = Get-TestFileState -Path $script:SetPath
            $caught = $null

            try
            {
                Update-CompleterSet $finding
            }
            catch
            {
                $caught = $_
            }

            $caught.Exception.Message | Should -BeLike "Failed to update completer set. *$([System.Management.Automation.WildcardPattern]::Escape([string] $finding))*"
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'writes nothing under -WhatIf and still warns' {
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            Add-TestRegistration -Path $script:BetaPath -CommandName 'caupdatedelta'
            $state = Get-TestFileState -Path $script:SetPath

            $output = @(Update-CompleterSet -LiteralPath $script:SetPath -PassThru -WhatIf -WarningVariable updateWarnings -WarningAction SilentlyContinue)

            $output | Should -BeNullOrEmpty
            @($updateWarnings.Message) | Should -HaveCount 1
            $updateWarnings[0].Message | Should -BeLike "Entry 2 ('beta_completer/beta_completer.ps1') of '*' was not updated: The declared Targets do not match the script.*"
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
            Get-TestTemporaryFile | Should -BeNullOrEmpty
        }

        It 'asks ShouldProcess once per set that has something to update, on the set path, with the count' {
            $cleanPath = Join-Path -Path $script:Folder -ChildPath 'clean.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $cleanPath
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            Add-Content -LiteralPath $script:BetaPath -Value '# drift' -Encoding utf8
            Update-CompleterSet -LiteralPath $cleanPath
            $childPath = Join-Path -Path $TestDrive -ChildPath 'update-completerset-whatif.ps1'
            Set-Content -LiteralPath $childPath -Encoding utf8 -Value @(
                'param([string] $ManifestPath, [string] $SetPath, [string] $CleanPath)'
                '$ErrorActionPreference = ''Stop'''
                'Import-Module -Name $ManifestPath -Force'
                'Update-CompleterSet -LiteralPath $SetPath, $CleanPath -WhatIf'
            )
            $state = Get-TestFileState -Path $script:SetPath

            $output = @(& $script:PwshPath -NoProfile -NoLogo -NonInteractive -File $childPath -ManifestPath $script:ManifestPath -SetPath $script:SetPath -CleanPath $cleanPath 2>&1)

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            @($output | ForEach-Object { [string] $_ } | Where-Object { $_ -like 'What if:*' }) | Should -Be @("What if: Performing the operation `"Update 2 Hash values`" on target `"$script:SetPath`".")
            Get-TestCurrentFileState -Path $script:SetPath | Should -BeExactly $state
        }

        It 'shows the three parameter sets in Get-Command -Syntax' {
            $syntax = @((Get-Command -Name 'Update-CompleterSet' -Syntax) -split '\r?\n' | Where-Object { $_ })

            $syntax | Should -Be @(
                'Update-CompleterSet [-Path] <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
                'Update-CompleterSet -LiteralPath <string[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
                'Update-CompleterSet -InputObject <CompleterScriptFinding[]> [-Filter <string>] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]'
            )
            (Get-Command -Name 'Update-CompleterSet').Parameters['InputObject'].ParameterType | Should -Be ([CompleterActions.CompleterScriptFinding[]])
        }

        It 'leaves a set that Test-CompleterSet finds clean and that Import-CompleterSet registers as before the script changed' {
            $before = @(Import-CompleterSet -LiteralPath $script:SetPath | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Key, $_.RuntimeKey, $_.State, $_.ScriptPath })
            $before.Count | Should -Be 3
            Remove-Module -Name 'CompleterActions' -Force

            foreach ($cleanupTarget in $script:UpdateCleanupTargets)
            {
                Invoke-TestRuntimeCompleterCleanup @cleanupTarget
            }

            Import-Module -Name $script:ManifestPath -Force | Out-Null
            Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8

            Test-CompleterSet -LiteralPath $script:SetPath | Update-CompleterSet

            Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
            @(Import-CompleterSet -LiteralPath $script:SetPath | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Key, $_.RuntimeKey, $_.State, $_.ScriptPath }) | Should -Be $before
        }

        It 'fails with the reader''s text under the update prefix for <Case>' -TestCases @(
            @{ Case = 'a set without Version = 1' }
            @{ Case = 'a directory' }
            @{ Case = 'a file that is not .psd1' }
        ) {
            $target = switch ($Case)
            {
                'a set without Version = 1'
                {
                    $path = Join-Path -Path $script:Folder -ChildPath 'version2.psd1'
                    Set-Content -LiteralPath $path -Value "@{ Version = 2; Entries = @( @{ Path = 'alpha_completer/alpha_completer.ps1'; Hash = 'x' } ) }" -Encoding utf8
                    @{ Path = $path; Message = "Completer set '$path' must declare Version = 1." }
                }
                'a directory'
                {
                    @{ Path = $script:Folder; Message = "Completer sets must be file paths. '$script:Folder' is a directory." }
                }
                'a file that is not .psd1'
                {
                    @{ Path = $script:AlphaPath; Message = "Completer sets must be .psd1 files. Received '$script:AlphaPath'." }
                }
            }
            $caught = $null

            try
            {
                Update-CompleterSet -LiteralPath $target.Path
            }
            catch
            {
                $caught = $_
            }

            $caught.Exception.Message | Should -BeExactly "Failed to update completer set. $($target.Message)"
        }
    }
}
