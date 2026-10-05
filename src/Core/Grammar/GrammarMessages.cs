namespace CompleterActions.Internal;

/// <summary>
/// The texts of the strict import grammar's findings, copied character for character from the
/// <c>Add-Finding</c> calls of the 2.2.0 <c>Test-CompleterScriptAst.ps1</c>. Each interpolated
/// PowerShell string is a format method that takes the interpolated values in the same places.
/// </summary>
internal static class GrammarMessages
{
    internal const string ConstructVariableExpressionAst = "VariableExpressionAst";
    internal const string ConstructTrapStatementAst = "TrapStatementAst";
    internal const string ConstructUnaryExpressionAst = "UnaryExpressionAst";
    internal const string ConstructBinaryExpressionAst = "BinaryExpressionAst";
    internal const string ConstructCommandAst = "CommandAst";
    internal const string ConstructPipelineAst = "PipelineAst";
    internal const string ConstructAssignmentStatementAst = "AssignmentStatementAst";
    internal const string ConstructCommandParameterAst = "CommandParameterAst";
    internal const string ConstructUsingStatementAst = "UsingStatementAst";
    internal const string ConstructScriptRequirements = "ScriptRequirements";
    internal const string ConstructFunctionDefinitionAst = "FunctionDefinitionAst";
    internal const string ConstructScriptBlockAst = "ScriptBlockAst";

    // $scriptScopeHint
    internal const string ScriptScopeHint = "Script scope may only contain Set-StrictMode, Get-Variable, Register-ArgumentCompleter, function definitions, and guarded if statements. Move this into a function that the completer calls lazily.";

    // Get-ImportSafeExpressionHint
    internal static string TypeCastHint(string typeText) => $"A type cast runs at import time. Move the {typeText} literal into a lazy initializer inside a function.";

    internal const string MemberAccessHint = "A [type]::Member or object member access runs at import time. Move it into a lazy initializer inside a function.";

    internal const string LiteralValuesHint = "Keep script-scope values literal (strings, numbers, arrays, and hashtables) and compute everything else lazily inside a function.";

    // Test-IsSupportedRegisterArgumentAst
    internal const string LiteralScriptBlockMessage = "The script must provide a literal script block for -ScriptBlock.";

    internal const string LiteralScriptBlockHint = "Pass the completer body as a literal { ... } script block and move any shared code into functions that the script block calls.";

    internal static string LiteralStringValuesMessage(string parameterName) => $"The script must use literal string values for -{parameterName}.";

    internal static string LiteralStringValuesHint(string parameterName) => $"Replace the -{parameterName} value with a literal string or a literal @('name', 'name.exe') array; a value computed at import time cannot be analyzed.";

    // Test-ImportSafeExpressionAst
    internal const string SplattingMessage = "The script uses argument splatting at script scope.";

    internal const string SplattingHint = "Spell out each parameter explicitly; Import-CompleterScript requires explicit top-level command arguments.";

    internal static string ExpandableStringExpressionMessage(string typeName) => $"The script contains unsupported top-level expression '{typeName}' inside an expandable string.";

    internal const string ExpandableStringExpressionHint = "Use only plain variables inside script-scope strings, or build the string lazily inside a function.";

    internal const string TrapMessage = "The script contains unsupported top-level syntax 'TrapStatementAst'.";

    internal const string TrapHint = "Move trap statements into function bodies.";

    internal static string UnsupportedOperatorMessage(string operatorName) => $"The script uses unsupported top-level operator '{operatorName}'.";

    internal const string UnaryOperatorHint = "Only -not and ! are supported at script scope; compute other values lazily inside a function.";

    internal const string BinaryOperatorHint = "Only comparison and logical operators are supported at script scope; compute other values lazily inside a function.";

    internal static string UnsupportedExpressionMessage(string typeName) => $"The script contains unsupported top-level expression '{typeName}'.";

    // Test-ImportSafeCommandExpressionAst and Test-ImportSafeCommandAst
    internal const string RedirectionMessage = "The script uses redirection at script scope.";

    internal const string ExpressionRedirectionHint = "Remove the redirection, or move the expression into a function that the completer calls lazily.";

    internal const string CommandRedirectionHint = "Remove the redirection, or move the command into a function that the completer calls lazily.";

    internal const string NonLiteralCommandMessage = "The script uses a non-literal top-level command.";

    internal const string NonLiteralCommandHint = "Call commands by their literal name at script scope, or move the call into a function that the completer calls lazily.";

    internal static string UnsupportedCommandMessage(string commandName) => $"The script uses unsupported top-level command '{commandName}'.";

    internal static string UnsupportedCommandHint(string commandName) => $"Only Set-StrictMode, Get-Variable, and Register-ArgumentCompleter may run at script scope. Move '{commandName}' into a function that the completer calls lazily.";

    // Test-ImportSafePipelineAst, Test-ImportSafeValueStatementAst, Test-ImportSafeStatementAst
    internal const string BackgroundPipelineMessage = "The script starts a background pipeline at script scope.";

    internal const string BackgroundPipelineHint = "Remove the & background operator; Import-CompleterScript does not support background execution.";

    internal static string UnsupportedSyntaxMessage(string typeName) => $"The script contains unsupported top-level syntax '{typeName}'.";

