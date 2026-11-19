# Changelog

All notable changes to CompleterActions are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Fixes for the eighteen findings in `docs/code-review-2026-11-18.md`. The
behaviour changes they bring are listed under Changed.

### Fixed

- Strict `Import-CompleterScript` runs the revision it validated. The
  importer parsed the file for the grammar and then had the capture module
  dot-source the path, which read the file again, so a save between the two
  reads ran text the grammar never saw, on eager import and on a lazy stub's
  first-tab load alike. The script is now resolved once and the contents
  that were parsed are the contents that run, with the script still the
  source file of errors, `$PSScriptRoot`, and `$PSCommandPath`. The importer
  refuses to run any file other than the one it resolved (2026-11-18
  review, finding 1).
- Strict import keeps a script's helpers out of the caller's and the
  module's function tables. `function global:Name` passed the grammar and
  defined `Name` in the caller's global scope while the script was
  dot-sourced, even though its body never ran. Every other helper,
  unqualified or `script:`, `local:`, or `private:`, and the capture
  module's own `Register-ArgumentCompleter` shim, were imported into the
  CompleterActions module scope, so a helper named after a private command
  of the module replaced it: a script defining `Get-CompleterScriptFinding`
  turned off the strict gate for every later import, and
  `Register-ArgumentCompleter` inside the module resolved to the shim. The
  capture module now exports nothing into the module, under `-Trusted` too,
  and helpers still resolve at completion time (2026-11-18 review,
  finding 2).
- Editing a record a command returns no longer changes the registration.
  `Get-Completer`, `Register-Completer -PassThru`, `Reset-Completer
  -PassThru`, `Import-CompleterSet`, and `Unregister-Completer -PassThru`
  wrote the objects held in the managed table, so setting `State` to
  `Failed` on a returned record made the next query report `Failed/Managed`
  and `Conflicted/Discovered` for a live registration, editing `ScriptPath`
  changed what a lazy load read, and a downstream failure under
  `Unregister-Completer -PassThru` put the edited record or script block
  back (2026-11-18 review, finding 3).
- `IsNative`, `Native`, and `Trusted` on an input object refuse a
  collection or another kind of object. Every value that was not text was
  cast to Boolean, so a parameter registration whose `Native` and `Trusted`
  were `@($false, $false)` registered a native, trusted completer and
  dropped its `ParameterName` (2026-11-18 review, finding 4).
- `Test-CompleterRegistration` tells the target's own matches from the
  rest. It labelled every `TabExpansion2` match with the tested target, so
  a match from another parameter's completer, when the cursor sat on that
  parameter, or the engine's file-name fallback, when the target's
  completer returned nothing, was credited to the target, and an assertion
  could pass while the completer contributed nothing (2026-11-18 review,
  finding 5).
- A failed lazy load keeps a newer registration of its own target. A
  trusted lazy script that replaced its target with `Register-Completer
  -Force`, or removed it with `Unregister-Completer`, and then threw had
  that state overwritten: `Get-Completer` reported the old stub as `Failed`
  and the live replacement as a `Conflicted` discovered entry, and an
  unregistered target came back as `Failed`. A failure is now recorded only
  while the stub's own record still owns the target (2026-11-18 review,
  finding 6).
- `Test-CompleterScript` reports `Register-ArgumentCompleter` calls that
  PowerShell cannot bind. A repeated parameter, such as two `-CommandName`
  arguments, a value-taking parameter followed directly by another
  parameter, such as `-CommandName -Native`, and an empty or blank
  `-CommandName` or `-ParameterName` name, alone or inside a literal array,
  gave no finding and then failed at import. Parameter names are also
  compared with the invariant culture, so under tr-TR a repeated
  `-ScriptBlock`/`-SCRIPTBLOCK` is reported and an upper-case
  `-SCRIPTBLOCK` alone is no longer refused as missing (2026-11-18 review,
  finding 7).
- A script that holds only a `begin`, `process`, `dynamicparam`, or `clean`
  block no longer stops `Test-CompleterScript`. The grammar recorded the
  named-block finding and then threw the 2.x binder message, so later paths
  in the same call were never checked; it now returns the `NamedBlockAst`
  finding and the missing-registration finding and goes on, and
  `Import-CompleterScript` refuses such a script with those findings
  (2026-11-18 review, finding 8).
- `Export-CompleterSet` resolves a relative `ScriptPath` or `SourcePath`
  against the PowerShell location. It resolved it against the process
  working directory, so after `Push-Location` a trusted export referenced
  a script in another tree and warned that hashing failed, and a strict
  export failed although the script existed (2026-11-18 review, finding 9).
- `Export-CompleterSet` keeps two scripts whose names differ only by case
  apart on Linux. Records were grouped ignoring case on every platform, so
  `Alpha.ps1` and `alpha.ps1` became one entry: a trusted export listed
  both targets under the first file, and a strict export failed. Grouping
  now ignores case on Windows and macOS and is exact on Linux, as the other
  path comparisons in the module are (2026-11-18 review, finding 10).
- One malformed `Path` in a set file no longer ends `Import-CompleterSet`
  or `Test-CompleterSet`. A null character, or on Windows a full path over
  32767 characters, made path normalization throw before the entry was
  classified, so `-SkipInvalid` could not skip it and the valid entries
  after it were never checked. Such an entry is now an `InvalidEntry`
  (`The Path is not a valid file path: ...`), and the package-layout check
  of `Test-CompleterSet` no longer fails on it (2026-11-18 review,
  finding 11).
- A set file's `Version` must really be 1. `$true` compared equal to 1, so
  a set with `Version = $true` imported (2026-11-18 review, finding 12).
- Standalone completers that `New-CompleterScript` generates for different
  commands no longer share a catalog. `ca-tool` and `ca_tool`, and `tool`,
  `tool.cmd`, `tool.bat`, `tool.ps1`, and `tool.com`, gave the same stem, so
  their scripts defined the same `Complete-<Stem>` function and
  `$script:<Stem>CompletionCatalog` variable, and dot-sourced together
  every command completed from the first script's table (2026-11-18 review,
  finding 13).
- The `release_check` build task checks the tag being published. On a tag
  push it compared whichever tag `git describe` picked on HEAD, while the
  workflow publishes under `GITHUB_REF_NAME`, so a second tag on the same
  commit passed the gate. It now compares `GITHUB_REF_NAME` when
  `GITHUB_REF_TYPE` is `tag`, and compares ordinally, so a tag that differs
  in case or by an invisible character such as a zero-width space fails
  (2026-11-18 review, finding 14).
- A release rerun after a partial failure can finish. `Publish_build`
  pushed the package every time, so rerunning the release job after a later
  step failed tried to publish the same version again, which PSGallery
  refuses, and never reached the GitHub release. It now looks up the exact
  version first: when the repository already holds it, it compares every
  file of the published package with `build/CompleterActions`, apart from
  the manifest's `Generated on` line, and continues without publishing when
  they match or fails naming the files that differ (2026-11-18 review,
  finding 15).
- The build moves only top-level `using` statements into the package, and
  only their own text. Any source line that read like a `using` statement
  was hoisted, so a here-string line `using namespace System.Text` was
  removed from its function (2026-11-18 review, finding 16).
- The release workflow takes its notes only from the changelog heading
  whose version matches the tag exactly. The pattern matched a prefix, so a
  stable `3.0.1` tag would have published the `3.0.1-preview1` section, and
  `3.0.1` matched a `3.0.10` heading; a tag with no exact heading now gets
  generated notes (2026-11-18 review, finding 17).

### Changed

- **Strict import refuses `function global:Name`.** A definition the strict
  grammar lets run at import time, at script scope or inside a guarded
  `if`, is reported when its name is in the global scope (`The script
  defines function 'Name' in the global scope.`), so `Test-CompleterScript`
  reports it and `Import-CompleterScript` refuses the script without
  `-Trusted`. A `global:` definition inside a function body or a completer
  script block runs only at completion time and is still accepted. None of
  the 175 PS_Completers scripts uses one (2026-11-18 review, finding 2).
