# cargo tab completion for PowerShell
# Help-seeded native completer: the tables were read from help text passed to New-CompleterScript.

Set-StrictMode -Version 2.0

if (-not (Get-Variable -Name CargoCompletionCatalog -Scope Script -ErrorAction Ignore)) {
    $script:CargoCompletionCatalog = @{
        Subcommands = @(
            @{ Name = 'build'; Description = 'Compile the current package' }
            @{ Name = 'check'; Description = 'Analyze the current package and report errors, but don''t build object files' }
            @{ Name = 'clean'; Description = 'Remove the target directory' }
            @{ Name = 'doc'; Description = 'Build this package''s and its dependencies'' documentation' }
            @{ Name = 'new'; Description = 'Create a new cargo package' }
            @{ Name = 'init'; Description = 'Create a new cargo package in an existing directory' }
            @{ Name = 'add'; Description = 'Add dependencies to a manifest file' }
            @{ Name = 'remove'; Description = 'Remove dependencies from a manifest file' }
            @{ Name = 'run'; Description = 'Run a binary or example of the local package' }
            @{ Name = 'test'; Description = 'Run the tests' }
            @{ Name = 'bench'; Description = 'Run the benchmarks' }
            @{ Name = 'update'; Description = 'Update dependencies listed in Cargo.lock' }
            @{ Name = 'search'; Description = 'Search registry for crates' }
            @{ Name = 'publish'; Description = 'Package and upload this package to the registry' }
            @{ Name = 'install'; Description = 'Install a Rust binary' }
            @{ Name = 'uninstall'; Description = 'Uninstall a Rust binary' }
        )
        Options = @(
            @{ Name = '-V'; Description = 'Print version info and exit' }
            @{ Name = '--version'; Description = 'Print version info and exit' }
            @{ Name = '--list'; Description = 'List installed commands' }
            @{ Name = '--explain'; Description = 'Provide a detailed explanation of a rustc error message' }
            @{ Name = '-v'; Description = 'Use verbose output (-vv very verbose/build.rs output)' }
            @{ Name = '--verbose'; Description = 'Use verbose output (-vv very verbose/build.rs output)' }
            @{ Name = '-q'; Description = 'Do not print cargo log messages' }
            @{ Name = '--quiet'; Description = 'Do not print cargo log messages' }
            @{ Name = '--color'; Description = 'Coloring [possible values: auto, always, never]' }
            @{ Name = '-C'; Description = 'Change to DIRECTORY before doing anything (nightly-only)' }
            @{ Name = '--locked'; Description = 'Assert that `Cargo.lock` will remain unchanged' }
            @{ Name = '--offline'; Description = 'Run without accessing the network' }
            @{ Name = '--frozen'; Description = 'Equivalent to specifying both --locked and --offline' }
            @{ Name = '--config'; Description = 'Override a configuration value' }
            @{ Name = '-Z'; Description = 'Unstable (nightly-only) flags to Cargo, see ''cargo -Z help'' for' }
            @{ Name = '-h'; Description = 'Print help' }
            @{ Name = '--help'; Description = 'Print help' }
        )
    }
}

function Complete-Cargo {
    param(
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [int]$cursorPosition
    )

    # Offer options in any position once the word starts with '-' or '/'.
    if ($wordToComplete.StartsWith('-') -or $wordToComplete.StartsWith('/')) {
        foreach ($option in $script:CargoCompletionCatalog.Options) {
            if ($option.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                [System.Management.Automation.CompletionResult]::new($option.Name, $option.Name, 'ParameterName', $option.Description)
            }
        }
    }

    # Offer subcommands in the first argument position only; extend this function for values.
    $precedingElements = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition })
    if ($precedingElements.Count -gt 1) {
        return
    }

    foreach ($subcommand in $script:CargoCompletionCatalog.Subcommands) {
        if ($subcommand.Name.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
            [System.Management.Automation.CompletionResult]::new($subcommand.Name, $subcommand.Name, 'ParameterValue', $subcommand.Description)
        }
    }
}

Register-ArgumentCompleter -Native -CommandName 'cargo', 'cargo.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cargo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
