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

    function New-TestCompleterSetPackage
    {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [string] $Root,

            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string] $Version,

            [Parameter()]
            [hashtable] $PrivateData = @{ CompleterSet = 'completers/completers.psd1' },

            [Parameter()]
            [object[]] $RequiredModules = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' }),

            [Parameter()]
            [string] $RootModule
        )

        $moduleBase = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Root, $Name, $Version))

        if (-not $PSCmdlet.ShouldProcess($moduleBase, 'Create completer set package'))
        {
            return
        }

        $setFolder = Join-Path -Path $moduleBase -ChildPath 'completers'
        New-Item -Path $setFolder -ItemType Directory -Force | Out-Null

        foreach ($fixtureFolder in 'cafixalpha_completer', 'cafixbeta_completer', 'cafixgamma_completer')
        {
            Copy-Item -LiteralPath (Join-Path -Path $script:PackageFixtureRoot -ChildPath $fixtureFolder) -Destination $setFolder -Recurse
        }

        $scriptPaths = @(Get-ChildItem -LiteralPath $setFolder -Recurse -Filter '*_completer.ps1' | Sort-Object -Property Name | ForEach-Object FullName)
        Import-CompleterScript -LiteralPath $scriptPaths | Export-CompleterSet -Path (Join-Path -Path $setFolder -ChildPath 'completers.psd1')

        $manifestParameters = @{
            Path              = Join-Path -Path $moduleBase -ChildPath "$Name.psd1"
            ModuleVersion     = $Version
            Author            = 'CompleterActions tests'
            Description       = 'Argument completers for native commands, as a CompleterActions completer set.'
            FunctionsToExport = @()
            CmdletsToExport   = @()
            VariablesToExport = @()
            AliasesToExport   = @()
            PrivateData       = $PrivateData
        }

        if ($RequiredModules.Count -gt 0)
        {
            $manifestParameters['RequiredModules'] = $RequiredModules
        }

        if (-not [string]::IsNullOrEmpty($RootModule))
        {
            $manifestParameters['RootModule'] = $RootModule
        }

        New-ModuleManifest @manifestParameters
        $moduleBase
    }

    function Export-TestPackageSet
    {
        param(
            [Parameter(Mandatory)]
            [string] $ModuleBase,

            [Parameter()]
            [string[]] $ScriptPath = @(),

            [Parameter()]
            [string[]] $TrustedScriptPath = @()
        )

        $records = @(
            if ($ScriptPath.Count -gt 0) { Import-CompleterScript -LiteralPath $ScriptPath }
            if ($TrustedScriptPath.Count -gt 0) { Import-CompleterScript -LiteralPath $TrustedScriptPath -Trusted }
        )

        $records | Export-CompleterSet -Path (Join-Path -Path $ModuleBase -ChildPath 'completers/completers.psd1')
    }

    function Join-TestModulePath
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string[]] $Root
        )

        (@($Root) + (Join-Path -Path $PSHOME -ChildPath 'Modules')) -join [System.IO.Path]::PathSeparator
    }

    function Get-TestFixtureScriptPath
    {
        param(
            [Parameter(Mandatory)]
            [string] $ModuleBase,

            [Parameter(Mandatory)]
            [ValidateSet('alpha', 'beta', 'gamma')]
            [string] $Fixture
        )

        [System.IO.Path]::Combine($ModuleBase, 'completers', "cafix$($Fixture)_completer", "cafix$($Fixture)_completer.ps1")
    }

    function Invoke-TestImportByName
    {
        param(
            [Parameter(Mandatory)]
            [string[]] $Name
        )

        $output = @(Import-CompleterSet -Name $Name -Force -Verbose 4>&1)

        [pscustomobject] @{
            Records = @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
            Verbose = @(
                $output |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^(Entry \d+ |Completer set )' } |
                    ForEach-Object { $_.Message }
            )
        }
    }

    function Get-TestModuleVerboseLine
    {
        param(
            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string] $Version,

            [Parameter(Mandatory)]
            [string] $ModuleBase,

            [Parameter()]
            [string] $SetPath = [System.IO.Path]::Combine($ModuleBase, 'completers', 'completers.psd1')
        )

        "Completer set module '$Name' $Version at '$ModuleBase': '$SetPath'."
    }

    function Get-TestPackageSetEntryIndex
    {
        param(
            [Parameter(Mandatory)]
            [string] $ModuleBase,

            [Parameter(Mandatory)]
            [string] $DeclaredPath
        )

        $entries = @((Import-PowerShellDataFile -LiteralPath (Join-Path -Path $ModuleBase -ChildPath 'completers/completers.psd1')).Entries)

        for ($index = 0; $index -lt $entries.Count; $index++)
        {
            if ($entries[$index].Path -eq $DeclaredPath)
            {
                return $index + 1
            }
        }

        throw "No entry declares '$DeclaredPath'."
    }

    function Get-TestPackageRegistration
    {
        @(Get-Completer -State Active, Pending, Failed, Stale | Where-Object { $_.Key -like 'cafix*' })
    }

    $script:ModuleManifestPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../CompleterActions.psd1'))
    $script:PackageFixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/CompleterSetPackage'
    $script:PackageCleanupTargets = @(
        foreach ($fixture in 'alpha', 'beta', 'gamma')
        {
            @{ CommandName = "cafix$fixture"; CompleterType = 'Native' }
            @{ CommandName = "cafix$fixture.exe"; CompleterType = 'Native' }
        }
    )
}

