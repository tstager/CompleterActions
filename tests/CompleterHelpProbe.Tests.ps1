BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ManifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'CompleterActions.psd1'
    $script:PwshPath = Join-Path -Path $PSHOME -ChildPath ($IsWindows ? 'pwsh.exe' : 'pwsh')

    # Writes a minimal PE header: MZ, e_lfanew = 0x80, PE\0\0, an x64 COFF
    # header, and the optional-header magic and Subsystem fields. -Truncate
    # ends the file one byte into the Subsystem field.
    function New-TestPEFile
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only writes a file in TestDrive.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [int] $Subsystem,

            [Parameter()]
            [int] $Magic = 0x20B,

            [Parameter()]
            [switch] $Truncate
        )

        $peOffset = 0x80
        $bytes = [byte[]]::new(512)
        $bytes[0] = 0x4D
        $bytes[1] = 0x5A
        [System.BitConverter]::GetBytes([int] $peOffset).CopyTo($bytes, 0x3C)
        $bytes[$peOffset] = 0x50
        $bytes[$peOffset + 1] = 0x45
        [System.BitConverter]::GetBytes([uint16] 0x8664).CopyTo($bytes, $peOffset + 4)
        [System.BitConverter]::GetBytes([uint16] 0xF0).CopyTo($bytes, $peOffset + 20)
        [System.BitConverter]::GetBytes([uint16] 0x22).CopyTo($bytes, $peOffset + 22)
        [System.BitConverter]::GetBytes([uint16] $Magic).CopyTo($bytes, $peOffset + 24)
        [System.BitConverter]::GetBytes([uint16] $Subsystem).CopyTo($bytes, $peOffset + 92)

        if ($Truncate)
        {
            $bytes = [byte[]] $bytes[0..($peOffset + 92)]
        }

        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }

    # Copies cmd.exe and rewrites the UInt16 Subsystem field at e_lfanew + 92.
    function New-TestPatchedExe
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only writes a file in TestDrive.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [int] $Subsystem
        )

        $bytes = [System.IO.File]::ReadAllBytes($env:ComSpec)
        $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
        [System.BitConverter]::GetBytes([uint16] $Subsystem).CopyTo($bytes, $peOffset + 92)
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }

    function New-TestDirectory
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only creates a folder in TestDrive.')]
        [CmdletBinding()]
        param()

        $path = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $path
        $path
    }

    function Write-TestShellScript
    {
        param(
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string[]] $Line,

            [Parameter()]
            [switch] $Executable
        )

        [System.IO.File]::WriteAllText($Path, (($Line -join "`n") + "`n"))
        if ($Executable)
        {
            & chmod 755 $Path
        }
        else
        {
            & chmod 644 $Path
        }
    }

    function Write-TestFixture
    {
        param(
            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string[]] $Line
        )

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        Set-Content -LiteralPath $path -Value $Line -Encoding utf8
        $path
    }

    function Invoke-TestHelpProcess
    {
        param(
            [Parameter(Mandatory)]
            [string] $FilePath,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]] $ArgumentList = @(),

            [Parameter(Mandatory)]
            [double] $TimeoutSeconds
        )

        InModuleScope -ModuleName 'CompleterActions' -Parameters @{ FilePath = $FilePath; ArgumentList = $ArgumentList; TimeoutSeconds = $TimeoutSeconds } -ScriptBlock {
            param($FilePath, $ArgumentList, $TimeoutSeconds)

            Invoke-CompleterHelpProcess -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds
        }
    }

    function Invoke-TestPwshFixture
    {
        param(
            [Parameter(Mandatory)]
            [string] $FixturePath,

            [Parameter(Mandatory)]
            [double] $TimeoutSeconds
        )

        Invoke-TestHelpProcess -FilePath $script:PwshPath -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $FixturePath) -TimeoutSeconds $TimeoutSeconds
    }

    function Resolve-TestProbeApplication
    {
        param(
            [Parameter(Mandatory)]
            [string] $Name
        )

        InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $Name } -ScriptBlock {
            param($Name)

            Resolve-CompleterHelpProbeApplication -Name $Name
        }
    }

    function Get-TestPESubsystem
    {
        param(
            [Parameter(Mandatory)]
            [string] $LiteralPath
        )

        InModuleScope -ModuleName 'CompleterActions' -Parameters @{ LiteralPath = $LiteralPath } -ScriptBlock {
            param($LiteralPath)

            Get-CompleterPESubsystem -LiteralPath $LiteralPath
        }
    }
}

AfterAll {
    Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
}

