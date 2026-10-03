<#
.SYNOPSIS
Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.

.DESCRIPTION
Writes a native completer script for one or more command names: a guarded,
literal-only table of subcommands, a Complete-<Stem> function that offers them
in the first argument position, and one bare Register-ArgumentCompleter call
that names every target. The file passes Test-CompleterScript and imports with
Import-CompleterScript and Register-Completer -Lazy before the author edits it.

The first -CommandName value is the primary name: it names the functions and
the state variable, and it is the one probed. Every name must be a bare command
name. The target list follows the -CommandName order, and a name that does not
end in .exe, .cmd, .bat, .ps1, or .com is followed by the same name with .exe
appended, so -CommandName rg registers 'rg' and 'rg.exe'.

The subcommand table is seeded in one of three ways. By default the command
runs the primary name's help and parses its commands section. -HelpText parses
help text the author already captured and runs nothing. -NoProbe runs nothing
and writes an empty table.

The probe runs only an application that Get-Command resolves; a function,
alias, cmdlet, or script of that name is never run. On Windows it runs only
a .exe whose PE header marks a console program, so GUI programs, shims such as
npm.cmd, and app execution aliases are refused with a warning. The program
runs with the help argument alone, standard input closed, the temporary
directory as its working directory, and NO_COLOR set, under a 5-second limit.
Without -HelpArgument the probe passes --help; on Windows, when --help ran to
completion, gave no subcommand, and printed fewer than five non-blank lines,
/? runs once and its result is used. A run that does not exit in time, or that
leaves a process holding its output, is stopped and its output is not used.
-WhatIf and -Confirm name the program before anything runs.

Before anything is resolved, probed, or written, every -CommandName value and
the -Path are checked: the path must end in .ps1, must not be a directory, and
its folder must exist, and the file must not exist unless -Force is given. The
script is written to a temporary file beside the target, checked with the
strict grammar Test-CompleterScript applies, and moved into place only when it
conforms and registers exactly the target list; otherwise nothing is written.
The file is UTF-8 without a byte-order mark, with the platform newline and a
final newline.

Every failure is a terminating error that begins 'Failed to create completer
script.', and a failed call leaves nothing at the path.

.PARAMETER CommandName
The native command names. The first is the primary name: it names the
functions and state, and it is the one probed.

.PARAMETER Path
The .ps1 file to write. A relative path is resolved against the current
location. The parent directory must exist.

.PARAMETER HelpArgument
The one argument the probe passes. When omitted the probe passes --help and,
on Windows, may fall back to /?.

.PARAMETER HelpText
Help text the author already captured. Lines are accumulated across pipeline
input, joined with LF, cleaned, and parsed; nothing is run.
winget --help | New-CompleterScript winget .\winget_completer.ps1 binds here.

.PARAMETER NoProbe
Runs nothing and writes an empty subcommand table.

.PARAMETER Force
Overwrites an existing file.

.PARAMETER PassThru
Returns the written file as System.IO.FileInfo, so it pipes into
Test-CompleterScript and Import-CompleterScript. Without -PassThru the
command returns nothing.

.INPUTS
System.String
Help text lines, bound to -HelpText.

.OUTPUTS
System.IO.FileInfo
When -PassThru is used, returns the written script file.

.EXAMPLE
PS> New-CompleterScript -CommandName cargo -Path .\cargo_completer\cargo_completer.ps1 -PassThru | Test-CompleterScript

Writes the cargo skeleton seeded from 'cargo --help' and checks it; the
pipeline is empty.

.EXAMPLE
PS> winget --help | New-CompleterScript -CommandName winget -Path .\winget_completer\winget_completer.ps1

Seeds the table from help the author ran, for a command the probe will not
run.

.EXAMPLE
PS> New-CompleterScript -CommandName mytool -Path .\mytool_completer.ps1 -NoProbe -Force

Writes an empty skeleton without running anything, replacing an existing file.
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
