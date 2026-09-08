Describe 'Module Manifest Tests' {
    It 'Passes Test-ModuleManifest' {
        $moduleName = 'CompleterActions'
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $moduleManifest = Test-ModuleManifest -Path $moduleManifestPath
        Test-Path -Path $moduleManifestPath | Should -Be $true
        $moduleManifest | Should -Not -BeNullOrEmpty
        $moduleManifest.Name | Should -Be $moduleName
        $moduleManifest.RootModule | Should -Be 'CompleterActions.psm1'
        $moduleManifest.CompatiblePSEditions | Should -Be @('Core')
        $moduleManifest.PowerShellVersion | Should -Be '7.0'
        @($moduleManifest.ExportedFormatFiles | ForEach-Object { Split-Path -Path $_ -Leaf }) | Should -Be @('CompleterActions.Format.ps1xml')
    }

    It 'exports the same public functions defined in the manifest and src\Public' {
        $moduleName = 'CompleterActions'
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $manifestData = Import-PowerShellDataFile -Path $moduleManifestPath
        $expectedPublicFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\src\Public') -Filter '*.ps1' |
            Sort-Object -Property BaseName |
            Select-Object -ExpandProperty BaseName

        Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        @($manifestData.FunctionsToExport | Sort-Object) | Should -Be $expectedPublicFunctions
        @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be $expectedPublicFunctions
    }

    It 'declares the completer registration format file in the manifest' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $manifestData = Import-PowerShellDataFile -Path $moduleManifestPath

        @($manifestData.FormatsToProcess) | Should -Be @('CompleterActions.Format.ps1xml')
    }

    It 'declares a module version that satisfies the release policy' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $sourceManifestPath = Join-Path -Path $repoRoot -ChildPath 'CompleterActions.psd1'
        $builtManifestPath = Join-Path -Path $repoRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1'

        $sourceManifest = Import-PowerShellDataFile -Path $sourceManifestPath
        $builtManifest = Import-PowerShellDataFile -Path $builtManifestPath

        $sourceVersion = $null
        [version]::TryParse($sourceManifest.ModuleVersion, [ref] $sourceVersion) | Should -BeTrue
        $builtManifest.ModuleVersion | Should -Be $sourceManifest.ModuleVersion

        $gitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
        if ($null -eq $gitCommand)
        {
            Set-ItResult -Skipped -Because 'git is not available to enumerate release tags'
        }

        $tagVersions = @(
            & $gitCommand -C $repoRoot tag -l 'v*' 2>$null |
                ForEach-Object {
                    $tagVersion = $null
                    if ([version]::TryParse($_.Substring(1), [ref] $tagVersion))
                    {
                        $tagVersion
                    }
                }
        )

        if ($tagVersions.Count -eq 0)
        {
            Set-ItResult -Skipped -Because 'no v* release tags are reachable locally'
        }

        $highestTagVersion = $tagVersions | Sort-Object | Select-Object -Last 1
        $sourceVersion | Should -BeGreaterOrEqual $highestTagVersion
    }

    It 'keeps publish metadata populated in the built manifest' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $sourceManifestPath = Join-Path -Path $repoRoot -ChildPath 'CompleterActions.psd1'
        $builtManifestPath = Join-Path -Path $repoRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1'

        $sourceManifest = Import-PowerShellDataFile -Path $sourceManifestPath
        $builtManifest = Import-PowerShellDataFile -Path $builtManifestPath

        $sourceManifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
        $builtManifest.PrivateData.PSData.ProjectUri | Should -Be $sourceManifest.PrivateData.PSData.ProjectUri
        $builtManifest.Copyright | Should -Match ([regex]::Escape($sourceManifest.Author))
    }

    It 'keeps the tracked build output in sync with the module sources' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent

        if ($null -eq (Get-Module -ListAvailable -Name 'InvokeBuild'))
        {
            Set-ItResult -Skipped -Because 'InvokeBuild is not available to reproduce the packaged module'
        }

        if ($null -eq (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PlatyPS'))
        {
            Set-ItResult -Skipped -Because 'Microsoft.PowerShell.PlatyPS is not available to reproduce the packaged module'
        }

        # The build derives the module name from its folder, so stage the build inputs
        # under a folder with the module name and build there instead of in the repo.
        $stagingRoot = Join-Path -Path $TestDrive -ChildPath 'CompleterActions'
        New-Item -Path $stagingRoot -ItemType Directory | Out-Null

        foreach ($buildInput in 'CompleterActions.build.ps1', 'CompleterActions.psd1', 'CompleterActions.Format.ps1xml', 'en-US', 'src')
        {
            Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath $buildInput) -Destination $stagingRoot -Recurse
        }

        $buildScriptPath = Join-Path -Path $stagingRoot -ChildPath 'CompleterActions.build.ps1'
        $buildOutput = @(& pwsh -NoProfile -NoLogo -NonInteractive -Command "Invoke-Build -File '$buildScriptPath' build" 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($buildOutput -join [Environment]::NewLine)

        foreach ($relativePath in 'CompleterActions.psm1', 'CompleterActions.Format.ps1xml', 'en-US/about_Import_Completers.help.txt')
        {
            $trackedPath = Join-Path -Path $repoRoot -ChildPath "build/CompleterActions/$relativePath"
            $freshPath = Join-Path -Path $stagingRoot -ChildPath "build/CompleterActions/$relativePath"

            @(Get-Content -LiteralPath $trackedPath) | Should -Be @(Get-Content -LiteralPath $freshPath) -Because "build/CompleterActions/$relativePath must match a fresh build of the sources; run 'Invoke-Build build' and commit the output"
        }

        $manifestContentFilter = { $_ -notmatch '^\s*#\s*Generated on:' }
        $trackedManifestLines = @(Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1') | Where-Object -FilterScript $manifestContentFilter)
        $freshManifestLines = @(Get-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'build/CompleterActions/CompleterActions.psd1') | Where-Object -FilterScript $manifestContentFilter)

        $trackedManifestLines | Should -Be $freshManifestLines -Because "build/CompleterActions/CompleterActions.psd1 must match a fresh build of the sources; run 'Invoke-Build build' and commit the output"
    }
}

