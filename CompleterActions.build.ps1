<#
InvokeBuild Build Script
Author: tstager

#>
param (
    [Parameter()]
    [String]
    $author
)


$modulename = Split-Path -Path $PSScriptRoot -Leaf
$buildpath = Join-Path -Path $PSScriptRoot -ChildPath 'build'
$modulepath = Join-Path -Path $buildpath -ChildPath $modulename
$sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath 'src'
$docPath = Join-Path -Path (Join-Path -Path $sourceRoot -ChildPath 'docs') -ChildPath $modulename
$sourceManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "$modulename.psd1"
$sourceManifestData = Import-PowerShellDataFile -Path $sourceManifestPath
$resolvedAuthor = if ([string]::IsNullOrWhiteSpace($author)) { $sourceManifestData.Author } else { $author }
$resolvedProjectUri = $sourceManifestData.PrivateData.PSData.ProjectUri
$resolvedIconUri = $sourceManifestData.PrivateData.PSData.IconUri
$resolvedCopyright = if (-not [string]::IsNullOrWhiteSpace($sourceManifestData.Copyright)) {
    $sourceManifestData.Copyright
}
else {
    "(c) $((Get-Date).Year) $resolvedAuthor. All rights reserved."
}
$coreProjectPath = Join-Path -Path $sourceRoot -ChildPath 'Core/CompleterActions.Core.csproj'
$coreAssemblyName = 'CompleterActions.Core.dll'
$libPath = Join-Path -Path $PSScriptRoot -ChildPath 'lib'
# Synopsis:

task clean {

    if (get-module -Name $modulename) {

        Remove-Module -Name $modulename -Force
    }

    if (Test-Path -Path $modulepath) {

        Remove-item -Path $modulepath -Recurse -Force

    }

}

