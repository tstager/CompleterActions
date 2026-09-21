class ImportedCompleterRegistration
{
    ImportedCompleterRegistration()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.ImportedCompleterRegistration')
    }

    [string] $Key
    [string] $RegistrationKey
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [bool] $IsNative
    [bool] $Native
    [CompleterType] $CompleterType
    [string] $TargetType
    [string] $Source
    [bool] $Trusted
    [string] $Path
    [string] $SourcePath
    [System.Management.Automation.PSModuleInfo] $ImportModule = $null
    [scriptblock] $ScriptBlock = $null
    [string] $ScriptText
}
