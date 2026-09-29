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

## Rerun after `fa3f43f`

`fa3f43f` removes redundant helper calls from the per-target import path (no record changes). The same command was run three times on 2026-09-28 at `fa3f43f`, pwsh 7.6.6, PS_Completers at `c821644`, with the baseline package extracted from `v2.0.0` the same way. Each run reported `Scripts: 173, targets: 366` and `Set: 173 entries, 173 Hash lines. No-Hash copy: 173 entries, 0 Hash lines.`

| Run | Eager ms | Baseline ms | Lazy ms | LazyNoHash ms | `Lazy` `RatioToBaseline` | `LazyNoHash` `RatioToBaseline` |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 8152.7 | 1589.4 | 815.1 | 1362.2 | 0.51 | 0.86 |
| 2 | 8675.2 | 1676.2 | 824.1 | 1388.4 | 0.49 | 0.83 |
| 3 | 9053.7 | 1656.3 | 886.0 | 1427.8 | 0.53 | 0.86 |

Interleaved child-process A/B runs of `Import-CompleterSet` alone over the hashed set put `fa3f43f` about 40 to 60 ms below `1432534`, which is smaller than the run-to-run spread of the `Lazy` median above (815 to 886 ms). The `Lazy` ratio therefore sits on the 0.50 line rather than below it: one run of three passes, and check 1 stays a miss under the section 7 fallback. The `LazyNoHash` leg is now 14 to 17 percent faster than 2.0.0, outside the within-10-percent band on the fast side, as the WP7 run (0.90) already was. Owner decisions on 2026-09-29: the measured range 0.49 to 0.54 is accepted under the section 7 fallback and the roadmap criterion is restated to it; the `LazyNoHash` band is read as "not slower than 2.0.0", so that leg passes; the scripted `-Confirm` Pester test stands in for the manual check 12.
