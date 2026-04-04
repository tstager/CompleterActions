<#
.SYNOPSIS
Imports self-contained completer scripts into registration input objects.

.DESCRIPTION
Parses and validates one or more completer scripts, executes them inside a
temporary module that shadows Register-ArgumentCompleter, and emits objects that
can be piped directly to Register-CompleterRegistration -InputObject.

Import-CompleterScript is safe by default for supported script shapes: it rejects
unsupported Register-ArgumentCompleter patterns during AST validation and avoids
mutating the live runtime completer tables during import. Imported ScriptBlock
objects keep the temporary module context that contains helper functions and
script-scope state defined by the source script.

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
        $resolvedPaths = @()

        try
        {
            switch ($PSCmdlet.ParameterSetName)
            {
                'Path'
                {
                    foreach ($pathItem in $Path)
                    {
                        $resolvedPaths += @(Resolve-Path -Path $pathItem -ErrorAction Stop | Select-Object -ExpandProperty ProviderPath)
                    }

                    break
                }

                'LiteralPath'
                {
                    foreach ($literalPathItem in $LiteralPath)
                    {
                        $resolvedPaths += (Get-Item -LiteralPath $literalPathItem -ErrorAction Stop).FullName
                    }

                    break
                }
            }

            foreach ($resolvedPath in $resolvedPaths)
            {
                $file = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
                if ($file.PSIsContainer)
                {
                    throw "Completer script imports require a file path. '$resolvedPath' is a directory."
                }

                if ($file.Extension -ne '.ps1')
                {
                    throw "Completer script imports require .ps1 files. Received '$resolvedPath'."
                }

                $parseResult = Get-CompleterScriptParseResult -LiteralPath $file.FullName
                $null = Test-CompleterScriptAst -Ast $parseResult.Ast -LiteralPath $file.FullName
                $importSession = Import-CompleterScriptDefinition -LiteralPath $file.FullName

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
                            (New-ImportedCompleterRegistration -Target $target -ScriptBlock $definition.ScriptBlock -SourcePath $file.FullName -ImportModule $importSession.Module)
                        )
                    }
                }
            }
        }
        catch
        {
            throw "Failed to import completer script. $($_.Exception.Message)"
        }
        finally
        {
            $resolvedPaths = @()
        }
    }
}
