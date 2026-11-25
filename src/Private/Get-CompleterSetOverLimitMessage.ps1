<#
.SYNOPSIS
Words the refusal of a completer set that would be written over the size limit.

.DESCRIPTION
Returns the one text Export-CompleterSet and Update-CompleterSet give when the
set they would write is larger than $script:CompleterSetMaxFileBytes, the
limit Import-CompleterSet and Test-CompleterSet read up to, so both commands
word it alike.

.PARAMETER ByteCount
The size in bytes of the set that would be written.

.OUTPUTS
System.String
#>
function Get-CompleterSetOverLimitMessage
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $ByteCount
    )

    "The set would be $ByteCount bytes, larger than the $script:CompleterSetMaxFileBytes-byte limit for completer set files, so Import-CompleterSet could not read it. Export the registrations as several sets. Nothing was written."
}
