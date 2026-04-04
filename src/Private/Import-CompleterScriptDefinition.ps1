<#
.SYNOPSIS
Executes a completer script in a controlled capture module.

.DESCRIPTION
Creates a temporary dynamic module that shadows Register-ArgumentCompleter so the
target script can run without mutating the live runtime completer tables. The
captured registration definitions preserve the imported script block behavior and
module scope so helper functions and script state remain available later.

.PARAMETER LiteralPath
The literal path to the completer script file.

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
        [string] $LiteralPath
    )

    $importModule = $null
    $capturedDefinitions = @()

    try
    {
        $importModule = New-Module -Name ('CompleterActions.ScriptImport.{0}' -f ([guid]::NewGuid().ToString('N'))) -ArgumentList $LiteralPath -ScriptBlock {
            param(
                [Parameter(Mandatory)]
                [string] $ScriptPath
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
                    $capturedScriptBlock = $ExecutionContext.SessionState.InvokeCommand.NewScriptBlock($ScriptBlock.ToString())

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

            $null = @(. $ScriptPath)
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
