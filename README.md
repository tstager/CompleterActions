# CompleterActions

`CompleterActions` is a PowerShell module for registering, discovering, querying, and removing PowerShell argument completers in a consistent way.

It wraps `Register-ArgumentCompleter` with module-managed registration tracking, while also discovering completers that were registered directly in the current PowerShell runtime.

> [!IMPORTANT]
> This module targets **PowerShell 7+ / PowerShell Core only**. The manifest declares `CompatiblePSEditions = @('Core')` and `PowerShellVersion = '7.0'`.

## Features

- Manage both **parameter completers** and **native command completers**
- Import supported completer scripts into **managed registration input objects**
- Query **module-managed** registrations and **runtime-discovered** registrations
- Remove managed registrations cleanly from both runtime and module state
- Require explicit opt-in before removing unmanaged runtime registrations
- Return rich registration objects with default table formatting
- Support property-name pipeline binding and paging for discovery scenarios

## Public commands

### `Get-CompleterRegistration`

Lists completer registrations known to the module or discovered from the current runtime.

Use it to:

- list all registrations
- query by registration key
- query native completers by command name
- query parameter completers by command + parameter
- limit results to managed-only or discovered-only entries

### `Import-CompleterScript`

Imports supported completer scripts into objects that can be piped directly to
`Register-CompleterRegistration -InputObject`.

Use it to:

- import self-contained completer scripts without mutating the live runtime
- preserve helper functions and script-scope state captured by the imported script block
- reject unsupported script shapes before execution
- bridge existing standalone completer scripts into this module's managed workflow

### `Register-CompleterRegistration`

Registers a managed completer and records it in module state.

Use it to:

- register parameter completers
- register native completers
- replace an existing runtime or managed registration with `-Force`
- return the created registration record with `-PassThru`

### `Unregister-CompleterRegistration`

Removes completer registrations from runtime and, when applicable, from module-managed state.

Use it to:

- remove managed registrations
- remove runtime-only registrations with `-AllowUnmanaged`
- work by key, by command target, or from pipeline input
- return removed records with `-PassThru`

## Install / import

After the module is published, install it from the gallery:

```powershell
Install-PSResource -Name CompleterActions
Import-Module CompleterActions
```

If you are using Windows PowerShell's older PowerShellGet tooling:

```powershell
Install-Module -Name CompleterActions
Import-Module CompleterActions
```

For development, clone the repository and import the module from the repository root:

```powershell
Import-Module .\CompleterActions.psd1
```

Or import the built module output after running the build:

```powershell
Import-Module .\build\CompleterActions\CompleterActions.psd1
```

For the conceptual import guide, run:

```powershell
Get-Help about_Import_Completers
```

Runtime registration discovery and unmanaged-registration removal depend on
PowerShell runtime internals. The module is tested on PowerShell 7, but future
engine changes may require maintenance in that discovery path.

## Quick start

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

## Common flows

### Get registrations

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

### Register and inspect

```powershell
$registration = Register-CompleterRegistration `
    -CommandName Invoke-DemoTool `
    -ParameterName Name `
    -ScriptBlock $scriptBlock `
    -PassThru

$registration | Format-List *
Get-CompleterRegistration -Key $registration.RegistrationKey
```

### Replace an existing registration

```powershell
Register-CompleterRegistration `
    -CommandName Invoke-DemoTool `
    -ParameterName Name `
    -ScriptBlock $scriptBlock `
    -Force
```

### Unregister

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

## Output, formatting, paging, and pipeline support

Registration records use the `CompleterActions.CompleterRegistration` type and have a default table view with:

- `Command`
- `Parameter`
- `Type`
- `Source`

`Get-CompleterRegistration` supports PowerShell paging parameters, so you can do things like:

```powershell
Get-CompleterRegistration -First 10
Get-CompleterRegistration -Skip 10 -First 10 -IncludeTotalCount
```

Pipeline highlights:

- `Get-CompleterRegistration` supports property-name binding for key/command/parameter lookups
- `Import-CompleterScript` emits input objects that are ready for `Register-CompleterRegistration -InputObject`
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
Invoke-Pester
```

### Linting

The repository includes `PSScriptAnalyzerSettings.psd1`.

```powershell
Invoke-ScriptAnalyzer -Path .\src -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\CompleterActions.psm1 -Settings .\PSScriptAnalyzerSettings.psd1
```

## Architecture notes

- `CompleterActions.psd1` is the root manifest and defines the exported public functions, formatting file, and PowerShell/Core compatibility.
- `CompleterActions.psm1` is a lightweight root loader that dot-sources `src\Private` and `src\Public`, initializes module state, and exports the public function set.
- `src\Public` contains the user-facing command surface:
  - `Get-CompleterRegistration`
  - `Import-CompleterScript`
  - `Register-CompleterRegistration`
  - `Unregister-CompleterRegistration`
- `src\Private` contains the runtime/state helpers that resolve targets, manage the module registration table, and inspect/remove runtime registrations.

### Runtime internals caveat

The module currently discovers live completer registrations by reflecting into PowerShell runtime internals to access the underlying completer dictionaries. That makes the current implementation practical and useful, but it also means runtime discovery depends on non-public engine details and may need maintenance if PowerShell internals change in a future release.

## Development notes

- Managed registrations are tracked in module state for the current session.
- Runtime-discovered registrations can be queried even if they were not created by this module.
- Removal of unmanaged runtime registrations is intentionally gated behind `-AllowUnmanaged`.