Describe 'Import-CompleterSet -Name' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:PackageCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name $script:ModuleManifestPath -Force | Out-Null

        $script:PackageRoot = Join-Path -Path $TestDrive -ChildPath ('pkg-{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:PackageRoot -ItemType Directory | Out-Null
        $script:SavedModulePath = $env:PSModulePath
    }

    AfterEach {
        $env:PSModulePath = $script:SavedModulePath

        foreach ($cleanupTarget in $script:PackageCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'uses the first root that has the module over a higher version in a later root' {
        $firstRoot = Join-Path -Path $script:PackageRoot -ChildPath 'first'
        $laterRoot = Join-Path -Path $script:PackageRoot -ChildPath 'later'
        $firstBase = New-TestCompleterSetPackage -Root $firstRoot -Name 'CaFixtureSet' -Version '1.0.0'
        $null = New-TestCompleterSetPackage -Root $laterRoot -Name 'CaFixtureSet' -Version '2.0.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $firstRoot, $laterRoot
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $firstBase)
        @($result.Records.ScriptPath | Select-Object -Unique) | Should -Be @(
            (Get-TestFixtureScriptPath -ModuleBase $firstBase -Fixture 'alpha')
            (Get-TestFixtureScriptPath -ModuleBase $firstBase -Fixture 'beta')
            (Get-TestFixtureScriptPath -ModuleBase $firstBase -Fixture 'gamma')
        )
    }

    It 'uses the highest version folder within a root' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '2.0.0'
        $highestBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '10.0.0'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '9.1.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '10.0.0' -ModuleBase $highestBase)
    }

    It "skips a version folder that differs from its manifest's ModuleVersion for <Case>" -TestCases @(
        @{ Case = 'folder 9.0.0 with 1.0.0'; Folder = '9.0.0'; ManifestVersion = '1.0.0'; ValidVersion = '2.0.0' }
        @{ Case = 'folder 1.0.0.0 with 1.0.0'; Folder = '1.0.0.0'; ManifestVersion = '1.0.0'; ValidVersion = '0.9.0' }
    ) {
        param($Case, $Folder, $ManifestVersion, $ValidVersion)

        $null = $Case
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $mismatchedBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version $ManifestVersion
        Rename-Item -LiteralPath $mismatchedBase -NewName $Folder
        $validBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version $ValidVersion

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version $ValidVersion -ModuleBase $validBase)
    }

    It 'uses the unversioned layout only when the root has no versioned candidate' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleFolder = Join-Path -Path $root -ChildPath 'CaFixtureSet'
        $stagedBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '3.0.0'
        New-Item -Path $moduleFolder -ItemType Directory | Out-Null
        Get-ChildItem -LiteralPath $stagedBase | Move-Item -Destination $moduleFolder
        $versionedBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $withVersioned = Invoke-TestImportByName -Name 'CaFixtureSet'

            Remove-Item -LiteralPath $versionedBase -Recurse -Force
            $unversionedOnly = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $withVersioned.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $versionedBase)
        $unversionedOnly.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '3.0.0' -ModuleBase ([System.IO.Path]::GetFullPath($moduleFolder)))
    }

    It 'finds a module folder spelled CaFixtureSet by -Name cafixtureset and names it CaFixtureSet in the verbose line' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'cafixtureset'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $moduleBase)
        $result.Records.Count | Should -Be 6
    }

    It 'finds a manifest whose base name differs from its folder only by case' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $manifestPath = Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psd1'
        $interimPath = Join-Path -Path $moduleBase -ChildPath 'interim.tmp'
        [System.IO.File]::Move($manifestPath, $interimPath)
        [System.IO.File]::Move($interimPath, (Join-Path -Path $moduleBase -ChildPath 'cafixtureset.psd1'))

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $moduleBase)
        $result.Records.Count | Should -Be 6
    }

    It 'skips empty and missing PSModulePath entries' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $missingRoot = Join-Path -Path $script:PackageRoot -ChildPath 'missing'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root '', $missingRoot, '', $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $moduleBase)
        $result.Records.Count | Should -Be 6
    }

    It 'fails with the section 3 text for <Case>' -TestCases @(
        @{ Case = 'a missing module'; Kind = 'Missing'; Value = $null }
        @{ Case = 'a manifest without CompleterSet'; Kind = 'NotDeclared'; Value = $null }
        @{ Case = 'an empty value'; Kind = 'Invalid'; Value = '' }
        @{ Case = 'a value directly in ModuleBase'; Kind = 'Invalid'; Value = 'completers.psd1' }
        @{ Case = 'a value with ..'; Kind = 'Invalid'; Value = '../completers.psd1' }
        @{ Case = 'a rooted value'; Kind = 'Invalid'; Value = '<rooted>' }
        @{ Case = 'a value two folders deep'; Kind = 'Invalid'; Value = 'completers/nested/completers.psd1' }
        @{ Case = 'a non-.psd1 value'; Kind = 'Invalid'; Value = 'completers/completers.txt' }
        @{ Case = 'a missing set file'; Kind = 'MissingSet'; Value = 'other/completers.psd1' }
    ) {
        param($Case, $Kind, $Value)

        $null = $Case
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, 'CaFixtureSet', '1.0.0'))

        if ($Value -eq '<rooted>')
        {
            $Value = Join-Path -Path $moduleBase -ChildPath 'completers/completers.psd1'
        }

        $privateData = if ($Kind -eq 'NotDeclared') { @{} } elseif ($null -ne $Value) { @{ CompleterSet = $Value } } else { @{ CompleterSet = 'completers/completers.psd1' } }
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -PrivateData $privateData
        $requestedName = if ($Kind -eq 'Missing') { 'cafixmissing' } else { 'CaFixtureSet' }

        $expected = switch ($Kind)
        {
            'Missing' { "No installed module named 'cafixmissing' was found in `$env:PSModulePath. Install it with Install-PSResource cafixmissing." }
            'NotDeclared' { "The module 'CaFixtureSet' 1.0.0 at '$moduleBase' does not declare a completer set. A completer set module names its set file in PrivateData.CompleterSet." }
            'Invalid' { "The module 'CaFixtureSet' 1.0.0 declares the completer set '$Value', which must be a .psd1 file in a folder directly below '$moduleBase'." }
            'MissingSet' { "The completer set '$([System.IO.Path]::Combine($moduleBase, 'other', 'completers.psd1'))' declared by the module 'CaFixtureSet' 1.0.0 does not exist." }
        }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrown = { Import-CompleterSet -Name $requestedName } | Should -Throw -PassThru
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrown.Exception.Message | Should -BeExactly "Failed to import completer set. $expected"
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It 'accepts a backslash as the separator in PrivateData.CompleterSet' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -PrivateData @{ CompleterSet = 'completers\completers.psd1' }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $moduleBase)
        $result.Records.Count | Should -Be 6
    }

    It 'uses the highest version even when it is broken and never falls back' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $brokenBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '2.0.0' -PrivateData @{ CompleterSet = 'missing/completers.psd1' }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrown = { Import-CompleterSet -Name 'CaFixtureSet' } | Should -Throw -PassThru
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrown.Exception.Message | Should -BeExactly "Failed to import completer set. The completer set '$([System.IO.Path]::Combine($brokenBase, 'missing', 'completers.psd1'))' declared by the module 'CaFixtureSet' 2.0.0 does not exist."
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It 'fails on an unreadable manifest in the highest version folder and never falls back' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $brokenBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '2.0.0'
        $brokenManifestPath = Join-Path -Path $brokenBase -ChildPath 'CaFixtureSet.psd1'
        Set-Content -LiteralPath $brokenManifestPath -Value '@{ ModuleVersion = ' -Encoding utf8

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrown = { Import-CompleterSet -Name 'CaFixtureSet' } | Should -Throw -PassThru
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrown.Exception.Message.StartsWith('Failed to import completer set. ', [System.StringComparison]::Ordinal) | Should -BeTrue -Because $thrown.Exception.Message
        $thrown.Exception.Message.Contains($brokenManifestPath) | Should -BeTrue -Because $thrown.Exception.Message
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It 'fails a wildcard name before resolving anything' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestResolveCalls = 0

            function script:Resolve-CompleterSetModule
            {
                param([string] $Name)

                $null = $Name
                $script:TestResolveCalls++
                throw 'Resolve-CompleterSetModule ran.'
            }
        }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root

            foreach ($wildcardName in 'CaFix*', 'CaFixtureSe?', 'CaFixture[S]et', 'CaFixtureSet]')
            {
                $thrown = { Import-CompleterSet -Name 'CaFixtureSet', $wildcardName } | Should -Throw -PassThru
                $thrown.Exception.Message | Should -BeExactly "Failed to import completer set. Import-CompleterSet -Name does not accept wildcards. Received '$wildcardName'."
            }
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        (& (Get-Module -Name 'CompleterActions') { $script:TestResolveCalls }) | Should -Be 0
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It 'never runs a RootModule, a ScriptsToProcess script, a NestedModules entry, or a RequiredModules module' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $markerFolder = Join-Path -Path $script:PackageRoot -ChildPath 'markers'
        New-Item -Path $markerFolder -ItemType Directory | Out-Null
        $markerLine = { param($marker) "Set-Content -LiteralPath '$(Join-Path -Path $markerFolder -ChildPath $marker)' -Value 'ran'" }

        $requiredBase = Join-Path -Path $root -ChildPath 'CaFixMarkerRequired/1.0.0'
        New-Item -Path $requiredBase -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $requiredBase -ChildPath 'CaFixMarkerRequired.psm1') -Value (& $markerLine 'required.txt') -Encoding utf8
        New-ModuleManifest -Path (Join-Path -Path $requiredBase -ChildPath 'CaFixMarkerRequired.psd1') -ModuleVersion '1.0.0' -RootModule 'CaFixMarkerRequired.psm1' -Author 'CompleterActions tests' -Description 'Writes a marker when it is imported.'

        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -RootModule 'CaFixtureSet.psm1' -RequiredModules @('CaFixMarkerRequired')
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psm1') -Value (& $markerLine 'root.txt') -Encoding utf8
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'setup.ps1') -Value (& $markerLine 'scripts-to-process.txt') -Encoding utf8
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'nested.psm1') -Value (& $markerLine 'nested.txt') -Encoding utf8
        $manifestPath = Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psd1'
        $manifestText = (Get-Content -LiteralPath $manifestPath -Raw).
            Replace("# ScriptsToProcess = @()", "ScriptsToProcess = @('setup.ps1')").
            Replace("# NestedModules = @()", "NestedModules = @('nested.psm1')")
        Set-Content -LiteralPath $manifestPath -Value $manifestText -Encoding utf8 -NoNewline

        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
        $manifest.RootModule | Should -Be 'CaFixtureSet.psm1'
        @($manifest.ScriptsToProcess) | Should -Be @('setup.ps1')
        @($manifest.NestedModules) | Should -Be @('nested.psm1')
        @($manifest.RequiredModules) | Should -Be @('CaFixMarkerRequired')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Records.Count | Should -Be 6
        @(Get-ChildItem -LiteralPath $markerFolder) | Should -BeNullOrEmpty
        Get-Module -Name 'CaFixtureSet', 'CaFixMarkerRequired' | Should -BeNullOrEmpty
    }

    It 'resolves every name before importing any set' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrown = { Import-CompleterSet -Name 'CaFixtureSet', 'CaFixMissing' } | Should -Throw -PassThru
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrown.Exception.Message | Should -BeExactly "Failed to import completer set. No installed module named 'CaFixMissing' was found in `$env:PSModulePath. Install it with Install-PSResource CaFixMissing."
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It 'returns ModuleBase as a full path when a root carries a .. segment' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        New-Item -Path (Join-Path -Path $script:PackageRoot -ChildPath 'unused') -ItemType Directory | Out-Null
        $dottedRoot = [System.IO.Path]::Combine($script:PackageRoot, 'unused', '..', 'modules')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $dottedRoot
            $module = & (Get-Module -Name 'CompleterActions') { Resolve-CompleterSetModule -Name 'CaFixtureSet' }
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $module.ModuleBase | Should -BeExactly $moduleBase
        $module.ModuleBase | Should -Not -Match '\.\.'
        $module.SetPath | Should -BeExactly ([System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1'))
        $module.ManifestPath | Should -BeExactly ([System.IO.Path]::Combine($moduleBase, 'CaFixtureSet.psd1'))
        $module.Name | Should -BeExactly 'CaFixtureSet'
        $module.Version | Should -BeExactly '1.0.0'
    }

    It 'fails a set whose entry resolves outside the module, and skips it under -SkipInvalid' -TestCases @(
        @{ SkipInvalid = $false }
        @{ SkipInvalid = $true }
    ) {
        param($SkipInvalid)

        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $outsidePath = [System.IO.Path]::GetFullPath((Join-Path -Path $moduleBase -ChildPath '../outside_completer.ps1'))
        Move-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'alpha') -Destination $outsidePath
        Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath $outsidePath, (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta'), (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma')
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $entryIndex = Get-TestPackageSetEntryIndex -ModuleBase $moduleBase -DeclaredPath '../../outside_completer.ps1'
        $problemLine = "Entry $entryIndex ('../../outside_completer.ps1'): the script '$outsidePath' is outside the module 'CaFixtureSet' at '$moduleBase'"

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root

            if ($SkipInvalid)
            {
                $registered = @(Import-CompleterSet -Name 'CaFixtureSet' -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)
            }
            else
            {
                $thrown = { Import-CompleterSet -Name 'CaFixtureSet' } | Should -Throw -PassThru
            }
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        if ($SkipInvalid)
        {
            @($warnings.Message) | Should -Be @("Completer set '$setPath' skipped $problemLine")
            @($registered.Key | Sort-Object) | Should -Be @('cafixbeta', 'cafixbeta.exe', 'cafixgamma', 'cafixgamma.exe')
        }
        else
        {
            $thrown.Exception.Message | Should -BeExactly "Failed to import completer set. Completer set '$setPath' has 1 invalid entry and nothing was registered. Fix the entries or use -SkipInvalid to register the valid ones.$([Environment]::NewLine)$problemLine"
            Get-TestPackageRegistration | Should -BeNullOrEmpty
        }
    }

    It 'reports only the outside-module problem for an outside entry whose file is missing' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $outsidePath = [System.IO.Path]::GetFullPath((Join-Path -Path $moduleBase -ChildPath '../outside_completer.ps1'))
        Move-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'alpha') -Destination $outsidePath
        Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath $outsidePath, (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta'), (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma')
        Remove-Item -LiteralPath $outsidePath
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $entryIndex = Get-TestPackageSetEntryIndex -ModuleBase $moduleBase -DeclaredPath '../../outside_completer.ps1'

        & (Get-Module -Name 'CompleterActions') {
            $script:TestHashPaths = [System.Collections.Generic.List[string]]::new()

            function script:Get-CompleterScriptHash
            {
                param([string] $LiteralPath, [string] $Text)

                $null = $Text
                if (-not [string]::IsNullOrEmpty($LiteralPath))
                {
                    $script:TestHashPaths.Add($LiteralPath)
                }

                'SHA256:0000000000000000000000000000000000000000000000000000000000000000'
            }
        }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $registered = @(Import-CompleterSet -Name 'CaFixtureSet' -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        @($warnings.Message) | Should -Be @("Completer set '$setPath' skipped Entry $entryIndex ('../../outside_completer.ps1'): the script '$outsidePath' is outside the module 'CaFixtureSet' at '$moduleBase'")
        $hashPaths = @(& (Get-Module -Name 'CompleterActions') { $script:TestHashPaths })
        $hashPaths.Count | Should -Be 2 -Because 'the two inside strict entries carry a Hash and are hashed once each'
        @($hashPaths | Where-Object { $_ -eq $outsidePath }).Count | Should -Be 0
        $registered.Count | Should -Be 4
    }

    It "treats a sibling folder whose name extends the module's as outside" {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleFolder = [System.IO.Path]::GetFullPath((Join-Path -Path $root -ChildPath 'CaFixtureSet'))
        $stagedBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0'
        New-Item -Path $moduleFolder -ItemType Directory | Out-Null
        Get-ChildItem -LiteralPath $stagedBase | Move-Item -Destination $moduleFolder
        $siblingFolder = Join-Path -Path $root -ChildPath 'CaFixtureSet2'
        New-Item -Path $siblingFolder -ItemType Directory | Out-Null
        $siblingPath = [System.IO.Path]::GetFullPath((Join-Path -Path $siblingFolder -ChildPath 'cafixalpha_completer.ps1'))
        Move-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleFolder -Fixture 'alpha') -Destination $siblingPath
        Export-TestPackageSet -ModuleBase $moduleFolder -ScriptPath $siblingPath, (Get-TestFixtureScriptPath -ModuleBase $moduleFolder -Fixture 'beta'), (Get-TestFixtureScriptPath -ModuleBase $moduleFolder -Fixture 'gamma')
        $setPath = [System.IO.Path]::Combine($moduleFolder, 'completers', 'completers.psd1')
        $entryIndex = Get-TestPackageSetEntryIndex -ModuleBase $moduleFolder -DeclaredPath '../../CaFixtureSet2/cafixalpha_completer.ps1'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $registered = @(Import-CompleterSet -Name 'CaFixtureSet' -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        @($warnings.Message) | Should -Be @("Completer set '$setPath' skipped Entry $entryIndex ('../../CaFixtureSet2/cafixalpha_completer.ps1'): the script '$siblingPath' is outside the module 'CaFixtureSet' at '$moduleFolder'")
        $registered.Count | Should -Be 4
    }

    It "compares containment with the platform's case rule" {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $casedPath = '../../../cafixtureset/1.0.0/completers/cafixalpha_completer/cafixalpha_completer.ps1'
        $setText = (Get-Content -LiteralPath $setPath -Raw).Replace("'cafixalpha_completer/cafixalpha_completer.ps1'", "'$casedPath'")
        Set-Content -LiteralPath $setPath -Value $setText -Encoding utf8 -NoNewline
        $entryIndex = Get-TestPackageSetEntryIndex -ModuleBase $moduleBase -DeclaredPath $casedPath
        $resolvedCasedPath = [System.IO.Path]::GetFullPath($casedPath, (Split-Path -Path $setPath -Parent))

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $registered = @(Import-CompleterSet -Name 'CaFixtureSet' -SkipInvalid -WarningVariable warnings -WarningAction SilentlyContinue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        if ($IsLinux)
        {
            @($warnings.Message) | Should -Be @("Completer set '$setPath' skipped Entry $entryIndex ('$casedPath'): the script '$resolvedCasedPath' is outside the module 'CaFixtureSet' at '$moduleBase'")
            $registered.Count | Should -Be 4
        }
        else
        {
            $warnings | Should -BeNullOrEmpty
            $registered.Count | Should -Be 6
        }
    }

    It 'writes one trusted-entry warning naming CaFixtureSet for a package with two trusted entries, and none through -LiteralPath' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma') -TrustedScriptPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'alpha'), (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta')
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $byName = @(Import-CompleterSet -Name 'cafixtureset' -WarningVariable nameWarnings -WarningAction SilentlyContinue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $byPath = @(Import-CompleterSet -LiteralPath $setPath -WarningVariable pathWarnings -WarningAction SilentlyContinue)

        @($nameWarnings.Message) | Should -Be @("The completer set module 'CaFixtureSet' 1.0.0 declares 2 trusted completer scripts, which run without the strict grammar check at first tab.")
        $pathWarnings | Should -BeNullOrEmpty
        $byName.Count | Should -Be 6
        $byPath.Count | Should -Be 6
        @($byName | Where-Object Trusted).Count | Should -Be 4
    }

    It 'writes the trusted-entry warning even when the set then fails' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $outsidePath = [System.IO.Path]::GetFullPath((Join-Path -Path $moduleBase -ChildPath '../outside_completer.ps1'))
        Move-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma') -Destination $outsidePath
        Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath $outsidePath -TrustedScriptPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'alpha'), (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrownMessage = $null

            try
            {
                $null = Import-CompleterSet -Name 'CaFixtureSet' -WarningVariable failedSetWarnings -WarningAction SilentlyContinue
            }
            catch
            {
                $thrownMessage = $_.Exception.Message
            }
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrownMessage | Should -Match ([regex]::Escape("is outside the module 'CaFixtureSet' at '$moduleBase'"))
        @($failedSetWarnings.Message) | Should -Be @("The completer set module 'CaFixtureSet' 1.0.0 declares 2 trusted completer scripts, which run without the strict grammar check at first tab.")
        Get-TestPackageRegistration | Should -BeNullOrEmpty
    }

    It "writes the module verbose line before the set's own lines" {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose | Should -Be @(
            (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0' -ModuleBase $moduleBase)
            "Entry 1 ('cafixalpha_completer/cafixalpha_completer.ps1'): hash matches; targets read from the set."
            "Entry 2 ('cafixbeta_completer/cafixbeta_completer.ps1'): hash matches; targets read from the set."
            "Entry 3 ('cafixgamma_completer/cafixgamma_completer.ps1'): hash matches; targets read from the set."
            "Completer set '$setPath': 3 entries from the hash, 0 parsed, 0 trusted."
        )
    }

    It 'shows the version with its prerelease label' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        $manifestPath = Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psd1'
        $manifestText = (Get-Content -LiteralPath $manifestPath -Raw).Replace("# Prerelease = ''", "Prerelease = 'preview1'")
        Set-Content -LiteralPath $manifestPath -Value $manifestText -Encoding utf8 -NoNewline
        (Import-PowerShellDataFile -LiteralPath $manifestPath).PrivateData.PSData.Prerelease | Should -Be 'preview1'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $result = Invoke-TestImportByName -Name 'CaFixtureSet'
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $result.Verbose[0] | Should -BeExactly (Get-TestModuleVerboseLine -Name 'CaFixtureSet' -Version '1.0.0-preview1' -ModuleBase $moduleBase)
    }

    It 'keeps Path as the default set and binds no pipeline input to -Name' {
        $command = Get-Command -Name 'Import-CompleterSet'
        $nameAttributes = @($command.Parameters['Name'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $pathAttributes = @($command.Parameters['Path'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })

        $command.DefaultParameterSet | Should -Be 'Path'
        $nameAttributes.Count | Should -Be 1
        $nameAttributes[0].ParameterSetName | Should -Be 'Name'
        $nameAttributes[0].Mandatory | Should -BeTrue
        $nameAttributes[0].Position | Should -Be ([int]::MinValue)
        $nameAttributes[0].ValueFromPipeline | Should -BeFalse
        $nameAttributes[0].ValueFromPipelineByPropertyName | Should -BeFalse
        $pathAttributes[0].Position | Should -Be 0
    }

    It 'packs the fixture package with Compress-PSResource' {
        if (-not (Get-Command -Name 'Compress-PSResource' -ErrorAction Ignore))
        {
            Set-ItResult -Skipped -Because 'PSResourceGet 1.1.0 or later is required'
        }

        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'source') -Name 'CaFixtureSet' -Version '1.0.0'
        $destination = Join-Path -Path $script:PackageRoot -ChildPath 'packed'
        New-Item -Path $destination -ItemType Directory | Out-Null

        Compress-PSResource -Path $moduleBase -DestinationPath $destination -SkipModuleManifestValidate -ErrorAction Stop

        @(Get-ChildItem -LiteralPath $destination -Filter '*.nupkg').Name | Should -Be @('CaFixtureSet.1.0.0.nupkg')
    }

    It 'refuses to pack a second .psd1 beside the manifest' {
        if (-not (Get-Command -Name 'Compress-PSResource' -ErrorAction Ignore))
        {
            Set-ItResult -Skipped -Because 'PSResourceGet 1.1.0 or later is required'
        }

        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'Linux lists the folder unsorted, so which .psd1 is taken depends on the file system'
        }

        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'source') -Name 'CaFixtureSet' -Version '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'aaa.psd1') -Value '@{ Version = 1 }' -Encoding utf8
        $destination = Join-Path -Path $script:PackageRoot -ChildPath 'packed'
        New-Item -Path $destination -ItemType Directory | Out-Null

        { Compress-PSResource -Path $moduleBase -DestinationPath $destination -SkipModuleManifestValidate -ErrorAction Stop } | Should -Throw
    }

    It 'imports by name from a saved package exactly as -LiteralPath does in a second process' {
        if (-not (Get-Command -Name 'Compress-PSResource' -ErrorAction Ignore))
        {
            Set-ItResult -Skipped -Because 'PSResourceGet 1.1.0 or later is required'
        }

        if ($IsWindows -and $env:GITHUB_ACTIONS -ne 'true')
        {
            Set-ItResult -Skipped -Because 'the PSResourceGet store cannot be redirected on Windows'
        }

        $packageBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'source') -Name 'CaFixtureSet' -Version '1.0.0'
        $repositoryPath = Join-Path -Path $script:PackageRoot -ChildPath 'repo'
        $modulesPath = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $dataHome = Join-Path -Path $script:PackageRoot -ChildPath 'xdg'
        New-Item -Path $repositoryPath, $modulesPath, $dataHome -ItemType Directory | Out-Null
        $repositoryName = 'CaLocal-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))

        $publishScriptPath = Join-Path -Path $script:PackageRoot -ChildPath 'publish.ps1'
        Set-Content -LiteralPath $publishScriptPath -Encoding utf8 -Value @'
