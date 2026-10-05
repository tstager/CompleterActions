namespace CompleterActions.Internal;

/// <summary>
/// The way the compiled layer reaches the engine's completer dictionaries, chosen once per import.
/// </summary>
public enum EnginePath
{
    /// <summary>The non-public engine members are resolved by reflection and their handles kept.</summary>
    Reflection,
}
