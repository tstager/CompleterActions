using System.Management.Automation;
using AllowNullAttribute = System.Diagnostics.CodeAnalysis.AllowNullAttribute;

namespace CompleterActions;

/// <summary>
/// A completer registration record, as <c>Get-Completer</c>, <c>Register-Completer</c>, and the other
/// registration commands emit it. Every string property defaults to an empty string and stores an
/// empty string when it is assigned <see langword="null"/>.
/// </summary>
public sealed class CompleterRegistration
{
    private string key = string.Empty;
    private string registrationKey = string.Empty;
    private string runtimeKey = string.Empty;
    private string commandName = string.Empty;
    private string parameterName = string.Empty;
    private string targetType = string.Empty;
    private string source = string.Empty;
    private string scriptPath = string.Empty;
    private string loadError = string.Empty;
    private string scriptText = string.Empty;

    /// <summary>The module's key for the registration.</summary>
    [AllowNull]
    public string Key { get => key; set => key = value ?? string.Empty; }

    /// <summary>The key the module tracks the registration under.</summary>
    [AllowNull]
    public string RegistrationKey { get => registrationKey; set => registrationKey = value ?? string.Empty; }

    /// <summary>The key of the entry in the runtime's completer dictionary.</summary>
    [AllowNull]
    public string RuntimeKey { get => runtimeKey; set => runtimeKey = value ?? string.Empty; }

    /// <summary>The command the completer targets.</summary>
    [AllowNull]
    public string CommandName { get => commandName; set => commandName = value ?? string.Empty; }

    /// <summary>The parameter the completer targets; empty on a native record.</summary>
    [AllowNull]
    public string ParameterName { get => parameterName; set => parameterName = value ?? string.Empty; }

    /// <summary>Whether the completer is a native command completer.</summary>
    public bool IsNative { get; set; }

    /// <summary>The kind of completer.</summary>
    public CompleterType CompleterType { get; set; }

    /// <summary>The kind of target, as the module describes it.</summary>
    [AllowNull]
    public string TargetType { get => targetType; set => targetType = value ?? string.Empty; }

    /// <summary>Where the record comes from: <c>Managed</c> or <c>Discovered</c>.</summary>
    [AllowNull]
    public string Source { get => source; set => source = value ?? string.Empty; }

    /// <summary>The state of the registration.</summary>
    public CompleterState State { get; set; }

    /// <summary>Whether the module manages the registration.</summary>
    public bool IsManaged { get; set; }

    /// <summary>Whether the registration is live in the runtime's completer dictionary.</summary>
    public bool IsRuntimeRegistered { get; set; }

    /// <summary>The script the registration came from; empty without a script.</summary>
    [AllowNull]
    public string ScriptPath { get => scriptPath; set => scriptPath = value ?? string.Empty; }

    /// <summary>Whether the script was imported with the trusted tier.</summary>
    public bool Trusted { get; set; }

    /// <summary>Why a lazy registration failed to load; empty unless the state is <c>Failed</c>.</summary>
    [AllowNull]
    public string LoadError { get => loadError; set => loadError = value ?? string.Empty; }

    /// <summary>The module the completer script block is bound to, or <see langword="null"/>.</summary>
    public PSModuleInfo? ImportModule { get; set; }

    /// <summary>The completer script block, or <see langword="null"/>.</summary>
    public ScriptBlock? ScriptBlock { get; set; }

    /// <summary>The text of the completer script block.</summary>
    [AllowNull]
    public string ScriptText { get => scriptText; set => scriptText = value ?? string.Empty; }
}
