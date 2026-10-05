# Milestone 3 benchmark and grammar timing (WP7, spec section 9, checks 9 and 16)

Run on 2026-10-04 at branch commit `802fef6` (`feat/milestone-3-compiled-core`), pwsh 7.6.6 (.NET 10.0.12) on Microsoft Windows 11 Pro 10.0.26300, dotnet SDK 10.0.401, PS_Completers at `e4f7d6e` (`master`, 173 scripts, 366 targets), read through a scratch clone. The baseline is the 2.2.0 build extracted from tag `v2.2.0` (`d5767e9`). Before the runs, the three run steps passed in separate processes: `Invoke-Build -Task build` (0 errors, 0 warnings, `git status` clean afterwards, so the committed `build/` was fresh), the two `Invoke-ScriptAnalyzer` calls (no output), and `Invoke-Pester -Path ./tests -CI` (639 passed, 0 failed, 8 skipped). No `pwsh` held the repository build imported.

Every `<scratch>` below is `C:\Users\Trent\AppData\Local\Temp\m3\wp7-scratch`, outside the repository. Each step ran in its own `pwsh -NoProfile`. The harness scripts were scratch files and are not committed.

## Setup

```powershell
git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers
New-Item -ItemType Directory -Path <scratch>\v2.2.0 -Force | Out-Null
git archive v2.2.0 build | tar -x -C <scratch>\v2.2.0
```

The extracted manifest reports `ModuleVersion` 2.2.0 with no `Prerelease`. The clone holds 173 `*_completer.ps1` files. `tar` is `C:\WINDOWS\system32\tar.exe`.

## Gate run

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v2.2.0\build\CompleterActions -Iterations 10
```

`-ModulePath` was the default, the branch's `build/CompleterActions`. One run was taken; its `LazyNoHash` `RatioToBaseline` is at or under 1.05, so the run rule needs no further runs. The tool was run through `pwsh -NoProfile -Command "& .\tools\Measure-CompleterStartup.ps1 ... | Out-String -Width 200"`, so its rows print in list form; the values are the tool's.

```text
Module: C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions
Baseline: C:\Users\Trent\AppData\Local\Temp\m3\wp7-scratch\v2.2.0\build\CompleterActions
Scripts: 173, targets: 366, samples per leg: 10
Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.

Leg             : Eager
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 3288.7
MinMs           : 3204.7
MaxMs           : 3494.5
RatioToEager    : 1
RatioToBaseline : 2.41

Leg             : Baseline
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 1362.4
MinMs           : 1331.7
MaxMs           : 1467.8
RatioToEager    : 0.41
RatioToBaseline : 1

Leg             : Lazy
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 788
MinMs           : 710.3
MaxMs           : 829.5
RatioToEager    : 0.24
RatioToBaseline : 0.58

Leg             : LazyNoHash
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 1349
MinMs           : 1302.8
MaxMs           : 1395.9
RatioToEager    : 0.41
RatioToBaseline : 0.99
```

`LazyNoHash` against `Baseline`: 1349.0 / 1362.4 ms = 0.990 (the tool prints 0.99).

## Information run (2.2.0 as the module under test)

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -ModulePath <scratch>\v2.2.0\build\CompleterActions -Iterations 10
```

```text
Module: C:\Users\Trent\AppData\Local\Temp\m3\wp7-scratch\v2.2.0\build\CompleterActions
Baseline: none
Scripts: 173, targets: 366, samples per leg: 10
Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.

Leg             : Eager
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 8046.7
MinMs           : 7504
MaxMs           : 8296.3
RatioToEager    : 1
RatioToBaseline :

Leg             : Lazy
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 811.2
MinMs           : 791.3
MaxMs           : 822.8
RatioToEager    : 0.1
RatioToBaseline :

Leg             : LazyNoHash
Scripts         : 173
Targets         : 366
Samples         : 10
MedianMs        : 1347.9
MinMs           : 1314.3
MaxMs           : 1374.4
RatioToEager    : 0.17
RatioToBaseline :
```

| `Lazy` median | Build | Run |
| --- | --- | --- |
| 788.0 ms | branch build (`802fef6`) | gate run |
| 811.2 ms | 2.2.0 (`v2.2.0`) | information run |

Ratio 788.0 / 811.2 = 0.971. Reported against the 1.05 bound, not gated: the two runs are not interleaved.

## Grammar loop

Each sample is a fresh `pwsh -NoProfile -NonInteractive -File <scratch>\grammar-loop.ps1 -ModulePath <build> -CompleterRoot <scratch>\PS_Completers`, which imports the module by path, asserts `ModuleBase`, sorts the clone's `*_completer.ps1` files by full name, warms up with one call, and times the loop:

