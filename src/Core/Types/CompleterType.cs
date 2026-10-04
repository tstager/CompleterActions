namespace CompleterActions;

/// <summary>
/// The kind of argument completer a registration targets.
/// </summary>
public enum CompleterType
{
    /// <summary>A native command completer, registered with <c>-Native</c>.</summary>
    Native,

    /// <summary>A parameter completer for a command and parameter name.</summary>
    Parameter,
}