- **Helpers of an imported script are no longer visible inside the
  module.** Neither tier imports the capture module's functions, aliases,
  or variables into CompleterActions, which only code running inside the
  module could see before (2026-11-18 review, finding 2).
- **Returned records are snapshots.** The records the five commands above
  write are copies, so two calls that describe one registration return two
  objects, and `-eq` between them is false. The copy is shallow: its
  `ScriptBlock` and `ImportModule` are the live objects (2026-11-18 review,
  finding 3).
- **`IsNative`, `Native`, and `Trusted` take only a scalar.** On an input
  object they accept null, a Boolean or switch value, a number, including a
  `BigInteger` such as `0n` or `1n`, where zero is False, and the text
  `True` or `False`. A collection, even of one element, is refused with
  `InputObject supplies a collection for <Property>, which takes a single
  Boolean value.`, and any other type, such as a character, an enum value,
  `DBNull`, `Int128`, `UInt128`, `Half`, `Complex`, or `IntPtr`, with
  `InputObject supplies a value of type <Type> for <Property>, which is not
  a Boolean value.` These were cast before, and the zero of the last five
  read as True (2026-11-18 review, finding 4).
- **`Test-CompleterRegistration` reports where each match came from.**
  `CompletionMatch` has a new `FromTarget` property, shown in the default
  table, that is `$true` only for matches the target's own completer
  produced; every match the engine returns is still reported, so filter
  with `Where-Object FromTarget` to verify the registration itself. To see
  the target's output the command fronts its runtime entry with an observer
  for the one completion; the completer runs as it does at the prompt, and
  output it returns is passed to the engine unchanged. Because the completer
  really runs, testing a `Pending` lazy registration loads it, as the help
  now says (2026-11-18 review, finding 5).
- **`Test-CompleterScript` reports more registrations.** A repeated
  `Register-ArgumentCompleter` parameter (`The script specifies
  Register-ArgumentCompleter parameter '-<Name>' more than once.`), a
  parameter left without its value, and an empty or blank name (`The script
  uses an empty or blank name for -<Parameter>.`) are now Error findings,
  so strict import refuses these scripts before running them instead of
  failing in the binder. A whitespace-only name binds in PowerShell but is
  reported too, because the importer refuses it (2026-11-18 review,
  finding 7).
- **`Export-CompleterSet` path rules.** A relative `ScriptPath` or
  `SourcePath` follows the PowerShell location and PowerShell drives; a
  path that resolves to a provider other than the file system is refused;
  and a provider-qualified path whose part after `::` is not fully
  qualified, such as `FileSystem::Native.ps1`, is refused, where it wrote
  a reference to a file in the process working directory before. A fully
  qualified provider-qualified path still exports (2026-11-18 review,
  finding 9).
- **An unresolvable set entry `Path` is an `InvalidEntry`.** A `Path` with
  a null character, or on Windows a full path over 32767 characters, is
  skipped under `-SkipInvalid` and reported by `Test-CompleterSet`, where
  it ended the command with an exception before (2026-11-18 review,
  finding 11).
- **A set `Version` is a number or the text `1`.** The version is compared
  with 1 only when it is text, or a number of one of the integer,
  floating-point, decimal, or `BigInteger` types; text must be exactly `1`.
  A Boolean, a character, an array such as `@(1)`, and text that equals `1`
  only under culture-aware comparison, such as `1` with a zero-width space,
  or a non-ASCII digit one such as U+0661, are refused. `1`, `1L`, `1.0`,
  `1d`, `1n`, and `'1'` still import (2026-11-18 review, finding 12).
- **Generated script identifiers changed for some command names.**
  `New-CompleterScript` gives a name that has a character other than an
  ASCII letter or digit, apart from a trailing `.exe`, a stem ending in `_`
  and eight hex digits of a SHA-256 of the name: `ca-tool` gives
  `Complete-CaTool_8f74ce7e`, `_a` gives `Complete-A_34fb7160`, and
  `npm.cmd` gives `Complete-Npm_a04d41f6`. Names of letters and digits, with
  or without `.exe`, keep their plain stem, so `cargo` and `cargo.exe` still
  give `Complete-Cargo`. Scripts generated before keep working; regenerating
  one for such a name changes its function and catalog variable names
  (2026-11-18 review, finding 13).
- **The build script has a `-Repository` parameter.** It names the
  repository `Publish_build` publishes to and looks the version up in, and
  defaults to `PSGallery` (2026-11-18 review, finding 15).

### Documentation

- The help of `Register-Completer` and `about_Completer_Sets` says that a
  trusted lazy script that replaced or removed its own target before it
  failed keeps that newer state and no failure is recorded (2026-11-18
  review, finding 6).
- The README's repository quick starts run `Invoke-Build -Task compile`
  before importing either manifest, because the assembly the manifests load
  is not tracked; `compile` also copies it into `build/CompleterActions`,
  so the full `build`, which needs Microsoft.PowerShell.PlatyPS, is not
  needed there (2026-11-18 review, finding 18).

## [3.0.1-preview1] - 2026-11-14

Fixes for all eight findings in `docs/code-review-2026-11-10.md`. The
behaviour changes they bring are listed under Changed.

### Fixed

- The strict import grammar refuses a literal `-CommandName` or
  `-ParameterName` target array that carries a redirection or a background
  operator. `@('tool' 2> file)` passed `Test-CompleterScript` with no
  finding, and default `Import-CompleterScript` then ran the redirection
  while it dot-sourced the script and truncated the file, although the strict
  tier promises that import cannot write a file. The recognizer of
  `@('tool', 'tool.exe')` arrays now rejects an array whose expression has a
  redirection or whose pipeline ends in `&`, so `Test-CompleterScript`
  reports `The script must use literal string values for -CommandName.`
  (`ArrayExpressionAst`) and `Import-CompleterScript` refuses the script
  before it runs. Forms that write nothing, such as `@('tool' 2>&1)`,
  `@('tool' 2> $null)`, and `@('tool' &)`, passed both commands before and
  are refused too. Strict `Register-Completer -Lazy` already refused an
  array with a redirection, because the read of its targets did not take it
  as literal, so `@('tool' &)` is the only form it newly refuses. None of
  the 175 PS_Completers scripts uses one of these forms (CA-2026-11-01).
- A managed registration is Active only while the runtime holds its own
  script block object. Reconciliation accepted any runtime block whose text
  compared equal, ignoring case, so a different closure with the same text,
  registered outside the module with `Register-ArgumentCompleter`, was
  reported as Active and could be removed without `-AllowUnmanaged`, and a
  second `Register-Completer` with such a closure silently kept the first
  one. Text now only decides whether a registration reuses the managed
  record: it must match case-sensitively, and the block must be bound to
  the same context. For an imported script that means one of the script
  block objects `Import-CompleterScript` emitted for that script and tier,
  recorded by the module itself, never the `ImportModule`, `SourcePath`, or
  `Trusted` of the piped object; otherwise the same module and defining
  file. Importing and registering a script again stays a no-op, and a
  closure, which has a module of its own, needs `-Force` (CA-2026-11-02).
- A registration is identified by its kind and its runtime key. A native
  command named `Cmd:Name` and the parameter target `Cmd` / `Name` share the
  normalized `Key`, and lookups passed only that key and searched the
  native registrations first, so `Get-Completer`, `Unregister-Completer`,
  `Reset-Completer`, and `Register-Completer -Force` could return or remove
  the other kind. The managed table, the runtime lookups, lazy stubs, and
  every deduplication now use the kind plus the `RuntimeKey`, compared as
  PowerShell compares its completer keys, so names the lowercased `Key`
  merges, such as one spelled with the Kelvin sign (U+212A) and one with
  the letter k, stay apart too. Script paths compare ignoring case on
  Windows and macOS and exactly on Linux. An input object that names its
  target only by `Key` or `RegistrationKey` is refused while a registered
  target of its kind holds that key under another spelling. The public
  `Key` and `RegistrationKey` values are unchanged (CA-2026-11-03).
