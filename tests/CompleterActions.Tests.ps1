Describe 'Module Manifest Tests' {
    It 'Passes Test-ModuleManifest' {
        $moduleName = 'CompleterActions'
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "..\$moduleName.psd1"
        $moduleManifest = Test-ModuleManifest -Path $moduleManifestPath
        Test-Path -Path $moduleManifestPath | Should -Be $true
        $moduleManifest | Should -Not -BeNullOrEmpty
        $moduleManifest.Name | Should -Be $moduleName
        $moduleManifest.Version.ToString() | Should -Be '1.0.0'
        $moduleManifest.RootModule | Should -Be 'CompleterActions.psm1'
    }
}

