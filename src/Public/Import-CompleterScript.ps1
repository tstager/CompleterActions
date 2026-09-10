<#
.SYNOPSIS
Imports self-contained completer scripts into registration input objects.

.DESCRIPTION
Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows Register-ArgumentCompleter, and emits objects that
can be piped directly to Register-CompleterRegistration -InputObject.

Import-CompleterScript is safe by default for supported script shapes: it
validates the script against a closed grammar before executing it, rejects
every unsupported construct with the same findings Test-CompleterScript
reports, and avoids mutating the live runtime completer tables during import.
Imported ScriptBlock objects keep the temporary module context that contains
helper functions and script-scope state defined by the source script.

Compatible completer scripts must be self-contained and must keep script scope
limited to Set-StrictMode, function definitions, importer-safe if statements,
and script-scope Register-ArgumentCompleter calls. Register-ArgumentCompleter
usage must use explicit parameter names and only the supported import-time
surface: -CommandName, -ParameterName, the bare -Native switch, and
-ScriptBlock.

Target metadata must stay literal. -CommandName and -ParameterName may be a
single literal string, a literal string array, or a literal @('...') array
expression. -ScriptBlock must be a literal script block. Positional arguments,
argument splatting, custom Register-ArgumentCompleter wrappers, dot-sourcing,
top-level assignments, loops, try/catch blocks, alias bootstrap, cache
initialization, and external command execution are not import-compatible and
should be moved into lazy helper paths reached from the registered script block.
'#requires -Modules', '#requires -Assembly', 'using module', and 'using
assembly' are rejected because they load code when the script is dot-sourced.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns CompleterActions.ImportedCompleterRegistration records compatible with
Register-CompleterRegistration -InputObject.

.EXAMPLE
PS> Import-CompleterScript -Path .\7z_completer.ps1 | Register-CompleterRegistration -PassThru

Imports a supported completer script and immediately registers the imported
completer definitions through the module's managed registration API.

.NOTES
Use this compatibility specification when authoring future standalone completer
scripts for import:

- Keep the script self-contained; do not dot-source other scripts.
- Register completers at script scope with literal Register-ArgumentCompleter
  calls.
- Use only -CommandName, -ParameterName, bare -Native, and -ScriptBlock.
- Keep -CommandName and -ParameterName literal; use literal @('name','name.exe')
  when multiple command names are required.
- Move alias bootstrap, cache initialization, generated completion loading, and
  tool discovery into lazy helper logic invoked during completion rather than at
  import time.
#>
function Import-CompleterScript
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                $findings = @(Get-CompleterScriptFinding -LiteralPath $resolvedPath | Where-Object -Property Severity -EQ -Value 'Error')

                if ($findings.Count -gt 0)
                {
                    $findingLines = foreach ($finding in $findings)
                    {
                        'Line {0}, column {1} ({2}): {3} {4}' -f $finding.Line, $finding.Column, $finding.Construct, $finding.Message, $finding.Hint
                    }

                    throw "Completer script '$resolvedPath' does not conform to the strict import grammar. Run Test-CompleterScript to work through the findings.$([Environment]::NewLine)$($findingLines -join [Environment]::NewLine)"
                }

                $importSession = Import-CompleterScriptDefinition -LiteralPath $resolvedPath

                foreach ($definition in $importSession.Definitions)
                {
                    $targetParameters = @{
                        CommandName = $definition.CommandName
                    }

                    if ($definition.IsNative)
                    {
                        $targetParameters['Native'] = $true
                    }
                    else
                    {
                        $targetParameters['ParameterName'] = $definition.ParameterName
                    }

                    foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                    {
                        $PSCmdlet.WriteObject(
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $resolvedPath -ImportModule $importSession.Module)
                        )
                    }
                }
            }
        }
        catch
        {
            throw "Failed to import completer script. $($_.Exception.Message)"
        }
    }
}
