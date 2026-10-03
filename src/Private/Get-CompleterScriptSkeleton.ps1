<#
.SYNOPSIS
Composes the lines of a generated native completer script.

.DESCRIPTION
Returns the skeleton New-CompleterScript writes, one string per line and
without line endings: the two comment lines, Set-StrictMode, one guarded
literal-only state block holding the subcommand table, a Complete-<Stem>
completion function that offers the table in the first argument position, and
one bare script-scope Register-ArgumentCompleter call with a literal -CommandName list.
Every string literal is single-quoted with its quote characters doubled. The
output names no date, version, or machine path, so the same input always gives
the same lines. The generated code uses four-space indentation and opening
braces on the same line, because it belongs to the author's repository.

.PARAMETER Name
The primary command name, as given. Line 1 names it, and so does line 2 of a
probe-seeded script.

.PARAMETER Stem
The stem from ConvertTo-CompleterScriptStem.

.PARAMETER Target
The target list from ConvertTo-CompleterTargetName.

.PARAMETER Subcommand
The subcommand rows, each with a Name and a Description, in help order. An
empty list writes an empty table and the skeleton line 2.

.PARAMETER SeedKind
Where a non-empty table came from: Probe or HelpText. It picks line 2.

.PARAMETER ProbeArgument
The argument whose output seeded the table. Required with -SeedKind Probe.

.OUTPUTS
System.String
#>
function Get-CompleterScriptSkeleton
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Stem,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Target,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Subcommand,

        [Parameter()]
        [ValidateSet('Probe', 'HelpText')]
        [string] $SeedKind,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ProbeArgument
    )

    $catalogName = '{0}CompletionCatalog' -f $Stem
    $functionName = 'Complete-{0}' -f $Stem

    if ($Subcommand.Count -eq 0)
    {
        $sourceLine = '# Native completer skeleton: add subcommands to the table and options to {0}.' -f $functionName
    }
    elseif ($SeedKind -eq 'Probe' -and $PSBoundParameters.ContainsKey('ProbeArgument'))
    {
        $sourceLine = "# Help-seeded native completer: the subcommand table was read from '{0} {1}' when the script was generated." -f $Name, $ProbeArgument
    }
    elseif ($SeedKind -eq 'HelpText')
    {
        $sourceLine = '# Help-seeded native completer: the subcommand table was read from help text passed to New-CompleterScript.'
    }
    else
    {
        throw 'A non-empty subcommand table needs -SeedKind HelpText, or -SeedKind Probe with -ProbeArgument.'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('# {0} tab completion for PowerShell' -f $Name))
    $lines.Add($sourceLine)
    $lines.Add('')
    $lines.Add('Set-StrictMode -Version 2.0')
    $lines.Add('')
    $lines.Add(('if (-not (Get-Variable -Name {0} -Scope Script -ErrorAction Ignore)) {{' -f $catalogName))
    $lines.Add(('    $script:{0} = @{{' -f $catalogName))

    if ($Subcommand.Count -eq 0)
    {
        $lines.Add('        Subcommands = @()')
    }
    else
    {
        $lines.Add('        Subcommands = @(')

        foreach ($row in $Subcommand)
        {
            $lines.Add(("            @{{ Name = '{0}'; Description = '{1}' }}" -f (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Name)), (ConvertTo-CompleterSingleQuotedText -Value ([string] $row.Description))))
        }

        $lines.Add('        )')
    }

    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('function {0} {{' -f $functionName))
    $lines.Add('    param(')
    $lines.Add('        [string]$wordToComplete,')
    $lines.Add('        [System.Management.Automation.Language.CommandAst]$commandAst,')
    $lines.Add('        [int]$cursorPosition')
    $lines.Add('    )')
    $lines.Add('')
    $lines.Add('    # Offer subcommands in the first argument position only; extend this function for options and values.')
    $lines.Add('    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })')
    $lines.Add('    if ($precedingElements.Count -gt 1) {')
    $lines.Add('        return')
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add(('    foreach ($subcommand in $script:{0}.Subcommands) {{' -f $catalogName))
    $lines.Add('        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {')
    $lines.Add("            [System.Management.Automation.CompletionResult]::new(`$subcommand.Name, `$subcommand.Name, 'ParameterValue', `$subcommand.Description)")
    $lines.Add('        }')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(('Register-ArgumentCompleter -Native -CommandName {0} -ScriptBlock {{' -f (@($Target | ForEach-Object { "'{0}'" -f (ConvertTo-CompleterSingleQuotedText -Value $_) }) -join ', ')))
    $lines.Add('    param($wordToComplete, $commandAst, $cursorPosition)')
    $lines.Add('')
    $lines.Add(('    {0} -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition' -f $functionName))
    $lines.Add('}')

    $lines.ToArray()
}
