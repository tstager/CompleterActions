<#
.SYNOPSIS
Validates one completer set entry and resolves its script path and targets.

.DESCRIPTION
Normalizes a raw entry hashtable from a completer set into a record that
Import-CompleterSet can register, collecting every problem instead of stopping
at the first so the caller can report all of them at once. A Path that is not
fully qualified, a drive-relative form such as C:scripts\x.ps1 included,
resolves against the set file's directory rather than the current location.
Trusted defaults to false. Trusted
entries must declare Targets because the script is not parsed. Strict entries
must register their targets with literal arguments so the targets can be
derived from the parsed script and, when the entry also declares Targets, the
two lists must match; the strict import grammar itself runs when the script
loads. Every target is then held to the rules Register-CompleterRegistration
applies through Resolve-CompleterRegistrationConflict, so a target that already
carries a different registration is a problem unless -Force is given, and a
target that an earlier valid entry of the same set already claimed is always a
problem. A valid entry claims its targets in ClaimedTargets for the entries
after it, and its Targets are the resolved records Register-CompleterSetEntry
registers, so a strict script is parsed once per import. The script is never
executed.

.PARAMETER Entry
The raw entry value from the set file's Entries array.

.PARAMETER Index
The one-based position of the entry in the set file, used in messages.

.PARAMETER SetDirectory
The directory that relative entry paths resolve against.

.PARAMETER ClaimedTargets
The dictionary, shared by every entry of one set, that maps a claimed target
key to the index of the valid entry that claimed it.

.PARAMETER Force
Indicates that the set is imported with -Force, so existing registrations for
its targets are replaced rather than reported.

.OUTPUTS
CompleterActions.CompleterSetEntry
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

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $ClaimedTargets,

        [Parameter()]
        [switch] $Force
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $declaredPath = $null
    $resolvedPath = $null
    $scriptIsUsable = $false
    $trusted = $false
    $declaredTargets = $null
    $targets = @()

    if ($Entry -isnot [System.Collections.IDictionary])
    {
        $problems.Add('The entry is not a hashtable with Path, Trusted, and Targets keys.')
    }
    else
    {
        if (-not $Entry.Contains('Path') -or [string]::IsNullOrWhiteSpace([string] $Entry['Path']))
        {
            $problems.Add('The entry has no Path.')
        }
        else
        {
            $declaredPath = [string] $Entry['Path']
            $resolvedPath = [System.IO.Path]::GetFullPath($declaredPath, $SetDirectory)

            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
            {
                $problems.Add("The file '$resolvedPath' does not exist.")
            }
            elseif ([System.IO.Path]::GetExtension($resolvedPath) -ne '.ps1')
            {
                $problems.Add("The file '$resolvedPath' is not a .ps1 script.")
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
                $problems.Add('Trusted must be $true or $false.')
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
                        $problems.Add('Each target must be a hashtable with CommandName and either Native = $true or ParameterName.')
                        continue
                    }

                    $commandName = if ($targetEntry.Contains('CommandName')) { [string] $targetEntry['CommandName'] } else { $null }

                    if ([string]::IsNullOrWhiteSpace($commandName))
                    {
                        $problems.Add('A target has no CommandName.')
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
                            $problems.Add("Target '$commandName' must declare Native = `$true or a ParameterName.")
                        }
                    }
                    catch
                    {
                        $problems.Add($_.Exception.Message)
                    }
                }
            )
        }

        if ($trusted)
        {
            if ($null -eq $declaredTargets)
            {
                $problems.Add('Trusted entries must declare Targets, because a trusted script is not parsed for them.')
            }
            else
            {
                $targets = $declaredTargets
            }
        }
        elseif ($scriptIsUsable)
        {
            $derivedTargets = @()

            try
            {
                $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $resolvedPath)
            }
            catch
            {
                $problems.Add($_.Exception.Message)
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
                        $problems.Add("The declared Targets do not match the script. Declared: $declaredList. Script registers: $derivedList.")
                    }
                    else
                    {
                        $targets = $derivedTargets
                    }
                }
            }
        }
    }

    foreach ($target in $targets)
    {
        $conflict = Resolve-CompleterRegistrationConflict -Target $target -ScriptPath $resolvedPath -Trusted:$trusted -Lazy -Force:$Force

        if ($null -ne $conflict.Problem)
        {
            $problems.Add($conflict.Problem)
        }

        if ($ClaimedTargets.Contains([string] $target.Key))
        {
            $problems.Add("Target '$($target.RuntimeKey)' is also listed by entry $($ClaimedTargets[[string] $target.Key]).")
        }
    }

    if ($problems.Count -eq 0)
    {
        foreach ($target in $targets)
        {
            $ClaimedTargets[[string] $target.Key] = $Index
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName   = 'CompleterActions.CompleterSetEntry'
        Index        = $Index
        DeclaredPath = $declaredPath
        Path         = $resolvedPath
        Trusted      = $trusted
        Targets      = @($targets)
        Problems     = @($problems)
        IsValid      = $problems.Count -eq 0
    }
}
