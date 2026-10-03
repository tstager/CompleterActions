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
set file's directory rather than the current location. Trusted defaults to
false. Trusted entries must declare Targets because the script is not parsed.
Strict entries must register their targets with literal arguments so the
targets can be derived from the parsed script and, when the entry also
declares Targets, the two lists must match; the strict import grammar itself
runs when the script loads. A strict script is parsed at most once here and
the targets it yields are the ones the import registers. The script is never
executed.

The fast path skips that parse. When a strict entry has no problem so far,
declares Targets, and carries a Hash whose form Test-CompleterSetHashFormat
recognises, the script's text is hashed and compared with it. On a match the
declared Targets are used as they are, in declared order and de-duplicated by
Key with the first occurrence kept, because the export that wrote the Hash
derived those targets from the same text. An absent, unrecognised, or
different Hash, or a script that cannot be read for its hash, falls through
to the parse, so such an entry gets exactly the problems it would get with
no Hash at all. A trusted entry's Hash is ignored and its script is not read.

When ModuleBase is given, as Import-CompleterSet -Name gives it, the
resolved path must lie inside that folder, compared with a trailing separator
and with the platform's case rule (case-insensitive on Windows and macOS,
case-sensitive on Linux). An entry outside it gets the OutsideModule problem
and no existence, extension, hash, or parse check, so its file is never
opened.

Each problem is a hashtable with Kind and Message. Kind is InvalidEntry,
MissingScript, OutsideModule, UnreadableTargets, or TargetMismatch; Message
is the text Import-CompleterSet reports.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.PARAMETER Verify
Disables the fast path, so every strict entry whose script is usable is
parsed once, and records the script's actual hash and parse-derived targets
for drift checks. A trusted entry's script is read for its hash but still not
parsed.

.PARAMETER ModuleName
The installed module folder's name, used in the OutsideModule problem.

.PARAMETER ModuleBase
The full path of the module folder the entry's script must stay inside.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns a record with Index, DeclaredPath, Path, Trusted, Targets,
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
            $resolvedPath = [System.IO.Path]::GetFullPath($declaredPath.Replace('\', '/'), $SetDirectory)

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

                    try
                    {
                        if ($targetEntry.Contains('Native') -and $targetEntry['Native'] -eq $true)
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
                $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
                $targets = @(
                    foreach ($declaredTarget in $declaredTargets)
                    {
                        if ($seenKeys.Add([string] $declaredTarget.Key))
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
                    $declaredKeys = @($declaredTargets | ForEach-Object { [string] $_.Key })
                    $derivedKeys = @($derivedTargets | ForEach-Object { [string] $_.Key })
                    $mismatch = @($declaredKeys | Where-Object { $_ -notin $derivedKeys }).Count -gt 0 -or @($derivedKeys | Where-Object { $_ -notin $declaredKeys }).Count -gt 0

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
