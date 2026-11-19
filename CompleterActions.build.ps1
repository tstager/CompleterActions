<#
InvokeBuild Build Script
Author: tstager

#>
param (
    [Parameter()]
    [String]
    $author,

    [Parameter()]
    [String]
    $Repository = 'PSGallery'
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
. (Join-Path -Path $sourceRoot -ChildPath 'Private/ConvertTo-CompleterSingleQuotedText.ps1')
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
    # Every file that goes into the packaged psm1 is read the same way, so the duplicate check below sees each definition
    # the package makes. Bootstrap.ps1 runs the import-time work, so it goes last, after the functions it calls.
    $files = @(Get-ChildItem -Path $sourceFolders -Filter *.ps1 -File) + (Get-Item -LiteralPath (Join-Path -Path $sourceRoot -ChildPath 'Bootstrap.ps1'))
    $moduleFilePath = Join-Path -Path $modulepath -ChildPath "$modulename.psm1"
    $moduleHelpPath = Join-Path -Path $modulepath -ChildPath 'en-US'
    $formatFiles = @($sourceManifestData.FormatsToProcess | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $typeFiles = @($sourceManifestData.TypesToProcess | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $usingStatements = [System.Collections.Generic.List[string]]::new()
    $definitions = @{}
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

        # The parser finds the functions, so a help line that starts with the word 'function' is not taken for one.
        $functionAsts = @($fileAst.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })

        # A scope modifier does not change the command a definition makes: function script:Get-Completer replaces
        # Get-Completer. A write through the Function: drive replaces it too, and may run only under a condition the
        # import check below does not meet, so a literal Function: path or a ${function:} variable that names a
        # command counts as a definition of it wherever it appears.
        $definitionAsts = $fileAst.FindAll({
                param($ast)
                $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                $ast -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $ast -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true)

        foreach ($definition in $definitionAsts) {
            $name = if ($definition -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $definition.Name
            }
            elseif ($definition -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $definition.Value -match '^function:[\\/]?(.+)$') {
                $Matches[1]
            }
            elseif ($definition -is [System.Management.Automation.Language.VariableExpressionAst] -and $definition.VariablePath.DriveName -eq 'function') {
                $definition.VariablePath.UserPath -replace '^function:', ''
            }

            if ($name) {
                $definitions[($name -replace '^(?:global|local|private|script):', '')] += @("$($file.FullName):$($definition.Extent.StartLineNumber)")
            }
        }

        $firstFunctionLine = if ($functionAsts.Count -eq 0) { [int]::MaxValue } else { $functionAsts[0].Extent.StartLineNumber }
        $commandLine = 0
        $helpLine = 0

        # Only public commands are in the generated MAML, so a private function, a helper in a public file included,
        # keeps its comment help.
        if ($public.FullName -contains $file.FullName) {
            $commandAst = $functionAsts | Where-Object Name -eq $file.BaseName | Select-Object -First 1

            if ($null -eq $commandAst) {
                throw "build: '$($file.FullName)' does not define the function '$($file.BaseName)' at its top level, so the exported command would be missing."
            }

            $commandLine = $commandAst.Extent.StartLineNumber
            $commandIndex = 0

            while ($tokens[$commandIndex].Extent.StartOffset -lt $commandAst.Extent.StartOffset) {
                $commandIndex++
            }

            # PowerShell reads help from the comment block directly before the function, never from between the name
            # and the opening brace, and that block outranks help in the body. The help that leads into the command is
            # therefore replaced with the directive, so Get-Help selects the MAML built from the markdown. The block is
            # the one PowerShell reads: comments ending at most one blank line above the declaration, with no blank
            # line between them. The help starts at its earliest comment that begins its own line; a comment after
            # code on its line, a #requires line and everything before them stay in the package.
            $helpStart = $commandAst.Extent
            $minEndLine = $commandAst.Extent.StartLineNumber - 2

            for ($index = $commandIndex - 1; $index -ge 0; $index--) {
                $token = $tokens[$index]

                if ($token.Extent.EndLineNumber -lt $minEndLine -or $token.Kind -notin 'Comment', 'NewLine' -or $token.Text -match '^#requires\b') {
                    break
                }

                if ($token.Kind -eq 'Comment') {
                    $minEndLine = $token.Extent.StartLineNumber - 1

                    if ($index -eq 0 -or $tokens[$index - 1].Kind -eq 'NewLine') {
                        $helpStart = $token.Extent
                    }
                }
            }

            $helpLine = $helpStart.StartLineNumber
        }

        $fileBody = [System.Collections.Generic.List[string]]::new()
        $lineNumber = 0

        foreach ($line in Get-Content -Path $file.FullName) {
            $lineNumber++

            if ($lineNumber -ge $helpLine -and $lineNumber -lt $commandLine) {
                continue
            }

            if ($lineNumber -eq $commandLine) {
                # The help can end on the declaration's line, so only the declaration is kept from it. Code before a
                # declaration that has no help stays, on its own line. The blank line keeps a comment left above out of
                # the directive's block: PowerShell reads no help from a block that starts with another comment.
                $lead = if ($helpLine -eq $commandLine) { $line.Substring(0, $helpStart.StartColumnNumber - 1) } else { '' }

                if (-not [string]::IsNullOrWhiteSpace($lead)) {
                    $fileBody.Add($lead)
                }

                $fileBody.Add('')
                $fileBody.Add('<#')
                $fileBody.Add(".EXTERNALHELP $modulename-help.xml")
                $fileBody.Add('#>')
                $fileBody.Add($line.Substring($commandAst.Extent.StartColumnNumber - 1))
                continue
            }

            if ($line -match '^\s*using\s+(namespace|module|assembly)\b') {
                if (-not $usingStatements.Contains($line)) {
                    $usingStatements.Add($line)
                }

                continue
            }

            if ($lineNumber -lt $firstFunctionLine -and $line -match $sourceDotSourcingPattern) {
                continue
            }

            $fileBody.Add($line)
        }

        $fileBody | Out-File -FilePath $moduleFilePath -Append -Encoding utf8

    }

    # Only the command's own definition carries the directive, so another definition of its name, which would replace
    # it or define it a second time, would ship the command without the MAML.
    $duplicates = @($public.BaseName | Where-Object { $definitions[$_].Count -gt 1 } | ForEach-Object { "'$_' at $($definitions[$_] -join ', ')" })

    if ($duplicates.Count -gt 0) {
        throw "build: a public command must be defined once, in its own file, and never named on the Function: drive, so the definition that is exported reads its help from the MAML: $($duplicates -join '; ')."
    }

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
    $requiredAssembliesLine = 'RequiredAssemblies = @({0})' -f (@($sourceManifestData.RequiredAssemblies | ForEach-Object { "'$(ConvertTo-CompleterSingleQuotedText -Value $_)'" }) -join ', ')
    (Get-Content -Path $Data.Path) -replace '^RequiredAssemblies = .*$', $requiredAssembliesLine |
        Set-Content -Path $Data.Path -Encoding utf8

    # The duplicate check reads the names in the sources, so a command replaced from text made at run time while the
    # module loads, a Function: path built from a variable for example, is found only by importing the package. A new
    # pwsh imports it, so this process does not hold the assembly in lib/ for the next compile.
    $pwshPath = Join-Path -Path $PSHOME -ChildPath ($IsWindows ? 'pwsh.exe' : 'pwsh')
    $withoutMaml = @(
        exec {
            & $pwshPath -NoProfile -NonInteractive -Command {
                param($ManifestPath, $CommandNames, $HelpFileName)

                $ErrorActionPreference = 'Stop'
                # Host text the package writes while it loads comes back to the build as output, which would read as
                # a finding, so the import discards the information stream.
                $module = Import-Module -Name $ManifestPath -PassThru 6>$null

                foreach ($name in $CommandNames) {
                    $command = $module.ExportedFunctions[$name]

                    if ($null -eq $command) {
                        "'$name' is not exported"
                    }
                    elseif ($command.ScriptBlock.Ast.GetHelpContent().MamlHelpFile -ne $HelpFileName) {
                        "'$name' is defined at $($command.ScriptBlock.File):$($command.ScriptBlock.StartPosition.StartLine)"
                    }
                }
            } -args $Data.Path, @($public.BaseName), "$modulename-help.xml"
        }
    )

    if ($withoutMaml.Count -gt 0) {
        throw "build: each exported command must be the definition that reads its help from the MAML, but in the imported package $($withoutMaml -join '; ')."
    }
}

# Synopsis: Regenerates every markdown help page under src/docs from the source module, overwriting hand edits
task Markdown_templates compile, {

    $templatePath = Join-Path -Path $sourceRoot -ChildPath 'docs'

    # Ensure the template directory exists
    if (-not (Test-Path -Path $templatePath)) {
        New-Item -Path $templatePath -ItemType Directory -Force | Out-Null
    }

    # An assembly cannot be unloaded, so the source manifest is imported in a new pwsh: its RequiredAssemblies
    # entry then loads the core compile just built rather than one this process already holds, and lib/ stays
    # unlocked here for the next compile.
    $pwshPath = Join-Path -Path $PSHOME -ChildPath ($IsWindows ? 'pwsh.exe' : 'pwsh')
    exec {
        & $pwshPath -NoProfile -NonInteractive -Command {
            param($ManifestPath, $OutputFolder)

            $ErrorActionPreference = 'Stop'
            Import-Module -Name Microsoft.PowerShell.PlatyPS
            $moduleInfo = Import-Module -Name $ManifestPath -PassThru
            New-MarkdownCommandHelp -ModuleInfo $moduleInfo -OutputFolder $OutputFolder -WithModulePage -Force
        } -args $sourceManifestPath, $templatePath
    }
}

# Synopsis: Updates external help documentation
task external_help {

    $commandHelp = @(
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
            }
    )
    $mamlFile = $commandHelp | Export-MamlCommandHelp -OutputFolder $docPath -Force

    # PlatyPS writes every parameter of a syntax entry as taking no pipeline input, so each one is given the pipeline
    # input the markdown declares for it in that entry's parameter set. The entries follow the markdown's syntax order.
    $maml = [System.Xml.XmlDocument]::new()
    $maml.PreserveWhitespace = $true
    $maml.Load($mamlFile.FullName)
    $namespaces = [System.Xml.XmlNamespaceManager]::new($maml.NameTable)
    $namespaces.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
    $namespaces.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')

    foreach ($help in $commandHelp) {
        $syntaxItems = $maml.SelectNodes("//command:command[command:details/command:name = '$($help.Title)']/command:syntax/command:syntaxItem", $namespaces)

        if ($syntaxItems.Count -ne $help.Syntax.Count) {
            throw "build: the MAML has $($syntaxItems.Count) syntax entries for $($help.Title), whose markdown has $($help.Syntax.Count)."
        }

        for ($index = 0; $index -lt $syntaxItems.Count; $index++) {
            $setName = $help.Syntax[$index].ParameterSetName

            foreach ($syntaxParameter in $syntaxItems[$index].SelectNodes('command:parameter', $namespaces)) {
                $name = $syntaxParameter.SelectSingleNode('maml:name', $namespaces).InnerText
                $set = @($help.Parameters | Where-Object Name -ceq $name | ForEach-Object ParameterSets | Where-Object Name -in $setName, '(All)')

                if ($set.Count -ne 1) {
                    throw "build: the markdown help of $($help.Title) lists -$name in the syntax of the set $setName but under PARAMETERS in $($set.Count) entries for that set."
                }

                $pipelineInput = @(if ($set[0].ValueFromPipeline) { 'ByValue' }; if ($set[0].ValueFromPipelineByPropertyName) { 'ByPropertyName' })
                $syntaxParameter.SetAttribute('pipelineInput', ($pipelineInput.Count -gt 0 ? "true ($($pipelineInput -join ', '))" : 'false'))
            }
        }
    }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.Xml.XmlWriter]::Create($stream, $settings)

    try {
        $maml.Save($writer)
    }
    finally {
        $writer.Dispose()
    }

    # PlatyPS writes the U+0080 that marks a blank line in an example as a character reference, and XmlWriter writes it
    # as the character, so it goes back to the reference PlatyPS wrote.
    $mamlText = $settings.Encoding.GetString($stream.ToArray()).Replace([string] [char] 0x80, '&#x80;')
    [System.IO.File]::WriteAllText($mamlFile.FullName, $mamlText, $settings.Encoding)
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

