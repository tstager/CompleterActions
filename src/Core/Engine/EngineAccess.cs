using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Reflection;

namespace CompleterActions.Internal;

/// <summary>
/// The module's single point of access to the non-public engine members that own the runtime
/// completer dictionaries. <see cref="Create"/> resolves the execution context and the two
/// dictionary properties once per import and keeps the handles; the PowerShell side reads and
/// writes the dictionaries through those handles and never resolves a member itself.
/// </summary>
public sealed class EngineAccess
{
    private const BindingFlags MemberFlags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
    private const string ExecutionContextFieldName = "_context";
    private const string ExecutionContextMemberName = "System.Management.Automation.EngineIntrinsics._context";
    private const string CustomPropertyName = "CustomArgumentCompleters";
    private const string NativePropertyName = "NativeArgumentCompleters";

    private EngineAccess(object executionContext, PropertyInfo customProperty, PropertyInfo nativeProperty, SemanticVersion engineVersion)
    {
        ExecutionContext = executionContext;
        CustomProperty = customProperty;
        NativeProperty = nativeProperty;
        EngineVersion = engineVersion;
    }

    /// <summary>The engine's execution context, which owns the completer dictionaries.</summary>
    public object ExecutionContext { get; }

    /// <summary>The handle of the execution context's <c>CustomArgumentCompleters</c> property.</summary>
    public PropertyInfo CustomProperty { get; }

    /// <summary>The handle of the execution context's <c>NativeArgumentCompleters</c> property.</summary>
    public PropertyInfo NativeProperty { get; }

    /// <summary>The way the engine is reached; always <see cref="EnginePath.Reflection"/> in this release.</summary>
    public EnginePath Path => EnginePath.Reflection;

    /// <summary>The version of the engine the members were resolved on.</summary>
    public SemanticVersion EngineVersion { get; }

    /// <summary>
    /// Runs the capability probe: resolves the execution context behind
    /// <paramref name="engineIntrinsics"/> (unless <paramref name="runtimeExecutionContext"/> is given)
    /// and the two completer dictionary properties on the context's type.
    /// </summary>
    /// <param name="engineIntrinsics">The <c>EngineIntrinsics</c> instance to inspect.</param>
    /// <param name="engineIntrinsicsType">The type to resolve the execution context field on.</param>
    /// <param name="runtimeExecutionContext">An already resolved execution context; when given, the field is not resolved.</param>
    /// <param name="engineVersion">The engine version the probe failure message names.</param>
    /// <returns>The handles for this import.</returns>
    /// <exception cref="InvalidOperationException">
    /// One or more members could not be resolved; the message names the engine version and every missing member.
    /// </exception>
    public static EngineAccess Create(object engineIntrinsics, Type engineIntrinsicsType, object? runtimeExecutionContext, SemanticVersion engineVersion)
    {
        ArgumentNullException.ThrowIfNull(engineIntrinsicsType);
        ArgumentNullException.ThrowIfNull(engineVersion);

        var missingMembers = new List<string>();
        object? executionContext = Unwrap(runtimeExecutionContext);
        PropertyInfo? customProperty = null;
        PropertyInfo? nativeProperty = null;

        if (executionContext is null)
        {
            try
            {
                executionContext = ResolveExecutionContext(engineIntrinsics, engineIntrinsicsType);
            }
            catch (Exception)
            {
                missingMembers.Add(ExecutionContextMemberName);
            }
        }

        if (executionContext is not null)
        {
            Type executionContextType = executionContext.GetType();
            customProperty = executionContextType.GetProperty(CustomPropertyName, MemberFlags);
            nativeProperty = executionContextType.GetProperty(NativePropertyName, MemberFlags);

            if (customProperty is null)
            {
                missingMembers.Add($"{executionContextType.FullName}.{CustomPropertyName}");
            }

            if (nativeProperty is null)
            {
                missingMembers.Add($"{executionContextType.FullName}.{NativePropertyName}");
            }
        }

        if (missingMembers.Count > 0 || executionContext is null || customProperty is null || nativeProperty is null)
        {
            string missingMemberList = string.Join("', '", missingMembers);

            throw new InvalidOperationException(
                $"CompleterActions cannot run on PowerShell {engineVersion}: the required runtime member(s) '{missingMemberList}' could not be resolved. Completer discovery depends on PowerShell internals; check for a module update that supports this engine version.");
        }

        return new EngineAccess(executionContext, customProperty, nativeProperty, engineVersion);
    }

    /// <summary>
    /// Resolves the engine's execution context from the non-public field behind <c>EngineIntrinsics</c>.
    /// </summary>
    /// <param name="engineIntrinsics">The <c>EngineIntrinsics</c> instance to read the field from.</param>
    /// <param name="engineIntrinsicsType">The type to resolve the field on.</param>
    /// <returns>The execution context.</returns>
    /// <exception cref="InvalidOperationException">The field does not exist, or its value is <see langword="null"/>.</exception>
    public static object ResolveExecutionContext(object engineIntrinsics, Type engineIntrinsicsType)
    {
        ArgumentNullException.ThrowIfNull(engineIntrinsicsType);

        FieldInfo? executionContextField = engineIntrinsicsType.GetField(ExecutionContextFieldName, MemberFlags);

        if (executionContextField is null)
        {
            throw new InvalidOperationException("Unable to access the PowerShell execution context field required for completer runtime discovery.");
        }

        object? executionContext = executionContextField.GetValue(Unwrap(engineIntrinsics));

        if (executionContext is null)
        {
            throw new InvalidOperationException("Unable to resolve the current PowerShell execution context.");
        }

        return executionContext;
    }

    // PowerShell passes a PSCustomObject argument still wrapped in its PSObject; unwrap it so the
    // probe sees the type a PowerShell caller sees.
    private static object? Unwrap(object? value) => value is PSObject wrapped ? wrapped.BaseObject : value;
}
