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
runs when the script loads. A strict script is parsed once here and the
targets it yields are the ones the import registers. The script is never
executed.

Each problem is a hashtable with Kind and Message. Kind is InvalidEntry,
MissingScript, UnreadableTargets, or TargetMismatch; Message is the text
Import-CompleterSet reports.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.OUTPUTS
CompleterActions.CompleterSetEntry
Returns a record with Index, DeclaredPath, Path, Trusted, Targets,
DeclaredHash (the entry's raw Hash value, or null), TargetSource (Trusted for
a trusted entry, Parsed for a strict entry whose script was parsed, or null
when neither applies), Problems, and IsValid. Registrations and Conflicts are
empty until Resolve-CompleterSetRegistration fills them.
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
        [string] $SetDirectory
    )

    $problems = [System.Collections.Generic.List[hashtable]]::new()
    $declaredPath = $null
    $resolvedPath = $null
    $declaredHash = $null
    $targetSource = $null
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

            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
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
        }
        elseif ($scriptIsUsable)
        {
            $targetSource = 'Parsed'
            $derivedTargets = @()

            try
            {
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $resolvedPath)
            }
            catch
            {
                $problems.Add(@{ Kind = 'UnreadableTargets'; Message = $_.Exception.Message })
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

    [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterSetEntry'
        Index         = $Index
        DeclaredPath  = $declaredPath
        Path          = $resolvedPath
        Trusted       = $trusted
        DeclaredHash  = $declaredHash
        TargetSource  = $targetSource
        Targets       = @($targets)
        Registrations = @()
        Conflicts     = @()
        Problems      = @($problems)
        IsValid       = $problems.Count -eq 0
    }
}
