using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation.Language;

namespace CompleterActions.Internal;

/// <summary>
/// The strict import grammar for completer scripts. A conforming script is self-contained, calls
/// <c>Register-ArgumentCompleter</c> at script scope, and uses literal values for the registration
/// target and script block. This type is not part of the supported surface.
/// </summary>
public static class StrictGrammar
{
    // PowerShell's -eq, -contains, and -in compare strings with the invariant culture, ignoring case.
    private static readonly StringComparer NameComparer = StringComparer.InvariantCultureIgnoreCase;

    private static readonly string[] AllowedImportCommands =
    {
        "Get-Variable",
        "Register-ArgumentCompleter",
        "Set-StrictMode",
    };

    private static readonly string[] RegisterParameters =
    {
        "CommandName",
        "ParameterName",
        "Native",
        "ScriptBlock",
    };

    private static readonly HashSet<TokenKind> AllowedTopLevelOperators = new()
    {
        TokenKind.And,
        TokenKind.Or,
        TokenKind.Xor,
        TokenKind.Ieq,
        TokenKind.Ine,
        TokenKind.Ige,
        TokenKind.Igt,
        TokenKind.Ilt,
        TokenKind.Ile,
        TokenKind.Ilike,
        TokenKind.Inotlike,
        TokenKind.Imatch,
        TokenKind.Inotmatch,
        TokenKind.Icontains,
        TokenKind.Inotcontains,
        TokenKind.Iin,
        TokenKind.Inotin,
        TokenKind.Ceq,
        TokenKind.Cne,
        TokenKind.Cge,
        TokenKind.Cgt,
        TokenKind.Clt,
        TokenKind.Cle,
        TokenKind.Clike,
        TokenKind.Cnotlike,
        TokenKind.Cmatch,
        TokenKind.Cnotmatch,
        TokenKind.Ccontains,
        TokenKind.Cnotcontains,
        TokenKind.Cin,
        TokenKind.Cnotin,
    };

    /// <summary>
    /// Checks a parsed completer script against the strict import grammar.
    /// </summary>
    /// <param name="ast">The script's AST, as the parser produced it from a script without parse errors.</param>
    /// <returns>Every unsupported construct, in source walk order; empty for a conforming script.</returns>
    /// <exception cref="ArgumentNullException"><paramref name="ast"/> is <see langword="null"/>.</exception>
    /// <exception cref="InvalidOperationException">The script has named blocks and no end block.</exception>
    public static IReadOnlyList<GrammarFinding> Test(ScriptBlockAst ast)
    {
        ArgumentNullException.ThrowIfNull(ast);

        var walk = new Walk(ast);
        walk.Run();
        return walk.Findings;
    }

    private static bool NameEquals(string? left, string right) => NameComparer.Equals(left, right);

    // One method per nested function of the 2.2.0 Test-CompleterScriptAst.ps1, in the same order.
    private sealed class Walk
    {
        private readonly ScriptBlockAst ast;

        internal Walk(ScriptBlockAst ast)
        {
            this.ast = ast;
        }

        internal List<GrammarFinding> Findings { get; } = new();

        private void AddFinding(IScriptExtent extent, string construct, string message, string hint)
        {
            Findings.Add(new GrammarFinding(extent, construct, message, hint));
        }

        private static string GetImportSafeExpressionHint(ExpressionAst expressionAst)
        {
            if (expressionAst is ConvertExpressionAst convertExpressionAst)
            {
                return GrammarMessages.TypeCastHint(convertExpressionAst.Type.Extent.Text);
            }

            if (expressionAst is MemberExpressionAst)
            {
                return GrammarMessages.MemberAccessHint;
            }

            return GrammarMessages.LiteralValuesHint;
        }

        private static string GetUnqualifiedFunctionName(string name)
        {
            return name.Substring(name.LastIndexOfAny(new[] { ':', '\\' }) + 1);
        }

