<#
.SYNOPSIS
Splices new Hash values into the text of a completer set.

.DESCRIPTION
Replaces each given extent of the set's text with its new text and returns the
result, working from the last offset to the first so that every earlier
offset still points where the parse put it. Nothing outside a replaced extent
changes: no line is split or joined there, so the file keeps its line endings,
and a Hash that shares its line with other keys keeps its neighbours. The
extents are the Hash value extents of the parse of this same text, which
Get-CompleterSetEntryExtent reports; they never overlap. Nothing is read or
written.

.PARAMETER Text
The decoded text of the set, the text the extents point into.

.PARAMETER Replacement
One record per value to replace, with Extent, the value's extent in Text, and
Text, what replaces it.

.OUTPUTS
System.String
#>
function Set-CompleterSetHashText
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This private helper only returns new text and changes no state.')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject[]] $Replacement
    )

    $builder = [System.Text.StringBuilder]::new($Text)

    foreach ($item in @($Replacement | Sort-Object -Property { $_.Extent.StartOffset } -Descending))
    {
        $null = $builder.Remove($item.Extent.StartOffset, $item.Extent.EndOffset - $item.Extent.StartOffset).Insert($item.Extent.StartOffset, $item.Text)
    }

    $builder.ToString()
}
