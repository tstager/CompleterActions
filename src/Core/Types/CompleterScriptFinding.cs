using System.Diagnostics.CodeAnalysis;

namespace CompleterActions;

/// <summary>
/// A finding about a completer script or completer set, as <c>Test-CompleterScript</c> and
/// <c>Test-CompleterSet</c> emit it. Every string property defaults to an empty string and stores
/// an empty string when it is assigned <see langword="null"/>.
/// </summary>
public sealed class CompleterScriptFinding
{
    private string path = string.Empty;
    private string severity = string.Empty;
    private string construct = string.Empty;
    private string message = string.Empty;
    private string hint = string.Empty;

    /// <summary>The file the finding is about.</summary>
    [AllowNull]
    public string Path { get => path; set => path = value ?? string.Empty; }

    /// <summary>The line the finding starts on.</summary>
    public int Line { get; set; }

    /// <summary>The column the finding starts at.</summary>
    public int Column { get; set; }

    /// <summary>The severity: <c>Error</c> or <c>Warning</c>.</summary>
    [AllowNull]
    public string Severity { get => severity; set => severity = value ?? string.Empty; }

    /// <summary>The construct the finding is about.</summary>
    [AllowNull]
    public string Construct { get => construct; set => construct = value ?? string.Empty; }

    /// <summary>What is wrong.</summary>
    [AllowNull]
    public string Message { get => message; set => message = value ?? string.Empty; }

    /// <summary>How to fix it.</summary>
    [AllowNull]
    public string Hint { get => hint; set => hint = value ?? string.Empty; }
}
