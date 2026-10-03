---
document type: module
Help Version: 1.0.0.0
HelpInfoUri:
Locale: en-US
Module Guid: 00000000-0000-0000-0000-000000000000
Module Name: CompleterActions
ms.date: 04/01/2026
PlatyPS schema version: 2024-05-01
title: CompleterActions Module
---

# CompleterActions Module

## Description

## CompleterActions

### [Export-CompleterSet](Export-CompleterSet.md)

Writes a completer set file from registrations that came from scripts.

### [Get-Completer](Get-Completer.md)

Gets completer registrations known to the module or discovered at runtime.

### [Import-CompleterScript](Import-CompleterScript.md)

Imports self-contained completer scripts into registration input objects.

### [Import-CompleterSet](Import-CompleterSet.md)

Validates a completer set file and registers every script it lists.

### [New-CompleterScript](New-CompleterScript.md)

Writes a completer script skeleton for a native command that passes Test-CompleterScript as written.

### [Register-Completer](Register-Completer.md)

Registers a managed PowerShell argument completer.

### [Reset-Completer](Reset-Completer.md)

Returns a Failed or Active script-backed completer to Pending, so its script loads again on the next tab press.

### [Test-CompleterRegistration](Test-CompleterRegistration.md)

Runs tab completion for an input against a registered completer target.

### [Test-CompleterScript](Test-CompleterScript.md)

Checks completer scripts against the strict import grammar and reports findings.

### [Test-CompleterSet](Test-CompleterSet.md)

Reports drift between a completer set file and the scripts on disk.

### [Unregister-Completer](Unregister-Completer.md)

Removes completer registrations from runtime and, when applicable, module state.
