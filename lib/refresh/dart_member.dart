/// A method or top-level function extracted from one library.
library;

/// Kind of declaration a [DartMember] came from.
enum DartMemberKind {
  /// A `State` subclass. Refresh runs inside `setState`.
  state,

  /// A widget class. Refresh marks matching elements dirty.
  widget,

  /// Any other class. Instance methods are invoked on live objects.
  logic,

  /// A top-level function.
  function,
}

/// One callable or view-affecting declaration.
class DartMember {
  /// Creates a member snapshot used for change detection.
  const DartMember({
    required this.libraryUri,
    required this.className,
    required this.methodName,
    required this.body,
    required this.kind,
    required this.isStatic,
    required this.callable,
    this.widgetName,
  });

  /// Library the declaration lives in, usually a `package:` URI.
  final String libraryUri;

  /// Enclosing class, or empty for a top-level function.
  final String className;

  /// Method or function name.
  final String methodName;

  /// Source of the declaration. A change to this text is a change to the member.
  final String body;

  /// How the member should be refreshed.
  final DartMemberKind kind;

  /// Widget type argument of `State<Widget>`, when [kind] is [DartMemberKind.state].
  final String? widgetName;

  /// Whether the declaration is `static`.
  final bool isStatic;

  /// Whether it can be invoked with no arguments.
  ///
  /// Lifecycle methods such as `build` and methods with required parameters
  /// are not callable. A changed `State` member still refreshes the view.
  final bool callable;

  /// Stable identity across edits to the body.
  String get key => '$libraryUri\n$className\n$methodName';

  /// `Class.method`, or the function name when there is no class.
  String get displayName =>
      className.isEmpty ? methodName : '$className.$methodName';
}

/// Members in [next] that are new or whose [DartMember.body] changed.
List<DartMember> changedMembers(
  Map<String, String> previousBodies,
  List<DartMember> next,
) {
  final changed = <DartMember>[];
  for (final member in next) {
    final previous = previousBodies[member.key];
    if (previous == null || previous != member.body) {
      changed.add(member);
    }
  }
  return changed;
}

/// Body text keyed by [DartMember.key].
Map<String, String> memberBodies(List<DartMember> members) => {
  for (final member in members) member.key: member.body,
};
