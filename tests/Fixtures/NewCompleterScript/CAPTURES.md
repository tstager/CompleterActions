# Help captures for the New-CompleterScript parser fixtures

Each `<tool>.txt` is the decoded, uncleaned help text of one real tool, exactly what `New-CompleterScript -HelpText` would receive. Each `<tool>.names.txt` holds the names the section 2 parsing rules give for that text, one per line in help order, written by hand from reading the capture before the parser was run on it. The `.names.txt` files are the assertion; the section 2 counts are a cross-check.

## How the captures were made

Captured on 2026-10-03 on the owner's machine (Windows 11, `Microsoft Windows [Version 10.0.26300.9550]`, PowerShell 7.6.6), from the branch build of CompleterActions imported by full path in `pwsh -NoProfile`.

For every tool except `winget`, a scratch script outside the repository ran, in module scope:

```powershell
$app = Resolve-CompleterHelpProbeApplication -Name <tool>
$run = Invoke-CompleterHelpProcess -FilePath $app.Path -ArgumentList @(<argument>) -TimeoutSeconds $script:CompleterHelpProbeTimeoutSeconds
$text = ConvertFrom-CompleterHelpOutput -Bytes $run.StandardOutput
if ([string]::IsNullOrWhiteSpace($text)) { $text = ConvertFrom-CompleterHelpOutput -Bytes $run.StandardError }
Set-Content -LiteralPath <tool>.txt -Value $text -Encoding utf8
```

Every run ended with `Status` `Exited`. The text was not cleaned before it was written.

`winget` resolves to an app execution alias, which the probe refuses, so it was captured in the fixture folder with:

```powershell
winget --help | Set-Content -Encoding utf8 .\winget.txt
```

## Captures

| Tool | Version | Capture command | Stream, exit code | Date | Expected | Section 2 | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cargo` | `cargo 1.98.1 (797e8a9bc 2026-08-05)` | `C:\Users\Trent\.cargo\bin\cargo.exe --help` | stdout, 0 | 2026-10-03 | 16 | 16 | |
| `docker` | `Docker version 29.8.1, build 4a63305` | `C:\Program Files\Docker\Docker\resources\bin\docker.exe --help` | stdout, 0 | 2026-10-03 | 65 | 65 | |
| `gh` | `gh version 2.102.0 (2026-09-30)` | `C:\Program Files\GitHub CLI\gh.exe --help` | stdout, 0 | 2026-10-03 | 34 | 34 | |
| `go` | `go version go1.27.0 windows/amd64` | `C:\Program Files\Go\bin\go.exe --help` | stderr, 2 | 2026-10-03 | 19 | 19 | |
| `7z` | `7-Zip 26.03 (x64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-09-03` | `C:\Users\Trent\scoop\shims\7z.exe --help` | stdout, 0 | 2026-10-03 | 11 | 11 | |
| `sc` | `Microsoft Windows [Version 10.0.26300.9550]` | `C:\WINDOWS\system32\sc.exe --help` | stdout, 1639 | 2026-10-03 | 35 | 35 | `qmanagedaccount-Queries` has a one-dash separator, so it is not an entry, as section 2 says. `boot`, `Lock`, and `QueryLock` follow `The following commands don't require a service name:`, which is not a header because of its apostrophe. |
| `bcdedit` | `Microsoft Windows [Version 10.0.26300.9550]` | `C:\WINDOWS\system32\bcdedit.exe /?` | stdout, 0 | 2026-10-03 | 20 | 20 | `/copy`, `/create`, `/delete`, `/mirror`, `/bootems`, `/ems`, and `/emssettings` sit under headers of eight and ten words, which are not headers. |
| `rustup` | `rustup 1.29.1 (d95a37b6a 2026-08-13)` | `C:\Users\Trent\.cargo\bin\rustup.exe --help` | stdout, 0 | 2026-10-03 | 17 | 17 | |
| `pip` | `pip 26.2.1 from C:\Users\Trent\AppData\Local\Programs\Python\Python314\Lib\site-packages\pip (python 3.14)` | `C:\Users\Trent\AppData\Local\Programs\Python\Python314\Scripts\pip.exe --help` | stdout, 0 | 2026-10-03 | 18 | 18 | |
| `kubectl` | `Client Version: v1.36.1` (`kubectl version --client`) | `C:\Program Files\Docker\Docker\resources\bin\kubectl.exe --help` | stdout, 0 | 2026-10-03 | 43 | 43 | |
| `winget` | `v1.30.140-preview` | `winget --help \| Set-Content -Encoding utf8 .\winget.txt` | pipeline | 2026-10-03 | 19 | 19 | |
| `git` | `git version 2.55.0.windows.5` | `C:\Program Files\Git\cmd\git.exe --help` | stdout, 0 | 2026-10-03 | 0 | 0 | |
| `rg` | `ripgrep 15.2.0 (rev e89fff89ac)` | `C:\Users\Trent\AppData\Local\Microsoft\WinGet\Links\rg.exe --help` | stdout, 0 | 2026-10-03 | 0 | 0 | Line 781, `example, in the command`, has the shape of a section header. The next non-blank line, `rg --one-file-system /foo/bar /quux/baz`, is not an entry, so the section ends before it has an entry and yields no name. |
| `schtasks` | `Microsoft Windows [Version 10.0.26300.9550]` | `C:\WINDOWS\system32\schtasks.exe /?` | stdout, 0 | 2026-10-03 | 0 | 0 | |

`sc`, `bcdedit`, and `schtasks` have no version switch; the Windows version line stands in for theirs.

## Result

Every expected list equals the parser's output on its capture, name for name and in order, and every count equals the section 2 table. No difference needed a version note.

Second reader: the WP2 corpus review checked every expected list against its capture with an independent implementation of the section 2 rules, run on the 14 raw captures. It matched every `<tool>.names.txt` name for name and in order: `7z` 11, `bcdedit` 20, `cargo` 16, `docker` 65, `gh` 34, `go` 19, `kubectl` 43, `pip` 18, `rustup` 17, `sc` 35, `winget` 19, and `git`, `rg`, and `schtasks` 0.
