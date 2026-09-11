<#
.SYNOPSIS
Registers a managed PowerShell argument completer.

.DESCRIPTION
Registers native or command-parameter argument completers with
Register-ArgumentCompleter and records the registrations in the module's managed
state. Existing managed or runtime registrations are preserved unless you use
-Force to replace them. Registering the same script for a target that is already
managed is idempotent only while the managed record still matches the live
runtime value; when the runtime registration was replaced or removed outside
this module, the managed record is stale and the command fails until you
reconcile it with -Force. Each target is updated transactionally: if the
runtime or managed write fails, the previous runtime and managed state are
restored and any rollback failure is reported alongside the original error. The
command supports array inputs for command and parameter targets, and it can
also accept pipeline InputObject values that describe the target and expose a
ScriptBlock property.

With -Path or -LiteralPath and -Lazy the command registers a completer script
without running it. The runtime entry for each target is a small stub that
imports the script through Import-CompleterScript on the first tab press,
replaces itself with the real completer, and delegates that first call to it.
The managed record reports State 'Pending' until then and 'Active' afterwards.
Under the default strict tier the targets are read from the script's literal
Register-ArgumentCompleter arguments, so the script is parsed but never
executed at registration time; the strict grammar itself runs when the script
loads, and a script that fails it moves to 'Failed' then. With -Trusted the
script is dot-sourced as-is
on first use and cannot be parsed safely, so the targets must be supplied with
-CommandName and -Native or -ParameterName.

If the script fails to load on the first tab press, the press returns no
completions, the runtime entry is removed so the completion engine's default
completion applies exactly as with no completer registered, and the managed
record moves to State 'Failed' with the error message in LoadError. Nothing is
written to the host. Registering the same target again with -Force retries the
load. Lazy loading runs entirely inside the ordinary completer call; it never
hooks key handlers, replaces TabExpansion2, or changes PSReadLine options.

.PARAMETER InputObject
Supplies one or more objects that describe completer targets. Input objects must
expose target metadata through Key, RegistrationKey, RuntimeKey, or
CommandName/ParameterName plus IsNative/Native, and must expose a ScriptBlock
property whose value is a script block. When only a key is supplied and no
IsNative/Native property is present, a key without a colon is treated as a
native command, and a key with a colon is treated as a 'Command:Parameter'
target unless the text after its last colon contains a path separator, in which
case it is treated as a native command path such as 'C:\tools\example.exe'. An
explicit IsNative/Native property always wins. ScriptPath or SourcePath and
Trusted properties, such as those on Import-CompleterScript records, are
carried onto the managed record.

.PARAMETER CommandName
Specifies one or more command names whose completers should be registered.
With -Lazy the parameter names the targets the script owns; it is required
with -Trusted and optional under the strict tier, where every name given must
be one the script registers.

.PARAMETER ParameterName
Specifies one or more parameter names for command-parameter completer
registrations.

.PARAMETER Native
Registers native completers for the commands instead of parameter completers.

.PARAMETER ScriptBlock
Provides the completer script block to register. When multiple targets are
supplied through arrays, the same script block is reused for each target.

.PARAMETER Path
The path to one completer script file to register lazily. Wildcards are
supported but must resolve to a single file.

.PARAMETER LiteralPath
The literal path to one completer script file to register lazily. Wildcards
are not expanded.

.PARAMETER Lazy
Registers a stub for each target of the script instead of running the script
now. The script is imported on the first tab press for any of its targets.

.PARAMETER Trusted
Imports the script through the trusted tier on first use, dot-sourcing it as-is
without the strict grammar. The targets must be supplied with -CommandName and
-Native or -ParameterName because a trusted script is not parsed. The default
is the strict tier, which validates the script against the grammar when it
loads.

.PARAMETER Force
Replaces an existing managed or runtime registration for the same target with
the new completer, including a stale managed record whose live runtime value was
changed outside this module and a Failed lazy record whose load should be
retried.

.PARAMETER PassThru
Returns the managed registration records that were created or reused.

.OUTPUTS
System.Management.Automation.PSCustomObject
When -PassThru is used, returns CompleterActions.CompleterRegistration records.

.EXAMPLE
PS> Register-CompleterRegistration -CommandName demoexe -Native -ScriptBlock $nativeScriptBlock

Registers a native completer for demoexe with a script block that is already in
memory.

.EXAMPLE
PS> Register-CompleterRegistration -Path .\git_completer.ps1 -Lazy -PassThru

Reads the targets from the script's Register-ArgumentCompleter calls, registers
a stub for each of them, and returns the Pending records. The script runs the
first time tab completion is requested for one of its targets.

.EXAMPLE
PS> Register-CompleterRegistration -Path .\git_completer.ps1 -Lazy -Trusted -CommandName git, git.exe -Native

Registers a script that needs the trusted tier lazily. The targets are named
explicitly because a trusted script is not parsed.

.EXAMPLE
PS> Get-CompleterRegistration -ManagedOnly | Where-Object State -eq Failed | ForEach-Object { Register-CompleterRegistration -LiteralPath $_.ScriptPath -Lazy -Trusted:$_.Trusted -CommandName $_.CommandName -Native:$_.IsNative -Force }

