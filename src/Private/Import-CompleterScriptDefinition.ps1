<#
.SYNOPSIS
Executes a completer script in a controlled capture module.

.DESCRIPTION
Creates a temporary dynamic module that shadows Register-ArgumentCompleter so the
target script can run without mutating the live runtime completer tables. Each
captured script block is the script's own block rebound to the capture module,
so helper functions and script state remain available later and the block
keeps its source file: $PSScriptRoot and $PSCommandPath inside the completer
name the script's directory and path, as they do when the script is
dot-sourced. Nothing the script defines is imported out of the capture module:
New-Module would otherwise import its functions and exported aliases into this
module, where a helper could replace a private command or the
Register-ArgumentCompleter cmdlet.

.PARAMETER LiteralPath
The literal path to the completer script file.

.PARAMETER Script
The script's command information. It is dot-sourced as it is, so the contents it
has already read are what runs, under the same execution policy and #requires
checks as dot-sourcing LiteralPath; the file is not read again.

.OUTPUTS
CompleterActions.CompleterScriptImportSession
#>
function Import-CompleterScriptDefinition
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.ExternalScriptInfo] $Script
    )

    $importModule = $null
    $capturedDefinitions = @()

    try
    {
        $importModule = New-Module -Name ('CompleterActions.ScriptImport.{0}' -f ([guid]::NewGuid().ToString('N'))) -Function @() -ArgumentList $Script -ScriptBlock {
            param(
                [Parameter(Mandatory)]
                [System.Management.Automation.ExternalScriptInfo] $ScriptInfo
            )

            $script:CapturedCompleterDefinitions = [System.Collections.Generic.List[object]]::new()

            function Register-ArgumentCompleter
            {
                [CmdletBinding(DefaultParameterSetName = 'CommandParameter')]
                param(
                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $CommandName,

                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNullOrEmpty()]
                    [string[]] $ParameterName,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [switch] $Native,

                    [Parameter(Mandatory, ParameterSetName = 'Native')]
                    [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
                    [ValidateNotNull()]
                    [scriptblock] $ScriptBlock
                )

                process
                {
                    # Rebinding the original block to this module keeps its source file, so
                    # $PSScriptRoot and $PSCommandPath inside the completer still name the
                    # script; rebuilding it from text would drop that association.
                    $capturedScriptBlock = $ExecutionContext.SessionState.Module.NewBoundScriptBlock($ScriptBlock)

                    $script:CapturedCompleterDefinitions.Add(
                        [pscustomobject] [ordered] @{
                            CommandName   = @($CommandName)
                            ParameterName = if ($Native) { @() } else { @($ParameterName) }
                            IsNative      = [bool] $Native
                            ScriptBlock   = $capturedScriptBlock
                        }
                    )
                }
            }

            $null = @(. $ScriptInfo)
        }

        $capturedDefinitions = @(& $importModule {
                @($script:CapturedCompleterDefinitions)
            })

        if ($capturedDefinitions.Count -eq 0)
        {
            throw 'The script executed successfully but did not register any completers at script scope.'
        }

        [pscustomobject] [ordered] @{
            PSTypeName  = 'CompleterActions.CompleterScriptImportSession'
            Path        = $LiteralPath
            Module      = $importModule
            Definitions = $capturedDefinitions
        }
    }
    catch
    {
        throw "Failed to execute completer script '$LiteralPath' in the import scope. $($_.Exception.Message)"
    }
}
