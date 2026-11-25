
<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Export-CompleterSet
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        # The output path follows the two rules of a script path in the records.
        # The engine hands the part after a provider qualifier to the provider
        # unchanged, so a relative one would be written under the PowerShell
        # location while every entry Path is computed against the process working
        # directory.
        $provider = $null
        $outputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref] $provider, [ref] $null)

        if ($provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
        {
            throw "The output path '$Path' resolves to '$outputPath' on the $($provider.Name) provider, not to a file system path."
        }

        if ($PSCmdlet.SessionState.Path.IsProviderQualified($Path) -and
            -not [System.IO.Path]::IsPathFullyQualified($Path.Substring($Path.IndexOf('::') + 2)))
        {
            throw "The output path '$Path' is provider-qualified but not fully qualified, so PowerShell would resolve it against the process working directory rather than the PowerShell location. Drop the provider qualifier or give a fully qualified path."
        }

        if ([System.IO.Path]::GetExtension($outputPath) -ne '.psd1')
        {
            throw "Completer sets must be .psd1 files. Received '$outputPath'."
        }

        $outputDirectory = Split-Path -Path $outputPath -Parent

        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
        {
            throw "The directory '$outputDirectory' does not exist."
        }

        $records = [System.Collections.Generic.List[psobject]]::new()

        # A pipeline or -InputObject chooses the records to export even when it
        # delivers none, and ExpectingInput is already true here for a pipeline
        # that never sends a record. Only a call with neither falls back to every
        # managed registration.
        $inputRequested = $PSCmdlet.MyInvocation.ExpectingInput -or $PSBoundParameters.ContainsKey('InputObject')
    }

    process
    {
        # A null carries no record, so a Get-Completer filter that matches nothing
        # selects nothing whether it is piped or passed to -InputObject.
        foreach ($item in $InputObject)
        {
            if ($null -ne $item)
            {
                $records.Add($item)
            }
        }
    }

    end
    {
        try
        {
            if (-not $inputRequested)
            {
                $records.AddRange([psobject[]] @(Get-Completer -State Active, Pending, Failed, Stale | Where-Object { $_.PSObject.Properties['ScriptPath'] -and -not [string]::IsNullOrWhiteSpace([string] $_.ScriptPath) }))
            }
            elseif ($records.Count -eq 0)
            {
                Write-Warning -Message "No registrations were selected for export, so nothing was written to '$outputPath'."
                return
            }

            # Group by script path the way the file system compares paths, so two
            # scripts whose names differ only by case stay two entries on Linux.
            $pathComparer = if ($IsWindows -or $IsMacOS) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
            $entriesByPath = [System.Collections.Specialized.OrderedDictionary]::new($pathComparer)

            foreach ($record in $records)
            {
                $scriptPath = $null

                foreach ($propertyName in 'ScriptPath', 'SourcePath')
                {
                    $property = $record.PSObject.Properties[$propertyName]

                    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                    {
                        $declaredPath = [string] $property.Value

                        if ([System.IO.Path]::IsPathFullyQualified($declaredPath))
                        {
                            $scriptPath = [System.IO.Path]::GetFullPath($declaredPath)
                            break
                        }

                        # Any other path is relative to the caller's PowerShell
                        # location, which Push-Location moves without changing the
                        # process working directory that GetFullPath would use.
                        $provider = $null
                        $scriptPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($declaredPath, [ref] $provider, [ref] $null)

                        if ($provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
                        {
                            throw "The script path '$declaredPath' resolves to '$scriptPath' on the $($provider.Name) provider, not to a file system path."
                        }

                        # The engine hands the part after a provider qualifier to the
                        # provider unchanged, so a relative one resolves against the
                        # process working directory instead of the PowerShell location.
                        if ($PSCmdlet.SessionState.Path.IsProviderQualified($declaredPath) -and
                            -not [System.IO.Path]::IsPathFullyQualified($declaredPath.Substring($declaredPath.IndexOf('::') + 2)))
                        {
                            throw "The script path '$declaredPath' is provider-qualified but not fully qualified, so PowerShell would resolve it against the process working directory rather than the PowerShell location. Drop the provider qualifier or give a fully qualified path."
                        }

                        break
                    }
                }

                if ($null -eq $scriptPath)
                {
                    throw 'InputObject must expose the script it came from through a ScriptPath or SourcePath property; registrations created from an in-memory script block cannot be exported to a set.'
                }

                $resolvedInput = $record | Resolve-CompleterInputObject
                $target = $resolvedInput.Target
                $trusted = $resolvedInput.Trusted

                if (-not $entriesByPath.Contains($scriptPath))
                {
                    $entriesByPath[$scriptPath] = [pscustomobject] [ordered] @{
                        Path    = $scriptPath
                        Trusted = $trusted
                        Hash    = $null
                        Targets = [ordered] @{}
                    }
                }

                $entry = $entriesByPath[$scriptPath]

                if ($entry.Trusted -ne $trusted)
                {
                    throw "The records for '$scriptPath' disagree on Trusted, so the entry's trust tier cannot be written."
                }

                $entry.Targets[(Get-CompleterTargetIdentity -Target $target)] = $target
            }

            if ($entriesByPath.Count -eq 0)
            {
                throw 'No registrations with a script path were found to export.'
            }

            # Import-CompleterSet holds a strict entry's Targets to the script's full
            # derived target list, so a strict group that covers only some of those
            # targets would write a set that cannot be imported. Check it here,
            # before anything is written, with the same derivation the import uses.
            foreach ($entry in $entriesByPath.Values)
            {
                if ($entry.Trusted)
                {
                    continue
                }

                # One read serves both the target check and the Hash, so an edit
                # between two reads cannot give a Hash that does not describe the
                # checked targets.
                $parseResult = Get-CompleterScriptParseResult -LiteralPath $entry.Path
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $entry.Path -ParseResult $parseResult)
                $derivedTargetsByIdentity = [ordered] @{}

                foreach ($derivedTarget in $derivedTargets)
                {
                    $derivedTargetsByIdentity[(Get-CompleterTargetIdentity -Target $derivedTarget)] = $derivedTarget
                }

                $missingTargets = @($derivedTargetsByIdentity.Keys | Where-Object { -not $entry.Targets.Contains($_) } | ForEach-Object { $derivedTargetsByIdentity[$_] })
                $unknownTargets = @($entry.Targets.Keys | Where-Object { -not $derivedTargetsByIdentity.Contains($_) })

                if ($missingTargets.Count -eq 0 -and $unknownTargets.Count -eq 0)
                {
                    # The targets match, so only order and casing can differ. Writing
                    # the derived targets puts them in script order and script casing,
                    # which is what the import fast path reproduces.
                    $entry.Targets = $derivedTargetsByIdentity
                    $entry.Hash = Get-CompleterScriptHash -Text $parseResult.Ast.Extent.Text
                    continue
                }

                $problem = "The strict entry for '$($entry.Path)' cannot be imported as a set entry because its targets do not match the script."

                if ($missingTargets.Count -gt 0)
                {
                    $problem += " Missing: $(@($missingTargets | ForEach-Object { "'$($_.Key)'" }) -join ', ')."
                }

                if ($unknownTargets.Count -gt 0)
                {
                    $problem += " Not registered by the script: $(@($unknownTargets | ForEach-Object { "'$($entry.Targets[$_].RuntimeKey)'" }) -join ', ')."
                }

                throw "$problem Export the registrations for every target the script registers, or register the script with -Trusted, whose entries take their targets as given. Nothing was written."
            }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('@{')
            $lines.Add('    Version = 1')
            $lines.Add('    Entries = @(')

            foreach ($entry in $entriesByPath.Values)
            {
                # A trusted script is never parsed here, and 2.0.0 exported a trusted
                # entry whose file is missing, so an unreadable trusted script is
                # written without a Hash rather than failing the export.
                if ($entry.Trusted)
                {
                    try
                    {
                        $entry.Hash = Get-CompleterScriptHash -LiteralPath $entry.Path
                    }
                    catch
                    {
                        Write-Warning -Message "The script '$($entry.Path)' could not be read, so its entry was written without a Hash. $($_.Exception.GetBaseException().Message)"
                    }
                }

                $relativePath = [System.IO.Path]::GetRelativePath($outputDirectory, $entry.Path)
                $writtenPath = if ([System.IO.Path]::IsPathRooted($relativePath)) { $entry.Path } else { $relativePath.Replace('\', '/') }

                $lines.Add('        @{')
                $lines.Add("            Path    = '$(ConvertTo-CompleterSingleQuotedText -Value $writtenPath)'")
                $lines.Add("            Trusted = `$$($entry.Trusted.ToString().ToLowerInvariant())")

                if ($null -ne $entry.Hash)
                {
                    $lines.Add("            Hash    = '$($entry.Hash)'")
                }

                $lines.Add('            Targets = @(')

                foreach ($target in $entry.Targets.Values)
                {
                    $commandName = ConvertTo-CompleterSingleQuotedText -Value ([string] $target.CommandName)

                    if ($target.IsNative)
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; Native = `$true }")
                    }
                    else
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; ParameterName = '$(ConvertTo-CompleterSingleQuotedText -Value ([string] $target.ParameterName))' }")
                    }
                }

                $lines.Add('            )')
                $lines.Add('        }')
            }

            $lines.Add('    )')
            $lines.Add('}')

            # Import-CompleterSetDefinition refuses a file over this size, so a set
            # that would be larger is refused here, before anything is written.
            # Set-Content writes every line followed by a newline, in UTF-8.
            $byteCount = [System.Text.Encoding]::UTF8.GetByteCount(($lines -join [Environment]::NewLine) + [Environment]::NewLine)

            if ($byteCount -gt $script:CompleterSetMaxFileBytes)
            {
                throw (Get-CompleterSetOverLimitMessage -ByteCount $byteCount)
            }

            if (-not $PSCmdlet.ShouldProcess($outputPath, 'Export completer set'))
            {
                return
            }

            Set-Content -LiteralPath $outputPath -Value $lines -Encoding utf8

            if ($PassThru)
            {
                Get-Item -LiteralPath $outputPath
            }
        }
        catch
        {
            throw "Failed to export completer set. $($_.Exception.Message)"
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Get-Completer
{
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsPaging)]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [CompleterActions.CompleterState[]] $State
    )

    begin
    {
        $registrationsByIdentity = [ordered] @{}
    }

    process
    {
        $targets = @()
        $managedRegistrations = @()
        $discoveredRegistrations = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $targets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            elseif ($PSCmdlet.ParameterSetName -ne 'All')
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                $targets = @(Resolve-CompleterTargetList @targetParameters)
            }

            if ($targets.Count -eq 0)
            {
                $managedRegistrations = @(Find-ManagedCompleterRegistration)
                $discoveredRegistrations = @(Find-RuntimeCompleterRegistration)
            }
            else
            {
                foreach ($target in $targets)
                {
                    $managedRegistrations += @(Find-ManagedCompleterRegistration -Target $target)
                    $discoveredRegistrations += @(Find-RuntimeCompleterRegistration -Target $target)
                }
            }

            $snapshot = Get-CompleterRegistrationSnapshot

            foreach ($registration in $managedRegistrations)
            {
                if ($null -eq $registration)
                {
                    continue
                }

                $registrationState = Resolve-CompleterRegistrationState -Target $registration -Snapshot $snapshot
                $identity = Get-CompleterTargetIdentity -Target $registration

                if ($registrationState.ManagedState -in 'Active', 'Pending', 'Failed')
                {
                    $registrationsByIdentity["Managed:$identity"] = $registration
                }
                else
                {
                    $registrationsByIdentity["Managed:$identity"] = New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -ImportModule $registration.ImportModule -State 'Stale' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted
                }

                if ($registrationState.ManagedState -in 'Stale', 'Failed' -and $null -ne $registrationState.RuntimeRegistration)
                {
                    $registrationsByIdentity["Discovered:$identity"] = New-CompleterRegistrationRecord -Target $registrationState.RuntimeRegistration -ScriptBlock $registrationState.RuntimeRegistration.ScriptBlock -Source 'Discovered' -State 'Conflicted'
                }
            }

            foreach ($registration in $discoveredRegistrations)
            {
                if ($null -eq $registration)
                {
                    continue
                }

                $identity = Get-CompleterTargetIdentity -Target $registration

                if ($registrationsByIdentity.Contains("Managed:$identity"))
                {
                    continue
                }

                $registrationsByIdentity["Discovered:$identity"] = $registration
            }
        }
        catch
        {
            throw "Failed to retrieve completer registrations. $($_.Exception.Message)"
        }
        finally
        {
            $targets = @()
            $managedRegistrations = @()
            $discoveredRegistrations = @()
        }
    }

    end
    {
        $registrations = @($registrationsByIdentity.Values)

        if ($PSBoundParameters.ContainsKey('State'))
        {
            $registrations = @($registrations | Where-Object { $State -contains $_.State })
        }

        $registrations = @($registrations | Sort-Object -Property 'CompleterType', 'CommandName', 'ParameterName' -Stable)
        $totalCount = $registrations.Count

        if ($PSCmdlet.PagingParameters.IncludeTotalCount)
        {
            $null = $PSCmdlet.WriteObject($PSCmdlet.PagingParameters.NewTotalCount($totalCount, 1.0))
        }

        $skip = $PSCmdlet.PagingParameters.Skip
        $first = $PSCmdlet.PagingParameters.First

        if ($skip -ge [uint64] $totalCount)
        {
            return
        }

        $startIndex = [int] $skip
        $itemsAvailable = $totalCount - $startIndex
        $itemsToEmit = if ($first -eq [uint64]::MaxValue)
        {
            $itemsAvailable
        }
        elseif ($first -gt [uint64] $itemsAvailable)
        {
            $itemsAvailable
        }
        else
        {
            [int] $first
        }

        if ($itemsToEmit -le 0)
        {
            return
        }

        $endIndex = $startIndex + $itemsToEmit - 1
        # Active, Pending, and Failed records are the managed table's own objects,
        # so the page is copied before it is written.
        $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $registrations[$startIndex..$endIndex]), $true)
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Import-CompleterScript
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('CompleterActions.ImportedCompleterRegistration')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter()]
        [switch] $Trusted
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                # The script is read once. The grammar validates the contents this
                # command information holds and the capture module executes the same
                # object, so a save between the two cannot run unvalidated code.
                # GetCommand looks a path with wildcard characters up as a pattern and
                # has no literal mode. Passing each '[', '*' and '?' as a class that
                # matches only itself finds most paths exactly, but a backtick in the
                # path defeats that form while the plain path then finds the file. So
                # both forms are tried in turn, and only command information for the
                # resolved file itself is accepted, never a sibling a pattern matched.
                $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
                $scriptCommand = $null
                $otherPath = $null
                foreach ($lookupPath in @(($resolvedPath -replace '[\[*?]', '[$0]'), $resolvedPath))
                {
                    $candidate = try { $ExecutionContext.InvokeCommand.GetCommand($lookupPath, [System.Management.Automation.CommandTypes]::ExternalScript) } catch { $null }
                    if ($null -eq $candidate) { continue }
                    if ([string]::Equals($candidate.Path, $resolvedPath, $pathComparison))
                    {
                        $scriptCommand = $candidate
                        break
                    }

                    $otherPath = $candidate.Path
                }

                if ($null -eq $scriptCommand)
                {
                    if ($null -ne $otherPath)
                    {
                        throw "The completer script path '$resolvedPath' resolves to the different file '$otherPath', so it was not loaded. Remove the backticks or wildcard characters from the path."
                    }

                    throw "The completer script '$resolvedPath' could not be loaded as a script file. Check that it still exists."
                }

                if (-not $Trusted)
                {
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $resolvedPath -Script $scriptCommand
                    Assert-CompleterScriptConformance -LiteralPath $resolvedPath -ParseResult $parseResult
                }

                $importSession = Import-CompleterScriptDefinition -LiteralPath $resolvedPath -Script $scriptCommand

                foreach ($definition in $importSession.Definitions)
                {
                    # The module, not the emitted record, records where each script block it
                    # emits came from, keyed on that very object: Register-Completer looks a
                    # block up in this table, so neither a property a caller sets nor a new
                    # block the caller binds to the capture module can claim an import.
                    $script:CompleterImportedScriptBlocks.Add($definition.ScriptBlock, [pscustomobject] @{ Module = $importSession.Module; ScriptPath = $resolvedPath; Trusted = [bool] $Trusted })

                    $targetParameters = @{
                        CommandName = $definition.CommandName
                    }

                    if ($definition.IsNative)
                    {
                        $targetParameters['Native'] = $true
                    }
                    else
                    {
                        $targetParameters['ParameterName'] = $definition.ParameterName
                    }

                    foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                    {
                        $PSCmdlet.WriteObject(
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $resolvedPath -ImportModule $importSession.Module -Trusted:$Trusted)
                        )
                    }
                }
            }
        }
        catch
        {
            throw "Failed to import completer script. $($_.Exception.Message)"
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Import-CompleterSet
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNull()]
        [version] $MinimumVersion,

        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNull()]
        [version] $RequiredVersion,

        [Parameter()]
        [switch] $SkipInvalid,

        [Parameter()]
        [switch] $Force
    )

    process
    {
        try
        {
            $resolvedPaths = @(
                if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
                    }
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'Path')
                {
                    foreach ($pathItem in $Path)
                    {
                        Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath
                    }
                }
            )

            $sets = @(
                if ($PSCmdlet.ParameterSetName -eq 'Name')
                {
                    $versionParameters = @{}

                    foreach ($versionParameterName in 'MinimumVersion', 'RequiredVersion')
                    {
                        if ($PSBoundParameters.ContainsKey($versionParameterName))
                        {
                            $versionParameters[$versionParameterName] = $PSBoundParameters[$versionParameterName]
                        }
                    }

                    if ($versionParameters.Count -eq 2)
                    {
                        throw '-MinimumVersion and -RequiredVersion cannot be used together.'
                    }

                    if ($versionParameters.Count -eq 1 -and $Name.Count -gt 1)
                    {
                        throw "-MinimumVersion and -RequiredVersion apply to one module name, but $($Name.Count) names were given."
                    }

                    foreach ($nameItem in $Name)
                    {
                        if ($nameItem -match '[*?\[\]]')
                        {
                            throw "Import-CompleterSet -Name does not accept wildcards. Received '$nameItem'."
                        }
                    }

                    foreach ($nameItem in $Name)
                    {
                        $setModule = Resolve-CompleterSetModule -Name $nameItem @versionParameters
                        @{ SetPath = $setModule.SetPath; Module = $setModule }
                    }
                }
                else
                {
                    foreach ($resolvedPath in $resolvedPaths)
                    {
                        @{ SetPath = $resolvedPath; Module = $null }
                    }
                }
            )

            foreach ($set in $sets)
            {
                $setPath = $set.SetPath
                $setModule = $set.Module
                $moduleParameters = @{}

                if ($null -ne $setModule)
                {
                    Write-Verbose -Message "Completer set module '$($setModule.Name)' $($setModule.Version) at '$($setModule.ModuleBase)': '$setPath'."
                    $moduleParameters = @{ ModuleName = $setModule.Name; ModuleBase = $setModule.ModuleBase }
                }

                $setDefinition = Import-CompleterSetDefinition -LiteralPath $setPath

                if ($null -ne $setModule)
                {
                    $trustedEntryCount = @($setDefinition.Entries.Where({ $_ -is [System.Collections.IDictionary] -and $_.Contains('Trusted') -and $_['Trusted'] -is [bool] -and $_['Trusted'] })).Count

                    if ($trustedEntryCount -gt 0)
                    {
                        Write-Warning -Message "The completer set module '$($setModule.Name)' $($setModule.Version) declares $trustedEntryCount trusted completer scripts, which run without the strict grammar check at first tab."
                    }
                }

                $snapshot = Get-CompleterRegistrationSnapshot
                $entryIndex = 0
                $staticEntries = @(
                    foreach ($rawEntry in $setDefinition.Entries)
                    {
                        $entryIndex++
                        Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $setDefinition.Directory @moduleParameters
                    }
                )
                $entries = @(Resolve-CompleterSetRegistration -Entry $staticEntries -Snapshot $snapshot -Force:$Force)

                $invalidEntries = @($entries.Where({ -not $_.IsValid }))

                if ($invalidEntries.Count -gt 0)
                {
                    $problemLines = @(
                        foreach ($entry in $invalidEntries)
                        {
                            $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $($entry.Index)" } else { "Entry $($entry.Index) ('$($entry.DeclaredPath)')" }

                            foreach ($problem in $entry.Problems)
                            {
                                '{0}: {1}' -f $entryLabel, $problem.Message
                            }
                        }
                    )

                    if (-not $SkipInvalid)
                    {
                        $entryNoun = if ($invalidEntries.Count -eq 1) { 'entry' } else { 'entries' }
                        throw "Completer set '$setPath' has $($invalidEntries.Count) invalid $entryNoun and nothing was registered. Fix the entries or use -SkipInvalid to register the valid ones.$([Environment]::NewLine)$($problemLines -join [Environment]::NewLine)"
                    }

                    foreach ($problemLine in $problemLines)
                    {
                        Write-Warning -Message "Completer set '$setPath' skipped $problemLine"
                    }
                }

                $validEntries = @($entries.Where({ $_.IsValid }))

                foreach ($entry in $validEntries)
                {
                    Write-Verbose -Message "Entry $($entry.Index) ('$($entry.DeclaredPath)'): $($entry.ResolutionNote)"
                }

                $hashCount = @($validEntries.Where({ $_.TargetSource -eq 'Hash' })).Count
                $parsedCount = @($validEntries.Where({ $_.TargetSource -eq 'Parsed' })).Count
                $trustedCount = @($validEntries.Where({ $_.TargetSource -eq 'Trusted' })).Count
                Write-Verbose -Message "Completer set '$setPath': $hashCount entries from the hash, $parsedCount parsed, $trustedCount trusted."

                $confirmedEntries = @(
                    foreach ($entry in $validEntries)
                    {
                        if ($PSCmdlet.ShouldProcess($entry.Path, 'Import completer set entry'))
                        {
                            $entry
                        }
                    }
                )

                $registrations = @(foreach ($entry in $confirmedEntries) { $entry.Registrations })
                $conflicts = @(foreach ($entry in $confirmedEntries) { $entry.Conflicts })

                Add-CompleterRegistration -Registration $registrations -Conflict $conflicts -Snapshot $snapshot | Copy-CompleterRegistration
            }
        }
        catch
        {
            throw "Failed to import completer set. $($_.Exception.Message)"
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function New-CompleterScript
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Probe', ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]] $CommandName,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(ParameterSetName = 'Probe')]
        [string] $HelpArgument,

        [Parameter(Mandatory, ParameterSetName = 'HelpText', ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]] $HelpText,

        [Parameter(Mandatory, ParameterSetName = 'NoProbe')]
        [switch] $NoProbe,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        try
        {
            $targetNames = @(ConvertTo-CompleterTargetName -CommandName $CommandName)

            # Line 2 of the script names the argument in a comment, which a line break would end.
            if ($HelpArgument.IndexOfAny([char[]] "`r`n") -ge 0)
            {
                throw '-HelpArgument must not contain a line break.'
            }

            $outputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

            if ([System.IO.Path]::GetExtension($outputPath) -ne '.ps1')
            {
                throw "Completer scripts must be .ps1 files. Received '$outputPath'."
            }

            if (Test-Path -LiteralPath $outputPath -PathType Container)
            {
                throw "Completer scripts must be file paths. '$outputPath' is a directory."
            }

            $outputDirectory = Split-Path -Path $outputPath -Parent

            if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
            {
                throw "The directory '$outputDirectory' does not exist."
            }

            if (-not $Force -and (Test-Path -LiteralPath $outputPath))
            {
                throw "The file '$outputPath' already exists. Use -Force to overwrite it."
            }
        }
        catch
        {
            # ThrowTerminatingError, unlike throw, is not silenced by -ErrorAction
            # SilentlyContinue or Ignore, so a failed check never lets end write.
            $exception = [System.InvalidOperationException]::new("Failed to create completer script. $($_.Exception.Message)", $_.Exception)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($exception, 'NewCompleterScriptFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Path))
        }

        $helpLines = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'HelpText')
        {
            foreach ($helpLine in $HelpText)
            {
                $helpLines.Add($helpLine)
            }
        }
    }

    end
    {
        try
        {
            $primaryName = $CommandName[0]
            $application = $null
            $action = 'Create completer script without running a program'

            if ($PSCmdlet.ParameterSetName -eq 'Probe')
            {
                $application = Resolve-CompleterHelpProbeApplication -Name $primaryName

                if ($application.CanRun)
                {
                    Write-Verbose -Message "Resolved '$primaryName' to the application '$($application.Path)'."

                    if ($null -ne $application.AliasTarget)
                    {
                        Write-Verbose -Message "'$($application.Path)' is an app execution alias for '$($application.AliasTarget)'."
                    }

                    if ($PSBoundParameters.ContainsKey('HelpArgument'))
                    {
                        $action = "Create completer script, running '$($application.Path) $HelpArgument' to read its help"
                    }
                    elseif ($IsWindows)
                    {
                        $action = "Create completer script, running '$($application.Path) --help' and, if it is rejected, '/?' to read its help"
                    }
                    else
                    {
                        $action = "Create completer script, running '$($application.Path) --help' to read its help"
                    }
                }
                else
                {
                    Write-Verbose -Message "The probe will not run '$primaryName'. $($application.Warning)"
                }
            }

            if (-not $PSCmdlet.ShouldProcess($outputPath, $action))
            {
                return
            }

            # The call was confirmed once; the write that follows must not ask again.
            $ConfirmPreference = 'None'

            $subcommands = @()
            $skeletonParameters = @{}

            switch ($PSCmdlet.ParameterSetName)
            {
                'Probe'
                {
                    $probeParameters = @{
                        Application    = $application
                        TimeoutSeconds = $script:CompleterHelpProbeTimeoutSeconds
                    }

                    if ($PSBoundParameters.ContainsKey('HelpArgument'))
                    {
                        $probeParameters['HelpArgument'] = $HelpArgument
                    }

                    $probe = Get-CompleterHelpSubcommand @probeParameters

                    foreach ($warning in $probe.Warnings)
                    {
                        Write-Warning -Message $warning
                    }

                    foreach ($verboseLine in $probe.VerboseLines)
                    {
                        Write-Verbose -Message $verboseLine
                    }

                    $subcommands = @($probe.Subcommands)

                    if ($subcommands.Count -gt 0)
                    {
                        $skeletonParameters['SeedKind'] = 'Probe'
                        $skeletonParameters['ProbeArgument'] = $probe.Argument
                    }
                }

                'HelpText'
                {
                    $subcommands = @(ConvertFrom-CompleterHelpText -Text (ConvertTo-CompleterCleanHelpText -Text ($helpLines -join "`n")))
                    $skeletonParameters['SeedKind'] = 'HelpText'
                }
            }

            $lines = Get-CompleterScriptSkeleton -Name $primaryName -Stem (ConvertTo-CompleterScriptStem -Name $primaryName) -Target $targetNames -Subcommand $subcommands @skeletonParameters

            $file = Save-CompleterScriptFile -Line $lines -LiteralPath $outputPath -ExpectedTarget $targetNames -Force:$Force -Verbose:$false

            Write-Verbose -Message "Wrote '$($file.FullName)': $($targetNames.Count) targets, $($subcommands.Count) subcommands."

            if ($PassThru)
            {
                $file
            }
        }
        catch
        {
            $exception = [System.InvalidOperationException]::new("Failed to create completer script. $($_.Exception.Message)", $_.Exception)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($exception, 'NewCompleterScriptFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Path))
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Register-Completer
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [switch] $Lazy,

        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [switch] $Trusted,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedInputs = @()
        $isLazy = $PSCmdlet.ParameterSetName -in 'LazyPath', 'LazyLiteralPath'

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedInputs = @($InputObject | Resolve-CompleterInputObject -RequireScriptBlock)
            }
            elseif ($isLazy)
            {
                $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LazyLiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }
                $resolvedPaths = @(Resolve-CompleterScriptPath @pathParameters)

                if ($resolvedPaths.Count -ne 1)
                {
                    throw "Lazy registration takes one completer script per call, but the path resolved to $($resolvedPaths.Count) files."
                }

                $scriptPath = $resolvedPaths[0]
                $explicitTargets = @()

                if ($PSBoundParameters.ContainsKey('CommandName'))
                {
                    if ($Native)
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -Native)
                    }
                    elseif ($PSBoundParameters.ContainsKey('ParameterName'))
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -ParameterName $ParameterName)
                    }
                    else
                    {
                        throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                    }
                }
                elseif ($Native -or $PSBoundParameters.ContainsKey('ParameterName'))
                {
                    throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                }

                if ($Trusted)
                {
                    if ($explicitTargets.Count -eq 0)
                    {
                        throw "-Trusted lazy registration requires explicit targets: a trusted script is not parsed, so its targets cannot be derived from '$scriptPath'. Pass -CommandName with -Native or -ParameterName."
                    }

                    $targets = $explicitTargets
                }
                else
                {
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $scriptPath

                    if ($parseResult.ParseErrors.Count -eq 0)
                    {
                        Assert-CompleterScriptConformance -LiteralPath $scriptPath -ParseResult $parseResult
                    }

                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath -ParseResult $parseResult)

                    if ($explicitTargets.Count -eq 0)
                    {
                        $targets = $derivedTargets
                    }
                    else
                    {
                        $derivedIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                        foreach ($derivedTarget in $derivedTargets)
                        {
                            $null = $derivedIdentities.Add((Get-CompleterTargetIdentity -Target $derivedTarget))
                        }

                        foreach ($explicitTarget in $explicitTargets)
                        {
                            if (-not $derivedIdentities.Contains((Get-CompleterTargetIdentity -Target $explicitTarget)))
                            {
                                $derivedList = ($derivedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                                throw "The script '$scriptPath' does not register a completer for '$($explicitTarget.RuntimeKey)'. It registers: $derivedList."
                            }
                        }

                        $targets = $explicitTargets
                    }
                }

                foreach ($target in $targets)
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = New-CompleterLazyStub -Key $target.RuntimeKey -Native:$target.IsNative
                        ImportModule = $null
                        ScriptPath = $scriptPath
                        Trusted = [bool] $Trusted
                    }
                }
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = $ScriptBlock
                        ImportModule = $null
                        ScriptPath = $null
                        Trusted = $false
                    }
                }
            }

            $targetState = if ($isLazy) { 'Pending' } else { 'Active' }

            foreach ($resolvedInput in $resolvedInputs)
            {
                $registration = New-CompleterRegistrationRecord -Target $resolvedInput.Target -ScriptBlock $resolvedInput.ScriptBlock -Source 'Managed' -ImportModule $resolvedInput.ImportModule -State $targetState -ScriptPath $resolvedInput.ScriptPath -Trusted:([bool] $resolvedInput.Trusted)
                $conflict = Resolve-CompleterRegistrationConflict -Registration $registration -Force:$Force

                if ($null -ne $conflict.Problem)
                {
                    throw "Failed to register the completer '$($registration.RuntimeKey)'. $($conflict.Problem)"
                }

                if (-not $conflict.IsExisting -and -not $PSCmdlet.ShouldProcess($registration.RuntimeKey, 'Register completer registration'))
                {
                    continue
                }

                $storedRegistration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                if ($PassThru)
                {
                    $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $storedRegistration))
                }
            }
        }
        finally
        {
            $resolvedInputs = @()
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Reset-Completer
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $decidedTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # A plain function, not an advanced one, so the error is written by
        # Reset-Completer itself: it names Reset-Completer and sets $? to false.
        function Write-CompleterResetError
        {
            param(
                [string] $Message,
                [System.Exception] $Exception,
                [object] $TargetObject
            )

            $PSCmdlet.WriteError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($Message, $Exception),
                    'CompleterResetFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $TargetObject
                )
            )
        }
    }

    process
    {
        $resolvedTargets = [System.Collections.Generic.List[psobject]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'InputObject')
        {
            foreach ($inputItem in $InputObject)
            {
                try
                {
                    $resolvedTargets.Add((Resolve-CompleterInputObject -InputObject $inputItem).Target)
                }
                catch
                {
                    Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception -TargetObject $inputItem
                }
            }
        }
        else
        {
            $targetParameters = @{ CommandName = $CommandName }

            if ($PSCmdlet.ParameterSetName -eq 'Native')
            {
                $targetParameters['Native'] = $true
            }
            else
            {
                $targetParameters['ParameterName'] = $ParameterName
            }

            try
            {
                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedTargets.Add($target)
                }
            }
            catch
            {
                Write-CompleterResetError -Message "Failed to reset the completer. $($_.Exception.Message)" -Exception $_.Exception
            }
        }

        foreach ($target in $resolvedTargets)
        {
            if (-not $decidedTargets.Add((Get-CompleterTargetIdentity -Target $target)))
            {
                continue
            }

            # Every row that cannot be reset sets a reason instead of throwing,
            # so -ErrorVariable collects exactly one error per target.
            $reason = $null
            $failure = $null

            try
            {
                $registrationState = Resolve-CompleterRegistrationState -Target $target
                $managedRegistration = $registrationState.ManagedRegistration
                $runtimeRegistration = $registrationState.RuntimeRegistration
                $managedState = $registrationState.ManagedState
                $runtimeKey = if ($null -ne $managedRegistration) { $managedRegistration.RuntimeKey } else { $target.RuntimeKey }

                $reason = if ($null -eq $managedRegistration -and $null -ne $runtimeRegistration)
                {
                    "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed, so it cannot be reset."
                }
                elseif ($null -eq $managedRegistration)
                {
                    'No completer registration was found for the requested target.'
                }
                elseif ($managedState -eq 'Pending')
                {
                    $null
                }
                elseif ($managedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                {
                    "The module-managed completer registration for '$runtimeKey' is $($managedState.ToLowerInvariant()) and the live runtime registration was created outside this module. Use Register-Completer -Force to replace it, or Unregister-Completer -AllowUnmanaged to remove it."
                }
                elseif ($managedState -eq 'Stale')
                {
                    "The module-managed completer registration for '$runtimeKey' is stale. Use Register-Completer -Force to register it again."
                }
                elseif ([string]::IsNullOrWhiteSpace($managedRegistration.ScriptPath))
                {
                    "The completer registration '$runtimeKey' was registered from a script block, not a script file, so there is nothing to reload."
                }
                elseif (-not (Test-Path -LiteralPath $managedRegistration.ScriptPath -PathType Leaf))
                {
                    "The script '$($managedRegistration.ScriptPath)' for '$runtimeKey' no longer exists. Restore it, or remove the registration with Unregister-Completer."
                }

                if ($null -eq $reason)
                {
                    if ($managedState -eq 'Pending')
                    {
                        Write-Verbose -Message "The completer registration '$runtimeKey' is already pending."

                        if ($PassThru -and -not $WhatIfPreference)
                        {
                            $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $managedRegistration))
                        }
                    }
                    elseif ($PSCmdlet.ShouldProcess($runtimeKey, 'Reset completer registration'))
                    {
                        $registration = New-CompleterRegistrationRecord -Target $managedRegistration -ScriptBlock (New-CompleterLazyStub -Key $managedRegistration.RuntimeKey -Native:$managedRegistration.IsNative) -Source 'Managed' -State 'Pending' -ScriptPath $managedRegistration.ScriptPath -Trusted:([bool] $managedRegistration.Trusted)
                        $conflict = [pscustomobject] [ordered] @{
                            Key                 = $registration.Key
                            ManagedRegistration = $managedRegistration
                            RuntimeRegistration = $runtimeRegistration
                            IsExisting          = $false
                            Problem             = $null
                        }

                        $storedRegistration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                        if ($PassThru)
                        {
                            $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $storedRegistration))
                        }
                    }
                }
            }
            catch
            {
                $failure = $_.Exception
                $reason = $_.Exception.Message
            }

            if ($null -ne $reason)
            {
                Write-CompleterResetError -Message "Failed to reset the completer '$($target.RuntimeKey)'. $reason" -Exception $failure -TargetObject $target.RuntimeKey
            }
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Test-CompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition,

        [Parameter()]
        [switch] $TargetOnly
    )

    begin
    {
        $resolvedCursorPosition = if ($PSBoundParameters.ContainsKey('CursorPosition')) { $CursorPosition } else { $InputText.Length }

        if ($resolvedCursorPosition -gt $InputText.Length)
        {
            throw "CursorPosition $resolvedCursorPosition is past the end of InputText, which has $($InputText.Length) characters."
        }

        $resolvedTargets = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets.AddRange([object[]] @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target }))
                return
            }

            $targetParameters = @{}

            switch ($PSCmdlet.ParameterSetName)
            {
                'Native'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['Native'] = $true
                    break
                }

                'CommandParameter'
                {
                    $targetParameters['CommandName'] = $CommandName
                    $targetParameters['ParameterName'] = $ParameterName
                    break
                }
            }

            $resolvedTargets.AddRange([object[]] @(Resolve-CompleterTargetList @targetParameters))
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
    }

    end
    {
        try
        {
            if ($resolvedTargets.Count -ne 1)
            {
                $targetList = ($resolvedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                throw "Test-CompleterRegistration tests one completer target per call because InputText can only invoke one completer, but $($resolvedTargets.Count) targets resolved: $targetList. Call it once per target."
            }

            $target = $resolvedTargets[0]

            $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $target

            if ($null -eq $runtimeRegistration)
            {
                throw "No runtime completer registration exists for '$($target.RuntimeKey)'. Register the completer before testing it."
            }

            # TabExpansion2 reports what the engine completed, not which completer
            # produced it, so the target's entry is fronted by an observer that
            # records the target's own output. The observer puts the original
            # entry back before it delegates, so the completer, including a lazy
            # stub that checks it still owns its entry, runs as it would at the
            # prompt. The engine keeps each CompletionResult in the completer's
            # output collection and turns every other non-null item into one
            # whose CompletionText is PSObject.ToString() of that item, so the
            # observer records the same text and hands the collection back as
            # is; re-emitting item by item would unroll an item that is itself
            # a collection and change what the engine completes.
            $runtime = Get-CompleterRuntime
            $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
            $runtimeKey = $runtimeRegistration.RuntimeKey
            $completerScriptBlock = $runtimeRegistration.ScriptBlock
            $targetCompletionTexts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $observer = {
                $dictionary[$runtimeKey] = $completerScriptBlock
                $output = $completerScriptBlock.Invoke($args)

                foreach ($item in $output)
                {
                    if ($null -ne $item)
                    {
                        $null = $targetCompletionTexts.Add($(if ($item -is [System.Management.Automation.CompletionResult]) { $item.CompletionText } else { $item.PSObject.ToString() }))
                    }
                }

                $output
            }.GetNewClosure()

            $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey -Value $observer

            try
            {
                $completion = TabExpansion2 -InputScript $InputText -CursorColumn $resolvedCursorPosition
            }
            finally
            {
                if ([object]::ReferenceEquals((Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey), $observer))
                {
                    $null = Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeKey -Value $completerScriptBlock
                }
            }

            foreach ($completionMatch in @($completion.CompletionMatches))
            {
                $match = New-CompletionMatch -Target $target -CompletionResult $completionMatch -InputText $InputText -CursorPosition $resolvedCursorPosition -FromTarget:$targetCompletionTexts.Contains($completionMatch.CompletionText)

                if ($TargetOnly -and -not $match.FromTarget)
                {
                    continue
                }

                $PSCmdlet.WriteObject($match)
            }
        }
        catch
        {
            throw "Failed to test the completer registration. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedTargets.Clear()
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Test-CompleterScript
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                Get-CompleterScriptFinding -LiteralPath $resolvedPath
            }
        }
        catch
        {
            throw "Failed to test completer script. $($_.Exception.Message)"
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Test-CompleterSet
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNull()]
        [version] $MinimumVersion,

        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNull()]
        [version] $RequiredVersion,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Filter = '*_completer.ps1'
    )

    process
    {
        try
        {
            $sets = @(
                if ($PSCmdlet.ParameterSetName -eq 'Name')
                {
                    $versionParameters = @{}

                    foreach ($versionParameterName in 'MinimumVersion', 'RequiredVersion')
                    {
                        if ($PSBoundParameters.ContainsKey($versionParameterName))
                        {
                            $versionParameters[$versionParameterName] = $PSBoundParameters[$versionParameterName]
                        }
                    }

                    if ($versionParameters.Count -eq 2)
                    {
                        throw '-MinimumVersion and -RequiredVersion cannot be used together.'
                    }

                    if ($versionParameters.Count -eq 1 -and $Name.Count -gt 1)
                    {
                        throw "-MinimumVersion and -RequiredVersion apply to one module name, but $($Name.Count) names were given."
                    }

                    foreach ($nameItem in $Name)
                    {
                        if ($nameItem -match '[*?\[\]]')
                        {
                            throw "Test-CompleterSet -Name does not accept wildcards. Received '$nameItem'."
                        }
                    }

                    foreach ($nameItem in $Name)
                    {
                        $setModule = Resolve-CompleterSetModule -Name $nameItem @versionParameters
                        @{ SetPath = $setModule.SetPath; Module = $setModule }
                    }
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        @{ SetPath = (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName; Module = $null }
                    }
                }
                else
                {
                    foreach ($pathItem in $Path)
                    {
                        foreach ($resolvedPath in @(Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath))
                        {
                            @{ SetPath = $resolvedPath; Module = $null }
                        }
                    }
                }
            )

            foreach ($set in $sets)
            {
                $setDefinition = Import-CompleterSetDefinition -LiteralPath $set.SetPath
                $findingParameters = @{ SetDefinition = $setDefinition; Filter = $Filter }
                $package = Get-CompleterSetPackage -SetPath $setDefinition.Path -Module $set.Module

                if ($null -ne $package)
                {
                    $findingParameters['Package'] = $package
                }

                Get-CompleterSetFinding @findingParameters
            }
        }
        catch
        {
            throw "Failed to test completer set. $($_.Exception.Message)"
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Unregister-Completer
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter()]
        [switch] $AllowUnmanaged,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $removedTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    process
    {
        $resolvedTargets = @()

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedTargets = @($InputObject | Resolve-CompleterInputObject | ForEach-Object { $_.Target })
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                $resolvedTargets = @(Resolve-CompleterTargetList @targetParameters)
            }

            foreach ($target in $resolvedTargets)
            {
                $identity = Get-CompleterTargetIdentity -Target $target

                if ($removedTargets.Contains($identity))
                {
                    continue
                }

                $managedRegistration = $null
                $runtimeRegistration = $null
                $registrationToRemove = $null
                $removedRuntimeRegistration = $null
                $removedManagedRegistration = $null

                try
                {
                    $registrationState = Resolve-CompleterRegistrationState -Target $target
                    $managedRegistration = $registrationState.ManagedRegistration
                    $runtimeRegistration = $registrationState.RuntimeRegistration

                    if ($registrationState.ManagedState -in 'Active', 'Pending')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed' -and $null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The module-managed completer registration for '$($runtimeRegistration.RuntimeKey)' is $($registrationState.ManagedState.ToLowerInvariant()): the live runtime registration was created outside this module. Re-run with -AllowUnmanaged to remove the live runtime registration and the managed record."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    elseif ($registrationState.ManagedState -in 'Stale', 'Failed')
                    {
                        $registrationToRemove = $managedRegistration
                    }
                    elseif ($null -ne $runtimeRegistration)
                    {
                        if (-not $AllowUnmanaged)
                        {
                            throw "The completer registration '$($runtimeRegistration.RuntimeKey)' is not module-managed. Re-run with -AllowUnmanaged to remove the runtime registration."
                        }

                        $registrationToRemove = $runtimeRegistration
                    }
                    else
                    {
                        throw 'No completer registration was found for the requested target.'
                    }

                    $null = $removedTargets.Add($identity)

                    if (-not $PSCmdlet.ShouldProcess($registrationToRemove.RuntimeKey, 'Unregister completer registration'))
                    {
                        continue
                    }

                    if ($null -ne $runtimeRegistration)
                    {
                        $removedRuntimeRegistration = Remove-RuntimeCompleterRegistration -Target $target
                    }

                    if ($null -ne $managedRegistration)
                    {
                        $removedManagedRegistration = Remove-ManagedCompleterRegistration -Target $target
                    }

                    if ($PassThru)
                    {
                        if ($registrationToRemove.IsManaged -and $null -ne $removedManagedRegistration)
                        {
                            $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $removedManagedRegistration))
                        }
                        elseif ($null -ne $removedRuntimeRegistration)
                        {
                            $PSCmdlet.WriteObject((Copy-CompleterRegistration -Registration $removedRuntimeRegistration))
                        }
                    }
                }
                catch
                {
                    if ($null -ne $removedRuntimeRegistration -and $null -eq (Find-RuntimeCompleterRegistration -Target $target))
                    {
                        $null = Add-RuntimeCompleterRegistration -Target $removedRuntimeRegistration -ScriptBlock $removedRuntimeRegistration.ScriptBlock
                    }

                    if ($null -ne $removedManagedRegistration -and $null -eq (Find-ManagedCompleterRegistration -Target $target))
                    {
                        $null = Add-ManagedCompleterRegistration -Registration $removedManagedRegistration
                    }

                    throw "Failed to unregister the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
                finally
                {
                    $managedRegistration = $null
                    $runtimeRegistration = $null
                    $registrationToRemove = $null
                    $removedRuntimeRegistration = $null
                    $removedManagedRegistration = $null
                }
            }
        }
        finally
        {
            $resolvedTargets = @()
        }
    }
}

