<#
.SYNOPSIS
Warns once per process that a legacy command name is deprecated.

.DESCRIPTION
Emits a single Write-Warning per process for a legacy command name, naming
the replacement command and the about_CompleterActions_Migration topic. The
names that have already warned are tracked in the module-scope set created by
Bootstrap.ps1, so a profile that calls a legacy name many times sees the
warning once.

.PARAMETER LegacyName
The deprecated command name the caller used.

.PARAMETER NewName
The command that replaces it.

.EXAMPLE
PS> Write-CompleterDeprecationWarning -LegacyName 'Get-CompleterRegistration' -NewName 'Get-Completer'
#>
function Write-CompleterDeprecationWarning
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LegacyName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $NewName
    )

    if ($script:CompleterDeprecationWarningsIssued.Add($LegacyName))
    {
        Write-Warning -Message "$LegacyName is deprecated and will be removed in 3.0; use $NewName instead. See about_CompleterActions_Migration."
    }
}
