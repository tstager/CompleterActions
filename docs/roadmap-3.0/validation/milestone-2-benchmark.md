# Milestone 2 import-time benchmark (WP8, spec section 5, check 21)

Run on 2026-10-03 at branch commit `bb0336c` (`feat/milestone-2-authoring-distribution`), pwsh 7.6.6 on Microsoft Windows 11 Pro 10.0.26300, PS_Completers at `2c590c6` (`master`, 173 scripts), read through a scratch clone. The baseline is the 2.1.0 build extracted from tag `v2.1.0`. `build/` was rebuilt with `Invoke-Build -Task build` before the runs and `git status` was clean.

Every `<scratch>` below is `C:\Users\Trent\AppData\Local\Temp\claude\...\scratchpad\wp8`, outside the repository. Each step ran in its own `pwsh -NoProfile`.

## Setup

```powershell
git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers
New-Item -ItemType Directory -Path <scratch>\v2.1.0 -Force | Out-Null
git archive v2.1.0 build | tar -x -C <scratch>\v2.1.0
```

The clone needed `-c core.longpaths=true`: without it `git clone` failed with `fatal: failed to unlink '<scratch>\PS_Completers/.git/objects/pack/pack-1894309c6bd1a16cbf61a8fcb68afccdc2680e7d.idx': Filename too long`, because the scratch folder is deep (the longest file path in the clone is 267 characters). The extracted manifest reports `ModuleVersion` 2.1.0.

## Gate run

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v2.1.0\build\CompleterActions -Iterations 10
```

`-ModulePath` was the default, the branch's `build/CompleterActions`. One run was taken; its `LazyNoHash` `RatioToBaseline` is at or under 1.05, so the run rule needs no further runs.

```text
Module: C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions
Baseline: C:\Users\Trent\AppData\Local\Temp\claude\C--Users-Trent-OneDrive-Documents-My-Scripts-Code-PowerShell-Modules-CompleterActions\7e8a3279-c213-4f2b-a3c6-8ea3a6a5db76\scratchpad\wp8\v2.1.0\build\CompleterActions
Scripts: 173, targets: 366, samples per leg: 10
Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.

Leg        Scripts Targets Samples MedianMs   MinMs   MaxMs RatioToEager RatioToBaseline
---        ------- ------- ------- --------   -----   ----- ------------ ---------------
Eager          173     366      10  7854.00 7269.40 8431.00         1.00            6.25
Baseline       173     366      10  1255.90 1223.90 1470.60         0.16            1.00
Lazy           173     366      10   761.00  732.50  800.80         0.10            0.61
LazyNoHash     173     366      10  1281.10 1252.30 1356.80         0.16            1.02
```

`LazyNoHash` against `Baseline`: 1281.1 / 1255.9 ms = 1.020 (the tool prints 1.02).

## Information run (2.1.0 as the module under test)

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -ModulePath <scratch>\v2.1.0\build\CompleterActions -Iterations 10
```

```text
Module: C:\Users\Trent\AppData\Local\Temp\claude\C--Users-Trent-OneDrive-Documents-My-Scripts-Code-PowerShell-Modules-CompleterActions\7e8a3279-c213-4f2b-a3c6-8ea3a6a5db76\scratchpad\wp8\v2.1.0\build\CompleterActions
Baseline: none
Scripts: 173, targets: 366, samples per leg: 10
Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.

Leg        Scripts Targets Samples MedianMs   MinMs   MaxMs RatioToEager RatioToBaseline
---        ------- ------- ------- --------   -----   ----- ------------ ---------------
Eager          173     366      10  8051.70 7364.10 8519.50         1.00
Lazy           173     366      10   760.50  730.10  797.00         0.09
LazyNoHash     173     366      10  1281.10 1221.00 1342.20         0.16
```

| `Lazy` median | Build | Run |
| --- | --- | --- |
| 761.0 ms | branch build (`bb0336c`) | gate run |
| 760.5 ms | 2.1.0 (`v2.1.0`) | information run |

Reported, not gated: the two runs are not interleaved.

## Spot cost

Staged package, built once in scratch:

```powershell
# <scratch>\modules\PS_Completers\1.0.0\completers\ holds the clone's ps_completers.psd1 and its 173 *_completer folders
New-ModuleManifest -Path <scratch>\modules\PS_Completers\1.0.0\PS_Completers.psd1 -ModuleVersion 1.0.0 -PrivateData @{ CompleterSet = 'completers/ps_completers.psd1' }
```

Each sample is a fresh `pwsh -NoProfile -NonInteractive` running the section 8 preamble, then:

```powershell
$env:PSModulePath = '<scratch>\modules;' + $env:PSModulePath
$ms = (Measure-Command { $n = @(Import-CompleterSet -Name PS_Completers).Count }).TotalMilliseconds
# or, for the other leg:
$ms = (Measure-Command { $n = @(Import-CompleterSet -LiteralPath <scratch>\modules\PS_Completers\1.0.0\completers\ps_completers.psd1).Count }).TotalMilliseconds
```

Every sample of every run returned 362 registrations. The harness was a scratch script and is not committed.

Four recorded runs were taken, in this order. Run A was taken first, with the two legs interleaved, `-Name` first in each pair; that order is not the plan's. Its difference was over 20 ms, so run B was taken in the plan's order (ten `-Name` processes, then ten `-LiteralPath` processes), then run C interleaved with `-LiteralPath` first, then run D, a 30-pair diagnostic that alternates which leg goes first. Before run A, two dry runs of one and three pairs checked the harness; the first `-Name` sample of the first dry run, the first sample after the package was copied, took 5042.2 ms, and every later sample was between 590 and 672 ms. The dry runs are not part of any median.