<#
.EXTERNALHELP CompleterActions-help.xml
#>
function Update-CompleterSet
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path', ConfirmImpact = 'Medium')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [CompleterActions.CompleterScriptFinding[]] $InputObject,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Filter = '*_completer.ps1',

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $pathComparer = if ($IsWindows -or $IsMacOS) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
        $seenSetPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
        $setPaths = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        try
        {
            $resolvedPaths = @(
                if ($PSCmdlet.ParameterSetName -eq 'InputObject')
                {
                    foreach ($finding in $InputObject)
                    {
                        (Get-Item -LiteralPath $finding.Path -ErrorAction Stop).FullName
                    }
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
                    }
                }
                else
                {
                    foreach ($pathItem in $Path)
                    {
                        Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath
                    }
                }
            )
        }
        catch
        {
            throw "Failed to update completer set. $($_.Exception.Message)"
        }

        foreach ($resolvedPath in $resolvedPaths)
        {
            if ($seenSetPaths.Add($resolvedPath))
            {
                $setPaths.Add($resolvedPath)
            }
        }
    }

    end
    {
        # The bytes a text encodes to, byte-order mark first.
        $getBytes = {
            param([string] $Text, [System.Text.Encoding] $Encoding, [byte[]] $Preamble)

            $body = $Encoding.GetBytes($Text)
            $bytes = [byte[]]::new($Preamble.Length + $body.Length)
            $Preamble.CopyTo($bytes, 0)
            $body.CopyTo($bytes, $Preamble.Length)
            , $bytes
        }

        # A value as text with its type, its keys sorted and each text prefixed
        # with its length, so two reads of the same data give the same text and
        # different data cannot.
        $getDataText = $null
        $getDataText = {
            param($Value)

            if ($null -eq $Value)
            {
                '$null'
            }
            elseif ($Value -is [System.Collections.IDictionary])
            {
                '@{' + (@(foreach ($key in @($Value.Keys | Sort-Object)) { (& $getDataText $key) + '=' + (& $getDataText $Value[$key]) }) -join ';') + '}'
            }
            elseif ($Value -is [System.Collections.IList])
            {
                '@(' + (@(foreach ($item in $Value) { & $getDataText $item }) -join ',') + ')'
            }
            else
            {
                $valueText = [string] $Value
                '[{0}]{1}:{2}' -f $Value.GetType().FullName, $valueText.Length, $valueText
            }
        }

        try
        {
            foreach ($setPath in $setPaths)
            {
                $setDefinition = Import-CompleterSetDefinition -LiteralPath $setPath -IncludeSource
                $setFile = $setDefinition.Path
                $states = @(Get-CompleterSetEntryState -SetDefinition $setDefinition -Filter $Filter)
                $entryStates = @($states | Where-Object { $_.PSObject.TypeNames[0] -eq 'CompleterActions.CompleterSetEntryState' })
                $unlistedScripts = @($states | Where-Object { $_.PSObject.TypeNames[0] -eq 'CompleterActions.CompleterSetUnlistedScript' })
                $updates = [System.Collections.Generic.List[object]]::new()
                $withoutHashCount = 0

                foreach ($state in $entryStates)
                {
                    $entry = $state.Entry
                    $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $($entry.Index)" } else { "Entry $($entry.Index) ('$($entry.DeclaredPath)')" }

                    if ($state.RawEntry -isnot [System.Collections.IDictionary])
                    {
                        continue
                    }

                    if (-not $state.RawEntry.Contains('Hash'))
                    {
                        $withoutHashCount++
                        continue
                    }

                    # The kinds Test-CompleterSet reports as Errors, in its order.
                    $errorProblem = @(
                        foreach ($kind in 'MissingScript', 'InvalidEntry', 'UnreadableTargets', 'TargetMismatch')
                        {
                            $entry.Problems | Where-Object { $_.Kind -eq $kind }
                        }

                        $state.DuplicateTargetProblems
                    ) | Select-Object -First 1

                    if ($null -ne $errorProblem)
                    {
                        Write-Warning -Message "$entryLabel of '$setFile' was not updated: $($errorProblem.Message) Regenerate the set with Export-CompleterSet."
                        continue
                    }

                    # Test-CompleterSet reports neither InvalidHash nor HashMismatch for these.
                    if ($null -eq $entry.ActualHash -or ((Test-CompleterSetHashFormat -Value $entry.DeclaredHash) -and $entry.ActualHash -ieq [string] $entry.DeclaredHash))
                    {
                        continue
                    }

                    if ($entry.Trusted)
                    {
                        Write-Warning -Message "$entryLabel of '$setFile' is trusted, so its Targets were not checked against the script."
                    }

                    $updates.Add([pscustomobject] [ordered] @{
                            State  = $state
                            Extent = $state.Extent.HashExtent
                            Text   = "'$($entry.ActualHash)'"
                        })
                }

                if ($withoutHashCount -gt 0)
                {
                    Write-Warning -Message "Entries of '$setFile' without a Hash were not updated: $withoutHashCount. Regenerate the set with Export-CompleterSet to add them."
                }

                foreach ($unlistedScript in $unlistedScripts)
                {
                    Write-Warning -Message "$($unlistedScript.Message) Add it with Export-CompleterSet."
                }

                if ($updates.Count -eq 0)
                {
                    Write-Verbose -Message "Updated 0 of $($entryStates.Count) entries in '$setFile'."
                    continue
                }

                $encoding = $setDefinition.Encoding
                $preamble = [byte[]]::new(0)

                if ($setDefinition.HasPreamble)
                {
                    $preamble = $encoding.GetPreamble()
                }

                if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]] (& $getBytes $setDefinition.Text $encoding $preamble), [byte[]] $setDefinition.Bytes))
                {
                    throw "'$setFile' cannot be rewritten without changing bytes outside its Hash values, because its text does not round-trip in its encoding. Regenerate the set with Export-CompleterSet."
                }

                $newText = Set-CompleterSetHashText -Text $setDefinition.Text -Replacement $updates.ToArray()

                # The entries as read, with the new Hash values, are what the new text must give back.
                foreach ($update in $updates)
                {
                    $update.State.RawEntry['Hash'] = $update.State.Entry.ActualHash
                }

                $expectedEntries = @($setDefinition.Entries | ForEach-Object { & $getDataText $_ })

                try
                {
                    $newEntries = @((Import-CompleterDataFile -Text $newText -SkipLimitCheck).Data['Entries'] | Where-Object { $null -ne $_ } | ForEach-Object { & $getDataText $_ })
                    $isEquivalent = [System.Linq.Enumerable]::SequenceEqual([string[]] $newEntries, [string[]] $expectedEntries)
                }
                catch
                {
                    $isEquivalent = $false
                }

                if (-not $isEquivalent)
                {
                    throw 'Update-CompleterSet did not produce an equivalent set, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues.'
                }

                $newBytes = & $getBytes $newText $encoding $preamble

                if ($newBytes.Length -gt $script:CompleterSetMaxFileBytes)
                {
                    throw (Get-CompleterSetOverLimitMessage -ByteCount $newBytes.Length)
                }

                if (-not $PSCmdlet.ShouldProcess($setFile, "Update $($updates.Count) Hash values"))
                {
                    continue
                }

                $writtenFile = Save-CompleterSetFile -Bytes $newBytes -LiteralPath $setFile

                foreach ($update in $updates)
                {
                    Write-Verbose -Message "Updated the Hash of entry $($update.State.Entry.Index) ('$($update.State.Entry.DeclaredPath)') in '$setFile'."
                }

                Write-Verbose -Message "Updated $($updates.Count) of $($entryStates.Count) entries in '$setFile'."

                if ($PassThru)
                {
                    $writtenFile
                }
            }
        }
        catch
        {
            throw "Failed to update completer set. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Writes a batch of completer registrations to the runtime and the managed state as one transaction.

.DESCRIPTION
Performs the write half of a registration after the caller has resolved every
record's conflicts and confirmed the operation. Each record whose conflict
result reports IsExisting is not written; the managed record it already
matches is returned in its place. The batch is written in two passes: every
other record's script block is first added to the live completer dictionary,
in order, and only then is every such record stored in the managed
registration table, in order. The stored records are returned in the same
order as the input. With one record the two passes are the runtime write and
then the managed write of that record.

If any write fails, the batch is rolled back in reverse from the last record
whose runtime write was started: for each written record, the earlier runtime
value carried on its conflict result is put back or the new one removed, and
the earlier managed record is put back or the new one removed, so the session
ends exactly as it was before the batch. A managed write that fails therefore
also undoes the runtime values of the records after it, which the runtime pass
had already written. The error names the target whose write failed, and a
failure during the rollback is reported together with the original error so
the caller can say the target may be inconsistent. Register-Completer writes
each target through this helper on its own, so every target of a call stays
its own transaction, and Import-CompleterSet writes a whole set through it,
so an eager, a lazy, and a completer set registration share one write path.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records to store, in write order.
Each record's ScriptBlock is the value written to the runtime dictionary.

.PARAMETER Conflict
The results Resolve-CompleterRegistrationConflict returned for the same
records, in the same order. Their RuntimeRegistration and ManagedRegistration
are the state restored when a write fails.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot the records were resolved
against. Its RuntimeContext and Managed table are written through, so a batch
looks up the runtime dictionaries and the managed table once instead of once
per record. When it is omitted each write looks them up itself.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one record per input, in order: the reused managed record for an
existing registration, otherwise the record as stored in the managed
registration table.
#>
function Add-CompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Conflict,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($Registration.Count -ne $Conflict.Count)
    {
        throw "Each registration needs the conflict result resolved for it, but $($Registration.Count) registrations came with $($Conflict.Count) conflict results."
    }

    $runtimeParameters = @{}
    $managedParameters = @{}

    if ($null -ne $Snapshot)
    {
        $runtimeParameters['Runtime'] = $Snapshot.RuntimeContext
        $managedParameters['Table'] = $Snapshot.Managed
    }

    $storedRegistrations = [System.Collections.Generic.List[psobject]]::new()
    $runtimeIndex = -1
    $managedIndex = -1

    try
    {
        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            $runtimeIndex = $index
            $null = Add-RuntimeCompleterRegistration -Target $Registration[$index] -ScriptBlock $Registration[$index].ScriptBlock @runtimeParameters
        }

        for ($index = 0; $index -lt $Registration.Count; $index++)
        {
            if ($Conflict[$index].IsExisting)
            {
                $storedRegistrations.Add($Conflict[$index].ManagedRegistration)
                continue
            }

            $managedIndex = $index
            $storedRegistrations.Add((Add-ManagedCompleterRegistration -Registration $Registration[$index] @managedParameters))
        }

        return $storedRegistrations
    }
    catch
    {
        $registrationError = $_
        $failedIndex = if ($managedIndex -ge 0) { $managedIndex } else { $runtimeIndex }
        $failedRegistration = $Registration[$failedIndex]
        $rollbackErrors = [System.Collections.Generic.List[string]]::new()

        for ($index = $runtimeIndex; $index -ge 0; $index--)
        {
            if ($Conflict[$index].IsExisting)
            {
                continue
            }

            try
            {
                if ($null -ne $Conflict[$index].RuntimeRegistration)
                {
                    $null = Add-RuntimeCompleterRegistration -Target $Conflict[$index].RuntimeRegistration -ScriptBlock $Conflict[$index].RuntimeRegistration.ScriptBlock @runtimeParameters
                }
                else
                {
                    $null = Remove-RuntimeCompleterRegistration -Target $Registration[$index]
                }

                if ($null -ne $Conflict[$index].ManagedRegistration)
                {
                    $null = Add-ManagedCompleterRegistration -Registration $Conflict[$index].ManagedRegistration @managedParameters
                }
                else
                {
                    $null = Remove-ManagedCompleterRegistration -Target $Registration[$index]
                }
            }
            catch
            {
                $rollbackErrors.Add($_.Exception.Message)
            }
        }

        $message = "Failed to register the completer '$($failedRegistration.RuntimeKey)'. $($registrationError.Exception.Message)"

        if ($rollbackErrors.Count -gt 0)
        {
            $message += " Rollback of the previous runtime and managed state also failed, so the target may be inconsistent: $($rollbackErrors -join ' ')"
        }

        throw $message
    }
}
<#
.SYNOPSIS
Adds or replaces a managed registration record in module state.

.DESCRIPTION
Stores a registration object in the module's in-memory registration table
under its Get-CompleterTargetIdentity, which combines its RuntimeKey with its
kind, so records whose Key is the same, such as a native and a parameter record,
are stored side by side. An existing entry for the same target is replaced,
which lets higher-level registration code refresh an internal record after
re-registering a completer.

.PARAMETER Registration
The registration record to store. The object must expose a non-empty Key
property, a RuntimeKey property, and an IsNative property.

.PARAMETER Table
The managed registration table to write to, as a registration snapshot
carries it in Managed. When it is omitted the module's table is looked up for
this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the record that is stored in the managed registration table.

.EXAMPLE
PS> $record | Add-ManagedCompleterRegistration

Adds a newly created internal registration record to the module state, replacing
any prior record for the same target.
#>
function Add-ManagedCompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $Registration,

        [Parameter()]
        [System.Collections.IDictionary] $Table
    )

    process
    {
        if ($null -eq $Registration.PSObject.Properties['Key'] -or [string]::IsNullOrWhiteSpace([string] $Registration.Key))
        {
            throw 'Registration records must expose a non-empty Key property.'
        }

        try
        {
            $registrations = $Table

            if ($null -eq $registrations)
            {
                $registrations = Get-ManagedCompleterRegistrationTable
            }

            $identity = Get-CompleterTargetIdentity -Target $Registration
            $registrations[$identity] = $Registration

            return $registrations[$identity]
        }
        catch
        {
            throw "Failed to add the managed completer registration '$([string] $Registration.Key)'. $($_.Exception.Message)"
        }
    }
}
<#
.SYNOPSIS
Adds or replaces a runtime completer registration in PowerShell's live dictionaries.

.DESCRIPTION
Writes directly to the runtime completer dictionaries that back TabExpansion2. The
helper initializes the relevant dictionary when PowerShell has not created it yet,
which keeps imported and ordinary completer registrations on the same runtime path.

.PARAMETER Target
The completer target or registration object. It must expose RuntimeKey and IsNative.

.PARAMETER ScriptBlock
The completer script block to register.

.PARAMETER Runtime
The CompleterActions.CompleterRuntime object to write through, as a
registration snapshot carries it in RuntimeContext. When it is omitted the
runtime is looked up for this call. When the object's dictionary is null the
helper re-reads it from the execution context first, so a dictionary another
registration created after the snapshot is kept rather than replaced, and
creates one only when the context still has none. Either way the dictionary is
stored on this object, so every later write of the same batch reuses it.
#>
function Add-RuntimeCompleterRegistration
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates the live completer runtime dictionaries on behalf of public commands.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [psobject] $Runtime
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    if ($null -eq $Runtime)
    {
        $Runtime = Get-CompleterRuntime
    }

    $propertyName = if ($Target.IsNative) { 'NativeArgumentCompleters' } else { 'CustomArgumentCompleters' }
    $dictionary = $Runtime.$propertyName

    if ($null -eq $dictionary)
    {
        $runtimeProperty = if ($Target.IsNative) { $Runtime.NativeProperty } else { $Runtime.CustomProperty }
        if ($null -eq $runtimeProperty)
        {
            throw "The current PowerShell runtime does not expose the '$propertyName' completer dictionary."
        }

        $dictionary = $runtimeProperty.GetValue($Runtime.ExecutionContext)
        if ($null -eq $dictionary)
        {
            $dictionary = [System.Collections.Generic.Dictionary[string, scriptblock]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $runtimeProperty.SetValue($Runtime.ExecutionContext, $dictionary)
        }

        $Runtime.$propertyName = $dictionary
    }

    return Set-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $Target.RuntimeKey) -Value $ScriptBlock
}
<#
.SYNOPSIS
Asserts that the PowerShell runtime exposes every internal member CompleterActions needs.

.DESCRIPTION
CompleterActions reaches into non-public PowerShell runtime members to discover and
manage argument completers: the execution context field behind EngineIntrinsics and
the two completer dictionaries that execution context owns.

This probe runs once during module import. It asks the compiled engine access layer
(CompleterActions.Internal.EngineAccess) to resolve all of those members, so an engine
whose internals changed fails with a single terminating error that names the PowerShell
version and the unresolved members, instead of failing deep inside a later
registration or discovery call. On success the resolved handles are kept in module
state for Get-CompleterRuntime.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

.PARAMETER RuntimeExecutionContext
An already resolved execution context object to inspect for the completer
dictionaries. When supplied, the execution context resolution step is skipped. This
is primarily exposed for internal testing of compatibility guards.

.OUTPUTS
None

.EXAMPLE
Assert-CompleterRuntimeCapability

Verifies that the current engine exposes the completer runtime members and throws a
single terminating error when any of them cannot be resolved.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the error
message explicit about both the engine version and the unresolved members so a future
runtime change is diagnosable from the import failure alone.
#>
function Assert-CompleterRuntimeCapability
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics],

        [Parameter()]
        [object] $RuntimeExecutionContext
    )

    try
    {
        $engine = [CompleterActions.Internal.EngineAccess]::Create($EngineIntrinsics, $EngineIntrinsicsType, $RuntimeExecutionContext, $PSVersionTable.PSVersion)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }

    $script:CompleterEngine = $engine
}
<#
.SYNOPSIS
Throws when a completer script does not conform to the strict import grammar.

.DESCRIPTION
Runs Get-CompleterScriptFinding over a completer script and throws one error
that lists every Error finding with its line, column, construct, message, and
hint. Import-CompleterScript runs this gate under the strict tier, both for an
eager import and when a lazy stub loads its script on the first tab press, and
Register-Completer -Lazy runs it on the parse it derives the targets from, so
no strict path executes or registers a script the grammar rejects and every
path reports the same findings as Test-CompleterScript. A conforming script
returns without output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again; Register-Completer -Lazy passes the
parse it also derives the script's targets from.

.OUTPUTS
None
#>
function Assert-CompleterScriptConformance
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    $findings = @(Get-CompleterScriptFinding @PSBoundParameters | Where-Object -Property Severity -EQ -Value 'Error')

    if ($findings.Count -eq 0)
    {
        return
    }

    $findingLines = foreach ($finding in $findings)
    {
        'Line {0}, column {1} ({2}): {3} {4}' -f $finding.Line, $finding.Column, $finding.Construct, $finding.Message, $finding.Hint
    }

    throw "Completer script '$LiteralPath' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings, or import with -Trusted to run the script as-is.$([Environment]::NewLine)$($findingLines -join [Environment]::NewLine)"
}
<#
.SYNOPSIS
Parses the option table out of cleaned help text.

.DESCRIPTION
Reads the text line by line with fixed rules. A line's indent is its count of
leading white-space characters. An option line starts, after its indent, with
a dash and a letter, digit, question mark, or period; with two dashes and a
letter or digit; with a slash and a letter, digit, or question mark; or is two
dashes alone or followed by white space.

While no option section is open, a section opens at a heading-shaped line
that is not a commands heading and whose next non-blank line is an option
line, or at an option line that is not under a commands heading when another
option line at the same indent follows it within its extent. A section with a
heading runs to the line before the next non-blank line indented no deeper
than the heading that is not an option line; one without a heading runs to
the line before the next non-blank line indented less than its first row that
is not an option line. Blank lines end neither.

The section indent is the smallest indent of an option line in the extent.
Rows are the option lines at that indent, and the lines that start with a long
name four columns deeper when no row at the section indent starts with a long
name. A line is under a commands heading while the subcommand parser's
commands section is open on it, unless an option heading has opened a section
since; such a line opens no section without a heading and is never a row.

A row holds names separated by a comma and an optional space, each followed
by at most one dropped placeholder: =TEXT or [=TEXT], a space and <TEXT>, a
space and one all-upper-case or all-lower-case word followed by a comma, two
or more spaces, or the end of the line, or one attached bracket or brace
group. The description is the text after the first run of two or more
spaces, a tab, or ' : ' after the names and placeholders; when that is empty,
the next non-blank line is used if it is deeper than the row and is not a
row. Descriptions are cleaned as subcommand descriptions are, and an empty
one becomes the name. Each name gives one row, in help order; a name already
seen, compared ordinally, is dropped.

