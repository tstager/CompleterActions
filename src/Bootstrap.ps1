# Import-time work shared by the source root module and the packaged module.
Assert-CompleterRuntimeCapability
$null = Get-CompleterActionState
$script:CompleterLazyLoadsInProgress = [System.Collections.Generic.HashSet[string]]::new()
$script:CompleterDeprecationWarningsIssued = [System.Collections.Generic.HashSet[string]]::new()
New-Alias -Name 'Get-CompleterRegistration' -Value 'Get-CompleterRegistrationLegacy'
New-Alias -Name 'Register-CompleterRegistration' -Value 'Register-CompleterRegistrationLegacy'
New-Alias -Name 'Unregister-CompleterRegistration' -Value 'Unregister-CompleterRegistrationLegacy'