- `Export-CompleterSet` after a pipe, or given `-InputObject`, exports only
  the records it receives, even when it receives none. A `Get-Completer`
  filter that matched nothing, piped to the command, fell through to the
  no-input default and replaced an existing set file with every managed
  script registration in the session. An empty pipe, an empty array,
  `$null`, and a filter that matches nothing, piped or passed to
  `-InputObject`, now warn that no registrations were selected, write
  nothing, and leave an existing file unchanged. `-InputObject` no longer
  carries `[ValidateNotNull()]`: a null is skipped, so `@($null, $record)`
  exports the record instead of failing parameter binding. Only a call with
  no pipe before it and no `-InputObject` exports every managed
  registration, and a wrapper function must pass its input on, as in
  `$input | Export-CompleterSet`, because the command cannot see a pipe in
  front of its caller. The command help and `about_Completer_Sets` say so
  (CA-2026-11-04).
- A set that `Export-CompleterSet` writes reads back. `Import-CompleterSet`
  and `Test-CompleterSet` read a set with `Import-PowerShellDataFile` and
  its default limits of 500 keys and 5000 syntax nodes, which the exporter
  does not share, so a set of more than 384 single-target entries failed
  with `Cannot generate a PowerShell object for a ScriptBlock evaluating
  dynamic expressions`. The reader now reads the set file once, never more
  than one byte past 128 KB (131072 bytes), decodes it as
  `Import-PowerShellDataFile` does, and evaluates it with the cmdlet's own
  data-only evaluator without those two limits, so a set still runs no
  code. Every `Test-CompleterSet` finding position comes from that read.
  `Export-CompleterSet` measures the bytes it would write and refuses a set
  over the limit, writing nothing. As the command writes entries, with a
  `Hash`, 128 KB holds about 400 of one target each (CA-2026-11-05).
- Generated PowerShell literals escape every single-quote delimiter the
  tokenizer accepts: U+0027 and the typographic U+2018, U+2019, U+201A, and
  U+201B. Only the ASCII apostrophe was doubled, so a script in a folder
  such as `author’s scripts` exported a set that `Import-CompleterSet`
  could not parse, and a target named with a typographic apostrophe made
  `Register-Completer -Lazy` fail with `The string is missing the
  terminator`. The set exporter's `Path`, `CommandName`, and `ParameterName`
  lines, the lazy stub that `Register-Completer -Lazy`, `Import-CompleterSet`,
  and `Reset-Completer` install, the startup benchmark's child scripts, and
  the build's `RequiredAssemblies` line now go through
  `ConvertTo-CompleterSingleQuotedText`, the policy the script skeleton
  already used (CA-2026-11-06).
- The packaged commands use the generated MAML help. The build put the
  `.EXTERNALHELP` directive between each function name and its opening
  brace, where PowerShell does not look for help, so all eleven exported
  commands had a null `MamlHelpFile` and `Get-Help` showed their source
  comment help instead of the maintained markdown help. The directive now
  replaces the command's own comment help in the packaged psm1. Selecting
  the MAML brought fixes to the help itself: a related link that is not
  http or https keeps its text and drops its URI, because `Get-Help` stops
  on a relative first link; each page's online link names its page on
  main; OUTPUTS lists only the type each command declares; and every
  PARAMETERS and syntax entry carries the pipeline input, required flag,
  position, aliases, and type the command declares. The build fails when a
  source defines or replaces a public command a second time, including
  under a scope modifier, through a literal `Function:` path or a
  `${function:}` variable, and when the package, imported in a new pwsh,
  exports a command other than the definition that carries the directive
  (CA-2026-11-07).
- The `Markdown_templates` build task works in a fresh process. It imported
  the root `.psm1` directly, which skips the manifest's `RequiredAssemblies`
  entry, and failed with `Unable to find type
  [CompleterActions.Internal.EngineAccess]` before writing a page. It now
  depends on `compile` and imports the source manifest in a child
  `pwsh -NoProfile`, so it loads the core `compile` just built, the build
  process never holds `lib/CompleterActions.Core.dll`, and the task can run
  twice in one session. A session that has the repository's module imported
  still fails at `compile`, as `compile` and `build` already did on Windows;
  the README describes the task (CA-2026-11-08).

### Changed

- **A new instance of a module replaces its record without `-Force`.**
  After `Import-Module -Force`, even with the same arguments, or a second
  `New-Module` with the same name, a script block with the same text,
  defining file, `ScriptPath`, and tier as a live managed record replaces
  the record and its runtime block, so completion runs in the module that
  is loaded now. A module that registers its completer when it is imported
  therefore keeps working after `Import-Module -Force`. A Stale or Failed
  record still needs `-Force` (CA-2026-11-02).
- **The same text in another context is another completer.** A script block
  whose text equals the managed record's but that is bound to another
  module or file, or is a closure, now needs `-Force`, where the first
  block was silently kept before. `Register-Completer -Lazy` over an Active
  record that the script's own import did not create needs `-Force` too
  (CA-2026-11-02).
- **Boolean properties are read, not cast.** `IsNative`, `Native`, and
  `Trusted` on an input object take a Boolean, a number, or the text `True`
  or `False` in any letter case, with or without white space around it; a
  null, or text that is empty or only white space, is False, and any other
  text is refused. The text `False` that `Export-Csv` writes was cast
  to True before, so a parameter row resolved to the native target and a
  strict script exported as trusted. In a set file a target's `Native` must
  be `$true` or `$false`; anything else, `$null` included, is an
  `InvalidEntry` (CA-2026-11-02, CA-2026-11-03).
- **Set files, and the module manifests read with them, are limited to
  128 KB.**
  `Import-CompleterSet` and `Test-CompleterSet` refuse a set file over
  131072 bytes before they parse it, and `Export-CompleterSet` refuses to
  write one, under `-WhatIf` too. A module manifest over the same limit
  fails `-Name` and declares no set in the package check. Parse time still
  grows with the square of the syntax errors, so a malformed set near the
  limit can take minutes to refuse (CA-2026-11-05).
- **Installed `Get-Help` comes from the MAML.** The exported commands show
  the maintained markdown help as PlatyPS writes it into the MAML, with its
  inline code, bold text, and fenced examples, as PowerShell's own cmdlet
  help shows them after `Update-Help`, instead of their plain source
  comment help (CA-2026-11-07).

## [3.0.0] - 2026-10-11

The stable 3.0.0 release. Same code as 3.0.0-rc1, promoted after the
candidate soaked for a week in a profile and in the PS_Completers conformance
CI without a defect, per roadmap decision 6. The 3.0.0-rc1 section below is
the full record of the milestone: the compiled C# core with public record
types, the version-gated engine boundary, the PowerShell 7.4 minimum, the
removal of the 1.x aliases, legacy wrappers, and `-ManagedOnly`/`-DiscoveredOnly`,
and the rewritten migration guide.

## [3.0.0-rc1] - 2026-10-04

### Removed

- **The 1.x aliases** (breaking). `Get-CompleterRegistration`,
  `Register-CompleterRegistration`, and `Unregister-CompleterRegistration`
  are no longer exported; calling one fails with PowerShell's own
  `CommandNotFoundException`. Use `Get-Completer`, `Register-Completer`, and
  `Unregister-Completer`.
- **The legacy wrappers** (breaking). `Get-CompleterRegistrationLegacy`,
  `Register-CompleterRegistrationLegacy`, and
  `Unregister-CompleterRegistrationLegacy` existed only to carry the aliases
  and are gone with them.
- **`-ManagedOnly` and `-DiscoveredOnly`** (breaking), which only the legacy
  Get wrapper still accepted. Use `-State Active, Pending, Failed, Stale` and
  `-State Discovered, Conflicted` on `Get-Completer`.
- **The once-per-process deprecation warning** the aliases wrote. Nothing is
  written in its place.

### Changed