.PARAMETER Text
Help text already cleaned by ConvertTo-CompleterCleanHelpText.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function ConvertFrom-CompleterHelpOption
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Copies of the locals of ConvertFrom-CompleterHelpText.ps1 (lines 34 to 40).
    # They decide what a heading and a commands heading are, and where a
    # commands section ends, exactly as the subcommand parser does. Keep the
    # two copies equal.
    $headerPattern = [regex]::new('^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$')
    $entryPattern = [regex]::new('^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$')
    $underlinePattern = [regex]::new('^\s*(?:=+|-+)\s*$')
    $headerWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('command', 'commands', 'subcommand', 'subcommands'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $optionLinePattern = [regex]::new('^(?:-[A-Za-z0-9?.]|--[A-Za-z0-9]|/[A-Za-z0-9?]|--(?:\s|$))')
    $longNamePattern = [regex]::new('^--[A-Za-z0-9]')
    $namePattern = [regex]::new('\G(?:--[A-Za-z0-9][A-Za-z0-9_-]*|-[A-Za-z0-9?.][A-Za-z0-9_-]*|/[A-Za-z0-9?]+)')
    $placeholderPattern = [regex]::new('\G(?:\[?=[^\s,]*| <[^>]*>| (?:[A-Z][A-Z0-9_-]*|[a-z][a-z0-9_-]*)(?=,| {2,}|\s*$)|\[[^\]]*\]|\{[^}]*\})')
    $listPattern = [regex]::new('\G, ?')
    $separatorPattern = [regex]::new(' {2,}|\t| : ')
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    $lines = $Text.Split("`n")
    $count = $lines.Length
    $isBlank = [bool[]]::new($count)
    $isOption = [bool[]]::new($count)
    $indent = [int[]]::new($count)
    $trimmedLines = [string[]]::new($count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $trimmed = $lines[$index].TrimStart()
        $trimmedLines[$index] = $trimmed
        $isBlank[$index] = [string]::IsNullOrWhiteSpace($trimmed)
        $indent[$index] = $lines[$index].Length - $trimmed.Length
        $isOption[$index] = $optionLinePattern.IsMatch($trimmed)
    }

    # First pass: which lines are under a commands heading, and which section
    # each line belongs to (-1 for none).
    $underCommands = [bool[]]::new($count)
    $sectionOf = [int[]]::new($count)
    [System.Array]::Fill($sectionOf, -1)
    $sectionIndents = [System.Collections.Generic.List[int]]::new()
    $inCommands = $false
    $commandsIndent = -1
    $sectionEnd = -1

    for ($index = 0; $index -lt $count; $index++)
    {
        $line = $lines[$index]

        # Follow the subcommand parser's commands section, so a line it reads
        # stays its own and no option section opens inside it.
        $isHeading = $false
        $isCommandsHeading = $false
        $header = $headerPattern.Match($line)
        if ($header.Success)
        {
            $isHeading = $true
            foreach ($word in $header.Groups['words'].Value.Split(' '))
            {
                if ($headerWords.Contains($word.Trim('(', ')', ',')))
                {
                    $isCommandsHeading = $true
                    break
                }
            }
        }

        if ($isCommandsHeading)
        {
            $inCommands = $true
            $commandsIndent = -1
        }
        elseif ($inCommands)
        {
            if ($isBlank[$index])
            {
                if ($commandsIndent -ge 0)
                {
                    $inCommands = $false
                }
            }
            elseif ($commandsIndent -lt 0)
            {
                if ($underlinePattern.IsMatch($line))
                {
                    $underCommands[$index] = $true
                }
                else
                {
                    $entry = $entryPattern.Match($line)
                    if ($entry.Success)
                    {
                        $commandsIndent = $entry.Groups['indent'].Length
                        $underCommands[$index] = $true
                    }
                    else
                    {
                        $inCommands = $false
                    }
                }
            }
            else
            {
                $entryIndent = $line.Length - $line.TrimStart(' ', "`t").Length
                if ($entryIndent -lt $commandsIndent -and $entryPattern.IsMatch($line))
                {
                    $inCommands = $false
                }
                else
                {
                    $underCommands[$index] = $true
                }
            }
        }

        if ($sectionEnd -lt $index)
        {
            $first = -1
            if ($isHeading -and -not $isCommandsHeading)
            {
                $next = $index + 1
                while ($next -lt $count -and $isBlank[$next])
                {
                    $next++
                }

                if ($next -lt $count -and $isOption[$next])
                {
                    $end = $index + 1
                    while ($end -lt $count -and ($isBlank[$end] -or $indent[$end] -gt $indent[$index] -or $isOption[$end]))
                    {
                        $end++
                    }

                    $first = $index + 1
                    $sectionEnd = $end - 1
                    $inCommands = $false
                }
            }
            elseif ($isOption[$index] -and -not $underCommands[$index])
            {
                $paired = $false
                $end = $index + 1
                while ($end -lt $count -and ($isBlank[$end] -or $indent[$end] -ge $indent[$index] -or $isOption[$end]))
                {
                    if ($isOption[$end] -and $indent[$end] -eq $indent[$index])
                    {
                        $paired = $true
                    }

                    $end++
                }

                if ($paired)
                {
                    $first = $index
                    $sectionEnd = $end - 1
                }
            }

            if ($first -ge 0)
            {
                $sectionIndent = [int]::MaxValue
                for ($row = $first; $row -le $sectionEnd; $row++)
                {
                    if ($isOption[$row] -and $indent[$row] -lt $sectionIndent)
                    {
                        $sectionIndent = $indent[$row]
                    }
                }

                $sectionIndents.Add($sectionIndent)
                for ($row = $first; $row -le $sectionEnd; $row++)
                {
                    $sectionOf[$row] = $sectionIndents.Count - 1
                }
            }
        }
    }

    # A section has a long row when one of its rows at the section indent
    # starts with a long name; a bare -- and a line under commands are not rows.
    $hasLongRow = [bool[]]::new($sectionIndents.Count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $section = $sectionOf[$index]
        if ($section -ge 0 -and $isOption[$index] -and -not $underCommands[$index] -and $indent[$index] -eq $sectionIndents[$section] -and $longNamePattern.IsMatch($trimmedLines[$index]))
        {
            $hasLongRow[$section] = $true
        }
    }

    $isRow = [bool[]]::new($count)
    for ($index = 0; $index -lt $count; $index++)
    {
        $section = $sectionOf[$index]
        if ($section -lt 0 -or -not $isOption[$index] -or $underCommands[$index])
        {
            continue
        }

        $depth = $indent[$index] - $sectionIndents[$section]
        $isRow[$index] = $depth -eq 0 -or ($depth -eq 4 -and -not $hasLongRow[$section] -and $longNamePattern.IsMatch($trimmedLines[$index]))
    }

    for ($index = 0; $index -lt $count; $index++)
    {
        if (-not $isRow[$index])
        {
            continue
        }

        $rowText = $trimmedLines[$index]
        $names = [System.Collections.Generic.List[string]]::new()
        $position = 0
        $name = $namePattern.Match($rowText, 0)
        while ($name.Success)
        {
            $names.Add($name.Value)
            $position = $name.Index + $name.Length
            $placeholder = $placeholderPattern.Match($rowText, $position)
            if ($placeholder.Success)
            {
                $position += $placeholder.Length
            }

            $comma = $listPattern.Match($rowText, $position)
            if (-not $comma.Success)
            {
                break
            }

            $name = $namePattern.Match($rowText, $comma.Index + $comma.Length)
        }

        if ($names.Count -eq 0)
        {
            continue
        }

        $description = ''
        $separator = $separatorPattern.Match($rowText, $position)
        if ($separator.Success)
        {
            $description = $rowText.Substring($separator.Index + $separator.Length)
        }

        if ([string]::IsNullOrWhiteSpace($description))
        {
            $next = $index + 1
            while ($next -lt $count -and $isBlank[$next])
            {
                $next++
            }

            if ($next -lt $count -and $indent[$next] -gt $indent[$index] -and -not $isRow[$next])
            {
                $description = $trimmedLines[$next]
            }
        }

        $description = [regex]::Replace($description, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', ' ')
        $description = [regex]::Replace($description, '\s+', ' ').Trim()

        foreach ($optionName in $names)
        {
            if (-not $seen.Add($optionName))
            {
                continue
            }

            $rowDescription = $description
            if ($rowDescription.Length -eq 0)
            {
                $rowDescription = $optionName
            }

            [pscustomobject] [ordered] @{
                Name        = $optionName
                Description = $rowDescription
            }
        }
    }
}
<#
.SYNOPSIS
Decodes the bytes a help probe captured into text.

.DESCRIPTION
Applies the help decoding steps in order. Bytes that start with the UTF-16 LE
byte-order mark FF FE, or that contain U+0000 when decoded leniently as UTF-8,
are decoded as UTF-16 LE. Otherwise the bytes are decoded as strict UTF-8,
after skipping a UTF-8 byte-order mark. When strict UTF-8 fails, Windows
decodes with the OEM code page of the current culture and Linux and macOS
decode with Latin-1 (code page 28591). A leading U+FEFF left by any decoder is
removed last. The text is not cleaned; ConvertTo-CompleterCleanHelpText does
that.

.PARAMETER Bytes
The captured bytes of one output stream.

.OUTPUTS
System.String
#>
function ConvertFrom-CompleterHelpOutput
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]] $Bytes
    )

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE)
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    elseif ([System.Text.Encoding]::UTF8.GetString($Bytes).Contains([char] 0))
    {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    }
    else
    {
        $offset = 0
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
        {
            $offset = 3
        }

        try
        {
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
        catch [System.Text.DecoderFallbackException]
        {
            $codePage = if ($IsWindows)
            {
                [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            }
            else
            {
                28591
            }

            $text = [System.Text.Encoding]::GetEncoding($codePage).GetString($Bytes, $offset, $Bytes.Length - $offset)
        }
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF)
    {
        $text = $text.Substring(1)
    }

    $text
}
<#
.SYNOPSIS
Parses the subcommand table out of cleaned help text.

.DESCRIPTION
Reads the text line by line with fixed rules. A section header is a whole line
of one to six words, optionally wrapped in angle brackets and followed by a
colon, one of which is command, commands, subcommand, or subcommands. After a
header, blank and underline lines are skipped and the first entry fixes the
section's indentation; any other line before the first entry ends the
section. Entries at that indentation are kept; deeper lines are
continuations and other non-entry lines are skipped. A blank line, a header,
or a shallower entry ends the section. Names keep help order and are
de-duplicated case-insensitively. Control, format, and line and paragraph
separator characters in a description become spaces, whitespace runs
collapse, and an empty description becomes the name.

.PARAMETER Text
Help text already cleaned by ConvertTo-CompleterCleanHelpText.

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function ConvertFrom-CompleterHelpText
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $headerPattern = [regex]::new('^\s*<?(?<words>[A-Za-z(),]+(?: [A-Za-z(),]+){0,5})>?:?\s*$')
    $entryPattern = [regex]::new('^(?<indent>[ \t]*)(?<name>/?[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\*?(?:,\s*[A-Za-z0-9][A-Za-z0-9._-]*)*(?<sep>\s*:\s+|-{2,}| - |\t| {2,})(?<desc>.*)$')
    $underlinePattern = [regex]::new('^\s*(?:=+|-+)\s*$')
    $headerWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('command', 'commands', 'subcommand', 'subcommands'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $inSection = $false
    $sectionIndent = -1

    foreach ($line in $Text.Split("`n"))
    {
        $header = $headerPattern.Match($line)
        if ($header.Success)
        {
            $isHeader = $false
            foreach ($word in $header.Groups['words'].Value.Split(' '))
            {
                if ($headerWords.Contains($word.Trim('(', ')', ',')))
                {
                    $isHeader = $true
                    break
                }
            }

            if ($isHeader)
            {
                $inSection = $true
                $sectionIndent = -1
                continue
            }
        }

        if (-not $inSection)
        {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line))
        {
            if ($sectionIndent -ge 0)
            {
                $inSection = $false
            }

            continue
        }

        if ($sectionIndent -lt 0)
        {
            if ($underlinePattern.IsMatch($line))
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                $inSection = $false
                continue
            }

            $sectionIndent = $entry.Groups['indent'].Length
        }
        else
        {
            $indent = $line.Length - $line.TrimStart(' ', "`t").Length
            if ($indent -gt $sectionIndent)
            {
                continue
            }

            $entry = $entryPattern.Match($line)
            if (-not $entry.Success)
            {
                continue
            }

            if ($indent -lt $sectionIndent)
            {
                $inSection = $false
                continue
            }
        }

        $name = $entry.Groups['name'].Value
        if (-not $seen.Add($name))
        {
            continue
        }

        $description = [regex]::Replace($entry.Groups['desc'].Value, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', ' ')
        $description = [regex]::Replace($description, '\s+', ' ').Trim()
        if ($description.Length -eq 0)
        {
            $description = $name
        }

        [pscustomobject] [ordered] @{
            Name        = $name
            Description = $description
        }
    }
}
<#
.SYNOPSIS
Removes terminal formatting from help text.

.DESCRIPTION
Applies the help cleaning rules in order: CSI sequences, OSC sequences such as
titles and OSC 8 hyperlinks (only the link text remains), any remaining
two-character escape, backspace overstrikes, and carriage returns. CR LF
becomes LF, and then each line keeps only the text after its last remaining
CR, which removes progress lines. The probe output and -HelpText both go
through this cleaner before parsing. The result uses LF line endings.

.PARAMETER Text
The decoded help text.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterCleanHelpText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $clean = [regex]::Replace($Text, '\e\[[0-9;?]*[ -/]*[@-~]', '')
    $clean = [regex]::Replace($clean, '\e\][^\a\e]*(?:\a|\e\\)', '')
    $clean = [regex]::Replace($clean, '\e[@-_]', '')

    # Removing [^\x08]\x08 until stable and then any remaining \x08 is done in
    # linear time: one regex pass removes the simple overstrikes, then a run of
    # n backspaces erases up to n characters before it, and the backspaces left
    # over are dropped. Pair removal gives the same result in any order.
    $clean = [regex]::Replace($clean, '[^\x08]\x08', '')
    $backspaceRuns = [regex]::Matches($clean, '\x08+')
    if ($backspaceRuns.Count -gt 0)
    {
        $builder = [System.Text.StringBuilder]::new($clean.Length)
        $start = 0
        foreach ($run in $backspaceRuns)
        {
            $null = $builder.Append($clean.Substring($start, $run.Index - $start))
            $builder.Length -= [System.Math]::Min($run.Length, $builder.Length)
            $start = $run.Index + $run.Length
        }

        $null = $builder.Append($clean.Substring($start))
        $clean = $builder.ToString()
    }

    $clean = $clean.Replace("`r`n", "`n")

    $lines = $clean.Split("`n")
    for ($index = 0; $index -lt $lines.Length; $index++)
    {
        $lastReturn = $lines[$index].LastIndexOf("`r")
        if ($lastReturn -ge 0)
        {
            $lines[$index] = $lines[$index].Substring($lastReturn + 1)
        }
    }

    $lines -join "`n"
}
<#
.SYNOPSIS
Makes a value from a file printable for an error message or a finding.

.DESCRIPTION
Replaces each control character, every character of the Unicode category Cc
such as a null character or a line break, with U+FFFD, and cuts a value longer
than 256 characters to its first 256, followed by '...'. A cut that would
leave the first half of a surrogate pair at the end is made one character
earlier. A value of 256 characters or fewer without a control character comes
back unchanged.

.PARAMETER Value
The text to make printable.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterPrintableText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $maximumLength = 256
    $text = $Value

    if ($text.Length -gt $maximumLength)
    {
        $length = if ([char]::IsHighSurrogate($text[$maximumLength - 1])) { $maximumLength - 1 } else { $maximumLength }
        $text = $text.Substring(0, $length) + '...'
    }

    [regex]::Replace($text, '\p{Cc}', [string] [char] 0xFFFD)
}
<#
.SYNOPSIS
Derives the stem that names a generated completer script's state and function.

.DESCRIPTION
Drops one trailing .exe, .cmd, .bat, .ps1, or .com (compared
case-insensitively) from the primary command name, splits the rest on every
character that is not an ASCII letter or digit, upper-cases the first
character of each part with the invariant culture, and joins the parts. 'rg'
and 'rg.exe' give 'Rg', 'DSC' stays 'DSC', and '7z' gives '7z'. When the join
dropped any character other than a trailing .exe, it is followed by '_' and
the first eight lower-case hex digits of the SHA-256 of the UTF-8 name without
a trailing .exe, so names that differ only in punctuation or suffix, such as
'ca-tool' and 'ca_tool', or 'tool', 'tool.cmd', and 'tool.bat', do not share
a stem: 'oh-my-posh' gives 'OhMyPosh_' and eight hex digits, and 'npm.cmd'
gives 'Npm_' and eight hex digits. Only .exe is dropped without a hash,
because a bare name registers its .exe form too. An empty
join is returned as is, for ConvertTo-CompleterTargetName to reject. The
script names $script:<Stem>CompletionCatalog and Complete-<Stem> after it, and
dot-sourced scripts share one scope, so the stem must be distinct per command.

.PARAMETER Name
The primary command name, already checked by ConvertTo-CompleterTargetName.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterScriptStem
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    # 'rg' registers rg.exe too, so only .exe names the same command as the bare name.
    $identity = $Name -replace '(?i)\.exe\z', ''
    $baseName = $Name -replace '(?i)\.(?:exe|cmd|bat|ps1|com)\z', ''

    $parts = [System.Text.RegularExpressions.Regex]::Split($baseName, '[^A-Za-z0-9]+') | Where-Object { $_.Length -gt 0 }
    $stem = -join @($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })

    if ($stem.Length -eq 0 -or $stem.Length -eq $identity.Length)
    {
        return $stem
    }

    # Joining the parts drops the separators and the suffix, so 'ca-tool' and 'ca_tool', or 'tool' and 'tool.cmd', would share one stem.
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($identity))
    '{0}_{1}' -f $stem, [System.Convert]::ToHexString($hash, 0, 4).ToLowerInvariant()
}
<#
.SYNOPSIS
Escapes text for a single-quoted PowerShell string literal.

.DESCRIPTION
Doubles every character PowerShell's tokenizer accepts as a single-quote
delimiter: U+0027, U+2018, U+2019, U+201A, and U+201B. Help text such as
"don't" written with a typographic apostrophe would otherwise end the string.
Every other character is kept as is. The result goes between two U+0027
quotes.

.PARAMETER Value
The text to escape.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterSingleQuotedText
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $escaped = $Value

    foreach ($quote in [char] 0x0027, [char] 0x2018, [char] 0x2019, [char] 0x201A, [char] 0x201B)
    {
        $escaped = $escaped.Replace([string] $quote, [string] $quote + $quote)
    }

    $escaped
}
<#
.SYNOPSIS
Builds the native target list a generated completer script registers.

.DESCRIPTION
Checks every command name before building anything, and throws for the first
name that is not a bare command name: at least one ASCII letter or digit, no
path separators, spaces, quotes, or wildcard characters, no leading '-' or
'.', and no trailing '.' or '-'. A name that passes but whose stem would be
empty, such as '_.exe', whose only letters are its suffix, is then refused
with its own reason, so no function name is ever derived from an empty stem.
The list then follows the -CommandName order.
Each name is written as given, and a name that does not end in .exe, .cmd,
.bat, .ps1, or .com is followed by the same name with .exe appended. Names are
de-duplicated case-insensitively, keeping the first spelling, so 'rg' and
'rg', 'rg.exe' give the same list, and no bare name is derived from a suffixed
one.

.PARAMETER CommandName
The command names, primary name first.

.OUTPUTS
System.String
#>
function ConvertTo-CompleterTargetName
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName
    )

    # The spec's pattern, with \z in place of $ so a trailing newline does not match.
    $commandNamePattern = '^(?=.*[A-Za-z0-9])[A-Za-z0-9_](?:[A-Za-z0-9._+-]*[A-Za-z0-9_+])?\z'

    foreach ($commandNameItem in $CommandName)
    {
        if (-not [System.Text.RegularExpressions.Regex]::IsMatch($commandNameItem, $commandNamePattern))
        {
            throw "'$commandNameItem' is not a command name New-CompleterScript can register. Use the bare command name, without a path, spaces, quotes, or wildcard characters."
        }

        if ([string]::IsNullOrEmpty((ConvertTo-CompleterScriptStem -Name $commandNameItem)))
        {
            throw "The command name '$commandNameItem' has no letter or digit outside its suffix, so no function name can be derived from it."
        }
    }

    $suffixes = '.exe', '.cmd', '.bat', '.ps1', '.com'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetNames = [System.Collections.Generic.List[string]]::new()

    foreach ($commandNameItem in $CommandName)
    {
        $names = @($commandNameItem)
        $hasSuffix = @($suffixes | Where-Object { $commandNameItem.EndsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0

        if (-not $hasSuffix)
        {
            $names += '{0}.exe' -f $commandNameItem
        }

        foreach ($name in $names)
        {
            if ($seen.Add($name))
            {
                $targetNames.Add($name)
            }
        }
    }

    $targetNames.ToArray()
}
<#
.SYNOPSIS
Copies a completer registration record so the copy can leave the module.

.DESCRIPTION
Returns a new CompleterRegistration instance with every property of the input
record. The public commands emit these copies instead of the records stored in
the managed registration table, so a caller that edits an emitted record never
changes module state. The copy is shallow: ScriptBlock and ImportModule still
reference the live script block and its module.

.PARAMETER Registration
The CompleterRegistration record to copy.

.OUTPUTS
CompleterActions.CompleterRegistration
Returns a detached copy of each input record.

.EXAMPLE
PS> Find-ManagedCompleterRegistration -Target $target | Copy-CompleterRegistration

Returns a copy of the managed record for a target that a caller may edit
without changing the managed table.
#>
function Copy-CompleterRegistration
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [CompleterActions.CompleterRegistration[]] $Registration
    )

    process
    {
        foreach ($record in $Registration)
        {
            $copy = [CompleterActions.CompleterRegistration]::new()
            $copy.Key = $record.Key
            $copy.RegistrationKey = $record.RegistrationKey
            $copy.RuntimeKey = $record.RuntimeKey
            $copy.CommandName = $record.CommandName
            $copy.ParameterName = $record.ParameterName
            $copy.IsNative = $record.IsNative
            $copy.CompleterType = $record.CompleterType
            $copy.TargetType = $record.TargetType
            $copy.Source = $record.Source
            $copy.State = $record.State
            $copy.IsManaged = $record.IsManaged
            $copy.IsRuntimeRegistered = $record.IsRuntimeRegistered
            $copy.ScriptPath = $record.ScriptPath
            $copy.Trusted = $record.Trusted
            $copy.LoadError = $record.LoadError
            $copy.ImportModule = $record.ImportModule
            $copy.ScriptBlock = $record.ScriptBlock
            $copy.ScriptText = $record.ScriptText

            $copy
        }
    }
}
<#
.SYNOPSIS
Finds managed completer registrations from module state.

.DESCRIPTION
Returns registration records from the module's in-memory registration table.
Callers can enumerate all records, look up the record of a target or of
another record, or look up a record by command and parameter target details.
Every lookup names the target kind, because a native target and a parameter
target can share a Key; the table is keyed by Get-CompleterTargetIdentity.

.PARAMETER Target
The completer target or registration record whose managed record to retrieve.
It must expose Key and IsNative.

.PARAMETER CommandName
The command or native executable name for the registration target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER Native
Indicates that the lookup target is a native command completer.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns matching CompleterActions.CompleterRegistration records, if found.

.EXAMPLE
PS> Find-ManagedCompleterRegistration -CommandName Get-Widget -ParameterName Name

Looks up the registration record associated with a specific command parameter
target.

.EXAMPLE
PS> Find-ManagedCompleterRegistration

Enumerates every managed registration record currently tracked in module state.
#>
function Find-ManagedCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $registrations = Get-ManagedCompleterRegistrationTable

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        return $registrations.Values
    }

    $lookupTarget = switch ($PSCmdlet.ParameterSetName)
    {
        'Target' { $Target }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
    }

    $identity = Get-CompleterTargetIdentity -Target $lookupTarget

    if (-not $registrations.Contains($identity))
    {
        return
    }

    return $registrations[$identity]
}
<#
.SYNOPSIS
Finds completer registrations from the live PowerShell runtime dictionaries.

.DESCRIPTION
Queries the current session's runtime completer dictionaries and returns
registration records for discovered entries. Maintainers use this helper to
inspect the registrations that PowerShell is actually using, rather than only
the module's cached or intended state.

The lookup can enumerate all discovered registrations, or resolve one
command-parameter or native target, named by its parts or by a target or
record. A lookup searches only the runtime dictionary of the target's kind, so
a native command whose name has the same key as a parameter target, such as
'Get-Thing:Name' and Get-Thing / Name, never resolves to the other's entry.
The record carries the key casing the dictionary stores. Because the
underlying data comes from PowerShell runtime internals, the result represents
the current session only and depends on internal dictionary shapes remaining
stable.

A completer registered with Register-ArgumentCompleter -ParameterName alone,
without -CommandName, sits in the custom dictionary under the bare parameter
name. The module does not manage that target kind, so enumeration skips such
entries with a verbose message and parameter lookups never match them; they
cannot abort discovery of the supported targets.

.PARAMETER Target
The completer target or registration record to look up. It must expose
RuntimeKey and IsNative.

.PARAMETER CommandName
The command or native executable name that identifies the runtime completer
target.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target.

.PARAMETER Native
Indicates that the lookup targets the native completer dictionary.

.OUTPUTS
CompleterActions.CompleterRegistration
System.Collections.Generic.List[object]

.EXAMPLE
Find-RuntimeCompleterRegistration

Enumerates all completer registrations currently exposed by the live PowerShell
runtime for maintainer inspection.

.EXAMPLE
Find-RuntimeCompleterRegistration -CommandName git -Native

Looks up the discovered runtime registration for a native completer target.

.EXAMPLE
Find-RuntimeCompleterRegistration -Target $registration

Looks up the live runtime registration for the target of a managed record, in
the dictionary of that record's kind.

.NOTES
This helper reads PowerShell's live completer dictionaries through
Get-CompleterRuntime, which depends on runtime internals. Treat the discovered
results as implementation details for maintainers, not as a stable public
contract.
#>
function Find-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject], [System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = Get-CompleterRuntime

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        $registrations = [System.Collections.Generic.List[object]]::new()

        if ($null -ne $runtime.NativeArgumentCompleters)
        {
            foreach ($entry in $runtime.NativeArgumentCompleters.GetEnumerator())
            {
                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key) -Native
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered' -State Discovered))
            }
        }

        if ($null -ne $runtime.CustomArgumentCompleters)
        {
            foreach ($entry in $runtime.CustomArgumentCompleters.GetEnumerator())
            {
                if (Test-CompleterParameterOnlyKey -Key ([string] $entry.Key))
                {
                    Write-Verbose -Message "Skipping the parameter-only completer registration '$($entry.Key)': it was registered with Register-ArgumentCompleter -ParameterName without -CommandName, and CompleterActions manages command-parameter and native targets only."
                    continue
                }

                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key)
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered' -State Discovered))
            }
        }

        return $registrations
    }

    $lookupTarget = switch ($PSCmdlet.ParameterSetName)
    {
        'Target' { $Target }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
    }

    $isNative = [bool] $lookupTarget.IsNative
    $dictionary = if ($isNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

    if ($null -eq $dictionary)
    {
        return
    }

    foreach ($entryKey in @($dictionary.Keys))
    {
        if ([string]::Equals([string] $entryKey, [string] $lookupTarget.RuntimeKey, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $storedTarget = if ($isNative) { Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) -Native } else { Resolve-CompleterTarget -RuntimeKey ([string] $entryKey) }

            return New-CompleterRegistrationRecord -Target $storedTarget -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key ([string] $entryKey)) -Source 'Discovered' -State Discovered
        }
    }
}
<#
.SYNOPSIS
Gets the module-scoped completer state table.

.DESCRIPTION
Returns the script-scoped state container used by the module to track managed
completer registrations. The helper initializes the state on first access and
repairs missing top-level members when older or partially constructed state is
encountered during maintenance or tests.

.OUTPUTS
System.Collections.Specialized.OrderedDictionary
Returns the module state dictionary with SchemaVersion and Registrations entries.

.EXAMPLE
PS> $state = Get-CompleterActionState

Retrieves the current in-memory state table so a maintainer can inspect or
update registration bookkeeping during module development.
#>
function Get-CompleterActionState
{
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $stateVariable = Get-Variable -Name 'CompleterActionState' -Scope Script -ErrorAction Ignore

    if ($null -eq $stateVariable)
    {
        $script:CompleterActionState = [ordered]@{
            SchemaVersion = 1
            Registrations = [ordered]@{}
        }

        return $script:CompleterActionState
    }

    if ($null -eq $script:CompleterActionState)
    {
        $script:CompleterActionState = [ordered]@{}
    }

    if ($script:CompleterActionState -isnot [System.Collections.IDictionary])
    {
        throw 'Module state variable ''CompleterActionState'' must be a dictionary-backed object.'
    }

    if (-not $script:CompleterActionState.Contains('SchemaVersion'))
    {
        $script:CompleterActionState['SchemaVersion'] = 1
    }

    if (-not $script:CompleterActionState.Contains('Registrations'))
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($null -eq $script:CompleterActionState['Registrations'])
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($script:CompleterActionState['Registrations'] -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $script:CompleterActionState
}
<#
.SYNOPSIS
Reads the target of a Windows app execution alias.

.DESCRIPTION
Calls CompleterActions.Internal.AppExecutionAlias.GetTarget, which reads the
file's reparse data. An app execution alias is a zero-byte reparse point with
the tag IO_REPARSE_TAG_APPEXECLINK; the third string of its data is the
executable it starts. Nothing is run, and nothing is read on Linux or macOS.

.PARAMETER LiteralPath
The full path of the file to read.

.OUTPUTS
System.String
Returns null when the file is not an app execution alias or its reparse data
cannot be read, the empty string for an alias with no target, and otherwise
the target path as the alias gives it.
#>
function Get-CompleterAppExecutionAliasTarget
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    [CompleterActions.Internal.AppExecutionAlias]::GetTarget($LiteralPath)
}
<#
.SYNOPSIS
Reads a subcommand table by running a program's help.

.DESCRIPTION
Decides what the help probe runs and turns each run's outcome into a table,
warnings, and verbose lines.

An application whose CanRun is false runs nothing; its Warning is returned.
Otherwise the program runs once with -HelpArgument, or with --help when
-HelpArgument is not given. On Windows, without -HelpArgument, /? runs once
more only when the --help run exited, yielded no subcommand, and its cleaned
text has fewer than five non-blank lines; the /? result is then used. No /?
runs after a timeout, a start failure, or held output, so one call returns at
most one warning.

A run that timed out, whose output a descendant held, or that failed to start
gives its warning and an empty table, and adds no probe verbose line, because
the line's exit code, characters, and subcommands describe a run that exited.
For a run that exited, the text is standard output, or standard error when
standard output is empty or whitespace after decoding; the exit code decides
nothing. The text is decoded, cleaned, and parsed with the help text helpers,
and the run adds one probe verbose line.

Warnings and verbose lines are returned as data; this helper writes no
stream.

.PARAMETER Application
The record Resolve-CompleterHelpProbeApplication returned for the primary
name.

.PARAMETER HelpArgument
The one argument to pass. When omitted the probe passes --help, and on
Windows may fall back to /?.

.PARAMETER TimeoutSeconds
The deadline for each run, in seconds.

.OUTPUTS
CompleterActions.CompleterHelpSubcommandResult
Returns a record with Subcommands (the parsed rows, in help order), Argument
(the argument of the last run that exited, whose result was used, or null
when no run exited; a /? run that does not exit leaves it at --help),
Warnings, and VerboseLines.
#>
function Get-CompleterHelpSubcommand
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Application,

        [Parameter()]
        [string] $HelpArgument,

        [Parameter(Mandatory)]
        [double] $TimeoutSeconds
    )

    $subcommands = @()
    $argument = $null
    $warnings = [System.Collections.Generic.List[string]]::new()
    $verboseLines = [System.Collections.Generic.List[string]]::new()

    if (-not $Application.CanRun)
    {
        $warnings.Add($Application.Warning)
    }
    else
    {
        $hasHelpArgument = $PSBoundParameters.ContainsKey('HelpArgument')
        $runArgument = if ($hasHelpArgument) { $HelpArgument } else { '--help' }
        $limit = $TimeoutSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)

        while ($true)
        {
            $result = Invoke-CompleterHelpProcess -FilePath $Application.Path -ArgumentList @($runArgument) -TimeoutSeconds $TimeoutSeconds

            switch ($result.Status)
            {
                'TimedOut'
                {
                    $warnings.Add("'$($Application.Name) $runArgument' did not exit within $limit seconds and was stopped, so its help was not used.")
                }
                'HeldOutput'
                {
                    $warnings.Add("'$($Application.Name) $runArgument' exited but left a process holding its output, so its help was not used.")
                }
                'StartFailed'
                {
                    $warnings.Add("'$($Application.Path)' was not run: $($result.StartError). Pass captured help with -HelpText.")
                }
            }

            if ($result.Status -ne 'Exited')
            {
                break
            }

            $text = ConvertFrom-CompleterHelpOutput -Bytes $result.StandardOutput
            if ([string]::IsNullOrWhiteSpace($text))
            {
                $text = ConvertFrom-CompleterHelpOutput -Bytes $result.StandardError
            }

            $cleanText = ConvertTo-CompleterCleanHelpText -Text $text
            $subcommands = @(ConvertFrom-CompleterHelpText -Text $cleanText)
            $argument = $runArgument
            $verboseLines.Add("Probed '$($Application.Path) $argument': exit $($result.ExitCode), $($text.Length) characters, $($subcommands.Count) subcommands, $($result.ElapsedMilliseconds) ms.")

            $tryFallback = $IsWindows -and -not $hasHelpArgument -and $argument -eq '--help' -and $subcommands.Count -eq 0
            if (-not $tryFallback)
            {
                break
            }

            $nonBlankLines = @($cleanText.Split("`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
            if ($nonBlankLines -ge 5)
            {
                break
            }

            $runArgument = '/?'
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName   = 'CompleterActions.CompleterHelpSubcommandResult'
        Subcommands  = $subcommands
        Argument     = $argument
        Warnings     = $warnings.ToArray()
        VerboseLines = $verboseLines.ToArray()
    }
}
<#
.SYNOPSIS
Returns the capture module Import-CompleterScript ran a script in, when a script block is one the import emitted.

.DESCRIPTION
Import-CompleterScript runs each script in a capture module of its own and
records every script block it emits, with that capture module, the script's
path, and the tier, in the module's CompleterImportedScriptBlocks table, keyed
on the script block object itself. This helper returns the capture module of a
script block the table holds for the given script path and tier, and nothing
otherwise.

That is how the module tells an imported script block from any other. A
record's ImportModule, ScriptPath, SourcePath, and Trusted properties are
claims that any caller can set, so none of them establishes provenance, and
neither does a block's binding: the capture module is public on every
imported record, so a caller can bind a script block of its own to it, but
only the objects the import emitted are in the table. A closure of an imported
block is a new object too. Script paths compare the way the file system does:
ignoring case on Windows and macOS, and ordinally elsewhere.

.PARAMETER ScriptBlock
The script block to look up. A null script block has no capture module.

.PARAMETER ScriptPath
The script the block must have been imported from.

.PARAMETER Trusted
The tier the script must have been imported under.

.OUTPUTS
System.Management.Automation.PSModuleInfo
Returns the capture module, or nothing when the script block is not one the
import emitted for that script under that tier.

.EXAMPLE
PS> Get-CompleterImportModule -ScriptBlock $record.ScriptBlock -ScriptPath $record.ScriptPath -Trusted $record.Trusted

Returns the capture module of an Import-CompleterScript record, or nothing for
a script block that only claims to come from the script.
#>
function Get-CompleterImportModule
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSModuleInfo])]
    param(
        [Parameter()]
        [AllowNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ScriptPath,

        [Parameter()]
        [bool] $Trusted
    )

    if ($null -eq $ScriptBlock -or [string]::IsNullOrEmpty($ScriptPath))
    {
        return
    }

    $importedScript = $null

    if (-not $script:CompleterImportedScriptBlocks.TryGetValue($ScriptBlock, [ref] $importedScript))
    {
        return
    }

    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ([string]::Equals($importedScript.ScriptPath, $ScriptPath, $pathComparison) -and $importedScript.Trusted -eq $Trusted)
    {
        return $importedScript.Module
    }
}
<#
.SYNOPSIS
Reads the Subsystem field of a Windows program's PE header.