param($RepositoryName, $RepositoryPath, $PackagePath, $ModulesPath)
$ErrorActionPreference = 'Stop'
'repositories before: ' + (@(Get-PSResourceRepository | ForEach-Object Name | Sort-Object) -join ', ')
try
{
    Register-PSResourceRepository -Name $RepositoryName -Uri $RepositoryPath -Trusted
    Publish-PSResource -Path $PackagePath -Repository $RepositoryName -SkipModuleManifestValidate -SkipDependenciesCheck
    Save-PSResource -Name 'CaFixtureSet' -Repository $RepositoryName -Path $ModulesPath -SkipDependencyCheck
}
finally
{
    Unregister-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue
}
'repositories after: ' + (@(Get-PSResourceRepository | ForEach-Object Name | Sort-Object) -join ', ')
'@

        $savedDataHome = $env:XDG_DATA_HOME
        try
        {
            if (-not $IsWindows)
            {
                $env:XDG_DATA_HOME = $dataHome
            }

            $publishOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $publishScriptPath -RepositoryName $repositoryName -RepositoryPath $repositoryPath -PackagePath $packageBase -ModulesPath $modulesPath 2>&1)
            $publishExitCode = $LASTEXITCODE
        }
        finally
        {
            $env:XDG_DATA_HOME = $savedDataHome
        }

        $publishExitCode | Should -Be 0 -Because ($publishOutput -join [Environment]::NewLine)
        $repositoriesBefore = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('repositories before: ', [System.StringComparison]::Ordinal) })
        $repositoriesAfter = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('repositories after: ', [System.StringComparison]::Ordinal) })
        $repositoriesBefore.Count | Should -Be 1 -Because ($publishOutput -join [Environment]::NewLine)
        $repositoriesAfter.Count | Should -Be 1 -Because ($publishOutput -join [Environment]::NewLine)
        $repositoriesAfter[0].Substring('repositories after: '.Length) | Should -BeExactly $repositoriesBefore[0].Substring('repositories before: '.Length)

        $savedBase = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($modulesPath, 'CaFixtureSet', '1.0.0'))
        $savedSetPath = [System.IO.Path]::Combine($savedBase, 'completers', 'completers.psd1')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $modulesPath
            $byName = @(Import-CompleterSet -Name 'CaFixtureSet' -WarningVariable importWarnings -ErrorVariable importErrors -ErrorAction Continue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $literalScriptPath = Join-Path -Path $script:PackageRoot -ChildPath 'literal.ps1'
        Set-Content -LiteralPath $literalScriptPath -Encoding utf8 -Value @'
param($ModuleManifestPath, $SetPath)
$ErrorActionPreference = 'Stop'
Import-Module -Name $ModuleManifestPath -Force
Import-CompleterSet -LiteralPath $SetPath | Select-Object -Property Key, RuntimeKey, State, Trusted, ScriptPath | ConvertTo-Csv
'@
        $literalCsv = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $literalScriptPath -ModuleManifestPath $script:ModuleManifestPath -SetPath $savedSetPath 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($literalCsv -join [Environment]::NewLine)

        $byNameCsv = @($byName | Select-Object -Property Key, RuntimeKey, State, Trusted, ScriptPath | ConvertTo-Csv)
        $byName.Count | Should -Be 6
        $byNameCsv | Should -Be $literalCsv
        foreach ($record in $byName)
        {
            $record.ScriptPath.StartsWith($savedBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal) | Should -BeTrue -Because "'$($record.ScriptPath)' must be under '$savedBase'"
        }

        $importWarnings | Should -BeNullOrEmpty
        $importErrors | Should -BeNullOrEmpty
    }
}