        private void TestIsSupportedRegisterArgumentAst(Ast argumentAst, string parameterName)
        {
            if (NameEquals(parameterName, "ScriptBlock"))
            {
                if (argumentAst is not ScriptBlockExpressionAst)
                {
                    AddFinding(argumentAst.Extent, argumentAst.GetType().Name, GrammarMessages.LiteralScriptBlockMessage, GrammarMessages.LiteralScriptBlockHint);
                }

                return;
            }

            if (argumentAst is StringConstantExpressionAst)
            {
                return;
            }

            IReadOnlyList<Ast>? elements = null;
            if (argumentAst is ArrayLiteralAst arrayLiteralAst)
            {
                elements = arrayLiteralAst.Elements;
            }
            else if (argumentAst is ArrayExpressionAst arrayExpressionAst)
            {
                elements = GetLiteralArrayExpressionElement(arrayExpressionAst);
            }

            if (elements is not null && elements.All(element => element is StringConstantExpressionAst))
            {
                return;
            }

            AddFinding(argumentAst.Extent, argumentAst.GetType().Name, GrammarMessages.LiteralStringValuesMessage(parameterName), GrammarMessages.LiteralStringValuesHint(parameterName));
        }

        private static IReadOnlyList<Ast>? GetLiteralArrayExpressionElement(ArrayExpressionAst expressionAst)
        {
            StatementBlockAst statementBlockAst = expressionAst.SubExpression;
            if ((statementBlockAst.Traps?.Count ?? 0) != 0 || statementBlockAst.Statements.Count != 1)
            {
                return null;
            }

            if (statementBlockAst.Statements[0] is not PipelineAst pipelineAst || pipelineAst.PipelineElements.Count != 1)
            {
                return null;
            }

            if (pipelineAst.PipelineElements[0] is not CommandExpressionAst commandExpressionAst)
            {
                return null;
            }

            if (commandExpressionAst.Expression is ArrayLiteralAst arrayLiteralAst)
            {
                return arrayLiteralAst.Elements;
            }

            return new Ast[] { commandExpressionAst.Expression };
        }

        // The nested validators below define the closed top-level grammar. Everything outside
        // function bodies and literal -ScriptBlock arguments must be reachable through them, so
        // anything they do not recognize is reported before the script is executed.
        private void TestImportSafeExpressionAst(ExpressionAst expressionAst)
        {
            if (expressionAst is ConstantExpressionAst)
            {
                return;
            }

            if (expressionAst is VariableExpressionAst variableExpressionAst)
            {
                if (variableExpressionAst.Splatted)
                {
                    AddFinding(expressionAst.Extent, GrammarMessages.ConstructVariableExpressionAst, GrammarMessages.SplattingMessage, GrammarMessages.SplattingHint);
                }

                return;
            }

            if (expressionAst is ExpandableStringExpressionAst expandableStringExpressionAst)
            {
                foreach (ExpressionAst nestedExpression in expandableStringExpressionAst.NestedExpressions)
                {
                    if (nestedExpression is not VariableExpressionAst nestedVariable || nestedVariable.Splatted)
                    {
                        string typeName = nestedExpression.GetType().Name;
                        AddFinding(nestedExpression.Extent, typeName, GrammarMessages.ExpandableStringExpressionMessage(typeName), GrammarMessages.ExpandableStringExpressionHint);
                    }
                }

                return;
            }

            if (expressionAst is ArrayLiteralAst arrayLiteralAst)
            {
                foreach (ExpressionAst element in arrayLiteralAst.Elements)
                {
                    TestImportSafeExpressionAst(element);
                }

                return;
            }

            if (expressionAst is ArrayExpressionAst arrayExpressionAst)
            {
                if (arrayExpressionAst.SubExpression.Traps is { Count: > 0 } traps)
                {
                    AddFinding(traps[0].Extent, GrammarMessages.ConstructTrapStatementAst, GrammarMessages.TrapMessage, GrammarMessages.TrapHint);
                }

                foreach (StatementAst statement in arrayExpressionAst.SubExpression.Statements)
                {
                    TestImportSafeValueStatementAst(statement);
                }

                return;
            }

            if (expressionAst is HashtableAst hashtableAst)
            {
                foreach (Tuple<ExpressionAst, StatementAst> keyValuePair in hashtableAst.KeyValuePairs)
                {
                    TestImportSafeExpressionAst(keyValuePair.Item1);
                    TestImportSafeValueStatementAst(keyValuePair.Item2);
                }

                return;
            }

            if (expressionAst is ParenExpressionAst parenExpressionAst)
            {
                TestImportSafeValueStatementAst(parenExpressionAst.Pipeline);
                return;
            }

            if (expressionAst is UnaryExpressionAst unaryExpressionAst)
            {
                if (unaryExpressionAst.TokenKind is not (TokenKind.Not or TokenKind.Exclaim))
                {
                    AddFinding(expressionAst.Extent, GrammarMessages.ConstructUnaryExpressionAst, GrammarMessages.UnsupportedOperatorMessage(unaryExpressionAst.TokenKind.ToString()), GrammarMessages.UnaryOperatorHint);
                    return;
                }

                TestImportSafeExpressionAst(unaryExpressionAst.Child);
                return;
            }

            if (expressionAst is BinaryExpressionAst binaryExpressionAst)
            {
                if (!AllowedTopLevelOperators.Contains(binaryExpressionAst.Operator))
                {
                    AddFinding(expressionAst.Extent, GrammarMessages.ConstructBinaryExpressionAst, GrammarMessages.UnsupportedOperatorMessage(binaryExpressionAst.Operator.ToString()), GrammarMessages.BinaryOperatorHint);
                    return;
                }

                TestImportSafeExpressionAst(binaryExpressionAst.Left);
                TestImportSafeExpressionAst(binaryExpressionAst.Right);
                return;
            }

            string expressionTypeName = expressionAst.GetType().Name;
            AddFinding(expressionAst.Extent, expressionTypeName, GrammarMessages.UnsupportedExpressionMessage(expressionTypeName), GetImportSafeExpressionHint(expressionAst));
        }

