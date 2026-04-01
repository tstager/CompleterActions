function Add-ManagedCompleterRegistration
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject] $Registration
    )

    process
    {
        if ($Registration.PSObject.Properties.Match('Key').Count -eq 0 -or [string]::IsNullOrWhiteSpace([string] $Registration.Key))
        {
            throw 'Registration records must expose a non-empty Key property.'
        }

        $registrations = Get-ManagedCompleterRegistrationTable
        $registrations[[string] $Registration.Key] = $Registration

        return $registrations[[string] $Registration.Key]
    }
}
