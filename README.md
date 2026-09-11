# CompleterActions

<p align="center">
    <img src="src/Assets/CompleterActions.png" alt="CompleterActions logo" width="560" />
</p>

<p align="center"><strong>PowerShell completion scripts for managed registrations, runtime discovery, and safe removal.</strong></p>

<p align="center">
    <a href="https://github.com/tstager/CompleterActions/actions/workflows/ci.yml"><img src="https://github.com/tstager/CompleterActions/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
    <a href="https://learn.microsoft.com/powershell/"><img src="https://img.shields.io/badge/PowerShell-7%2B-012456?logo=powershell&logoColor=white" alt="PowerShell 7+" /></a>
    <a href="https://learn.microsoft.com/powershell/scripting/install/powershell-core-support"><img src="https://img.shields.io/badge/Edition-Core-0078D4?logo=powershell&logoColor=white" alt="PowerShell Core only" /></a>
    <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-MIT-2da44e.svg" alt="MIT License" /></a>
</p>

`CompleterActions` is a PowerShell 7+ / Core-only module for registering, discovering, querying, and removing PowerShell argument completers in a consistent way.

> [!IMPORTANT]
> This module targets **PowerShell 7+ / PowerShell Core only**. The manifest declares `CompatiblePSEditions = @('Core')` and `PowerShellVersion = '7.0'`.

## At a glance

- Manage both parameter completers and native command completers
- Import completer scripts into managed registration input objects through a strict grammar or, for scripts you own, a trusted tier
- Describe a whole completer repository in one set file, validate it up front, and register it with a single command
- Check completer scripts against the strict grammar and get findings with line numbers and fix hints
- Verify a registration by running tab completion for an input and getting the matches back as objects
- Query module-managed registrations and runtime-discovered registrations
- Remove managed registrations cleanly from both runtime and module state
- Require explicit opt-in before removing unmanaged runtime registrations
- Return rich registration objects with default table formatting
- Support property-name pipeline binding and paging for discovery scenarios

## Command map

| Command | What it does |
| --- | --- |
| `Export-CompleterSet` | Writes a completer set file (`.psd1`) from registrations that came from scripts, with each script's trust tier and targets |
| `Get-CompleterRegistration` | Lists completer registrations known to the module or discovered from the current runtime |
| `Import-CompleterScript` | Converts standalone completer scripts into objects that can be piped to `Register-CompleterRegistration -InputObject`; strict grammar by default, `-Trusted` to run the script as-is |
| `Import-CompleterSet` | Validates every entry of a completer set up front, then registers the whole set lazily; `-SkipInvalid` warns and registers the rest |
| `Register-CompleterRegistration` | Registers a managed completer and records it in module state; `-Path -Lazy` registers a completer script that loads on its first tab press |
| `Test-CompleterRegistration` | Runs tab completion for an input against a registered target and returns the completion matches |
| `Test-CompleterScript` | Checks completer scripts against the strict import grammar and returns findings with line, column, construct, and a fix hint |
| `Unregister-CompleterRegistration` | Removes completer registrations from runtime and, when applicable, from module state |

## Start here

### Install from the gallery

```powershell
Install-PSResource -Name CompleterActions
Import-Module CompleterActions
```

### Import from the repository during development

```powershell
Import-Module .\CompleterActions.psd1
```

### Import the built module output

```powershell
Import-Module .\build\CompleterActions\CompleterActions.psd1
```

### Read the conceptual guides

```powershell
Get-Help about_Import_Completers
Get-Help about_Completer_Sets
```

Runtime registration discovery and unmanaged-registration removal depend on PowerShell runtime internals. The module is tested on PowerShell 7, but future engine changes may require maintenance in that discovery path.

## Typical flow

1. Check an existing completer script with `Test-CompleterScript`, or decide to import it with `-Trusted`.
2. Register a completer directly, or import the script into managed input objects.
3. Verify the registration with `Test-CompleterRegistration` and inspect it with `Get-CompleterRegistration`.
4. Replace or remove registrations when the target changes.
5. Use `-AllowUnmanaged` only when removing runtime registrations that were not created by the module.