.DESCRIPTION
Opens the file with File.OpenRead, reads at most its first 4096 bytes, and
returns the optional header's Subsystem value: 2 for a Windows GUI program, 3
for a Windows console program, and other values for other images. No process
is started to inspect the file.

The reader checks the MZ signature, follows e_lfanew (the Int32 at 0x3C) to
the PE\0\0 signature, checks the optional-header magic (0x10B for PE32, 0x20B
for PE32+), and reads Subsystem as the UInt16 at e_lfanew + 24 + 68, an offset
that is the same in PE32 and PE32+. A file too short for that, a wrong
signature or magic, and any failure to open or read the file, such as an app
execution alias or a file another handle holds exclusively, return null. The
reader never throws.

.PARAMETER LiteralPath
The full path of the file to read.

.OUTPUTS
System.Int32
Returns the Subsystem value, or null when the header cannot be read.
#>
function Get-CompleterPESubsystem
{
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $buffer = [byte[]]::new(4096)
    $count = 0

    try
    {
        $stream = [System.IO.File]::OpenRead($LiteralPath)
        try
        {
            while ($count -lt $buffer.Length)
            {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -eq 0)
                {
                    break
                }

                $count += $read
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }
    catch
    {
        Write-Debug -Message "The program header of '$LiteralPath' could not be read. $($_.Exception.Message)"
        return $null
    }

    if ($count -lt 0x40 -or $buffer[0] -ne 0x4D -or $buffer[1] -ne 0x5A)
    {
        return $null
    }

    $peOffset = [System.BitConverter]::ToInt32($buffer, 0x3C)
    if ($peOffset -lt 0 -or ([long] $peOffset + 94) -gt $count)
    {
        return $null
    }

    if ($buffer[$peOffset] -ne 0x50 -or $buffer[$peOffset + 1] -ne 0x45 -or $buffer[$peOffset + 2] -ne 0 -or $buffer[$peOffset + 3] -ne 0)
    {
        return $null
    }

    $magic = [System.BitConverter]::ToUInt16($buffer, $peOffset + 24)
    if ($magic -ne 0x10B -and $magic -ne 0x20B)
    {
        return $null
    }

    [int] [System.BitConverter]::ToUInt16($buffer, $peOffset + 24 + 68)
}
<#
.SYNOPSIS
Captures the managed registration table and the live runtime completer dictionaries once for a batch of lookups.

.DESCRIPTION
Reads the module's managed registration table and the current session's
runtime completer dictionaries once, and indexes the runtime keys case
insensitively, so that a batch of targets can be reconciled against the
session without reaching into PowerShell internals for each one.
Resolve-CompleterRegistrationState resolves keys against a snapshot, taking
its own when the caller passes none, and Import-CompleterSet takes one
snapshot per set so validating and registering hundreds of targets costs one
runtime read. The snapshot holds references to the live table and
dictionaries: its views describe the session at the moment it was taken and
are meant to be consumed before the same batch writes, and the batch then
writes through its RuntimeContext and Managed table instead of looking them
up again for every target. Parameter-only entries of the
custom dictionary, registered with Register-ArgumentCompleter -ParameterName
alone, are left out of the index because the module does not manage them.

.OUTPUTS
CompleterActions.CompleterRegistrationSnapshot
Returns an object with Managed, the managed registration table, keyed by
Get-CompleterTargetIdentity; Runtime, one view per runtime dictionary, native
first; and RuntimeContext, the CompleterActions.CompleterRuntime object the
views were read from. Each view carries IsNative, the Dictionary, and Keys, a
case-insensitive map from a key to the casing the dictionary stores. A target
resolves only against the view of its own kind, because a native and a
parameter target can share a key.

.EXAMPLE
PS> $snapshot = Get-CompleterRegistrationSnapshot

Captures the session's registrations before resolving a set of targets against
them.
#>
function Get-CompleterRegistrationSnapshot
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $runtime = Get-CompleterRuntime
    $views = @(
        foreach ($view in @(
                @{ IsNative = $true; Dictionary = $runtime.NativeArgumentCompleters },
                @{ IsNative = $false; Dictionary = $runtime.CustomArgumentCompleters }
            ))
        {
            $keys = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            if ($null -ne $view.Dictionary)
            {
                foreach ($entryKey in $view.Dictionary.Keys)
                {
                    if (-not $view.IsNative -and (Test-CompleterParameterOnlyKey -Key ([string] $entryKey)))
                    {
                        continue
                    }

                    $keys[[string] $entryKey] = [string] $entryKey
                }
            }

            [pscustomobject] [ordered] @{
                IsNative   = $view.IsNative
                Dictionary = $view.Dictionary
                Keys       = $keys
            }
        }
    )

    return [pscustomobject] [ordered] @{
        PSTypeName     = 'CompleterActions.CompleterRegistrationSnapshot'
        Managed        = Get-ManagedCompleterRegistrationTable
        Runtime        = $views
        RuntimeContext = $runtime
    }
}
<#
.SYNOPSIS
Gets the current session's completer runtime dictionaries from PowerShell internals.

.DESCRIPTION
Builds the runtime wrapper object from the engine access handles that
Assert-CompleterRuntimeCapability resolved at import: the execution context object
that owns the runtime completer dictionaries and the handles of its two dictionary
properties. Maintainers use this helper when they need authoritative access to the
live CustomArgumentCompleters and NativeArgumentCompleters collections that
Register-ArgumentCompleter populates.

The dictionaries are read through the handles on every call, so a dictionary the
engine creates after import is seen.

This helper depends on non-public PowerShell runtime details. It is therefore
intended only for internal module plumbing.

.OUTPUTS
CompleterActions.CompleterRuntime

.EXAMPLE
Get-CompleterRuntime

Returns the current runtime wrapper object so a maintainer can inspect the live
completer dictionaries during module development or debugging.

.NOTES
This function relies on PowerShell internals rather than a public API. Keep the
error messages explicit so failures are diagnosable when runtime implementation
details change across PowerShell releases.
#>
function Get-CompleterRuntime
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $engine = $script:CompleterEngine

    if ($null -eq $engine -or $null -eq $engine.CustomProperty -or $null -eq $engine.NativeProperty)
    {
        throw 'The current PowerShell runtime does not expose the completer dictionaries expected by CompleterActions.'
    }

    $runtime = [pscustomobject] [ordered] @{
        PSTypeName               = 'CompleterActions.CompleterRuntime'
        ExecutionContext         = $engine.ExecutionContext
        CustomProperty           = $engine.CustomProperty
        CustomArgumentCompleters = $engine.CustomProperty.GetValue($engine.ExecutionContext)
        NativeProperty           = $engine.NativeProperty
        NativeArgumentCompleters = $engine.NativeProperty.GetValue($engine.ExecutionContext)
    }

    return $runtime
}
<#
.SYNOPSIS
Gets a value from a runtime completer dictionary by key.
#>
function Get-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if (-not (Test-CompleterRuntimeDictionaryKey -Dictionary $Dictionary -Key $Key))
    {
        return $null
    }

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    return $Dictionary[$Key]
}
<#
.SYNOPSIS
Parses a completer script and returns its strict-grammar findings.

.DESCRIPTION
Runs the validation shared by Test-CompleterScript and Import-CompleterScript.
A script that fails to parse yields one finding per parse error and is not
checked further; a script that parses is validated against the strict import
grammar by Test-CompleterScriptAst. A conforming script produces no output.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not parsed again, so a caller that also derives the
script's targets from the same parse reads the file once.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Get-CompleterScriptFinding
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    if (-not $PSBoundParameters.ContainsKey('ParseResult'))
    {
        $ParseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    }

    if ($ParseResult.ParseErrors.Count -gt 0)
    {
        foreach ($parseError in $ParseResult.ParseErrors)
        {
            New-CompleterScriptFinding -Path $LiteralPath -Extent $parseError.Extent -Construct 'ParseError' -Message $parseError.Message -Hint 'Fix the syntax error; the completer shape is only checked once the script parses.'
        }

        return
    }

    Test-CompleterScriptAst -Ast $ParseResult.Ast -LiteralPath $LiteralPath
}
<#
.SYNOPSIS
Computes the set file Hash of a completer script's text.

.DESCRIPTION
Returns 'SHA256:' followed by 64 uppercase hexadecimal digits: the SHA-256 of
the script's decoded text after every CR LF pair, and then every remaining lone
CR, is replaced with LF, encoded as UTF-8 without a byte-order mark. The same
script therefore hashes to one value whether it is checked out with CRLF on
Windows or LF on Linux, and whether or not it carries a byte-order mark.

-Text hashes text that is already decoded, such as a parse result's
Ast.Extent.Text, so a caller that has parsed the script does not read it a
second time. -LiteralPath reads the file with File.ReadAllText, which decodes
UTF-8 unless a byte-order mark names another encoding, as PowerShell's parser
does. ReadAllText resolves a relative path against the process directory, so
callers pass a full path.

.PARAMETER Text
The decoded script text to hash.

.PARAMETER LiteralPath
The full path of the script file to read and hash.

.OUTPUTS
System.String
#>
function Get-CompleterScriptHash
{
    [CmdletBinding(DefaultParameterSetName = 'LiteralPath')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        $Text = [System.IO.File]::ReadAllText($LiteralPath)
    }

    $normalizedText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try
    {
        $digest = $sha256.ComputeHash($bytes)
    }
    finally
    {
        $sha256.Dispose()
    }

    'SHA256:' + ([System.BitConverter]::ToString($digest) -replace '-', '')
}
<#
.SYNOPSIS
Parses a completer script file into a reusable AST result.

.DESCRIPTION
Uses PowerShell's parser to read a completer script from disk and returns the
root AST, token stream, and parse errors so higher-level import helpers can
validate the script shape before executing it in a controlled scope. Parse
errors are returned on the result rather than thrown, so callers can report
them as findings. A file that cannot be read yields a single FileReadError.

.PARAMETER LiteralPath
The literal path to the completer script file. Every extent in the result names
it as its file, whether the text is read from disk or from Script.

.PARAMETER Script
The script's command information, already resolved from LiteralPath. When it is
supplied, the text it reads and keeps is parsed instead of the file, so
dot-sourcing the same object afterwards runs exactly the text that was parsed.
Import-CompleterScript passes it so the grammar validates what executes.

.OUTPUTS
CompleterActions.CompleterScriptParseResult
#>
function Get-CompleterScriptParseResult
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.ExternalScriptInfo] $Script
    )

    $tokens = $null
    $parseErrors = $null
    $ast = if (-not $PSBoundParameters.ContainsKey('Script'))
    {
        [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $tokens, [ref] $parseErrors)
    }
    else
    {
        try
        {
            # Reading the ScriptContents property returns $null when the file cannot be read;
            # calling its getter raises the read failure instead.
            [System.Management.Automation.Language.Parser]::ParseInput($Script.get_ScriptContents(), $LiteralPath, [ref] $tokens, [ref] $parseErrors)
        }
        catch
        {
            # Report the failure exactly as ParseFile does: one FileReadError with no position.
            $noPosition = [System.Management.Automation.Language.ScriptPosition]::new($null, 0, 0, $null)
            $readError = [System.Management.Automation.Language.ParseError]::new(
                [System.Management.Automation.Language.ScriptExtent]::new($noPosition, $noPosition),
                'FileReadError',
                ('The file could not be read: {0}.' -f $_.Exception.GetBaseException().Message)
            )

            [System.Management.Automation.Language.Parser]::ParseInput('', $LiteralPath, [ref] $tokens, [ref] $parseErrors)
            $parseErrors = @($readError)
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterScriptParseResult'
        Path        = $LiteralPath
        Ast         = $ast
        Tokens      = @($tokens)
        ParseErrors = @($parseErrors)
    }
}
<#
.SYNOPSIS
Composes the lines of a generated native completer script.

.DESCRIPTION
Returns the skeleton New-CompleterScript writes, one string per line and
without line endings: the two comment lines, Set-StrictMode, one guarded
literal-only state block holding the subcommand table, a Complete-<Stem>
completion function that offers the table in the first argument position, and
one bare script-scope Register-ArgumentCompleter call with a literal
-CommandName list. Every string literal is single-quoted with its quote
characters doubled. The
output names no date, version, or machine path, so the same input always gives
the same lines. The generated code uses four-space indentation and opening
braces on the same line, because it belongs to the author's repository.

.PARAMETER Name
The primary command name, as given. Line 1 names it, and so does line 2 of a
probe-seeded script.

.PARAMETER Stem
The stem from ConvertTo-CompleterScriptStem.

.PARAMETER Target
The target list from ConvertTo-CompleterTargetName.

.PARAMETER Subcommand
The subcommand rows, each with a Name and a Description, in help order. An
empty list writes an empty table and the skeleton line 2.

.PARAMETER SeedKind
Where a non-empty table came from: Probe or HelpText. It picks line 2.

.PARAMETER ProbeArgument
The argument whose output seeded the table. Required with -SeedKind Probe. It
must not contain a line break, which would end the line 2 comment.

.OUTPUTS
System.String
#>
function Get-CompleterScriptSkeleton
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Stem,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Target,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Subcommand,

        [Parameter()]
        [ValidateSet('Probe', 'HelpText')]
        [string] $SeedKind,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('\A[^\r\n]*\z')]
        [string] $ProbeArgument
    )

    $catalogName = '{0}CompletionCatalog' -f $Stem
    $functionName = 'Complete-{0}' -f $Stem

    if ($Subcommand.Count -eq 0)
    {
        $sourceLine = '# Native completer skeleton: add subcommands to the table and options to {0}.' -f $functionName
    }
    elseif ($SeedKind -eq 'Probe' -and $PSBoundParameters.ContainsKey('ProbeArgument'))
    {
        $sourceLine = "# Help-seeded native completer: the subcommand table was read from '{0} {1}' when the script was generated." -f $Name, $ProbeArgument
    }
    elseif ($SeedKind -eq 'HelpText')
    {
        $sourceLine = '# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.'
    }
    else
    {
        throw 'A non-empty subcommand table needs -SeedKind HelpText, or -SeedKind Probe with -ProbeArgument.'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('# {0} tab completion for PowerShell' -f $Name))
    $lines.Add($sourceLine)
    $lines.Add('')
    $lines.Add('Set-StrictMode -Version 2.0')
    $lines.Add('')
    $lines.Add(('if (-not (Get-Variable -Name {0} -Scope Script -ErrorAction Ignore)) {{' -f $catalogName))
    $lines.Add(('    $script:{0} = @{{' -f $catalogName))

    if ($Subcommand.Count -eq 0)
    {
        $lines.Add('        Subcommands = @()')
    }
    else
    {
        $lines.Add('        Subcommands = @(')

        foreach ($row in $Subcommand)
        {
            $lines.Add(("            @{{ Name = '{0}'; Description = '{1}' }}" -f (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Name)), (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Description))))
        }

        $lines.Add('        )')
    }

    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('function {0} {{' -f $functionName))
    $lines.Add('    param(')
    $lines.Add('        [string]$wordToComplete,')
    $lines.Add('        [System.Management.Automation.Language.CommandAst]$commandAst,')
    $lines.Add('        [int]$cursorPosition')
    $lines.Add('    )')
    $lines.Add('')
    $lines.Add('    # Offer subcommands in the first argument position only; extend this function for options and values.')
    $lines.Add('    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })')
    $lines.Add('    if ($precedingElements.Count -gt 1) {')
    $lines.Add('        return')
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add(('    foreach ($subcommand in $script:{0}.Subcommands) {{' -f $catalogName))
    $lines.Add('        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {')
    $lines.Add("            [System.Management.Automation.CompletionResult]::new(`$subcommand.Name, `$subcommand.Name, 'ParameterValue', `$subcommand.Description)")
    $lines.Add('        }')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('Register-ArgumentCompleter -Native -CommandName {0} -ScriptBlock {{' -f (@($Target | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', ')))
    $lines.Add('    param($wordToComplete, $commandAst, $cursorPosition)')
    $lines.Add('')
    $lines.Add(('    {0} -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition' -f $functionName))
    $lines.Add('}')

    $lines.ToArray()
}
<#
.SYNOPSIS
Derives the completer targets a strict-tier script registers without executing it.

.DESCRIPTION
Parses the script once and reads the literal -CommandName, -ParameterName, and
-Native arguments of every script-scope Register-ArgumentCompleter call from
the AST, resolving them into normalized completer targets. Nested script
blocks are not searched: a call inside a completer body or a function does not
run when the script is imported, and skipping them keeps the walk cheap. The
strict import grammar requires those arguments to be literal, so a conforming
script's targets are known without running it, and a script whose arguments
cannot be read statically is reported with the position of the offending
argument. The grammar itself does not run here; it runs through
Import-CompleterScript when the script loads, so registering a script lazily
costs one parse rather than a full conformance walk. Duplicate targets
collapse to one record.

.PARAMETER LiteralPath
The literal path to the completer script file. Error messages name it.

.PARAMETER ParseResult
A parse result of the script from Get-CompleterScriptParseResult. When it is
supplied the script is not read again, so a caller that also needs the
script's text, such as Export-CompleterSet for its Hash, reads the file once.

.OUTPUTS
CompleterActions.CompleterTarget
#>
function Get-CompleterScriptTarget
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [ValidateNotNull()]
        [psobject] $ParseResult
    )

    if (-not $PSBoundParameters.ContainsKey('ParseResult'))
    {
        $ParseResult = Get-CompleterScriptParseResult -LiteralPath $LiteralPath
    }

    if ($ParseResult.ParseErrors.Count -gt 0)
    {
        $parseError = $ParseResult.ParseErrors[0]
        throw "The script '$LiteralPath' does not parse, so its targets cannot be derived. Line $($parseError.Extent.StartLineNumber), column $($parseError.Extent.StartColumnNumber): $($parseError.Message)"
    }

    $registerCommands = @($ParseResult.Ast.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Register-ArgumentCompleter'
            },
            $false
        ))

    $targetsByIdentity = [ordered] @{}

    foreach ($registerCommand in $registerCommands)
    {
        $commandNames = @()
        $parameterNames = @()
        $isNative = $false
        $currentParameter = $null

        foreach ($commandElement in ($registerCommand.CommandElements | Select-Object -Skip 1))
        {
            if ($commandElement -is [System.Management.Automation.Language.CommandParameterAst])
            {
                if ($commandElement.ParameterName -eq 'Native')
                {
                    $isNative = $true
                    $currentParameter = $null
                    continue
                }

                if ($null -eq $commandElement.Argument)
                {
                    $currentParameter = $commandElement.ParameterName
                    continue
                }

                $argumentAst = $commandElement.Argument
                $argumentParameter = $commandElement.ParameterName
            }
            else
            {
                $argumentAst = $commandElement
                $argumentParameter = $currentParameter
            }

            $currentParameter = $null

            if ($argumentParameter -notin 'CommandName', 'ParameterName')
            {
                continue
            }

            try
            {
                $argumentValues = @([string[]] @($argumentAst.SafeGetValue()))
            }
            catch
            {
                throw "The script '$LiteralPath' does not use a literal -$argumentParameter argument at line $($argumentAst.Extent.StartLineNumber), column $($argumentAst.Extent.StartColumnNumber), so its targets cannot be derived without running it. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
            }

            if ($argumentParameter -eq 'CommandName')
            {
                $commandNames += $argumentValues
            }
            else
            {
                $parameterNames += $argumentValues
            }
        }

        $targetParameters = @{
            CommandName = $commandNames
        }

        if ($isNative)
        {
            $targetParameters['Native'] = $true
        }
        else
        {
            $targetParameters['ParameterName'] = $parameterNames
        }

        foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
        {
            $targetsByIdentity[(Get-CompleterTargetIdentity -Target $target)] = $target
        }
    }

    if ($targetsByIdentity.Count -eq 0)
    {
        throw "The script '$LiteralPath' does not call Register-ArgumentCompleter with literal targets, so nothing can be registered lazily. Run Test-CompleterScript to work through the findings, or register it with -Trusted and name the targets."
    }

    return @($targetsByIdentity.Values)
}
<#
.SYNOPSIS
Finds the source positions of a completer set file's entries.

.DESCRIPTION
Walks the parse of a completer set, never evaluating it, and returns the
position of the Entries key and, for each element of the Entries
array, the element's own extent (the entry's @{ for a hashtable) and the
extents of its Path value, Hash key and value, and Targets key.
Test-CompleterSet uses them to point a finding at the part of the set that
needs fixing.

The elements are walked the way Import-CompleterSetDefinition reads them, so
the positions line up with its entry numbers: an Entries array written with
one element per line and one written with commas both work, and a $null
element is skipped because the definition reader drops it before the entries
are numbered.

.PARAMETER Ast
The Ast of the CompleterActions.CompleterSetDefinition that
Import-CompleterSetDefinition returned, the parse of the bytes it read, so the
set file is not read again.

.OUTPUTS
CompleterActions.CompleterSetEntryExtent
Returns one record with EntriesExtent, the extent of the Entries key or of the
whole set when the key cannot be found, and Entries, one record per element
in set order with Extent, PathExtent, HashExtent, and TargetsExtent. An
extent the element does not have is null.
#>
function Get-CompleterSetEntryExtent
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.Ast] $Ast
    )

    # Output of a statement enumerates arrays, as the data reader's @() and
    # pipeline do; the elements of a comma array are not enumerated again.
    $getStatementElement = $null
    $getOutputElement = {
        param($Expression)

        if ($Expression -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            foreach ($element in $Expression.Elements)
            {
                if (-not ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.VariablePath.UserPath -eq 'null'))
                {
                    $element
                }
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            foreach ($statement in $Expression.SubExpression.Statements)
            {
                & $getStatementElement $statement
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ParenExpressionAst])
        {
            & $getStatementElement $Expression.Pipeline
        }
        elseif (-not ($Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and $Expression.VariablePath.UserPath -eq 'null'))
        {
            $Expression
        }
    }
    $getStatementElement = {
        param($Statement)

        if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and
            $Statement.PipelineElements.Count -eq 1 -and
            $Statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst])
        {
            & $getOutputElement $Statement.PipelineElements[0].Expression
        }
        else
        {
            $Statement
        }
    }

    $findKeyValue = {
        param($Hashtable, $Name)

        foreach ($keyValuePair in $Hashtable.KeyValuePairs)
        {
            if ($keyValuePair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $keyValuePair.Item1.Value -eq $Name)
            {
                return $keyValuePair
            }
        }
    }

    $setHashtable = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    $entriesPair = if ($null -ne $setHashtable) { & $findKeyValue $setHashtable 'Entries' }
    $entryExtents = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $entriesPair)
    {
        foreach ($element in @(& $getStatementElement $entriesPair.Item2))
        {
            $pathPair = $null
            $hashPair = $null
            $targetsPair = $null

            if ($element -is [System.Management.Automation.Language.HashtableAst])
            {
                $pathPair = & $findKeyValue $element 'Path'
                $hashPair = & $findKeyValue $element 'Hash'
                $targetsPair = & $findKeyValue $element 'Targets'
            }

            $entryExtents.Add([pscustomobject] [ordered] @{
                    Extent        = $element.Extent
                    PathExtent    = if ($null -ne $pathPair) { $pathPair.Item2.Extent } else { $null }
                    HashExtent    = if ($null -ne $hashPair) { $hashPair.Item2.Extent } else { $null }
                    TargetsExtent = if ($null -ne $targetsPair) { $targetsPair.Item1.Extent } else { $null }
                })
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterSetEntryExtent'
        EntriesExtent = if ($null -ne $entriesPair) { $entriesPair.Item1.Extent } else { $ast.Extent }
        Entries       = $entryExtents.ToArray()
    }
}
<#
.SYNOPSIS
Verifies every entry of one completer set and finds the scripts it does not list.

.DESCRIPTION
The per-entry work Test-CompleterSet and Update-CompleterSet share, so both
judge a set alike. Each entry goes through Resolve-CompleterSetEntry -Verify,
the static phase of an import with the fast path turned off, so a strict
script is parsed once and its current hash and targets come from that one
parse. A trusted script is never parsed; its hash is read from the file.

The duplicate-target check follows import's claiming rule without the session:
entries are walked in set order, an entry with no problem claims its targets,
and a later entry that lists a claimed target gets import's duplicate text as
a DuplicateTarget problem. An entry with a problem, such as a malformed
target, still lists its targets for the check, as import does.

Last, every file under the set's directory that matches -Filter and that no
entry lists, hidden files included, is an unlisted script, compared
case-insensitively on Windows and case-sensitively elsewhere. A folder that
cannot be read stops the scan with a terminating error.

Each record is written as soon as it is made, so a caller in the same
pipeline handles every entry before the scan for unlisted scripts starts.
Every position comes from the parse in SetDefinition, so the set file is not
read again. Nothing here reads or writes the session's registrations or runs a
script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.OUTPUTS
CompleterActions.CompleterSetEntryState
CompleterActions.CompleterSetUnlistedScript
Returns one CompleterActions.CompleterSetEntryState per entry in set order,
with Entry, the record Resolve-CompleterSetEntry -Verify returned, RawEntry,
the entry as the set holds it, DuplicateTargetProblems, the entry's
DuplicateTarget problems as Kind and Message hashtables, and Extent, the
entry's positions from Get-CompleterSetEntryExtent. Then one
CompleterActions.CompleterSetUnlistedScript per unlisted script, sorted by
path, with Path, Message, the UnlistedScript text, and Extent, the position of
the set's Entries key.
#>
function Get-CompleterSetEntryState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Filter
    )

    $extents = Get-CompleterSetEntryExtent -Ast $SetDefinition.Ast
    $pathComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $listedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    $claimedTargets = @{}
    $entryIndex = 0

    foreach ($rawEntry in $SetDefinition.Entries)
    {
        $entryIndex++
        $entry = Resolve-CompleterSetEntry -Entry $rawEntry -Index $entryIndex -SetDirectory $SetDefinition.Directory -Verify
        $duplicateTargetProblems = [System.Collections.Generic.List[hashtable]]::new()

        if ($null -ne $entry.Path)
        {
            $null = $listedPaths.Add($entry.Path)
        }

        # $entry.Targets is the list import checks, so an entry with a problem,
        # such as a malformed target, can still report a duplicate.
        $entryTargets = @($entry.Targets)
        $targetIdentities = @($entryTargets | ForEach-Object { Get-CompleterTargetIdentity -Target $_ })

        for ($targetIndex = 0; $targetIndex -lt $entryTargets.Count; $targetIndex++)
        {
            $targetIdentity = $targetIdentities[$targetIndex]

            if ($claimedTargets.Contains($targetIdentity))
            {
                $duplicateTargetProblems.Add(@{ Kind = 'DuplicateTarget'; Message = "Target '$($entryTargets[$targetIndex].RuntimeKey)' is also listed by entry $($claimedTargets[$targetIdentity])." })
            }
        }

        if ($entry.Problems.Count -eq 0 -and $duplicateTargetProblems.Count -eq 0)
        {
            foreach ($targetIdentity in $targetIdentities)
            {
                $claimedTargets[$targetIdentity] = $entryIndex
            }
        }

        [pscustomobject] [ordered] @{
            PSTypeName              = 'CompleterActions.CompleterSetEntryState'
            Entry                   = $entry
            RawEntry                = $rawEntry
            DuplicateTargetProblems = $duplicateTargetProblems.ToArray()
            Extent                  = $extents.Entries[$entryIndex - 1]
        }
    }

    $unlistedScripts = @(
        Get-ChildItem -LiteralPath $SetDefinition.Directory -Filter $Filter -File -Recurse -Force -ErrorAction Stop |
            Where-Object { -not $listedPaths.Contains($_.FullName) } |
            Sort-Object -Property FullName
    )

    foreach ($unlistedScript in $unlistedScripts)
    {
        [pscustomobject] [ordered] @{
            PSTypeName = 'CompleterActions.CompleterSetUnlistedScript'
            Path       = $unlistedScript.FullName
            Message    = "The script '$($unlistedScript.FullName)' matches '$Filter', but no entry of the set lists it."
            Extent     = $extents.EntriesExtent
        }
    }
}
<#
.SYNOPSIS
Checks one completer set against the scripts on disk and returns its drift findings.

.DESCRIPTION
Runs the checks shared with Import-CompleterSet for every entry of a set that
Import-CompleterSetDefinition has read, and adds the checks only a drift
report needs. Get-CompleterSetEntryState does the per-entry work, which
Update-CompleterSet shares: each entry goes through Resolve-CompleterSetEntry
-Verify, the static phase of an import with the fast path turned off, so a
strict script is parsed once and its current hash and targets come from that
one parse. A trusted script is never parsed; its hash is read from the file.

The static phase's problems become MissingScript, InvalidEntry,
UnreadableTargets, and TargetMismatch findings with import's problem text.
DuplicateTarget follows import's claiming rule without the session: entries
are walked in set order, an entry with no Error finding claims its targets,
and a later entry that lists a claimed target gets import's duplicate text.
The declared Hash is then compared with the script's current hash
(HashMismatch), or reported as MissingHash or InvalidHash. Last, every file
under the set's directory that matches -Filter and that no entry lists, hidden
files included, is an UnlistedScript finding, compared case-insensitively on Windows and
case-sensitively elsewhere.

With Package, the set is a package set, and Get-CompleterSetPackageFinding
adds its PackageLayout findings after every entry's findings and before the
UnlistedScript findings. Without it the findings are exactly the plain set's.
Each finding is written as its entry is checked, so the findings of every
entry, and the PackageLayout findings, are written before a folder that cannot
be read stops the scan for unlisted scripts.

Every position comes from the parse in SetDefinition, so the set file is not
read again. Nothing here reads or writes the session's registrations or runs a
script.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Filter
The file-name pattern of the unlisted-script scan.