- **The records are public .NET types** (breaking).
  `CompleterRegistration`, `ImportedCompleterRegistration`,
  `CompleterScriptFinding`, `CompletionMatch`, and the `CompleterState` and
  `CompleterType` enums move from module-private PowerShell classes to
  sealed .NET types in the `CompleterActions` namespace, with the same
  property names and order and the same enum values. Eight differences a
  caller can see: `-is [CompleterActions.CompleterRegistration]` and
  `::new()` work from any scope, and keep working after `Remove-Module`;
  `PSTypeNames` is `CompleterActions.<Type>`, `System.Object`, without the
  bare class name, so the format views and `PSTypeNames[0]` checks are
  unaffected; every string property is `''` when it has no value, now also
  on an instance built with `::new()`, and assigning `$null` stores `''`,
  while `ImportModule` and `ScriptBlock` stay `$null`; enum values still
  serialize as integers; `[enum]::GetNames([CompleterActions.CompleterState])`
  works from a script; hashtable conversion such as
  `[CompleterActions.CompleterScriptFinding] @{ Path = 'x'; Line = 1 }`
  works; `OutputType` names are unchanged; and a record that crosses a
  remoting or job boundary arrives deserialized as before.
- **Engine access runs in the compiled layer.** The import-time capability
  probe, the reflection into `EngineIntrinsics._context`, and the
  resolution of the `CustomArgumentCompleters` and
  `NativeArgumentCompleters` properties move into
  `CompleterActions.Internal.EngineAccess`, which resolves each member once
  per import and keeps the handles, so a member that resolved at import
  cannot fail later in the session. The probe's message and the two other
  engine messages are unchanged, and no `.ps1` under `src` reflects any
  more.
- **The strict grammar runs in the compiled layer, and also at
  registration and import** (breaking). The walk is a compiled AST visitor,
  `CompleterActions.Internal.StrictGrammar`, with the same findings, in the
  same order and with the same text, as the 2.2.0 walk. Because it is cheap
  enough to run wherever a strict script is already parsed for its targets,
  `Register-Completer -Lazy` without `-Trusted` now refuses a
  non-conforming script with the error `Import-CompleterScript` gives, one
  line per finding, before anything is registered and under `-WhatIf` too,
  and `Import-CompleterSet` reports a non-conforming strict entry as an
  invalid entry, `The script does not conform to the strict import grammar:
  line <l>, column <c> (<Construct>): <Message> ...`, ahead of any target
  mismatch for the same entry. An entry whose `Hash` matches takes the fast
  path and is not walked, trusted entries are never walked,
  `Test-CompleterSet` and `Export-CompleterSet` are unchanged, and the
  first-tab check still runs before every strict script executes.
- **`PowerShellVersion = '7.4'`** (breaking), raised from `'7.0'`.
  `Import-Module` on PowerShell 7.0 to 7.3 fails on the manifest with
  PowerShell's own version error. The `src` code may use .NET 8 APIs.

### Added

- **`CompleterActions.Core.dll`.** The compiled core, built from the C#
  project under `src/Core` (`net8.0`, referencing
  `System.Management.Automation` 7.4.0), shipped at
  `lib/CompleterActions.Core.dll` in the module and loaded through the
  manifest's `RequiredAssemblies`. Its `AssemblyVersion` is `3.0.0.0` for
  every 3.x release; the file and informational versions carry the module
  version. It exports no cmdlet, and it is not tracked in git.
- **The `compile` build task.** `Invoke-Build -Task compile` runs
  `dotnet build` on the project and copies the assembly to `lib/`, where
  the source manifest finds it; `build` runs it first and places the
  assembly in the package. Importing the source manifest and running the
  tests need it first. CI and the release workflow gain a `Compile` step.
- **The dotnet SDK is a build requirement**, version 8.0 or later. The
  GitHub-hosted runners carry it, so no workflow step installs one.

### Documentation

- **`about_CompleterActions_Migration`** says that an installed 2.x copy on
  `PSModulePath` is autoloaded by a removed name until it is uninstalled,
  and gives the `Uninstall-PSResource` line to run.
- `about_CompleterActions_Migration` is rewritten for 2.x to 3.0: the
  removed names with their replacements, the public types with the eight
  differences, the engine floor, the grammar at registration and import
  with what a profile sees, a checklist for a profile, and a shortened
  `MOVING FROM 1.x` section. The topic keeps its name.
- `about_Completer_Sets` and `about_Import_Completers` describe the grammar
  check at registration and import next to the first-tab check, and
  `about_Completer_Sets` states why an entry whose `Hash` matches is not
  walked again.
- `Register-Completer` and `Import-CompleterSet` help mention the grammar
  at registration and import. README gains a Types paragraph and describes
  the assembly, `lib/`, and the `compile` task;
  `.github/copilot-instructions.md` points at the C# project; the module
  page names the public types; and the `Measure-CompleterStartup.ps1` help
  says that a 3.x baseline comes from `Save-PSResource` or a rebuilt tag,
  because `git archive` yields an importable package only for 2.x tags.

## [2.2.0] - 2026-10-04

The stable 2.2.0 release. Same code as 2.2.0-preview1, promoted after the
preview soaked in a profile and in the PS_Completers conformance CI without a
defect, per roadmap decision 7. The 2.2.0-preview1 section below is the full
record of the milestone: `New-CompleterScript`, `Import-CompleterSet -Name`,
`Test-CompleterSet -Name` with the `PackageLayout` findings, and the third
edition of the author guide.

## [2.2.0-preview1] - 2026-10-03

### Added

- **`New-CompleterScript`.** Writes a native completer script skeleton
  that passes `Test-CompleterScript` as written: a guarded, literal-only
  subcommand table, a `Complete-<Stem>` function that offers it in the
  first argument position, and one bare `Register-ArgumentCompleter` call
  that names every target. Each `-CommandName` is written as given and
  followed by its `.exe` form unless it already ends in `.exe`, `.cmd`,
  `.bat`, `.ps1`, or `.com`. The table is seeded in one of three ways. By
  default the command probes the tool's help: it runs `--help`, and on
  Windows also `/?` once when `--help` ran to completion but gave no
  subcommand and fewer than five non-blank lines, or it runs the one
  argument given with `-HelpArgument`. The probe runs only an
  application, never a function, alias, cmdlet, or PowerShell script,
  and on Windows only a
  `.exe` whose header marks a console program; it runs with no shell,
  standard input closed, the temporary directory as its working
  directory, and `NO_COLOR=1`, under a 5-second limit, and output from a
  run that timed out or left a process holding its output is not used.
  `-HelpText` parses help the author captured, from the pipeline or as an
  argument, and runs nothing; `-NoProbe` writes an empty table. Help is
  decoded, cleaned of terminal escapes and progress lines, and parsed by
  fixed rules for a commands section. Before the file is put in place, a
  temporary copy is checked with the strict grammar and its targets are
  derived as `Register-Completer -Lazy` derives them, so every output
  conforms; a failure writes nothing. The file is UTF-8 without a
  byte-order mark and holds no date, version, or machine path. Supports
  `-Force`, `-PassThru`, `-WhatIf`, and `-Confirm`; `-WhatIf` names the
  program the probe would run. A name with no letter or digit outside its
  suffix, such as `_.exe`, and a `-HelpArgument` with a line break are
  refused before anything runs or is written.
- **`Import-CompleterSet -Name`.** Imports the completer set of an
  installed completer set package: a module whose manifest names its set
  file in `PrivateData.CompleterSet`, in a folder directly below the
  module folder. The module is found as `Import-Module` finds it, without
  loading it or calling `Get-Module -ListAvailable`: the first
  `$env:PSModulePath` root that has the module wins, and within it the
  highest version, with the module folder's name matched
  case-insensitively on every platform. The manifest is read as data, so
  nothing in the package runs. Two rules apply to a package and not to a
  set imported by path: an entry whose script resolves outside the module
  folder is an invalid entry, and a set with trusted entries writes one
  warning that counts them. Names are literal, and every name is resolved
  before any set is imported.
- **`Test-CompleterSet -Name`.** Tests the set of an installed completer
  set package, found exactly as `Import-CompleterSet -Name` finds it.
