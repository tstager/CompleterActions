function Get-ManagedCompleterRegistrationTable
{
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    $state = Get-CompleterActionState
    $registrations = $state['Registrations']

    if ($registrations -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $registrations
}