.PARAMETER Package
The record Get-CompleterSetPackage returned for the set, when a module
manifest declares it.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the findings in set order, each entry's in the order MissingScript,
InvalidEntry, UnreadableTargets, TargetMismatch, DuplicateTarget,
HashMismatch, MissingHash, InvalidHash, then, for a package set, the
PackageLayout findings, followed by the UnlistedScript findings sorted by
path. Path is the set file for every finding.
#>
function Get-CompleterSetFinding
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Filter,

        [Parameter()]
        [psobject] $Package
    )

    $regenerateHint = 'Regenerate the set with Export-CompleterSet.'
    $hints = @{
        MissingScript     = 'Restore the script or remove the entry, then regenerate the set.'
        InvalidEntry      = 'Fix the entry in the set, or regenerate the set with Export-CompleterSet.'
        UnreadableTargets = 'Run Test-CompleterScript on the script, or mark the entry Trusted and list its targets.'
        TargetMismatch    = 'Regenerate the set with Export-CompleterSet; a strict entry must list every target its script registers.'
    }
    $hints['DuplicateTarget'] = $hints['TargetMismatch']

    $setPath = $SetDefinition.Path
    $entryCount = @($SetDefinition.Entries).Count
    $resolvedEntries = [System.Collections.Generic.List[object]]::new()

    # The states arrive as each entry is checked, so this block writes an entry's
    # findings, and after the last entry the PackageLayout findings, before the
    # scan for unlisted scripts starts.
    Get-CompleterSetEntryState -SetDefinition $SetDefinition -Filter $Filter | ForEach-Object {
        $state = $_

        if ($state.PSObject.TypeNames[0] -eq 'CompleterActions.CompleterSetUnlistedScript')
        {
            New-CompleterScriptFinding -Path $setPath -Extent $state.Extent -Construct 'UnlistedScript' -Severity Warning -Message $state.Message -Hint $regenerateHint
        }
        else
        {
            $entry = $state.Entry
            $rawEntry = $state.RawEntry
            $entryIndex = $entry.Index
            $entryExtent = $state.Extent
            $findings = [System.Collections.Generic.List[object]]::new()

            $entryLabel = if ([string]::IsNullOrWhiteSpace($entry.DeclaredPath)) { "Entry $entryIndex" } else { "Entry $entryIndex ('$($entry.DeclaredPath)')" }
            $entryStart = $entryExtent.Extent
            $pathStart = if ($null -ne $entryExtent.PathExtent) { $entryExtent.PathExtent } else { $entryStart }
            $hashStart = if ($null -ne $entryExtent.HashExtent) { $entryExtent.HashExtent } else { $entryStart }
            $targetsStart = if ($null -ne $entryExtent.TargetsExtent) { $entryExtent.TargetsExtent } else { $entryStart }
            $problemExtents = @{
                MissingScript     = $pathStart
                InvalidEntry      = $entryStart
                UnreadableTargets = $pathStart
                TargetMismatch    = $targetsStart
            }

            foreach ($kind in 'MissingScript', 'InvalidEntry', 'UnreadableTargets', 'TargetMismatch')
            {
                foreach ($problem in @($entry.Problems | Where-Object { $_.Kind -eq $kind }))
                {
                    $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $problemExtents[$kind] -Construct $kind -Message "${entryLabel}: $($problem.Message)" -Hint $hints[$kind]))
                }
            }

            foreach ($problem in $state.DuplicateTargetProblems)
            {
                $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $targetsStart -Construct 'DuplicateTarget' -Message "${entryLabel}: $($problem.Message)" -Hint $hints['DuplicateTarget']))
            }

            if ($rawEntry -is [System.Collections.IDictionary])
            {
                if (-not $rawEntry.Contains('Hash'))
                {
                    $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $entryStart -Construct 'MissingHash' -Severity Warning -Message "${entryLabel}: The entry has no Hash, so a change to its script cannot be detected." -Hint $regenerateHint))
                }
                elseif (-not (Test-CompleterSetHashFormat -Value $entry.DeclaredHash))
                {
                    $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'InvalidHash' -Severity Warning -Message "${entryLabel}: The Hash '$($entry.DeclaredHash)' is not 'SHA256:' followed by 64 hexadecimal digits, so it is ignored." -Hint $regenerateHint))
                }
                elseif ($null -ne $entry.ActualHash -and $entry.ActualHash -ne [string] $entry.DeclaredHash)
                {
                    $findings.Add((New-CompleterScriptFinding -Path $setPath -Extent $hashStart -Construct 'HashMismatch' -Severity Warning -Message "${entryLabel}: The script has changed since the set was written. Declared: $($entry.DeclaredHash). Script: $($entry.ActualHash)." -Hint $regenerateHint))
                }
            }

            $findings
            $resolvedEntries.Add($entry)

            if ($resolvedEntries.Count -eq $entryCount -and $null -ne $Package)
            {
                Get-CompleterSetPackageFinding -SetDefinition $SetDefinition -Package $Package -Entry $resolvedEntries.ToArray()
            }
        }
    }
}
<#
.SYNOPSIS
Words the refusal of a completer set that would be written over the size limit.

.DESCRIPTION
Returns the one text Export-CompleterSet and Update-CompleterSet give when the
set they would write is larger than $script:CompleterSetMaxFileBytes, the
limit Import-CompleterSet and Test-CompleterSet read up to, so both commands
word it alike.

.PARAMETER ByteCount
The size in bytes of the set that would be written.

.OUTPUTS
System.String
#>
function Get-CompleterSetOverLimitMessage
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $ByteCount
    )

    "The set would be $ByteCount bytes, larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files, so Import-CompleterSet could not read it. Export the registrations as several sets. Nothing was written."
}
<#
.SYNOPSIS
Finds the module manifest that declares a completer set, if any.

.DESCRIPTION
Decides whether a completer set is a package set, one whose module manifest
is known, so Test-CompleterSet can check the package layout.

With Module, as Test-CompleterSet -Name gives it, the manifest is the one
Resolve-CompleterSetModule chose. Without it, the candidates are the .psd1
files in the folder above the set file's folder, taken in ordinal order of
file name. The first that reads as data and whose PrivateData.CompleterSet
resolves to the set file is the manifest, so a staged package is recognised
before it is published, whatever its folder is called. A .psd1 that is not
data does not declare the set, and a folder that cannot be listed holds no
manifest. Paths are compared case-insensitively on Windows and macOS and
case-sensitively on Linux.

A declaration that is not a valid file path, because it holds a null
character or, on Windows, is longer than the platform allows, is recorded as a
declaration problem, and the search goes on. Every candidate is read, also
after the manifest is found, so each such manifest in the folder is recorded,
in ordinal order of file name. The reason is 'it is longer than the platform
allows' or the underlying message, as Resolve-CompleterSetEntry words an
entry's Path.

Nothing is imported or run: Import-CompleterDataFile reads each candidate as
data only, under the set file limit, so a .psd1 larger than 128 KB is not
parsed and does not declare the set.

.PARAMETER SetPath
The full path of the completer set file.

.PARAMETER Module
The record Resolve-CompleterSetModule returned for the set.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Name, ManifestPath, ModuleBase (the folder that holds the manifest),
Manifest (the manifest's data), and DeclarationProblems, one record with
ManifestPath and Reason per manifest whose declaration is not a valid file
path, empty with Module. When no manifest declares the set but a declaration
problem was recorded, Name, ManifestPath, ModuleBase, and Manifest are null.
Returns nothing when no manifest declares the set and none was recorded.
#>
function Get-CompleterSetPackage
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SetPath,

        [Parameter()]
        [psobject] $Module
    )

    if ($null -ne $Module)
    {
        return [pscustomobject] [ordered] @{
            Name                = $Module.Name
            ManifestPath        = $Module.ManifestPath
            ModuleBase          = $Module.ModuleBase
            Manifest            = $Module.Manifest
            DeclarationProblems = @()
        }
    }

    $setDirectory = [System.IO.Path]::GetDirectoryName($SetPath)
    $moduleBase = if ([string]::IsNullOrEmpty($setDirectory)) { $null } else { [System.IO.Path]::GetDirectoryName($setDirectory) }

    if ([string]::IsNullOrEmpty($moduleBase))
    {
        return
    }

    try
    {
        $fileNames = [string[]] @(
            foreach ($file in [System.IO.Directory]::EnumerateFiles($moduleBase))
            {
                if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase))
                {
                    [System.IO.Path]::GetFileName($file)
                }
            }
        )
    }
    catch
    {
        return
    }

    [System.Array]::Sort($fileNames, [System.StringComparer]::Ordinal)
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $package = $null
    $declarationProblems = [System.Collections.Generic.List[psobject]]::new()

    foreach ($fileName in $fileNames)
    {
        $manifestPath = [System.IO.Path]::Combine($moduleBase, $fileName)

        try
        {
            $manifestFile = Import-CompleterDataFile -LiteralPath $manifestPath
        }
        catch
        {
            continue
        }

        if ($manifestFile.OverLimit)
        {
            continue
        }

        $manifest = $manifestFile.Data
        $privateData = $manifest['PrivateData']
        $declaredSet = if ($privateData -is [System.Collections.IDictionary]) { $privateData['CompleterSet'] } else { $null }

        if ($declaredSet -isnot [string] -or [string]::IsNullOrWhiteSpace($declaredSet))
        {
            continue
        }

        # A bad declaration in one manifest must not hide the set's own manifest
        # or another bad one, so it is recorded and the search goes on.
        try
        {
            $declaredSetPath = [System.IO.Path]::GetFullPath($declaredSet.Replace('\', '/'), $moduleBase)
        }
        catch [System.IO.PathTooLongException]
        {
            # Its message repeats the whole path, so the reason is worded as the
            # entry rule words it.
            $declarationProblems.Add([pscustomobject] [ordered] @{ ManifestPath = $manifestPath; Reason = 'it is longer than the platform allows' })
            continue
        }
        catch [System.ArgumentException]
        {
            $declarationProblems.Add([pscustomobject] [ordered] @{ ManifestPath = $manifestPath; Reason = $_.Exception.GetBaseException().Message })
            continue
        }

        # A rooted declaration that is a valid path does not declare a set in the
        # package, so it is checked after the bad ones are recorded.
        if ([System.IO.Path]::IsPathRooted($declaredSet))
        {
            continue
        }

        if ($null -eq $package -and [string]::Equals($declaredSetPath, $SetPath, $pathComparison))
        {
            $package = [pscustomobject] [ordered] @{
                Name                = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                ManifestPath        = $manifestPath
                ModuleBase          = $moduleBase
                Manifest            = $manifest
                DeclarationProblems = $null
            }
        }
    }

    if ($null -eq $package)
    {
        if ($declarationProblems.Count -eq 0)
        {
            return
        }

        # No manifest declares the set, so only the bad declarations are reported.
        $package = [pscustomobject] [ordered] @{
            Name                = $null
            ManifestPath        = $null
            ModuleBase          = $null
            Manifest            = $null
            DeclarationProblems = $null
        }
    }

    $package.DeclarationProblems = $declarationProblems.ToArray()
    $package
}
<#
.SYNOPSIS
Checks a package set against the package layout and returns its PackageLayout findings.

.DESCRIPTION
Reports the declaration problems Get-CompleterSetPackage recorded, then runs
the four package-layout checks for a completer set whose module manifest it
found, in this order:

- Error, per declaration problem in the order recorded: a manifest in the
  folder above the set declares a completer set path that is not a valid file
  path. The message names the manifest by its full path, made printable by
  ConvertTo-CompleterPrintableText, and gives the reason. The finding points
  at line 1, column 1 of the set. These rows are written even when no
  manifest declares the set, and then they are the only rows.
- Error, per entry in set order: the entry's Path is fully qualified, or it
  resolves outside the module folder. The folder is compared with a trailing
  separator, case-insensitively on Windows and macOS and case-sensitively on
  Linux. A relative Path that cannot be resolved has no location to compare,
  and its InvalidEntry finding already reports it. The finding points at the
  entry's Path value.
- Error, per other .psd1 in the module folder in ordinal order of file name:
  Publish-PSResource can take that file as the manifest. The message names
  the module folder by its full path and the two files by name. The finding
  points at line 1, column 1 of the set.
- Error: the set file's base name equals the module name, compared
  case-insensitively on every platform, so PSResourceGet can take the set as
  the module manifest when it saves or installs the package. The message
  names the set file and the module. The finding points at line 1, column 1
  of the set.
- Warning: RequiredModules has no hashtable whose ModuleName is
  CompleterActions and whose ModuleVersion or RequiredVersion is 2.2.0 or
  later. The message and hint name the manifest by its full path. The
  finding points at line 1, column 1 of the set.

Path is the set file for every finding. Every position comes from the parse
in SetDefinition, so the set file is not read again. Nothing is imported or
run.

.PARAMETER SetDefinition
The CompleterActions.CompleterSetDefinition that Import-CompleterSetDefinition
returned for the set.

.PARAMETER Package
The record Get-CompleterSetPackage returned for the set.

.PARAMETER Entry
The set's entries as Resolve-CompleterSetEntry returned them, in set order.

.OUTPUTS
CompleterActions.CompleterScriptFinding
Returns the PackageLayout findings in the order above, or nothing.
#>
function Get-CompleterSetPackageFinding
{
    [CmdletBinding()]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $SetDefinition,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Package,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entry
    )

    $setPath = $SetDefinition.Path
    # The parse of the whole set starts at line 1, column 1.
    $extentOne = $SetDefinition.Ast.Extent

    foreach ($declarationProblem in $Package.DeclarationProblems)
    {
        $printableManifestPath = ConvertTo-CompleterPrintableText -Value $declarationProblem.ManifestPath
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The module manifest '$printableManifestPath' declares a completer set path that is not a valid file path: $(([string] $declarationProblem.Reason).TrimEnd('.'))." -Hint "Make PrivateData.CompleterSet in '$printableManifestPath' the path of its set file relative to the manifest's folder, such as 'completers/completers.psd1'."
    }

    # Without a manifest that declares the set there is no package to check.
    if ($null -eq $Package.ManifestPath)
    {
        return
    }

    $moduleBase = $Package.ModuleBase
    $manifestPath = $Package.ManifestPath
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $moduleBasePrefix = $moduleBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $extents = Get-CompleterSetEntryExtent -Ast $SetDefinition.Ast

    foreach ($setEntry in $Entry)
    {
        if ([string]::IsNullOrWhiteSpace($setEntry.DeclaredPath))
        {
            continue
        }

        # Path is null when the entry's Path cannot be resolved, which its
        # InvalidEntry finding already reports.
        if ([System.IO.Path]::IsPathFullyQualified($setEntry.DeclaredPath) -or ($null -ne $setEntry.Path -and -not $setEntry.Path.StartsWith($moduleBasePrefix, $pathComparison)))
        {
            $entryExtent = $extents.Entries[$setEntry.Index - 1]
            $pathExtent = if ($null -ne $entryExtent.PathExtent) { $entryExtent.PathExtent } else { $entryExtent.Extent }
            New-CompleterScriptFinding -Path $setPath -Extent $pathExtent -Construct 'PackageLayout' -Message "Entry $($setEntry.Index) ('$($setEntry.DeclaredPath)'): the script is outside the module folder, so an installed copy of the package does not contain it." -Hint 'Move the script under the folder that holds the set file, then regenerate the set with Export-CompleterSet.'
        }
    }

    $otherManifestNames = [string[]] @(
        foreach ($file in [System.IO.Directory]::EnumerateFiles($moduleBase))
        {
            if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::Equals($file, $manifestPath, $pathComparison))
            {
                [System.IO.Path]::GetFileName($file)
            }
        }
    )
    [System.Array]::Sort($otherManifestNames, [System.StringComparer]::Ordinal)

    $manifestName = [System.IO.Path]::GetFileName($manifestPath)

    foreach ($otherManifestName in $otherManifestNames)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The module folder '$moduleBase' holds '$otherManifestName' beside the module manifest '$manifestName', so Publish-PSResource can take the wrong file as the manifest." -Hint 'Keep the module manifest as the only .psd1 in the module folder; move the set into a subfolder and update PrivateData.CompleterSet.'
    }

    $setName = [System.IO.Path]::GetFileName($setPath)

    if ([string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($setPath), $Package.Name, [System.StringComparison]::OrdinalIgnoreCase))
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Message "The set file '$setName' has the base name of the module '$($Package.Name)', so PSResourceGet can take it as the module manifest when it saves or installs the package." -Hint 'Rename the set file so its base name differs from the module name, for example to completers.psd1, and update PrivateData.CompleterSet.'
    }

    $minimumVersion = [version] '2.2.0'
    $requiresCompleterActions = $false

    foreach ($requiredModule in @($Package.Manifest['RequiredModules']))
    {
        if ($requiredModule -isnot [System.Collections.IDictionary] -or
            -not [string]::Equals([string] $requiredModule['ModuleName'], 'CompleterActions', [System.StringComparison]::OrdinalIgnoreCase))
        {
            continue
        }

        foreach ($versionKey in 'ModuleVersion', 'RequiredVersion')
        {
            $requiredVersion = $null

            if ([version]::TryParse([string] $requiredModule[$versionKey], [ref] $requiredVersion) -and $requiredVersion -ge $minimumVersion)
            {
                $requiresCompleterActions = $true
            }
        }
    }

    if (-not $requiresCompleterActions)
    {
        New-CompleterScriptFinding -Path $setPath -Extent $extentOne -Construct 'PackageLayout' -Severity Warning -Message "The module manifest '$manifestPath' does not require CompleterActions 2.2.0 or later, so installing the package does not install Import-CompleterSet -Name." -Hint "Add @{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' } to RequiredModules in '$manifestPath'."
    }
}
<#
.SYNOPSIS
Returns the string that identifies one completer target, kind included.

.DESCRIPTION
PowerShell keeps native and parameter completers in two runtime dictionaries,
each comparing its keys ordinally ignoring case. A target is therefore its kind
together with its RuntimeKey, the command name of a native completer or
'Command:Parameter' of a parameter completer, and two targets are the same
exactly when the runtime would store them under one entry.

The target's Key cannot stand in for that. It is the RuntimeKey folded to
lowercase, so a native command whose name contains a colon, such as an alias
named 'Get-Thing:Name', has the same Key as the parameter target Get-Thing /
Name, and the folding also merges names the runtime keeps apart: the Kelvin
sign (U+212A) lowercases to the letter k, yet the runtime holds 'Kelvin'
spelled with it and 'kelvin' as two entries.

The identity is the target kind, 'native' or 'parameter', a colon, and the
RuntimeKey with its casing kept. The kind never contains a colon, so the first
colon ends it and an identity of one kind never equals an identity of the
other. Identities compare as the runtime compares its keys, ordinally ignoring
case. A PowerShell hashtable literal, @{} or [ordered] @{}, already compares its
keys that way; any other collection of identities is built with
[System.StringComparer]::OrdinalIgnoreCase, and a single comparison uses
[string]::Equals with OrdinalIgnoreCase. PowerShell's -eq, -contains, and -in
operators compare culture-aware, which treats the Kelvin sign as K, so they are
never used on identities.

.PARAMETER Target
A completer target or registration record. It must expose RuntimeKey and
IsNative.

.OUTPUTS
System.String
Returns the identity, such as 'native:git' or 'parameter:Get-Item:Path'.

.EXAMPLE
PS> Get-CompleterTargetIdentity -Target (Resolve-CompleterTarget -CommandName 'Get-Item' -ParameterName 'Path')

Returns 'parameter:Get-Item:Path'.
#>
function Get-CompleterTargetIdentity
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target
    )

    foreach ($requiredProperty in 'RuntimeKey', 'IsNative')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $kind = if ($Target.IsNative) { 'native' } else { 'parameter' }

    return '{0}:{1}' -f $kind, [string] $Target.RuntimeKey
}
<#
.SYNOPSIS
Gets the managed registration dictionary from module state.

.DESCRIPTION
Returns the dictionary stored in the module state under the Registrations key.
This helper centralizes validation of that member so callers can work with the
registration table without repeating state-shape checks.

.OUTPUTS
System.Collections.IDictionary
Returns the dictionary that stores managed completer registration records by key.

.EXAMPLE
PS> $registrations = Get-ManagedCompleterRegistrationTable

Retrieves the backing registration table before adding, finding, or removing
managed completer records inside module internals.
#>
function Get-ManagedCompleterRegistrationTable
{
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    $state = Get-CompleterActionState
    $registrations = $state['Registrations']

    if ($registrations -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $registrations
}
<#
.SYNOPSIS
Reads a PowerShell data file as data only, within the completer set file limit.

.DESCRIPTION
Reads a completer set file or a module manifest the way
Import-PowerShellDataFile reads a data file, except that the file is read
once, never more than one byte past $script:CompleterSetMaxFileBytes (128 KB),
and a file that holds more is not parsed: the result reports OverLimit, and
the caller words the refusal. The read is the measurement, because the size
the file system reports is 0 for a Windows symbolic link, a procfs file, or a
device, whatever a read of it returns. Opening a named pipe waits until
something writes to it, and the pipe is then read like a file.

The bytes read are decoded as Import-PowerShellDataFile decodes a file, as
UTF-8 unless a byte order mark names another encoding, and parsed. The data is
the first hashtable in the parse, the one Import-PowerShellDataFile takes,
evaluated by Ast.SafeGetValue, the data-only evaluator that cmdlet uses, so an
expression is refused and a script block literal comes back as a ScriptBlock
value that nothing runs. Parse errors, among them input nested too deeply for
the parser, which then returns no parse at all, and a file without a hashtable
throw the cmdlet's error text, as does a value the evaluator refuses.

The limit bounds the bytes parsed and so the parse time, though a malformed
file can still take minutes to refuse. A valid set of 95 KB parsed in 11
milliseconds when the limit was set. The parser's SaveError compares each new
error with every error saved before it, so the time to refuse a malformed file
grows with the square of its syntax errors, and a file can hold about one
error per byte. Measured at the limit: a file that repeats one key on every
line in about 11 bytes took 5.6 seconds (about 12,000 errors), one that
repeats it in 4 bytes 70 seconds (about 33,000), and a file of nothing but
closing parentheses or closing braces, one error per byte, 129 and 171
seconds. A set that Export-CompleterSet writes has no syntax errors.

-Text parses and evaluates text that is already decoded, such as a set that
Update-CompleterSet has rewritten in memory, the same way and with the same
error texts, except that a text without a hashtable is named as text. It reads
nothing and applies no size limit, so OverLimit is always $false.

.PARAMETER LiteralPath
The full path of the data file.

.PARAMETER Text
The decoded text of a data file, parsed instead of a file.

.PARAMETER SkipLimitCheck
Skips the evaluator's hashtable size check, as Import-PowerShellDataFile
-SkipLimitCheck does. The default limits of 500 keys and 5000 syntax nodes
apply otherwise.

.PARAMETER IncludeSource
Adds what was read to the result, so a caller that rewrites the file can
reproduce it: Bytes, the bytes read; Text, their decoded text, the text the
parse positions point into; Encoding, the encoding that decoded them; and
HasPreamble, whether the bytes start with that encoding's byte-order mark,
which the text does not contain.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns OverLimit, which is $true when the file holds more than the limit,
Data, the hashtable the file holds, and Ast, the parse of the bytes read.
Data and Ast are $null when OverLimit is $true. With -IncludeSource the record
also carries Bytes, Text, Encoding, and HasPreamble; Text, Encoding, and
HasPreamble are $null when OverLimit is $true.
#>
function Import-CompleterDataFile
{
    [CmdletBinding(DefaultParameterSetName = 'LiteralPath')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [switch] $SkipLimitCheck,

        [Parameter(ParameterSetName = 'LiteralPath')]
        [switch] $IncludeSource
    )

    $encoding = $null
    $hasPreamble = $null

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        try
        {
            $stream = [System.IO.File]::OpenRead($LiteralPath)

            try
            {
                $bytes = [System.IO.BinaryReader]::new($stream).ReadBytes($script:CompleterSetMaxFileBytes + 1)
            }
            finally
            {
                $stream.Dispose()
            }
        }
        catch [System.Management.Automation.MethodInvocationException]
        {
            throw $_.Exception.InnerException
        }

        if ($bytes.Length -gt $script:CompleterSetMaxFileBytes)
        {
            $result = [pscustomobject] [ordered] @{ OverLimit = $true; Data = $null; Ast = $null }

            if ($IncludeSource)
            {
                $result | Add-Member -NotePropertyMembers ([ordered] @{ Bytes = $bytes; Text = $null; Encoding = $null; HasPreamble = $null })
            }

            return $result
        }

        $reader = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($bytes), [System.Text.UTF8Encoding]::new($false))
        $Text = $reader.ReadToEnd()
        # The reader names the encoding a byte-order mark selected only after it has read.
        $encoding = $reader.CurrentEncoding
        $preamble = $encoding.GetPreamble()
        $hasPreamble = $preamble.Length -gt 0 -and $bytes.Length -ge $preamble.Length -and [System.Linq.Enumerable]::SequenceEqual([byte[]] $preamble, [byte[]] $bytes[0..($preamble.Length - 1)])
    }

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, $LiteralPath, [ref] $null, [ref] $parseErrors)
    # A parser that gives up on input nested too deeply returns no AST, only its error.
    $hashtable = if ($parseErrors.Count -eq 0) { $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false) }

    if ($null -eq $hashtable)
    {
        if ($PSCmdlet.ParameterSetName -eq 'Text')
        {
            throw 'The text could not be parsed as a PowerShell Data File.'
        }

        throw "The file '$LiteralPath' could not be parsed as a PowerShell Data File."
    }

    try
    {
        $data = $hashtable.SafeGetValue($SkipLimitCheck.IsPresent)
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }

    $result = [pscustomobject] [ordered] @{ OverLimit = $false; Data = $data; Ast = $ast }

    if ($IncludeSource)
    {
        $result | Add-Member -NotePropertyMembers ([ordered] @{ Bytes = $bytes; Text = $Text; Encoding = $encoding; HasPreamble = $hasPreamble })
    }

    $result
}
<#
.SYNOPSIS
Executes a completer script in a controlled capture module.

.DESCRIPTION
Creates a temporary dynamic module that shadows Register-ArgumentCompleter so the
target script can run without mutating the live runtime completer tables. Each
captured script block is the script's own block rebound to the capture module,
so helper functions and script state remain available later and the block
keeps its source file: $PSScriptRoot and $PSCommandPath inside the completer
name the script's directory and path, as they do when the script is
dot-sourced. Nothing the script defines is imported out of the capture module:
New-Module would otherwise import its functions and exported aliases into this
module, where a helper could replace a private command or the
Register-ArgumentCompleter cmdlet.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER Script
The script's command information. It is dot-sourced as it is, so the contents it
has already read are what runs, under the same execution policy and #requires
checks as dot-sourcing LiteralPath; the file is not read again.

.OUTPUTS
CompleterActions.CompleterScriptImportSession
#>
function Import-CompleterScriptDefinition
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.ExternalScriptInfo] $Script
    )

    $importModule = $null
    $capturedDefinitions = @()

    try
    {
        # The script is dot-sourced into this module's scope, so the variables the module
        # keeps there carry the reserved __CompleterActions prefix and cannot shadow the
        # script's own state.
        $importModule = New-Module -Name ('CompleterActions.ScriptImport.{0}' -f ([guid]::NewGuid().ToString('N'))) -Function @() -ArgumentList $Script -ScriptBlock {
            param(
                [Parameter(Mandatory)]
                [System.Management.Automation.ExternalScriptInfo] $__CompleterActionsScriptInfo
            )

            $script:__CompleterActionsCapturedDefinitions = [System.Collections.Generic.List[object]]::new()

            function Register-ArgumentCompleter
            {
                [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
                param(
                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $CommandName,

                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $ParameterName,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [switch] $Native,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNull()]
                    [scriptblock] $ScriptBlock
                )

                process
                {
                    # Rebinding the original block to this module keeps its source file, so
                    # $PSScriptRoot and $PSCommandPath inside the completer still name the
                    # script; rebuilding it from text would drop that association.
                    $capturedScriptBlock = $ExecutionContext.SessionState.Module.NewBoundScriptBlock($ScriptBlock)

                    $script:__CompleterActionsCapturedDefinitions.Add(
                        [pscustomobject] [ordered] @{
                            CommandName   = @($CommandName)
                            ParameterName = if ($Native) { @() } else { @($ParameterName) }
                            IsNative      = [bool] $Native
                            ScriptBlock   = $capturedScriptBlock
                        }
                    )
                }
            }

            $null = @(. $__CompleterActionsScriptInfo)
        }

        $capturedDefinitions = @(& $importModule {
                @($script:__CompleterActionsCapturedDefinitions)
            })

        if ($capturedDefinitions.Count -eq 0)
        {
            throw 'The script executed successfully but did not register any completers at script scope.'
        }

        [pscustomobject] [ordered] @{
            PSTypeName  = 'CompleterActions.CompleterScriptImportSession'
            Path        = $LiteralPath
            Module      = $importModule
            Definitions = $capturedDefinitions
        }
    }
    catch
    {
        throw "Failed to execute completer script '$LiteralPath' in the import scope. $($_.Exception.Message)"
    }
}
<#
.SYNOPSIS
Reads a completer set file and checks its top-level shape.

.DESCRIPTION
Reads the .psd1 once and evaluates it as data only, so a set file can never
execute a completer script or anything else. The file must declare Version 1
and a non-empty Entries array; the entries themselves are validated one by one
by Resolve-CompleterSetEntry.

Import-CompleterDataFile does the read: never more than one byte past
$script:CompleterSetMaxFileBytes (128 KB), with a larger file refused before
it is parsed, and with the evaluator Import-PowerShellDataFile uses and the
cmdlet's error text. The read is the measurement, so a symbolic link, a procfs
file whose reported size is 0, or a named pipe is held to the limit too.

The set file is not read by its own path again: the definition carries the
parse, and Test-CompleterSet takes its positions from it, so a set rewritten
during an import or a test cannot change the entries checked or the line and
column of a finding. The module manifests read to find a set by -Name or to
check a packaged set's layout are read by their own paths, held to the same
limit. The scripts the entries name are read by theirs and parsed in full,
because a completer script can be larger than a set. A link can make one of
those paths another name for the set file, and that read then sees the file
as it is at that moment.

The evaluator's hashtable size check is skipped, as Import-PowerShellDataFile
-SkipLimitCheck skips it, because the default limits of 500 keys and 5000
syntax nodes reject an exported set of a few hundred entries. Skipping them
changes nothing else the evaluator accepts. Export-CompleterSet refuses to
write a set over the size limit, so every set it writes reads back.

The limit bounds the bytes parsed and so the parse time, though a malformed
file can still take minutes to refuse; Import-CompleterDataFile gives the
measurements.

.PARAMETER LiteralPath
The literal path to the completer set file.

.PARAMETER IncludeSource
Adds the bytes that were read, their decoded text, the encoding, and whether
the bytes start with its byte-order mark, as Import-CompleterDataFile
-IncludeSource returns them, so Update-CompleterSet rewrites the file from the
one read its checks were made on.

.OUTPUTS
CompleterActions.CompleterSetDefinition
Returns one record with Path and Directory, the set file's full path and
folder, Version, Entries, the set's non-null entries in order, and Ast, the
parse of the bytes that were read. With -IncludeSource the record also carries
Bytes, Text, Encoding, and HasPreamble.
#>
function Import-CompleterSetDefinition
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter()]
        [switch] $IncludeSource
    )

    $file = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop

    if ($file.PSIsContainer)
    {
        throw "Completer sets must be file paths. '$LiteralPath' is a directory."
    }

    if ($file.Extension -ne '.psd1')
    {
        throw "Completer sets must be .psd1 files. Received '$LiteralPath'."
    }

    $dataFile = Import-CompleterDataFile -LiteralPath $file.FullName -SkipLimitCheck -IncludeSource:$IncludeSource

    if ($dataFile.OverLimit)
    {
        throw "Completer set '$($file.FullName)' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets."
    }

    $data = $dataFile.Data
    $version = $data['Version']

    # -eq converts 1 to the type on its left, so $true or [char]1 would equal
    # it and an array would be filtered rather than compared: only a number of
    # one of these exact types is compared with 1. Text is compared ordinally,
    # because string -eq is culture-aware and takes '1' followed by a
    # zero-width space, or an Arabic-Indic one, as equal to '1'.
    $numberTypes = [sbyte], [byte], [int16], [uint16], [int], [uint32], [long], [uint64], [single], [double], [decimal], [bigint]

    $isVersionOne = if ($version -is [string])
    {
        [string]::Equals($version, '1', [System.StringComparison]::Ordinal)
    }
    else
    {
        $null -ne $version -and $version.GetType() -in $numberTypes -and $version -eq 1
    }

    if (-not $isVersionOne)
    {
        throw "Completer set '$($file.FullName)' must declare Version = 1."
    }

    $entries = @()

    if ($data.Contains('Entries'))
    {
        $entries = @($data['Entries'] | Where-Object { $null -ne $_ })
    }

    if ($entries.Count -eq 0)
    {
        throw "Completer set '$($file.FullName)' has no Entries."
    }

    $definition = [pscustomobject] [ordered] @{
        PSTypeName = 'CompleterActions.CompleterSetDefinition'
        Path       = $file.FullName
        Directory  = $file.DirectoryName
        Version    = 1
        Entries    = $entries
        Ast        = $dataFile.Ast
    }

    if ($IncludeSource)
    {
        $definition | Add-Member -NotePropertyMembers ([ordered] @{
                Bytes       = $dataFile.Bytes
                Text        = $dataFile.Text
                Encoding    = $dataFile.Encoding
                HasPreamble = $dataFile.HasPreamble
            })
    }

    $definition
}
<#
.SYNOPSIS
Runs a program once to read its help, under one deadline.

.DESCRIPTION
Starts the program with UseShellExecute off, no window, the arguments in
ArgumentList so no shell parses them, standard input redirected and closed at
once, the temporary directory as the working directory, and the session's
environment plus NO_COLOR=1.

Standard output and standard error are read concurrently as bytes, one
ReadAsync per stream at a time. Each stream keeps its first 1 MiB (1048576
bytes) and keeps draining after that, discarding the rest, so a chatty
program never blocks on a full pipe. The reads are polled from this thread
with Task.WaitAny and a timeout, so no callback runs PowerShell code and no
wait is unbounded.

One deadline, fixed at start, covers the process and both reads. A process
still running at the deadline is killed with its descendants (Kill($true)),
waited for up to 1 second, and its output is dropped: TimedOut. When the
process has exited, the reads get until 1 second later or the deadline,
whichever is earlier; a read still open then means a descendant holds the
pipe, so the streams are closed, Kill($true) is attempted, and the output is
dropped: HeldOutput. An exception from Process.Start gives StartFailed with
the exception's message. Otherwise the result is Exited, with both streams'
bytes and the exit code; the exit code decides nothing here.

This helper writes no warning or verbose stream; its caller turns the status
into messages.

.PARAMETER FilePath
The full path of the program to run.

.PARAMETER ArgumentList
The arguments, each passed as one argument without shell parsing.

.PARAMETER TimeoutSeconds
The deadline in seconds, measured from the start of the run.