Describe 'Test-CompleterSet package checks' {
    BeforeAll {
        function Format-TestFinding
        {
            param(
                [Parameter(ValueFromPipeline)]
                [object] $Finding
            )

            process
            {
                '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $Finding.Path, $Finding.Line, $Finding.Column, $Finding.Severity, $Finding.Construct, $Finding.Message, $Finding.Hint
            }
        }

        function Get-TestOutsideFinding
        {
            param(
                [Parameter(Mandatory)]
                [string] $SetPath,

                [Parameter(Mandatory)]
                [int] $Index,

                [Parameter(Mandatory)]
                [string] $DeclaredPath
            )

            $setLines = @(Get-Content -LiteralPath $SetPath)
            $quotedPath = "'$DeclaredPath'"

            for ($lineIndex = 0; $lineIndex -lt $setLines.Count; $lineIndex++)
            {
                $column = $setLines[$lineIndex].IndexOf($quotedPath, [System.StringComparison]::Ordinal)

                if ($column -ge 0)
                {
                    return '{0}|{1}|{2}|Error|PackageLayout|Entry {3} ({4}): the script is outside the module folder, so an installed copy of the package does not contain it.|Move the script under the folder that holds the set file, then regenerate the set with Export-CompleterSet.' -f $SetPath, ($lineIndex + 1), ($column + 1), $Index, $quotedPath
                }
            }

            throw "The set '$SetPath' does not declare '$DeclaredPath'."
        }

        function Get-TestExtraManifestFinding
        {
            param(
                [Parameter(Mandatory)]
                [string] $SetPath,

                [Parameter(Mandatory)]
                [string] $ModuleBase,

                [Parameter(Mandatory)]
                [string] $FileName,

                [Parameter(Mandatory)]
                [string] $ManifestName
            )

            "$SetPath|1|1|Error|PackageLayout|The module folder '$ModuleBase' holds '$FileName' beside the module manifest '$ManifestName', so Publish-PSResource can take the wrong file as the manifest.|Keep the module manifest as the only .psd1 in the module folder; move the set into a subfolder and update PrivateData.CompleterSet."
        }

        function Get-TestSetNameFinding
        {
            param(
                [Parameter(Mandatory)]
                [string] $SetPath,

                [Parameter(Mandatory)]
                [string] $ModuleName
            )

            "$SetPath|1|1|Error|PackageLayout|The set file '$([System.IO.Path]::GetFileName($SetPath))' has the base name of the module '$ModuleName', so PSResourceGet can take it as the module manifest when it saves or installs the package.|Rename the set file so its base name differs from the module name, for example to completers.psd1, and update PrivateData.CompleterSet."
        }

        function Get-TestRequiredModulesFinding
        {
            param(
                [Parameter(Mandatory)]
                [string] $SetPath,

                [Parameter(Mandatory)]
                [string] $ManifestPath
            )

            "$SetPath|1|1|Warning|PackageLayout|The module manifest '$ManifestPath' does not require CompleterActions 2.2.0 or later, so installing the package does not install Import-CompleterSet -Name.|Add @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' } to RequiredModules in '$ManifestPath'."
        }

        function Set-TestQualifiedEntryPath
        {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [Parameter(Mandatory)]
                [string] $ModuleBase,

                [Parameter(Mandatory)]
                [ValidateSet('alpha', 'beta', 'gamma')]
                [string] $Fixture
            )

            $setPath = [System.IO.Path]::Combine($ModuleBase, 'completers', 'completers.psd1')
            $qualifiedPath = Get-TestFixtureScriptPath -ModuleBase $ModuleBase -Fixture $Fixture

            if ($PSCmdlet.ShouldProcess($setPath, 'Qualify an entry Path'))
            {
                $setText = (Get-Content -LiteralPath $setPath -Raw).Replace("'cafix$($Fixture)_completer/cafix$($Fixture)_completer.ps1'", "'$qualifiedPath'")
                Set-Content -LiteralPath $setPath -Value $setText -Encoding utf8 -NoNewline
            }

            $qualifiedPath
        }

        function Save-TestCompleterSetPackage
        {
            param(
                [Parameter(Mandatory)]
                [string] $PackageBase,

                [Parameter(Mandatory)]
                [string] $WorkFolder
            )

            $repositoryPath = Join-Path -Path $WorkFolder -ChildPath 'repo'
            $modulesPath = Join-Path -Path $WorkFolder -ChildPath 'saved'
            $dataHome = Join-Path -Path $WorkFolder -ChildPath 'xdg'
            New-Item -Path $repositoryPath, $modulesPath, $dataHome -ItemType Directory | Out-Null
            $repositoryName = 'CaLocal-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))

            $publishScriptPath = Join-Path -Path $WorkFolder -ChildPath 'publish.ps1'
            Set-Content -LiteralPath $publishScriptPath -Encoding utf8 -Value @'
param($RepositoryName, $RepositoryPath, $PackagePath, $ModulesPath)
$ErrorActionPreference = 'Stop'
'repositories before: ' + (@(Get-PSResourceRepository | ForEach-Object Name | Sort-Object) -join ', ')
try
{
    Register-PSResourceRepository -Name $RepositoryName -Uri $RepositoryPath -Trusted
    Publish-PSResource -Path $PackagePath -Repository $RepositoryName -SkipModuleManifestValidate -SkipDependenciesCheck
    Save-PSResource -Name 'CaFixtureSet' -Repository $RepositoryName -Path $ModulesPath -SkipDependencyCheck
}
finally
{
    Unregister-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue
}
'repositories after: ' + (@(Get-PSResourceRepository | ForEach-Object Name | Sort-Object) -join ', ')
'@

            $savedDataHome = $env:XDG_DATA_HOME
            try
            {
                if (-not $IsWindows)
                {
                    $env:XDG_DATA_HOME = $dataHome
                }

                $publishOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -File $publishScriptPath -RepositoryName $repositoryName -RepositoryPath $repositoryPath -PackagePath $PackageBase -ModulesPath $modulesPath 2>&1)
                $publishExitCode = $LASTEXITCODE
            }
            finally
            {
                $env:XDG_DATA_HOME = $savedDataHome
            }

            $publishExitCode | Should -Be 0 -Because ($publishOutput -join [Environment]::NewLine)
            $repositoriesBefore = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('repositories before: ', [System.StringComparison]::Ordinal) })
            $repositoriesAfter = @($publishOutput | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('repositories after: ', [System.StringComparison]::Ordinal) })
            $repositoriesBefore.Count | Should -Be 1 -Because ($publishOutput -join [Environment]::NewLine)
            $repositoriesAfter.Count | Should -Be 1 -Because ($publishOutput -join [Environment]::NewLine)
            $repositoriesAfter[0].Substring('repositories after: '.Length) | Should -BeExactly $repositoriesBefore[0].Substring('repositories before: '.Length)

            $modulesPath
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ModuleManifestPath -Force | Out-Null

        $script:PackageRoot = Join-Path -Path $TestDrive -ChildPath ('pkg-{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:PackageRoot -ItemType Directory | Out-Null
        $script:SavedModulePath = $env:PSModulePath
    }

    AfterEach {
        $env:PSModulePath = $script:SavedModulePath
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'reports <Mutation> and nothing after reverting it' -TestCases @(
        @{ Mutation = 'a fully qualified Path'; Kind = 'Qualified' }
        @{ Mutation = 'a script moved outside the module folder'; Kind = 'Moved' }
        @{ Mutation = 'a second .psd1 beside the manifest'; Kind = 'SecondManifest' }
        @{ Mutation = 'an emptied RequiredModules'; Kind = 'NoRequiredModules' }
        @{ Mutation = 'a deleted manifest'; Kind = 'NoManifest' }
    ) {
        param($Mutation, $Kind)

        $null = $Mutation
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $manifestPath = [System.IO.Path]::Combine($moduleBase, 'CaFixtureSet.psd1')
        $originalSet = [System.IO.File]::ReadAllBytes($setPath)
        $originalManifest = [System.IO.File]::ReadAllBytes($manifestPath)
        $fixturePaths = @('alpha', 'beta', 'gamma' | ForEach-Object { Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture $_ })
        $outsidePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($moduleBase, '..', 'outside_completer.ps1'))

        @(Test-CompleterSet -LiteralPath $setPath) | Should -BeNullOrEmpty

        $expected = @(
            switch ($Kind)
            {
                'Qualified'
                {
                    $qualifiedPath = Set-TestQualifiedEntryPath -ModuleBase $moduleBase -Fixture 'beta'
                    Get-TestOutsideFinding -SetPath $setPath -Index 2 -DeclaredPath $qualifiedPath
                }
                'Moved'
                {
                    Move-Item -LiteralPath $fixturePaths[0] -Destination $outsidePath
                    Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath $outsidePath, $fixturePaths[1], $fixturePaths[2]
                    Get-TestOutsideFinding -SetPath $setPath -Index 1 -DeclaredPath '../../outside_completer.ps1'
                }
                'SecondManifest'
                {
                    Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'aaa.psd1') -Value '@{ Version = 1 }' -Encoding utf8
                    Get-TestExtraManifestFinding -SetPath $setPath -ModuleBase $moduleBase -FileName 'aaa.psd1' -ManifestName 'CaFixtureSet.psd1'
                }
                'NoRequiredModules'
                {
                    $manifestText = (Get-Content -LiteralPath $manifestPath -Raw) -replace '(?m)^RequiredModules = .*$', '# RequiredModules = @()'
                    Set-Content -LiteralPath $manifestPath -Value $manifestText -Encoding utf8 -NoNewline
                    (Import-PowerShellDataFile -LiteralPath $manifestPath).Contains('RequiredModules') | Should -BeFalse
                    Get-TestRequiredModulesFinding -SetPath $setPath -ManifestPath $manifestPath
                }
                'NoManifest'
                {
                    Remove-Item -LiteralPath $manifestPath
                }
            }
        )

        $mutated = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)

        if ($expected.Count -eq 0)
        {
            $mutated | Should -BeNullOrEmpty
        }
        else
        {
            $mutated | Should -Be $expected
        }

        switch ($Kind)
        {
            'Moved'
            {
                Move-Item -LiteralPath $outsidePath -Destination $fixturePaths[0]
            }
            'SecondManifest'
            {
                Remove-Item -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'aaa.psd1')
            }
        }

        [System.IO.File]::WriteAllBytes($setPath, $originalSet)
        [System.IO.File]::WriteAllBytes($manifestPath, $originalManifest)

        @(Test-CompleterSet -LiteralPath $setPath) | Should -BeNullOrEmpty
    }

    It 'applies the set-file name rule to the module <ModuleName> through -<Source>' -TestCases @(
        @{ ModuleName = 'Completers'; Source = 'LiteralPath'; Fires = $true }
        @{ ModuleName = 'completers'; Source = 'LiteralPath'; Fires = $true }
        @{ ModuleName = 'Completers'; Source = 'Name'; Fires = $true }
        @{ ModuleName = 'CaFixtureSet'; Source = 'LiteralPath'; Fires = $false }
        @{ ModuleName = 'CaFixtureSet'; Source = 'Name'; Fires = $false }
    ) {
        param($ModuleName, $Source, $Fires)

        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name $ModuleName -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')

        if ($Source -eq 'Name')
        {
            $savedModulePath = $env:PSModulePath
            try
            {
                $env:PSModulePath = Join-TestModulePath -Root $root
                $findings = @(Test-CompleterSet -Name $ModuleName | Format-TestFinding)
            }
            finally
            {
                $env:PSModulePath = $savedModulePath
            }
        }
        else
        {
            $findings = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)
        }

        if ($Fires)
        {
            $findings | Should -Be @(Get-TestSetNameFinding -SetPath $setPath -ModuleName $ModuleName)
        }
        else
        {
            $findings | Should -BeNullOrEmpty
        }
    }

    It 'returns nothing for an installed copy tested by -Name for <Case>' -TestCases @(
        @{ Case = 'a package folder in a scratch module root'; Source = 'Scratch' }
        @{ Case = 'the copy Save-PSResource saved'; Source = 'Saved' }
    ) {
        param($Case, $Source)

        $null = $Case

        if ($Source -eq 'Saved')
        {
            if (-not (Get-Command -Name 'Compress-PSResource' -ErrorAction Ignore))
            {
                Set-ItResult -Skipped -Because 'PSResourceGet 1.1.0 or later is required'
            }

            if ($IsWindows -and $env:GITHUB_ACTIONS -ne 'true')
            {
                Set-ItResult -Skipped -Because 'the PSResourceGet store cannot be redirected on Windows'
            }

            $packageBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'source') -Name 'CaFixtureSet' -Version '1.0.0'
            $root = Save-TestCompleterSetPackage -PackageBase $packageBase -WorkFolder $script:PackageRoot
        }
        else
        {
            $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
            $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'
        }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $findings = @(Test-CompleterSet -Name 'CaFixtureSet' -ErrorVariable testErrors -ErrorAction Continue)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $findings | Should -BeNullOrEmpty
        $testErrors | Should -BeNullOrEmpty
        Test-Path -LiteralPath ([System.IO.Path]::Combine($root, 'CaFixtureSet', '1.0.0', 'completers', 'completers.psd1')) | Should -BeTrue
    }

    It 'reports one PackageLayout error for a script on another drive than the set' {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'drive letters exist on Windows only'
        }

        if ([string]::Equals([System.IO.Path]::GetPathRoot($PSScriptRoot), [System.IO.Path]::GetPathRoot([string] $TestDrive), [System.StringComparison]::OrdinalIgnoreCase))
        {
            Set-ItResult -Skipped -Because 'the repository and TestDrive share a drive'
        }

        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $repositoryScriptPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($script:PackageFixtureRoot, 'cafixalpha_completer', 'cafixalpha_completer.ps1'))
        Remove-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'alpha')
        Export-TestPackageSet -ModuleBase $moduleBase -ScriptPath $repositoryScriptPath, (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta'), (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma')

        $findings = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)

        $findings | Should -Be @(Get-TestOutsideFinding -SetPath $setPath -Index 1 -DeclaredPath $repositoryScriptPath)
    }

    It 'fails with Failed to test completer set for <Case>' -TestCases @(
        @{ Case = 'a missing module'; Kind = 'Missing'; Names = @('CaFixtureSet', 'cafixmissing') }
        @{ Case = 'a wildcard name'; Kind = 'Wildcard'; Names = @('CaFixtureSet', 'CaFixture[S]et') }
        @{ Case = 'a manifest without CompleterSet'; Kind = 'NotDeclared'; Names = @('cafixtureset') }
    ) {
        param($Case, $Kind, $Names)

        $null = $Case
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $privateData = if ($Kind -eq 'NotDeclared') { @{} } else { @{ CompleterSet = 'completers/completers.psd1' } }
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -PrivateData $privateData

        $expected = switch ($Kind)
        {
            'Missing' { "No installed module named 'cafixmissing' was found in `$env:PSModulePath. Install it with Install-PSResource cafixmissing." }
            'Wildcard' { "Test-CompleterSet -Name does not accept wildcards. Received 'CaFixture[S]et'." }
            'NotDeclared' { "The module 'CaFixtureSet' 1.0.0 at '$moduleBase' does not declare a completer set. A completer set module names its set file in PrivateData.CompleterSet." }
        }

        & (Get-Module -Name 'CompleterActions') {
            $script:TestResolveCalls = 0
            $script:TestResolveCommand = (Get-Command -Name 'Resolve-CompleterSetModule' -CommandType Function).ScriptBlock

            function script:Resolve-CompleterSetModule
            {
                param([string] $Name)

                $script:TestResolveCalls++
                & $script:TestResolveCommand -Name $Name
            }
        }

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $thrown = { Test-CompleterSet -Name $Names } | Should -Throw -PassThru
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $thrown.Exception.Message | Should -BeExactly "Failed to test completer set. $expected"
        $resolveCalls = & (Get-Module -Name 'CompleterActions') { $script:TestResolveCalls }

        if ($Kind -eq 'Wildcard')
        {
            $resolveCalls | Should -Be 0 -Because 'the wildcard check runs before any name is resolved'
        }
        else
        {
            $resolveCalls | Should -Be $Names.Count
        }
    }

    It 'treats a parent .psd1 that is not data as no manifest' {
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0' -RequiredModules @()
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $manifestPath = [System.IO.Path]::Combine($moduleBase, 'CaFixtureSet.psd1')
        $null = Set-TestQualifiedEntryPath -ModuleBase $moduleBase -Fixture 'alpha'
        @(Test-CompleterSet -LiteralPath $setPath).Construct | Should -Be @('PackageLayout', 'PackageLayout')

        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '1.0.0'; PrivateData = @{ CompleterSet = 'completers/completers.psd1' }; Stamp = (Get-Date) }" -Encoding utf8
        { Import-PowerShellDataFile -LiteralPath $manifestPath } | Should -Throw

        @(Test-CompleterSet -LiteralPath $setPath) | Should -BeNullOrEmpty
    }

    It 'treats a parent folder that cannot be listed as holding no manifest' {
        if ($IsWindows)
        {
            Set-ItResult -Skipped -Because 'denying a folder listing needs an ACL edit; the Linux legs cover the rule'
        }

        if ((& id -u) -eq '0')
        {
            Set-ItResult -Skipped -Because 'root ignores file modes'
        }

        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0' -RequiredModules @()
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $null = Set-TestQualifiedEntryPath -ModuleBase $moduleBase -Fixture 'alpha'
        @(Test-CompleterSet -LiteralPath $setPath).Construct | Should -Be @('PackageLayout', 'PackageLayout')

        try
        {
            & chmod a-r $moduleBase
            $LASTEXITCODE | Should -Be 0
            { [System.IO.Directory]::GetFiles($moduleBase) } | Should -Throw
            $findings = @(Test-CompleterSet -LiteralPath $setPath)
        }
        finally
        {
            & chmod a+r $moduleBase
        }

        $findings | Should -BeNullOrEmpty
    }

    It 'reports no finding for a manifest with a RootModule' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $moduleBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -RootModule 'CaFixtureSet.psm1'
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psm1') -Value 'function Get-CaFixture { }' -Encoding utf8
        (Import-PowerShellDataFile -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'CaFixtureSet.psd1')).RootModule | Should -Be 'CaFixtureSet.psm1'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $byName = @(Test-CompleterSet -Name 'CaFixtureSet')
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $byName | Should -BeNullOrEmpty
        @(Test-CompleterSet -LiteralPath ([System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1'))) | Should -BeNullOrEmpty
    }

    It 'accepts RequiredModules <Case>' -TestCases @(
        @{ Case = 'as a hashtable with ModuleVersion 2.2.0'; RequiredModules = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' }); Warns = $false }
        @{ Case = 'as a hashtable with RequiredVersion 2.3.0'; RequiredModules = @(@{ ModuleName = 'CompleterActions'; RequiredVersion = '2.3.0' }); Warns = $false }
        @{ Case = 'as a hashtable with ModuleVersion 2.1.0, with a warning'; RequiredModules = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.1.0' }); Warns = $true }
        @{ Case = 'as a bare string, with a warning'; RequiredModules = @('CompleterActions'); Warns = $true }
    ) {
        param($Case, $RequiredModules, $Warns)

        $null = $Case
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0' -RequiredModules $RequiredModules
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $manifestPath = [System.IO.Path]::Combine($moduleBase, 'CaFixtureSet.psd1')

        $findings = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)

        if ($Warns)
        {
            $findings | Should -Be @(Get-TestRequiredModulesFinding -SetPath $setPath -ManifestPath $manifestPath)
        }
        else
        {
            $findings | Should -BeNullOrEmpty
        }
    }

    It 'writes PackageLayout findings after the entry findings and before UnlistedScript' {
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'Completers' -Version '1.0.0' -RequiredModules @()
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        $manifestPath = [System.IO.Path]::Combine($moduleBase, 'Completers.psd1')
        $qualifiedPath = Set-TestQualifiedEntryPath -ModuleBase $moduleBase -Fixture 'alpha'
        Add-Content -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'beta') -Value '# changed after the set was written' -Encoding utf8
        Copy-Item -LiteralPath (Get-TestFixtureScriptPath -ModuleBase $moduleBase -Fixture 'gamma') -Destination ([System.IO.Path]::Combine($moduleBase, 'completers', 'cafixextra_completer.ps1'))
        Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath 'aaa.psd1') -Value '@{ Version = 1 }' -Encoding utf8

        $findings = @(Test-CompleterSet -LiteralPath $setPath)

        @($findings | ForEach-Object { '{0} {1}' -f $_.Construct, $_.Severity }) | Should -Be @(
            'HashMismatch Warning'
            'PackageLayout Error'
            'PackageLayout Error'
            'PackageLayout Error'
            'PackageLayout Warning'
            'UnlistedScript Warning'
        )
        $findings[0].Message | Should -Match '^Entry 2 '
        @($findings[1..4] | Format-TestFinding) | Should -Be @(
            (Get-TestOutsideFinding -SetPath $setPath -Index 1 -DeclaredPath $qualifiedPath)
            (Get-TestExtraManifestFinding -SetPath $setPath -ModuleBase $moduleBase -FileName 'aaa.psd1' -ManifestName 'Completers.psd1')
            (Get-TestSetNameFinding -SetPath $setPath -ModuleName 'Completers')
            (Get-TestRequiredModulesFinding -SetPath $setPath -ManifestPath $manifestPath)
        )
    }

    It 'writes one finding per extra .psd1 in ordinal order' {
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'CaFixtureSet' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')

        foreach ($extraName in 'b.psd1', 'B2.psd1', 'a.psd1', '_x.psd1')
        {
            Set-Content -LiteralPath (Join-Path -Path $moduleBase -ChildPath $extraName) -Value '@{}' -Encoding utf8
        }

        $findings = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)

        $findings | Should -Be @(
            foreach ($extraName in 'B2.psd1', '_x.psd1', 'a.psd1', 'b.psd1')
            {
                Get-TestExtraManifestFinding -SetPath $setPath -ModuleBase $moduleBase -FileName $extraName -ManifestName 'CaFixtureSet.psd1'
            }
        )
    }

    It 'uses the first declaring .psd1 in ordinal order as the manifest' {
        $moduleBase = New-TestCompleterSetPackage -Root (Join-Path -Path $script:PackageRoot -ChildPath 'staging') -Name 'Zz' -Version '1.0.0'
        $setPath = [System.IO.Path]::Combine($moduleBase, 'completers', 'completers.psd1')
        New-ModuleManifest -Path (Join-Path -Path $moduleBase -ChildPath 'aa.psd1') -ModuleVersion '1.0.0' -Author 'CompleterActions tests' -Description 'A second manifest that declares the same set.' -PrivateData @{ CompleterSet = 'completers/completers.psd1' }

        $findings = @(Test-CompleterSet -LiteralPath $setPath | Format-TestFinding)

        $findings | Should -Be @(Get-TestExtraManifestFinding -SetPath $setPath -ModuleBase $moduleBase -FileName 'aa.psd1' -ManifestName 'Zz.psd1')
    }

    It 'tests every set named by -Name in order' {
        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $setBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0' -RequiredModules @()
        $altBase = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureAlt' -Version '1.0.0' -RequiredModules @()
        $setPath = [System.IO.Path]::Combine($setBase, 'completers', 'completers.psd1')
        $altPath = [System.IO.Path]::Combine($altBase, 'completers', 'completers.psd1')

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $setFirst = @(Test-CompleterSet -Name 'CaFixtureSet', 'CaFixtureAlt' | Format-TestFinding)
            $altFirst = @(Test-CompleterSet -Name 'cafixturealt', 'cafixtureset' | Format-TestFinding)
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $setFinding = Get-TestRequiredModulesFinding -SetPath $setPath -ManifestPath ([System.IO.Path]::Combine($setBase, 'CaFixtureSet.psd1'))
        $altFinding = Get-TestRequiredModulesFinding -SetPath $altPath -ManifestPath ([System.IO.Path]::Combine($altBase, 'CaFixtureAlt.psd1'))
        $setFirst | Should -Be @($setFinding, $altFinding)
        $altFirst | Should -Be @($altFinding, $setFinding)
    }

    It 'reads the help for all three parameter sets' {
        $help = Get-Help -Name 'Test-CompleterSet' -Full -ErrorAction Stop

        @($help.Syntax.syntaxItem).Count | Should -Be 3
        @($help.Parameters.parameter).name | Should -Contain 'Name'
    }
}

