using System.Management.Automation.Language;

namespace CompleterActions.Internal;

/// <summary>
/// One construct of a completer script that the strict import grammar rejects, as
/// <see cref="StrictGrammar.Test"/> returns it. The module turns each one into a
/// <see cref="CompleterScriptFinding"/>. This type is not part of the supported surface.
/// </summary>
public sealed class GrammarFinding
{
    internal GrammarFinding(IScriptExtent extent, string construct, string message, string hint)
    {
        Extent = extent;
        Construct = construct;
        Message = message;
        Hint = hint;
    }

    /// <summary>The extent of the offending AST node; the finding's line and column are its start.</summary>
    public IScriptExtent Extent { get; }

    /// <summary>The offending construct, usually the AST node type name.</summary>
    public string Construct { get; }

    /// <summary>What is wrong.</summary>
    public string Message { get; }

    /// <summary>How to change the script so the finding goes away.</summary>
    public string Hint { get; }
}
