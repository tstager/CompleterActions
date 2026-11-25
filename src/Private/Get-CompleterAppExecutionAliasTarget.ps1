<#
.SYNOPSIS
Reads the target of a Windows app execution alias.

.DESCRIPTION
Calls CompleterActions.Internal.AppExecutionAlias.GetTarget, which reads the
file's reparse data. An app execution alias is a zero-byte reparse point with
the tag IO_REPARSE_TAG_APPEXECLINK; the third string of its data is the
executable it starts. Nothing is run, and nothing is read on Linux or macOS.

.PARAMETER LiteralPath
The full path of the file to read.

.OUTPUTS
System.String
Returns null when the file is not an app execution alias or its reparse data
cannot be read, the empty string for an alias with no target, and otherwise
the target path as the alias gives it.
#>
function Get-CompleterAppExecutionAliasTarget
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    [CompleterActions.Internal.AppExecutionAlias]::GetTarget($LiteralPath)
}
