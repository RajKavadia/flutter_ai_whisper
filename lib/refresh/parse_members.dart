/// Syntactic extraction of classes and methods from Dart source.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_ai_whisper/refresh/dart_member.dart';

const _lifecycle = <String>{
  'build',
  'initState',
  'dispose',
  'didChangeDependencies',
  'didUpdateWidget',
  'reassemble',
  'deactivate',
  'activate',
  'createState',
  'debugFillProperties',
  'setState',
};

const _widgetSupers = <String>{
  'Widget',
  'StatelessWidget',
  'StatefulWidget',
  'InheritedWidget',
  'ProxyWidget',
  'RenderObjectWidget',
  'SingleChildRenderObjectWidget',
  'MultiChildRenderObjectWidget',
  'LeafRenderObjectWidget',
};

/// Parses [source] and returns the class methods and top-level functions.
///
/// Syntax errors yield whatever declarations the parser recovered. The
/// analysis gate is what decides whether those declarations are safe to call.
List<DartMember> parseDartMembers(String source, {required String libraryUri}) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final members = <DartMember>[];
  for (final declaration in unit.declarations) {
    if (declaration is ClassDeclaration) {
      members.addAll(_classMembers(declaration, libraryUri));
    } else if (declaration is FunctionDeclaration) {
      final member = _functionMember(declaration, libraryUri);
      if (member != null) members.add(member);
    }
  }
  return members;
}

List<DartMember> _classMembers(
  ClassDeclaration declaration,
  String libraryUri,
) {
  final className = declaration.namePart.typeName.lexeme;
  final superclass = declaration.extendsClause?.superclass;
  final superName = superclass?.name.lexeme;
  final kind = _kind(className, superName);
  final widgetName = kind == DartMemberKind.state
      ? _firstTypeArgument(superclass)
      : null;
  final members = <DartMember>[];
  for (final member in declaration.body.members) {
    if (member is! MethodDeclaration) continue;
    if (member.isGetter || member.isSetter || member.isOperator) continue;
    final methodName = member.name.lexeme;
    final callable =
        !_lifecycle.contains(methodName) &&
        member.body is! EmptyFunctionBody &&
        _callable(member.parameters);
    members.add(
      DartMember(
        libraryUri: libraryUri,
        className: className,
        methodName: methodName,
        body: member.toString(),
        kind: kind,
        widgetName: widgetName,
        isStatic: member.isStatic,
        callable: callable,
      ),
    );
  }
  return members;
}

DartMember? _functionMember(
  FunctionDeclaration declaration,
  String libraryUri,
) {
  if (declaration.isGetter || declaration.isSetter) return null;
  final expression = declaration.functionExpression;
  return DartMember(
    libraryUri: libraryUri,
    className: '',
    methodName: declaration.name.lexeme,
    body: declaration.toString(),
    kind: DartMemberKind.function,
    isStatic: true,
    callable:
        expression.body is! EmptyFunctionBody &&
        _callable(expression.parameters),
  );
}

DartMemberKind _kind(String className, String? superName) {
  if (superName != null &&
      superName != className &&
      superName.endsWith('State')) {
    return DartMemberKind.state;
  }
  if (superName != null && _widgetSupers.contains(superName)) {
    return DartMemberKind.widget;
  }
  return DartMemberKind.logic;
}

String? _firstTypeArgument(NamedType? type) {
  final arguments = type?.typeArguments?.arguments;
  if (arguments == null || arguments.isEmpty) return null;
  final first = arguments.first;
  if (first is! NamedType) return null;
  return first.name.lexeme;
}

bool _callable(FormalParameterList? parameters) {
  if (parameters == null) return true;
  for (final parameter in parameters.parameters) {
    if (parameter.isRequired) return false;
  }
  return true;
}