# Synopsis: Publishes the built package to -Repository (PSGallery by default), or publishes nothing when the repository already holds that exact version with the same files, so a rerun of a partly finished release continues
task Publish_build {

    $packageManifestData = Import-PowerShellDataFile -Path (Join-Path -Path $modulepath -ChildPath "$modulename.psd1")
    $version = $packageManifestData.ModuleVersion
    $prerelease = $packageManifestData.PrivateData.PSData.Prerelease

    if (-not [string]::IsNullOrWhiteSpace($prerelease)) {
        $version = "$version-$prerelease"
    }

    $published = try {
        Find-PSResource -Name $modulename -Version $version -Prerelease -Repository $Repository -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'PackageNotFound,*') {
            throw
        }
    }

    if ($null -eq $published) {
        Publish-PSResource -ApiKey $env:GalleryAPI -Repository $Repository -Path $modulepath
        return
    }

    # A published version cannot be replaced, so a rerun continues only when the repository holds what this build made.
    # Update-ModuleManifest dates the manifest, so its Generated on line is the one line a later rebuild changes.
    $getDigest = {
        param($Root)

        foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse) {
            $relativePath = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            $hash = if ($relativePath -eq "$modulename.psd1") {
                $text = @(Get-Content -LiteralPath $file.FullName) -notmatch '^# Generated on: ' -join "`n"
                [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text)))
            }
            else {
                (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            }

            "$hash $relativePath"
        }
    }

    $savedRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$modulename-published-$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $savedRoot -ItemType Directory | Out-Null

    try {
        Save-PSResource -Name $modulename -Version $version -Prerelease -Repository $Repository -Path $savedRoot -SkipDependencyCheck -TrustRepository
        $publishedPath = Join-Path -Path (Join-Path -Path $savedRoot -ChildPath $modulename) -ChildPath $packageManifestData.ModuleVersion
        $differences = @(
            Compare-Object -ReferenceObject @(& $getDigest $modulepath) -DifferenceObject @(& $getDigest $publishedPath) -CaseSensitive |
                ForEach-Object { ($_.InputObject -split ' ', 2)[1] } |
                Sort-Object -Unique
        )
    }
    finally {
        Remove-Item -LiteralPath $savedRoot -Recurse -Force
    }

    if ($differences.Count -gt 0) {
        throw "Publish_build: $Repository already holds $modulename $version, and that copy differs from '$modulepath' in $($differences -join ', '). A published version cannot be replaced, so publish this build under a new version."
    }

    Write-Build Green "Publish_build: $Repository already holds $modulename $version with the same files as '$modulepath', so nothing was published."
}

# Synopsis: Default task
task . build, {

}