- **`PackageLayout` findings in `Test-CompleterSet`.** For a set whose
  module manifest is known, through `-Name` or a `.psd1` one folder above
  the set that declares it, as in a staged package: an `Error` for each
  entry whose `Path` is fully qualified or outside the module folder, an
  `Error` for each other `.psd1` beside the manifest, which
  `Publish-PSResource` can take as the manifest, an `Error` when the set
  file's base name equals the module name case-insensitively, which
  PSResourceGet can take as the manifest when it saves or installs the
  package, even from a subfolder, and a `Warning` when
  `RequiredModules` does not require CompleterActions 2.2.0 or later. They
  come after the entry findings and before `UnlistedScript`. A set that no
  manifest declares gets the same findings as in 2.1.0.
- The module now exports fourteen functions and the same three aliases.

### Documentation

- The third edition of `about_Import_Completers` and
  `about_Completer_Sets`. `about_Import_Completers` gains a section on
  scaffolding a completer with `New-CompleterScript`: the three ways to
  seed the table, what the probe runs and refuses to run, its limit and
  working directory, the parsing rules with examples that work and one
  that does not, the residual risks, and the skeleton read against the
  three shapes. Its workflow starts from `New-CompleterScript` and ends
  with `Export-CompleterSet` and `Test-CompleterSet`, and a new paragraph
  points to the package layout. `about_Completer_Sets` gains full sections
  on the hash and the fast path, on checking for drift with
  `Test-CompleterSet`, with every finding kind, its severity, and its fix,
  and on completer sets as modules: the package layout and manifest,
  including the rule that the set file's base name differs from the module
  name, `New-ModuleManifest`, `Import-CompleterSet -Name` and its two package
  rules, what installing a package means for trust, `Test-CompleterSet
  -Name`, and staging before `Publish-PSResource`.
- Command help for `New-CompleterScript`, and the `Name` parameter sets of
  `Import-CompleterSet` and `Test-CompleterSet`. README and
  `.github/copilot-instructions.md` list the new command.

## [2.1.0] - 2026-10-02

The stable 2.1.0 release. Same code as 2.1.0-preview1, promoted after the
preview soaked in a profile and in the PS_Completers conformance CI without a
defect, per roadmap decision 7. The 2.1.0-preview1 section below is the full
record of the milestone: the set-file `Hash`, the bulk registration path,
`Reset-Completer`, `Test-CompleterSet`, and the startup benchmark.

## [2.1.0-preview1] - 2026-09-29

### Added

- **`Reset-Completer`.** Returns a `Failed` or `Active` script-backed
  completer to `Pending`, so its script loads again on the next tab press,
  without re-importing the set. A script-backed completer is any managed
  record with a `ScriptPath`: a lazy one from `Import-CompleterSet` or
  `Register-Completer -Lazy`, or an eager one from
  `Import-CompleterScript | Register-Completer`. Targets are named exactly as
  for `Unregister-Completer`: `-CommandName` with `-Native` or
  `-ParameterName`, or records piped from `Get-Completer`,
  `Register-Completer -PassThru`, or `Import-CompleterSet`, under the 2.0
  target contract. There is no `-AllowUnmanaged`, because a reset never
  touches a registration the module does not manage. A `Pending` target is
  left as it is and `-PassThru` still returns it. A target with no managed
  record, a `Stale` one, a `Failed` one whose live value was created outside
  the module, one registered from a script block, or one whose script no
  longer exists is written as a non-terminating error, `Failed to reset the
  completer '<RuntimeKey>'. <reason>`, and the call goes on with the next
  target, so `Get-Completer -State Failed | Reset-Completer` resets every
  record it can. That is the difference from `Unregister-Completer`, which
  removes the registration and stops at the first record it cannot remove;
  `-ErrorAction Stop` restores stop-on-first-error. Each target is its own
  transaction, and a failed write restores the previous runtime value and
  managed record. Only the named targets are reset; the script is not
  parsed. Supports `-WhatIf`, `-Confirm`, and `-PassThru`.
- **`Test-CompleterSet`.** Reports drift between a completer set file and
  the scripts on disk as `CompleterActions.CompleterScriptFinding` records,
  each positioned at a line and column of the set file. The `Error` kinds,
  `MissingScript`, `InvalidEntry`, `UnreadableTargets`, `TargetMismatch`,
  and `DuplicateTarget`, are the problems that would make
  `Import-CompleterSet` reject the set, with its text; the `Warning` kinds,
  `HashMismatch`, `MissingHash`, `InvalidHash`, and `UnlistedScript`, mark a
  set that still imports but is stale or slower. Every strict entry is
  parsed, trusted entries never are, no script runs, and the session's
  registrations are neither read nor changed. A set that matches its folder
  returns nothing, with no warning or error and `$?` true, so a CI gate can
  assert an empty result. `-Filter` sets the pattern of the recursive scan
  for unlisted scripts, `*_completer.ps1` by default. With the two new
  commands the module exports thirteen functions and the same three
  aliases.
- **Per-entry `Hash` in the completer set schema.** An optional key,
  `SHA256:` followed by 64 hexadecimal digits, computed over the script's
  decoded text with its line endings normalised to LF, so a Windows and a
  Linux checkout of the same script hash alike. `Export-CompleterSet`
  writes it on every entry, strict and trusted, between `Trusted` and
  `Targets`. It is a cache key for a strict entry's targets, not a
  signature, and it does not change the trust tier. The set `Version`
  stays `1`, and 2.0.0 ignores the key, so a set written by this version
  still imports on 2.0.0. A `Hash` in any other form is treated as absent
  at import and reported by `Test-CompleterSet` as `InvalidHash`.

### Changed

- **`Import-CompleterSet` skips the parse for a matching `Hash`.** A strict
  entry that declares `Targets` and whose `Hash` matches its script is
  registered from those `Targets` without parsing the script; every check
  that needs only the set still runs. Every other entry takes the 2.0.0
  path, so a set without `Hash` imports exactly as before, with the same
  validation, records, errors, and warnings. A stale `Hash` is not a
  warning: `-Verbose` writes one line per entry saying how its targets were
  read and one summary line per set, and `Test-CompleterSet` reports it.
  The strict grammar still runs on the first tab press, so a wrong `Hash`
  can at worst leave a `Failed` record, never run an unchecked script.
- **A completer set is written as one batch.** `Import-CompleterSet`
  reads the state of every target in the set in one pass and writes all
  runtime values, then all managed records, against the set's one snapshot
  of the session. The rollback is unchanged: if any write fails,
  every change the set made is undone, including the runtime values of
  entries after the one that failed, and the error text is 2.0.0's.
  `Register-Completer` keeps its per-target transaction.
- **`Export-CompleterSet` writes script order and hashes trusted scripts.**
  A strict entry's `Targets` are written in the order its script registers
  them, with the script's casing, instead of in record order; the keys are
  the same. Trusted entries keep record order. A trusted script is now read
  once, for its `Hash` only; when it is missing or cannot be read, the
  entry is written without `Hash`, the export still succeeds, and one
  warning names it: `The script '<path>' could not be read, so its entry
  was written without a Hash. <reason>`.
- **`Register-Completer` help.** The example that retries failed lazy
  loads now uses `Get-Completer -State Failed | Reset-Completer`.
- **Performance.** Startup benchmark over the 173-script set, ten samples
  each, four runs: 2.0.0 lazy median 1589 to 1676 ms, 2.1.0 lazy median 815
  to 886 ms, ratio 0.49 to 0.54 against the 0.50 target; an unhashed set
  1362 to 1428 ms, 0.83 to 0.90 of 2.0.0. The 0.50 target sits inside the
  run-to-run spread rather than below it, so the roadmap's exit criterion is
  restated to the measured range with the owner's sign-off. The unhashed set
  is faster than 2.0.0 because the bulk registration path applies to it too.
  The runs used 366 targets on pwsh 7.6.6 and Windows 10.0.26200.
  `tools/Measure-CompleterStartup.ps1` took the measurement in its second
  edition: the `Lazy` leg imports a set exported with `Hash`, a `LazyNoHash`
  leg imports a copy with every `Hash` line removed, the new
  `-BaselineModulePath` adds a `Baseline` leg that imports that copy with
  another package such as 2.0.0, the legs are sampled interleaved,
  `-Iterations` defaults to 10, every row gains `RatioToBaseline`, and the
  tool takes no sample unless the exported set carries one `Hash` per entry.

