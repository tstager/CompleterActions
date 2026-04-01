function Find-RuntimeCompleterRegistration
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Native', Justification = 'The switch is used to bind the native-specific parameter set.')]
    [OutputType([pscustomobject], [System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [ValidateNotNullOrEmpty()]
        [string] $Key,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native
    )

    $runtime = Get-CompleterRuntime

    if ($PSCmdlet.ParameterSetName -eq 'All')
    {
        $registrations = [System.Collections.Generic.List[object]]::new()

        if ($null -ne $runtime.NativeArgumentCompleters)
        {
            foreach ($entry in $runtime.NativeArgumentCompleters.GetEnumerator())
            {
                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key) -Native
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered'))
            }
        }

        if ($null -ne $runtime.CustomArgumentCompleters)
        {
            foreach ($entry in $runtime.CustomArgumentCompleters.GetEnumerator())
            {
                $target = Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key)
                $registrations.Add((New-CompleterRegistrationRecord -Target $target -ScriptBlock $entry.Value -Source 'Discovered'))
            }
        }

        return $registrations
    }

    $target = switch ($PSCmdlet.ParameterSetName)
    {
        'ByKey'
        {
            $normalizedKey = Get-CompleterRegistrationKey -RuntimeKey $Key

            if ($null -ne $runtime.NativeArgumentCompleters)
            {
                foreach ($entry in $runtime.NativeArgumentCompleters.GetEnumerator())
                {
                    if ((Get-CompleterRegistrationKey -RuntimeKey ([string] $entry.Key)) -eq $normalizedKey)
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key) -Native) -ScriptBlock $entry.Value -Source 'Discovered'
                    }
                }
            }

            if ($null -ne $runtime.CustomArgumentCompleters)
            {
                foreach ($entry in $runtime.CustomArgumentCompleters.GetEnumerator())
                {
                    if ((Get-CompleterRegistrationKey -RuntimeKey ([string] $entry.Key)) -eq $normalizedKey)
                    {
                        return New-CompleterRegistrationRecord -Target (Resolve-CompleterTarget -RuntimeKey ([string] $entry.Key)) -ScriptBlock $entry.Value -Source 'Discovered'
                    }
                }
            }

            return
        }

        'Native'
        {
            if (-not $Native)
            {
                throw 'Native target resolution requires the -Native switch.'
            }

            Resolve-CompleterTarget -CommandName $CommandName -Native
            break
        }

        'CommandParameter'
        {
            Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
            break
        }
    }

    $dictionary = if ($target.IsNative) { $runtime.NativeArgumentCompleters } else { $runtime.CustomArgumentCompleters }

    if ($null -eq $dictionary -or -not $dictionary.ContainsKey($target.RuntimeKey))
    {
        return
    }

    return New-CompleterRegistrationRecord -Target $target -ScriptBlock $dictionary[$target.RuntimeKey] -Source 'Discovered'
}
