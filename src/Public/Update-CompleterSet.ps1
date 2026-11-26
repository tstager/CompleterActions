<#
.SYNOPSIS
Rewrites the Hash of each completer set entry whose script has changed, leaving the rest of the set file as it is.

.DESCRIPTION
Reads each completer set once, verifies every entry the way Test-CompleterSet
does, and replaces the Hash value of each entry whose script has changed since
the set was written, or whose Hash is not 'SHA256:' followed by 64 hexadecimal
digits, with the script's current hash, written as Export-CompleterSet writes
it: a single-quoted 'SHA256:' followed by 64 upper-case hexadecimal digits.
Nothing else in the file changes. An entry whose Hash equals its script's,
ignoring letter case, is not touched. The command never adds an entry or a
Hash; regenerate the set with Export-CompleterSet for that.

An entry is updated only when it has a Hash value, its script can be read,
and Test-CompleterSet reports no Error for it: no MissingScript, InvalidEntry,
UnreadableTargets, TargetMismatch, or DuplicateTarget. A matching Hash makes
Import-CompleterSet take a strict entry's Targets without comparing them with
the script, so rehashing an entry whose targets also changed would make the
import register stale targets unchecked. Such an entry is left as it is, with
a warning that names its first Error, whether or not its Hash differs, and the
set needs Export-CompleterSet. An entry that is not trusted, whose Hash
differs, and whose script no longer passes the strict grammar is left as it is
too, with a warning that names the first grammar Error as Test-CompleterScript
words it, because a matching Hash would let the import skip the grammar and
move the failure to the first tab. A trusted entry is updated, with a warning,
because its script is never parsed, so its Targets cannot be checked; import
ignores a trusted entry's Hash, which only feeds Test-CompleterSet. One
warning per set counts the entries without a Hash, and one warning names each
script under the set's folder that matches -Filter and that no entry lists.

The file is read once as bytes and decoded as Import-CompleterSet decodes it,
as UTF-8 unless a byte-order mark names another encoding. Each new value is
spliced into the text where the old value was parsed, last entry first, so no
line outside a replaced value is split or joined: a file with LF line endings
keeps them, and a Hash that shares its line with other keys keeps them. A
double-quoted or here-string Hash becomes the single-quoted form, on one line.
The result is encoded with the same encoding and byte-order mark and written
through a temporary file beside the set and a replacing move, so a reader sees
the old set or the new one. A set reached through a symbolic link is written
at the link's final target, and the link is kept. Nothing is written when the
set's text does not give back its bytes in its encoding, such as a set with an
invalid UTF-8 byte, when the new text does not read back as the same entries,
paths, and targets, or when it would be larger than the 128 KB (131072-byte)
limit that Import-CompleterSet reads. A set with nothing to update is not written, and
its timestamp does not change.

Every set is resolved as it arrives and updated once, in the end block, so a
piped Test-CompleterSet has finished reading before anything is written, and a
set named by many findings is still read and written once. A set that cannot
be read stops the call with a terminating error after the sets before it were
updated. With -WhatIf nothing is written, and the warnings are still written.

.PARAMETER Path
The path to a completer set file. Wildcards are supported.

.PARAMETER LiteralPath
The literal path to a completer set file. Wildcards are not expanded.

.PARAMETER InputObject
The CompleterActions.CompleterScriptFinding records Test-CompleterSet returns,
from the pipeline or by name. Only each finding's Path, the set file, is used,
taken literally, and each set is updated once however many findings name it.
A finding names the set to update, not the entries: every entry of that set is
verified again. Given positionally, a finding binds to -Path as text.

.PARAMETER Filter
The file-name pattern of the scan for scripts that no entry lists. The scan is
recursive under the set file's directory. The default is *_completer.ps1.

.PARAMETER PassThru
Returns the System.IO.FileInfo of each set that was written.

.OUTPUTS
System.IO.FileInfo
With -PassThru, returns each set file that was written; otherwise the command
returns nothing.

.EXAMPLE
PS> Update-CompleterSet -Path ~\Completers\completers.psd1

Rewrites the Hash of every entry whose script changed since the set was
written, and warns about each entry it leaves for Export-CompleterSet.

.EXAMPLE
PS> Test-CompleterSet -Path ~\Completers\completers.psd1 | Update-CompleterSet

Updates the set the drift report names, once, after the report has read it.

.EXAMPLE
PS> Update-CompleterSet -Path ~\Completers\completers.psd1 -WhatIf

Reports how many Hash values would be rewritten, and writes the same warnings,
without changing the file.
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
                    else
                    {
                        # A matching Hash lets Import-CompleterSet skip the strict
                        # grammar, which would move this failure to the first tab.
                        $grammarError = @(Get-CompleterScriptFinding -LiteralPath $entry.Path | Where-Object -Property Severity -EQ -Value 'Error') | Select-Object -First 1

                        if ($null -ne $grammarError)
                        {
                            Write-Warning -Message "$entryLabel of '$setFile' was not updated: $($grammarError.Message.TrimEnd('.')). Regenerate the set with Export-CompleterSet."
                            continue
                        }
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
                    throw "Completer set '$setFile' would be $($newBytes.Length) bytes after the update, which is larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files. Split its entries across several sets and regenerate them with Export-CompleterSet."
                }

                $hashValueNoun = if ($updates.Count -eq 1) { 'Hash value' } else { 'Hash values' }

                if (-not $PSCmdlet.ShouldProcess($setFile, "Update $($updates.Count) $hashValueNoun"))
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
