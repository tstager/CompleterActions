# CompleterActions repository instructions

## Build, test, and lint commands

- Build uses Invoke-Build tasks defined in `CompleterActions.build.ps1` and surfaced through generated VS Code tasks in `.vscode\tasks.json`.
- Run the default build task from the repository root with `Invoke-Build -Task .`.
- Run named build tasks with `Invoke-Build -Task clean` or `Invoke-Build -Task build`. The generated task list also includes `Markdown_templates`, `external_help`, and `?`, but only `clean`, `build`, and `.` currently exist in `CompleterActions.build.ps1`.
- Run the current test suite from the repository root with `Invoke-Pester`.
- Run a single test file with `Invoke-Pester -Path .\tests\CompleterActions.Tests.ps1`.
- Run a single test case with `Invoke-Pester -Path .\tests\CompleterActions.Tests.ps1 -FullNameFilter 'Module Manifest Tests.Passes Test-ModuleManifest'`.
- Lint with the repository ruleset using `Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` and `Invoke-ScriptAnalyzer -Path .\tests -Recurse -Settings .\PSScriptAnalyzerSettings.psd1`.
- VS Code is configured to use `.\PSScriptAnalyzerSettings.psd1` automatically through `.vscode\settings.json`.
- `tests\CompleterActions.Tests.ps1` assumes the module manifest lives at the repository root as `CompleterActions.psd1`.

## High-level architecture

- This repository is a PowerShell module skeleton centered on the root-level `CompleterActions.psd1` and `CompleterActions.psm1`.
- The manifest declares `RootModule = 'CompleterActions.psm1'`, so importing the module starts in the repo-root module file.
- Module assembly is file-system driven. `CompleterActions.psm1` uses the repository root as its anchor, then dot-sources `*.ps1` files from selected folders under `src\` before exporting public commands.
- Only functions whose scripts live in `src\Public\` are exported. Export names are derived from the `.ps1` filenames in that folder with `Export-ModuleMember -Function $publicFunctions`.
- Internal helpers belong in `src\Private\` and are expected to be loaded into module scope without being exported.
- The repository layout also reserves `src\Classes\`, `src\docs\`, and `src\DSCResources\` for classes, docs/help content, and DSC resources, even though they are currently empty.

## Key conventions

- Treat `CompleterActions.psm1` as the source of truth for module bootstrapping. It loads code from `src\Private`, `src\Public`, and `src\docs`, so changes to source layout need corresponding updates there.
- Public command discovery is convention-based rather than manifest-based. Adding or renaming a file in `src\Public\` changes the exported function set automatically.
- The module manifest still exports wildcards (`FunctionsToExport = '*'`, `CmdletsToExport = '*'`, `VariablesToExport = '*'`, `AliasesToExport = '*'`), but the `.psm1` narrows function exports explicitly. When changing exports, keep both layers consistent.
- `.vscode\tasks.json` is generated; do not hand-edit it. The file explicitly says to change `CompleterActions.build.ps1` or `.vscode\tasks-merge.json` and then regenerate tasks.
- The repository is set up for strict PSScriptAnalyzer enforcement. `PSScriptAnalyzerSettings.psd1` enables rules such as approved verbs, singular nouns, no aliases, no positional parameters, and `ShouldProcess` requirements for state-changing functions.
- `.justfile` is only a convenience wrapper for launching Copilot with GitHub MCP tools enabled. It is not the build or test entry point for the module itself.