        private void TestImportSafeCommandExpressionAst(CommandExpressionAst commandExpressionAst)
        {
            if (commandExpressionAst.Redirections.Count != 0)
            {
                RedirectionAst redirection = commandExpressionAst.Redirections[0];
                AddFinding(redirection.Extent, redirection.GetType().Name, GrammarMessages.RedirectionMessage, GrammarMessages.ExpressionRedirectionHint);
                return;
            }

            TestImportSafeExpressionAst(commandExpressionAst.Expression);
        }

        private void TestImportSafeCommandAst(CommandAst commandAst)
        {
            if (commandAst.Redirections.Count != 0)
            {
                RedirectionAst redirection = commandAst.Redirections[0];
                AddFinding(redirection.Extent, redirection.GetType().Name, GrammarMessages.RedirectionMessage, GrammarMessages.CommandRedirectionHint);
                return;
            }

            string? commandName = commandAst.GetCommandName();
            if (string.IsNullOrWhiteSpace(commandName))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.NonLiteralCommandMessage, GrammarMessages.NonLiteralCommandHint);
                return;
            }

            if (!AllowedImportCommands.Contains(commandName, NameComparer))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.UnsupportedCommandMessage(commandName), GrammarMessages.UnsupportedCommandHint(commandName));
                return;
            }

            if (NameEquals(commandName, "Register-ArgumentCompleter"))
            {
                // Register-ArgumentCompleter arguments are validated separately below.
                return;
            }

            foreach (CommandElementAst commandElement in commandAst.CommandElements.Skip(1))
            {
                if (commandElement is CommandParameterAst commandParameterAst)
                {
                    if (commandParameterAst.Argument is not null)
                    {
                        TestImportSafeExpressionAst(commandParameterAst.Argument);
                    }

                    continue;
                }

                TestImportSafeExpressionAst((ExpressionAst)commandElement);
            }
        }

        private void TestImportSafePipelineAst(PipelineAst pipelineAst, bool allowExpression)
        {
            if (pipelineAst.Background)
            {
                AddFinding(pipelineAst.Extent, GrammarMessages.ConstructPipelineAst, GrammarMessages.BackgroundPipelineMessage, GrammarMessages.BackgroundPipelineHint);
                return;
            }

            foreach (CommandBaseAst pipelineElement in pipelineAst.PipelineElements)
            {
                if (pipelineElement is CommandAst commandAst)
                {
                    TestImportSafeCommandAst(commandAst);
                    continue;
                }

                if (pipelineElement is CommandExpressionAst commandExpressionAst)
                {
                    if (allowExpression)
                    {
                        TestImportSafeCommandExpressionAst(commandExpressionAst);
                        continue;
                    }

                    string expressionTypeName = commandExpressionAst.Expression.GetType().Name;
                    AddFinding(pipelineElement.Extent, expressionTypeName, GrammarMessages.UnsupportedExpressionMessage(expressionTypeName), GetImportSafeExpressionHint(commandExpressionAst.Expression));
                    continue;
                }

                string elementTypeName = pipelineElement.GetType().Name;
                AddFinding(pipelineElement.Extent, elementTypeName, GrammarMessages.UnsupportedSyntaxMessage(elementTypeName), GrammarMessages.ScriptScopeHint);
            }
        }

        private void TestImportSafeValueStatementAst(StatementAst statementAst)
        {
            if (statementAst is PipelineAst pipelineAst)
            {
                TestImportSafePipelineAst(pipelineAst, allowExpression: true);
                return;
            }

            if (statementAst is CommandExpressionAst commandExpressionAst)
            {
                TestImportSafeCommandExpressionAst(commandExpressionAst);
                return;
            }

            string statementTypeName = statementAst.GetType().Name;
            AddFinding(statementAst.Extent, statementTypeName, GrammarMessages.UnsupportedSyntaxMessage(statementTypeName), GrammarMessages.ScriptScopeHint);
        }

        private void TestImportSafeStatementAst(StatementAst statementAst, bool allowAssignment)
        {
            if (statementAst is FunctionDefinitionAst)
            {
                return;
            }

            if (statementAst is IfStatementAst ifStatementAst)
            {
                foreach (Tuple<PipelineBaseAst, StatementBlockAst> clause in ifStatementAst.Clauses)
                {
                    if (clause.Item1 is not PipelineAst conditionAst)
                    {
                        string conditionTypeName = clause.Item1.GetType().Name;
                        AddFinding(clause.Item1.Extent, conditionTypeName, GrammarMessages.UnsupportedSyntaxMessage(conditionTypeName), GrammarMessages.ScriptScopeHint);
                        continue;
                    }

                    TestImportSafePipelineAst(conditionAst, allowExpression: true);
                    TestImportSafeStatementBlockAst(clause.Item2);
                }

                if (ifStatementAst.ElseClause is not null)
                {
                    TestImportSafeStatementBlockAst(ifStatementAst.ElseClause);
                }

                return;
            }

            if (statementAst is PipelineAst pipelineAst)
            {
                TestImportSafePipelineAst(pipelineAst, allowExpression: false);
                return;
            }

            if (statementAst is AssignmentStatementAst assignmentStatementAst)
            {
                if (!allowAssignment)
                {
                    AddFinding(statementAst.Extent, GrammarMessages.ConstructAssignmentStatementAst, GrammarMessages.AssignmentMessage, GrammarMessages.AssignmentHint);
                    return;
                }

                if (assignmentStatementAst.Operator != TokenKind.Equals)
                {
                    AddFinding(statementAst.Extent, GrammarMessages.ConstructAssignmentStatementAst, GrammarMessages.UnsupportedOperatorMessage(assignmentStatementAst.Operator.ToString()), GrammarMessages.AssignmentOperatorHint);
                    return;
                }

                ExpressionAst target = assignmentStatementAst.Left;
                if (target is not VariableExpressionAst targetVariable ||
                    targetVariable.Splatted ||
                    !(targetVariable.VariablePath.IsUnqualified || targetVariable.VariablePath.IsScript))
                {
                    AddFinding(target.Extent, target.GetType().Name, GrammarMessages.AssignmentTargetMessage(target.Extent.Text), GrammarMessages.AssignmentTargetHint);
                    return;
                }

                TestImportSafeValueStatementAst(assignmentStatementAst.Right);
                return;
            }

            string statementTypeName = statementAst.GetType().Name;
            AddFinding(statementAst.Extent, statementTypeName, GrammarMessages.UnsupportedSyntaxMessage(statementTypeName), GrammarMessages.ScriptScopeHint);
        }

        private void TestImportSafeStatementBlockAst(StatementBlockAst statementBlockAst)
        {
            if (statementBlockAst.Traps is { Count: > 0 } traps)
            {
                AddFinding(traps[0].Extent, GrammarMessages.ConstructTrapStatementAst, GrammarMessages.TrapMessage, GrammarMessages.TrapHint);
            }

            foreach (StatementAst statement in statementBlockAst.Statements)
            {
                TestImportSafeStatementAst(statement, allowAssignment: true);
            }
        }

        private void TestRegisterArgumentCompleterCommandAst(CommandAst commandAst)
        {
            Ast? ancestor = commandAst.Parent;
            while (ancestor is not null && !ReferenceEquals(ancestor, ast))
            {
                if (ancestor is FunctionDefinitionAst or ScriptBlockExpressionAst)
                {
                    AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.NestedRegistrationMessage, GrammarMessages.NestedRegistrationHint);
                    return;
                }

                ancestor = ancestor.Parent;
            }

            string? currentParameter = null;

            // The 2.2.0 walk kept these in an [ordered] dictionary, whose keys compare with the
            // current culture, ignoring case.
            var seenParameters = new HashSet<string>(StringComparer.CurrentCultureIgnoreCase);

            foreach (CommandElementAst commandElement in commandAst.CommandElements.Skip(1))
            {
                if (commandElement is CommandParameterAst commandParameterAst)
                {
                    string parameterName = commandParameterAst.ParameterName;
                    if (!RegisterParameters.Contains(parameterName, NameComparer))
                    {
                        AddFinding(commandElement.Extent, GrammarMessages.ConstructCommandParameterAst, GrammarMessages.UnsupportedRegisterParameterMessage(parameterName), GrammarMessages.UnsupportedRegisterParameterHint);
                        return;
                    }

                    if (commandParameterAst.Argument is not null)
                    {
                        if (NameEquals(parameterName, "Native"))
                        {
                            AddFinding(commandElement.Extent, GrammarMessages.ConstructCommandParameterAst, GrammarMessages.NativeArgumentMessage, GrammarMessages.NativeArgumentHint);
                            return;
                        }

                        TestIsSupportedRegisterArgumentAst(commandParameterAst.Argument, parameterName);
                        currentParameter = null;
                    }
                    else if (NameEquals(parameterName, "Native"))
                    {
                        currentParameter = null;
                    }
                    else
                    {
                        currentParameter = parameterName;
                    }

                    seenParameters.Add(parameterName);
                    continue;
                }

                if (commandElement is VariableExpressionAst { Splatted: true })
                {
                    AddFinding(commandElement.Extent, GrammarMessages.ConstructVariableExpressionAst, GrammarMessages.RegisterSplattingMessage, GrammarMessages.RegisterSplattingHint);
                    return;
                }

                if (string.IsNullOrWhiteSpace(currentParameter))
                {
                    AddFinding(commandElement.Extent, commandElement.GetType().Name, GrammarMessages.PositionalArgumentMessage, GrammarMessages.PositionalArgumentHint);
                    return;
                }

                TestIsSupportedRegisterArgumentAst(commandElement, currentParameter);
                currentParameter = null;
            }

            if (!string.IsNullOrWhiteSpace(currentParameter))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.MissingArgumentMessage(currentParameter), GrammarMessages.MissingArgumentHint(currentParameter));
                return;
            }

            if (!seenParameters.Contains("CommandName"))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.MissingCommandNameMessage, GrammarMessages.MissingCommandNameHint);
            }

            if (!seenParameters.Contains("ScriptBlock"))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.MissingScriptBlockMessage, GrammarMessages.MissingScriptBlockHint);
            }

            if (seenParameters.Contains("Native") && seenParameters.Contains("ParameterName"))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.NativeAndParameterNameMessage, GrammarMessages.NativeAndParameterNameHint);
            }

            if (!seenParameters.Contains("Native") && !seenParameters.Contains("ParameterName"))
            {
                AddFinding(commandAst.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.MissingCompleterKindMessage, GrammarMessages.MissingCompleterKindHint);
            }
        }

        internal void Run()
        {
            foreach (UsingStatementAst usingStatement in ast.UsingStatements)
            {
                if (usingStatement.UsingStatementKind != UsingStatementKind.Namespace)
                {
                    AddFinding(usingStatement.Extent, GrammarMessages.ConstructUsingStatementAst, GrammarMessages.UsingStatementMessage(usingStatement.UsingStatementKind.ToString().ToLowerInvariant()), GrammarMessages.UsingStatementHint);
                }
            }

            if (ast.ScriptRequirements is not null)
            {
                if (ast.ScriptRequirements.RequiredModules is { Count: > 0 })
                {
                    AddFinding(ast.Extent, GrammarMessages.ConstructScriptRequirements, GrammarMessages.RequiresModulesMessage, GrammarMessages.RequiresModulesHint);
                }

                if (ast.ScriptRequirements.RequiredAssemblies is { Count: > 0 })
                {
                    AddFinding(ast.Extent, GrammarMessages.ConstructScriptRequirements, GrammarMessages.RequiresAssemblyMessage, GrammarMessages.RequiresAssemblyHint);
                }
            }

            foreach (Ast? namedBlock in new Ast?[] { ast.ParamBlock, ast.BeginBlock, ast.ProcessBlock, ast.DynamicParamBlock, ast.CleanBlock })
            {
                if (namedBlock is not null)
                {
                    string blockTypeName = namedBlock.GetType().Name;
                    AddFinding(namedBlock.Extent, blockTypeName, GrammarMessages.UnsupportedSyntaxMessage(blockTypeName), GrammarMessages.NamedBlockHint);
                }
            }

            if (ast.EndBlock?.Traps is { Count: > 0 } traps)
            {
                AddFinding(traps[0].Extent, GrammarMessages.ConstructTrapStatementAst, GrammarMessages.TrapMessage, GrammarMessages.TrapHint);
            }

            if (ast.EndBlock is null)
            {
                throw new InvalidOperationException(GrammarMessages.MissingEndBlockError);
            }

            foreach (StatementAst statement in ast.EndBlock.Statements)
            {
                TestImportSafeStatementAst(statement, allowAssignment: false);
            }

            // One pass collects what the 2.2.0 walk found with three FindAll calls; FindAll visits in
            // the same order, so each list keeps the order the walk reported it in.
            var collector = new NodeCollector();
            ast.Visit(collector);

            // A function definition keeps its scope qualifier in FunctionDefinitionAst.Name, so
            // 'function script:Get-Variable' shadows Get-Variable in the capture scope while its
            // Name is not 'Get-Variable'. Definitions are therefore compared by their unqualified
            // name: the text after the last scope or module qualifier. Command calls are
            // deliberately not normalized the same way, because a qualified call such as
            // 'script:Get-Variable' or 'Foo\Get-Variable' is not the allowlisted built-in and the
            // exact-match allowlist above already rejects it.
            foreach (FunctionDefinitionAst functionOverride in collector.FunctionOverrides)
            {
                string unqualifiedName = GetUnqualifiedFunctionName(functionOverride.Name);
                AddFinding(functionOverride.Extent, GrammarMessages.ConstructFunctionDefinitionAst, GrammarMessages.FunctionOverrideMessage(functionOverride.Name), GrammarMessages.FunctionOverrideHint(unqualifiedName));
            }

            foreach (CommandAst dotSourcedCommand in collector.DotSourcedCommands)
            {
                AddFinding(dotSourcedCommand.Extent, GrammarMessages.ConstructCommandAst, GrammarMessages.DotSourceMessage, GrammarMessages.DotSourceHint);
            }

            if (collector.RegisterCommands.Count == 0)
            {
                AddFinding(ast.Extent, GrammarMessages.ConstructScriptBlockAst, GrammarMessages.MissingRegistrationMessage, GrammarMessages.MissingRegistrationHint);
            }

            foreach (CommandAst registerCommand in collector.RegisterCommands)
            {
                TestRegisterArgumentCompleterCommandAst(registerCommand);
            }
        }

        private sealed class NodeCollector : AstVisitor2
        {
            internal List<FunctionDefinitionAst> FunctionOverrides { get; } = new();

            internal List<CommandAst> DotSourcedCommands { get; } = new();

            internal List<CommandAst> RegisterCommands { get; } = new();

            public override AstVisitAction VisitFunctionDefinition(FunctionDefinitionAst functionDefinitionAst)
            {
                if (AllowedImportCommands.Contains(GetUnqualifiedFunctionName(functionDefinitionAst.Name), NameComparer))
                {
                    FunctionOverrides.Add(functionDefinitionAst);
                }

                return AstVisitAction.Continue;
            }

            public override AstVisitAction VisitCommand(CommandAst commandAst)
            {
                if (commandAst.InvocationOperator == TokenKind.Dot)
                {
                    DotSourcedCommands.Add(commandAst);
                }

                if (NameEquals(commandAst.GetCommandName(), "Register-ArgumentCompleter"))
                {
                    RegisterCommands.Add(commandAst);
                }

                return AstVisitAction.Continue;
            }
        }
    }
}
