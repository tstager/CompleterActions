enum CompleterState
{
    Active
    Stale
    Conflicted
    Pending
    Failed
    Discovered
}

enum CompleterType
{
    Native
    Parameter
}

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
    [CompleterState] $State
    [bool] $IsManaged
    [bool] $IsRuntimeRegistered
    [string] $ScriptPath
    [bool] $Trusted
    [string] $LoadError
    [System.Management.Automation.PSModuleInfo] $ImportModule = $null
    [scriptblock] $ScriptBlock = $null
    [string] $ScriptText
}

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

class CompleterScriptFinding
{
    CompleterScriptFinding()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompleterScriptFinding')
    }

    [string] $Path
    [int] $Line
    [int] $Column
    [string] $Severity
    [string] $Construct
    [string] $Message
    [string] $Hint
}

class CompletionMatch
{
    CompletionMatch()
    {
        $this.PSObject.TypeNames.Insert(0, 'CompleterActions.CompletionMatch')
    }

    [string] $Key
    [string] $RuntimeKey
    [string] $CommandName
    [string] $ParameterName
    [bool] $IsNative
    [CompleterType] $CompleterType
    [string] $InputText
    [int] $CursorPosition
    [string] $CompletionText
    [string] $ListItemText
    [System.Management.Automation.CompletionResultType] $ResultType
    [string] $ToolTip
}