## [2.0.0] - 2026-09-23

The stable 2.0.0 release. Same code as 2.0.0-rc1, promoted after the candidate
soaked in a profile and in the PS_Completers conformance CI without a defect,
per roadmap decision 6. The 2.0.0-rc1 section below is the full record of the
breaking surface; `about_CompleterActions_Migration` walks through the move
from 1.x.

## [2.0.0-rc1] - 2026-09-21

The 2.0.0 breaking surface. Every incompatible change of the 2.x line lands
here at once, with aliases for the old names, so there is one migration to
make; `about_CompleterActions_Migration` walks through it with before and
after samples.

### Changed

- **Renamed commands** (breaking). The three commands with the
  `CompleterRegistration` noun are renamed; the old names stay as exported
  aliases until 3.0.

  | 1.x | 2.0 |
  | --- | --- |
  | `Get-CompleterRegistration` | `Get-Completer` |
  | `Register-CompleterRegistration` | `Register-Completer` |
  | `Unregister-CompleterRegistration` | `Unregister-Completer` |

  Each alias points at an exported legacy wrapper
  (`Get-CompleterRegistrationLegacy`, `Register-CompleterRegistrationLegacy`,
  `Unregister-CompleterRegistrationLegacy`) that forwards every parameter,
  pipeline input, `-WhatIf`, and `-Confirm` to the new command and shows the
  new command's help. The wrappers are exported because an exported alias
  whose target function is not exported fails at the call site, so
  `Get-Command -Module CompleterActions` lists eleven functions and three
  aliases. The first call to each old name in a process writes one warning,
  `<old name> is deprecated and will be removed in 3.0; use <new name>
  instead. See about_CompleterActions_Migration.`; later calls are silent.
- **Explicit target contract** (breaking). Keys are output-only identifiers.
  The typed `-Key` parameter is removed from `Get-Completer`,
  `Unregister-Completer`, and `Test-CompleterRegistration`, and the
  inference that read a key's shape (no colon for a native command,
  `Command:Parameter` for a parameter completer, a path separator after the
  last colon for a native command path) is deleted together with its helper.
  A target is named with `-CommandName` plus `-Native` or `-ParameterName`,
  or described by an input object that carries `CommandName` with
  `Native`/`IsNative` or `ParameterName`, or a `Key`, `RegistrationKey`, or
  `RuntimeKey` together with `IsNative`/`Native`. A bare key input object
  fails with `InputObject supplies the key '<key>' without an IsNative or
  Native property ... See about_CompleterActions_Migration.` Records piped
  back from `Get-Completer`, `Register-Completer -PassThru`,
  `Import-CompleterScript`, `Import-CompleterSet`, and
  `Test-CompleterRegistration` always carry `IsNative` and still round-trip;
  `Get-Completer` gained an `InputObject` parameter set for them, matching
  `Unregister-Completer` and `Test-CompleterRegistration`.
  `Unregister-Completer`'s default parameter set is `CommandParameter`, so a
  call without arguments reports the missing `CommandName` and
  `ParameterName`. Completer set files never carried keys, so a set exported
  by 2.0.0-preview3 imports unchanged.

  ```powershell
  # 1.x
  Get-CompleterRegistration -Key 'git:checkout', 'git:branch'
  Unregister-CompleterRegistration -Key 'git'
  # 2.0
  Get-Completer -CommandName git -ParameterName checkout, branch
  Unregister-Completer -CommandName git -Native
  ```

- **One `-State` filter** (breaking). `-ManagedOnly` and `-DiscoveredOnly`
  are removed from `Get-Completer` and replaced by `-State`, a
  `CompleterState[]` accepting `Active`, `Stale`, `Conflicted`, `Pending`,
  `Failed`, and `Discovered` with tab completion; a scalar binds, several
  values return the union, and no `-State` returns everything. The legacy
  `Get-CompleterRegistration` alias keeps both switches and translates
  `-ManagedOnly` to `-State Active, Pending, Failed, Stale` and
  `-DiscoveredOnly` to `-State Discovered, Conflicted`; it rejects either
  switch combined with `-State`. `Export-CompleterSet` uses the same managed
  state list internally.
- **A runtime-only registration now reports `State` `Discovered`, not
  `Active`** (breaking). `Active` is reserved for managed records whose
  stored script is the live runtime value; a live value that no managed
  record describes is `Discovered`. A filter such as
  `Where-Object State -eq Active` that relied on runtime-only registrations
  being `Active` now returns managed records only; use
  `-State Active, Discovered` for the old meaning. `Source`, `IsManaged`, and
  `IsRuntimeRegistered` are unchanged. `Unregister-Completer -PassThru
  -AllowUnmanaged` returns the removed runtime-only record as `Discovered`.
- **A replaced target yields two records** (breaking). `Get-Completer`
  computes every candidate's state once and `-State` selects among them, so
  a managed target that was replaced outside the module returns both its
  `Stale` managed record and the `Conflicted` live value from an unfiltered
  call (1.x returned only the `Conflicted` record unless `-ManagedOnly`
  revealed the `Stale` one). The same holds for a `Failed` managed record
  whose target was re-registered externally. `Key` is unique in the output
  except for such replaced targets.
- **Promised sort order.** `Get-Completer` sorts by `CompleterType` (native
  first), `CommandName`, and `ParameterName` before `-Skip` and `-First` are
  applied, so paging across several calls neither skips nor duplicates a
  record while unrelated targets change between pages; only a target that
  sorts before the current window can shift it. 1.x returned insertion
  order.
