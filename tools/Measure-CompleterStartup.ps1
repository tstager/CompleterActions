<#
.SYNOPSIS
Measures session startup cost for a completer repository, eager versus lazy.

.DESCRIPTION
Times the two ways a profile can load a completer repository, each in a fresh
child pwsh -NoProfile process so every sample starts cold:

- Eager: Get-ChildItem -Recurse -Filter *_completer.ps1 | Import-CompleterScript |
  Register-CompleterRegistration -Force
- Lazy: Import-CompleterSet of a set file exported once from the eager result

Each sample times Import-Module plus the registration work with a Stopwatch
inside the child, which is the cost a profile pays. The script prints one row
per leg with the median, minimum, and maximum milliseconds and the ratio of
each leg's median to the eager median.

.PARAMETER CompleterRoot
The folder searched recursively for *_completer.ps1 scripts.

.PARAMETER Iterations
How many child processes to run per leg. The median of the samples is reported.

.PARAMETER ModulePath
The CompleterActions module to measure. Defaults to the tracked package under
build/CompleterActions next to this script's tools folder.

.EXAMPLE
PS> .\tools\Measure-CompleterStartup.ps1

Measures the default completer repository with five samples per leg.

.EXAMPLE
PS> .\tools\Measure-CompleterStartup.ps1 -CompleterRoot ~\Completers -Iterations 10
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $CompleterRoot = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers',

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int] $Iterations = 5,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/CompleterActions')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Invoke-ChildMeasurement
{
    param(
        [Parameter(Mandatory)]
        [string] $Script
    )

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
    $output = @(& pwsh -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1)

    if ($LASTEXITCODE -ne 0)
    {
        throw "The child measurement process failed.$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }

    return [double] ($output | Select-Object -Last 1)
}

function Get-Median
{
    param(
        [Parameter(Mandatory)]
        [double[]] $Value
    )

    $sorted = @($Value | Sort-Object)
    $middle = [int] [Math]::Floor($sorted.Count / 2)

    if ($sorted.Count % 2 -eq 1)
    {
        return $sorted[$middle]
    }

    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

function ConvertTo-SingleQuoted
{
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

$resolvedCompleterRoot = (Resolve-Path -LiteralPath $CompleterRoot).ProviderPath
$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).ProviderPath
$scriptCount = @(Get-ChildItem -LiteralPath $resolvedCompleterRoot -Recurse -Filter '*_completer.ps1' -File).Count

if ($scriptCount -eq 0)
{
    throw "No *_completer.ps1 scripts were found under '$resolvedCompleterRoot'."
}

$quotedRoot = ConvertTo-SingleQuoted -Value $resolvedCompleterRoot
$quotedModule = ConvertTo-SingleQuoted -Value $resolvedModulePath
$setPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('CompleterActions-startup-{0}.psd1' -f ([guid]::NewGuid().ToString('N')))
$quotedSet = ConvertTo-SingleQuoted -Value $setPath

$timedPreamble = @"
`$ErrorActionPreference = 'Stop'
`$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module -Name $quotedModule
"@

$timedEpilogue = @"
`$stopwatch.Stop()
`$stopwatch.Elapsed.TotalMilliseconds
"@

$eagerScript = @"
$timedPreamble
Get-ChildItem -LiteralPath $quotedRoot -Recurse -Filter '*_completer.ps1' -File | Import-CompleterScript | Register-CompleterRegistration -Force
$timedEpilogue
"@

$exportScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module -Name $quotedModule
`$imported = @(Get-ChildItem -LiteralPath $quotedRoot -Recurse -Filter '*_completer.ps1' -File | Import-CompleterScript)
`$imported | Register-CompleterRegistration -Force
`$imported | Export-CompleterSet -Path $quotedSet
`$imported.Count
"@

$lazyScript = @"
$timedPreamble
Import-CompleterSet -LiteralPath $quotedSet -Force | Out-Null
$timedEpilogue
"@

try
{
    Write-Verbose -Message "Measuring $scriptCount completer scripts under '$resolvedCompleterRoot' with module '$resolvedModulePath', $Iterations samples per leg."

    $eagerSamples = @(
        for ($sample = 1; $sample -le $Iterations; $sample++)
        {
            Write-Verbose -Message "Eager sample $sample of $Iterations"
            Invoke-ChildMeasurement -Script $eagerScript
        }
    )

    $targetCount = [int] (Invoke-ChildMeasurement -Script $exportScript)
    Write-Verbose -Message "Exported $targetCount targets to '$setPath'."

    $lazySamples = @(
        for ($sample = 1; $sample -le $Iterations; $sample++)
        {
            Write-Verbose -Message "Lazy sample $sample of $Iterations"
            Invoke-ChildMeasurement -Script $lazyScript
        }
    )

    $eagerMedian = Get-Median -Value $eagerSamples
    $lazyMedian = Get-Median -Value $lazySamples

    foreach ($leg in @(
            @{ Name = 'Eager'; Samples = $eagerSamples; Median = $eagerMedian },
            @{ Name = 'Lazy'; Samples = $lazySamples; Median = $lazyMedian }
        ))
    {
        [pscustomobject] [ordered] @{
            Leg          = $leg.Name
            Scripts      = $scriptCount
            Targets      = $targetCount
            Samples      = $Iterations
            MedianMs     = [Math]::Round($leg.Median, 1)
            MinMs        = [Math]::Round(($leg.Samples | Measure-Object -Minimum).Minimum, 1)
            MaxMs        = [Math]::Round(($leg.Samples | Measure-Object -Maximum).Maximum, 1)
            RatioToEager = [Math]::Round($leg.Median / $eagerMedian, 2)
        }
    }
}
finally
{
    Remove-Item -LiteralPath $setPath -Force -ErrorAction SilentlyContinue
}
