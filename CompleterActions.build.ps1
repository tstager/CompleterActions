<#
InvokeBuild Build Script
Author: tstager

#>
param (
    [Parameter()]
    [String]
    $author,
    [string[]]
    [ValidateSet("Desktop", "Core")]
    $pseditions = @("Desktop", "Core")
)


$modulename = $PSScriptRoot.Split("\")[-1]
$buildpath = "$PSScriptRoot\build"
$modulepath = "$buildpath\$modulename"
$docPath = "$PSScriptRoot\src\docs\$modulename"
# Synopsis:

task clean {

    if (get-module -Name $modulename) {

        Remove-Module -Name $modulename -Force
    }

    if (Test-Path -Path "$buildpath\$modulename") {

        Remove-item -Path $modulepath -Recurse -Force

    }

}
task build clean, external_help, {

    $public = Get-childitem -Path "$PSScriptRoot\src\Public" -Filter *.ps1 -File
    $files = Get-ChildItem -Path "$PSScriptRoot\src\Public", "$PSScriptRoot\src\Private", "$PSScriptRoot\src\Classes" -Filter *.ps1 -File
    $moduleFilePath = "$modulepath\$modulename.psm1"
    $usingStatements = [System.Collections.Generic.List[string]]::new()
    $sourceDotSourcingPattern = '^\s*\.\s+[''\"]?(?:\.\\|\.\/)?src[\\/].+\.ps1[''\"]?\s*$'


    if (-not(Test-Path -Path "$modulepath\en-US")) {

        new-item -Path "$modulepath\en-US" -ItemType Directory

    }

    if (Test-Path -Path $moduleFilePath) {

        Remove-Item -Path $moduleFilePath -Force

    }

    ForEach ($file in ($files)) {

        $fileAndHelp = Get-Content -Path $file.FullName
        $fileBody = [System.Collections.Generic.List[string]]::new()
        $encounteredFunction = $false

        foreach ($line in $fileAndHelp) {
            if ($line -match '^\s*using\s+(namespace|module|assembly)\b') {
                if (-not $usingStatements.Contains($line)) {
                    $usingStatements.Add($line)
                }

                continue
            }

            if (-not $encounteredFunction -and $line -match '^\s*function\b') {
                $encounteredFunction = $true
            }

            if (-not $encounteredFunction -and $line -match $sourceDotSourcingPattern) {
                continue
            }

            $fileBody.Add($line)
        }

        $functionLine = ($fileBody | Select-String -Pattern '^\s*function\b' | Select-Object -First 1).LineNumber

        if ($null -eq $functionLine) {
            $fileBody | Out-File -FilePath $moduleFilePath -Append -Encoding utf8
            continue
        }

        $functionIndex = $functionLine - 1
        $fileContentWithExternalHelp = @(
            $fileBody[0..$functionIndex]
            '<#'
            ".EXTERNALHELP $modulename-help.xml"
            '#>'
        )

        if ($functionIndex -lt ($fileBody.Count - 1)) {
            $fileContentWithExternalHelp += $fileBody[($functionIndex + 1)..($fileBody.Count - 1)]
        }

        $fileContentWithExternalHelp | Out-File -FilePath $moduleFilePath -Append -Encoding utf8

    }

    if ($usingStatements.Count -gt 0) {

        @(
            $usingStatements
            ''
            (Get-Content -Path $moduleFilePath)
        ) | Set-Content -Path $moduleFilePath -Encoding utf8

    }

    Copy-Item -Path "$PSScriptRoot\$modulename.psd1" -Destination $modulepath

    if(-not(Test-Path -Path $buildpath\"en-US")) {

        New-Item -Path $buildpath -ItemType Directory -Value "en-US" -Force
    }

    Copy-Item -Path "$docPath\$modulename\$modulename-help.xml" -Destination "$modulepath\en-US\$modulename-help.xml" -Force


    $Data = @{

        CompatiblePSEditions = $pseditions
        PowerShellVersion    = 5.1
        Copyright            = "(c) $((get-date).Year) $author. All rights reserved."
        Path                 = "$modulePath\$moduleName.psd1"
        FunctionsToExport    = $public.BaseName
        ProjectUri           = ""
    }
    Update-ModuleManifest @Data
}

task Markdown_templates {

    $templatePath = "$PSScriptRoot\src\Docs"

    # Ensure the template directory exists
    if (-not (Test-Path -Path $templatePath)) {
        New-Item -Path $templatePath -ItemType Directory -Force | Out-Null
    }

    # Import Microsoft.PowerShell.Platyps module (new version)
    if (-not (Get-Module -Name Microsoft.PowerShell.Platyps -ErrorAction SilentlyContinue)) {
        Import-Module -Name Microsoft.PowerShell.Platyps -Force
    }

    # Import the module if not already loaded
    if (-not (Get-Module -Name $modulename -ErrorAction SilentlyContinue)) {
        Import-Module -Name "$PSScriptRoot\$modulename.psm1" -Force
    }

    # Create markdown templates for all commands in the module using the new PlatyPS 1.0 API

    $moduleInfo = Get-Module -Name $modulename
    New-MarkdownCommandHelp -ModuleInfo $moduleInfo -OutputFolder $templatePath -WithModulePage -Force
}

# Synopsis: Updates external help documentation
task external_help {


    Measure-PlatyPSMarkdown -Path "$docPath\*.md" |
    Where-Object Filetype -match 'CommandHelp' |
    Import-MarkdownCommandHelp -Path {$_.FilePath} |
    Export-MamlCommandHelp -OutputFolder $docPath -Force
}

# Synopsis: Default task
task . build, {

}