namespace CompleterActions;

/// <summary>
/// The state of a completer registration that the module tracks or discovers.
/// </summary>
public enum CompleterState
{
    /// <summary>A managed registration that is live in the runtime.</summary>
    Active,

    /// <summary>A managed registration whose runtime entry is gone.</summary>
    Stale,

    /// <summary>A runtime entry that replaced a managed registration.</summary>
    Conflicted,

    /// <summary>A lazy registration whose script has not loaded yet.</summary>
    Pending,

    /// <summary>A lazy registration whose script failed to load.</summary>
    Failed,

    /// <summary>A runtime entry that the module did not register.</summary>
    Discovered,
}