- **Typed output** (breaking). Registration, import, finding, and
  completion-match records are PowerShell classes (`CompleterRegistration`,
  `ImportedCompleterRegistration`, `CompleterScriptFinding`,
  `CompletionMatch`) backed by the `CompleterState` and `CompleterType`
  enums, and every command declares its record type in `OutputType`. A class
  cannot carry a dotted name, so each keeps a bare class name and inserts the
  existing dotted `PSTypeName` (`CompleterActions.CompleterRegistration` and
  so on) at the front of its `PSTypeNames` in the constructor; the dotted
  name remains the contract for format views and type checks, and the
  classes are private to the module's session state, so `-is
  [CompleterRegistration]` only resolves inside the module. Property names
  and order are unchanged, except that `CompletionMatch` gained `IsNative`
  after `ParameterName` so a native match resolves as a target when it is
  piped back. `State` and `CompleterType` are enum values that
  still compare equal to their names (`-eq 'Failed'`, `-in Pending, Failed`).
  String properties that were `$null` on the 1.x records are `''` on the
  class records: `ParameterName` on a native record, `ScriptPath` and
  `LoadError` on a record without a script, and `ToolTip` on a completion
  match; a `-eq $null` test no longer matches. `State` and `CompleterType`
  serialize as integers through `ConvertTo-Json` and `Export-Clixml`, where
  1.x wrote the name strings; pass `-EnumsAsStrings` or store
  `[string] $_.State` when persisting records (`ConvertTo-Csv` and the format
  views still write the names). Across a remoting or job
  boundary the records arrive as
  `Deserialized.CompleterActions.CompleterRegistration` with `State` as a
  plain string, as in 1.x.
- The `InputObject` parameter of `Get-Completer`, `Register-Completer`,
  `Unregister-Completer`, `Test-CompleterRegistration`, and
  `Export-CompleterSet` is typed `[object[]]` instead of `[psobject[]]`, so a
  piped class record binds by value instead of falling through to
  property-name binding. Because every piped object binds there,
  `Get-Completer` no longer declares property-name binding on `-CommandName`,
  `-ParameterName`, and `-Native`; an input object describes one target, and
  one whose `CommandName` or `ParameterName` holds several values is rejected
  with an error instead of being joined into one name (pass arrays to
  `-CommandName` and `-ParameterName` for several targets).
- The source module loads `src\Classes` before `src\Private` and
  `src\Public`, as one script block, and the packaged module defines the
  classes before the first function.

### Documentation

- New `about_CompleterActions_Migration` topic: the rename table and alias
  mechanics, the explicit target contract, the `-State` consolidation with
  the `Discovered` change, the sort order, the typed records with the
  class-versus-`PSTypeName` note and the deserialization caveat, and a
  checklist for a profile. The deprecation warning and the bare-key error
  name it.
- README, `about_Import_Completers`, `about_Completer_Sets`, the command help,
  and `.github/copilot-instructions.md` use the new names and `-State`.

## [2.0.0-preview3] - 2026-09-12

Fixes for the five findings in `docs/code-review-2026-09-12.md`.

### Fixed

- The strict import grammar rejects a scope-qualified definition of an
  allow-listed command. `function script:Get-Variable`, and the `local:`,
  `global:`, `private:`, and module-qualified forms, passed validation because
  the definition's name kept its qualifier, and the body ran at import time
  when the allow-listed `Get-Variable` call executed. Definitions are now
  compared by their unqualified name; command calls stay exact-match, so a
  qualified call is still rejected as an unsupported top-level command (R1).
- Imported completer blocks keep their source file. The capture module rebuilt
  each block from its text, which dropped the file association, so
  `$PSScriptRoot` and `$PSCommandPath` were empty inside an imported completer
  and a location-dependent completer failed once registered. The original
  block is now rebound to the capture module, under the strict, trusted, and
  lazy paths alike (R2).
- A completer registered with `Register-ArgumentCompleter -ParameterName`
  alone, without `-CommandName`, no longer makes `Get-CompleterRegistration`
  throw for the whole session. The engine stores that shape under the bare
  parameter name; discovery skips it with a verbose message, key lookups never
  match it, and the registration snapshot leaves it out, so it is never
  resolved as a native target of the same name (R3).
- A lazily loaded script that registers the same target more than once now
  loads the last definition, as `Register-ArgumentCompleter` does when the
  script is dot-sourced; the first definition used to win on the first press
  and stay in place (R4).
- `Export-CompleterSet` refuses a strict entry that lists only some of the
  targets its script registers, naming the missing targets and writing
  nothing, because `Import-CompleterSet` compares a strict entry's `Targets`
  with the parsed script and rejects the mismatch. Trusted entries are written
  with the targets the records carry (R5).

### Documentation

- `about_Import_Completers` names scope-qualified shadows of allow-listed
  commands as findings and states that imported blocks keep `$PSScriptRoot`
  and `$PSCommandPath`; `about_Completer_Sets` covers last-wins lazy loading
  and the strict-entry export rule; `Get-CompleterRegistration` help and the
  README describe how parameter-only registrations are skipped.
- `.github/copilot-instructions.md` lists the eight public commands, lazy
  registration with the `Pending` and `Failed` states, completer sets, and the
  own-process rule for running the tests.

## [2.0.0-preview2] - 2026-09-11

### Fixed

- Completer set files are portable across platforms. `Export-CompleterSet`
  writes relative paths with forward slashes, and `Import-CompleterSet`
  accepts either separator, so a set exported on Windows imports on Linux
  and macOS instead of failing every entry with a missing file.

## [2.0.0-preview1] - 2026-09-11

### Added

- Lazy registration. `Register-CompleterRegistration -Path` or `-LiteralPath`
  with `-Lazy` registers a completer script without running it: the runtime
  entry for each target is a stub that imports the script through
  `Import-CompleterScript` on the first tab press, replaces itself with the
  real completer, and delegates that first call to it. Under the default strict
  tier the targets are read from the script's literal
  `Register-ArgumentCompleter` arguments, so the file is parsed but never
  executed at registration time; `-Trusted` selects the trusted tier for the
  load and requires the targets to be named with `-CommandName` and `-Native`
  or `-ParameterName`. A script that registers several targets is executed once
  and every Pending sibling is swapped from the same import.
- `Pending` and `Failed` registration states. A lazy record reports `Pending`
  until its script loads and `Active` afterwards. If the load fails, the tab
  press returns no completions, the runtime entry is removed so the completion
  engine's default completion applies exactly as with no completer registered,
  and the record moves to `Failed` with the message in `LoadError`; nothing is
  written to the host. `Register-CompleterRegistration -Force` retries the
  load. `Get-CompleterRegistration` returns both states by default and with
  `-ManagedOnly`; `Unregister-CompleterRegistration` removes a Pending stub with
  its record and a Failed record on its own.
- `ScriptPath`, `Trusted`, and `LoadError` properties on
  `CompleterActions.CompleterRegistration` records. Registrations made from
  `Import-CompleterScript` records carry the script's path and tier too, so an
  eager session exposes the same file information as a lazy one.
- Lazy loading never hooks PSReadLine key handlers, replaces `TabExpansion2`,
  or changes PSReadLine options; the tests snapshot
  `Get-PSReadLineKeyHandler` around registration, first tab, and removal.
- `Import-CompleterSet`. Reads a completer set, a `.psd1` data file that lists
  completer scripts with a per-entry trust tier and their targets, through
  `Import-PowerShellDataFile` so the set itself can never run code. Every
  entry is validated before anything registers: the file exists and is a
  `.ps1`, `Trusted` entries declare their `Targets`, strict entries expose
  literal targets that are derived from the parsed script and compared
  against any the entry declares, no target is listed by two entries, and
  without `-Force` no target already carries a managed or runtime
  registration for a different completer, the same rules
  `Register-CompleterRegistration` applies. One terminating error lists every
  problem;
  `-SkipInvalid` writes them as warnings and registers the valid entries.
  Paths that are not fully qualified, drive-relative ones included, resolve
  against the set file's directory, `-Force` passes through to the
  registration, and the command returns the registration records.
- `Export-CompleterSet`. Writes a completer set from registration records
  piped from `Get-CompleterRegistration` or `Import-CompleterScript`, or from
  every managed registration that records a `ScriptPath`, one entry per
  script with its `Trusted` flag and targets, and script paths relative to the
  set file when they share a root.
- `tools/Measure-CompleterStartup.ps1`. Startup benchmark that times the eager
  `Get-ChildItem | Import-CompleterScript | Register-CompleterRegistration`
  pipeline against `Import-CompleterSet` of a set exported from the same
  scripts, each sample in a fresh `pwsh -NoProfile` process, and reports the
  median, minimum, maximum, and ratio per leg. On the 169-script, 355-target
  repository with five samples per leg: eager median 7063.3 ms, lazy median
  1315.5 ms, ratio 0.19, under the roadmap target of 0.25; against the
  highest eager median recorded on this machine, 7427.7 ms, the same lazy
  figure is 0.18. The remaining lazy cost is one parse per strict script,
  about a third of the leg, plus record creation and the runtime and managed
  writes.

### Changed

- The default table view for registration records adds `ScriptPath` and
  `LoadError` columns after `State`.
- `Import-CompleterScript` runs its strict conformance gate through
  `Assert-CompleterScriptConformance`. A lazily registered strict script goes
  through that gate when it loads rather than at registration, so
  `Register-CompleterRegistration -Lazy` and `Import-CompleterSet` each cost
  one parse per strict script with no conformance walk; a script that fails
  the grammar moves to `Failed` on its first tab press with the findings in
  `LoadError`.
- `Import-CompleterSet` registers each entry from the targets its validation
  derived instead of calling `Register-CompleterRegistration -Lazy`, which
  parsed every strict script a second time. Both paths write registrations
  through one shared transactional helper, so conflict rules, record shapes,
  and rollback are unchanged. On the 169-script repository the lazy startup
  median dropped from 2566.2 ms to 1806.1 ms.
- `Import-CompleterSet` registers a set as one batch. Validation and
  registration share one snapshot of the managed table and the runtime
  completer dictionaries, each entry's targets are reconciled in one pass
  against that snapshot instead of once per target during validation and
  again during registration, and the whole set is written through one call
  that rolls back every runtime and managed change of the set, replaced
  registrations included, if any write fails. `Register-CompleterRegistration`
  resolves conflicts and writes through the same helpers one target at a time,
  so each target of a call is still its own transaction: a failed write or a
  conflict on a later target leaves the earlier targets of that call
  registered, and a target repeated within one call is resolved against what
  the earlier occurrence wrote, exactly as before. On the 169-script
  repository the lazy startup median dropped from 1806.1 ms to 1315.5 ms.
- `Find-RuntimeCompleterRegistration -Key` compares the stored dictionary
  keys directly instead of normalizing every key on each lookup, which removed
  a quadratic cost from registering many targets: the eager 169-script import
  dropped from about 9.0 s to 6.6 s per fresh `pwsh -NoProfile` session.

### Documentation

- `about_Completer_Sets` describes the set file schema, the trust tier per
  entry, up-front validation, the `Pending` and `Failed` lifecycle of lazily
  loaded completers, and the PSReadLine neutrality promise.
- README command map, examples, and architecture notes cover the two set
  commands, and a lazy-loading section explains the set format and lifecycle.

## [1.4.0] - 2026-09-10

### Added

- `Test-CompleterScript`. Runs the strict import grammar over completer scripts
  without executing them and returns one
  `CompleterActions.CompleterScriptFinding` per unsupported construct, with
  `Path`, `Line`, `Column`, `Severity`, `Construct`, `Message`, and a `Hint`
  that says how to fix it. A conforming script produces no output, so
  `Get-ChildItem | Test-CompleterScript` doubles as a conformance test for a
  completer repository.
- `Test-CompleterRegistration`. Runs `TabExpansion2` for an `-InputText`
  against a registered target and returns `CompleterActions.CompletionMatch`
  records carrying `CompletionText`, `ListItemText`, `ResultType`, and
  `ToolTip`, so completion behaviour can be asserted on instead of checked by
  hand. Targets follow the `Get-CompleterRegistration` contract, including
  piped registration records, and exactly one target must resolve per call
  because one input text invokes one completer; `-CursorPosition` defaults to
  the end of the input. The command never touches PSReadLine.
- `Import-CompleterScript -Trusted`. Skips the grammar and dot-sources the
  script as-is inside the same capture module, for completer repositories you
  own. Strict stays the default. Imported records carry a `Trusted` property
  that records the tier.
- Default views for findings (a list grouped by script path) and completion
  matches (a table grouped by target key).

### Changed

- `Import-CompleterScript` reports every strict-grammar finding, each with its
  line, column, construct, and hint, instead of the first one only. The error
  text is built from the same findings `Test-CompleterScript` returns, so the
  two cannot drift.
- A single-element `@('name')` array expression is accepted for `-CommandName`
  and `-ParameterName`; the previous shape check rejected it.

### Documentation

- `about_Import_Completers` rewritten around the two tiers, with the three
  import-safe shapes as worked examples, `Test-CompleterScript` as the
  conformance step, and `Test-CompleterRegistration` as the verification step.
- README command map, examples, and architecture notes cover the two new
  commands and the trusted switch.

## [1.3.0] - 2026-09-09

### Added

- Capability probe at import. `Assert-CompleterRuntimeCapability` resolves every
  reflected engine member once and throws a single terminating error naming the
  running PowerShell version and the members that could not be resolved, instead
  of failing deep inside a later `Get` or `Register` call.
- Import bootstrap in the packaged module. The built `.psm1` contained function
  definitions only, so installed copies never ran the `Get-CompleterActionState`
  initialization; the import-time work now lives in `src/Bootstrap.ps1` and the
  build appends it to the package.
- Continuous integration on `windows-latest` and `ubuntu-latest` across
  PowerShell 7.4 LTS, 7.5, 7.6, and preview, running the build, the analyzer, and
  the Pester suite on each leg.
- Tag-triggered release workflow. A pushed `v` tag runs `release_check`, the
  build, and the tests, publishes to the PowerShell Gallery using the
  `GALLERY_API_KEY` repository secret, and creates the GitHub release with the
  matching section of this file as its notes.
- This changelog.

### Fixed

- The build copied the generated MAML help under a lowercase file name that only
  resolves on a case-insensitive filesystem, so `Invoke-Build -Task build` failed
  on Linux. Only the source path casing changed; the packaged help file name is
  unchanged.

### Documentation

- 2.0 roadmap in `docs/roadmap-2.0.md`, covering four milestones from the 1.2.0
  baseline and the design decisions locked on 2026-09-08.
- README gains a CI badge and a `Releasing` section describing the tag-triggered
  flow.

## [1.2.0] - 2026-09-09

Hardening release covering the findings in `docs/code-review-2026-09-08.md`.

### Security

- Completer script validation rejects executable top-level constructs and
  `#requires -Modules` / `-Assembly`, so importing a script can no longer load
  types or run code as a side effect of validation (CA-001).