Retries every lazy registration whose script failed to load, after the scripts
have been fixed.
#>
function Register-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'InputObject', ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [Alias('IsNative')]
        [switch] $Native,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'LazyPath')]
        [Parameter(Mandatory, ParameterSetName = 'LazyLiteralPath')]
        [switch] $Lazy,

        [Parameter(ParameterSetName = 'LazyPath')]
        [Parameter(ParameterSetName = 'LazyLiteralPath')]
        [switch] $Trusted,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    process
    {
        $resolvedInputs = @()
        $isLazy = $PSCmdlet.ParameterSetName -in 'LazyPath', 'LazyLiteralPath'

        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'InputObject')
            {
                $resolvedInputs = @($InputObject | Resolve-CompleterInputObject -RequireScriptBlock)
            }
            elseif ($isLazy)
            {
                $pathParameters = if ($PSCmdlet.ParameterSetName -eq 'LazyLiteralPath') { @{ LiteralPath = $LiteralPath } } else { @{ Path = $Path } }
                $resolvedPaths = @(Resolve-CompleterScriptPath @pathParameters)

                if ($resolvedPaths.Count -ne 1)
                {
                    throw "Lazy registration takes one completer script per call, but the path resolved to $($resolvedPaths.Count) files."
                }

                $scriptPath = $resolvedPaths[0]
                $explicitTargets = @()

                if ($PSBoundParameters.ContainsKey('CommandName'))
                {
                    if ($Native)
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -Native)
                    }
                    elseif ($PSBoundParameters.ContainsKey('ParameterName'))
                    {
                        $explicitTargets = @(Resolve-CompleterTargetList -CommandName $CommandName -ParameterName $ParameterName)
                    }
                    else
                    {
                        throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                    }
                }
                elseif ($Native -or $PSBoundParameters.ContainsKey('ParameterName'))
                {
                    throw 'Lazy registration targets are named with -CommandName plus -Native or -ParameterName.'
                }

                if ($Trusted)
                {
                    if ($explicitTargets.Count -eq 0)
                    {
                        throw "-Trusted lazy registration requires explicit targets: a trusted script is not parsed, so its targets cannot be derived from '$scriptPath'. Pass -CommandName with -Native or -ParameterName."
                    }

                    $targets = $explicitTargets
                }
                else
                {
                    $derivedTargets = @(Get-CompleterScriptTarget -LiteralPath $scriptPath)

                    if ($explicitTargets.Count -eq 0)
                    {
                        $targets = $derivedTargets
                    }
                    else
                    {
                        foreach ($explicitTarget in $explicitTargets)
                        {
                            if (@($derivedTargets.Key) -notcontains $explicitTarget.Key)
                            {
                                $derivedList = ($derivedTargets | ForEach-Object { "'$($_.RuntimeKey)'" }) -join ', '
                                throw "The script '$scriptPath' does not register a completer for '$($explicitTarget.RuntimeKey)'. It registers: $derivedList."
                            }
                        }

                        $targets = $explicitTargets
                    }
                }

                foreach ($target in $targets)
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = New-CompleterLazyStub -Key $target.Key
                        ImportModule = $null
                        ScriptPath = $scriptPath
                        Trusted = [bool] $Trusted
                    }
                }
            }
            else
            {
                $targetParameters = @{}

                switch ($PSCmdlet.ParameterSetName)
                {
                    'Native'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['Native'] = $true
                        break
                    }

                    'CommandParameter'
                    {
                        $targetParameters['CommandName'] = $CommandName
                        $targetParameters['ParameterName'] = $ParameterName
                        break
                    }
                }

                foreach ($target in @(Resolve-CompleterTargetList @targetParameters))
                {
                    $resolvedInputs += [pscustomobject] [ordered] @{
                        Target = $target
                        ScriptBlock = $ScriptBlock
                        ImportModule = $null
                        ScriptPath = $null
                        Trusted = $false
                    }
                }
            }

            foreach ($resolvedInput in $resolvedInputs)
            {
                $target = $resolvedInput.Target
                $targetScriptBlock = $resolvedInput.ScriptBlock
                $targetImportModule = $resolvedInput.ImportModule
                $targetScriptPath = $resolvedInput.ScriptPath
                $targetTrusted = [bool] $resolvedInput.Trusted
                $targetState = if ($isLazy) { 'Pending' } else { 'Active' }

                try
                {
                    $conflict = Resolve-CompleterRegistrationConflict -Target $target -ScriptText $targetScriptBlock.ToString() -ScriptPath $targetScriptPath -Trusted:$targetTrusted -Lazy:$isLazy -Force:$Force

                    if ($null -ne $conflict.Problem)
                    {
                        throw $conflict.Problem
                    }

                    if ($conflict.IsExisting)
                    {
                        if ($PassThru)
                        {
                            $PSCmdlet.WriteObject($conflict.ManagedRegistration)
                        }

                        continue
                    }

                    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
                    {
                        continue
                    }

                    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $targetScriptBlock -Source 'Managed' -ImportModule $targetImportModule -State $targetState -ScriptPath $targetScriptPath -Trusted:$targetTrusted
                    $registration = Add-CompleterRegistration -Registration $registration -Conflict $conflict

                    if ($PassThru)
                    {
                        $PSCmdlet.WriteObject($registration)
                    }
                }
                catch
                {
                    throw "Failed to register the completer '$($target.RuntimeKey)'. $($_.Exception.Message)"
                }
            }
        }
        finally
        {
            $resolvedInputs = @()
        }
    }
}
