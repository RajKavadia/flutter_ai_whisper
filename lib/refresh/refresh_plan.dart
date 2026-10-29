/// Turns changed declarations into refresh calls.
library;

import 'package:flutter_ai_whisper/refresh/dart_member.dart';

/// What to run in the connected app for one changed member, or for the reload.
sealed class RefreshAction {
  /// Creates an action labeled for the tool report.
  const RefreshAction(this.label);

  /// Class and method, or the reload step name.
  final String label;
}

/// Evaluates [expression] in [libraryUri].
final class EvaluateAction extends RefreshAction {
  /// Creates an expression call.
  const EvaluateAction({
    required String label,
    required this.libraryUri,
    required this.expression,
  }) : super(label);

  /// Library scope. Private names compile only in their declaring library.
  final String libraryUri;

  /// Single Dart expression.
  final String expression;
}

/// Invokes a zero-argument instance method on live objects of [className].
final class InvokeAction extends RefreshAction {
  /// Creates a live-instance call.
  const InvokeAction({
    required String label,
    required this.libraryUri,
    required this.className,
    required this.methodName,
  }) : super(label);

  /// Library URI used to pick the class when several share a name.
  final String libraryUri;

  /// Class to search for on the heap.
  final String className;

  /// Zero-argument instance method.
  final String methodName;
}

/// Builds one evaluate call per changed class.
///
/// An empty [changed] list produces no actions. The whole application is not
/// reassembled. `State` methods run inside `setState` on that state object.
/// Widget methods run on elements of that widget type. Other instance methods
/// are invoked on live objects. Methods that need arguments are omitted.
List<RefreshAction> planRefresh(List<DartMember> changed) {
  if (changed.isEmpty) return const [];
  final actions = <RefreshAction>[];

  final byClass = <String, List<DartMember>>{};
  for (final member in changed) {
    final key =
        '${member.libraryUri}\n${member.className}\n${member.kind.name}';
    byClass.putIfAbsent(key, () => []).add(member);
  }

  for (final group in byClass.values) {
    final sample = group.first;
    switch (sample.kind) {
      case DartMemberKind.state:
        actions.add(_stateAction(sample, group));
      case DartMemberKind.widget:
        actions.add(_widgetAction(sample, group));
      case DartMemberKind.logic:
        actions.addAll(_logicActions(group));
      case DartMemberKind.function:
        for (final member in group.where((member) => member.callable)) {
          actions.add(
            EvaluateAction(
              label: member.displayName,
              libraryUri: member.libraryUri,
              expression: '${member.methodName}()',
            ),
          );
        }
    }
  }
  return actions;
}

EvaluateAction _stateAction(DartMember sample, List<DartMember> group) {
  final calls = [
    for (final member in group)
      if (member.callable && !member.isStatic) 's.${member.methodName}();',
  ];
  final staticCalls = [
    for (final member in group)
      if (member.callable && member.isStatic)
        '${sample.className}.${member.methodName}();',
  ];
  final widgetTest = sample.widgetName == null
      ? "e is StatefulElement && e.state.runtimeType.toString() == '${sample.className}'"
      : 'e.widget is ${sample.widgetName}';
  final expression =
      '''
(() {
  Element? t;
  void walk(Element e) {
    if (t != null) return;
    if ($widgetTest) { t = e; return; }
    e.visitChildren(walk);
  }
  walk(WidgetsBinding.instance.rootElement!);
  if (t == null) return 'not-found';
  final s = (t as StatefulElement).state as ${sample.className};
  ${staticCalls.join('\n  ')}
  s.setState(() { ${calls.join(' ')} });
  return 'ok';
})()''';
  final called = group
      .where((member) => member.callable)
      .map((member) => member.methodName);
  final label = called.isEmpty
      ? 'setState ${sample.className}'
      : 'setState ${sample.className} ${called.join(', ')}';
  return EvaluateAction(
    label: label,
    libraryUri: sample.libraryUri,
    expression: expression,
  );
}

EvaluateAction _widgetAction(DartMember sample, List<DartMember> group) {
  final calls = [
    for (final member in group)
      if (member.callable && !member.isStatic) 'w.${member.methodName}();',
  ];
  final expression =
      '''
(() {
  var found = 0;
  void walk(Element e) {
    if (e.widget is ${sample.className}) {
      found++;
      final w = e.widget as ${sample.className};
      ${calls.join('\n      ')}
      e.markNeedsBuild();
    }
    e.visitChildren(walk);
  }
  walk(WidgetsBinding.instance.rootElement!);
  return found.toString();
})()''';
  return EvaluateAction(
    label: 'rebuild ${sample.className}',
    libraryUri: sample.libraryUri,
    expression: expression,
  );
}

List<RefreshAction> _logicActions(List<DartMember> group) {
  final actions = <RefreshAction>[];
  for (final member in group.where((member) => member.callable)) {
    if (member.isStatic) {
      actions.add(
        EvaluateAction(
          label: member.displayName,
          libraryUri: member.libraryUri,
          expression: '${member.className}.${member.methodName}()',
        ),
      );
    } else {
      actions.add(
        InvokeAction(
          label: member.displayName,
          libraryUri: member.libraryUri,
          className: member.className,
          methodName: member.methodName,
        ),
      );
    }
  }
  return actions;
}