Describe 'Module state bootstrap' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'initializes module-owned state on import' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $state = & $module {
            Get-CompleterActionState
        }

        $state | Should -Not -BeNullOrEmpty
        $state.GetType().FullName | Should -Be 'System.Collections.Specialized.OrderedDictionary'
        $state['SchemaVersion'] | Should -Be 1
        $state['Registrations'].GetType().FullName | Should -Be 'System.Collections.Specialized.OrderedDictionary'
        $state['Registrations'].Count | Should -Be 0
    }

    It 'returns the existing state instead of rebuilding it during the same import' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            $firstState = Get-CompleterActionState
            $firstState['Registrations']['git:checkout'] = [ordered]@{
                Name = 'git:checkout'
            }

            $secondState = Get-CompleterActionState

            [pscustomobject]@{
                SameInstance      = [object]::ReferenceEquals($firstState, $secondState)
                RegistrationCount = $secondState['Registrations'].Count
            }
        }

        $result.SameInstance | Should -BeTrue
        $result.RegistrationCount | Should -Be 1
    }

    It 'reinitializes cleanly on a forced re-import' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        & $module {
            $state = Get-CompleterActionState
            $state['Registrations']['git:commit'] = [ordered]@{
                Name = 'git:commit'
            }
        }

        Remove-Module -Name 'CompleterActions' -Force
        $reimportedModule = Import-Module -Name $moduleManifestPath -Force -PassThru

        $stateAfterReimport = & $reimportedModule {
            Get-CompleterActionState
        }

        $stateAfterReimport['SchemaVersion'] | Should -Be 1
        $stateAfterReimport['Registrations'].Count | Should -Be 0
    }
}

