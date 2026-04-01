function Get-CompleterActionState
{
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $stateVariable = Get-Variable -Name 'CompleterActionState' -Scope Script -ErrorAction Ignore

    if ($null -eq $stateVariable)
    {
        $script:CompleterActionState = [ordered]@{
            SchemaVersion = 1
            Registrations = [ordered]@{}
        }

        return $script:CompleterActionState
    }

    if ($null -eq $script:CompleterActionState)
    {
        $script:CompleterActionState = [ordered]@{}
    }

    if ($script:CompleterActionState -isnot [System.Collections.IDictionary])
    {
        throw 'Module state variable ''CompleterActionState'' must be a dictionary-backed object.'
    }

    if (-not $script:CompleterActionState.Contains('SchemaVersion'))
    {
        $script:CompleterActionState['SchemaVersion'] = 1
    }

    if (-not $script:CompleterActionState.Contains('Registrations'))
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($null -eq $script:CompleterActionState['Registrations'])
    {
        $script:CompleterActionState['Registrations'] = [ordered]@{}
    }
    elseif ($script:CompleterActionState['Registrations'] -isnot [System.Collections.IDictionary])
    {
        throw 'Module state property ''Registrations'' must be a dictionary-backed object.'
    }

    return $script:CompleterActionState
}
