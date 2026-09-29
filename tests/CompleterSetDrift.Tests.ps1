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

    function Read-TestSetText
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path
        )

        @(Get-Content -LiteralPath $Path)
    }

    function Write-TestSetText
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string[]] $Line
        )

        Set-Content -LiteralPath $Path -Value $Line -Encoding utf8
    }

    # The export writes each entry as an '@{' line and a '}' line at eight spaces.
    function Get-TestEntryRange
    {
        param(
            [Parameter(Mandatory)]
            [string[]] $Line
        )

        $start = -1

        for ($index = 0; $index -lt $Line.Count; $index++)
        {
            if ($Line[$index] -match '^ {8}@\{$')
            {
                $start = $index
            }
            elseif ($Line[$index] -match '^ {8}\}$' -and $start -ge 0)
            {
                [pscustomobject] @{ Start = $start; End = $index }
                $start = -1
            }
        }
    }

    # Returns the zero-based index of an anchor line in the set text.
    function Get-TestAnchorIndex
    {
        param(
            [Parameter(Mandatory)]
            [string[]] $Line,

            [Parameter(Mandatory)]
            [ValidateSet('Entries', 'Entry', 'Path', 'Trusted', 'Hash', 'Targets')]
            [string] $Anchor,

            [Parameter()]
            [int] $Entry = 1
        )

        if ($Anchor -eq 'Entries')
        {
            for ($index = 0; $index -lt $Line.Count; $index++)
            {
                if ($Line[$index] -match '^\s*Entries\s*=')
                {
                    return $index
                }
            }

            throw 'The set text has no Entries line.'
        }

        $range = @(Get-TestEntryRange -Line $Line)[$Entry - 1]

        if ($Anchor -eq 'Entry')
        {
            return $range.Start
        }

        for ($index = $range.Start; $index -le $range.End; $index++)
        {
            if ($Line[$index] -match "^\s*$Anchor\s*=")
            {
                return $index
            }
        }

        throw "Entry $Entry of the set text has no $Anchor line."
    }

    function Get-TestAnchorLine
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $Anchor,

            [Parameter()]
            [int] $Entry = 1
        )

        (Get-TestAnchorIndex -Line (Read-TestSetText -Path $Path) -Anchor $Anchor -Entry $Entry) + 1
    }

    function Clear-TestSetLine
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $Anchor,

            [Parameter(Mandatory)]
            [int] $Entry
        )

        $lines = Read-TestSetText -Path $Path
        $removeIndex = Get-TestAnchorIndex -Line $lines -Anchor $Anchor -Entry $Entry
        Write-TestSetText -Path $Path -Line @(for ($index = 0; $index -lt $lines.Count; $index++) { if ($index -ne $removeIndex) { $lines[$index] } })
    }

    function Edit-TestSetValue
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $Anchor,

            [Parameter(Mandatory)]
            [int] $Entry,

            [Parameter(Mandatory)]
            [string] $Value
        )

        $lines = Read-TestSetText -Path $Path
        $valueIndex = Get-TestAnchorIndex -Line $lines -Anchor $Anchor -Entry $Entry
        $lines[$valueIndex] = $lines[$valueIndex] -replace '=.*$', "= $Value"
        Write-TestSetText -Path $Path -Line $lines
    }

    # Returns the zero-based first and last line of an entry's Targets block.
    function Get-TestTargetsRange
    {
        param(
            [Parameter(Mandatory)]
            [string[]] $Line,

            [Parameter(Mandatory)]
            [int] $Entry
        )

        $start = Get-TestAnchorIndex -Line $Line -Anchor 'Targets' -Entry $Entry
        $end = $start

        while ($Line[$end] -notmatch '^ {12}\)$')
        {
            $end++
        }

        [pscustomobject] @{ Start = $start; End = $end }
    }

    function Invoke-TestSetMutation
    {
        param(
            [Parameter(Mandatory)]
            [string] $Mutation
        )

        switch ($Mutation)
        {
            'a comment appended to one script'
            {
                Add-Content -LiteralPath $script:AlphaPath -Value '# drift' -Encoding utf8
            }
            'a new completer script'
            {
                $newPath = Join-Path -Path $script:Folder -ChildPath 'new_completer' -AdditionalChildPath 'new_completer.ps1'
                $null = New-Item -ItemType Directory -Path (Split-Path -Path $newPath -Parent)
                Set-Content -LiteralPath $newPath -Value "Register-ArgumentCompleter -Native -CommandName 'setfixturenew' -ScriptBlock { param(`$w, `$c, `$p) }" -Encoding utf8
            }
            'a deleted script'
            {
                Remove-Item -LiteralPath $script:BetaPath
            }
            'a target added to one script'
            {
                Add-Content -LiteralPath $script:AlphaPath -Value "Register-ArgumentCompleter -Native -CommandName 'setfixturegamma' -ScriptBlock { param(`$w, `$c, `$p) }" -Encoding utf8
            }
            'a deleted Hash line'
            {
                Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 2
            }
            "one entry's Targets copied into another"
            {
                $lines = Read-TestSetText -Path $script:SetPath
                $source = Get-TestTargetsRange -Line $lines -Entry 1
                $destination = Get-TestTargetsRange -Line $lines -Entry 2
                Write-TestSetText -Path $script:SetPath -Line @(
                    $lines[0..($destination.Start - 1)]
                    $lines[$source.Start..$source.End]
                    $lines[($destination.End + 1)..($lines.Count - 1)]
                )
            }
            'a duplicated entry'
            {
                $lines = Read-TestSetText -Path $script:SetPath
                $ranges = @(Get-TestEntryRange -Line $lines)
                Write-TestSetText -Path $script:SetPath -Line @(
                    $lines[0..$ranges[1].End]
                    $lines[$ranges[0].Start..$ranges[0].End]
                    $lines[($ranges[1].End + 1)..($lines.Count - 1)]
                )
            }
            default
            {
                throw "Unknown mutation '$Mutation'."
            }
        }
    }

    function Invoke-TestSetImport
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path
        )

        $warnings = $null

        try
        {
            $null = Import-CompleterSet -LiteralPath $Path -WarningVariable warnings -ErrorAction Stop

            [pscustomobject] @{ Rejected = $false; Problems = @(); Warnings = @($warnings) }
        }
        catch
        {
            [pscustomobject] @{
                Rejected = $true
                Problems = @($_.Exception.Message -split '\r?\n' | Select-Object -Skip 1)
                Warnings = @($warnings)
            }
        }
    }

    function Save-TestSetFolder
    {
        Copy-Item -LiteralPath $script:Folder -Destination $script:BackupFolder -Recurse
    }

    function Restore-TestSetFolder
    {
        Remove-Item -LiteralPath $script:Folder -Recurse -Force
        Copy-Item -LiteralPath $script:BackupFolder -Destination $script:Folder -Recurse
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

    # Returns the one-based line and column of the first Marker after the After text.
    function Get-TestTextPosition
    {
        param(
            [Parameter(Mandatory)]
            [string] $Text,

            [Parameter(Mandatory)]
            [string] $Marker,

            [Parameter()]
            [string] $After
        )

        $searchStart = if ($After) { $Text.IndexOf($After, [System.StringComparison]::Ordinal) } else { 0 }
        $offset = $Text.IndexOf($Marker, $searchStart, [System.StringComparison]::Ordinal)
        $before = $Text.Substring(0, $offset)

        [pscustomobject] @{
            Line   = ($before.Split("`n")).Count
            Column = $offset - $before.LastIndexOf("`n")
        }
    }

    $script:ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
    $script:NoHashFixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures' -AdditionalChildPath 'CompleterSet', 'NoHash'
    $script:DriftCleanupTargets = @(
        @{ CommandName = 'setfixturealpha'; CompleterType = 'Native' },
        @{ CommandName = 'setfixturealpha.exe'; CompleterType = 'Native' },
        @{ CommandName = 'setfixturegamma'; CompleterType = 'Native' },
        @{ CommandName = 'setfixturenew'; CompleterType = 'Native' },
        @{ CommandName = 'setfixtureprobe'; CompleterType = 'Native' },
        @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name'; CompleterType = 'Parameter' },
        @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Other'; CompleterType = 'Parameter' }
    )
}

