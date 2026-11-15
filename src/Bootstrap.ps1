# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:CompleterImportModules = [System.Runtime.CompilerServices.ConditionalWeakTable[System.Management.Automation.PSModuleInfo, psobject]]::new()
$script:CompleterHelpProbeTimeoutSeconds = 5
