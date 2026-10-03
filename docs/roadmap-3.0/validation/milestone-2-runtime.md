# Milestone 2 runtime validation (WP9, spec section 8)

Run on 2026-10-03 at branch commit `a229841` (`feat/milestone-2-authoring-distribution`), Windows pwsh 7.6.6 on Microsoft Windows 11 Pro 10.0.26300, with PSReadLine 2.4.5. `build/` was rebuilt with `Invoke-Build -Task build` first and `git status` was clean afterwards. The branch build reports `ModuleVersion` 2.1.0 (the release commit has not been made); the stamped copy used where a by-name import must satisfy `-MinimumVersion 2.2.0` differs from it in the `.psd1` `ModuleVersion` only (`2.2.0`). The 2.1.0 build is `git archive v2.1.0 build`, never the gallery copy. ripgrep is 15.2.0 (`rg --version`: `ripgrep 15.2.0 (rev e89fff89ac)`). PS_Completers was read only through a scratch clone at `2c590c6` (`git -c core.longpaths=true clone C:\Users\Trent\OneDrive\Documents\PowerShell\Completers <scratch>\PS_Completers`).

Every check ran in its own `pwsh -NoProfile` process (WSL checks in `/snap/bin/pwsh -NoProfile`, Ubuntu on WSL2, pwsh 7.6.5, PSResourceGet 1.2.0) and began with section 8's preamble, which printed the line `ModuleBase OK: ...` below the branch's `build\CompleterActions` (or `/mnt/c/.../build/CompleterActions` under WSL). `<scratch>` is a folder under the session scratchpad, outside the repository. No check read or wrote the real PS_Completers folder. The Windows PSResourceGet store was never registered to, published to, or saved from: every register, publish, and save step ran under WSL in a child with `XDG_DATA_HOME` pointing at a folder created first, and each child asserted that the repository names were the same before and after (`[PSGallery]` both times); the WSL store without the redirect was also read before and after and was unchanged.

## Summary

