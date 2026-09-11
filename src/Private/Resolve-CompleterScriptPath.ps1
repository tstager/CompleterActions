<#
.SYNOPSIS
Resolves completer script path input into full .ps1 file paths.

.DESCRIPTION
Shared by Import-CompleterScript and Test-CompleterScript so both commands
accept the same -Path and -LiteralPath input and reject the same non-script
input. Wildcards in -Path are expanded; -LiteralPath is used as written.
Directories and files without a .ps1 extension are rejected.

.PARAMETER Path
One or more paths to completer script files. Wildcards are supported.

.PARAMETER LiteralPath
One or more literal paths to completer script files. Wildcards are not expanded.

.OUTPUTS
System.String
#>
function Resolve-CompleterScriptPath
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    $resolvedPaths = @()

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
            throw "Completer scripts must be file paths. '$resolvedPath' is a directory."
        }

        if ($file.Extension -ne '.ps1')
        {
            throw "Completer scripts must be .ps1 files. Received '$resolvedPath'."
        }

        $file.FullName
    }
}
