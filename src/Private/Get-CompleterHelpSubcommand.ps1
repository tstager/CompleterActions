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
gives its warning and an empty table. For a run that exited, the text is
standard output, or standard error when standard output is empty or
whitespace after decoding; the exit code decides nothing. The text is decoded,
cleaned, and parsed with the help text helpers. Each run that exited adds one
probe verbose line.

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
(the argument of the run whose result was used, or null when nothing ran),
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
        [AllowEmptyString()]
        [string] $HelpArgument,

        [Parameter(Mandatory)]
        [ValidateRange(0.001, 3600)]
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
        $argument = if ($hasHelpArgument) { $HelpArgument } else { '--help' }
        $limit = $TimeoutSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)

        while ($true)
        {
            $result = Invoke-CompleterHelpProcess -FilePath $Application.Path -ArgumentList @($argument) -TimeoutSeconds $TimeoutSeconds

            switch ($result.Status)
            {
                'TimedOut'
                {
                    $warnings.Add("'$($Application.Name) $argument' did not exit within $limit seconds and was stopped, so its help was not used.")
                }
                'HeldOutput'
                {
                    $warnings.Add("'$($Application.Name) $argument' exited but left a process holding its output, so its help was not used.")
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

            $argument = '/?'
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
