using System.Management.Automation;
using AllowNullAttribute = System.Diagnostics.CodeAnalysis.AllowNullAttribute;

namespace CompleterActions;

/// <summary>
/// A registration read from a completer script, as <c>Import-CompleterScript</c> emits it. Every
/// string property defaults to an empty string and stores an empty string when it is assigned
/// <see langword="null"/>.
/// </summary>
public sealed class ImportedCompleterRegistration
{
    private string key = string.Empty;
    private string registrationKey = string.Empty;
    private string runtimeKey = string.Empty;
    private string commandName = string.Empty;
    private string parameterName = string.Empty;
    private string targetType = string.Empty;
    private string source = string.Empty;
    private string path = string.Empty;
    private string sourcePath = string.Empty;
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

    /// <summary>The parameter the completer targets; empty on a native registration.</summary>
    [AllowNull]
    public string ParameterName { get => parameterName; set => parameterName = value ?? string.Empty; }

    /// <summary>Whether the completer is a native command completer.</summary>
    public bool IsNative { get; set; }

    /// <summary>Whether the script registered the completer with <c>-Native</c>.</summary>
    public bool Native { get; set; }

    /// <summary>The kind of completer.</summary>
    public CompleterType CompleterType { get; set; }

    /// <summary>The kind of target, as the module describes it.</summary>
    [AllowNull]
    public string TargetType { get => targetType; set => targetType = value ?? string.Empty; }

    /// <summary>Where the registration comes from.</summary>
    [AllowNull]
    public string Source { get => source; set => source = value ?? string.Empty; }

    /// <summary>Whether the script was imported with the trusted tier.</summary>
    public bool Trusted { get; set; }

    /// <summary>The path of the imported script.</summary>
    [AllowNull]
    public string Path { get => path; set => path = value ?? string.Empty; }

    /// <summary>The path the import was requested with.</summary>
    [AllowNull]
    public string SourcePath { get => sourcePath; set => sourcePath = value ?? string.Empty; }

    /// <summary>The module the completer script block is bound to, or <see langword="null"/>.</summary>
    public PSModuleInfo? ImportModule { get; set; }

    /// <summary>The completer script block, or <see langword="null"/>.</summary>
    public ScriptBlock? ScriptBlock { get; set; }

    /// <summary>The text of the completer script block.</summary>
    [AllowNull]
    public string ScriptText { get => scriptText; set => scriptText = value ?? string.Empty; }
}