### Added

- The packaged `build/` output is tracked, and a test fails when it drifts from
  the sources it was generated from.

### Fixed

- Registration updates each target transactionally and restores the previous
  runtime and managed state when a write fails (CA-002).
- Managed records reconcile against the live runtime, so an externally replaced
  registration reports `Stale` or `Conflicted` instead of being silently
  preferred or removed (CA-003).
- Drive-qualified path keys classify as native completer targets, and the dead
  drive-letter regex was removed from key classification (CA-004).
- The build derives the module name and every constructed path portably and
  enumerates only source folders that exist (CA-005).
- The manifest tests no longer invoke the build, so a full Pester run leaves the
  working tree unchanged (CA-007).
- The hard-coded manifest version assertion is replaced by a release-policy test
  comparing the source manifest, the built manifest, and the highest local tag
  (CA-008).

### Documentation

- Key-shape help aligned with the last-colon separator rule.
- Added the code review document `docs/code-review-2026-09-08.md`.

## [1.1.2] - 2026-05-04

### Added

- Module icon assets under `src/Assets/` and an `IconUri` in the manifest, which
  the build now propagates into the packaged manifest.

### Changed

- README rewritten with a badge row and a tighter layout.
- Corrected the LICENSE text.
- `Publish_build` no longer imports SecretManagement and PSResourceGet
  explicitly.

## [1.1.1] - 2026-04-28

### Changed

- Expanded the manifest `Description` from `Interacts with PowerShell completers`
  to the two-sentence description the module ships today.
- `Publish_build` reads the gallery key from `$env:GalleryAPI` instead of
  prompting to unlock a SecretStore vault.

Version 1.1.0 (commit
[`05ebec3`](https://github.com/tstager/CompleterActions/commit/05ebec3)) is the
baseline for this file; earlier history is not documented.

[Unreleased]: https://github.com/tstager/CompleterActions/compare/v3.0.1-preview1...HEAD
[3.0.1-preview1]: https://github.com/tstager/CompleterActions/compare/v3.0.0...v3.0.1-preview1
[3.0.0]: https://github.com/tstager/CompleterActions/compare/v2.2.0...v3.0.0
[3.0.0-rc1]: https://github.com/tstager/CompleterActions/compare/v2.2.0...v3.0.0-rc1
[2.2.0]: https://github.com/tstager/CompleterActions/compare/v2.1.0...v2.2.0
[2.2.0-preview1]: https://github.com/tstager/CompleterActions/compare/v2.1.0...v2.2.0-preview1
[2.1.0]: https://github.com/tstager/CompleterActions/compare/v2.0.0...v2.1.0
[2.1.0-preview1]: https://github.com/tstager/CompleterActions/compare/v2.0.0...v2.1.0-preview1
[2.0.0]: https://github.com/tstager/CompleterActions/compare/v2.0.0-rc1...v2.0.0
[2.0.0-rc1]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview3...v2.0.0-rc1
[2.0.0-preview3]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview2...v2.0.0-preview3
[2.0.0-preview2]: https://github.com/tstager/CompleterActions/compare/v2.0.0-preview1...v2.0.0-preview2
[2.0.0-preview1]: https://github.com/tstager/CompleterActions/compare/v1.4.0...v2.0.0-preview1
[1.4.0]: https://github.com/tstager/CompleterActions/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/tstager/CompleterActions/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/tstager/CompleterActions/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/tstager/CompleterActions/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/tstager/CompleterActions/compare/05ebec3...v1.1.1
