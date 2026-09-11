# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new()
