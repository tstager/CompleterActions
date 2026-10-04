using System.Management.Automation;
using AllowNullAttribute = System.Diagnostics.CodeAnalysis.AllowNullAttribute;

namespace CompleterActions;

/// <summary>
/// A completion result produced through a registration, as <c>Test-CompleterRegistration</c> emits
/// it. Every string property defaults to an empty string and stores an empty string when it is
/// assigned <see langword="null"/>.
/// </summary>
public sealed class CompletionMatch
{
    private string key = string.Empty;
    private string runtimeKey = string.Empty;
    private string commandName = string.Empty;
    private string parameterName = string.Empty;
    private string inputText = string.Empty;
    private string completionText = string.Empty;
    private string listItemText = string.Empty;
    private string toolTip = string.Empty;

    /// <summary>The module's key for the registration that produced the result.</summary>
    [AllowNull]
    public string Key { get => key; set => key = value ?? string.Empty; }

    /// <summary>The key of the entry in the runtime's completer dictionary.</summary>
    [AllowNull]
    public string RuntimeKey { get => runtimeKey; set => runtimeKey = value ?? string.Empty; }

    /// <summary>The command the completer targets.</summary>
    [AllowNull]
    public string CommandName { get => commandName; set => commandName = value ?? string.Empty; }

    /// <summary>The parameter the completer targets; empty for a native completer.</summary>
    [AllowNull]
    public string ParameterName { get => parameterName; set => parameterName = value ?? string.Empty; }

    /// <summary>Whether the completer is a native command completer.</summary>
    public bool IsNative { get; set; }

    /// <summary>The kind of completer.</summary>
    public CompleterType CompleterType { get; set; }

    /// <summary>The input line that was completed.</summary>
    [AllowNull]
    public string InputText { get => inputText; set => inputText = value ?? string.Empty; }

    /// <summary>The cursor position the input was completed at.</summary>
    public int CursorPosition { get; set; }

    /// <summary>The text the completion inserts.</summary>
    [AllowNull]
    public string CompletionText { get => completionText; set => completionText = value ?? string.Empty; }

    /// <summary>The text the completion list shows.</summary>
    [AllowNull]
    public string ListItemText { get => listItemText; set => listItemText = value ?? string.Empty; }

    /// <summary>The kind of completion result.</summary>
    public CompletionResultType ResultType { get; set; }

    /// <summary>The tool tip of the completion result.</summary>
    [AllowNull]
    public string ToolTip { get => toolTip; set => toolTip = value ?? string.Empty; }
}