.OUTPUTS
CompleterActions.CompleterHelpProcessResult
Returns a record with Status (Exited, TimedOut, HeldOutput, or StartFailed),
ExitCode (null unless Exited), StandardOutput and StandardError (byte arrays,
empty unless Exited), ElapsedMilliseconds, ProcessId (null for StartFailed),
and StartError (the Process.Start exception message, or null).
#>
function Invoke-CompleterHelpProcess
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [ValidateRange(0.001, 3600)]
        [double] $TimeoutSeconds
    )

    $streamCap = 1048576
    $readSize = 65536
    $pollMilliseconds = 50

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $startInfo.Environment['NO_COLOR'] = '1'
    foreach ($argument in $ArgumentList)
    {
        $startInfo.ArgumentList.Add($argument)
    }

    $status = $null
    $exitCode = $null
    $processId = $null
    $startError = $null
    $readers = @()
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = $TimeoutSeconds * 1000

    try
    {
        try
        {
            $null = $process.Start()
        }
        catch
        {
            $exception = $_.Exception
            if ($exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $exception.InnerException)
            {
                $exception = $exception.InnerException
            }

            $status = 'StartFailed'
            $startError = $exception.Message
        }

        if ($null -eq $status)
        {
            $processId = $process.Id
            $process.StandardInput.Close()

            $readers = @(
                foreach ($stream in @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream))
                {
                    $buffer = [byte[]]::new($readSize)
                    [pscustomobject] @{
                        Stream = $stream
                        Buffer = $buffer
                        Data   = [System.IO.MemoryStream]::new()
                        Task   = $stream.ReadAsync($buffer, 0, $readSize)
                        Done   = $false
                    }
                }
            )

            $readDeadline = $deadline
            $exitSeen = $false
            while ($true)
            {
                $pending = @($readers | Where-Object { -not $_.Done })
                if ($pending.Count -eq 0)
                {
                    break
                }

                $now = $stopwatch.Elapsed.TotalMilliseconds
                if (-not $exitSeen -and $process.HasExited)
                {
                    $exitSeen = $true
                    $readDeadline = [System.Math]::Min($now + 1000, $deadline)
                }

                if ($now -ge $readDeadline)
                {
                    $status = if ($exitSeen) { 'HeldOutput' } else { 'TimedOut' }
                    break
                }

                $wait = [int] [System.Math]::Ceiling([System.Math]::Min($readDeadline - $now, $pollMilliseconds))
                $tasks = [System.Threading.Tasks.Task[]] @($pending | ForEach-Object { $_.Task })
                $null = [System.Threading.Tasks.Task]::WaitAny($tasks, $wait)

                foreach ($reader in $pending)
                {
                    if (-not $reader.Task.IsCompleted)
                    {
                        continue
                    }

                    $read = 0
                    if ($reader.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion)
                    {
                        $read = $reader.Task.Result
                    }

                    if ($read -le 0)
                    {
                        $reader.Done = $true
                        continue
                    }

                    $keep = [System.Math]::Min($read, $streamCap - $reader.Data.Length)
                    if ($keep -gt 0)
                    {
                        $reader.Data.Write($reader.Buffer, 0, $keep)
                    }

                    $reader.Task = $reader.Stream.ReadAsync($reader.Buffer, 0, $readSize)
                }
            }

            if ($null -eq $status)
            {
                $remaining = [int] [System.Math]::Max(0, [System.Math]::Ceiling($deadline - $stopwatch.Elapsed.TotalMilliseconds))
                if ($process.WaitForExit($remaining))
                {
                    $status = 'Exited'
                    $exitCode = $process.ExitCode
                }
                else
                {
                    $status = 'TimedOut'
                }
            }

            if ($status -eq 'HeldOutput')
            {
                foreach ($reader in $readers)
                {
                    $reader.Stream.Dispose()
                }
            }

            if ($status -ne 'Exited')
            {
                try
                {
                    $process.Kill($true)
                }
                catch
                {
                    Write-Debug -Message "Stopping process $processId failed. $($_.Exception.Message)"
                }

                if ($status -eq 'TimedOut')
                {
                    $null = $process.WaitForExit(1000)
                }
            }
        }
    }
    finally
    {
        foreach ($reader in $readers)
        {
            $reader.Stream.Dispose()
        }

        $process.Dispose()
    }

    $standardOutput = [byte[]]::new(0)
    $standardError = [byte[]]::new(0)
    if ($status -eq 'Exited')
    {
        $standardOutput = $readers[0].Data.ToArray()
        $standardError = $readers[1].Data.ToArray()
    }

    [pscustomobject] [ordered] @{
        PSTypeName          = 'CompleterActions.CompleterHelpProcessResult'
        Status              = $status
        ExitCode            = $exitCode
        StandardOutput      = $standardOutput
        StandardError       = $standardError
        ElapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        ProcessId           = $processId
        StartError          = $startError
    }
}
<#
.SYNOPSIS
Loads a lazily registered completer script on its first invocation and delegates the call.

.DESCRIPTION
Runs inside the ordinary completer call for a Pending lazy target. It imports
the script recorded on the managed record through Import-CompleterScript, in the
strict or trusted tier the record was registered with, finds the imported script
block for its own target, replaces the runtime dictionary entry with it, and
moves the managed record to Active. Every other Pending record that points at
the same script and tier, and whose runtime entry is still its own stub, is
swapped from the same import so a script that registers several targets is
executed once. Script paths compare the way the file system does, ignoring case
on Windows and macOS and case sensitively elsewhere, so a sibling registered
from another file whose path differs only in case keeps its own script. When
the script registers the same target more than once, the last definition wins
for that target, as it does when the script is dot-sourced and
Register-ArgumentCompleter overwrites the earlier entry. The call that
triggered the load is then delegated to the real script block and its results
are returned.

A load in flight owns its record. The helper tracks the targets it is loading
on the current call stack, so a nested completion for the same target, such as a
script that calls TabExpansion2 for its own command while it loads, returns
nothing instead of starting a second import, and a sibling load never swaps or
fails a record whose own load is still running.

When anything in the load fails, the helper returns nothing, stores the error
message on the managed record as LoadError with State Failed, and removes the
runtime entry for the target, so the completion engine's default completion
applies exactly as it would with no completer registered. When the script
replaced or removed the managed record for its own target before it failed,
for example through Register-Completer -Force or Unregister-Completer, that
newer state is left as it is and no failure is recorded. No error reaches the
host. The helper never hooks key handlers, replaces TabExpansion2, or touches
PSReadLine options.

.PARAMETER Key
The RuntimeKey of the lazy target being invoked, with its casing kept.

.PARAMETER Native
Indicates that the lazy target being invoked is a native command completer.

.PARAMETER ArgumentList
The arguments the completion engine passed to the completer.

.OUTPUTS
System.Management.Automation.CompletionResult
Whatever the loaded completer returns for the delegated call. Nothing when the
load fails.
#>
function Invoke-CompleterLazyStub
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CompletionResult])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [switch] $Native,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ArgumentList = @()
    )

    $callerErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $registration = $null
    $realScriptBlock = $null

    try
    {
        $stubTarget = if ($Native) { Resolve-CompleterTarget -RuntimeKey $Key -Native } else { Resolve-CompleterTarget -RuntimeKey $Key }
        $registration = Find-ManagedCompleterRegistration -Target $stubTarget

        if ($null -eq $registration)
        {
            throw "No managed registration exists for the lazy completer '$Key'."
        }

        if ($registration.State -eq 'Active')
        {
            $realScriptBlock = $registration.ScriptBlock
        }
        else
        {
            if ($registration.State -ne 'Pending')
            {
                throw "The managed registration for '$($registration.RuntimeKey)' is in state '$($registration.State)' and cannot be loaded lazily."
            }

            $identity = Get-CompleterTargetIdentity -Target $registration

            if (-not $script:CompleterLazyLoadsInProgress.Add($identity))
            {
                return
            }

            try
            {
                # Register-ArgumentCompleter lets the last registration for a target
                # win, so a script that registers the same target twice is reduced
                # to its last definition per target before the initiating target is
                # selected and the siblings are swapped from the same collection.
                $importedRegistrationsByIdentity = [ordered] @{}

                foreach ($importedRegistration in @(Import-CompleterScript -LiteralPath $registration.ScriptPath -Trusted:$registration.Trusted))
                {
                    $importedRegistrationsByIdentity[(Get-CompleterTargetIdentity -Target $importedRegistration)] = $importedRegistration
                }

                if (-not $importedRegistrationsByIdentity.Contains($identity))
                {
                    $importedKeys = @($importedRegistrationsByIdentity.Values | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                    throw "The script '$($registration.ScriptPath)' did not register a completer for '$($registration.RuntimeKey)'. It registered: $importedKeys."
                }

                $ownRegistration = $importedRegistrationsByIdentity[$identity]
                $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

                foreach ($importedIdentity in @($importedRegistrationsByIdentity.Keys))
                {
                    $importedRegistration = $importedRegistrationsByIdentity[$importedIdentity]
                    $pendingRegistration = Find-ManagedCompleterRegistration -Target $importedRegistration

                    if ($null -eq $pendingRegistration -or
                        $pendingRegistration.State -ne 'Pending' -or
                        -not [string]::Equals($pendingRegistration.ScriptPath, $registration.ScriptPath, $pathComparison) -or
                        [bool] $pendingRegistration.Trusted -ne [bool] $registration.Trusted -or
                        (-not [string]::Equals($importedIdentity, $identity, [System.StringComparison]::OrdinalIgnoreCase) -and $script:CompleterLazyLoadsInProgress.Contains($importedIdentity)))
                    {
                        continue
                    }

                    $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $pendingRegistration

                    if ($null -eq $runtimeRegistration -or -not [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $pendingRegistration.ScriptBlock))
                    {
                        continue
                    }

                    $null = Add-RuntimeCompleterRegistration -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock
                    $null = Add-ManagedCompleterRegistration -Registration (
                        New-CompleterRegistrationRecord -Target $pendingRegistration -ScriptBlock $importedRegistration.ScriptBlock -Source 'Managed' -ImportModule $importedRegistration.ImportModule -State 'Active' -ScriptPath $pendingRegistration.ScriptPath -Trusted:$pendingRegistration.Trusted
                    )
                }

                $realScriptBlock = $ownRegistration.ScriptBlock
            }
            finally
            {
                $null = $script:CompleterLazyLoadsInProgress.Remove($identity)
            }
        }
    }
    catch
    {
        $loadError = $_.Exception.Message

        try
        {
            # A trusted script can replace or remove its own target before it
            # fails, so the failure is recorded only while the record this call
            # loaded still owns the managed slot.
            if ($null -ne $registration -and [object]::ReferenceEquals((Find-ManagedCompleterRegistration -Target $registration), $registration))
            {
                $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $registration

                if ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($runtimeRegistration.ScriptBlock, $registration.ScriptBlock))
                {
                    $null = Remove-RuntimeCompleterRegistration -Target $registration
                }

                $null = Add-ManagedCompleterRegistration -Registration (
                    New-CompleterRegistrationRecord -Target $registration -ScriptBlock $registration.ScriptBlock -Source 'Managed' -State 'Failed' -ScriptPath $registration.ScriptPath -Trusted:$registration.Trusted -LoadError $loadError
                )
            }
        }
        catch
        {
            Write-Debug -Message "Failed to record the lazy load failure for '$Key'. $($_.Exception.Message)"
        }

        return
    }

    $ErrorActionPreference = $callerErrorActionPreference

    & $realScriptBlock @ArgumentList
}
<#
.SYNOPSIS
Creates the runtime stub registered for a lazy completer target.

.DESCRIPTION
Builds a script block, bound to this module's session state, that hands every
invocation to Invoke-CompleterLazyStub together with the target's runtime key
and kind, which together identify its managed record (see
Get-CompleterTargetIdentity). The stub carries nothing else: the script
path and trust tier live on the managed record, so the stub text is the same
shape for every lazy target and the record stays the single source of truth. Binding through the module's
InvokeCommand is what lets the stub reach the module's private helpers when the
completion engine invokes it.

.PARAMETER Key
The RuntimeKey of the lazy target, with its casing kept.

.PARAMETER Native
Indicates that the lazy target is a native command completer.

.OUTPUTS
System.Management.Automation.ScriptBlock
#>
function New-CompleterLazyStub
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory script block.')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [switch] $Native
    )

    $escapedKey = ConvertTo-CompleterSingleQuotedText -Value $Key

    $nativeArgument = if ($Native) { ' -Native' } else { '' }

    return $ExecutionContext.SessionState.InvokeCommand.NewScriptBlock("Invoke-CompleterLazyStub -Key '$escapedKey'$nativeArgument -ArgumentList `$args")
}
<#
.SYNOPSIS
Creates an internal completer registration record object.

.DESCRIPTION
Builds the CompleterRegistration instance stored in the managed registration table. The helper
copies the required target metadata, derives convenience properties such as
CompleterType and IsManaged, and captures both the script block and its text so
module internals can inspect the registered completer later.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, IsNative, and TargetType properties.

.PARAMETER ScriptBlock
The script block that was or will be registered for the completer target.

.PARAMETER Source
Indicates whether the record originated from module-managed registration or from
runtime discovery.

.PARAMETER ImportModule
Preserves a reference to an imported helper module when a registration originated
from Import-CompleterScript.

.PARAMETER State
Describes how the record relates to the live runtime. 'Active' records describe
a managed registration whose value PowerShell is currently using. 'Discovered'
marks a runtime value that no managed record describes. 'Pending' marks a lazy
registration whose runtime value is still the stub that loads the script on
first use.
'Failed' marks a lazy registration whose script failed to load; its runtime
entry was removed and LoadError holds the reason. 'Stale' marks a managed
record whose stored script no longer matches the runtime because the target
was replaced or removed outside this module. 'Conflicted' marks a discovered
runtime value that shadows a stale managed record for the same target.

.PARAMETER ScriptPath
The completer script the registration came from: the file a lazy registration
loads on first use, or the source of an Import-CompleterScript record.

.PARAMETER Trusted
Indicates that the script is imported through the trusted tier, which
dot-sources it without validating it against the strict import grammar.

.PARAMETER LoadError
The error message from the failed lazy load of a 'Failed' record.

.OUTPUTS
CompleterActions.CompleterRegistration
Returns a CompleterRegistration instance suitable for internal storage.

.EXAMPLE
PS> $record = New-CompleterRegistrationRecord -Target $target -ScriptBlock $scriptBlock

Creates a managed registration record from previously resolved target metadata
before adding it to the in-memory registration table.
#>
function New-CompleterRegistrationRecord
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an in-memory registration object.')]
    [OutputType('CompleterActions.CompleterRegistration')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [ValidateSet('Managed', 'Discovered')]
        [string] $Source = 'Managed',

        [Parameter()]
        [System.Management.Automation.PSModuleInfo] $ImportModule,

        [Parameter()]
        [CompleterActions.CompleterState] $State = 'Active',

        [Parameter()]
        [string] $ScriptPath,

        [Parameter()]
        [switch] $Trusted,

        [Parameter()]
        [string] $LoadError
    )

    foreach ($requiredProperty in 'Key', 'RuntimeKey', 'CommandName', 'ParameterName', 'IsNative', 'TargetType')
    {
        if ($null -eq $Target.PSObject.Properties[$requiredProperty])
        {
            throw "Target is missing required property '$requiredProperty'."
        }
    }

    $registration = [CompleterActions.CompleterRegistration]::new()
    $registration.Key = [string] $Target.Key
    $registration.RegistrationKey = [string] $Target.Key
    $registration.RuntimeKey = [string] $Target.RuntimeKey
    $registration.CommandName = [string] $Target.CommandName
    $registration.ParameterName = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
    $registration.IsNative = [bool] $Target.IsNative
    $registration.CompleterType = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
    $registration.TargetType = [string] $Target.TargetType
    $registration.Source = $Source
    $registration.State = $State
    $registration.IsManaged = $Source -eq 'Managed'
    $registration.IsRuntimeRegistered = $State -notin 'Stale', 'Failed'
    $registration.ScriptPath = if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $null } else { $ScriptPath }
    $registration.Trusted = [bool] $Trusted
    $registration.LoadError = if ([string]::IsNullOrWhiteSpace($LoadError)) { $null } else { $LoadError }
    $registration.ImportModule = $ImportModule
    $registration.ScriptBlock = $ScriptBlock
    $registration.ScriptText = $ScriptBlock.ToString()

    return $registration
}
<#
.SYNOPSIS
Creates a completer script validation finding.

.DESCRIPTION
Builds the CompleterActions.CompleterScriptFinding record shared by
Test-CompleterScript and Import-CompleterScript. Each finding pins one
unsupported construct to a source position and pairs the problem statement with
a hint that describes how to bring the script back inside the strict import
grammar.

.PARAMETER Path
The completer script path the finding belongs to.

.PARAMETER Extent
The script extent of the offending construct. The finding takes its line and
column from the start of the extent.

.PARAMETER Construct
The offending construct type, usually the AST node type name.

.PARAMETER Message
The problem statement.

.PARAMETER Hint
How to change the script so the finding goes away.

.PARAMETER Severity
'Error' for constructs the strict importer rejects, 'Warning' for constructs
that import but should be changed.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function New-CompleterScriptFinding
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a finding object.')]
    [OutputType('CompleterActions.CompleterScriptFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.IScriptExtent] $Extent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Construct,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Hint,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string] $Severity = 'Error'
    )

    [CompleterActions.CompleterScriptFinding] @{
        Path       = $Path
        Line       = $Extent.StartLineNumber
        Column     = $Extent.StartColumnNumber
        Severity   = $Severity
        Construct  = $Construct
        Message    = $Message
        Hint       = $Hint
    }
}
<#
.SYNOPSIS
Creates a completion match record for a tested completer target.

.DESCRIPTION
Builds the CompletionMatch instance that Test-CompleterRegistration returns for
each completion result TabExpansion2 produced. The helper copies the target
metadata and the input that was completed alongside the completion result's
text, list item, result type, and tooltip.

.PARAMETER Target
The resolved completer target metadata object. It must expose the Key,
RuntimeKey, CommandName, ParameterName, and IsNative properties.

.PARAMETER CompletionResult
The completion result returned by TabExpansion2 for the target.

.PARAMETER InputText
The input text that was completed.

.PARAMETER CursorPosition
The cursor position within InputText at which completion ran.

.PARAMETER FromTarget
Indicates that the target's own completer produced the completion result.

.OUTPUTS
CompleterActions.CompletionMatch
Returns a CompletionMatch instance for one completion result.

.EXAMPLE
PS> New-CompletionMatch -Target $target -CompletionResult $result -InputText 'git che' -CursorPosition 7 -FromTarget

Creates the completion match record for one TabExpansion2 result that the
resolved git native completer target produced.
#>
function New-CompletionMatch
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates a completion match object.')]
    [OutputType('CompleterActions.CompletionMatch')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CompletionResult] $CompletionResult,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InputText,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $CursorPosition,

        [Parameter()]
        [switch] $FromTarget
    )

    [CompleterActions.CompletionMatch] @{
        Key            = [string] $Target.Key
        RuntimeKey     = [string] $Target.RuntimeKey
        CommandName    = [string] $Target.CommandName
        ParameterName  = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative       = [bool] $Target.IsNative
        CompleterType  = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        InputText      = $InputText
        CursorPosition = $CursorPosition
        CompletionText = $CompletionResult.CompletionText
        ListItemText   = $CompletionResult.ListItemText
        ResultType     = $CompletionResult.ResultType
        ToolTip        = $CompletionResult.ToolTip
        FromTarget     = [bool] $FromTarget
    }
}
<#
.SYNOPSIS
Creates a Register-Completer-compatible import object.

.DESCRIPTION
Builds the public object emitted by Import-CompleterScript. The resulting object
captures normalized target metadata plus the imported ScriptBlock object from the
temporary import module so callers can pipe it directly into
Register-Completer -InputObject.

.PARAMETER Target
The normalized completer target metadata.

.PARAMETER ScriptBlock
The imported completer script block.

.PARAMETER SourcePath
The source completer script path.

.PARAMETER ImportModule
The temporary module that owns the imported script block context.

.PARAMETER Trusted
Indicates that the script was imported through the trusted tier, which
dot-sources it without validating it against the strict import grammar.

.OUTPUTS
CompleterActions.ImportedCompleterRegistration
#>
function New-ImportedCompleterRegistration
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only creates an import object.')]
    [OutputType('CompleterActions.ImportedCompleterRegistration')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSModuleInfo] $ImportModule,

        [Parameter()]
        [switch] $Trusted
    )

    [CompleterActions.ImportedCompleterRegistration] @{
        Key             = [string] $Target.Key
        RegistrationKey = [string] $Target.Key
        RuntimeKey      = [string] $Target.RuntimeKey
        CommandName     = [string] $Target.CommandName
        ParameterName   = if ($Target.IsNative) { $null } else { [string] $Target.ParameterName }
        IsNative        = [bool] $Target.IsNative
        Native          = [bool] $Target.IsNative
        CompleterType   = if ($Target.IsNative) { 'Native' } else { 'Parameter' }
        TargetType      = [string] $Target.TargetType
        Source          = 'Imported'
        Trusted         = [bool] $Trusted
        Path            = $SourcePath
        SourcePath      = $SourcePath
        ImportModule    = $ImportModule
        ScriptBlock     = $ScriptBlock
        ScriptText      = $ScriptBlock.ToString()
    }
}
<#
.SYNOPSIS
Removes and returns a value from a runtime completer dictionary by key.
#>
function Remove-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if (-not (Test-CompleterRuntimeDictionaryKey -Dictionary $Dictionary -Key $Key))
    {
        return $null
    }

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        $removedValue = ([System.Collections.IDictionary] $Dictionary)[$Key]
        ([System.Collections.IDictionary] $Dictionary).Remove($Key)
        return $removedValue
    }

    $removedValue = $Dictionary[$Key]
    $null = $Dictionary.Remove($Key)

    return $removedValue
}
<#
.SYNOPSIS
Removes a managed completer registration from module state.

.DESCRIPTION
Deletes a registration record from the module's in-memory registration table and
returns the removed record. Callers name the entry by a target or record, or by
command target details. Every removal names the target kind, because a native
target and a parameter target can share a Key; only the record of the named
kind is removed.

.PARAMETER Target
The completer target or registration record whose managed record to remove.
It must expose Key and IsNative.

.PARAMETER CommandName
The command or native executable name for the registration target.

.PARAMETER ParameterName
The parameter name for a PowerShell command completer target.

.PARAMETER Native
Indicates that the removal target is a native command completer.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the removed CompleterActions.CompleterRegistration record, if one existed.

.EXAMPLE
PS> Remove-ManagedCompleterRegistration -CommandName Get-Widget -ParameterName Name

Removes the managed registration record for a specific command parameter target
and returns the record that was deleted from module state.
#>
function Remove-ManagedCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'Target')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes in-memory module state for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $registrations = Get-ManagedCompleterRegistrationTable
    $removalTarget = switch ($PSCmdlet.ParameterSetName)
    {
        'Target' { $Target }
        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
        }
        'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
    }

    $identity = Get-CompleterTargetIdentity -Target $removalTarget

    if (-not $registrations.Contains($identity))
    {
        return
    }

    $removedRegistration = $registrations[$identity]
    $registrations.Remove($identity)

    return $removedRegistration
}
<#
.SYNOPSIS
Removes a completer registration directly from the live PowerShell runtime.

.DESCRIPTION
Targets the current session's runtime completer dictionaries and removes the
matching discovered registration. Maintainers use this helper when internal
module workflows need to reconcile or replace registrations that already exist
in PowerShell's live runtime state. Only the dictionary of the target's kind is
touched, so removing a parameter target never removes a native entry that
shares its key, and the reverse.

This helper mutates dictionaries reached through PowerShell runtime internals,
not a public management API. It is therefore intentionally private and should
only be used from higher-level module operations that already understand the
runtime caveats and session-scoped effects.

.PARAMETER Target
The completer target or registration record whose runtime entry to remove. It
must expose RuntimeKey and IsNative.

.PARAMETER CommandName
The command or native executable name that identifies the completer target to
remove.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target to remove.

.PARAMETER Native
Indicates that the target to remove is a native completer registration.

.OUTPUTS
CompleterActions.CompleterRegistration

.EXAMPLE
Remove-RuntimeCompleterRegistration -Target $registration

Removes the live runtime entry for the target of a registration record from
the dictionary of that record's kind.

.EXAMPLE
Remove-RuntimeCompleterRegistration -CommandName git -Native

Shows how a native completer registration can be removed from the live runtime
dictionary during internal reconciliation.

.NOTES
This helper changes live session state by removing entries from runtime
dictionaries obtained through reflection-backed helpers. If PowerShell changes
those internals, both the targeting logic and the runtime access helper may need
to be updated together.
#>
function Remove-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'Target')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper removes entries from PowerShell runtime completer dictionaries for higher-level callers.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Target')]
        [ValidateNotNull()]
        [psobject] $Target,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = $null
    $runtimeRegistration = $null
    $removalTarget = $null
    $dictionary = $null

    try
    {
        $removalTarget = switch ($PSCmdlet.ParameterSetName)
        {
            'Target' { $Target }
            'Native'
            {
                if (-not $Native)
                {
                    throw 'Native target resolution requires the -Native switch.'
                }

                Resolve-CompleterTarget -CommandName $CommandName -Native
            }
            'CommandParameter' { Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName }
        }

        $runtimeRegistration = Find-RuntimeCompleterRegistration -Target $removalTarget

        if ($null -eq $runtimeRegistration)
        {
            return
        }

        $runtime = Get-CompleterRuntime
        $dictionary = if ($runtimeRegistration.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
        $null = Remove-CompleterRuntimeDictionaryValue -Dictionary $dictionary -Key $runtimeRegistration.RuntimeKey

        return $runtimeRegistration
    }
    catch
    {
        $targetDescription = if ($null -ne $removalTarget) { $removalTarget.RuntimeKey } else { $CommandName }
        throw "Failed to remove the runtime completer registration '$targetDescription'. $($_.Exception.Message)"
    }
    finally
    {
        $runtime = $null
        $runtimeRegistration = $null
        $removalTarget = $null
        $dictionary = $null
    }
}
<#
.SYNOPSIS
Resolves the program a help probe would run and decides whether it may run.

.DESCRIPTION
Resolves the name with Get-Command -CommandType Application and takes the
first match, so a function, alias, cmdlet, or script of that name is never
chosen. The name is escaped with [WildcardPattern]::Escape, so it is matched
literally: a name with *, ?, or brackets never resolves some other program.
-ErrorAction Ignore keeps a missing command from throwing under
$ErrorActionPreference = 'Stop'. Nothing is run.

On Windows the resolved file may run only when it is a .exe whose PE header
reads as Subsystem 3 (Windows CUI). Any other file gets a reason: a GUI
program (Subsystem 2), another subsystem, an unreadable header, no file
extension, or an extension that only runs through cmd.exe. On Linux and macOS
every resolved application may run.

When the header of a .exe cannot be read, its reparse data is read with
Get-CompleterAppExecutionAliasTarget. An app execution alias may run when its
target is a fully qualified path to an existing .exe whose header reads as
Subsystem 3; the alias is what runs, so Path stays the alias path. An alias
with no target, or whose target does not exist, is not a .exe, has an
unreadable header, or is not a console program, gets a reason that names the
target. A file that is not an alias, or whose reparse data cannot be read,
keeps the unreadable-header reason. The reparse data is never read on Linux
or macOS.

The warning text is returned as data; this helper writes no stream.

.PARAMETER Name
The command name to resolve, as the author gave it.

.OUTPUTS
CompleterActions.CompleterHelpProbeApplication
Returns a record with Name (as given), Path (the resolved file, or null when
nothing was found), CanRun, Warning (the not-found or not-run text, or null
when the application may run), and AliasTarget (the target an app execution
alias names, or null when Path is not an alias or the alias names none).
#>
function Resolve-CompleterHelpProbeApplication
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    $application = Get-Command -Name ([WildcardPattern]::Escape($Name)) -CommandType Application -ErrorAction Ignore | Select-Object -First 1

    $path = $null
    $warning = $null
    $aliasTarget = $null
    if ($null -eq $application)
    {
        $warning = "The command '$Name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand."
    }
    else
    {
        $path = $application.Path
        if ($IsWindows)
        {
            $extension = [System.IO.Path]::GetExtension($path)
            $reason = $null
            if ([string]::Equals($extension, '.exe', [System.StringComparison]::OrdinalIgnoreCase))
            {
                $subsystem = Get-CompleterPESubsystem -LiteralPath $path
                if ($null -eq $subsystem)
                {
                    # An app execution alias is a zero-byte reparse point, so its own header never reads.
                    $target = Get-CompleterAppExecutionAliasTarget -LiteralPath $path
                    if ($null -eq $target)
                    {
                        $reason = 'its program header could not be read'
                    }
                    elseif ($target.Length -eq 0)
                    {
                        $reason = 'it is an app execution alias with no target'
                    }
                    else
                    {
                        $aliasTarget = $target
                        if (-not [System.IO.Path]::IsPathFullyQualified($target) -or -not [System.IO.File]::Exists($target))
                        {
                            $reason = "its target '$target' does not exist"
                        }
                        elseif (-not [string]::Equals([System.IO.Path]::GetExtension($target), '.exe', [System.StringComparison]::OrdinalIgnoreCase))
                        {
                            $reason = "its target '$target' is not a .exe file"
                        }
                        else
                        {
                            $targetSubsystem = Get-CompleterPESubsystem -LiteralPath $target
                            if ($null -eq $targetSubsystem)
                            {
                                $reason = "the program header of its target '$target' could not be read"
                            }
                            elseif ($targetSubsystem -eq 2)
                            {
                                $reason = "its target '$target' is a Windows GUI program"
                            }
                            elseif ($targetSubsystem -ne 3)
                            {
                                $reason = "its target '$target' is not a Windows console program (subsystem $targetSubsystem)"
                            }
                        }
                    }
                }
                elseif ($subsystem -eq 2)
                {
                    $reason = 'it is a Windows GUI program'
                }
                elseif ($subsystem -ne 3)
                {
                    $reason = "it is not a Windows console program (subsystem $subsystem)"
                }
            }
            elseif ($extension.Length -eq 0)
            {
                $reason = 'it has no file extension'
            }
            else
            {
                $reason = "it is a $($extension.ToLowerInvariant()) file, which only runs through cmd.exe"
            }

            if ($null -ne $reason)
            {
                $warning = "'$path' was not run: $reason. Run '$Name --help' yourself and pass the text with -HelpText."
            }
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName  = 'CompleterActions.CompleterHelpProbeApplication'
        Name        = $Name
        Path        = $path
        CanRun      = $null -ne $path -and $null -eq $warning
        Warning     = $warning
        AliasTarget = $aliasTarget
    }
}
<#
.SYNOPSIS
Resolves a pipeline input object into a completer target definition.

.DESCRIPTION
Normalizes public pipeline input into the target metadata used by the module's
registration, lookup, and removal commands. The helper accepts module
registration records and custom objects that expose CommandName with
IsNative/Native or ParameterName, or a Key, RegistrationKey, or RuntimeKey
together with IsNative/Native. An input object describes one target, so a
CommandName or ParameterName that holds several values is rejected rather
than joined into one name. Keys are output-only identifiers, so a key
without a native indicator is rejected rather than classified by its shape.
CommandName names a target exactly, and so does RuntimeKey, which wins when an
object exposes several keys. Key and RegistrationKey are folded to lowercase,
which can merge two names the runtime keeps apart, so an object that names its
target only through one of them resolves through Resolve-CompleterKeyTarget:
to the target of its kind whose runtime key is the key apart from case, with
an error when a registered target of that kind has the key under a name the
lowercasing merged into it.

A ScriptBlock, ScriptPath or SourcePath, and Trusted property are carried
through when present so imported and managed records round-trip into
Register-Completer. An ImportModule property is ignored: the resolved
ImportModule is the capture module Import-CompleterScript ran the script in,
as Get-CompleterImportModule finds it for the script block, ScriptPath, and
tier, and it is null for any script block the import did not emit.

IsNative, Native, and Trusted take a Boolean or switch value, a number, where
zero is false, or the text 'True' or 'False' in any casing, with or without
white space around it, as Export-Csv writes a Boolean, and a null value, or
text that is empty or only white space, counts as false. Any other text, a
collection, or any other kind of object is rejected: a cast to Boolean would
turn the text 'False', or an array of False values, into true and select the
other kind of target, or the trusted tier.

.PARAMETER InputObject
The object to resolve into a completer target.

.PARAMETER RequireScriptBlock
Requires the input object to expose a ScriptBlock property whose value is a
script block.

.OUTPUTS
CompleterActions.ResolvedInputObject

.EXAMPLE
Resolve-CompleterInputObject -InputObject $registration

