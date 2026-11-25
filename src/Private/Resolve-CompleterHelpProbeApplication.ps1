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
