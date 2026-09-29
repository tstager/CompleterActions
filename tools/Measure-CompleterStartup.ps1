<#
.SYNOPSIS
Measures session startup cost for a completer repository, eager versus lazy.

.DESCRIPTION
Times the ways a profile can load a completer repository, each in a fresh
child pwsh -NoProfile process so every sample starts cold:

- Eager: Get-ChildItem -Recurse -Filter *_completer.ps1 | Import-CompleterScript |
  Register-Completer -Force
- Lazy: Import-CompleterSet of a set file exported once from the eager result
  by the module under test, so every entry carries a Hash and no script has
  changed since
- LazyNoHash: Import-CompleterSet of a copy of that set with every Hash line
  removed, written next to it so relative paths resolve the same way
- Baseline: only with -BaselineModulePath, Import-CompleterSet of the same
  no-Hash copy under the baseline package, which is what a 2.0.0 profile pays

The samples are interleaved per iteration in the order Eager, Baseline, Lazy,
LazyNoHash, so drift in machine load reaches every leg alike. Each sample times
Import-Module plus the registration work with a Stopwatch inside the child,
which is the cost a profile pays. The script prints one row per leg with the
median, minimum, and maximum milliseconds, the ratio of each leg's median to
the eager median, and the ratio to the baseline median, which is empty when no
baseline was measured.

Before the first sample the script counts the entries (Path lines) and the
Hash lines of the exported set and of its no-Hash copy, and prints both counts
in the output header and through Write-Verbose. It throws, and takes no
sample, unless the exported set has exactly one Hash line per entry and the
copy has none. A -ModulePath that points at a 2.0.0 package writes no Hash,
so it stops there instead of printing a meaningless ratio.

.PARAMETER CompleterRoot
The folder searched recursively for *_completer.ps1 scripts.

.PARAMETER Iterations
How many child processes to run per leg. The median of the samples is reported.

.PARAMETER ModulePath
The CompleterActions module to measure. Defaults to the tracked package under
build/CompleterActions next to this script's tools folder. It must write a
Hash for every entry it exports, so a 2.0.0 package is rejected.

.PARAMETER BaselineModulePath
The CompleterActions package to compare against, normally 2.0.0. When it is
given, a Baseline leg imports the no-Hash copy of the set with this package
and every row gets a RatioToBaseline. Extract the package from the tag without
a worktree, with git archive v2.0.0 build | tar -x -C <folder>, and pass
<folder>/build/CompleterActions.

.EXAMPLE
PS> .\tools\Measure-CompleterStartup.ps1

Measures the default completer repository with ten samples per leg and no
Baseline leg, so RatioToBaseline is empty on every row.

.EXAMPLE
PS> $baseline = New-Item -ItemType Directory -Path (Join-Path -Path $env:TEMP -ChildPath 'CompleterActions-2.0.0')
PS> git archive v2.0.0 build | tar -x -C $baseline.FullName
PS> .\tools\Measure-CompleterStartup.ps1 -BaselineModulePath (Join-Path -Path $baseline.FullName -ChildPath 'build/CompleterActions')

Extracts the 2.0.0 package from its tag and measures all four legs against it.

.EXAMPLE
PS> .\tools\Measure-CompleterStartup.ps1 -CompleterRoot ~\Completers -Iterations 1 -Verbose

A quick dry run over another repository with one sample per leg.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $CompleterRoot = 'C:\Users\Trent\OneDrive\Documents\PowerShell\Completers',

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int] $Iterations = 10,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'build/CompleterActions'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $BaselineModulePath
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

function ConvertTo-TimedScript
{
    param(
        [Parameter(Mandatory)]
        [string] $Module,

        [Parameter(Mandatory)]
        [string] $Body
    )

    return @"
`$ErrorActionPreference = 'Stop'
`$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module -Name $(ConvertTo-SingleQuoted -Value $Module)
$Body
`$stopwatch.Stop()
`$stopwatch.Elapsed.TotalMilliseconds
"@
}

function Get-SetLineCount
{
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $lines = [System.IO.File]::ReadAllLines($LiteralPath)

    return [pscustomobject] @{
        Entries = @($lines -match '^\s*Path\s*=').Count
        Hashes  = @($lines -match '^\s*Hash\s*=').Count
    }
}

$resolvedCompleterRoot = (Resolve-Path -LiteralPath $CompleterRoot).ProviderPath
$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).ProviderPath
$resolvedBaselineModulePath = $null

if ($PSBoundParameters.ContainsKey('BaselineModulePath'))
{
    $resolvedBaselineModulePath = (Resolve-Path -LiteralPath $BaselineModulePath).ProviderPath
}

$scriptCount = @(Get-ChildItem -LiteralPath $resolvedCompleterRoot -Recurse -Filter '*_completer.ps1' -File).Count

if ($scriptCount -eq 0)
{
    throw "No *_completer.ps1 scripts were found under '$resolvedCompleterRoot'."
}