Resolves a completer registration object returned by Get-Completer
into the normalized target metadata used by the module internals.
#>
function Resolve-CompleterInputObject
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $InputObject,

        [Parameter()]
        [switch] $RequireScriptBlock
    )

    begin
    {
        function ConvertTo-InputObjectBoolean
        {
            param(
                [string] $PropertyName,
                [object] $Value
            )

            if ($null -eq $Value)
            {
                return $false
            }

            if ($Value -is [bool] -or $Value -is [switch] -or $Value -is [System.Numerics.BigInteger])
            {
                return [bool] $Value
            }

            $valueType = $Value.GetType()
            $typeCode = [type]::GetTypeCode($valueType)

            if (-not $valueType.IsEnum -and $typeCode -ge [System.TypeCode]::SByte -and $typeCode -le [System.TypeCode]::Decimal)
            {
                return [bool] $Value
            }

            if ($Value -isnot [string])
            {
                if ($Value -is [System.Collections.IEnumerable])
                {
                    throw "InputObject supplies a collection for $PropertyName, which takes a single Boolean value. Use True or False."
                }

                throw "InputObject supplies a value of type $($valueType.FullName) for $PropertyName, which is not a Boolean value. Use True or False."
            }

            if ([string]::IsNullOrWhiteSpace($Value))
            {
                return $false
            }

            $parsedValue = $false

            if (-not [bool]::TryParse($Value.Trim(), [ref] $parsedValue))
            {
                throw "InputObject supplies '$Value' for $PropertyName, which is not a Boolean value. Use True or False."
            }

            $parsedValue
        }
    }

    process
    {
        $keyValue = $null
        $keyIsRuntimeKey = $false
        $commandName = $null
        $parameterName = $null
        $hasNativeIndicator = $false
        $isNative = $false
        $scriptBlock = $null
        $importModule = $null
        $scriptPath = $null
        $trusted = $false
        $target = $null

        try
        {
            foreach ($propertyName in 'RuntimeKey', 'Key', 'RegistrationKey')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                {
                    $keyValue = [string] $property.Value
                    $keyIsRuntimeKey = $propertyName -eq 'RuntimeKey'
                    break
                }
            }

            foreach ($propertyName in 'CommandName', 'ParameterName')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and @($property.Value).Count -gt 1)
                {
                    throw "InputObject supplies $(@($property.Value).Count) values for $propertyName. An input object describes one target; pass arrays to -CommandName and -ParameterName instead."
                }
            }

            $commandProperty = $InputObject.PSObject.Properties['CommandName']
            if ($null -ne $commandProperty -and -not [string]::IsNullOrWhiteSpace([string] $commandProperty.Value))
            {
                $commandName = [string] $commandProperty.Value
            }

            $parameterProperty = $InputObject.PSObject.Properties['ParameterName']
            if ($null -ne $parameterProperty -and -not [string]::IsNullOrWhiteSpace([string] $parameterProperty.Value))
            {
                $parameterName = [string] $parameterProperty.Value
            }

            foreach ($propertyName in 'IsNative', 'Native')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property)
                {
                    $hasNativeIndicator = $true
                    $isNative = ConvertTo-InputObjectBoolean -PropertyName $propertyName -Value $property.Value
                    break
                }
            }

            $scriptBlockProperty = $InputObject.PSObject.Properties['ScriptBlock']
            if ($null -ne $scriptBlockProperty -and $scriptBlockProperty.Value -is [scriptblock])
            {
                $scriptBlock = [scriptblock] $scriptBlockProperty.Value
            }

            foreach ($propertyName in 'ScriptPath', 'SourcePath')
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                {
                    $scriptPath = [string] $property.Value
                    break
                }
            }

            $trustedProperty = $InputObject.PSObject.Properties['Trusted']
            if ($null -ne $trustedProperty)
            {
                $trusted = ConvertTo-InputObjectBoolean -PropertyName 'Trusted' -Value $trustedProperty.Value
            }

            if ($RequireScriptBlock -and $null -eq $scriptBlock)
            {
                throw 'InputObject must expose a ScriptBlock property whose value is a script block.'
            }

            $importModule = Get-CompleterImportModule -ScriptBlock $scriptBlock -ScriptPath $scriptPath -Trusted $trusted

            if (-not [string]::IsNullOrWhiteSpace($commandName))
            {
                if ($hasNativeIndicator -and $isNative)
                {
                    $target = Resolve-CompleterTarget -CommandName $commandName -Native
                }
                elseif (-not [string]::IsNullOrWhiteSpace($parameterName))
                {
                    $target = Resolve-CompleterTarget -CommandName $commandName -ParameterName $parameterName
                }
                else
                {
                    throw 'InputObject must expose ParameterName for command-parameter targets or IsNative/Native for native targets.'
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($keyValue))
            {
                if (-not $hasNativeIndicator)
                {
                    throw "InputObject supplies the key '$keyValue' without an IsNative or Native property. Keys are output-only identifiers and are no longer classified by their shape: add IsNative or Native alongside the key, or supply CommandName with Native or ParameterName. See about_CompleterActions_Migration."
                }

                if (-not $keyIsRuntimeKey)
                {
                    $target = Resolve-CompleterKeyTarget -Key $keyValue -Native:$isNative
                }
                elseif ($isNative)
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue -Native
                }
                else
                {
                    $target = Resolve-CompleterTarget -RuntimeKey $keyValue
                }
            }
            else
            {
                throw 'InputObject must expose CommandName with Native or ParameterName, or Key, RegistrationKey, or RuntimeKey with IsNative or Native.'
            }

            [pscustomobject] [ordered] @{
                PSTypeName = 'CompleterActions.ResolvedInputObject'
                InputObject = $InputObject
                Target = $target
                ScriptBlock = $scriptBlock
                ImportModule = $importModule
                ScriptPath = $scriptPath
                Trusted = $trusted
            }
        }
        catch
        {
            throw "Failed to resolve a completer target from InputObject. $($_.Exception.Message)"
        }
        finally
        {
            $keyValue = $null
            $keyIsRuntimeKey = $false
            $commandName = $null
            $parameterName = $null
            $scriptBlock = $null
            $importModule = $null
            $scriptPath = $null
            $trusted = $false
            $target = $null
        }
    }
}
<#
.SYNOPSIS
Resolves a Key or RegistrationKey of a given kind to the one target it can name.

.DESCRIPTION
A record's Key and RegistrationKey are its RuntimeKey folded to lowercase, and
the folding merges names the runtime keeps apart: the Kelvin sign (U+212A)
lowercases to the letter k, so 'Kelvin' spelled with it and 'kelvin' have one
key but are two runtime entries. A key therefore names only the target whose
runtime key is the key itself, compared ordinally ignoring case as the runtime
compares it, and only while no other target could be meant. This helper looks
for the targets of the given kind, in the managed table and in the runtime
dictionary of that kind, whose RuntimeKey is the key compared that way or
folds to the key. When one of them has a name the runtime keeps apart from the
key, such as the Kelvin-sign spelling for the key 'kelvin', it throws rather
than pick a target: that target and the one the key spells are both meant.
Otherwise the key names the registered target with that name, keeping its
spelling, even one the folding does not reach, such as a name spelled with the
final sigma (U+03C2) for a key spelled with the sigma (U+03C3) the runtime
takes for it, or the target the key spells when none is registered.

.PARAMETER Key
The folded key, such as a record's Key or RegistrationKey.

.PARAMETER Native
Resolves the key among native targets instead of parameter targets.

.OUTPUTS
CompleterActions.CompleterTarget

.EXAMPLE
PS> Resolve-CompleterKeyTarget -Key 'kelvin' -Native

Returns the native target 'kelvin', and throws while a native target spelled
with the Kelvin sign (U+212A) is registered, whether or not 'kelvin' is.
#>
function Resolve-CompleterKeyTarget
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch selects the kind of target the key is resolved among.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter()]
        [switch] $Native
    )

    $foldedKey = $Key.ToLowerInvariant()
    $runtime = Get-CompleterRuntime
    $dictionary = if ($Native) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }
    $candidateKeys = @(
        if ($null -ne $dictionary)
        {
            $dictionary.Keys
        }

        foreach ($registration in @(Find-ManagedCompleterRegistration))
        {
            if ([bool] $registration.IsNative -eq [bool] $Native)
            {
                $registration.RuntimeKey
            }
        }
    )

    $matchingKeys = [System.Collections.Generic.List[string]]::new()
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($candidateKey in $candidateKeys)
    {
        $runtimeKey = [string] $candidateKey

        $isMatch = [string]::Equals($runtimeKey, $Key, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($runtimeKey.ToLowerInvariant(), $foldedKey, [System.StringComparison]::Ordinal)

        if ($isMatch -and $seenKeys.Add($runtimeKey))
        {
            $matchingKeys.Add($runtimeKey)
        }
    }

    $kind = if ($Native) { 'native' } else { 'parameter' }

    $exactNaming = 'Supply RuntimeKey, or CommandName with IsNative or ParameterName, to name the target exactly.'

    if ($matchingKeys.Count -gt 1)
    {
        throw "The key '$Key' belongs to $($matchingKeys.Count) registered $kind targets, $(@($matchingKeys | ForEach-Object { "'$_'" }) -join ', '), which differ in characters that lowercasing merges, so it cannot name one of them. $exactNaming"
    }

    if ($matchingKeys.Count -eq 1 -and -not [string]::Equals($matchingKeys[0], $Key, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "The key '$Key' belongs to the registered $kind target '$($matchingKeys[0])', whose name differs from the key in characters that lowercasing merges, so the key could also name the $kind target '$Key'. $exactNaming"
    }

    $runtimeKey = if ($matchingKeys.Count -eq 1) { $matchingKeys[0] } else { $Key }

    if ($Native)
    {
        return Resolve-CompleterTarget -RuntimeKey $runtimeKey -Native
    }

    return Resolve-CompleterTarget -RuntimeKey $runtimeKey
}
<#
.SYNOPSIS
Decides whether each of a batch of completer registrations can be written over the current managed and runtime state.

.DESCRIPTION
Reconciles the records through one Resolve-CompleterRegistrationState pass,
or through the states the caller already resolved for them, and applies the
module's replacement rules in one place. Without -Force an existing managed
record blocks a registration when it is stale, when its lazy load failed, or
when it describes a different completer that does not come from a new
instance of the module that registered it, and an unmanaged runtime
registration blocks it as well. A managed record that already describes the
same completer is reported as existing so the caller can reuse it. Script
paths compare the way the file system does: ignoring case on Windows and
macOS, and ordinally elsewhere, where two paths that differ only in case name
two files.

A record is imported when its script block is one Import-CompleterScript
emitted for the record's ScriptPath under the record's tier, as
Get-CompleterImportModule finds it in the table the import writes. Records
that Import-CompleterScript emits and records a lazy load activated are
imported. A record that only names a ScriptPath is not, and neither is one
whose ImportModule property names the module its own script block is bound
to, such as a closure of an imported block, or one whose script block a caller
bound to the capture module: provenance comes from the module's table, never
from a property or a binding the caller can set.

A record is lazy when its State is 'Pending'. A lazy record describes the
same completer as a managed record that loads, or already loaded, the same
script under the same tier: a Pending record, or an imported record.

An eager record describes the same completer when it holds the very same
script block, or a script block with exactly the same text, compared case
sensitively, with the same ScriptPath and tier, defined in the same file and
bound to the same context. Two imported records of the same script are bound
to the same context, so importing and registering the same script again stays
a no-op although every import binds its script blocks to a new module. Any
other two script blocks are bound to the same context when they are bound to
the same module or to none. A closure is bound to a module of its own with a
unique name, so two closures never match even when their text is identical,
because they run with different captured values.

A script block with that same text, ScriptPath, tier and file that is bound to
another instance of a module with the same name, as when a module is imported
again, comes from the module that owns the managed record. It is not the same
completer, because the new instance holds its own state, so it is not reported
as existing, but it is not a problem either: it replaces a live record from
the earlier instance without -Force. A Stale or Failed record is checked
first and still needs -Force.

The records are resolved in order as if each earlier record of the same call
had already been written: a later record for the same target sees the earlier
one as the managed and runtime registration, so repeating a target within one
call reuses or replaces the first registration exactly as two calls would.
Register-Completer resolves one record at a time, after the
earlier targets of its call have been written, and throws the reported
problem; Resolve-CompleterSetRegistration resolves an entry's records together and
collects the problems, so a completer set is validated against the same rules
its registrations are held to.

.PARAMETER Registration
The CompleterActions.CompleterRegistration records that are about to be
written, in the order they will be written.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted, one is taken for this call.

.PARAMETER RegistrationState
The rows Resolve-CompleterRegistrationState already returned for these records,
one per record in the same order. When it is supplied no state pass is made
here, so a caller that resolves many batches against one snapshot can resolve
every key in one pass and hand each batch its slice.

.PARAMETER Force
Indicates that existing registrations are replaced, so nothing is reported as
a problem.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per record, in order, with Key, ManagedRegistration,
RuntimeRegistration, IsExisting (the managed record already describes this
completer), and Problem (the message that blocks the registration, or null).
#>
function Resolve-CompleterRegistrationConflict
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [psobject[]] $Registration,

        [Parameter()]
        [psobject] $Snapshot,

        [Parameter()]
        [AllowEmptyCollection()]
        [psobject[]] $RegistrationState,

        [Parameter()]
        [switch] $Force
    )

    if ($Registration.Count -eq 0)
    {
        return
    }

    $registrationStates = $RegistrationState

    if (-not $PSBoundParameters.ContainsKey('RegistrationState'))
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Target $Registration -Snapshot $Snapshot)
    }

    function Test-ImportedCompleterRecord
    {
        param(
            [psobject] $Record
        )

        $null -ne (Get-CompleterImportModule -ScriptBlock $Record.ScriptBlock -ScriptPath $Record.ScriptPath -Trusted ([bool] $Record.Trusted))
    }

    $plannedRegistrations = @{}
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    for ($index = 0; $index -lt $Registration.Count; $index++)
    {
        $registrationItem = $Registration[$index]
        $registrationState = $registrationStates[$index]
        $key = [string] $registrationItem.Key
        $identity = Get-CompleterTargetIdentity -Target $registrationItem

        if ($plannedRegistrations.Contains($identity))
        {
            $plannedRegistration = $plannedRegistrations[$identity]
            $registrationState = [pscustomobject] [ordered] @{
                Key                 = $key
                ManagedRegistration = $plannedRegistration
                RuntimeRegistration = New-CompleterRegistrationRecord -Target $plannedRegistration -ScriptBlock $plannedRegistration.ScriptBlock -Source 'Discovered' -State Discovered
                ManagedState        = $plannedRegistration.State
            }
        }

        $existingManagedRegistration = $registrationState.ManagedRegistration
        $existingRuntimeRegistration = $registrationState.RuntimeRegistration
        $isExisting = $false
        $isNewModuleInstance = $false
        $problem = $null

        if (-not $Force)
        {
            if ($null -ne $existingManagedRegistration)
            {
                if ($registrationState.ManagedState -eq 'Stale')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' is stale: the runtime registration was replaced or removed outside this module. Use -Force to replace the live registration and reconcile the managed record."
                }
                elseif ($registrationState.ManagedState -eq 'Failed')
                {
                    $problem = "The module-managed completer registration for '$($registrationItem.RuntimeKey)' failed to load '$($existingManagedRegistration.ScriptPath)': $($existingManagedRegistration.LoadError) Use -Force to retry the lazy load."
                }
                else
                {
                    $isSameScript = [string]::Equals($existingManagedRegistration.ScriptPath, $registrationItem.ScriptPath, $pathComparison) -and
                        [bool] $existingManagedRegistration.Trusted -eq [bool] $registrationItem.Trusted
                    $isExistingImported = Test-ImportedCompleterRecord -Record $existingManagedRegistration
                    $isExisting = if ($registrationItem.State -eq 'Pending')
                    {
                        $isSameScript -and ($existingManagedRegistration.State -eq 'Pending' -or $isExistingImported)
                    }
                    else
                    {
                        $existingScriptBlock = $existingManagedRegistration.ScriptBlock
                        $newScriptBlock = $registrationItem.ScriptBlock
                        $existingModule = $existingScriptBlock.Module
                        $newModule = $newScriptBlock.Module
                        $isSameDefinition = [string]::Equals($existingManagedRegistration.ScriptText, $registrationItem.ScriptText, [System.StringComparison]::Ordinal) -and
                            $isSameScript -and
                            [string]::Equals($existingScriptBlock.File, $newScriptBlock.File, $pathComparison)
                        $isNewModuleInstance = $isSameDefinition -and
                            $null -ne $existingModule -and $null -ne $newModule -and
                            -not [object]::ReferenceEquals($existingModule, $newModule) -and
                            [string]::Equals($existingModule.Name, $newModule.Name, [System.StringComparison]::OrdinalIgnoreCase)

                        [object]::ReferenceEquals($existingScriptBlock, $newScriptBlock) -or (
                            $isSameDefinition -and (
                                ($isExistingImported -and (Test-ImportedCompleterRecord -Record $registrationItem)) -or
                                [object]::ReferenceEquals($existingModule, $newModule)))
                    }

                    if (-not $isExisting -and -not $isNewModuleInstance)
                    {
                        $problem = "A module-managed completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
                    }
                }
            }
            elseif ($null -ne $existingRuntimeRegistration)
            {
                $problem = "A runtime completer registration already exists for '$($registrationItem.RuntimeKey)'. Use -Force to replace it."
            }
        }

        if ($null -eq $problem)
        {
            $plannedRegistrations[$identity] = if ($isExisting) { $existingManagedRegistration } else { $registrationItem }
        }

        [pscustomobject] [ordered] @{
            Key                 = $key
            ManagedRegistration = $existingManagedRegistration
            RuntimeRegistration = $existingRuntimeRegistration
            IsExisting          = $isExisting
            Problem             = $problem
        }
    }
}
<#
.SYNOPSIS
Reconciles managed registration records with the live runtime values for one or more targets.

.DESCRIPTION
Looks up both the module-managed record and the live runtime registration for
each target and reports whether the managed record still describes what
PowerShell is actually using. A target is identified by its Key together with
its kind: a native target is looked up only in the native runtime dictionary
and a parameter target only in the custom one, and the managed record is
found by Get-CompleterTargetIdentity, so a native command named
'Get-Thing:Name' and the parameter target Get-Thing / Name never resolve to
each other's registrations.

A managed record is authoritative only while the runtime holds the very same
script block object. Equal text is not ownership: two closures with the same
text run with different captured values, and text that differs only in case
can complete differently. The record is reported as 'Pending' when that
script block is still a lazy stub and 'Active' otherwise. A managed record
whose lazy load failed is reported as 'Failed' regardless of the runtime,
because its runtime entry was removed on purpose. When the runtime value was
replaced, even by a script block with the same text, or removed outside this
module, the managed record is reported as stale so public commands can
surface the live value, refuse silent reuse, and apply the unmanaged-removal
gate.

Every target is resolved against one snapshot of the managed table and the
runtime dictionaries, the one passed in or one taken here, so a batch of
targets costs a single runtime read. Discovered runtime values keep the key
casing the dictionary stores, and the states come back in the order of the
targets.

.PARAMETER Target
The completer targets or registration records to reconcile. Each must expose
Key, RuntimeKey, and IsNative.

.PARAMETER Snapshot
A CompleterActions.CompleterRegistrationSnapshot to resolve against. When it is
omitted the helper takes one for this call.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one object per target, in order, with Key (the target's Key),
ManagedRegistration, RuntimeRegistration, and ManagedState ('None', 'Active',
'Pending', 'Failed', or 'Stale') properties. The registration properties hold
the exact stored objects so callers can restore them unchanged.

.EXAMPLE
PS> $state = Resolve-CompleterRegistrationState -Target (Resolve-CompleterTarget -CommandName 'Get-Item' -ParameterName 'Path')

Retrieves the managed and runtime records for a target and reports whether the
managed record still matches the live runtime registration.

.EXAMPLE
PS> $states = Resolve-CompleterRegistrationState -Target $registrations -Snapshot $snapshot

Reconciles every record of a batch against one snapshot of the session.
#>
function Resolve-CompleterRegistrationState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [psobject[]] $Target,

        [Parameter()]
        [psobject] $Snapshot
    )

    if ($null -eq $Snapshot)
    {
        $Snapshot = Get-CompleterRegistrationSnapshot
    }

    foreach ($targetItem in $Target)
    {
        $identity = Get-CompleterTargetIdentity -Target $targetItem
        $isNative = [bool] $targetItem.IsNative
        $managedRegistration = if ($Snapshot.Managed.Contains($identity)) { $Snapshot.Managed[$identity] } else { $null }
        $runtimeRegistration = $null

        foreach ($view in $Snapshot.Runtime)
        {
            if ([bool] $view.IsNative -ne $isNative -or -not $view.Keys.ContainsKey([string] $targetItem.RuntimeKey))
            {
                continue
            }

            $storedKey = $view.Keys[[string] $targetItem.RuntimeKey]
            $storedTarget = if ($isNative) { Resolve-CompleterTarget -RuntimeKey $storedKey -Native } else { Resolve-CompleterTarget -RuntimeKey $storedKey }
            $runtimeRegistration = New-CompleterRegistrationRecord -Target $storedTarget -ScriptBlock (Get-CompleterRuntimeDictionaryValue -Dictionary $view.Dictionary -Key $storedKey) -Source 'Discovered' -State Discovered
            break
        }

        $managedState = if ($null -eq $managedRegistration)
        {
            'None'
        }
        elseif ($managedRegistration.State -eq 'Failed')
        {
            'Failed'
        }
        elseif ($null -ne $runtimeRegistration -and [object]::ReferenceEquals($managedRegistration.ScriptBlock, $runtimeRegistration.ScriptBlock))
        {
            if ($managedRegistration.State -eq 'Pending') { 'Pending' } else { 'Active' }
        }
        else
        {
            'Stale'
        }

        [pscustomobject] [ordered] @{
            Key                 = $targetItem.Key
            ManagedRegistration = $managedRegistration
            RuntimeRegistration = $runtimeRegistration
            ManagedState        = $managedState
        }
    }
}
<#
.SYNOPSIS
Resolves PowerShell's internal execution context object used for completer storage.

.DESCRIPTION
Asks the compiled engine access layer (CompleterActions.Internal.EngineAccess) for the
internal execution context object behind EngineIntrinsics that owns the runtime
completer dictionaries.

.PARAMETER EngineIntrinsics
The EngineIntrinsics instance to inspect. Defaults to the current session's
ExecutionContext.

.PARAMETER EngineIntrinsicsType
The EngineIntrinsics type to resolve the execution context field on. This is primarily
exposed for internal testing of compatibility guards.

.OUTPUTS
System.Object
#>
function Resolve-CompleterRuntimeExecutionContext
{
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [object] $EngineIntrinsics = $ExecutionContext,

        [Parameter()]
        [ValidateNotNull()]
        [type] $EngineIntrinsicsType = [System.Management.Automation.EngineIntrinsics]
    )

    try
    {
        return [CompleterActions.Internal.EngineAccess]::ResolveExecutionContext($EngineIntrinsics, $EngineIntrinsicsType)
    }
    catch
    {
        throw $_.Exception.GetBaseException().Message
    }
}
<#
.SYNOPSIS
Resolves completer script path input into full .ps1 file paths.

.DESCRIPTION
Shared by Import-CompleterScript and Test-CompleterScript so both commands
accept the same -Path and -LiteralPath input and reject the same non-script
input. Wildcards in -Path are expanded; -LiteralPath is used as written.
Directories and files without a .ps1 extension are rejected.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.String
#>
function Resolve-CompleterScriptPath
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    $resolvedPaths = @()

    switch ($PSCmdlet.ParameterSetName)
    {
        'Path'
        {
            foreach ($pathItem in $Path)
            {
                $resolvedPaths += @(Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath)
            }

            break
        }

        'LiteralPath'
        {
            foreach ($literalPathItem in $LiteralPath)
            {
                $resolvedPaths += (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
            }

            break
        }
    }

    foreach ($resolvedPath in $resolvedPaths)
    {
        $file = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
        if ($file.PSIsContainer)
        {
            throw "Completer scripts must be file paths. '$resolvedPath' is a directory."
        }

        if ($file.Extension -ne '.ps1')
        {
            throw "Completer scripts must be .ps1 files. Received '$resolvedPath'."
        }

        $file.FullName
    }
}
<#
.SYNOPSIS
Validates one completer set entry and resolves its script path and targets.

.DESCRIPTION
Normalizes a raw entry hashtable from a completer set into a record that
Resolve-CompleterSetRegistration can reconcile with the session, collecting
every problem instead of stopping at the first so the caller can report all
of them at once. This is the static phase of a set import: it reads only the
entry and the file system, never the session's registrations, so its result
does not depend on what is registered. A Path that is not fully qualified, a
drive-relative form such as C:scripts\x.ps1 included, resolves against the
set file's directory rather than the current location. A Path the platform
cannot resolve, one with a null character or one past the Windows length
limit, is an InvalidEntry problem, the record's Path stays null, and no file
check follows, so the set's other entries are still resolved. Trusted
defaults to false. Trusted, and a target's Native, must be $true or $false:
text or a number is an InvalidEntry problem rather than read as one kind or
the other. Trusted entries must declare Targets because the script is not
parsed.
Strict entries must register their targets with literal arguments so the
targets can be derived from the parsed script and, when the entry also
declares Targets, the two lists must match. Without -Verify the strict import
grammar runs on the same parse once the targets are derived from it, so a
script that does not parse or whose targets cannot be read gets only the
UnreadableTargets problem, and a script that fails the grammar gets the
NonConforming problem, built from its first Error finding, ahead of any
TargetMismatch for the same entry; the grammar runs again when the script
loads. A strict script is parsed at most once here and the targets it yields
are the ones the import registers. The script is never executed.

The fast path skips that parse and the grammar. When a strict entry has no
problem so far, declares Targets, and carries a Hash whose form
Test-CompleterSetHashFormat recognises, the script's text is hashed and
compared with it. On a match the declared Targets are used as they are, in
declared order and de-duplicated by Key with the first occurrence kept,
because the export that wrote the Hash derived those targets from the same
text. An absent, unrecognised, or different Hash, or a script that cannot be
read for its hash, falls through to the parse, so such an entry gets exactly
the problems it would get with no Hash at all. A trusted entry's Hash is
ignored and its script is not read.

When ModuleBase is given, as Import-CompleterSet -Name gives it, the
resolved path must lie inside that folder, compared with a trailing separator
and with the platform's case rule (case-insensitive on Windows and macOS,
case-sensitive on Linux). An entry outside it gets the OutsideModule problem
and no existence, extension, hash, or parse check, so its file is never
opened.

Each problem is a hashtable with Kind and Message. Kind is InvalidEntry,
MissingScript, OutsideModule, UnreadableTargets, NonConforming, or
TargetMismatch; Message is the text Import-CompleterSet reports.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.PARAMETER Verify
Disables the fast path and the grammar, so every strict entry whose script is
usable is parsed once and never walked, and records the script's actual hash
and parse-derived targets for drift checks. A trusted entry's script is read
for its hash but still not parsed.

.PARAMETER ModuleName
The installed module folder's name, used in the OutsideModule problem.

.PARAMETER ModuleBase
The full path of the module folder the entry's script must stay inside.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns a record with Index, DeclaredPath, Path (null when the entry has no
Path or its Path cannot be resolved), Trusted, Targets,
DeclaredHash (the entry's raw Hash value, or null), TargetSource (Trusted for
a trusted entry, Hash for a strict entry that took the fast path, Parsed for
a strict entry whose script was parsed, or null when neither applies),
ResolutionNote (the text Import-CompleterSet writes as the entry's verbose
line, or null for an entry with a problem or under -Verify), Problems, and
IsValid. Registrations and Conflicts are empty until
Resolve-CompleterSetRegistration fills them. With -Verify the record also
carries ActualHash, the Hash of the script as it is now or null when it is
missing or cannot be read (the parser's FileReadError included, whose empty
text would otherwise hash as a change), and DerivedTargets, the targets the parse derived,
empty for a trusted entry or a failed parse.
#>
function Resolve-CompleterSetEntry
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Entry,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Index,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SetDirectory,

        [Parameter()]
        [switch] $Verify,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleBase
    )

    $problems = [System.Collections.Generic.List[hashtable]]::new()
    $moduleBasePrefix = $null
    $pathComparison = if ($IsWindows -or $IsMacOS) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if ($PSBoundParameters.ContainsKey('ModuleBase'))
    {
        $moduleBasePrefix = $ModuleBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    }
    $declaredPath = $null
    $resolvedPath = $null
    $hasHash = $false
    $declaredHash = $null
    $actualHash = $null
    $derivedTargets = @()
    $targetSource = $null
    $resolutionNote = $null
    $scriptIsUsable = $false
    $trusted = $false
    $declaredTargets = $null
    $targets = @()

    if ($Entry -isnot [System.Collections.IDictionary])
    {
        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'The entry is not a hashtable with Path, Trusted, and Targets keys.' })
    }
    else
    {
        if ($Entry.Contains('Hash'))
        {
            $hasHash = $true
            $declaredHash = $Entry['Hash']
        }

        if (-not $Entry.Contains('Path') -or [string]::IsNullOrWhiteSpace([string] $Entry['Path']))
        {
            $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'The entry has no Path.' })
        }
        else
        {
            $declaredPath = [string] $Entry['Path']

            try
            {
                $resolvedPath = [System.IO.Path]::GetFullPath($declaredPath.Replace('\', '/'), $SetDirectory)
            }
            catch [System.IO.PathTooLongException]
            {
                # Its message repeats the whole path, which the entry label already shows.
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'The Path is not a valid file path: it is longer than the platform allows.' })
            }
            catch [System.ArgumentException]
            {
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = "The Path is not a valid file path: $($_.Exception.GetBaseException().Message)" })
            }

            if ($null -ne $resolvedPath)
            {
                if ($null -ne $moduleBasePrefix -and -not $resolvedPath.StartsWith($moduleBasePrefix, $pathComparison))
                {
                    $problems.Add(@{ Kind = 'OutsideModule'; Message = "the script '$resolvedPath' is outside the module '$ModuleName' at '$ModuleBase'" })
                }
                elseif (-not [System.IO.File]::Exists($resolvedPath))
                {
                    $problems.Add(@{ Kind = 'MissingScript'; Message = "The file '$resolvedPath' does not exist." })
                }
                elseif ([System.IO.Path]::GetExtension($resolvedPath) -ne '.ps1')
                {
                    $problems.Add(@{ Kind = 'InvalidEntry'; Message = "The file '$resolvedPath' is not a .ps1 script." })
                }
                else
                {
                    $scriptIsUsable = $true
                }
            }
        }

        if ($Entry.Contains('Trusted'))
        {
            if ($Entry['Trusted'] -isnot [bool])
            {
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Trusted must be $true or $false.' })
            }
            else
            {
                $trusted = $Entry['Trusted']
            }
        }

        if ($Entry.Contains('Targets') -and @($Entry['Targets']).Count -gt 0)
        {
            $declaredTargets = @(
                foreach ($targetEntry in @($Entry['Targets']))
                {
                    if ($targetEntry -isnot [System.Collections.IDictionary])
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Each target must be a hashtable with CommandName and either Native = $true or ParameterName.' })
                        continue
                    }

                    $commandName = if ($targetEntry.Contains('CommandName')) { [string] $targetEntry['CommandName'] } else { $null }

                    if ([string]::IsNullOrWhiteSpace($commandName))
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'A target has no CommandName.' })
                        continue
                    }

                    # Native decides the target's kind, so it is held to a Boolean as
                    # Trusted is: comparing it with $true would read the text 'True' and
                    # the number 1 as native, and 'False' or 'nope' as a parameter target.
                    if ($targetEntry.Contains('Native') -and $targetEntry['Native'] -isnot [bool])
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = "Target '$commandName' must set Native to `$true or `$false." })
                        continue
                    }

                    try
                    {
                        if ($targetEntry.Contains('Native') -and $targetEntry['Native'])
                        {
                            Resolve-CompleterTarget -CommandName $commandName -Native
                        }
                        elseif ($targetEntry.Contains('ParameterName') -and -not [string]::IsNullOrWhiteSpace([string] $targetEntry['ParameterName']))
                        {
                            Resolve-CompleterTarget -CommandName $commandName -ParameterName ([string] $targetEntry['ParameterName'])
                        }
                        else
                        {
                            $problems.Add(@{ Kind = 'InvalidEntry'; Message = "Target '$commandName' must declare Native = `$true or a ParameterName." })
                        }
                    }
                    catch
                    {
                        $problems.Add(@{ Kind = 'InvalidEntry'; Message = $_.Exception.Message })
                    }
                }
            )
        }

        if ($trusted)
        {
            $targetSource = 'Trusted'

            if ($null -eq $declaredTargets)
            {
                $problems.Add(@{ Kind = 'InvalidEntry'; Message = 'Trusted entries must declare Targets, because a trusted script is not parsed for them.' })
            }
            else
            {
                $targets = $declaredTargets
            }

            $resolutionNote = 'trusted; targets read from the set.'

            if ($Verify -and $scriptIsUsable)
            {
                try
                {
                    $actualHash = Get-CompleterScriptHash -LiteralPath $resolvedPath
                }
                catch
                {
                    $actualHash = $null
                }
            }
        }
        elseif ($scriptIsUsable)
        {
            $hashMatches = $false

            if ($null -eq $declaredTargets)
            {
                $resolutionNote = 'no Targets; parsed the script.'
            }
            elseif (-not $hasHash)
            {
                $resolutionNote = 'no hash; parsed the script.'
            }
            elseif (-not (Test-CompleterSetHashFormat -Value $declaredHash))
            {
                $resolutionNote = 'hash not recognised; parsed the script.'
            }
            elseif ($problems.Count -eq 0 -and -not $Verify)
            {
                $resolutionNote = 'hash differs; parsed the script.'

                try
                {
                    $hashMatches = (Get-CompleterScriptHash -LiteralPath $resolvedPath) -ieq [string] $declaredHash
                }
                catch
                {
                    $hashMatches = $false
                }
            }

            if ($hashMatches)
            {
                $targetSource = 'Hash'
                $resolutionNote = 'hash matches; targets read from the set.'
                $seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $targets = @(
                    foreach ($declaredTarget in $declaredTargets)
                    {
                        if ($seenTargets.Add((Get-CompleterTargetIdentity -Target $declaredTarget)))
                        {
                            $declaredTarget
                        }
                    }
                )
            }
            else
            {
                $targetSource = 'Parsed'

                try
                {
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $resolvedPath

                    if ($Verify -and -not @($parseResult.ParseErrors | Where-Object { $_.ErrorId -eq 'FileReadError' }))
                    {
                        $actualHash = Get-CompleterScriptHash -Text $parseResult.Ast.Extent.Text
                    }

                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $resolvedPath -ParseResult $parseResult)

                    if (-not $Verify)
                    {
                        $grammarFinding = @(Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $resolvedPath | Where-Object -Property Severity -EQ -Value 'Error') | Select-Object -First 1

                        if ($null -ne $grammarFinding)
                        {
                            $problems.Add(@{ Kind = 'NonConforming'; Message = "The script does not conform to the strict import grammar: line $($grammarFinding.Line), column $($grammarFinding.Column) ($($grammarFinding.Construct)): $($grammarFinding.Message) Run Test-CompleterScript to work through the findings, or mark the entry Trusted to run it as-is." })
                        }
                    }
                }
                catch
                {
                    $problems.Add(@{ Kind = 'UnreadableTargets'; Message = $_.Exception.Message })
                }
            }

            if ($derivedTargets.Count -gt 0)
            {
                if ($null -eq $declaredTargets)
                {
                    $targets = $derivedTargets
                }
                else
                {
                    $declaredIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                    foreach ($declaredTarget in $declaredTargets)
                    {
                        $null = $declaredIdentities.Add((Get-CompleterTargetIdentity -Target $declaredTarget))
                    }

                    $mismatch = -not $declaredIdentities.SetEquals([string[]] @($derivedTargets | ForEach-Object { Get-CompleterTargetIdentity -Target $_ }))

                    if ($mismatch)
                    {
                        $declaredList = @($declaredTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                        $derivedList = @($derivedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                        $problems.Add(@{ Kind = 'TargetMismatch'; Message = "The declared Targets do not match the script. Declared: $declaredList. Script registers: $derivedList." })
                    }
                    else
                    {
                        $targets = $derivedTargets
                    }
                }
            }
        }
    }

    $record = [pscustomobject] [ordered] @{
        PSTypeName     = 'CompleterActions.CompleterSetEntry'
        Index          = $Index
        DeclaredPath   = $declaredPath
        Path           = $resolvedPath
        Trusted        = $trusted
        DeclaredHash   = $declaredHash
        TargetSource   = $targetSource
        ResolutionNote = if ($problems.Count -eq 0 -and -not $Verify) { $resolutionNote } else { $null }
        Targets        = @($targets)
        Registrations  = @()
        Conflicts      = @()
        Problems       = @($problems)
        IsValid        = $problems.Count -eq 0
    }

    if ($Verify)
    {
        $record | Add-Member -NotePropertyName 'ActualHash' -NotePropertyValue $actualHash
        $record | Add-Member -NotePropertyName 'DerivedTargets' -NotePropertyValue @($derivedTargets)
    }

    $record
}
<#
.SYNOPSIS
Finds an installed completer set module by name and returns its set file.