Describe 'Private completer registration helpers' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
    }

    It 'resolves native and command-parameter targets into normalized contracts' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            [pscustomobject]@{
                NativeTarget = Resolve-CompleterTarget -CommandName 'Git' -Native
                ParameterTarget = Resolve-CompleterTarget -CommandName 'Git' -ParameterName 'Branch'
                ParsedParameterTarget = Resolve-CompleterTarget -RuntimeKey 'Git:Branch'
            }
        }

        $result.NativeTarget.TargetType | Should -Be 'Native'
        $result.NativeTarget.RuntimeKey | Should -Be 'Git'
        $result.NativeTarget.Key | Should -Be 'git'
        $result.NativeTarget.ParameterName | Should -BeNullOrEmpty
        $result.ParameterTarget.TargetType | Should -Be 'CommandParameter'
        $result.ParameterTarget.RuntimeKey | Should -Be 'Git:Branch'
        $result.ParameterTarget.Key | Should -Be 'git:branch'
        $result.ParsedParameterTarget.CommandName | Should -Be 'Git'
        $result.ParsedParameterTarget.ParameterName | Should -Be 'Branch'
    }

    It 'stores and finds managed registrations using normalized keys' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            $target = Resolve-CompleterTarget -CommandName 'Git' -ParameterName 'Checkout'
            $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
            }

            Add-ManagedCompleterRegistration -Registration $registration | Out-Null

            $byKey = Find-ManagedCompleterRegistration -Key 'git:checkout'
            $byParts = Find-ManagedCompleterRegistration -CommandName 'GIT' -ParameterName 'CHECKOUT'
            $allManaged = @(Find-ManagedCompleterRegistration)

            [pscustomobject]@{
                RegistrationCount = (Get-ManagedCompleterRegistrationTable).Count
                RuntimeKey = $byKey.RuntimeKey
                Source = $byKey.Source
                IsManaged = $byKey.IsManaged
                MatchingKey = $byParts.Key
                EnumeratedCount = $allManaged.Count
            }
        }

        $result.RegistrationCount | Should -Be 1
        $result.RuntimeKey | Should -Be 'Git:Checkout'
        $result.Source | Should -Be 'Managed'
        $result.IsManaged | Should -BeTrue
        $result.MatchingKey | Should -Be 'git:checkout'
        $result.EnumeratedCount | Should -Be 1
    }

    It 'removes managed registrations and returns the removed record' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            $target = Resolve-CompleterTarget -CommandName 'Git' -Native
            $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock {
                param($wordToComplete, $commandAst, $cursorPosition)

                $null = $wordToComplete, $commandAst, $cursorPosition
            }

            Add-ManagedCompleterRegistration -Registration $registration | Out-Null
            $removed = Remove-ManagedCompleterRegistration -CommandName 'git' -Native
            $afterRemoval = Find-ManagedCompleterRegistration -CommandName 'git' -Native

            [pscustomobject]@{
                RemovedKey = $removed.Key
                RemovedSource = $removed.Source
                WasRemoved = $null -eq $afterRemoval
                RemainingCount = (Get-ManagedCompleterRegistrationTable).Count
            }
        }

        $result.RemovedKey | Should -Be 'git'
        $result.RemovedSource | Should -Be 'Managed'
        $result.WasRemoved | Should -BeTrue
        $result.RemainingCount | Should -Be 0
    }

    It 'discovers runtime completers from PowerShell internals and removes them on demand' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            $nativeScriptBlock = {
                param($wordToComplete, $commandAst, $cursorPosition)

                $null = $wordToComplete, $commandAst, $cursorPosition
                [System.Management.Automation.CompletionResult]::new('native', 'native', 'ParameterValue', 'native')
            }

            $parameterScriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
                [System.Management.Automation.CompletionResult]::new('parameter', 'parameter', 'ParameterValue', 'parameter')
            }

            Register-ArgumentCompleter -Native -CommandName 'CompleterActionsNativeRuntimeTest' -ScriptBlock $nativeScriptBlock
            Register-ArgumentCompleter -CommandName 'CompleterActionsParameterRuntimeTest' -ParameterName 'Name' -ScriptBlock $parameterScriptBlock

            try
            {
                $allRuntime = @(Find-RuntimeCompleterRegistration)
                $native = Find-RuntimeCompleterRegistration -CommandName 'CompleterActionsNativeRuntimeTest' -Native
                $parameter = Find-RuntimeCompleterRegistration -CommandName 'CompleterActionsParameterRuntimeTest' -ParameterName 'Name'
                $removed = Remove-RuntimeCompleterRegistration -CommandName 'CompleterActionsNativeRuntimeTest' -Native
                $afterRemoval = Find-RuntimeCompleterRegistration -CommandName 'CompleterActionsNativeRuntimeTest' -Native

                [pscustomobject]@{
                    NativeFound = $null -ne $native
                    NativeSource = $native.Source
                    ParameterFound = $null -ne $parameter
                    ParameterSource = $parameter.Source
                    EnumeratedNative = $allRuntime.Key -contains 'completeractionsnativeruntimetest'
                    EnumeratedParameter = $allRuntime.Key -contains 'completeractionsparameterruntimetest:name'
                    RemovedKey = $removed.Key
                    WasRemoved = $null -eq $afterRemoval
                }
            }
            finally
            {
                $runtime = Get-CompleterRuntime
                $runtime.NativeArgumentCompleters.Remove('CompleterActionsNativeRuntimeTest') | Out-Null
                $runtime.CustomArgumentCompleters.Remove('CompleterActionsParameterRuntimeTest:Name') | Out-Null
            }
        }

        $result.NativeFound | Should -BeTrue
        $result.NativeSource | Should -Be 'Discovered'
        $result.ParameterFound | Should -BeTrue
        $result.ParameterSource | Should -Be 'Discovered'
        $result.EnumeratedNative | Should -BeTrue
        $result.EnumeratedParameter | Should -BeTrue
        $result.RemovedKey | Should -Be 'completeractionsnativeruntimetest'
        $result.WasRemoved | Should -BeTrue
    }

    It 'supports IDictionary-based runtime completer dictionary helpers' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        $result = & $module {
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $scriptBlock = {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $null = $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters
            }

            Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key 'Git:Checkout' -Value $scriptBlock

            $containsAfterSet = Test-CompleterRuntimeDictionaryKey -Dictionary $dictionary -Key 'Git:Checkout'
            $stored = Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key 'Git:Checkout'
            $removed = Remove-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key 'Git:Checkout'
            $containsAfterRemove = Test-CompleterRuntimeDictionaryKey -Dictionary $dictionary -Key 'Git:Checkout'

            [pscustomobject]@{
                ContainsAfterSet    = $containsAfterSet
                StoredScriptText    = $stored.ToString()
                RemovedScriptText   = $removed.ToString()
                ContainsAfterRemove = $containsAfterRemove
                RemainingCount      = $dictionary.Count
            }
        }

        $result.ContainsAfterSet | Should -BeTrue
        $result.StoredScriptText | Should -Match 'param'
        $result.RemovedScriptText | Should -Match 'param'
        $result.ContainsAfterRemove | Should -BeFalse
        $result.RemainingCount | Should -Be 0
    }

    It 'throws a clear error when runtime execution context internals are unavailable' {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\CompleterActions.psd1'
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru

        {
            & $module {
                Resolve-CompleterRuntimeExecutionContext -EngineIntrinsicsType ([pscustomobject]) -EngineIntrinsics ([pscustomobject]@{})
            }
        } | Should -Throw 'Unable to access the PowerShell execution context field required for completer runtime discovery.'
    }
}