Describe 'Completer authoring and packages leave PSReadLine alone' {
    BeforeAll {
        # Replaces Invoke-CompleterHelpProcess in module scope with a
        # pass-through that puts -NoProfile -NonInteractive -File in front of
        # the one probe argument, because a user profile can keep
        # 'pwsh <file>' from exiting. The probe still records the argument it
        # was given, and the AfterEach module removal drops the shim.
        function Install-TestRunnerShim
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only replaces a function in the imported test module.')]
            [CmdletBinding()]
            param(
                [Parameter()]
                [switch] $NoProfile
            )

            & (Get-Module -Name 'CompleterActions') {
                param($NoProfile)

                $script:TestRunnerNoProfile = $NoProfile
                $script:TestRunnerOriginal = ${function:Invoke-CompleterHelpProcess}

                function script:Invoke-CompleterHelpProcess
                {
                    param($FilePath, $ArgumentList, $TimeoutSeconds)

                    $arguments = @($ArgumentList)
                    if ($script:TestRunnerNoProfile)
                    {
                        $arguments = @('-NoProfile', '-NonInteractive', '-File') + $arguments
                    }

                    & $script:TestRunnerOriginal -FilePath $FilePath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds
                }
            } $NoProfile.IsPresent
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue

        foreach ($cleanupTarget in $script:PackageCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Import-Module -Name $script:ModuleManifestPath -Force | Out-Null

        $script:PackageRoot = Join-Path -Path $TestDrive -ChildPath ('neutral-{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:PackageRoot -ItemType Directory | Out-Null
    }

    AfterEach {
        foreach ($cleanupTarget in $script:PackageCleanupTargets)
        {
            Invoke-TestRuntimeCompleterCleanup @cleanupTarget
        }

        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'leaves PSReadLine key handlers unchanged across New-CompleterScript with a probe, Import-CompleterSet -Name, and Test-CompleterSet -Name' {
        Import-Module -Name 'PSReadLine' -ErrorAction SilentlyContinue

        if ($null -eq (Get-Module -Name 'PSReadLine'))
        {
            Set-ItResult -Skipped -Because 'PSReadLine is not loaded in this session'
        }

        $before = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        $fixture = Join-Path -Path $script:PackageRoot -ChildPath 'neutral-help.ps1'
        Set-Content -LiteralPath $fixture -Encoding utf8 -Value "'Commands:'", "'  build    Compile the project'", "'  test     Run the tests'"
        $scriptPath = Join-Path -Path $script:PackageRoot -ChildPath 'pwsh_completer.ps1'
        Install-TestRunnerShim -NoProfile
        $file = New-CompleterScript -CommandName 'pwsh' -Path $scriptPath -HelpArgument $fixture -PassThru -WarningVariable probeWarnings -WarningAction SilentlyContinue

        $root = Join-Path -Path $script:PackageRoot -ChildPath 'modules'
        $null = New-TestCompleterSetPackage -Root $root -Name 'CaFixtureSet' -Version '1.0.0'

        $savedModulePath = $env:PSModulePath
        try
        {
            $env:PSModulePath = Join-TestModulePath -Root $root
            $records = @(Import-CompleterSet -Name 'CaFixtureSet' -WarningVariable importWarnings -WarningAction SilentlyContinue)
            $findings = @(Test-CompleterSet -Name 'CaFixtureSet')
        }
        finally
        {
            $env:PSModulePath = $savedModulePath
        }

        $after = @(Get-PSReadLineKeyHandler -Bound -Unbound | ForEach-Object { '{0}={1}' -f $_.Key, $_.Function })

        @($probeWarnings) | Should -BeNullOrEmpty
        @(Get-Content -LiteralPath $file.FullName)[1] | Should -BeExactly "# Help-seeded native completer: the subcommand table was read from 'pwsh $fixture' when the script was generated."
        Test-CompleterScript -LiteralPath $file.FullName | Should -BeNullOrEmpty
        @($importWarnings) | Should -BeNullOrEmpty
        $records.Count | Should -Be 6
        @($records.State | Select-Object -Unique) | Should -Be @('Pending')
        $findings | Should -BeNullOrEmpty
        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }
}
