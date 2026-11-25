# Milestone 1 import benchmark (WP11, spec section 10, check 24)

Run on 2026-11-25 at branch commit `1a903db` (`feat/3.1.0-authoring-second-pass`), pwsh 7.7.0 (.NET 11.0.0) on Microsoft Windows 11 Pro 10.0.26300, dotnet SDK 10.0.404, PS_Completers at `9db457c` (`master`, 176 scripts, 372 targets), read through a scratch clone. The baseline is the 3.0.1 build compiled from tag `v3.0.1` (`820d224`). Before the runs, `Invoke-Build -Task build` passed in its own process on the branch (0 errors, 0 warnings, `git status` clean afterwards, so the committed `build/` was fresh), and no `pwsh` held the branch build or the baseline build imported.

Every `<scratch>` below is `C:\Users\Trent\AppData\Local\Temp\m31\scratch`, outside the repository. Each step ran in its own `pwsh -NoProfile`. The harness scripts were scratch files and are not committed.

## Setup

```powershell
git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers
New-Item -ItemType Directory -Path <scratch>\v3.0.1\CompleterActions -Force | Out-Null
git archive --format=tar -o <scratch>\WP11\v3.0.1.tar v3.0.1
tar -x -f <scratch>\WP11\v3.0.1.tar -C <scratch>\v3.0.1\CompleterActions
Set-Location <scratch>\v3.0.1\CompleterActions; Invoke-Build -Task compile
```

The archive went through a file rather than a pipe; the extracted tree is the same. `tar` is `C:\WINDOWS\system32\tar.exe`. The compile step built `CompleterActions.Core.dll` with 0 warnings and 0 errors and filled `build\CompleterActions\lib`. The baseline manifest reports `ModuleVersion` 3.0.1 with no `Prerelease`. The clone holds 176 `*_completer.ps1` files, and its `ps_completers.psd1` gives no `Test-CompleterSet` finding under the branch build.

## Gate run

```powershell
.\tools\Measure-CompleterStartup.ps1 -CompleterRoot <scratch>\PS_Completers -BaselineModulePath <scratch>\v3.0.1\CompleterActions\build\CompleterActions -Iterations 10
```

`-ModulePath` was the default, the branch's `build/CompleterActions`. The tool ran from the repository root through a scratch script that captured its output with `Out-String -Width 200`, so its rows print in list form; the values are the tool's. The run took from 16:48:44 to 16:50:27 local time. One run was taken; its `LazyNoHash` `RatioToBaseline` is at or under 1.05, so the run rule of section 10 needs no further runs.

```text
Module: C:\Users\Trent\AppData\Local\Temp\m31\INT\CompleterActions\build\CompleterActions
Baseline: C:\Users\Trent\AppData\Local\Temp\m31\scratch\v3.0.1\CompleterActions\build\CompleterActions
Scripts: 176, targets: 372, samples per leg: 10
Set: 176 entries, 176 Hash lines. No-Hash copy: 176 entries, 0 Hash lines.

Leg             : Eager
Scripts         : 176
Targets         : 372
Samples         : 10
MedianMs        : 4031.1
MinMs           : 3902.6
MaxMs           : 4151.1
RatioToEager    : 1
RatioToBaseline : 2.42

Leg             : Baseline
Scripts         : 176
Targets         : 372
Samples         : 10
MedianMs        : 1667
MinMs           : 1589.8
MaxMs           : 1770.6
RatioToEager    : 0.41
RatioToBaseline : 1

Leg             : Lazy
Scripts         : 176
Targets         : 372
Samples         : 10
MedianMs        : 1008
MinMs           : 986.6
MaxMs           : 1046.6
RatioToEager    : 0.25
RatioToBaseline : 0.6

Leg             : LazyNoHash
Scripts         : 176
Targets         : 372
Samples         : 10
MedianMs        : 1655.5
MinMs           : 1596
MaxMs           : 1714.2
RatioToEager    : 0.41
RatioToBaseline : 0.99
```

`LazyNoHash` against `Baseline`: 1655.5 / 1667.0 ms = 0.993 (the tool prints 0.99).

The `Lazy` row is reported, not gated: 1008.0 ms, 0.60 of the `Baseline` median in the same run.

## Update-CompleterSet times (reported, not gated)

The set was a second clone, `<scratch>\WP11\PS_Completers-update`, cloned from `<scratch>\PS_Completers`, so the first clone stayed untouched. Its `ps_completers.psd1` has 176 entries, each with a `Hash` and `Trusted = $false`, and 67589 bytes with CR LF line endings in the clone's working tree, where `core.autocrlf` is `true`, and no byte-order mark.

Each sample is a fresh `pwsh -NoProfile -NonInteractive -File <scratch>\WP11\update-child.ps1`, started as `$PSHOME\pwsh.exe`, which imports the branch build by path, asserts `ModuleBase`, and times one call with no warm-up, so each sample includes the first-call cost a user pays:

```powershell
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$written = @(Update-CompleterSet -LiteralPath $SetPath -PassThru -WarningVariable warnings -WarningAction SilentlyContinue)
$sw.Stop()
```

`Import-Module` is outside the stopwatch. Before every sample the parent wrote the set's original bytes back. For the changed case it also appended the line `# WP11 benchmark change` to `rg_completer/rg_completer.ps1`, which changes that script's hash and not its targets; for the unchanged case it wrote the script's original bytes back. Ten pairs, alternating, the unchanged case first in each pair. After the runs both files were restored and `git status --short` printed nothing in either clone.

| Sample | None ms | One changed ms |
| --- | --- | --- |
| 1 | 1520.6 | 1774.7 |
| 2 | 1486.7 | 1731.8 |
| 3 | 1575.7 | 1770.0 |
| 4 | 1570.1 | 1752.9 |
| 5 | 1525.4 | 1738.9 |
| 6 | 1600.0 | 1783.7 |
| 7 | 1511.5 | 1696.7 |
| 8 | 1483.3 | 1692.1 |
| 9 | 1530.2 | 1688.5 |
| 10 | 1329.4 | 1750.8 |
| Median | 1523.0 | 1744.9 |

In every unchanged sample `-PassThru` returned nothing, no warning was written, and the set's bytes were unchanged. In every changed sample `-PassThru` returned the one set, no warning was written, exactly one line of the set differed afterwards (the `Hash` line of the `rg` entry), and the file's length was unchanged.

## Criteria

| Criterion | Expected | Measured | Result |
| --- | --- | --- | --- |
| `LazyNoHash` `RatioToBaseline`, by the section 10 run rule | at most 1.05 | 0.99 on run 1 of 1 (1655.5 / 1667.0 ms) | Pass |
| `Lazy` `RatioToBaseline` | reported, not gated | 0.60 (1008.0 / 1667.0 ms) | Reported |
| `Update-CompleterSet` over the PS_Completers set, no changed script | reported, not gated | median 1523.0 ms over ten fresh processes | Reported |
| `Update-CompleterSet` over the PS_Completers set, one changed script | reported, not gated | median 1744.9 ms over ten fresh processes | Reported |