# Synopsis: Compiles CompleterActions.Core.dll and places it in lib/, where the source manifest's RequiredAssemblies entry finds it, and in the tracked package's lib/ so the packaged module imports before a full build
task compile {

    if (-not (Get-Command -Name dotnet -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'compile: the dotnet SDK (8.0 or later) is required to build CompleterActions.Core.dll.'
    }

    $fileVersion = $sourceManifestData.ModuleVersion
    $informationalVersion = $fileVersion
    $prerelease = $sourceManifestData.PrivateData.PSData.Prerelease

    if (-not [string]::IsNullOrWhiteSpace($prerelease)) {
        $informationalVersion = "$fileVersion-$prerelease"
    }

    exec { dotnet build $coreProjectPath -c Release -nologo -v q "-p:FileVersion=$fileVersion" "-p:InformationalVersion=$informationalVersion" }

    New-Item -Path $libPath -ItemType Directory -Force | Out-Null
    $builtAssemblyPath = Join-Path -Path (Split-Path -Path $coreProjectPath -Parent) -ChildPath "bin/Release/net8.0/$coreAssemblyName"
    Copy-Item -Path $builtAssemblyPath -Destination $libPath -Force

    if (Test-Path -Path $modulepath) {
        $packageLibPath = Join-Path -Path $modulepath -ChildPath 'lib'
        New-Item -Path $packageLibPath -ItemType Directory -Force | Out-Null
        Copy-Item -Path $builtAssemblyPath -Destination $packageLibPath -Force
    }
}

task build clean, compile, external_help, {

    $sourceFolders = @(
        @('Public', 'Private') |
            ForEach-Object { Join-Path -Path $sourceRoot -ChildPath $_ } |
            Where-Object { Test-Path -Path $_ -PathType Container }
    )
    $public = Get-childitem -Path (Join-Path -Path $sourceRoot -ChildPath 'Public') -Filter *.ps1 -File
    $files = Get-ChildItem -Path $sourceFolders -Filter *.ps1 -File
    $moduleFilePath = Join-Path -Path $modulepath -ChildPath "$modulename.psm1"
    $moduleHelpPath = Join-Path -Path $modulepath -ChildPath 'en-US'
    $formatFiles = @($sourceManifestData.FormatsToProcess | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $typeFiles = @($sourceManifestData.TypesToProcess | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $usingStatements = [System.Collections.Generic.List[string]]::new()
    $sourceDotSourcingPattern = '^\s*\.\s+[''\"]?(?:\.\\|\.\/)?src[\\/].+\.ps1[''\"]?\s*$'


    if (-not(Test-Path -Path $moduleHelpPath)) {

        new-item -Path $moduleHelpPath -ItemType Directory

    }

    if (Test-Path -Path $moduleFilePath) {

        Remove-Item -Path $moduleFilePath -Force

    }

    ForEach ($file in ($files)) {

        $tokens = $null
        $parseErrors = $null
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)

        if ($parseErrors.Count -gt 0) {
            throw "build: '$($file.FullName)' does not parse at line $($parseErrors[0].Extent.StartLineNumber): $($parseErrors[0].Message)"
        }

        # The parser finds the function, so a help line that starts with the word 'function' is not taken for it.
        $functionAst = $fileAst.EndBlock.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
            Select-Object -First 1
        $functionLine = if ($null -eq $functionAst) { [int]::MaxValue } else { $functionAst.Extent.StartLineNumber }
        $helpStartLine = $functionLine

        # Only public commands are in the generated MAML, so a private function keeps its comment help.
        $isPublic = $null -ne $functionAst -and $public.FullName -contains $file.FullName

        if ($isPublic) {
            # PowerShell reads help from the comments directly before the function, never from between the name and
            # the opening brace, and those comments outrank help in the body. Every comment that leads into a public
            # function, block or line comments and any blank lines between, is therefore replaced with the directive,
            # so Get-Help selects the MAML built from the markdown.
            $leadingTokens = @($tokens | Where-Object { $_.Extent.EndOffset -le $functionAst.Extent.StartOffset })

            for ($index = $leadingTokens.Count - 1; $index -ge 0 -and $leadingTokens[$index].Kind -in 'Comment', 'NewLine'; $index--) {
                if ($leadingTokens[$index].Kind -eq 'Comment') {
                    $helpStartLine = $leadingTokens[$index].Extent.StartLineNumber
                }
            }
        }

        $fileBody = [System.Collections.Generic.List[string]]::new()
        $lineNumber = 0

        foreach ($line in Get-Content -Path $file.FullName) {
            $lineNumber++

            if ($lineNumber -ge $helpStartLine -and $lineNumber -lt $functionLine) {
                continue
            }

            if ($line -match '^\s*using\s+(namespace|module|assembly)\b') {
                if (-not $usingStatements.Contains($line)) {
                    $usingStatements.Add($line)
                }

                continue
            }

            if ($lineNumber -lt $functionLine -and $line -match $sourceDotSourcingPattern) {
                continue
            }

            if ($isPublic -and $lineNumber -eq $functionLine) {
                $fileBody.Add('<#')
                $fileBody.Add(".EXTERNALHELP $modulename-help.xml")
                $fileBody.Add('#>')
            }

            $fileBody.Add($line)
        }

        $fileBody | Out-File -FilePath $moduleFilePath -Append -Encoding utf8

    }

    Get-Content -Path (Join-Path -Path $sourceRoot -ChildPath 'Bootstrap.ps1') |
        Out-File -FilePath $moduleFilePath -Append -Encoding utf8

    if ($usingStatements.Count -gt 0) {

        @(
            $usingStatements
            ''
            (Get-Content -Path $moduleFilePath)
        ) | Set-Content -Path $moduleFilePath -Encoding utf8

    }

    Copy-Item -Path $sourceManifestPath -Destination $modulepath

    # Before Update-ModuleManifest: it rejects a manifest whose RequiredAssemblies file is missing.
    $moduleLibPath = Join-Path -Path $modulepath -ChildPath 'lib'
    New-Item -Path $moduleLibPath -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $libPath -ChildPath $coreAssemblyName) -Destination $moduleLibPath -Force

    foreach ($supportFile in @($formatFiles + $typeFiles)) {

        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath $supportFile) -Destination (Join-Path -Path $modulepath -ChildPath $supportFile) -Force
    }

    if (-not(Test-Path -Path (Join-Path -Path $buildpath -ChildPath 'en-US'))) {

        New-Item -Path $buildpath -ItemType Directory -Value "en-US" -Force
    }

    Copy-Item -Path (Join-Path -Path (Join-Path -Path $docPath -ChildPath $modulename) -ChildPath "$modulename-Help.xml") -Destination (Join-Path -Path $moduleHelpPath -ChildPath "$modulename-help.xml") -Force

    $aboutHelpSourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'en-US'
    if (Test-Path -Path $aboutHelpSourcePath) {
        Get-ChildItem -Path $aboutHelpSourcePath -Filter 'about_*.help.txt' -File |
            ForEach-Object {
                Copy-Item -Path $_.FullName -Destination (Join-Path -Path $moduleHelpPath -ChildPath $_.Name) -Force
            }
    }


    $Data = @{

        CompatiblePSEditions = @($sourceManifestData.CompatiblePSEditions)
        PowerShellVersion    = $sourceManifestData.PowerShellVersion
        Copyright            = $resolvedCopyright
        Path                 = Join-Path -Path $modulePath -ChildPath "$moduleName.psd1"
        FunctionsToExport    = $public.BaseName
        AliasesToExport      = @($sourceManifestData.AliasesToExport)
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedProjectUri)) {
        $Data['ProjectUri'] = $resolvedProjectUri
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedIconUri)) {
        $Data['IconUri'] = $resolvedIconUri
    }

    Update-ModuleManifest @Data

    # Update-ModuleManifest rewrites a RequiredAssemblies entry whose file exists with the platform's
    # path separator; restore the source manifest's portable entry so every platform builds the same text.
    $requiredAssembliesLine = 'RequiredAssemblies = @({0})' -f (@($sourceManifestData.RequiredAssemblies | ForEach-Object { "'$_'" }) -join ', ')
    (Get-Content -Path $Data.Path) -replace '^RequiredAssemblies = .*$', $requiredAssembliesLine |
        Set-Content -Path $Data.Path -Encoding utf8
}

