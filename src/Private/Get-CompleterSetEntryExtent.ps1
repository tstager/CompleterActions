<#
.SYNOPSIS
Finds the source positions of a completer set file's entries.

.DESCRIPTION
Parses the set file with the PowerShell parser, never evaluating it, and
returns the position of the Entries key and, for each element of the Entries
array, the element's own extent (the entry's @{ for a hashtable) and the
extents of its Path value, Hash key and value, and Targets key.
Test-CompleterSet uses them to point a finding at the part of the set that
needs fixing.

The elements are walked the way Import-CompleterSetDefinition reads them, so
the positions line up with its entry numbers: an Entries array written with
one element per line and one written with commas both work, and a $null
element is skipped because the definition reader drops it before the entries
are numbered.

.PARAMETER LiteralPath
The full path of the completer set file.

.OUTPUTS
CompleterActions.CompleterSetEntryExtent
Returns one record with EntriesExtent, the extent of the Entries key or of the
whole set when the key cannot be found, and Entries, one record per element
in set order with Extent, PathExtent, HashExtent, and TargetsExtent. An
extent the element does not have is null.
#>
function Get-CompleterSetEntryExtent
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref] $tokens, [ref] $parseErrors)

    # Output of a statement enumerates arrays, as the data reader's @() and
    # pipeline do; the elements of a comma array are not enumerated again.
    $getStatementElement = $null
    $getOutputElement = {
        param($Expression)

        if ($Expression -is [System.Management.Automation.Language.ArrayLiteralAst])
        {
            foreach ($element in $Expression.Elements)
            {
                if (-not ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.VariablePath.UserPath -eq 'null'))
                {
                    $element
                }
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ArrayExpressionAst])
        {
            foreach ($statement in $Expression.SubExpression.Statements)
            {
                & $getStatementElement $statement
            }
        }
        elseif ($Expression -is [System.Management.Automation.Language.ParenExpressionAst])
        {
            & $getStatementElement $Expression.Pipeline
        }
        elseif (-not ($Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and $Expression.VariablePath.UserPath -eq 'null'))
        {
            $Expression
        }
    }
    $getStatementElement = {
        param($Statement)

        if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and
            $Statement.PipelineElements.Count -eq 1 -and
            $Statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst])
        {
            & $getOutputElement $Statement.PipelineElements[0].Expression
        }
        else
        {
            $Statement
        }
    }

    $findKeyValue = {
        param($Hashtable, $Name)

        foreach ($keyValuePair in $Hashtable.KeyValuePairs)
        {
            if ($keyValuePair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $keyValuePair.Item1.Value -eq $Name)
            {
                return $keyValuePair
            }
        }
    }

    $setHashtable = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    $entriesPair = if ($null -ne $setHashtable) { & $findKeyValue $setHashtable 'Entries' }
    $entryExtents = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $entriesPair)
    {
        foreach ($element in @(& $getStatementElement $entriesPair.Item2))
        {
            $pathPair = $null
            $hashPair = $null
            $targetsPair = $null

            if ($element -is [System.Management.Automation.Language.HashtableAst])
            {
                $pathPair = & $findKeyValue $element 'Path'
                $hashPair = & $findKeyValue $element 'Hash'
                $targetsPair = & $findKeyValue $element 'Targets'
            }

            $entryExtents.Add([pscustomobject] [ordered] @{
                    Extent        = $element.Extent
                    PathExtent    = if ($null -ne $pathPair) { $pathPair.Item2.Extent } else { $null }
                    HashExtent    = if ($null -ne $hashPair) { $hashPair.Item2.Extent } else { $null }
                    TargetsExtent = if ($null -ne $targetsPair) { $targetsPair.Item1.Extent } else { $null }
                })
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName    = 'CompleterActions.CompleterSetEntryExtent'
        EntriesExtent = if ($null -ne $entriesPair) { $entriesPair.Item1.Extent } else { $ast.Extent }
        Entries       = $entryExtents.ToArray()
    }
}
