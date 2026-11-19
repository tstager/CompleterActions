<#
.SYNOPSIS
Imports self-contained completer scripts into registration input objects.

.DESCRIPTION
Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows Register-ArgumentCompleter, and emits objects that
can be piped directly to Register-Completer -InputObject.

Import-CompleterScript has two tiers. The strict tier is the default: it
validates the script against a closed grammar before executing it, rejects
every unsupported construct with the same findings Test-CompleterScript
reports, and avoids mutating the live runtime completer tables during import.
The script is read once and the validated text is the text that runs, so a
save after the check cannot change what executes. The trusted tier, selected
with -Trusted, skips the grammar and dot-sources the script as-is inside the
same capture module, so use it only for scripts you wrote or reviewed.
Imported ScriptBlock objects keep the temporary module
context that contains helper functions and script-scope state defined by the
source script under either tier, and they keep the script as their source
file, so $PSScriptRoot and $PSCommandPath inside a completer name the script's
directory and path exactly as they do when the script is dot-sourced.

Compatible strict-tier completer scripts must be self-contained and must keep script scope
limited to Set-StrictMode, function definitions without the global: qualifier,
importer-safe if statements, and script-scope Register-ArgumentCompleter calls.
Register-ArgumentCompleter usage must use explicit parameter names and only the
supported import-time surface: -CommandName, -ParameterName, the bare -Native
switch, and -ScriptBlock.

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

.PARAMETER Trusted
Skips the strict grammar validation and dot-sources the script as-is inside the
capture module. Everything at script scope runs at import time, exactly as it
would when the script is dot-sourced from a profile. The emitted records carry
Trusted set to true.

.OUTPUTS
CompleterActions.ImportedCompleterRegistration
Returns CompleterActions.ImportedCompleterRegistration records compatible with
Register-Completer -InputObject. The Trusted property records which
tier produced the record.

.EXAMPLE
PS> Import-CompleterScript -Path .\7z_completer.ps1 | Register-Completer -PassThru

Imports a supported completer script and immediately registers the imported
completer definitions through the module's managed registration API.

.EXAMPLE
PS> Import-CompleterScript -Path .\git_completer.ps1 -Trusted | Register-Completer

Imports a completer script you own without validating it against the strict
grammar, then registers it.

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
    [OutputType('CompleterActions.ImportedCompleterRegistration')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter()]
        [switch] $Trusted
    )

    process
    {
        try
        {
            $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }

            foreach ($resolvedPath in @(Resolve-CompleterScriptPath @pathParameters))
            {
                # The script is read once. The grammar validates the contents this
                # command information holds and the capture module executes the same
                # object, so a save between the two cannot run unvalidated code.
                # GetCommand looks a path with wildcard characters up as a pattern and
                # has no literal mode. Passing each '[', '*' and '?' as a class that
                # matches only itself finds most paths exactly, but a backtick in the
                # path defeats that form while the plain path then finds the file. So
                # both forms are tried in turn, and only command information for the
                # resolved file itself is accepted, never a sibling a pattern matched.
                $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
                $scriptInfo = $null
                $otherPath = $null
                foreach ($lookupPath in @(($resolvedPath -replace '[\[*?]', '[$0]'), $resolvedPath))
                {
                    $candidate = try { $ExecutionContext.InvokeCommand.GetCommand($lookupPath, [System.Management.Automation.CommandTypes]::ExternalScript) } catch { $null }
                    if ($null -eq $candidate) { continue }
                    if ([string]::Equals($candidate.Path, $resolvedPath, $pathComparison))
                    {
                        $scriptInfo = $candidate
                        break
                    }

                    $otherPath = $candidate.Path
                }

                if ($null -eq $scriptInfo)
                {
                    if ($null -ne $otherPath)
                    {
                        throw "The completer script path '$resolvedPath' resolves to the different file '$otherPath', so it was not loaded. Remove the backticks or wildcard characters from the path."
                    }

                    throw "The completer script '$resolvedPath' could not be loaded as a script file. Check that it still exists."
                }

                if (-not $Trusted)
                {
                    $parseResult = Get-CompleterScriptParseResult -LiteralPath $resolvedPath -Script $scriptInfo
                    Assert-CompleterScriptConformance -LiteralPath $resolvedPath -ParseResult $parseResult
                }

                $importSession = Import-CompleterScriptDefinition -LiteralPath $resolvedPath -Script $scriptInfo

                foreach ($definition in $importSession.Definitions)
                {
                    # The module, not the emitted record, records where each script block it
                    # emits came from, keyed on that very object: Register-Completer looks a
                    # block up in this table, so neither a property a caller sets nor a new
                    # block the caller binds to the capture module can claim an import.
                    $script:CompleterImportedScriptBlocks.Add($definition.ScriptBlock, [pscustomobject] @{ Module = $importSession.Module; ScriptPath = $resolvedPath; Trusted = [bool] $Trusted })

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
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $resolvedPath -ImportModule $importSession.Module -Trusted:$Trusted)
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
