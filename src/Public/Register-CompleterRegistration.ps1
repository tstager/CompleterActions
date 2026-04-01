function Register-CompleterRegistration
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CommandParameter', ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter(Mandatory, ParameterSetName = 'CommandParameter')]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName,

        [Parameter(Mandatory, ParameterSetName = 'Native')]
        [switch] $Native,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    $target = if ($PSCmdlet.ParameterSetName -eq 'Native')
    {
        Resolve-CompleterTarget -CommandName $CommandName -Native
    }
    else
    {
        Resolve-CompleterTarget -CommandName $CommandName -ParameterName $ParameterName
    }

    $existingManagedRegistration = Find-ManagedCompleterRegistration -Key $target.Key
    $existingRuntimeRegistration = Find-RuntimeCompleterRegistration -Key $target.Key

    if ($null -ne $existingManagedRegistration -and -not $Force)
    {
        if ($existingManagedRegistration.ScriptText -eq $ScriptBlock.ToString())
        {
            if ($PassThru)
            {
                return $existingManagedRegistration
            }

            return
        }

        throw "A module-managed completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if ($null -eq $existingManagedRegistration -and $null -ne $existingRuntimeRegistration -and -not $Force)
    {
        throw "A runtime completer registration already exists for '$($target.RuntimeKey)'. Use -Force to replace it."
    }

    if (-not $PSCmdlet.ShouldProcess($target.RuntimeKey, 'Register completer registration'))
    {
        return
    }

    if ($Force)
    {
        if ($null -ne $existingManagedRegistration)
        {
            $null = Remove-ManagedCompleterRegistration -Key $target.Key
        }

        if ($null -ne $existingRuntimeRegistration)
        {
            $null = Remove-RuntimeCompleterRegistration -Key $target.Key
        }
    }

    if ($target.IsNative)
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -Native -ScriptBlock $ScriptBlock
    }
    else
    {
        Register-ArgumentCompleter -CommandName $target.CommandName -ParameterName $target.ParameterName -ScriptBlock $ScriptBlock
    }

    $registration = New-CompleterRegistrationRecord -Target $target -ScriptBlock $ScriptBlock -Source 'Managed'
    $registration = Add-ManagedCompleterRegistration -Registration $registration

    if ($PassThru)
    {
        return $registration
    }
}
