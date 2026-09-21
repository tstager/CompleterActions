<#
.SYNOPSIS
Writes a completer set file from registrations that came from scripts.

.DESCRIPTION
Groups registration records by the completer script they came from and writes
a completer set: a .psd1 data file that lists each script once with its trust
tier and the targets it registers. Import-CompleterSet reads the file back and
registers everything in it, so a profile that imports a completer repository
becomes one Import-CompleterSet call.

Records arrive through -InputObject, typically from Get-CompleterRegistration
or Import-CompleterScript. Without -InputObject the command exports every
managed registration that records a ScriptPath. Script paths are written
relative to the set file when both share a root, so a repository can carry its
set file alongside its scripts; paths on another drive stay absolute. The
Trusted flag of each entry is taken from the records, and records for the same
script must agree on it.

A strict entry must list every target its script registers, because
Import-CompleterSet compares a strict entry's Targets with the targets derived
from the parsed script and rejects a mismatch. The command derives those
targets the same way before writing and refuses, naming the missing targets
and leaving the output untouched, when the records for a strict script cover
only some of them, as they do after Register-CompleterRegistration -Lazy
-CommandName selected a subset. Trusted entries are written with the targets
the records carry, so a subset of a trusted script's targets exports and
imports as given.

.PARAMETER Path
The path of the .psd1 file to write. The parent directory must exist.

.PARAMETER InputObject
Registration records to export. Each record must describe a target and expose
the script it came from through a ScriptPath or SourcePath property. Records
without a script path cannot be expressed in a set and are rejected.

.PARAMETER PassThru
Returns the written file.

.OUTPUTS
System.IO.FileInfo
When -PassThru is used, returns the written set file.

.EXAMPLE
PS> Export-CompleterSet -Path ~\Completers\completers.psd1

Writes every managed registration that came from a script into a set file next
to the scripts.

.EXAMPLE
PS> Get-ChildItem ~\Completers -Recurse -Filter *_completer.ps1 | Import-CompleterScript | Export-CompleterSet -Path ~\Completers\completers.psd1

Builds a set from a completer repository without registering anything in the
current session.
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
        [ValidateNotNull()]
        [object[]] $InputObject,

        [Parameter()]
        [switch] $PassThru
    )

    begin
    {
        $outputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

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
        $inputBound = $false
    }

    process
    {
        if ($PSBoundParameters.ContainsKey('InputObject'))
        {
            $inputBound = $true
            $records.AddRange([psobject[]] @($InputObject))
        }
    }

    end
    {
        try
        {
            if (-not $inputBound)
            {
                $records.AddRange([psobject[]] @(Get-CompleterRegistration -ManagedOnly | Where-Object { $_.PSObject.Properties['ScriptPath'] -and -not [string]::IsNullOrWhiteSpace([string] $_.ScriptPath) }))
            }

            $entriesByPath = [ordered] @{}

            foreach ($record in $records)
            {
                $scriptPath = $null

                foreach ($propertyName in 'ScriptPath', 'SourcePath')
                {
                    $property = $record.PSObject.Properties[$propertyName]

                    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value))
                    {
                        $scriptPath = [System.IO.Path]::GetFullPath([string] $property.Value)
                        break
                    }
                }

                if ($null -eq $scriptPath)
                {
                    throw 'InputObject must expose the script it came from through a ScriptPath or SourcePath property; registrations created from an in-memory script block cannot be exported to a set.'
                }

                $target = ($record | Resolve-CompleterInputObject).Target
                $trustedProperty = $record.PSObject.Properties['Trusted']
                $trusted = $null -ne $trustedProperty -and [bool] $trustedProperty.Value

                if (-not $entriesByPath.Contains($scriptPath))
                {
                    $entriesByPath[$scriptPath] = [pscustomobject] [ordered] @{
                        Path    = $scriptPath
                        Trusted = $trusted
                        Targets = [ordered] @{}
                    }
                }

                $entry = $entriesByPath[$scriptPath]

                if ($entry.Trusted -ne $trusted)
                {
                    throw "The records for '$scriptPath' disagree on Trusted, so the entry's trust tier cannot be written."
                }

                $entry.Targets[[string] $target.Key] = $target
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

                $derivedKeys = @(Get-CompleterScriptTarget -LiteralPath $entry.Path | ForEach-Object { [string] $_.Key })
                $missingTargets = @($derivedKeys | Where-Object { -not $entry.Targets.Contains($_) })
                $unknownTargets = @($entry.Targets.Keys | Where-Object { $_ -notin $derivedKeys })

                if ($missingTargets.Count -eq 0 -and $unknownTargets.Count -eq 0)
                {
                    continue
                }

                $problem = "The strict entry for '$($entry.Path)' cannot be imported as a set entry because its targets do not match the script."

                if ($missingTargets.Count -gt 0)
                {
                    $problem += " Missing: $(@($missingTargets | ForEach-Object { "'$_'" }) -join ', ')."
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
                $relativePath = [System.IO.Path]::GetRelativePath($outputDirectory, $entry.Path)
                $writtenPath = if ([System.IO.Path]::IsPathRooted($relativePath)) { $entry.Path } else { $relativePath.Replace('\', '/') }

                $lines.Add('        @{')
                $lines.Add("            Path    = '$($writtenPath.Replace("'", "''"))'")
                $lines.Add("            Trusted = `$$($entry.Trusted.ToString().ToLowerInvariant())")
                $lines.Add('            Targets = @(')

                foreach ($target in $entry.Targets.Values)
                {
                    $commandName = ([string] $target.CommandName).Replace("'", "''")

                    if ($target.IsNative)
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; Native = `$true }")
                    }
                    else
                    {
                        $lines.Add("                @{ CommandName = '$commandName'; ParameterName = '$(([string] $target.ParameterName).Replace("'", "''"))' }")
                    }
                }

                $lines.Add('            )')
                $lines.Add('        }')
            }

            $lines.Add('    )')
            $lines.Add('}')

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