```powershell
Import-Module -Name (Join-Path $ModulePath 'CompleterActions.psd1') -Force
$files = @(Get-ChildItem -LiteralPath $CompleterRoot -Recurse -Filter *_completer.ps1 | Sort-Object FullName)
$null = Test-CompleterScript -LiteralPath $files[0].FullName
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($f in $files) { $null = Test-CompleterScript -LiteralPath $f.FullName }
$sw.Stop()
```

After the timed loop the harness counted the findings in a second, untimed pass: 0 for every script under both builds. Three runs per build, alternating, the branch build first in each pair:

| Run | Branch build ms | Branch ms per script | 2.2.0 ms | 2.2.0 ms per script |
| --- | --- | --- | --- | --- |
| 1 | 461.2 | 2.666 | 4719.8 | 27.282 |
| 2 | 478.9 | 2.768 | 4271.2 | 24.689 |
| 3 | 461.8 | 2.669 | 4648.7 | 26.871 |
| Median | 461.8 | 2.669 | 4648.7 | 26.871 |

Median branch time against median 2.2.0 time: 461.8 / 4648.7 ms = 0.099.

## Compiled walk

Each run is a fresh `pwsh -NoProfile -NonInteractive -File <scratch>\compiled-walk.ps1 -ModulePath <branch build> -CompleterRoot <scratch>\PS_Completers`, which imports the branch build, asserts `ModuleBase`, parses the 173 sorted scripts once with `[System.Management.Automation.Language.Parser]::ParseFile` (no parse errors), warms up with one `Test` call per script, then times each script on its own stopwatch:

```powershell
foreach ($ast in $asts) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = [CompleterActions.Internal.StrictGrammar]::Test($ast)
    $sw.Stop()
    $samples.Add($sw.Elapsed.TotalMilliseconds)
}
```

| Run | Scripts | Median ms per script | Min ms | Max ms | Total ms | Mean ms | Findings |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 173 | 0.1177 | 0.0358 | 0.8831 | 28.9 | 0.1671 | 0 |
| 2 | 173 | 0.0940 | 0.0287 | 0.7804 | 22.3 | 0.1291 | 0 |
| 3 | 173 | 0.0970 | 0.0296 | 0.8024 | 22.8 | 0.1319 | 0 |

Every run's median is under 1 ms; the median of the three is 0.097 ms, and no single script took 1 ms in any run.

## Spot cost

Each sample is a fresh `pwsh -NoProfile -NonInteractive -File <scratch>\spot.ps1 <build>`:

```powershell
param($m)
$ms = (Measure-Command { Import-Module -Name (Join-Path $m "CompleterActions.psd1") -Force }).TotalMilliseconds
if ((Get-Module CompleterActions).ModuleBase -ne $m) { throw "wrong ModuleBase" }
[Math]::Round($ms, 1)
```

Ten branch-build processes were taken first, then ten 2.2.0 processes.

| Sample | Branch build ms | 2.2.0 ms |
| --- | --- | --- |
| 1 | 134.9 | 171.5 |
| 2 | 135.3 | 140.6 |
| 3 | 128.8 | 139.6 |
| 4 | 125.0 | 134.1 |
| 5 | 138.7 | 144.2 |
| 6 | 135.3 | 138.7 |
| 7 | 144.4 | 137.1 |
| 8 | 129.4 | 138.4 |
| 9 | 150.0 | 141.9 |
| 10 | 135.8 | 144.8 |
| Median | 135.3 | 140.1 |

## Criteria

| Criterion | Expected | Measured | Result |
| --- | --- | --- | --- |
| `LazyNoHash` `RatioToBaseline`, by the section 9 run rule | at most 1.05 | 0.99 on run 1 of 1 (1349.0 / 1362.4 ms) | Pass |
| `Test-CompleterScript` loop over 173 scripts, branch median against 2.2.0 median | at most 0.30 | 0.099 (461.8 / 4648.7 ms, three runs each) | Pass |
| Compiled walk, median per script | under 1 ms | 0.1177, 0.0940, 0.0970 ms over three runs | Pass |
| `Lazy` median, branch build against 2.2.0 | bound 1.05, reported | 0.971 (788.0 / 811.2 ms) | Reported, within the bound |
| Spot cost, `Import-Module` median over ten fresh processes | reported, not gated | 135.3 ms branch build, 140.1 ms 2.2.0 | Reported |
