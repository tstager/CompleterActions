<#
.SYNOPSIS
Runs a program once to read its help, under one deadline.

.DESCRIPTION
Starts the program with UseShellExecute off, no window, the arguments in
ArgumentList so no shell parses them, standard input redirected and closed at
once, the temporary directory as the working directory, and the session's
environment plus NO_COLOR=1.

Standard output and standard error are read concurrently as bytes, one
ReadAsync per stream at a time. Each stream keeps its first 1 MiB (1048576
bytes) and keeps draining after that, discarding the rest, so a chatty
program never blocks on a full pipe. The reads are polled from this thread
with Task.WaitAny and a timeout, so no callback runs PowerShell code and no
wait is unbounded.

One deadline, fixed at start, covers the process and both reads. A process
still running at the deadline is killed with its descendants (Kill($true)),
waited for up to 1 second, and its output is dropped: TimedOut. When the
process has exited, the reads get until 1 second later or the deadline,
whichever is earlier; a read still open then means a descendant holds the
pipe, so the streams are closed, Kill($true) is attempted, and the output is
dropped: HeldOutput. An exception from Process.Start gives StartFailed with
the exception's message. Otherwise the result is Exited, with both streams'
bytes and the exit code; the exit code decides nothing here.

This helper writes no warning or verbose stream; its caller turns the status
into messages.

.PARAMETER FilePath
The full path of the program to run.

.PARAMETER ArgumentList
The arguments, each passed as one argument without shell parsing.

.PARAMETER TimeoutSeconds
The deadline in seconds, measured from the start of the run.

.OUTPUTS
CompleterActions.CompleterHelpProcessResult
Returns a record with Status (Exited, TimedOut, HeldOutput, or StartFailed),
ExitCode (null unless Exited), StandardOutput and StandardError (byte arrays,
empty unless Exited), ElapsedMilliseconds, ProcessId (null for StartFailed),
and StartError (the Process.Start exception message, or null).
#>
function Invoke-CompleterHelpProcess
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [ValidateRange(0.001, 3600)]
        [double] $TimeoutSeconds
    )

    $streamCap = 1048576
    $readSize = 65536
    $pollMilliseconds = 50

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $startInfo.Environment['NO_COLOR'] = '1'
    foreach ($argument in $ArgumentList)
    {
        $startInfo.ArgumentList.Add($argument)
    }

    $status = $null
    $exitCode = $null
    $processId = $null
    $startError = $null
    $readers = @()
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = $TimeoutSeconds * 1000

    try
    {
        try
        {
            $null = $process.Start()
        }
        catch
        {
            $exception = $_.Exception
            if ($exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $exception.InnerException)
            {
                $exception = $exception.InnerException
            }

            $status = 'StartFailed'
            $startError = $exception.Message
        }

        if ($null -eq $status)
        {
            $processId = $process.Id
            $process.StandardInput.Close()

            $readers = @(
                foreach ($stream in @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream))
                {
                    $buffer = [byte[]]::new($readSize)
                    [pscustomobject] @{
                        Stream = $stream
                        Buffer = $buffer
                        Data   = [System.IO.MemoryStream]::new()
                        Task   = $stream.ReadAsync($buffer, 0, $readSize)
                        Done   = $false
                    }
                }
            )

            $readDeadline = $deadline
            $exitSeen = $false
            while ($true)
            {
                $pending = @($readers | Where-Object { -not $_.Done })
                if ($pending.Count -eq 0)
                {
                    break
                }

                $now = $stopwatch.Elapsed.TotalMilliseconds
                if (-not $exitSeen -and $process.HasExited)
                {
                    $exitSeen = $true
                    $readDeadline = [System.Math]::Min($now + 1000, $deadline)
                }

                if ($now -ge $readDeadline)
                {
                    $status = if ($exitSeen) { 'HeldOutput' } else { 'TimedOut' }
                    break
                }

                $wait = [int] [System.Math]::Ceiling([System.Math]::Min($readDeadline - $now, $pollMilliseconds))
                $tasks = [System.Threading.Tasks.Task[]] @($pending | ForEach-Object { $_.Task })
                $null = [System.Threading.Tasks.Task]::WaitAny($tasks, $wait)

                foreach ($reader in $pending)
                {
                    if (-not $reader.Task.IsCompleted)
                    {
                        continue
                    }

                    $read = 0
                    if ($reader.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion)
                    {
                        $read = $reader.Task.Result
                    }

                    if ($read -le 0)
                    {
                        $reader.Done = $true
                        continue
                    }

                    $keep = [System.Math]::Min($read, $streamCap - $reader.Data.Length)
                    if ($keep -gt 0)
                    {
                        $reader.Data.Write($reader.Buffer, 0, $keep)
                    }

                    $reader.Task = $reader.Stream.ReadAsync($reader.Buffer, 0, $readSize)
                }
            }

            if ($null -eq $status)
            {
                $remaining = [int] [System.Math]::Max(0, [System.Math]::Ceiling($deadline - $stopwatch.Elapsed.TotalMilliseconds))
                if ($process.WaitForExit($remaining))
                {
                    $status = 'Exited'
                    $exitCode = $process.ExitCode
                }
                else
                {
                    $status = 'TimedOut'
                }
            }

            if ($status -ne 'Exited')
            {
                try
                {
                    $process.Kill($true)
                }
                catch
                {
                    Write-Debug -Message "Stopping process $processId failed. $($_.Exception.Message)"
                }

                if ($status -eq 'TimedOut')
                {
                    $null = $process.WaitForExit(1000)
                }
            }
        }
    }
    finally
    {
        foreach ($reader in $readers)
        {
            $reader.Stream.Dispose()
        }

        $process.Dispose()
    }

    $standardOutput = [byte[]]::new(0)
    $standardError = [byte[]]::new(0)
    if ($status -eq 'Exited')
    {
        $standardOutput = $readers[0].Data.ToArray()
        $standardError = $readers[1].Data.ToArray()
    }

    [pscustomobject] [ordered] @{
        PSTypeName          = 'CompleterActions.CompleterHelpProcessResult'
        Status              = $status
        ExitCode            = $exitCode
        StandardOutput      = $standardOutput
        StandardError       = $standardError
        ElapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        ProcessId           = $processId
        StartError          = $startError
    }
}