.DESCRIPTION
Follows the module lookup without calling Get-Module. The roots of
$env:PSModulePath are walked in order, split on the platform's path separator,
skipping empty and missing entries. In each root the module folders are the
subdirectories whose name equals Name case-insensitively, on every platform,
and within a module folder the manifest is the .psd1 whose base name equals
the folder's name case-insensitively.

The candidates in a root are every version subfolder that parses as a version
and equals its manifest's ModuleVersion, and the unversioned layout, the
manifest directly in the module folder. The first root with a candidate wins;
within it the highest version wins, and the unversioned layout is used only
when the root has no versioned candidate. The chosen module is never replaced
by a lower version, even when its set declaration is broken.

With -MinimumVersion or -RequiredVersion every manifest of each root walked is
read, and the unversioned layout is a candidate beside the version folders
when its ModuleVersion parses as a version. -RequiredVersion takes the
candidate equal to the value from the first root that holds one.
-MinimumVersion takes, from the first root that holds a candidate equal to or
above the value, the highest such candidate; a root whose candidates are all
lower is passed over. Versions compare as System.Version values, so 1.2.0 and
1.2.0.0 differ, and a prerelease label takes no part. On a tie a version
folder wins over the unversioned layout. When no root holds a match but some
root holds a candidate, the error names the wanted version and lists every
candidate's version from every root, highest first, without repeats; when no
root holds a candidate, the error is the one without a version parameter.

Manifests are read by Import-CompleterDataFile, as data only, so nothing in
the package runs, and under the set file limit, so a manifest larger than
128 KB is refused before it is parsed. PrivateData.CompleterSet must name
a .psd1 file in a folder directly below ModuleBase, with / or \ as the
separator, and the file must exist. A declaration that is not a valid file
path, because it holds a null character or is longer than the platform allows,
fails with the invalid-declaration text, the value shown through
ConvertTo-CompleterPrintableText; the error for a set file that does not exist
shows its path the same way. A failure throws the bare reason; the caller adds
its own prefix.

.PARAMETER Name
The module name, taken literally.

.PARAMETER MinimumVersion
Selects the highest candidate equal to or above this version, from the first
root that holds one.

.PARAMETER RequiredVersion
Selects the candidate equal to this version, from the first root that holds
one.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Name (the installed module folder's spelling), Version (ModuleVersion,
followed by -<Prerelease> when PrivateData.PSData.Prerelease is set),
ModuleBase (the full path of the version folder, or of the module folder for
the unversioned layout), ManifestPath, Manifest (the manifest's data), and
SetPath (the full path of the set file).
#>
function Resolve-CompleterSetModule
{
    [CmdletBinding(DefaultParameterSetName = 'Highest')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = 'MinimumVersion')]
        [version] $MinimumVersion,

        [Parameter(Mandatory, ParameterSetName = 'RequiredVersion')]
        [version] $RequiredVersion
    )

    $sortOrdinal = {
        param([string[]] $Value)

        $sorted = [string[]] @($Value)
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $sorted
    }

    $findManifest = {
        param([string] $Folder, [string] $ModuleName)

        $manifestPaths = @(
            foreach ($file in [System.IO.Directory]::EnumerateFiles($Folder, '*.psd1'))
            {
                if ([string]::Equals([System.IO.Path]::GetExtension($file), '.psd1', [System.StringComparison]::OrdinalIgnoreCase) -and
                    [string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($file), $ModuleName, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $file
                }
            }
        )

        if ($manifestPaths.Count -gt 0)
        {
            @(& $sortOrdinal $manifestPaths)[0]
        }
    }

    $readManifest = {
        param([string] $ManifestPath)

        $fullPath = [System.IO.Path]::GetFullPath($ManifestPath)
        $manifestFile = Import-CompleterDataFile -LiteralPath $fullPath

        if ($manifestFile.OverLimit)
        {
            throw "The module manifest '$fullPath' is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files and their module manifests."
        }

        $manifestFile.Data
    }

    # A version folder is a candidate when its manifest's ModuleVersion equals the folder's version.
    $readVersionFolder = {
        param([pscustomobject] $VersionFolder)

        $moduleName = [System.IO.Path]::GetFileName($VersionFolder.ModuleFolder)
        $manifestPath = & $findManifest $VersionFolder.Folder $moduleName

        if ($null -ne $manifestPath)
        {
            $manifest = & $readManifest $manifestPath
            $manifestVersion = $null

            if ([version]::TryParse([string] $manifest['ModuleVersion'], [ref] $manifestVersion) -and $manifestVersion -eq $VersionFolder.FolderVersion)
            {
                @{ Name = $moduleName; ModuleBase = $VersionFolder.Folder; ManifestPath = $manifestPath; Manifest = $manifest }
            }
        }
    }

    $selectVersion = $PSCmdlet.ParameterSetName -ne 'Highest'
    $candidateVersions = [System.Collections.Generic.SortedSet[version]]::new()
    $chosen = $null

    foreach ($root in ([string] $env:PSModulePath).Split([System.IO.Path]::PathSeparator))
    {
        if ([string]::IsNullOrWhiteSpace($root) -or -not [System.IO.Directory]::Exists($root))
        {
            continue
        }

        $moduleFolders = @(
            foreach ($directory in [System.IO.Directory]::EnumerateDirectories($root))
            {
                if ([string]::Equals([System.IO.Path]::GetFileName($directory), $Name, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $directory
                }
            }
        )

        if ($moduleFolders.Count -eq 0)
        {
            continue
        }

        $moduleFolders = @(& $sortOrdinal $moduleFolders)
        $order = 0
        $versionFolders = @(
            foreach ($moduleFolder in $moduleFolders)
            {
                foreach ($versionFolder in @(& $sortOrdinal @([System.IO.Directory]::EnumerateDirectories($moduleFolder))))
                {
                    $folderVersion = $null

                    if ([version]::TryParse([System.IO.Path]::GetFileName($versionFolder), [ref] $folderVersion))
                    {
                        $order++
                        [pscustomobject] @{ ModuleFolder = $moduleFolder; Folder = $versionFolder; FolderVersion = $folderVersion; Order = $order }
                    }
                }
            }
        )

        $versionFolders = @($versionFolders | Sort-Object -Property @{ Expression = 'FolderVersion'; Descending = $true }, @{ Expression = 'Order'; Descending = $false })

        if ($selectVersion)
        {
            # Version folders come first, so on a tie a version folder wins over the unversioned layout.
            $candidates = @(
                foreach ($versionFolder in $versionFolders)
                {
                    $candidate = & $readVersionFolder $versionFolder

                    if ($null -ne $candidate)
                    {
                        @{ Version = $versionFolder.FolderVersion; Module = $candidate }
                    }
                }

                foreach ($moduleFolder in $moduleFolders)
                {
                    $moduleName = [System.IO.Path]::GetFileName($moduleFolder)
                    $manifestPath = & $findManifest $moduleFolder $moduleName

                    if ($null -ne $manifestPath)
                    {
                        $manifest = & $readManifest $manifestPath
                        $manifestVersion = $null

                        if ([version]::TryParse([string] $manifest['ModuleVersion'], [ref] $manifestVersion))
                        {
                            @{ Version = $manifestVersion; Module = @{ Name = $moduleName; ModuleBase = $moduleFolder; ManifestPath = $manifestPath; Manifest = $manifest } }
                        }
                    }
                }
            )

            $selected = $null

            foreach ($candidate in $candidates)
            {
                $null = $candidateVersions.Add($candidate.Version)
                $isMatch = if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion') { $candidate.Version -eq $RequiredVersion } else { $candidate.Version -ge $MinimumVersion }

                if ($isMatch -and ($null -eq $selected -or $candidate.Version -gt $selected.Version))
                {
                    $selected = $candidate
                }
            }

            if ($null -ne $selected)
            {
                $chosen = $selected.Module
                break
            }

            continue
        }

        foreach ($versionFolder in $versionFolders)
        {
            $chosen = & $readVersionFolder $versionFolder

            if ($null -ne $chosen)
            {
                break
            }
        }

        if ($null -eq $chosen)
        {
            foreach ($moduleFolder in $moduleFolders)
            {
                $moduleName = [System.IO.Path]::GetFileName($moduleFolder)
                $manifestPath = & $findManifest $moduleFolder $moduleName

                if ($null -ne $manifestPath)
                {
                    $manifest = & $readManifest $manifestPath
                    $chosen = @{ Name = $moduleName; ModuleBase = $moduleFolder; ManifestPath = $manifestPath; Manifest = $manifest }
                    break
                }
            }
        }

        if ($null -ne $chosen)
        {
            break
        }
    }

    if ($null -eq $chosen)
    {
        if ($candidateVersions.Count -gt 0)
        {
            $wanted = if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion') { "version $RequiredVersion" } else { "version $MinimumVersion or later" }
            $installed = @($candidateVersions.Reverse()) -join ', '
            throw "No installed module named '$Name' with $wanted was found in `$env:PSModulePath. Installed versions: $installed."
        }

        throw "No installed module named '$Name' was found in `$env:PSModulePath. Install it with Install-PSResource $Name."
    }

    $moduleName = $chosen.Name
    $moduleBase = [System.IO.Path]::GetFullPath($chosen.ModuleBase)
    $manifest = $chosen.Manifest
    $privateData = $manifest['PrivateData']
    $version = [string] $manifest['ModuleVersion']

    if ($privateData -is [System.Collections.IDictionary] -and $privateData['PSData'] -is [System.Collections.IDictionary])
    {
        $prerelease = [string] $privateData['PSData']['Prerelease']

        if (-not [string]::IsNullOrEmpty($prerelease))
        {
            $version = '{0}-{1}' -f $version, $prerelease
        }
    }

    $declaredSet = if ($privateData -is [System.Collections.IDictionary]) { $privateData['CompleterSet'] } else { $null }

    if ($null -eq $declaredSet)
    {
        throw "The module '$moduleName' $version at '$moduleBase' does not declare a completer set. A completer set module names its set file in PrivateData.CompleterSet."
    }

    $segments = @(
        if ($declaredSet -is [string] -and -not [System.IO.Path]::IsPathRooted($declaredSet))
        {
            $declaredSet.Replace('\', '/').Split('/')
        }
    )
    $isValidDeclaration = $segments.Count -eq 2 -and
        @($segments.Where({ [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' -or [System.IO.Path]::IsPathRooted($_) })).Count -eq 0 -and
        [System.IO.Path]::GetExtension($segments[1]) -eq '.psd1'

    if (-not $isValidDeclaration)
    {
        throw "The module '$moduleName' $version declares the completer set '$(ConvertTo-CompleterPrintableText -Value ([string] $declaredSet))', which must be a .psd1 file in a folder directly below '$moduleBase'."
    }

    try
    {
        $setPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($moduleBase, $segments[0], $segments[1]))
    }
    catch [System.IO.PathTooLongException], [System.ArgumentException]
    {
        # A null character, or a path longer than the platform allows, names no
        # file. The value can hold control characters, so it is made printable.
        throw "The module '$moduleName' $version declares the completer set '$(ConvertTo-CompleterPrintableText -Value $declaredSet)', which must be a .psd1 file in a folder directly below '$moduleBase'."
    }

    if (-not [System.IO.File]::Exists($setPath))
    {
        throw "The completer set '$(ConvertTo-CompleterPrintableText -Value $setPath)' declared by the module '$moduleName' $version does not exist."
    }

    [pscustomobject] [ordered] @{
        Name         = $moduleName
        Version      = $version
        ModuleBase   = $moduleBase
        ManifestPath = [System.IO.Path]::GetFullPath($chosen.ManifestPath)
        Manifest     = $manifest
        SetPath      = $setPath
    }
}
<#
.SYNOPSIS
Reconciles the statically resolved entries of one completer set with the session's registrations.

.DESCRIPTION
The session phase of a set import. For each entry that
Resolve-CompleterSetEntry produced, in set order, it builds the Pending
records, one lazy stub per target, and holds them to the rules
Register-Completer applies through Resolve-CompleterRegistrationConflict
against the snapshot the whole set shares. A target that already carries a
different registration is a Conflict problem unless -Force is given, and a
target that an earlier valid entry of the same set already claimed is always
a DuplicateTarget problem. An entry with no problem claims its targets for
the entries after it. The entry's Registrations and Conflicts are what
Import-CompleterSet writes, so the session's registrations are read once per
set.

Every target of the set is reconciled with the session in one
Resolve-CompleterRegistrationState pass, in set order. Each entry's conflicts
are then decided on its own slice of that pass, so an entry is planned
exactly as if it were resolved alone and a target two entries share stays a
DuplicateTarget problem, not a conflict with the earlier entry. When no entry
resolved a target there is nothing to reconcile and no pass is made.

Each entry record is completed in place: Registrations and Conflicts are
filled, the session problems are appended after the entry's static ones, and
IsValid is recomputed.

.PARAMETER Entry
The CompleterActions.CompleterSetEntry records of one set, in set order.

.PARAMETER Snapshot
The CompleterActions.CompleterRegistrationSnapshot, shared by every entry of
the set, that the entries' targets are reconciled against.

.PARAMETER Force
Indicates that the set is imported with -Force, so existing registrations for
its targets are replaced rather than reported.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns each entry record, in set order, with Registrations, the Conflicts
resolved for them in the same order, Problems, and IsValid.
#>
function Resolve-CompleterSetRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Entry,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject] $Snapshot,

        [Parameter()]
        [switch] $Force
    )

    $entryRegistrations = [System.Collections.Generic.List[object]]::new()
    $setRegistrations = [System.Collections.Generic.List[psobject]]::new()

    foreach ($entryItem in $Entry)
    {
        $registrations = @(
            foreach ($target in @($entryItem.Targets))
            {
                New-CompleterRegistrationRecord -Target $target -ScriptBlock (New-CompleterLazyStub -Key $target.RuntimeKey -Native:$target.IsNative) -Source 'Managed' -State 'Pending' -ScriptPath $entryItem.Path -Trusted:$entryItem.Trusted
            }
        )

        $entryRegistrations.Add($registrations)

        foreach ($registration in $registrations)
        {
            $setRegistrations.Add($registration)
        }
    }

    $registrationStates = @()

    if ($setRegistrations.Count -gt 0)
    {
        $registrationStates = @(Resolve-CompleterRegistrationState -Target $setRegistrations.ToArray() -Snapshot $Snapshot)
    }

    $claimedTargets = @{}
    $stateIndex = 0

    for ($entryIndex = 0; $entryIndex -lt $Entry.Count; $entryIndex++)
    {
        $entryItem = $Entry[$entryIndex]
        $problems = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($problem in $entryItem.Problems)
        {
            $problems.Add($problem)
        }

        $targets = @($entryItem.Targets)
        $registrations = $entryRegistrations[$entryIndex]
        $conflicts = @()

        if ($registrations.Count -gt 0)
        {
            $stateSlice = $registrationStates[$stateIndex..($stateIndex + $registrations.Count - 1)]
            $stateIndex += $registrations.Count
            $conflicts = @(Resolve-CompleterRegistrationConflict -Registration $registrations -RegistrationState $stateSlice -Force:$Force)
        }

        $targetIdentities = @($targets | ForEach-Object { Get-CompleterTargetIdentity -Target $_ })

        for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++)
        {
            $target = $targets[$targetIndex]
            $targetIdentity = $targetIdentities[$targetIndex]

            if ($null -ne $conflicts[$targetIndex].Problem)
            {
                $problems.Add(@{ Kind = 'Conflict'; Message = $conflicts[$targetIndex].Problem })
            }

            if ($claimedTargets.Contains($targetIdentity))
            {
                $problems.Add(@{ Kind = 'DuplicateTarget'; Message = "Target '$($target.RuntimeKey)' is also listed by entry $($claimedTargets[$targetIdentity])." })
            }
        }

        if ($problems.Count -eq 0)
        {
            foreach ($targetIdentity in $targetIdentities)
            {
                $claimedTargets[$targetIdentity] = $entryItem.Index
            }
        }

        $entryItem.Registrations = $registrations
        $entryItem.Conflicts = $conflicts
        $entryItem.Problems = @($problems)
        $entryItem.IsValid = $problems.Count -eq 0
        $entryItem
    }
}
<#
.SYNOPSIS
Resolves completer target metadata from user-facing inputs or runtime keys.

.DESCRIPTION
Normalizes the different target shapes used by the module into a single
CompleterTarget record. Maintainers use this helper when moving between the
module's public command/parameter model and the runtime key shapes used by
PowerShell's completer dictionaries.

For command-parameter completers, runtime keys are expected to use the
'Command:Parameter' format. For native completers, the runtime key is the
command name. This helper validates those assumptions and returns a normalized
target object that other runtime helpers can consume.

.PARAMETER CommandName
The command or native executable name that identifies the completer target.

.PARAMETER ParameterName
The parameter name for a command-parameter completer target.

.PARAMETER Native
Indicates that the target refers to a native command completer rather than a
PowerShell command parameter completer.

.PARAMETER RuntimeKey
The raw key shape used by the PowerShell runtime dictionaries. This is either a
native command name or a 'Command:Parameter' string for command-parameter
targets.

.OUTPUTS
CompleterActions.CompleterTarget

.EXAMPLE
Resolve-CompleterTarget -CommandName git -Native

Shows the maintainer-oriented path that converts a native completer target into
the normalized object used by runtime registration helpers.

.EXAMPLE
Resolve-CompleterTarget -RuntimeKey 'Get-Item:Path'

Shows how a command-parameter runtime key is parsed back into normalized target
metadata.

.NOTES
This helper is intentionally aligned with the runtime key conventions used by
PowerShell's completer dictionaries and the module's registration records. If
those runtime conventions change, update this parser and the related runtime
helpers together.
#>
function Resolve-CompleterTarget
{
    [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to select native-specific parameter sets and to derive the target kind.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'RuntimeKey')]
        [Parameter(Mandatory, ParameterSetName = 'NativeRuntimeKey')]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeKey
    )

    $resolvedCommandName = $CommandName
    $resolvedParameterName = $ParameterName
    $resolvedIsNative = $false

    switch ($PSCmdlet.ParameterSetName)
    {
        'Native'
        {
            $resolvedIsNative = [bool] $Native
            $RuntimeKey = $CommandName
            break
        }

        'CommandParameter'
        {
            $RuntimeKey = '{0}:{1}' -f $CommandName, $ParameterName
            break
        }

        'NativeRuntimeKey'
        {
            $resolvedCommandName = $RuntimeKey
            $resolvedParameterName = $null
            $resolvedIsNative = [bool] $Native
            break
        }

        'RuntimeKey'
        {
            $match = [System.Text.RegularExpressions.Regex]::Match($RuntimeKey, '^(.*):([^:]+)$')

            if (-not $match.Success)
            {
                throw "Parameter completer runtime keys must use the format 'Command:Parameter'. Received '$RuntimeKey'."
            }

            $resolvedCommandName = $match.Groups[1].Value
            $resolvedParameterName = $match.Groups[2].Value
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedCommandName))
    {
        throw 'Completer targets require a non-empty command name.'
    }

    if (-not $resolvedIsNative -and [string]::IsNullOrWhiteSpace($resolvedParameterName))
    {
        throw 'Command-parameter completer targets require a non-empty parameter name.'
    }

    $resolvedKey = $RuntimeKey.ToLowerInvariant()

    $target = [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterTarget'
        Key           = $resolvedKey
        RuntimeKey    = $RuntimeKey
        CommandName   = $resolvedCommandName
        ParameterName = if ($resolvedIsNative) { $null } else { $resolvedParameterName }
        IsNative      = $resolvedIsNative
        TargetType    = if ($resolvedIsNative) { 'Native' } else { 'CommandParameter' }
    }

    return $target
}
<#
.SYNOPSIS
Resolves one or more public cmdlet inputs into completer targets.

.DESCRIPTION
Expands array-based public command inputs into the normalized target objects used
throughout the module. Command and parameter arrays are paired by position when
they have matching lengths, or broadcast when either side contains a single
value.

.PARAMETER CommandName
One or more command names to resolve.

.PARAMETER ParameterName
One or more parameter names to resolve for command-parameter targets.

.PARAMETER Native
Indicates that the targets refer to native completers.

.OUTPUTS
CompleterActions.CompleterTarget
#>
function Resolve-CompleterTargetList
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    switch ($PSCmdlet.ParameterSetName)
    {
        'Native'
        {
            foreach ($commandNameItem in $CommandName)
            {
                Resolve-CompleterTarget -CommandName $commandNameItem -Native
            }

            break
        }

        'CommandParameter'
        {
            $commandCount = $CommandName.Count
            $parameterCount = $ParameterName.Count

            if ($commandCount -ne $parameterCount -and $commandCount -ne 1 -and $parameterCount -ne 1)
            {
                throw 'CommandName and ParameterName arrays must have matching lengths, or one side must provide a single value to broadcast.'
            }

            $iterationCount = [Math]::Max($commandCount, $parameterCount)

            for ($index = 0; $index -lt $iterationCount; $index++)
            {
                $resolvedCommandName = if ($commandCount -eq 1) { $CommandName[0] } else { $CommandName[$index] }
                $resolvedParameterName = if ($parameterCount -eq 1) { $ParameterName[0] } else { $ParameterName[$index] }

                Resolve-CompleterTarget -CommandName $resolvedCommandName -ParameterName $resolvedParameterName
            }

            break
        }
    }
}
<#
.SYNOPSIS
Writes a generated completer script after checking the bytes it installs.

.DESCRIPTION
Writes the lines to '<path>.<8 hex>.tmp' in the target folder with
Set-Content -Encoding utf8 (UTF-8 without a byte-order mark, the platform
newline, and a final newline). It then checks that file the way
Test-CompleterScript does, parse errors included, and derives its targets the
way Register-Completer -Lazy does. Any finding, or derived targets that differ
from -ExpectedTarget in order or spelling, throws the self-check text. A
checked file is moved into place with File.Move, overwriting only under
-Force; without -Force, a file that appeared at the path before the move makes
the call fail with the already-exists text and stay unchanged. The temporary
file never survives the call.

.PARAMETER Line
The script's lines, without line endings.

.PARAMETER LiteralPath
The .ps1 file to write. A relative path is resolved against the current
PowerShell location. The caller checks that the folder exists and that the
path is not a directory (New-CompleterScript step 1); the helper reports
neither case in its own words.

.PARAMETER ExpectedTarget
The target list the script must register, in order.

.PARAMETER Force
Overwrites an existing file at the path.

.OUTPUTS
System.IO.FileInfo
#>
function Save-CompleterScriptFile
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ExpectedTarget,

        [Parameter()]
        [switch] $Force
    )

    # Set-Content resolves against the PowerShell location, File.Move against the process directory.
    $LiteralPath = [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($LiteralPath))
    $temporaryPath = '{0}.{1}.tmp' -f $LiteralPath, [guid]::NewGuid().ToString('N').Substring(0, 8)

    try
    {
        Set-Content -LiteralPath $temporaryPath -Value $Line -Encoding utf8 -ErrorAction Stop

        $detail = $null
        $finding = @(Get-CompleterScriptFinding -LiteralPath $temporaryPath) | Select-Object -First 1

        if ($null -ne $finding)
        {
            $detail = $finding.Message
        }
        else
        {
            try
            {
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $temporaryPath | Where-Object IsNative | ForEach-Object { [string] $_.CommandName })
            }
            catch
            {
                $derivedTargets = $null
                $detail = $_.Exception.Message
            }

            if ($null -ne $derivedTargets -and -not [System.Linq.Enumerable]::SequenceEqual([string[]] $derivedTargets, [string[]] $ExpectedTarget))
            {
                $derivedList = @($derivedTargets | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', '
                $expectedList = @($ExpectedTarget | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', '
                $detail = 'The script registers {0}, not {1}.' -f $derivedList, $expectedList
            }
        }

        if ($null -ne $detail)
        {
            throw "New-CompleterScript did not produce a conforming script, so nothing was written. This is a defect in CompleterActions; report it at https://github.com/tstager/CompleterActions/issues with the command line you ran. $detail"
        }

        try
        {
            [System.IO.File]::Move($temporaryPath, $LiteralPath, [bool] $Force)
        }
        catch [System.IO.IOException]
        {
            if (-not $Force -and (Test-Path -LiteralPath $LiteralPath))
            {
                throw "The file '$LiteralPath' already exists. Use -Force to overwrite it."
            }

            throw
        }

        Get-Item -LiteralPath $LiteralPath
    }
    finally
    {
        if (Test-Path -LiteralPath $temporaryPath)
        {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}
<#
.SYNOPSIS
Replaces a completer set file with new bytes in one step.

.DESCRIPTION
Writes the bytes to '<path>.<8 hex>.tmp' beside the set and moves that file
over the set with File.Move, replacing it, so a reader sees either the old set
or the new one and never part of either. The temporary file never survives
the call.

A set reached through a symbolic link is written at the link's final target,
with the temporary file beside that target, so the link is kept and the move
stays on the target's volume.

.PARAMETER Bytes
The complete new content of the set file, byte-order mark included.

.PARAMETER LiteralPath
The full path of the set file to replace.

.OUTPUTS
System.IO.FileInfo
Returns the set file at LiteralPath, the link itself when it is one.
#>
function Save-CompleterSetFile
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]] $Bytes,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $temporaryPath = $null

    try
    {
        $linkTarget = [System.IO.File]::ResolveLinkTarget($LiteralPath, $true)
        $destinationPath = if ($null -eq $linkTarget) { $LiteralPath } else { $linkTarget.FullName }
        $temporaryPath = '{0}.{1}.tmp' -f $destinationPath, [guid]::NewGuid().ToString('N').Substring(0, 8)
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        throw $_.Exception.InnerException
    }
    finally
    {
        if ([System.IO.File]::Exists($temporaryPath))
        {
            [System.IO.File]::Delete($temporaryPath)
        }
    }

    [System.IO.FileInfo]::new($LiteralPath)
}
<#
.SYNOPSIS
Sets a value in a runtime completer dictionary by key.
#>
function Set-CompleterRuntimeDictionaryValue
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only mutates in-memory runtime dictionary instances for higher-level callers.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        ([System.Collections.IDictionary] $Dictionary)[$Key] = $Value
        return ([System.Collections.IDictionary] $Dictionary)[$Key]
    }

    $Dictionary[$Key] = $Value

    return $Dictionary[$Key]
}
<#
.SYNOPSIS
Splices new Hash values into the text of a completer set.

.DESCRIPTION
Replaces each given extent of the set's text with its new text and returns the
result, working from the last offset to the first so that every earlier
offset still points where the parse put it. Nothing outside a replaced extent
changes: no line is split or joined there, so the file keeps its line endings,
and a Hash that shares its line with other keys keeps its neighbours. The
extents are the Hash value extents of the parse of this same text, which
Get-CompleterSetEntryExtent reports; they never overlap. Nothing is read or
written.

.PARAMETER Text
The decoded text of the set, the text the extents point into.

.PARAMETER Replacement
One record per value to replace, with Extent, the value's extent in Text, and
Text, what replaces it.

.OUTPUTS
System.String
#>
function Set-CompleterSetHashText
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only returns new text and changes no state.')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject[]] $Replacement
    )

    $builder = [System.Text.StringBuilder]::new($Text)

    foreach ($item in @($Replacement | Sort-Object -Property { $_.Extent.StartOffset } -Descending))
    {
        $null = $builder.Remove($item.Extent.StartOffset, $item.Extent.EndOffset - $item.Extent.StartOffset).Insert($item.Extent.StartOffset, $item.Text)
    }

    $builder.ToString()
}
<#
.SYNOPSIS
Determines whether a custom completer dictionary key is a parameter-only registration.

.DESCRIPTION
Register-ArgumentCompleter accepts -ParameterName without -CommandName and then
stores the completer in the custom completer dictionary under the parameter
name alone, so that dictionary holds two key shapes: 'Command:Parameter' for a
command-parameter completer and a bare parameter name for a completer that
applies to every command with that parameter. This module manages
command-parameter and native targets only, so discovery and the registration
snapshot use this rule to leave the parameter-only entries alone instead of
parsing them as 'Command:Parameter' keys and failing. The rule is the engine's
own key format, not an inference: a 'Command:Parameter' key always contains a
colon and a parameter name never does.

.PARAMETER Key
The key as stored in the custom completer dictionary.

.OUTPUTS
System.Boolean
Returns $true when the key names a parameter-only registration.

.EXAMPLE
Test-CompleterParameterOnlyKey -Key 'Get-Item:Path'

Returns $false because the key is a command-parameter key.

.EXAMPLE
Test-CompleterParameterOnlyKey -Key 'ComputerName'

Returns $true because the key came from Register-ArgumentCompleter
-ParameterName ComputerName without a command name.
#>
function Test-CompleterParameterOnlyKey
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    return $Key.IndexOf(':') -lt 0
}
<#
.SYNOPSIS
Tests whether a runtime completer dictionary contains a key.
#>
function Test-CompleterRuntimeDictionaryKey
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Dictionary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if ($Dictionary -is [System.Collections.IDictionary])
    {
        return ([System.Collections.IDictionary] $Dictionary).Contains($Key)
    }

    return $Dictionary.ContainsKey($Key)
}
<#
.SYNOPSIS
Validates that a completer script uses a supported import shape.

.DESCRIPTION
Checks the script AST for patterns that Import-CompleterScript can safely and
predictably import. Supported scripts must be self-contained, must call
Register-ArgumentCompleter at script scope, and must use literal values for the
registration target and script block. The walk runs in the compiled
CompleterActions.Internal.StrictGrammar class; every unsupported construct it
returns is reported as a CompleterActions.CompleterScriptFinding record, in the
order the walk found it. A conforming script produces no output.

.PARAMETER Ast
The parsed script AST to validate.

.PARAMETER LiteralPath
The source path recorded on each finding.

.OUTPUTS
CompleterActions.CompleterScriptFinding
#>
function Test-CompleterScriptAst
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    try
    {
        $grammarFindings = [CompleterActions.Internal.StrictGrammar]::Test($Ast)
    }
    catch
    {
        # A static-method exception arrives wrapped in a MethodInvocationException whose
        # message names the method; the base exception carries the walk's own text.
        throw $_.Exception.GetBaseException().Message
    }

    foreach ($grammarFinding in $grammarFindings)
    {
        New-CompleterScriptFinding -Path $LiteralPath -Extent $grammarFinding.Extent -Construct $grammarFinding.Construct -Message $grammarFinding.Message -Hint $grammarFinding.Hint
    }
}
<#
.SYNOPSIS
Tests whether a set entry's Hash value has a form this module recognises.

.DESCRIPTION
Returns $true only for a string made of the prefix 'SHA256:' and 64
hexadecimal digits, compared case-insensitively. Any other value, including a
non-string, an empty string, or an unknown prefix such as 'SHA512:', returns
$false, so a reader treats the Hash as absent and falls back to parsing the
script instead of failing.

.PARAMETER Value
The Hash value read from a set entry.

.OUTPUTS
System.Boolean
#>
function Test-CompleterSetHashFormat
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [object] $Value
    )

    $Value -is [string] -and [regex]::IsMatch($Value, '\ASHA256:[0-9A-F]{64}\z', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:CompleterImportedScriptBlocks = [System.Runtime.CompilerServices.ConditionalWeakTable[scriptblock, psobject]]::new()
$script:CompleterHelpProbeTimeoutSeconds = 5
$script:CompleterSetMaxFileBytes = 128KB