## Examples

### Register a parameter completer

```powershell
function Invoke-DemoTool {
    [CmdletBinding()]
    param(
        [string] $Name
    )
}

$scriptBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    'alpha', 'beta', 'gamma' |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name -ScriptBlock $scriptBlock
```

### Register a native completer

```powershell
$nativeScriptBlock = {
    param($wordToComplete, $commandAst, $cursorPosition)

    'status', 'switch', 'sync' |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-CompleterRegistration -CommandName demoexe -Native -ScriptBlock $nativeScriptBlock
```

### Import an existing completer script

```powershell
Import-CompleterScript -Path .\7z_completer.ps1 |
    Register-CompleterRegistration -PassThru
```

### Check a completer script before importing it

```powershell
# One script: findings with line, column, construct, message, and hint
Test-CompleterScript -Path .\7z_completer.ps1

# A whole repository: empty when every script conforms
Get-ChildItem -Path ~\Completers -Recurse -Filter *.ps1 |
    Test-CompleterScript |
    Where-Object Severity -eq Error
```

### Import a script you own with the trusted tier

```powershell
Import-CompleterScript -Path .\git_completer.ps1 -Trusted |
    Register-CompleterRegistration
```

### Register a script lazily

```powershell
# Strict tier: the targets are read from the script, which runs on the first tab press
Register-CompleterRegistration -Path .\7z_completer.ps1 -Lazy

# Trusted tier: name the targets, because a trusted script is not parsed
Register-CompleterRegistration -Path .\git_completer.ps1 -Lazy -Trusted -CommandName git, git.exe -Native

# Pending until the first tab press; Failed, with LoadError, if the script did not load
Get-CompleterRegistration -ManagedOnly | Where-Object State -in Pending, Failed
```

### Describe a completer repository as a set

```powershell
# Build the set once, without registering anything in this session
Get-ChildItem ~\Completers -Recurse -Filter *_completer.ps1 |
    Import-CompleterScript |
    Export-CompleterSet -Path ~\Completers\completers.psd1

# The profile then needs one line
Import-CompleterSet -Path ~\Completers\completers.psd1
```

### Verify a registration

```powershell
Test-CompleterRegistration -CommandName git -Native -InputText 'git che'

Get-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name |
    Test-CompleterRegistration -InputText 'Invoke-DemoTool -Name a'
```

### Query registrations

```powershell
# All known registrations
Get-CompleterRegistration

# A specific native completer
Get-CompleterRegistration -CommandName git -Native

# A specific parameter completer
Get-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name

# Only module-managed registrations
Get-CompleterRegistration -ManagedOnly

# Only runtime-discovered registrations
Get-CompleterRegistration -DiscoveredOnly
```

### Replace an existing registration

```powershell
Register-CompleterRegistration `
    -CommandName Invoke-DemoTool `
    -ParameterName Name `
    -ScriptBlock $scriptBlock `
    -Force
```

### Unregister registrations

```powershell
# Remove a managed registration
Unregister-CompleterRegistration -CommandName Invoke-DemoTool -ParameterName Name -Confirm:$false

# Remove by key
Get-CompleterRegistration -CommandName demoexe -Native |
    Unregister-CompleterRegistration -Confirm:$false

# Remove a runtime-only registration explicitly
Unregister-CompleterRegistration `
    -CommandName SomeTool `
    -ParameterName Name `
    -AllowUnmanaged `
    -Confirm:$false
```

## Lazy loading and completer sets

A completer set is a `.psd1` data file that lists completer scripts, the trust tier each one loads under, and the targets each one registers:

```powershell
@{
    Version = 1
    Entries = @(
        @{
            Path    = 'git_completer.ps1'
            Trusted = $false
            Targets = @(
                @{ CommandName = 'git'; Native = $true }
            )
        }
    )
}
```