task Markdown_templates {

    $templatePath = Join-Path -Path $sourceRoot -ChildPath 'docs'

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
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath "$modulename.psm1") -Force
    }

    # Create markdown templates for all commands in the module using the new PlatyPS 1.0 API

    $moduleInfo = Get-Module -Name $modulename
    New-MarkdownCommandHelp -ModuleInfo $moduleInfo -OutputFolder $templatePath -WithModulePage -Force
}

# Synopsis: Updates external help documentation
task external_help {

    Measure-PlatyPSMarkdown -Path (Join-Path -Path $docPath -ChildPath '*.md') |
        Where-Object Filetype -match 'CommandHelp' |
        Import-MarkdownCommandHelp -Path { $_.FilePath } |
        ForEach-Object {
            # Get-Help reads the first non-empty related-link URI on every view and stops with "The specified URI ...
            # is not valid" unless it is absolute, so a link to another command's markdown page keeps its text but no URI.
            # Only http and https links keep theirs: a path such as /docs/x.md is an absolute file URI on Linux alone.
            foreach ($link in $_.RelatedLinks) {
                $linkUri = $null

                if (-not ([uri]::TryCreate($link.Uri, [System.UriKind]::Absolute, [ref] $linkUri) -and $linkUri.Scheme -in 'http', 'https')) {
                    $link.Uri = ''
                }
            }

            $_
        } |
        Export-MamlCommandHelp -OutputFolder $docPath -Force
}

# Synopsis: Asserts that the tag on HEAD (if any) matches the source manifest ModuleVersion plus any Prerelease label
task release_check {

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        throw "release_check: git is not available, so the HEAD tag cannot be compared with ModuleVersion '$($sourceManifestData.ModuleVersion)'."
    }

    $headTag = git -C $PSScriptRoot describe --tags --exact-match 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headTag)) {
        Write-Build Yellow "release_check: HEAD is not tagged; ModuleVersion '$($sourceManifestData.ModuleVersion)' was not compared with a tag."
        return
    }

    $expectedVersion = $sourceManifestData.ModuleVersion
    $prerelease = $sourceManifestData.PrivateData.PSData.Prerelease

    if (-not [string]::IsNullOrWhiteSpace($prerelease)) {
        $expectedVersion = "$expectedVersion-$prerelease"
    }

    $expectedTag = "v$expectedVersion"

    if ($headTag -ne $expectedTag) {
        throw "release_check: HEAD tag '$headTag' does not match the source manifest version '$expectedVersion' (expected tag '$expectedTag')."
    }

    Write-Build Green "release_check: HEAD tag '$headTag' matches the source manifest version '$expectedVersion'."
}

task Publish_build {


    Publish-PSResource -ApiKey $env:GalleryAPI -Repository PSGallery -Path $modulepath

}

# Synopsis: Default task
task . build, {

}