Describe 'Help probe process helpers' {
    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null
    }

    It 'reads the PE subsystem of <Case>' -TestCases @(
        @{ Case = 'zero bytes'; Build = 'Empty'; Subsystem = 3; Magic = 0x20B; Expected = $null }
        @{ Case = 'a truncated header'; Build = 'Truncate'; Subsystem = 3; Magic = 0x20B; Expected = $null }
        @{ Case = 'a wrong MZ signature'; Build = 'WrongMZ'; Subsystem = 3; Magic = 0x20B; Expected = $null }
        @{ Case = 'a wrong PE signature'; Build = 'WrongPE'; Subsystem = 3; Magic = 0x20B; Expected = $null }
        @{ Case = 'a wrong optional-header magic'; Build = 'Header'; Subsystem = 3; Magic = 0x107; Expected = $null }
        @{ Case = 'an e_lfanew beyond the bytes read'; Build = 'FarHeader'; Subsystem = 3; Magic = 0x20B; Expected = $null }
        @{ Case = 'subsystem 1'; Build = 'Header'; Subsystem = 1; Magic = 0x20B; Expected = 1 }
        @{ Case = 'subsystem 2'; Build = 'Header'; Subsystem = 2; Magic = 0x10B; Expected = 2 }
        @{ Case = 'subsystem 3'; Build = 'Header'; Subsystem = 3; Magic = 0x20B; Expected = 3 }
    ) {
        $path = Join-Path -Path (New-TestDirectory) -ChildPath 'image.exe'
        if ($Build -eq 'Empty')
        {
            [System.IO.File]::WriteAllBytes($path, [byte[]]::new(0))
        }
        else
        {
            New-TestPEFile -Path $path -Subsystem $Subsystem -Magic $Magic -Truncate:($Build -eq 'Truncate')
            $bytes = [System.IO.File]::ReadAllBytes($path)
            switch ($Build)
            {
                'WrongMZ' { $bytes[0] = 0x58 }
                'WrongPE' { $bytes[0x80] = 0x58 }
                'FarHeader' { [System.BitConverter]::GetBytes([int] 4096).CopyTo($bytes, 0x3C) }
            }

            [System.IO.File]::WriteAllBytes($path, $bytes)
        }

        $result = Get-TestPESubsystem -LiteralPath $path

        if ($null -eq $Expected)
        {
            $null -eq $result | Should -BeTrue
        }
        else
        {
            $result | Should -BeOfType ([int])
            $result | Should -Be $Expected
        }
    }

    It 'returns $null for a file that cannot be opened' {
        $path = Join-Path -Path (New-TestDirectory) -ChildPath 'locked.exe'
        New-TestPEFile -Path $path -Subsystem 3

        if ($IsWindows)
        {
            $handle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try
            {
                $result = Get-TestPESubsystem -LiteralPath $path
            }
            finally
            {
                $handle.Dispose()
            }
        }
        else
        {
            if ((& id -u) -eq '0')
            {
                Set-ItResult -Skipped -Because 'root ignores file modes'
                return
            }

            & chmod 000 $path
            try
            {
                $result = Get-TestPESubsystem -LiteralPath $path
            }
            finally
            {
                & chmod 644 $path
            }
        }

        $null -eq $result | Should -BeTrue
        Get-TestPESubsystem -LiteralPath $path | Should -Be 3
    }

    It 'reads pwsh.exe as 3 and a cmd.exe copy patched to subsystem 2 as 2' {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'PE subsystems are read on Windows only'
            return
        }

        $patchedPath = Join-Path -Path (New-TestDirectory) -ChildPath 'guicmd.exe'
        New-TestPatchedExe -Path $patchedPath -Subsystem 2

        Get-TestPESubsystem -LiteralPath (Join-Path -Path $PSHOME -ChildPath 'pwsh.exe') | Should -Be 3
        Get-TestPESubsystem -LiteralPath $patchedPath | Should -Be 2
    }

    It 'resolves only applications, never a function or alias named like the command' {
        $directory = New-TestDirectory
        if ($IsWindows)
        {
            $applicationPath = Join-Path -Path $directory -ChildPath 'caprobetool.exe'
            New-TestPEFile -Path $applicationPath -Subsystem 3
        }
        else
        {
            $applicationPath = Join-Path -Path $directory -ChildPath 'caprobetool'
            Write-TestShellScript -Path $applicationPath -Line '#!/bin/sh', 'exit 0' -Executable
        }

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            foreach ($name in 'caprobetool', 'caprobeonly')
            {
                Set-Item -Path "Function:global:$name" -Value { 'function' }
                Set-Alias -Name $name -Value 'Get-Date' -Scope Global
            }

            $application = Resolve-TestProbeApplication -Name 'caprobetool'
            $functionOnly = Resolve-TestProbeApplication -Name 'caprobeonly'
        }
        finally
        {
            $env:PATH = $savedPath
            foreach ($name in 'caprobetool', 'caprobeonly')
            {
                Remove-Alias -Name $name -Scope Global -Force -ErrorAction Ignore
                Remove-Item -Path "Function:global:$name" -Force -ErrorAction Ignore
            }
        }

        $application.Path | Should -Be $applicationPath
        $application.CanRun | Should -BeTrue
        $application.Warning | Should -BeNullOrEmpty
        $functionOnly.Path | Should -BeNullOrEmpty
        $functionOnly.CanRun | Should -BeFalse
        $functionOnly.Warning | Should -Be "The command 'caprobeonly' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand."
    }

    It 'matches the name literally, so <Case> resolves nothing' -TestCases @(
        @{ Case = 'a lone *'; Name = '*' }
        @{ Case = 'a trailing *'; Name = 'caprobewil*' }
        @{ Case = 'a ?'; Name = 'caprobewil?' }
        @{ Case = 'a bracket class'; Name = 'caprobewil[d]' }
    ) {
        $directory = New-TestDirectory
        if ($IsWindows)
        {
            New-TestPEFile -Path (Join-Path -Path $directory -ChildPath 'caprobewild.exe') -Subsystem 3
        }
        else
        {
            Write-TestShellScript -Path (Join-Path -Path $directory -ChildPath 'caprobewild') -Line '#!/bin/sh', 'exit 0' -Executable
        }

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            $result = Resolve-TestProbeApplication -Name $Name
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $result.Name | Should -BeExactly $Name
        $result.Path | Should -BeNullOrEmpty
        $result.CanRun | Should -BeFalse
        $result.Warning | Should -BeExactly "The command '$Name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand."
    }

    It 'returns the not-found warning without throwing when ErrorActionPreference is Stop' {
        $name = 'zz_nonexistent_{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))

        $result = InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Name = $name } -ScriptBlock {
            param($Name)

            $ErrorActionPreference = 'Stop'
            Resolve-CompleterHelpProbeApplication -Name $Name
        }

        $result.Name | Should -Be $name
        $result.Path | Should -BeNullOrEmpty
        $result.CanRun | Should -BeFalse
        $result.Warning | Should -Be "The command '$name' was not found as an application, so the subcommand table is empty. Pass captured help with -HelpText, or fill the table by hand."
    }

    It 'refuses <Case> on Windows with its reason' -TestCases @(
        @{ Case = 'the patched GUI copy'; Build = 'Gui'; FileName = 'caguiprobe.exe'; Name = 'caguiprobe'; Reason = 'it is a Windows GUI program' }
        @{ Case = 'a .cmd file'; Build = 'Script'; FileName = 'caprobeshim.cmd'; Name = 'caprobeshim'; Reason = 'it is a .cmd file, which only runs through cmd.exe' }
        @{ Case = 'a file named TOOL.BAT'; Build = 'Script'; FileName = 'TOOL.BAT'; Name = 'TOOL'; Reason = 'it is a .bat file, which only runs through cmd.exe' }
        @{ Case = 'a zero-byte .exe'; Build = 'Empty'; FileName = 'caprobeempty.exe'; Name = 'caprobeempty'; Reason = 'its program header could not be read' }
        @{ Case = 'a subsystem 1 .exe'; Build = 'Native'; FileName = 'caprobenative.exe'; Name = 'caprobenative'; Reason = 'it is not a Windows console program (subsystem 1)' }
        @{ Case = 'a file with no extension'; Build = 'Script'; FileName = 'caprobenoext'; Name = 'caprobenoext'; Reason = 'it has no file extension' }
    ) {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the PE and extension checks apply on Windows only'
            return
        }

        $directory = New-TestDirectory
        $filePath = Join-Path -Path $directory -ChildPath $FileName
        switch ($Build)
        {
            'Gui' { New-TestPatchedExe -Path $filePath -Subsystem 2 }
            'Script' { Set-Content -LiteralPath $filePath -Value '@echo off', 'echo ran' -Encoding ascii }
            'Empty' { [System.IO.File]::WriteAllBytes($filePath, [byte[]]::new(0)) }
            'Native' { New-TestPEFile -Path $filePath -Subsystem 1 }
        }

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            $result = Resolve-TestProbeApplication -Name $Name
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $result.Path | Should -Be $filePath
        $result.CanRun | Should -BeFalse
        $result.Warning | Should -BeExactly "'$($result.Path)' was not run: $Reason. Run '$Name --help' yourself and pass the text with -HelpText."
    }

    It 'treats every resolved application as runnable on Linux and macOS' {
        if ($IsWindows)
        {
            Set-ItResult -Skipped -Because 'Linux and macOS run any resolved application'
            return
        }

        $directory = New-TestDirectory
        $applicationPath = Join-Path -Path $directory -ChildPath 'caprobesh'
        Write-TestShellScript -Path $applicationPath -Line '#!/bin/sh', 'echo help' -Executable

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            $result = Resolve-TestProbeApplication -Name 'caprobesh'
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $result.Path | Should -Be $applicationPath
        $result.CanRun | Should -BeTrue
        $result.Warning | Should -BeNullOrEmpty
    }

    It 'returns Exited with both streams and the exit code' {
        $fixture = Write-TestFixture -Name 'exit3.ps1' -Line @(
            '$stdout = [Console]::OpenStandardOutput()'
            '$bytes = [byte[]] (0x6F, 0x75, 0x74, 0x00, 0xFF, 0x0A)'
            '$stdout.Write($bytes, 0, $bytes.Length)'
            '$stdout.Flush()'
            '$stderr = [Console]::OpenStandardError()'
            '$bytes = [byte[]] (0x65, 0x72, 0x72, 0x0A)'
            '$stderr.Write($bytes, 0, $bytes.Length)'
            '$stderr.Flush()'
            'exit 3'
        )

        $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 60

        $result.Status | Should -Be 'Exited'
        $result.ExitCode | Should -Be 3
        $result.StandardOutput -join ',' | Should -Be '111,117,116,0,255,10'
        $result.StandardError -join ',' | Should -Be '101,114,114,10'
        $result.ProcessId | Should -BeGreaterThan 0
        $result.StartError | Should -BeNullOrEmpty
    }

    It 'closes standard input so a program that reads it sees end of file' {
        $fixture = Write-TestFixture -Name 'stdin.ps1' -Line @(
            '$text = [Console]::In.ReadToEnd()'
            '[Console]::Out.Write(''eof:'' + $text.Length)'
            'exit 0'
        )

        $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 60

        $result.Status | Should -Be 'Exited'
        [System.Text.Encoding]::UTF8.GetString($result.StandardOutput) | Should -Be 'eof:0'
    }

    It 'runs in the temporary directory with NO_COLOR set' {
        $fixture = Write-TestFixture -Name 'environment.ps1' -Line @(
            '[Console]::Out.Write((Get-Location).ProviderPath + ''|'' + $env:NO_COLOR)'
            'exit 0'
        )

        $savedNoColor = $env:NO_COLOR
        try
        {
            $env:NO_COLOR = '0'
            $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 60
        }
        finally
        {
            $env:NO_COLOR = $savedNoColor
        }

        $separators = [char[]] @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $directory, $noColor = [System.Text.Encoding]::UTF8.GetString($result.StandardOutput).Split('|')

        $result.Status | Should -Be 'Exited'
        $directory.TrimEnd($separators) | Should -Be ([System.IO.Path]::GetTempPath().TrimEnd($separators))
        $noColor | Should -BeExactly '1'
    }

    It 'keeps the first MiB of a stream and drains the rest' {
        $fixture = Write-TestFixture -Name 'chatty.ps1' -Line @(
            '$chunk = [byte[]]::new(65536)'
            'for ($i = 0; $i -lt $chunk.Length; $i++) { $chunk[$i] = $i % 251 }'
            '$stdout = [Console]::OpenStandardOutput()'
            '$stderr = [Console]::OpenStandardError()'
            'for ($i = 0; $i -lt 48; $i++)'
            '{'
            '    $stdout.Write($chunk, 0, $chunk.Length)'
            '    if ($i -lt 32) { $stderr.Write($chunk, 0, $chunk.Length) }'
            '}'
            '$stdout.Flush()'
            '$stderr.Flush()'
            'exit 0'
        )

        $chunk = [byte[]]::new(65536)
        for ($i = 0; $i -lt $chunk.Length; $i++)
        {
            $chunk[$i] = $i % 251
        }

        $expected = [System.IO.MemoryStream]::new()
        for ($i = 0; $i -lt 16; $i++)
        {
            $expected.Write($chunk, 0, $chunk.Length)
        }

        $expectedText = [System.Convert]::ToBase64String($expected.ToArray())

        $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 60

        $result.Status | Should -Be 'Exited'
        $result.ExitCode | Should -Be 0
        $result.StandardOutput.Length | Should -Be 1048576
        $result.StandardError.Length | Should -Be 1048576
        [System.Convert]::ToBase64String($result.StandardOutput) | Should -BeExactly $expectedText
        [System.Convert]::ToBase64String($result.StandardError) | Should -BeExactly $expectedText
    }

    It 'returns TimedOut and kills the process at the deadline' {
        $fixture = Write-TestFixture -Name 'sleep.ps1' -Line @(
            '[Console]::Out.Write(''started'')'
            'Start-Sleep -Seconds 60'
            'exit 0'
        )

        $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 2

        $result.Status | Should -Be 'TimedOut'
        $result.ExitCode | Should -BeNullOrEmpty
        $result.StandardOutput.Length | Should -Be 0
        $result.StandardError.Length | Should -Be 0
        $result.ProcessId | Should -BeGreaterThan 0
        Get-Process -Id $result.ProcessId -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    Context 'Held output' {
        AfterEach {
            if ($null -ne $script:HeldDescendantId)
            {
                Stop-Process -Id $script:HeldDescendantId -Force -ErrorAction Ignore
                Wait-Process -Id $script:HeldDescendantId -Timeout 10 -ErrorAction Ignore
            }
        }

        It 'returns HeldOutput when a descendant keeps the output open after the parent exits' {
            $script:HeldDescendantId = $null
            $directory = New-TestDirectory
            $idPath = Join-Path -Path $directory -ChildPath 'descendant.txt'

            if ($IsWindows)
            {
                $fixture = Write-TestFixture -Name 'held.ps1' -Line @(
                    '$descendant = Start-Process -NoNewWindow -FilePath ''ping.exe'' -ArgumentList ''-n'', ''15'', ''127.0.0.1'' -PassThru'
                    ('Set-Content -LiteralPath ''{0}'' -Value $descendant.Id' -f $idPath)
                    'exit 0'
                )

                $result = Invoke-TestPwshFixture -FixturePath $fixture -TimeoutSeconds 20
            }
            else
            {
                $scriptPath = Join-Path -Path $directory -ChildPath 'held.sh'
                Write-TestShellScript -Path $scriptPath -Line '#!/bin/sh', 'sleep 30 &', ('echo $! > ''{0}''' -f $idPath), 'exit 0' -Executable

                $result = Invoke-TestHelpProcess -FilePath $scriptPath -TimeoutSeconds 20
            }

            $script:HeldDescendantId = [int] (Get-Content -LiteralPath $idPath -TotalCount 1)

            $result.Status | Should -Be 'HeldOutput'
            $result.ExitCode | Should -BeNullOrEmpty
            $result.StandardOutput.Length | Should -Be 0
            $result.StandardError.Length | Should -Be 0
        }

        It 'leaves no held-output descendant running after cleanup' {
            $script:HeldDescendantId | Should -BeGreaterThan 0
            Get-Process -Id $script:HeldDescendantId -ErrorAction Ignore | Should -BeNullOrEmpty
        }
    }

    It 'returns StartFailed with the exception message for a file the loader rejects' {
        $directory = New-TestDirectory
        if ($IsWindows)
        {
            $filePath = Join-Path -Path $directory -ChildPath 'carejected.exe'
            New-TestPEFile -Path $filePath -Subsystem 3
        }
        else
        {
            $filePath = Join-Path -Path $directory -ChildPath 'canoexec'
            Write-TestShellScript -Path $filePath -Line '#!/bin/sh', 'echo help'

            $savedPath = $env:PATH
            try
            {
                $env:PATH = $directory
                $filePath = (Get-Command -Name 'canoexec' -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
            }
            finally
            {
                $env:PATH = $savedPath
            }
        }

        $result = Invoke-TestHelpProcess -FilePath $filePath -ArgumentList '--help' -TimeoutSeconds 10

        $result.Status | Should -Be 'StartFailed'
        $result.StartError | Should -Not -BeNullOrEmpty
        $result.StartError | Should -Not -Match '^Exception calling'
        $result.ExitCode | Should -BeNullOrEmpty
        $result.ProcessId | Should -BeNullOrEmpty
    }
}

Describe 'Probe decisions' {
    BeforeAll {
        $script:ProbeHelpText = "Usage: catool <command>`n`nCommands:`n  build    Compile the project`n  test     Run the tests`n"

        # Replaces Invoke-CompleterHelpProcess in module scope with a shim that
        # records each run. Without -Fake it passes through to the real runner;
        # -NoProfile then puts -NoProfile -NonInteractive -File in front of the
        # one probe argument, because a user profile can keep 'pwsh <file>'
        # from exiting. -Fake replaces the runner with a script block that
        # returns a result for each argument list.
        function Install-TestRunnerShim
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only replaces a function in the imported test module.')]
            [CmdletBinding()]
            param(
                [Parameter()]
                [switch] $NoProfile,

                [Parameter()]
                [scriptblock] $Fake
            )

            & (Get-Module -Name 'CompleterActions') {
                param($NoProfile, $Fake)

                $script:TestProbeRuns = [System.Collections.Generic.List[object]]::new()
                $script:TestRunnerNoProfile = $NoProfile
                $script:TestRunnerFake = $Fake
                $script:TestRunnerOriginal = ${function:Invoke-CompleterHelpProcess}

                function script:Invoke-CompleterHelpProcess
                {
                    param($FilePath, $ArgumentList, $TimeoutSeconds)

                    if ($null -ne $script:TestRunnerFake)
                    {
                        $result = & $script:TestRunnerFake $FilePath $ArgumentList $TimeoutSeconds
                    }
                    else
                    {
                        $arguments = @($ArgumentList)
                        if ($script:TestRunnerNoProfile)
                        {
                            $arguments = @('-NoProfile', '-NonInteractive', '-File') + $arguments
                        }

                        $result = & $script:TestRunnerOriginal -FilePath $FilePath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds
                    }

                    $script:TestProbeRuns.Add([pscustomobject] @{
                            FilePath     = $FilePath
                            ArgumentList = @($ArgumentList)
                            Status       = $result.Status
                            ProcessId    = $result.ProcessId
                        })
                    $result
                }
            } $NoProfile.IsPresent $Fake
        }

        function Get-TestProbeRun
        {
            & (Get-Module -Name 'CompleterActions') {
                $script:TestProbeRuns.ToArray()
            }
        }

        function Invoke-TestHelpSubcommand
        {
            param(
                [Parameter(Mandatory)]
                [psobject] $Application,

                [Parameter()]
                [string] $HelpArgument,

                [Parameter()]
                [double] $TimeoutSeconds = 30
            )

            $parameters = @{ Application = $Application; TimeoutSeconds = $TimeoutSeconds }
            if ($PSBoundParameters.ContainsKey('HelpArgument'))
            {
                $parameters['HelpArgument'] = $HelpArgument
            }

            InModuleScope -ModuleName 'CompleterActions' -Parameters @{ Splat = $parameters } -ScriptBlock {
                param($Splat)

                Get-CompleterHelpSubcommand @Splat
            }
        }

        function New-TestApplication
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only builds an application record.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string] $Name
            )

            [pscustomobject] @{
                PSTypeName = 'CompleterActions.CompleterHelpProbeApplication'
                Name       = $Name
                Path       = Join-Path -Path $TestDrive -ChildPath "$Name.exe"
                CanRun     = $true
                Warning    = $null
            }
        }

        function New-TestProcessResult
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This test helper only builds a runner result.')]
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Exited', 'TimedOut', 'HeldOutput', 'StartFailed')]
                [string] $Status,

                [Parameter()]
                [AllowEmptyString()]
                [string] $Text = ''
            )

            [pscustomobject] @{
                Status              = $Status
                ExitCode            = if ($Status -eq 'Exited') { 1 } else { $null }
                StandardOutput      = if ($Status -eq 'Exited') { [System.Text.Encoding]::UTF8.GetBytes($Text) } else { [byte[]]::new(0) }
                StandardError       = [byte[]]::new(0)
                ElapsedMilliseconds = [long] 12
                ProcessId           = if ($Status -eq 'StartFailed') { $null } else { 4242 }
                StartError          = if ($Status -eq 'StartFailed') { 'the fake program could not be started' } else { $null }
            }
        }

        # Writes a pwsh fixture that writes the given bytes to standard output
        # and standard error, then PaddingLines lines of 99 'x' characters to
        # standard output, and exits with ExitCode.
        function Write-TestByteFixture
        {
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter()]
                [byte[]] $StandardOutput = [byte[]]::new(0),

                [Parameter()]
                [byte[]] $StandardError = [byte[]]::new(0),

                [Parameter()]
                [int] $PaddingLines = 0,

                [Parameter()]
                [int] $ExitCode = 0
            )

            Write-TestFixture -Name $Name -Line @(
                ('$out = [System.Convert]::FromBase64String(''{0}'')' -f [System.Convert]::ToBase64String($StandardOutput))
                ('$err = [System.Convert]::FromBase64String(''{0}'')' -f [System.Convert]::ToBase64String($StandardError))
                '$stdout = [Console]::OpenStandardOutput()'
                '$stderr = [Console]::OpenStandardError()'
                '$stdout.Write($out, 0, $out.Length)'
                '$stderr.Write($err, 0, $err.Length)'
                '$line = [byte[]]::new(100)'
                'for ($i = 0; $i -lt 99; $i++) { $line[$i] = 0x78 }'
                '$line[99] = 0x0A'
                ('for ($i = 0; $i -lt {0}; $i++) {{ $stdout.Write($line, 0, $line.Length) }}' -f $PaddingLines)
                '$stdout.Flush()'
                '$stderr.Flush()'
                ('exit {0}' -f $ExitCode)
            )
        }

        function Resolve-TestPwshApplication
        {
            if ($null -eq (Get-Command -Name 'pwsh' -CommandType Application -ErrorAction Ignore))
            {
                return $null
            }

            Resolve-TestProbeApplication -Name 'pwsh'
        }

        function Get-TestProbeLinePattern
        {
            param(
                [Parameter(Mandatory)]
                [string] $Path,

                [Parameter(Mandatory)]
                [string] $Argument,

                [Parameter(Mandatory)]
                [string] $ExitCode,

                [Parameter(Mandatory)]
                [string] $Characters,

                [Parameter(Mandatory)]
                [string] $Subcommands
            )

            '^Probed ''{0} {1}'': exit {2}, {3} characters, {4} subcommands, \d+ ms\.$' -f [regex]::Escape($Path), [regex]::Escape($Argument), $ExitCode, $Characters, $Subcommands
        }
    }

    BeforeEach {
        Remove-Module -Name 'CompleterActions' -Force -ErrorAction SilentlyContinue
        Import-Module -Name $script:ManifestPath -Force | Out-Null
    }

    It 'probes pwsh --help once and returns one probe line with exit 0' {
        $application = Resolve-TestPwshApplication
        if ($null -eq $application)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        Install-TestRunnerShim
        $result = Invoke-TestHelpSubcommand -Application $application
        $runs = @(Get-TestProbeRun)

        $runs.Count | Should -Be 1
        $runs[0].ArgumentList | Should -Be @('--help')
        $result.Argument | Should -BeExactly '--help'
        $result.Warnings | Should -BeNullOrEmpty
        $result.VerboseLines.Count | Should -Be 1
        $result.VerboseLines[0] | Should -Match (Get-TestProbeLinePattern -Path $application.Path -Argument '--help' -ExitCode '0' -Characters '\d+' -Subcommands '\d+')
    }

    It 'uses help that a probe writes only to standard error with exit 2' {
        $application = Resolve-TestPwshApplication
        if ($null -eq $application)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $fixture = Write-TestByteFixture -Name 'stderr-help.ps1' -StandardError ([System.Text.Encoding]::UTF8.GetBytes($script:ProbeHelpText)) -ExitCode 2

        Install-TestRunnerShim -NoProfile
        $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $fixture

        $result.Subcommands.Name | Should -Be @('build', 'test')
        $result.Subcommands.Description | Should -Be @('Compile the project', 'Run the tests')
        $result.Argument | Should -BeExactly $fixture
        $result.Warnings | Should -BeNullOrEmpty
        $result.VerboseLines.Count | Should -Be 1
        $result.VerboseLines[0] | Should -Match (Get-TestProbeLinePattern -Path $application.Path -Argument $fixture -ExitCode '2' -Characters $script:ProbeHelpText.Length -Subcommands '2')
    }

    It 'decodes UTF-16 LE probe output' {
        $application = Resolve-TestPwshApplication
        if ($null -eq $application)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $fixture = Write-TestByteFixture -Name 'utf16-help.ps1' -StandardOutput ([System.Text.Encoding]::Unicode.GetBytes($script:ProbeHelpText))

        Install-TestRunnerShim -NoProfile
        $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $fixture

        $result.Subcommands.Name | Should -Be @('build', 'test')
        $result.Subcommands.Description | Should -Be @('Compile the project', 'Run the tests')
        $result.Warnings | Should -BeNullOrEmpty
        $result.VerboseLines[0] | Should -Match (Get-TestProbeLinePattern -Path $application.Path -Argument $fixture -ExitCode '0' -Characters $script:ProbeHelpText.Length -Subcommands '2')
    }

    It 'cuts standard output at 1 MiB and still parses the table' {
        $application = Resolve-TestPwshApplication
        if ($null -eq $application)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $fixture = Write-TestByteFixture -Name 'chatty-help.ps1' -StandardOutput ([System.Text.Encoding]::UTF8.GetBytes($script:ProbeHelpText + "`n")) -PaddingLines 16384

        Install-TestRunnerShim -NoProfile
        $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $fixture
        $runs = @(Get-TestProbeRun)

        $runs.Count | Should -Be 1
        $runs[0].Status | Should -Be 'Exited'
        $result.Subcommands.Name | Should -Be @('build', 'test')
        $result.Warnings | Should -BeNullOrEmpty
        $result.VerboseLines[0] | Should -Match (Get-TestProbeLinePattern -Path $application.Path -Argument $fixture -ExitCode '0' -Characters '1048576' -Subcommands '2')
    }

    It 'warns did not exit within 0.05 seconds and leaves no direct child running' {
        $application = Resolve-TestPwshApplication
        if ($null -eq $application)
        {
            Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
            return
        }

        $fixture = Write-TestFixture -Name 'sleep-help.ps1' -Line @(
            'Start-Sleep -Seconds 60'
            'exit 0'
        )

        Install-TestRunnerShim -NoProfile
        $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $fixture -TimeoutSeconds 0.05
        $runs = @(Get-TestProbeRun)

        $runs.Count | Should -Be 1
        $runs[0].Status | Should -Be 'TimedOut'
        $runs[0].ProcessId | Should -BeGreaterThan 0
        $result.Subcommands.Count | Should -Be 0
        $result.Warnings | Should -Be @("'pwsh $fixture' did not exit within 0.05 seconds and was stopped, so its help was not used.")
        Get-Process -Id $runs[0].ProcessId -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    Context 'Held output' {
        AfterEach {
            if ($null -ne $script:DecisionDescendantId)
            {
                Stop-Process -Id $script:DecisionDescendantId -Force -ErrorAction Ignore
                Wait-Process -Id $script:DecisionDescendantId -Timeout 10 -ErrorAction Ignore
            }
        }

        It 'returns within 3 seconds with the held-output warning and an empty table' {
            $script:DecisionDescendantId = $null
            $directory = New-TestDirectory
            $idPath = Join-Path -Path $directory -ChildPath 'descendant.txt'
            $timeoutSeconds = InModuleScope -ModuleName 'CompleterActions' -ScriptBlock { $script:CompleterHelpProbeTimeoutSeconds }

            if ($IsWindows)
            {
                $application = Resolve-TestPwshApplication
                if ($null -eq $application)
                {
                    Set-ItResult -Skipped -Because 'pwsh is not an application on PATH'
                    return
                }

                $fixture = Write-TestFixture -Name 'held-help.ps1' -Line @(
                    '$descendant = Start-Process -NoNewWindow -FilePath ''ping.exe'' -ArgumentList ''-n'', ''15'', ''127.0.0.1'' -PassThru'
                    ('Set-Content -LiteralPath ''{0}'' -Value $descendant.Id' -f $idPath)
                    'exit 0'
                )
                $expectedWarning = "'pwsh $fixture' exited but left a process holding its output, so its help was not used."

                Install-TestRunnerShim -NoProfile
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $fixture -TimeoutSeconds $timeoutSeconds
                $stopwatch.Stop()
            }
            else
            {
                Write-TestShellScript -Path (Join-Path -Path $directory -ChildPath 'caheldprobe') -Line '#!/bin/sh', 'sleep 30 &', ('echo $! > ''{0}''' -f $idPath), 'exit 0' -Executable
                $expectedWarning = "'caheldprobe --help' exited but left a process holding its output, so its help was not used."

                $savedPath = $env:PATH
                try
                {
                    $env:PATH = $directory
                    $application = Resolve-TestProbeApplication -Name 'caheldprobe'
                }
                finally
                {
                    $env:PATH = $savedPath
                }

                Install-TestRunnerShim
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Invoke-TestHelpSubcommand -Application $application -TimeoutSeconds $timeoutSeconds
                $stopwatch.Stop()
            }

            $script:DecisionDescendantId = [int] (Get-Content -LiteralPath $idPath -TotalCount 1)
            $runs = @(Get-TestProbeRun)

            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 3
            $runs.Count | Should -Be 1
            $runs[0].Status | Should -Be 'HeldOutput'
            $result.Subcommands.Count | Should -Be 0
            $result.Warnings | Should -Be @($expectedWarning)
        }
    }

    It 'applies the /? rule to <Case>' -TestCases @(
        @{ Case = 'two lines on Windows'; Platform = 'Windows'; HelpArgument = $null; FirstStatus = 'Exited'; FirstText = "Invalid argument.`nType ""catool /?"" for usage.`n"; Expected = '--help,/?'; Names = 'build,test'; Argument = '/?'; Warning = $null }
        @{ Case = 'five lines on Windows'; Platform = 'Windows'; HelpArgument = $null; FirstStatus = 'Exited'; FirstText = "one`ntwo`n`nthree`nfour`nfive`n"; Expected = '--help'; Names = ''; Argument = '--help'; Warning = $null }
        @{ Case = 'a timeout on Windows'; Platform = 'Windows'; HelpArgument = $null; FirstStatus = 'TimedOut'; FirstText = ''; Expected = '--help'; Names = ''; Argument = '--help'; Warning = "'catool --help' did not exit within 5 seconds and was stopped, so its help was not used." }
        @{ Case = 'a start failure on Windows'; Platform = 'Windows'; HelpArgument = $null; FirstStatus = 'StartFailed'; FirstText = ''; Expected = '--help'; Names = ''; Argument = '--help'; Warning = "'<path>' was not run: the fake program could not be started. Pass captured help with -HelpText." }
        @{ Case = 'held output on Windows'; Platform = 'Windows'; HelpArgument = $null; FirstStatus = 'HeldOutput'; FirstText = ''; Expected = '--help'; Names = ''; Argument = '--help'; Warning = "'catool --help' exited but left a process holding its output, so its help was not used." }
        @{ Case = '-HelpArgument given'; Platform = 'Any'; HelpArgument = '-h'; FirstStatus = 'Exited'; FirstText = "Invalid argument.`nType ""catool /?"" for usage.`n"; Expected = '-h'; Names = ''; Argument = '-h'; Warning = $null }
        @{ Case = 'two lines on Linux and macOS'; Platform = 'Unix'; HelpArgument = $null; FirstStatus = 'Exited'; FirstText = "Invalid argument.`nType ""catool /?"" for usage.`n"; Expected = '--help'; Names = ''; Argument = '--help'; Warning = $null }
    ) {
        if ($Platform -eq 'Windows' -and -not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the /? fallback runs on Windows only'
            return
        }

        if ($Platform -eq 'Unix' -and $IsWindows)
        {
            Set-ItResult -Skipped -Because 'this case asserts the Linux and macOS rule'
            return
        }

        $first = New-TestProcessResult -Status $FirstStatus -Text $FirstText
        $fallback = New-TestProcessResult -Status 'Exited' -Text $script:ProbeHelpText
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                if ($ArgumentList[0] -eq '/?') { $fallback } else { $first }
            }.GetNewClosure())

        $application = New-TestApplication -Name 'catool'
        if ($null -eq $HelpArgument)
        {
            $result = Invoke-TestHelpSubcommand -Application $application -TimeoutSeconds 5
        }
        else
        {
            $result = Invoke-TestHelpSubcommand -Application $application -HelpArgument $HelpArgument -TimeoutSeconds 5
        }

        $runs = @(Get-TestProbeRun)
        $exitedRuns = @($runs | Where-Object { $_.Status -eq 'Exited' }).Count

        @($runs | ForEach-Object { $_.ArgumentList[0] }) -join ',' | Should -BeExactly $Expected
        @($runs | Where-Object { $_.FilePath -ne $application.Path }).Count | Should -Be 0
        @($result.Subcommands | ForEach-Object { $_.Name }) -join ',' | Should -BeExactly $Names
        $result.Argument | Should -BeExactly $Argument
        $result.VerboseLines.Count | Should -Be $exitedRuns
        if ($null -eq $Warning)
        {
            $result.Warnings | Should -BeNullOrEmpty
        }
        else
        {
            $result.Warnings | Should -Be @($Warning.Replace('<path>', $application.Path))
        }
    }

    It 'runs an executable shell script and warns was not run for the same file without the execute bit' {
        if ($IsWindows)
        {
            Set-ItResult -Skipped -Because 'execute bits exist on Linux and macOS only'
            return
        }

        $directory = New-TestDirectory
        $scriptPath = Join-Path -Path $directory -ChildPath 'cashellprobe'
        $lines = @('#!/bin/sh', 'printf ''Commands:\n  build    Compile the project\n  test     Run the tests\n''', 'exit 0')

        # chmod runs with the session's PATH; only resolution uses the scratch PATH.
        Write-TestShellScript -Path $scriptPath -Line $lines -Executable
        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            $runnable = Resolve-TestProbeApplication -Name 'cashellprobe'
        }
        finally
        {
            $env:PATH = $savedPath
        }

        Write-TestShellScript -Path $scriptPath -Line $lines
        try
        {
            $env:PATH = $directory
            $notExecutable = Resolve-TestProbeApplication -Name 'cashellprobe'
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $notExecutable.Path | Should -Be $scriptPath
        $notExecutable.CanRun | Should -BeTrue
        $notRun = Invoke-TestHelpSubcommand -Application $notExecutable

        Write-TestShellScript -Path $scriptPath -Line $lines -Executable
        $run = Invoke-TestHelpSubcommand -Application $runnable

        $run.Subcommands.Name | Should -Be @('build', 'test')
        $run.Warnings | Should -BeNullOrEmpty
        $notRun.Subcommands.Count | Should -Be 0
        $notRun.Warnings.Count | Should -Be 1
        $notRun.Warnings[0] | Should -Match ('^''{0}'' was not run: .+\. Pass captured help with -HelpText\.$' -f [regex]::Escape($scriptPath))
        $notRun.VerboseLines | Should -BeNullOrEmpty
    }

    It 'warns was not run for a console header the loader rejects' {
        if (-not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the PE loader exists on Windows only'
            return
        }

        $directory = New-TestDirectory
        New-TestPEFile -Path (Join-Path -Path $directory -ChildPath 'carejectedprobe.exe') -Subsystem 3

        $savedPath = $env:PATH
        try
        {
            $env:PATH = $directory
            $application = Resolve-TestProbeApplication -Name 'carejectedprobe'
        }
        finally
        {
            $env:PATH = $savedPath
        }

        $application.CanRun | Should -BeTrue
        Install-TestRunnerShim
        $result = Invoke-TestHelpSubcommand -Application $application
        $runs = @(Get-TestProbeRun)

        $runs.Count | Should -Be 1
        $runs[0].Status | Should -Be 'StartFailed'
        $result.Subcommands.Count | Should -Be 0
        $result.Warnings.Count | Should -Be 1
        $result.Warnings[0] | Should -Match ('^''{0}'' was not run: .+\. Pass captured help with -HelpText\.$' -f [regex]::Escape($application.Path))
        $result.Warnings[0] | Should -Not -Match 'Exception calling'
        $result.VerboseLines | Should -BeNullOrEmpty
    }

    It 'runs nothing for <Case> and returns its warning' -TestCases @(
        @{ Case = 'a command not found'; Build = 'Missing' }
        @{ Case = 'the patched GUI copy'; Build = 'Gui' }
        @{ Case = 'a .cmd file'; Build = 'Cmd' }
    ) {
        if ($Build -ne 'Missing' -and -not $IsWindows)
        {
            Set-ItResult -Skipped -Because 'the PE and extension checks apply on Windows only'
            return
        }

        $directory = New-TestDirectory
        $markerPath = Join-Path -Path $directory -ChildPath 'marker.txt'
        switch ($Build)
        {
            'Missing'
            {
                $name = 'zz_nonexistent_{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))
            }
            'Gui'
            {
                $name = 'caguidecision'
                New-TestPatchedExe -Path (Join-Path -Path $directory -ChildPath "$name.exe") -Subsystem 2
            }
            'Cmd'
            {
                $name = 'cacmddecision'
                Set-Content -LiteralPath (Join-Path -Path $directory -ChildPath "$name.cmd") -Value '@echo off', ('echo ran> "{0}"' -f $markerPath) -Encoding ascii
            }
        }

        $savedPath = $env:PATH
        try
        {
            if ($Build -ne 'Missing')
            {
                $env:PATH = $directory
            }

            $application = Resolve-TestProbeApplication -Name $name
        }
        finally
        {
            $env:PATH = $savedPath
        }

        Install-TestRunnerShim
        $result = Invoke-TestHelpSubcommand -Application $application

        $application.CanRun | Should -BeFalse
        @(Get-TestProbeRun).Count | Should -Be 0
        $result.Subcommands.Count | Should -Be 0
        $result.Argument | Should -BeNullOrEmpty
        $result.Warnings | Should -Be @($application.Warning)
        $result.VerboseLines | Should -BeNullOrEmpty
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }

    It 'formats the limit with the invariant culture under a comma-decimal culture' {
        $timedOut = New-TestProcessResult -Status 'TimedOut'
        Install-TestRunnerShim -Fake ({
                param($FilePath, $ArgumentList, $TimeoutSeconds)

                $timedOut
            }.GetNewClosure())

        $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try
        {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
            $commaText = (0.05).ToString()
            $result = Invoke-TestHelpSubcommand -Application (New-TestApplication -Name 'catool') -TimeoutSeconds 0.05
        }
        finally
        {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
        }

        $commaText | Should -Be '0,05'
        $result.Warnings | Should -Be @("'catool --help' did not exit within 0.05 seconds and was stopped, so its help was not used.")
    }
}