| Row | Check | Result |
| --- | --- | --- |
| 1 | Check 1, owner form (scaffold for ripgrep) | pass |
| 2 | Check 2, by-name import of a saved package (WSL) | pass |
| 3 | Check 3, no engine cmdlets on 7.6.6 | pass (local half; the eight CI legs are not in this machine's reach) |
| 4 | Check 16, plain set untouched in the clone | pass |
| 5 | Check 17, PS_Completers as a package | **FAIL** (the staged folder as the spec shapes it cannot be saved; with the set file renamed, every assertion passes) |
| 6 | Check 19, PSReadLine live | pass |
| 7 | Check 20, surface | pass |
| 8 | Check 22, help from the build | pass |
| 9 | Section 7 spot checks (`-LiteralPath` against 2.1.0, `Reset-Completer -Verbose`) | pass |
| 10 | Check 15 installed-copy half, in the saved folders | pass |
| 11 | Check 22 gates run here (lint, Pester) | lint pass; **Pester 1 failure on this machine** |

## Row 1: check 1, owner form

```powershell
$file = New-CompleterScript -CommandName rg -Path <scratch>\rg_completer.ps1 -PassThru -Force
$file | Test-CompleterScript                            # empty
Test-CompleterScript -LiteralPath $file.FullName        # empty
(Get-Content -LiteralPath $file.FullName)[0..1]
(Import-CompleterScript -LiteralPath $file.FullName).CommandName
```

```text
PassThru type: System.IO.FileInfo
pipeline findings: 0
literal findings: 0
line1: # rg tab completion for PowerShell
line2: # Native completer skeleton: add subcommands to the table and options to Complete-Rg.
targets: rg,rg.exe
rg version: ripgrep 15.2.0 (rev e89fff89ac)
```

With `-Verbose` the probe line read `Probed '...\WinGet\Links\rg.exe --help': exit 0, 74735 characters, 0 subcommands, 35 ms.` and `Wrote '...rg_completer.ps1': 2 targets, 0 subcommands.` The parameter set was Probe (no `-HelpText`, no `-NoProbe`). Result: **pass**.

## Row 2: check 2, by-name import of a saved package, under WSL

The Windows store cannot be redirected (spec section 8), so this ran under WSL. The package `CaFixtureSet` was built as the plan's helper builds it (manifest at the root, `completers/completers.psd1` from `Export-CompleterSet`, three fixture scripts from `tests/Fixtures/CompleterSetPackage`), then:

```powershell
# child: pwsh -NoProfile -File publish-child.ps1, with XDG_DATA_HOME=/tmp/wp9-check2/xdg created first
Register-PSResourceRepository -Name CaLocal-<8 hex> -Uri /tmp/wp9-check2/repo -Trusted
Publish-PSResource -Path /tmp/wp9-check2/pkg/CaFixtureSet -Repository CaLocal-<8 hex> -SkipModuleManifestValidate -SkipDependenciesCheck
Save-PSResource -Name CaFixtureSet -Repository CaLocal-<8 hex> -Path /tmp/wp9-check2/modules -SkipDependencyCheck
# finally: Unregister-PSResourceRepository -Name CaLocal-<8 hex>
```

```text
store location: XDG_DATA_HOME=/tmp/wp9-check2/xdg ; repo name CaLocal-4161395f ; PSResourceGet 1.2.0
repositories before: [PSGallery]
registered; during: [CaLocal-4161395f,PSGallery]
published: CaFixtureSet.1.0.0.nupkg
saved: /tmp/wp9-check2/modules/CaFixtureSet;/tmp/wp9-check2/modules/CaFixtureSet/1.0.0
repositories after: [PSGallery]
store names identical before and after: True
real store (no XDG) before: [PSGallery]; after: [PSGallery] unchanged: True
```

Then two separate `pwsh -NoProfile` processes with the preamble and `/tmp/wp9-check2/modules` first on `PSModulePath`: `Import-CompleterSet -Name CaFixtureSet | Select-Object Key, RuntimeKey, State, Trusted, ScriptPath | ConvertTo-Csv` and the same for `-LiteralPath <ModuleBase>/completers/completers.psd1`:

```text
MODE=Name    warnings=0 errors=0 records=6
MODE=Literal warnings=0 errors=0 records=6
(the two CSV bodies are byte-identical; ScriptPath, shown as <ModuleBase>/..., is under the installed ModuleBase for every record)
all ScriptPath under ModuleBase (/tmp/wp9-check2/modules/CaFixtureSet/1.0.0): True
```

The CSV pair is `docs/roadmap-3.0/validation/milestone-2-check2-import-name.csv` (column `Mode` is `Name` or `LiteralPath`; the module base is written `<ModuleBase>`). The step was run twice (the WSL `/tmp` was cleared between sessions); both runs gave this result. The Windows legs of CI are the Windows coverage. Result: **pass**.

## Row 3: check 3

```text
pwsh: 7.6.6
Get-Command Get-ArgumentCompleter, Unregister-ArgumentCompleter -ErrorAction Ignore -> count: 0
```

**Pass** for the local half. The "full suite passes unchanged on all eight CI legs" half needs the pull request's runs, which do not exist yet; it is untested here.

## Row 4: check 16, second half

`Test-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1`, in a process per build, each with the preamble (the 2.1.0 process asserts `ModuleBase` equal to `<scratch>\v2.1.0\build\CompleterActions`):

```text
branch build: Test-CompleterSet findings: 0
2.1.0 build:  Test-CompleterSet findings: 0
```

Result: **pass**.

## Row 5: check 17, PS_Completers as a package (FAIL as specified)

The prototypes of WP10 step 1 were written, uncommitted, in the scratch clone and are reproduced in the appendix: `package/PS_Completers.psd1`, `tools/Build-Package.ps1`, and a `Describe` block appended to `tests/Completers.Tests.ps1`.

1. `Test-CompleterSet -LiteralPath <staging>\PS_Completers\completers\ps_completers.psd1` (branch build, stage of 173 scripts):

   ```text
   staged: <scratch>\stg\PS_Completers
   top-level: completers, LICENSE, PS_Completers.psd1, README.md
   scripts staged: 173
   Test-CompleterSet staged findings: 0
   ```
   **Pass.**

2. The clone's Pester run under the stamped build (`ModuleBase` asserted to be `<scratch>\stamped\CompleterActions`, version 2.2.0), `Invoke-Pester -Path ./tests -CI -PassThru`:

   ```text
   before the prototype: total=176 passed=176 failed=0 skipped=0 result=Passed
   after the prototype:  total=177 passed=177 failed=0 skipped=0 result=Passed
   ```
   **Pass** (previous count plus one).

3. Publish and save of the staged folder under WSL with the XDG redirect, as in row 2 with `-PkgName PS_Completers`:

   ```text
   registered; during: [CaLocal-158fbef8,PSGallery]
   published: PS_Completers.1.0.0.nupkg
   Save-PSResource: ... TryConvertFromHashtableForPsd1: Could not find expected information from
   module manifest file hashtable with error: Value cannot be null. (Parameter 'input')
   child exit: 1
   real store unchanged: True
   ```
   **FAIL.** Publish (pack plus push to the local repository) works; `Save-PSResource` does not. Cause, bisected under WSL with PSResourceGet 1.2.0: a package whose module is named `PS_Completers` and which holds a file `completers/ps_completers.psd1` cannot be saved. Evidence: (a) the same manifest in a package with no other `.psd1` saves; (b) a manifest generated by `New-ModuleManifest`, with a GUID, `PowerShellVersion`, tags, and `LicenseUri` added one at a time and all together, saves; (c) a minimal package with the manifest plus `completers/ps_completers.psd1` containing `@{ SchemaVersion = 1; Entries = @() }` fails with the error above, and the same package with that file named `set.psd1` saves. The save step appears to pick up the file whose name matches `<module name>.psd1` case-insensitively, anywhere in the package, and reads the set as if it were the manifest. This is the same name collision spec section 3 names for the repository root (`PS_Completers.psd1` and `ps_completers.psd1` are one file on Windows and macOS), here inside `completers/`. It is a spec and plan defect, reported, not fixed: the package layout in section 3 and WP10 (`completers/ps_completers.psd1`) cannot be installed by PSResourceGet 1.2.0 on Linux. Whether Windows behaves the same is untested (the Windows store was not touched).

4. Variant that isolates the cause (a deviation from the spec's shape, recorded so the rest of the row can be judged): the stage was rebuilt with the set file renamed to `completers/completers.psd1` (byte-identical to the original, SHA-256 compared) and the manifest's `PrivateData.CompleterSet` set to `completers/completers.psd1`.

   ```text
   set file byte-identical to the original: True
   Test-CompleterSet renamed-set findings: 0
   published: PS_Completers.1.0.0.nupkg
   saved: /tmp/wp9-check17/modules/PS_Completers;/tmp/wp9-check17/modules/PS_Completers/1.0.0
   store names identical before and after: True
   MODE=Name    warnings=0 errors=0 records=362 pending=362   (all ScriptPath under ModuleBase: True)
   MODE=Literal warnings=0 errors=0 records=362 pending=362   (-LiteralPath <scratch>\PS_Completers\ps_completers.psd1)
   KEYS_IDENTICAL
   ```
   The `Key` and `State` lists of the two processes are equal for all 362 records; the table is `docs/roadmap-3.0/validation/milestone-2-check17-import-name.csv`. The count is 362 at `2c590c6` (the spec's appendix B gives 173 entries and 362 targets). **Pass for the variant only.**

Row result: **FAIL** until the spec and plan change the set file's name or place, or a PSResourceGet fix is confirmed.

## Row 6: check 19, PSReadLine, live

```text
PSReadLine: 2.4.5
handlers in snapshot: 197
New-CompleterScript (rg probe) done
Import-CompleterSet -Name CaFixtureSet records: 6
Test-CompleterSet -Name CaFixtureSet findings: 0
after New-CompleterScript identical: True
after Import-CompleterSet -Name and Test-CompleterSet -Name identical: True
```

The snapshot is `Get-PSReadLineKeyHandler -Bound -Unbound` as `Key|Function|Group|Description` lines, compared with `-ceq`. Result: **pass**. (The probe here ran `rg --help`, not `pwsh`; see row 11 for the `pwsh` probe on this machine.)

## Row 7: check 20, surface

```text
branch: functions: 14 aliases: 3
2.1.0 : functions: 13 aliases: 3
```

`Get-Command` metadata (parameter names, and parameter sets with each parameter's mandatory flag and position) dumped from both builds in separate processes and compared with `diff`: the only differences are the new function `New-CompleterScript` (sets `HelpText`, `NoProbe`, `Probe`; `Probe` is the default), the `Name` parameter and `Name` set of `Import-CompleterSet`, and the `Name` parameter and `Name` set of `Test-CompleterSet`. No other function differs in any parameter name or set. `Get-Command New-CompleterScript -Syntax` shows the three sets (row 8). The version and `Prerelease` lines belong to the release commits (recipe steps 5 and 14) and are not checked here. Result: **pass**.

## Row 8: check 22, help from the build, in a fresh process

```text
New-CompleterScript -Full: Name=New-CompleterScript Synopsis=[Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.] examples=3
Import-CompleterSet -Parameter Name: name=Name type=String[] desc=[The names of installed completer set modules. Each name is taken literally: ...]
about_Completer_Sets contains [THE HASH AND THE FAST PATH]: True
about_Completer_Sets contains [CHECKING FOR DRIFT WITH TEST-COMPLETERSET]: True
about_Completer_Sets contains [COMPLETER SETS AS MODULES]: True
about_Completer_Sets contains [PrivateData.CompleterSet]: True
about_Completer_Sets contains [Import-CompleterSet -Name]: True
about_Import_Completers scaffolding heading at line 207 before strict grammar heading at line 437 : True
DISTRIBUTING COMPLETERS AS A MODULE: True
Synopsis exact: True
Examples count (Get-Help -Examples): 3
New-CompleterScript [-CommandName] <string[]> [-Path] <string> [-HelpArgument <string>] [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -HelpText <string[]> [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
New-CompleterScript [-CommandName] <string[]> [-Path] <string> -NoProbe [-Force] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

The headings were matched as whole trimmed lines, because a first version that matched the first text occurrence of the strict-grammar heading hit an earlier mention and gave a false negative. Result: **pass**.

## Row 9: section 7 spot checks

```powershell
# one process per build; CA_MODULE selects the 2.1.0 build, with the same ModuleBase assertion
Import-CompleterSet -LiteralPath <scratch>\PS_Completers\ps_completers.psd1 -Verbose 3>&1 4>&1
Reset-Completer -CommandName 7z, 7z.exe -Native -Verbose 4>&1 3>&1
```

```text
branch: records=362 verbose=347 warnings=0 / trusted-entry warning present: False / reset output lines: 2
2.1.0 : records=362 verbose=347 warnings=0 / trusted-entry warning present: False / reset output lines: 2
```

`Select-Object Key, RuntimeKey, State, Trusted, ScriptPath | ConvertTo-Csv` (363 lines), the 347 verbose lines, and the two `Reset-Completer -Verbose` lines (`The completer registration '7z' is already pending.`, and the same for `7z.exe`) are byte-identical between the builds (`cmp`). Result: **pass**. This is the pull request gate for risk 14. The `Reset-Completer` case ran on pending registrations only; resetting a materialised registration was not run.

## Row 10: check 15, installed-copy half

`Test-CompleterSet -Name` over the folders saved in rows 2 and 5 (variant), under WSL with the saved roots on `PSModulePath`, and over a package folder in a scratch module root on Windows (`<scratch>\modules\CaFixtureSet\1.0.0`, row 6):

```text
Test-CompleterSet -Name CaFixtureSet findings: 0     (WSL, saved copy of row 2)
Test-CompleterSet -Name PS_Completers findings: 0    (WSL, saved copy of row 5 variant)
Test-CompleterSet -Name CaFixtureSet findings: 0     (Windows, scratch module root)
```

Result: **pass**. The mutation table of check 15 is covered by Pester and was not repeated here.

## Row 11: check 22 gates run on this machine

```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; Invoke-Pester -Path ./tests -CI'
```

Lint printed nothing: **pass**. Pester, run twice (the second time with nothing else running), gave the same result both times:

```text
Tests Passed: 600, Failed: 1, Skipped: 8, Inconclusive: 0, NotRun: 0
[-] Completer authoring and packages leave PSReadLine alone.leaves PSReadLine key handlers unchanged across New-CompleterScript with a probe, Import-CompleterSet -Name, and Test-CompleterSet -Name
 Expected $null or empty, but got 'pwsh <TestDrive>\neutral-...\neutral-help.ps1' did not exit within 5 seconds and was stopped, so its help was not used..
 at @($probeWarnings) | Should -BeNullOrEmpty, tests\CompleterSetPackage.Tests.ps1:1684
```

**FAIL on this machine.** The test probes `pwsh <fixture>` without `-NoProfile`, so the child `pwsh` loads the owner's profile (`Microsoft.PowerShell_profile.ps1`), which does not exit: started with `Start-Process pwsh` and redirected stdin and stdout, `pwsh -NoProfile nh.ps1` exited in 0.2 s and `pwsh nh.ps1` was still running after 30 s (the profile printed `Set-PSReadLineOption: The predictive suggestion feature cannot be enabled because the console output doesn't support virtual terminal processing or it's redirected.` at its line 128). A CI runner has no profile, so this is expected to pass there; the test is not independent of the user profile. The failure is in the test's fixture choice, not in the command: the live check of row 6 shows the key handlers unchanged. Reported, not fixed. Pester was not run under WSL.

## Untested, and risks

- The eight CI legs (check 3, check 22) and the Windows legs of the package tests need the pull request.
- Whether the `PS_Completers` and `ps_completers.psd1` collision of row 5 also affects `Install-PSResource`, and whether it affects Windows, was not run (the Windows store must not be touched; `Install-PSResource` was not tried under WSL).
- The release commits' version and `Prerelease` lines (check 20, first bullet) wait for the release commits.
- The literal roadmap install line is the owner's, after the publish.

## Appendix: WP10 step 1 prototypes (scratch clone, uncommitted)

`package/PS_Completers.psd1` (the first version also had `RootModule = ''`; removing it did not change the save failure):

```powershell
@{
    ModuleVersion         = '1.0.0'
    GUID                  = '6b0d8c7e-3a41-4f6a-9d2e-5c1a7f0e9b34'
    Author                = 'Trent Stager'
    Description           = 'Argument completers for native commands, as a CompleterActions completer set.'
    PowerShellVersion     = '7.2'
    RequiredModules       = @(@{ ModuleName = 'CompleterActions'; ModuleVersion = '2.2.0' })
    FunctionsToExport     = @()
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        CompleterSet = 'completers/ps_completers.psd1'
        PSData       = @{
            Tags       = @('completer', 'argument-completer', 'CompleterActions')
            LicenseUri = 'https://github.com/tstager/PS_Completers/blob/master/LICENSE'
        }
    }
}
```

`tools/Build-Package.ps1`:

```powershell
<#
.SYNOPSIS
Stages the PS_Completers package folder for Publish-PSResource.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DestinationPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$package = Join-Path -Path $DestinationPath -ChildPath 'PS_Completers'
$completers = Join-Path -Path $package -ChildPath 'completers'

New-Item -Path $completers -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'package/PS_Completers.psd1'), (Join-Path $repoRoot 'LICENSE'), (Join-Path $repoRoot 'README.md') -Destination $package
Copy-Item -LiteralPath (Join-Path $repoRoot 'ps_completers.psd1') -Destination $completers
Get-ChildItem -LiteralPath $repoRoot -Directory -Filter '*_completer' | Copy-Item -Destination $completers -Recurse

Get-Item -LiteralPath $package
```

Appended to `tests/Completers.Tests.ps1` (passes: 177 tests):

```powershell
Describe 'The staged package is a conforming package set' {
    BeforeAll {
        Import-Module -Name CompleterActions -MinimumVersion 2.2.0 -ErrorAction Stop
    }

    It 'has no findings from Test-CompleterSet' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $package = & (Join-Path -Path $repoRoot -ChildPath 'tools/Build-Package.ps1') -DestinationPath $TestDrive

        $findings = @(Test-CompleterSet -LiteralPath (Join-Path -Path $package.FullName -ChildPath 'completers/ps_completers.psd1'))

        $findings | Should -BeNullOrEmpty -Because (($findings | ForEach-Object { "$($_.Construct): $($_.Message) $($_.Hint)" }) -join '; ')
    }
}
```