`Import-CompleterSet` reads the file with `Import-PowerShellDataFile`, so the set itself can never run code, and validates every entry before registering anything: the file exists and is a `.ps1`, `Trusted` entries declare their `Targets`, strict entries name their targets with literal `Register-ArgumentCompleter` arguments so they can be derived from the parsed script and compared against any the entry declares, no target is listed by two entries, and without `-Force` no target already carries a managed or runtime registration for a different completer. The strict grammar itself runs when a script loads, not at import: importing a set parses each strict script once, to validate the entry, registers the targets that parse derived, and walks none of them; a script that fails the grammar moves to `Failed` on its first tab press. One error lists every problem; `-SkipInvalid` turns them into warnings and registers the rest.

Registering a set does not run the scripts. Each target gets a stub and a managed record in state `Pending`; the first tab press for that target loads the script, swaps in the real completer, and moves the record to `Active`. A script that fails to load yields no completions for that press, records the error as `LoadError` with state `Failed`, and removes its stub so PowerShell's default completion takes over. Nothing the module does hooks PSReadLine key handlers, replaces `TabExpansion2`, or changes PSReadLine options. `about_Completer_Sets` covers the schema and lifecycle in full, and `tools/Measure-CompleterStartup.ps1` measures the eager and lazy startup cost of a completer repository in child `pwsh -NoProfile` processes. On a 169-script, 355-target repository (five samples per leg) the eager `Import-CompleterScript | Register-CompleterRegistration` pipeline takes a median 7427.7 ms and `Import-CompleterSet` a median 1806.1 ms, a ratio of 0.24; that sits at the roadmap target of 0.25 with a thin margin, since the eager leg moves by a few hundred milliseconds between runs, and the remaining lazy cost is one parse per strict script plus the per-target conflict check and registration bookkeeping.

## Output, formatting, paging, and pipeline support

Registration records use the `CompleterActions.CompleterRegistration` type and have a default table view with:

- `Command`
- `Parameter`
- `Type`
- `Source`
- `State`
- `ScriptPath`
- `LoadError`

`State` is `Active` for records that describe the live runtime value. If another caller replaces or removes a managed target with the built-in `Register-ArgumentCompleter`, the managed record becomes `Stale`: `Get-CompleterRegistration` returns the live value as `Conflicted`, `Register-CompleterRegistration` requires `-Force` to reconcile, and `Unregister-CompleterRegistration` requires `-AllowUnmanaged` before it removes the live value together with the stale record. A lazy registration is `Pending` until its script loads on the first tab press. If that load fails, the press returns no completions and default completion applies exactly as with no completer registered; the record becomes `Failed` with the message in `LoadError`, its runtime entry is removed, and `Register-CompleterRegistration -Force` retries. `ScriptPath` names the completer script behind a lazy or imported registration. Lazy loading runs inside the ordinary completer call and never touches PSReadLine key handlers, `TabExpansion2`, or PSReadLine options.

`Test-CompleterScript` returns `CompleterActions.CompleterScriptFinding` records shown as a list grouped by script path, with `Line`, `Column`, `Severity`, `Construct`, `Message`, and `Hint`. A conforming script returns nothing. `Test-CompleterRegistration` returns `CompleterActions.CompletionMatch` records shown as a table grouped by target key, with `CompletionText`, `ListItemText`, `ResultType`, and `ToolTip`.

`Get-CompleterRegistration` supports PowerShell paging parameters, so you can do things like:

```powershell
Get-CompleterRegistration -First 10
Get-CompleterRegistration -Skip 10 -First 10 -IncludeTotalCount
```

Pipeline highlights:

- `Get-CompleterRegistration` supports property-name binding for key, command, and parameter lookups
- `Import-CompleterScript` emits input objects that are ready for `Register-CompleterRegistration -InputObject`
- `Export-CompleterSet` accepts records from `Get-CompleterRegistration` and `Import-CompleterScript`; `Import-CompleterSet` accepts `Get-ChildItem` output through `FullName` binding
- `Test-CompleterScript` accepts `Get-ChildItem` output directly through `FullName` binding
- `Test-CompleterRegistration` accepts registration records from `Get-CompleterRegistration` and `Import-CompleterScript`
- `Register-CompleterRegistration` can accept input objects that describe a target and expose a `ScriptBlock`
- `Unregister-CompleterRegistration` can accept pipeline input directly from `Get-CompleterRegistration`

