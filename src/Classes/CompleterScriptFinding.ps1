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