$quotedRoot = ConvertTo-SingleQuoted -Value $resolvedCompleterRoot
$quotedModule = ConvertTo-SingleQuoted -Value $resolvedModulePath
$setDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('CompleterActions-startup-{0}' -f ([guid]::NewGuid().ToString('N')))
$setPath = Join-Path -Path $setDirectory -ChildPath 'startup.psd1'
$noHashSetPath = Join-Path -Path $setDirectory -ChildPath 'startup-nohash.psd1'
$quotedSet = ConvertTo-SingleQuoted -Value $setPath
$quotedNoHashSet = ConvertTo-SingleQuoted -Value $noHashSetPath

$exportScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module -Name $quotedModule
`$imported = @(Get-ChildItem -LiteralPath $quotedRoot -Recurse -Filter '*_completer.ps1' -File | Import-CompleterScript)
`$imported | Register-Completer -Force
`$imported | Export-CompleterSet -Path $quotedSet
`$imported.Count
"@

$legs = [System.Collections.Generic.List[object]]::new()
$legs.Add(@{ Name = 'Eager'; Script = (ConvertTo-TimedScript -Module $resolvedModulePath -Body "Get-ChildItem -LiteralPath $quotedRoot -Recurse -Filter '*_completer.ps1' -File | Import-CompleterScript | Register-Completer -Force") })

if ($null -ne $resolvedBaselineModulePath)
{
    $legs.Add(@{ Name = 'Baseline'; Script = (ConvertTo-TimedScript -Module $resolvedBaselineModulePath -Body "Import-CompleterSet -LiteralPath $quotedNoHashSet -Force | Out-Null") })
}

$legs.Add(@{ Name = 'Lazy'; Script = (ConvertTo-TimedScript -Module $resolvedModulePath -Body "Import-CompleterSet -LiteralPath $quotedSet -Force | Out-Null") })
$legs.Add(@{ Name = 'LazyNoHash'; Script = (ConvertTo-TimedScript -Module $resolvedModulePath -Body "Import-CompleterSet -LiteralPath $quotedNoHashSet -Force | Out-Null") })

try
{
    $null = New-Item -ItemType Directory -Path $setDirectory
    Write-Verbose -Message "Measuring $scriptCount completer scripts under '$resolvedCompleterRoot' with module '$resolvedModulePath', $Iterations samples per leg."

    $targetCount = [int] (Invoke-ChildMeasurement -Script $exportScript)
    Write-Verbose -Message "Exported $targetCount targets to '$setPath'."

    $setLines = [System.IO.File]::ReadAllLines($setPath)
    [System.IO.File]::WriteAllLines($noHashSetPath, [string[]] @($setLines -notmatch '^\s*Hash\s*='))

    $hashedCount = Get-SetLineCount -LiteralPath $setPath
    $noHashCount = Get-SetLineCount -LiteralPath $noHashSetPath
    $countLine = "Set: $($hashedCount.Entries) entries, $($hashedCount.Hashes) Hash lines. No-Hash copy: $($noHashCount.Entries) entries, $($noHashCount.Hashes) Hash lines."
    Write-Verbose -Message $countLine

    Write-Host -Object "Module: $resolvedModulePath"
    Write-Host -Object "Baseline: $(if ($null -ne $resolvedBaselineModulePath) { $resolvedBaselineModulePath } else { 'none' })"
    Write-Host -Object "Scripts: $scriptCount, targets: $targetCount, samples per leg: $Iterations"
    Write-Host -Object $countLine

    if ($hashedCount.Entries -eq 0 -or $hashedCount.Hashes -ne $hashedCount.Entries -or $noHashCount.Entries -ne $hashedCount.Entries -or $noHashCount.Hashes -ne 0)
    {
        throw "The exported set must carry exactly one Hash line per entry and its no-Hash copy none, so no sample was taken. $countLine A -ModulePath that points at a 2.0.0 package writes no Hash."
    }

    foreach ($leg in $legs)
    {
        $leg.Samples = [System.Collections.Generic.List[double]]::new()
    }

    for ($sample = 1; $sample -le $Iterations; $sample++)
    {
        foreach ($leg in $legs)
        {
            Write-Verbose -Message "$($leg.Name) sample $sample of $Iterations"
            $leg.Samples.Add((Invoke-ChildMeasurement -Script $leg.Script))
        }
    }

    foreach ($leg in $legs)
    {
        $leg.Median = Get-Median -Value $leg.Samples.ToArray()
    }

    $eagerMedian = $legs[0].Median
    $baselineMedian = @($legs | Where-Object -FilterScript { $_.Name -eq 'Baseline' } | ForEach-Object -Process { $_.Median })

    foreach ($leg in $legs)
    {
        [pscustomobject] [ordered] @{
            Leg             = $leg.Name
            Scripts         = $scriptCount
            Targets         = $targetCount
            Samples         = $Iterations
            MedianMs        = [Math]::Round($leg.Median, 1)
            MinMs           = [Math]::Round(($leg.Samples | Measure-Object -Minimum).Minimum, 1)
            MaxMs           = [Math]::Round(($leg.Samples | Measure-Object -Maximum).Maximum, 1)
            RatioToEager    = [Math]::Round($leg.Median / $eagerMedian, 2)
            RatioToBaseline = if ($baselineMedian.Count -eq 1) { [Math]::Round($leg.Median / $baselineMedian[0], 2) } else { $null }
        }
    }
}
finally
{
    Remove-Item -LiteralPath $setDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