Example:

```powershell
Get-CompleterRegistration -ManagedOnly |
    Unregister-CompleterRegistration -Confirm:$false
```

## Build, test, and lint

### Build

The repository uses `Invoke-Build`.

```powershell
Invoke-Build -Task clean
Invoke-Build -Task build
Invoke-Build -Task external_help
Invoke-Build -Task Markdown_templates
Invoke-Build -Task ?
```

### Tests

The repository uses `Pester`.

```powershell
Invoke-Pester -Path .\tests
```

Run the tests in their own `pwsh -NoProfile` process. Importing PSScriptAnalyzer into the same session registers an argument completer that changes the discovered registration order the paging tests assert on. The tests also compare the tracked `build\CompleterActions` package against the sources, so run them before `Invoke-Build -Task build`, which regenerates that package.

### Linting

The repository includes `PSScriptAnalyzerSettings.psd1`. CI runs the same two commands.

```powershell
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\tests -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

## Releasing

Once per repository, add a PowerShell Gallery API key as the `GALLERY_API_KEY` secret under Settings > Secrets and variables > Actions.

Each release is then a tag push:

```powershell
# bump ModuleVersion in CompleterActions.psd1, move the Unreleased CHANGELOG entries
# under the new version heading, then regenerate and commit the packaged build
Invoke-Build -Task build
git commit -am 'chore(release): bump module version to X.Y.Z'
git tag vX.Y.Z
git push origin main vX.Y.Z
```

The tag push runs `release_check`, `build`, the Pester suite, `Publish_build`, and finally creates the GitHub release. The tag must equal `v` plus `ModuleVersion` or `release_check` throws before anything is published.

## Architecture notes

- `CompleterActions.psd1` is the root manifest and defines the exported public functions, formatting file, and PowerShell/Core compatibility.
- `CompleterActions.psm1` is a lightweight root loader that dot-sources `src\Private` and `src\Public`, runs `src\Bootstrap.ps1`, and exports the public function set.
- `src\Bootstrap.ps1` holds the import-time work shared by the source root module and the packaged module: the runtime capability probe and module state initialization. The build appends it to the packaged `.psm1` after the function definitions.
- `src\Public` contains the user-facing command surface:
  - `Export-CompleterSet`
  - `Get-CompleterRegistration`
  - `Import-CompleterScript`
  - `Import-CompleterSet`
  - `Register-CompleterRegistration`
  - `Test-CompleterRegistration`
  - `Test-CompleterScript`
  - `Unregister-CompleterRegistration`
- `src\Private` contains the runtime and state helpers that resolve targets, manage the module registration table, and inspect or remove runtime registrations. The strict import grammar lives in `Test-CompleterScriptAst`, which returns `CompleterActions.CompleterScriptFinding` records that both `Test-CompleterScript` and `Import-CompleterScript` consume. Completer sets are read by `Import-CompleterSetDefinition`, validated entry by entry in `Resolve-CompleterSetEntry` (with `Get-CompleterScriptTarget` deriving strict-tier targets from the AST), and registered through `Register-CompleterSetEntry`.
- `tools\Measure-CompleterStartup.ps1` is the startup benchmark: eager import versus `Import-CompleterSet`, each sampled in fresh `pwsh -NoProfile` processes.

### Runtime internals caveat

The module discovers live completer registrations by reflecting into PowerShell runtime internals to access the underlying completer dictionaries. That makes the current implementation practical and useful, but it also means runtime discovery depends on non-public engine details and may need maintenance if PowerShell internals change in a future release.

`Assert-CompleterRuntimeCapability` resolves every reflected member once during import. On an engine whose internals have changed, `Import-Module` fails with a single error that names the running PowerShell version and the members that could not be resolved, instead of a later `Get` or `Register` call failing deep inside the module.

## Development notes

- Managed registrations are tracked in module state for the current session.
- Runtime-discovered registrations can be queried even if they were not created by this module.
- Removal of unmanaged runtime registrations is intentionally gated behind `-AllowUnmanaged`.
