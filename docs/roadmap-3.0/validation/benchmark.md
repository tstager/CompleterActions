# WP9 startup benchmark (spec section 8, check 1)

Run on 2026-09-28 at branch commit `80e6ee1` (`feat/milestone-1-faster-imports`), pwsh 7.6.6 on Microsoft Windows 10.0.26200, PS_Completers at `c821644` (173 scripts).

```powershell
.\tools\Measure-CompleterStartup.ps1 -BaselineModulePath <scratch>\v2.0.0\build\CompleterActions -Iterations 10
```

`-ModulePath` was the default, the branch's `build/CompleterActions`. The baseline package was extracted with `git archive v2.0.0 build | tar -x`.

```text
Module: C:\Users\Trent\OneDrive\Documents\My Scripts\Code\PowerShell\Modules\CompleterActions\build\CompleterActions
Baseline: C:\Users\Trent\AppData\Local\Temp\wp9m1\v2.0.0\build\CompleterActions
Scripts: 173, targets: 366, samples per leg: 10
Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.

Leg        Scripts Targets Samples MedianMs   MinMs   MaxMs RatioToEager RatioToBaseline
---        ------- ------- ------- --------   -----   ----- ------------ ---------------
Eager          173     366      10  8590.80 7827.40 8861.30         1.00            5.39
Baseline       173     366      10  1592.80 1551.60 1647.50         0.19            1.00
Lazy           173     366      10   843.70  820.50  897.00         0.10            0.53
LazyNoHash     173     366      10  1447.40 1375.90 1588.10         0.17            0.91
```

| Criterion | Expected | Measured | Result |
| --- | --- | --- | --- |
| `Lazy` `RatioToBaseline` | below 0.50 | 0.53 | Miss, under the section 7 fallback (the roadmap exit criterion was restated to 0.54 in `792929e`) |
| `LazyNoHash` against `Baseline` | within 10 percent | 1447.4 / 1592.8 ms, 9.1 percent faster | Pass |

The `Targets` column counts the records of the eager export the tool builds its set from (366). The committed `ps_completers.psd1` resolves to 362 records (checks 4, 7, and 9).