    internal const string AssignmentMessage = "The script uses a top-level assignment.";

    internal const string AssignmentHint = "Guard script-scope state with if (-not (Get-Variable -Name State -Scope Script -ErrorAction SilentlyContinue)) { $script:State = @{ ... } }, or initialize it lazily inside a function.";

    internal const string AssignmentOperatorHint = "Use plain = assignment for script-scope state.";

    internal static string AssignmentTargetMessage(string targetText) => $"The script assigns to unsupported target '{targetText}'.";

    internal const string AssignmentTargetHint = "Assign only to unqualified or $script: variables at script scope; drive-qualified and member targets change state outside the script at import time.";

    // Test-RegisterArgumentCompleterCommandAst
    internal const string NestedRegistrationMessage = "The script registers a completer from inside a nested function or script block.";

    internal const string NestedRegistrationHint = "Move the Register-ArgumentCompleter call to script scope; Import-CompleterScript only captures script-scope registrations.";

    internal static string UnsupportedRegisterParameterMessage(string parameterName) => $"The script uses unsupported Register-ArgumentCompleter parameter '-{parameterName}'.";

    internal const string UnsupportedRegisterParameterHint = "Use only -CommandName, -ParameterName, -Native, and -ScriptBlock.";

    internal const string NativeArgumentMessage = "The script uses an argument for -Native.";

    internal const string NativeArgumentHint = "Use the bare -Native switch.";

    internal const string RegisterSplattingMessage = "The script uses argument splatting for Register-ArgumentCompleter.";

    internal const string RegisterSplattingHint = "Spell out -CommandName, -ParameterName or -Native, and -ScriptBlock explicitly.";

    internal const string PositionalArgumentMessage = "The script uses positional Register-ArgumentCompleter arguments.";

    internal const string PositionalArgumentHint = "Name every argument: -CommandName, -ParameterName or -Native, and -ScriptBlock.";

    internal static string MissingArgumentMessage(string parameterName) => $"The script is missing the argument for -{parameterName}.";

    internal static string MissingArgumentHint(string parameterName) => $"Supply a literal value after -{parameterName}.";

    internal const string MissingCommandNameMessage = "The script is missing -CommandName in a Register-ArgumentCompleter call.";

    internal const string MissingCommandNameHint = "Add -CommandName with a literal command name or a literal array of command names.";

    internal const string MissingScriptBlockMessage = "The script is missing -ScriptBlock in a Register-ArgumentCompleter call.";

    internal const string MissingScriptBlockHint = "Add -ScriptBlock with a literal { ... } script block.";

    internal const string NativeAndParameterNameMessage = "The script combines -Native and -ParameterName.";

    internal const string NativeAndParameterNameHint = "Use -Native for a native command completer or -ParameterName for a command parameter completer, not both.";

    internal const string MissingCompleterKindMessage = "The script does not identify whether the completer is native or parameter-based.";

    internal const string MissingCompleterKindHint = "Add -Native for a native command completer or -ParameterName for a command parameter completer.";

    // Script-level checks
    internal static string UsingStatementMessage(string kind) => $"The script uses a 'using {kind}' statement.";

    internal const string UsingStatementHint = "Remove the using statement; only using namespace is supported. Load the module or assembly lazily inside a function with Import-Module or Add-Type.";

    internal const string RequiresModulesMessage = "The script uses a '#requires -Modules' directive.";

    internal const string RequiresModulesHint = "Remove the directive; the required modules are imported, and their top-level code executes, when the script is dot-sourced. Import the module lazily inside a function instead.";

    internal const string RequiresAssemblyMessage = "The script uses a '#requires -Assembly' directive.";

    internal const string RequiresAssemblyHint = "Remove the directive; the required assemblies are loaded when the script is dot-sourced. Load the assembly lazily inside a function with Add-Type instead.";

    internal const string NamedBlockHint = "Remove the param, begin, process, dynamicparam, or clean block; a completer script is a flat script that defines functions and registers completers.";

    internal static string FunctionOverrideMessage(string name) => $"The script defines its own {name} function.";

    internal static string FunctionOverrideHint(string unqualifiedName) => $"Rename the function; Import-CompleterScript only supports scripts that call the built-in {unqualifiedName} directly, and a scope-qualified definition such as script:{unqualifiedName} or global:{unqualifiedName} shadows it in the same way.";

    internal const string DotSourceMessage = "The script dot-sources another script.";

    internal const string DotSourceHint = "Inline the dot-sourced content, or move the dot-source into a function that the completer calls lazily; Import-CompleterScript only supports self-contained completer scripts.";

    internal const string MissingRegistrationMessage = "The script does not contain a Register-ArgumentCompleter call.";

    internal const string MissingRegistrationHint = "Add a script-scope Register-ArgumentCompleter call with -CommandName, -ScriptBlock, and either -Native or -ParameterName.";

    // The 2.2.0 walk passed each end-block statement to a [ValidateNotNull()] parameter named
    // StatementAst. A script with named blocks and no end block has no end block to walk, and the
    // walk failed with the parameter binder's message instead of returning findings.
    internal const string MissingEndBlockError = "Cannot validate argument on parameter 'StatementAst'. The argument is null. Provide a valid value for the argument, and then try running the command again.";
}
