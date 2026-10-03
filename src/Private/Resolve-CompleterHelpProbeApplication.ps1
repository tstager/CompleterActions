<#
.SYNOPSIS
Resolves the program a help probe would run and decides whether it may run.

.DESCRIPTION
Resolves the name with Get-Command -CommandType Application and takes the
first match, so a function, alias, cmdlet, or script of that name is never
chosen. -ErrorAction Ignore keeps a missing command from throwing under
$ErrorActionPreference = 'Stop'. Nothing is run.

On Windows the resolved file may run only when it is a .exe whose PE header
reads as Subsystem 3 (Windows CUI). Any other file gets a reason: a GUI
program (Subsystem 2), another subsystem, an unreadable header, or an
extension that only runs through cmd.exe. On Linux and macOS every resolved
application may run.

The warning text is returned as data; this helper writes no stream.

.PARAMETER Name
The command name to resolve, as the author gave it.

.OUTPUTS
CompleterActions.CompleterHelpProbeApplication
Returns a record with Name (as given), Path (the resolved file, or null when
nothing was found), CanRun, and Warning (the not-found or not-run text, or
null when the application may run).
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

    $application = Get-Command -Name $Name -CommandType Application -ErrorAction Ignore | Select-Object -First 1

    $path = $null
    $warning = $null
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
                    $reason = 'its program header could not be read'
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
        PSTypeName = 'CompleterActions.CompleterHelpProbeApplication'
        Name       = $Name
        Path       = $path
        CanRun     = $null -ne $path -and $null -eq $warning
        Warning    = $warning
    }
}
