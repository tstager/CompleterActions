class CompleterRegistration
{
    CompleterRegistration()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompleterRegistration')
    }

    [string] $Key
    [string] $RegistrationKey
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [bool] $IsNative
    [CompleterType] $CompleterType
    [string] $TargetType
    [string] $Source
    [string] $State
    [bool] $IsManaged
    [bool] $IsRuntimeRegistered
    [string] $ScriptPath
    [bool] $Trusted
    [string] $LoadError
    [System.Management.Automation.PSModuleInfo] $ImportModule = $null
    [scriptblock] $ScriptBlock = $null
    [string] $ScriptText
}