Describe 'Test-CompleterSet' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:DriftCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name $script:ManifestPath -Force | Out-Null

        $caseRoot = Join-Path -Path $TestDrive -ChildPath ('drift-{0}' -f ([guid]::NewGuid().ToString('N')))
        $null = New-Item -ItemType Directory -Path $caseRoot
        $script:Folder = Join-Path -Path $caseRoot -ChildPath 'set'
        $script:BackupFolder = Join-Path -Path $caseRoot -ChildPath 'backup'
        Copy-Item -LiteralPath $script:NoHashFixtureRoot -Destination $script:Folder -Recurse
        $script:AlphaPath = Join-Path -Path $script:Folder -ChildPath 'alpha_completer' -AdditionalChildPath 'alpha_completer.ps1'
        $script:BetaPath = Join-Path -Path $script:Folder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1'
        $script:SetPath = Join-Path -Path $script:Folder -ChildPath 'completers.psd1'

        @(
            [pscustomobject] @{ CommandName = 'setfixturealpha'; IsNative = $true; ScriptPath = $script:AlphaPath; Trusted = $false }
            [pscustomobject] @{ CommandName = 'setfixturealpha.exe'; IsNative = $true; ScriptPath = $script:AlphaPath; Trusted = $false }
            [pscustomobject] @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name'; ScriptPath = $script:BetaPath; Trusted = $false }
        ) | Export-CompleterSet -Path $script:SetPath
    }

    AfterEach {
        foreach ($cleanupTarget in $script:DriftCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'returns nothing and leaves $? true for a set that matches its folder' {
        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath -ErrorVariable testErrors -WarningVariable testWarnings)
        $succeeded = $?

        $findings | Should -BeNullOrEmpty
        $succeeded | Should -BeTrue
        $testErrors | Should -BeNullOrEmpty
        $testWarnings | Should -BeNullOrEmpty
    }

    It 'reports <Mutation> and nothing else' -TestCases @(
        @{
            Mutation = 'a comment appended to one script'
            Expected = @(@{ Construct = 'HashMismatch'; Severity = 'Warning'; Anchor = 'Hash'; Entry = 1 })
        }
        @{
            Mutation = 'a new completer script'
            Expected = @(@{ Construct = 'UnlistedScript'; Severity = 'Warning'; Anchor = 'Entries'; Entry = 0; Message = 'new_completer.ps1' })
        }
        @{
            Mutation = 'a deleted script'
            Expected = @(@{ Construct = 'MissingScript'; Severity = 'Error'; Anchor = 'Path'; Entry = 2 })
        }
        @{
            Mutation = 'a target added to one script'
            Expected = @(
                @{ Construct = 'TargetMismatch'; Severity = 'Error'; Anchor = 'Targets'; Entry = 1; Message = 'setfixturegamma' }
                @{ Construct = 'HashMismatch'; Severity = 'Warning'; Anchor = 'Hash'; Entry = 1 }
            )
        }
        @{
            Mutation = 'a deleted Hash line'
            Expected = @(@{ Construct = 'MissingHash'; Severity = 'Warning'; Anchor = 'Entry'; Entry = 2 })
        }
        @{
            Mutation = "one entry's Targets copied into another"
            Expected = @(@{ Construct = 'TargetMismatch'; Severity = 'Error'; Anchor = 'Targets'; Entry = 2 })
        }
        @{
            Mutation = 'a duplicated entry'
            Expected = @(
                @{ Construct = 'DuplicateTarget'; Severity = 'Error'; Anchor = 'Targets'; Entry = 3; Message = "Target 'setfixturealpha' is also listed by entry 1." }
                @{ Construct = 'DuplicateTarget'; Severity = 'Error'; Anchor = 'Targets'; Entry = 3; Message = "Target 'setfixturealpha.exe' is also listed by entry 1." }
            )
        }
    ) {
        Save-TestSetFolder
        Invoke-TestSetMutation -Mutation $Mutation

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings | ForEach-Object { '{0}|{1}' -f $_.Construct, $_.Severity }) | Should -Be @($Expected | ForEach-Object { '{0}|{1}' -f $_.Construct, $_.Severity })

        for ($index = 0; $index -lt $Expected.Count; $index++)
        {
            $finding = $findings[$index]
            $finding.Path | Should -Be $script:SetPath
            $finding.Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor $Expected[$index].Anchor -Entry $Expected[$index].Entry)

            if ($Expected[$index].Message)
            {
                $finding.Message | Should -BeLike "*$($Expected[$index].Message)*"
            }
        }

        $import = Invoke-TestSetImport -Path $script:SetPath
        $import.Rejected | Should -Be (@($Expected | Where-Object { $_.Severity -eq 'Error' }).Count -gt 0)

        Restore-TestSetFolder
        Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
    }

    It 'reports MissingHash for every entry of the checked-in 2.0.0 set' {
        Copy-Item -LiteralPath (Join-Path -Path $script:NoHashFixtureRoot -ChildPath 'completers.psd1') -Destination $script:SetPath -Force

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @('MissingHash', 'MissingHash')
        @($findings.Severity | Select-Object -Unique) | Should -Be @('Warning')
        @($findings.Line) | Should -Be @(
            (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Entry' -Entry 1)
            (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Entry' -Entry 2)
        )
        $findings[0].Message | Should -BeLike "Entry 1 ('alpha_completer/alpha_completer.ps1'): *"
        $findings[1].Message | Should -BeLike "Entry 2 ('beta_completer/beta_completer.ps1'): *"
        @($findings.Hint | Select-Object -Unique) | Should -Be @('Regenerate the set with Export-CompleterSet.')
    }

    It 'reports InvalidHash as a Warning for an unrecognised Hash' {
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Hash' -Entry 1 -Value "'SHA512:abc'"

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @('InvalidHash')
        $findings[0].Severity | Should -Be 'Warning'
        $findings[0].Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Hash' -Entry 1)
        $findings[0].Message | Should -BeLike "*'SHA512:abc'*"

        $import = Invoke-TestSetImport -Path $script:SetPath
        $import.Rejected | Should -BeFalse
        $import.Warnings | Should -BeNullOrEmpty
    }

    It 'reports InvalidEntry with the import problem text word for word for <Case>' -TestCases @(
        @{ Case = 'an entry that is not a hashtable' }
        @{ Case = 'an entry without Path' }
        @{ Case = 'a path that is not a .ps1' }
        @{ Case = 'a Trusted value that is not a bool' }
        @{ Case = 'a malformed target' }
        @{ Case = 'a trusted entry without Targets' }
    ) {
        $entryLine = Get-TestAnchorLine -Path $script:SetPath -Anchor 'Entry' -Entry 2

        switch ($Case)
        {
            'an entry that is not a hashtable'
            {
                $lines = Read-TestSetText -Path $script:SetPath
                $range = @(Get-TestEntryRange -Line $lines)[1]
                Write-TestSetText -Path $script:SetPath -Line @(
                    $lines[0..($range.Start - 1)]
                    "        'beta_completer/beta_completer.ps1'"
                    $lines[($range.End + 1)..($lines.Count - 1)]
                )
            }
            'an entry without Path'
            {
                Clear-TestSetLine -Path $script:SetPath -Anchor 'Path' -Entry 2
            }
            'a path that is not a .ps1'
            {
                Copy-Item -LiteralPath $script:BetaPath -Destination ([System.IO.Path]::ChangeExtension($script:BetaPath, '.txt'))
                Edit-TestSetValue -Path $script:SetPath -Anchor 'Path' -Entry 2 -Value "'beta_completer/beta_completer.txt'"
            }
            'a Trusted value that is not a bool'
            {
                Edit-TestSetValue -Path $script:SetPath -Anchor 'Trusted' -Entry 2 -Value "'yes'"
            }
            'a malformed target'
            {
                $lines = [System.Collections.Generic.List[string]]::new([string[]] (Read-TestSetText -Path $script:SetPath))
                $targetsIndex = Get-TestAnchorIndex -Line $lines -Anchor 'Targets' -Entry 2
                $lines.Insert($targetsIndex + 1, "                @{ CommandName = 'Test-SetFixtureBeta' }")
                Write-TestSetText -Path $script:SetPath -Line $lines
            }
            'a trusted entry without Targets'
            {
                Edit-TestSetValue -Path $script:SetPath -Anchor 'Trusted' -Entry 2 -Value '$true'
                $lines = Read-TestSetText -Path $script:SetPath
                $targets = Get-TestTargetsRange -Line $lines -Entry 2
                Write-TestSetText -Path $script:SetPath -Line @(
                    $lines[0..($targets.Start - 1)]
                    $lines[($targets.End + 1)..($lines.Count - 1)]
                )
            }
        }

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)
        $invalid = @($findings | Where-Object { $_.Construct -eq 'InvalidEntry' })
        $import = Invoke-TestSetImport -Path $script:SetPath

        $import.Rejected | Should -BeTrue
        $invalid.Count | Should -Be 1
        @($invalid.Message) | Should -BeExactly @($import.Problems)
        $invalid[0].Severity | Should -Be 'Error'
        $invalid[0].Line | Should -Be $entryLine
        $invalid[0].Path | Should -Be $script:SetPath
    }

    It 'reports DuplicateTarget next to <Case> as import does' -TestCases @(
        @{
            Case     = 'a trusted entry whose script is missing'
            Entry    = '        @{ Path = ''gone_completer/gone_completer.ps1''; Trusted = $true; Targets = @(@{ CommandName = ''setfixturealpha''; Native = $true }) }'
            Expected = @('MissingScript', 'DuplicateTarget')
        }
        @{
            Case     = 'a Trusted value that is not a bool'
            Entry    = '        @{ Path = ''alpha_completer/alpha_completer.ps1''; Trusted = ''yes'' }'
            Expected = @('InvalidEntry', 'DuplicateTarget', 'DuplicateTarget')
        }
        @{
            Case     = 'a malformed target'
            Entry    = '        @{ Path = ''alpha_completer/alpha_completer.ps1''; Trusted = $false; Targets = @(@{ CommandName = ''setfixturealpha''; Native = $true }, @{ CommandName = ''setfixturealpha.exe''; Native = $true }, @{ CommandName = ''q'' }) }'
            Expected = @('InvalidEntry', 'DuplicateTarget', 'DuplicateTarget')
        }
    ) {
        $lines = Read-TestSetText -Path $script:SetPath
        $range = @(Get-TestEntryRange -Line $lines)[1]
        Write-TestSetText -Path $script:SetPath -Line @(
            $lines[0..($range.Start - 1)]
            $Entry
            $lines[($range.End + 1)..($lines.Count - 1)]
        )

        $errors = @(Test-CompleterSet -LiteralPath $script:SetPath | Where-Object { $_.Severity -eq 'Error' })
        $import = Invoke-TestSetImport -Path $script:SetPath

        $import.Rejected | Should -BeTrue
        @($errors.Construct) | Should -Be $Expected -Because 'an Error finding does not take the entry''s other targets out of the duplicate check at import'
        @($errors.Message) | Should -BeExactly @($import.Problems)
    }

    It 'reports UnreadableTargets for a strict script that <Case>' -TestCases @(
        @{
            Case    = 'does not parse'
            Content = "Register-ArgumentCompleter -Native -CommandName 'setfixturealpha' -ScriptBlock {"
            Pattern = '*does not parse*'
        }
        @{
            Case    = 'uses a non-literal target'
            Content = "`$name = 'setfixturealpha'`nRegister-ArgumentCompleter -Native -CommandName `$name -ScriptBlock { param(`$w, `$c, `$p) }"
            Pattern = '*does not use a literal -CommandName argument*'
        }
        @{
            Case    = 'registers no literal targets'
            Content = "Write-Output 'no completer here'"
            Pattern = '*does not call Register-ArgumentCompleter with literal targets*'
        }
    ) {
        Set-Content -LiteralPath $script:AlphaPath -Value $Content -Encoding utf8

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @('UnreadableTargets', 'HashMismatch')
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Path' -Entry 1)
        $findings[0].Message | Should -BeLike $Pattern

        $import = Invoke-TestSetImport -Path $script:SetPath
        @($import.Problems) | Should -BeExactly @($findings[0].Message)
    }

    It 'reports only UnreadableTargets for a strict script that cannot be read' -Skip:(-not $IsWindows) {
        $lock = [System.IO.File]::Open($script:AlphaPath, 'Open', 'ReadWrite', 'None')

        try
        {
            $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)
        }
        finally
        {
            $lock.Dispose()
        }

        @($findings.Construct) | Should -Be @('UnreadableTargets') -Because 'an unreadable script has no current hash to compare'
        $findings[0].Message | Should -BeLike '*could not be read*'
    }

    It 'never parses a trusted entry' {
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Trusted' -Entry 1 -Value '$true'
        Enable-TestParseCounter

        Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty

        Set-Content -LiteralPath $script:AlphaPath -Value "Register-ArgumentCompleter -Native -CommandName (Get-Date) -ScriptBlock {" -Encoding utf8
        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @('HashMismatch') -Because 'a trusted script is only hashed, so a script that does not parse is not UnreadableTargets'
        $calls = Get-TestParseCall
        $calls.Parses | Should -Be @($script:BetaPath, $script:BetaPath) -Because 'only the strict entry is parsed, once per run'
        $calls.Targets | Should -Be @($script:BetaPath, $script:BetaPath)
    }

    It 'reports <Kind> for a trusted entry without parsing it' -TestCases @(
        @{ Kind = 'HashMismatch'; Anchor = 'Hash' }
        @{ Kind = 'MissingHash'; Anchor = 'Entry' }
    ) {
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Trusted' -Entry 1 -Value '$true'
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Trusted' -Entry 2 -Value '$true'

        if ($Kind -eq 'HashMismatch')
        {
            Add-Content -LiteralPath $script:AlphaPath -Value '# edited after export' -Encoding utf8
        }
        else
        {
            Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1
        }

        Enable-TestParseCounter

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @($Kind)
        $findings[0].Severity | Should -Be 'Warning'
        $findings[0].Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor $Anchor -Entry 1)
        $calls = Get-TestParseCall
        $calls.Parses.Count | Should -Be 0
        $calls.Targets.Count | Should -Be 0
    }

    It 'counts a script listed by an absolute path outside the set directory as listed' {
        $outsideFolder = Join-Path -Path $TestDrive -ChildPath ('outside-{0}' -f ([guid]::NewGuid().ToString('N')))
        $null = New-Item -ItemType Directory -Path $outsideFolder
        Move-Item -LiteralPath (Split-Path -Path $script:BetaPath -Parent) -Destination $outsideFolder
        $outsideBetaPath = Join-Path -Path $outsideFolder -ChildPath 'beta_completer' -AdditionalChildPath 'beta_completer.ps1'
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Path' -Entry 1 -Value "'$script:AlphaPath'"
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Path' -Entry 2 -Value "'$outsideBetaPath'"

        Test-CompleterSet -LiteralPath $script:SetPath | Should -BeNullOrEmpty
    }

    It 'treats a listed path that differs only in case as <Expected>' -TestCases @(
        @{ Expected = if ($IsWindows) { 'listed' } else { 'unlisted' } }
    ) {
        Edit-TestSetValue -Path $script:SetPath -Anchor 'Path' -Entry 1 -Value "'alpha_completer/ALPHA_completer.ps1'"

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        if ($Expected -eq 'listed')
        {
            $findings | Should -BeNullOrEmpty -Because 'paths compare case-insensitively on Windows'
        }
        else
        {
            @($findings.Construct) | Should -Be @('MissingScript', 'UnlistedScript')
            $findings[0].Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Path' -Entry 1)
            $findings[1].Message | Should -BeLike "*'$script:AlphaPath'*"
        }
    }

    It 'scans with -Filter and ignores files that do not match it' {
        $gammaPath = Join-Path -Path $script:Folder -ChildPath 'gamma_completer' -AdditionalChildPath 'gamma_completer.ps1'
        $toolPath = Join-Path -Path $script:Folder -ChildPath 'tools' -AdditionalChildPath 'extra_tool.ps1'
        $notesPath = Join-Path -Path $script:Folder -ChildPath 'notes_completer.txt'

        foreach ($extraPath in $gammaPath, $toolPath, $notesPath)
        {
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $extraPath -Parent) -Force
            Set-Content -LiteralPath $extraPath -Value '# not listed' -Encoding utf8
        }

        $defaultFindings = @(Test-CompleterSet -LiteralPath $script:SetPath)
        $toolFindings = @(Test-CompleterSet -LiteralPath $script:SetPath -Filter '*_tool.ps1')

        @($defaultFindings.Construct) | Should -Be @('UnlistedScript')
        $defaultFindings[0].Message | Should -BeLike "*'$gammaPath'*"
        $defaultFindings[0].Line | Should -Be (Get-TestAnchorLine -Path $script:SetPath -Anchor 'Entries')
        @($toolFindings.Construct) | Should -Be @('UnlistedScript')
        $toolFindings[0].Message | Should -BeLike "*'$toolPath'*"
    }

    It 'reports a hidden script that matches -Filter as UnlistedScript' {
        $hiddenPath = Join-Path -Path $script:Folder -ChildPath '.hidden_completer.ps1'
        Set-Content -LiteralPath $hiddenPath -Value '# not listed' -Encoding utf8

        if ($IsWindows)
        {
            (Get-Item -LiteralPath $hiddenPath).Attributes = 'Hidden'
        }

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)

        @($findings.Construct) | Should -Be @('UnlistedScript')
        $findings[0].Message | Should -BeLike "*'$hiddenPath'*"
    }

    It 'writes the entry findings and then throws when a folder under the set directory cannot be read' -Skip:(-not $IsWindows) {
        Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1
        $lockedPath = Join-Path -Path $script:Folder -ChildPath 'locked'
        $null = New-Item -ItemType Directory -Path $lockedPath
        $written = [System.Collections.Generic.List[object]]::new()
        $caught = $null

        $null = icacls $lockedPath /deny "$($env:USERNAME):(OI)(CI)(RX)"
        $LASTEXITCODE | Should -Be 0

        try
        {
            Test-CompleterSet -LiteralPath $script:SetPath | ForEach-Object { $written.Add($_) }
        }
        catch
        {
            $caught = $_
        }
        finally
        {
            $null = icacls $lockedPath /remove:d $env:USERNAME
        }

        @($written.Construct) | Should -Be @('MissingHash')
        $caught | Should -Not -BeNullOrEmpty -Because 'a scan that skipped the folder could miss an unlisted script and let an empty-output gate pass'
        $caught.Exception.Message | Should -BeLike "Failed to test completer set. *'$([System.Management.Automation.WildcardPattern]::Escape($lockedPath))'*"
    }

    It 'binds <Parameter> like Import-CompleterSet' -TestCases @(
        @{ Parameter = '-Path' }
        @{ Parameter = '-LiteralPath' }
    ) {
        if ($Parameter -eq '-Path')
        {
            $secondPath = Join-Path -Path $script:Folder -ChildPath 'second.psd1'
            Copy-Item -LiteralPath $script:SetPath -Destination $secondPath
            Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1
            Clear-TestSetLine -Path $secondPath -Anchor 'Hash' -Entry 2

            $findings = @(Test-CompleterSet -Path (Join-Path -Path $script:Folder -ChildPath '*.psd1'))

            @($findings.Construct) | Should -Be @('MissingHash', 'MissingHash')
            @($findings.Path | Sort-Object) | Should -Be @(@($script:SetPath, $secondPath) | Sort-Object)
        }
        else
        {
            $bracketPath = Join-Path -Path $script:Folder -ChildPath 'set[1].psd1'
            $plainPath = Join-Path -Path $script:Folder -ChildPath 'set1.psd1'
            [System.IO.File]::Copy($script:SetPath, $bracketPath)
            [System.IO.File]::Copy($script:SetPath, $plainPath)
            Clear-TestSetLine -Path $bracketPath -Anchor 'Hash' -Entry 2
            Clear-TestSetLine -Path $plainPath -Anchor 'Hash' -Entry 1

            $literalFindings = @(Test-CompleterSet -LiteralPath $bracketPath)
            $wildcardFindings = @(Test-CompleterSet -Path $bracketPath)

            @($literalFindings.Construct) | Should -Be @('MissingHash')
            $literalFindings[0].Path | Should -Be $bracketPath
            $literalFindings[0].Message | Should -BeLike 'Entry 2 *'
            @($wildcardFindings.Path) | Should -Be @($plainPath) -Because '-Path expands the brackets, so it matches set1.psd1 and not the bracket file'
        }
    }

    It 'throws Failed to test completer set for a set without Version = 1 and never executes a script' {
        $probeFolder = Join-Path -Path $TestDrive -ChildPath ('probe-{0}' -f ([guid]::NewGuid().ToString('N')))
        $probeScript = Join-Path -Path $probeFolder -ChildPath 'probe' -AdditionalChildPath 'probe_completer.ps1'
        $probeFile = Join-Path -Path $probeFolder -ChildPath 'probe-executed.txt'
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $probeScript -Parent)
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
        $entryText = "        @{ Path = 'probe/probe_completer.ps1'; Targets = @( @{ CommandName = 'setfixtureprobe'; Native = `$true } ) }"
        $badSetPath = Join-Path -Path $probeFolder -ChildPath 'bad.psd1'
        $goodSetPath = Join-Path -Path $probeFolder -ChildPath 'good.psd1'
        Write-TestSetText -Path $badSetPath -Line @('@{', '    Version = 2', '    Entries = @(', $entryText, '    )', '}')
        Write-TestSetText -Path $goodSetPath -Line @('@{', '    Version = 1', '    Entries = @(', $entryText, '    )', '}')

        { Test-CompleterSet -LiteralPath $badSetPath } | Should -Throw -ExpectedMessage "Failed to test completer set. Completer set '$badSetPath' must declare Version = 1."
        Test-Path -LiteralPath $probeFile | Should -BeFalse

        @((Test-CompleterSet -LiteralPath $goodSetPath).Construct) | Should -Be @('MissingHash') -Because 'the strict entry is parsed and matches its script'
        Test-Path -LiteralPath $probeFile | Should -BeFalse
    }

    It 'writes the findings of an earlier set before throwing for a later unreadable set' {
        Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1
        $badSetPath = Join-Path -Path $script:Folder -ChildPath 'bad.psd1'
        Write-TestSetText -Path $badSetPath -Line @('@{', '    Version = 2', "    Entries = @( @{ Path = 'alpha_completer/alpha_completer.ps1' } )", '}')
        $written = [System.Collections.Generic.List[object]]::new()
        $caught = $null

        try
        {
            Test-CompleterSet -LiteralPath $script:SetPath, $badSetPath | ForEach-Object { $written.Add($_) }
        }
        catch
        {
            $caught = $_
        }

        @($written.Construct) | Should -Be @('MissingHash')
        $written[0].Path | Should -Be $script:SetPath
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -BeExactly "Failed to test completer set. Completer set '$badSetPath' must declare Version = 1."
    }

    It 'throws before writing anything when a path does not resolve' {
        Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1
        $missingPath = Join-Path -Path $script:Folder -ChildPath 'missing.psd1'
        $written = [System.Collections.Generic.List[object]]::new()
        $caught = $null

        try
        {
            Test-CompleterSet -LiteralPath $script:SetPath, $missingPath | ForEach-Object { $written.Add($_) }
        }
        catch
        {
            $caught = $_
        }

        $written.Count | Should -Be 0
        $caught.Exception.Message | Should -BeLike "Failed to test completer set. *$([System.Management.Automation.WildcardPattern]::Escape($missingPath))*"
    }

    It 'never reads or writes the session registrations' {
        $null = Register-Completer -LiteralPath $script:AlphaPath -Lazy
        $before = @(Get-Completer | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Key, $_.Source, $_.State, $_.ScriptPath })
        Invoke-TestSetMutation -Mutation 'a duplicated entry'
        Invoke-TestSetMutation -Mutation 'a comment appended to one script'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestSessionCalls = [System.Collections.Generic.List[string]]::new()
            $script:TestSnapshotFunction = ${function:Get-CompleterRegistrationSnapshot}
            $script:TestRuntimeFunction = ${function:Get-CompleterRuntime}
            $script:TestTableFunction = ${function:Get-ManagedCompleterRegistrationTable}

            function script:Get-CompleterRegistrationSnapshot { $script:TestSessionCalls.Add('Snapshot'); & $script:TestSnapshotFunction @args }
            function script:Get-CompleterRuntime { $script:TestSessionCalls.Add('Runtime'); & $script:TestRuntimeFunction @args }
            function script:Get-ManagedCompleterRegistrationTable { $script:TestSessionCalls.Add('Table'); & $script:TestTableFunction @args }
        }

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)
        $sessionCalls = & (Get-Module -Name 'CompleterActions') { @($script:TestSessionCalls) }

        @($findings.Construct) | Should -Be @('HashMismatch', 'DuplicateTarget', 'DuplicateTarget', 'HashMismatch')
        $sessionCalls | Should -BeNullOrEmpty
        @(Get-Completer | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Key, $_.Source, $_.State, $_.ScriptPath }) | Should -Be $before
        & (Get-Module -Name 'CompleterActions') { @($script:TestSessionCalls) } | Should -Contain 'Snapshot' -Because 'the counters see the snapshot Get-Completer takes'
    }

    It 'points findings at the right extents in <Shape> Entries arrays' -TestCases @(
        @{ Shape = 'comma-separated'; Separator = ', ' }
        @{ Shape = 'newline-separated'; Separator = "`n        " }
        @{ Shape = 'newline-separated with a $null element'; Separator = "`n        `$null`n        " }
    ) {
        $entryOne = "@{ Path = 'alpha_completer/alpha_completer.ps1'; Targets = @( @{ CommandName = 'setfixturealpha'; Native = `$true }, @{ CommandName = 'setfixturealpha.exe'; Native = `$true } ) }"
        $entryTwo = "@{ Path = 'beta_completer/beta_completer.ps1'; Hash = 'SHA512:abc'; Targets = @( @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Name' }, @{ CommandName = 'Test-SetFixtureBeta'; ParameterName = 'Other' } ) }"
        $text = "@{`n    Version = 1`n    Entries = @(`n        $entryOne$Separator$entryTwo`n    )`n}`n"
        [System.IO.File]::WriteAllText($script:SetPath, $text)

        $findings = @(Test-CompleterSet -LiteralPath $script:SetPath)
        $expected = @(
            Get-TestTextPosition -Text $text -Marker "@{ Path = 'alpha"
            Get-TestTextPosition -Text $text -Marker 'Targets' -After "Path = 'beta"
            Get-TestTextPosition -Text $text -Marker "'SHA512:abc'"
        )

        @($findings.Construct) | Should -Be @('MissingHash', 'TargetMismatch', 'InvalidHash')

        for ($index = 0; $index -lt $expected.Count; $index++)
        {
            '{0}:{1}' -f $findings[$index].Line, $findings[$index].Column | Should -Be ('{0}:{1}' -f $expected[$index].Line, $expected[$index].Column)
        }

        $findings[1].Message | Should -BeLike "Entry 2 ('beta_completer/beta_completer.ps1'): *"
        $import = Invoke-TestSetImport -Path $script:SetPath
        @($import.Problems) | Should -BeExactly @($findings[1].Message) -Because 'Import-CompleterSet numbers the entry after a $null element the same way'
    }

    It 'accepts set files piped from Get-ChildItem' {
        Clear-TestSetLine -Path $script:SetPath -Anchor 'Hash' -Entry 1

        $findings = @(Get-ChildItem -LiteralPath $script:Folder -Filter '*.psd1' | Test-CompleterSet)

        @($findings.Construct) | Should -Be @('MissingHash')
        $findings[0].Path | Should -Be $script:SetPath
    }
}