| Run | Order | Samples per leg | `-Name` median ms | `-LiteralPath` median ms | Difference ms |
| --- | --- | --- | --- | --- | --- |
| A | interleaved, `-Name` first | 10 | 636.1 | 604.0 | 32.0 |
| B | the plan's: ten `-Name`, then ten `-LiteralPath` | 10 | 628.5 | 613.7 | 14.8 |
| C | interleaved, `-LiteralPath` first | 10 | 633.7 | 606.5 | 27.1 |
| D | interleaved, alternating which leg is first | 30 | 631.5 | 633.4 | -1.8 |
| A to D pooled | | 60 | 631.5 | 617.1 | 14.4 |

The `-LiteralPath` leg spreads 100.2 to 119.4 ms between its fastest and slowest sample within each of runs A to D, five to six times the bound, so a ten-sample median difference moves by more than 20 ms from run to run. A diagnostic in fresh processes (scratch, not a recorded run) timed the private `Resolve-CompleterSetModule -Name PS_Completers` alone at 53.8 to 74.0 ms on its first call and 4.4 to 5.3 ms on its second; part of the first-call cost is first use of commands the `-LiteralPath` path also pays for, such as `Import-PowerShellDataFile`.

### Run A

| Sample | `-Name` ms | `-LiteralPath` ms |
| --- | --- | --- |
| 1 | 638.1 | 612.1 |
| 2 | 621.7 | 604.9 |
| 3 | 655.0 | 594.1 |
| 4 | 663.0 | 598.9 |
| 5 | 624.5 | 571.3 |
| 6 | 624.4 | 616.3 |
| 7 | 634.0 | 645.9 |
| 8 | 656.8 | 558.5 |
| 9 | 727.4 | 603.1 |
| 10 | 614.6 | 658.7 |
| Median | 636.1 | 604.0 |

### Run B

| Sample | `-Name` ms | `-LiteralPath` ms |
| --- | --- | --- |
| 1 | 645.5 | 596.2 |
| 2 | 638.5 | 670.7 |
| 3 | 607.4 | 558.3 |
| 4 | 629.7 | 649.2 |
| 5 | 633.1 | 588.8 |
| 6 | 618.9 | 592.1 |
| 7 | 623.8 | 665.0 |
| 8 | 618.2 | 631.3 |
| 9 | 627.2 | 642.2 |
| 10 | 666.4 | 556.9 |
| Median | 628.5 | 613.7 |

### Run C

| Sample | `-Name` ms | `-LiteralPath` ms |
| --- | --- | --- |
| 1 | 627.4 | 663.3 |
| 2 | 621.9 | 608.0 |
| 3 | 649.6 | 602.4 |
| 4 | 638.4 | 641.4 |
| 5 | 640.7 | 584.9 |
| 6 | 728.3 | 654.3 |
| 7 | 628.4 | 548.6 |
| 8 | 629.0 | 614.3 |
| 9 | 628.5 | 605.1 |
| 10 | 661.1 | 592.8 |
| Median | 633.7 | 606.5 |

### Run D

| Sample | `-Name` ms | `-LiteralPath` ms |
| --- | --- | --- |
| 1 | 722.0 | 608.0 |
| 2 | 659.7 | 591.3 |
| 3 | 628.5 | 677.6 |
| 4 | 661.2 | 644.1 |
| 5 | 596.1 | 658.0 |
| 6 | 628.4 | 676.5 |
| 7 | 685.0 | 675.4 |
| 8 | 627.3 | 604.4 |
| 9 | 687.6 | 614.6 |
| 10 | 638.2 | 623.5 |
| 11 | 623.1 | 688.3 |
| 12 | 630.0 | 646.9 |
| 13 | 628.6 | 624.8 |
| 14 | 636.5 | 664.0 |
| 15 | 622.8 | 634.9 |
| 16 | 633.1 | 603.3 |
| 17 | 686.5 | 644.2 |
| 18 | 622.0 | 631.8 |
| 19 | 672.6 | 635.2 |
| 20 | 635.2 | 606.5 |
| 21 | 624.2 | 568.9 |
| 22 | 705.3 | 609.8 |
| 23 | 667.9 | 642.5 |
| 24 | 628.7 | 615.5 |
| 25 | 618.0 | 604.2 |
| 26 | 679.5 | 660.8 |
| 27 | 649.4 | 635.8 |
| 28 | 626.4 | 617.9 |
| 29 | 624.0 | 623.1 |
| 30 | 616.8 | 657.3 |
| Median | 631.5 | 633.4 |

## Criteria

| Criterion | Expected | Measured | Result |
| --- | --- | --- | --- |
| `LazyNoHash` `RatioToBaseline`, by the section 5 run rule | at most 1.05 | 1.02 on run 1 of 1 (1281.1 / 1255.9 ms) | Pass |
| Spot cost, `-Name` median minus `-LiteralPath` median | at most 20 ms | 14.8 ms in run B, the plan's order; 32.0 ms (run A) and 27.1 ms (run C) in interleaved orders; -1.8 ms over 30 alternating pairs (run D); 14.4 ms pooled | Pass in the plan's order; runs A and C were over, so the owner rules on it |
| `Lazy` median, branch build (`bb0336c`) | reported, not gated | 761.0 ms | Reported |
| `Lazy` median, 2.1.0 build (`v2.1.0`) | reported, not gated | 760.5 ms | Reported |
