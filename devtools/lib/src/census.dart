import 'dart:convert';

/// The result of a screen census evaluate.
class ScreenCensus {
  const ScreenCensus({
    required this.ok,
    required this.route,
    required this.isDialog,
    required this.capped,
    required this.count,
    required this.rows,
    this.error,
  });

  /// Whether the census completed.
  final bool ok;

  /// The name of the current route, when known.
  final String route;

  /// Whether the current route is a dialog or other popup route.
  final bool isDialog;

  /// Whether the walk stopped at the stateful-element cap.
  final bool capped;

  /// Number of stateful elements encountered before the cap.
  final int count;

  /// Stateful rows in the current route.
  final List<ScreenRow> rows;

  /// A machine-readable failure reason when [ok] is false.
  final String? error;

  /// Parses the JSON string returned by [Census.screen].
  static ScreenCensus parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Screen census did not return a JSON object.');
    }
    final rows = <ScreenRow>[];
    final rawRows = decoded['rows'];
    if (rawRows is List) {
      for (final rawRow in rawRows) {
        if (rawRow is Map<String, dynamic>) {
          rows.add(ScreenRow.fromJson(rawRow));
        }
      }
    }
    return ScreenCensus(
      ok: decoded['ok'] == true,
      route: decoded['route'] as String? ?? '',
      isDialog: decoded['isDialog'] == true,
      capped: decoded['capped'] == true,
      count: (decoded['count'] as num?)?.toInt() ?? rows.length,
      rows: rows,
      error: decoded['error'] as String?,
    );
  }
}

/// One stateful widget on the current route.
class ScreenRow {
  const ScreenRow({
    required this.widgetType,
    required this.stateType,
    required this.finderKey,
    required this.preview,
    required this.route,
    required this.depth,
    required this.siblingIndex,
  });

  /// The widget's runtime type name.
  final String widgetType;

  /// The State's runtime type name.
  final String stateType;

  /// Stable locator: route, widget type, State type, depth, sibling index.
  final String finderKey;

  /// A short, human-readable value preview.
  final String preview;

  /// The route this row was found on.
  final String route;

  /// Depth from the root element.
  final int depth;

  /// Index among this element's siblings.
  final int siblingIndex;

  /// Reads a row from the census JSON.
  factory ScreenRow.fromJson(Map<String, dynamic> json) {
    return ScreenRow(
      widgetType: json['widget'] as String? ?? '',
      stateType: json['state'] as String? ?? '',
      finderKey: json['key'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      route: json['route'] as String? ?? '',
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      siblingIndex: (json['sibling'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether [query] matches the widget, State type, or preview.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return widgetType.toLowerCase().contains(needle) ||
        stateType.toLowerCase().contains(needle) ||
        preview.toLowerCase().contains(needle);
  }
}

/// A field read from a State or logic object.
class FieldRow {
  const FieldRow({
    required this.name,
    required this.type,
    required this.value,
    required this.editable,
    this.readOnlyReason,
    this.suggestedMethod,
  });

  /// The field or accessor name.
  final String name;

  /// The declared type name, when known.
  final String type;

  /// The current value as reported by the VM.
  final String value;

  /// Whether the panel may assign this field.
  final bool editable;

  /// Why the field is read-only.
  final String? readOnlyReason;

  /// A public method the Run mode can call instead.
  final String? suggestedMethod;
}

/// The result of reading a field and the Text widgets under its route.
class ReadSnapshot {
  const ReadSnapshot({
    required this.ok,
    required this.field,
    required this.current,
    required this.texts,
    this.route = '',
    this.error,
  });

  /// Whether the read completed.
  final bool ok;

  /// The field value as a string.
  final String field;

  /// Whether the route holding the object is current.
  final bool current;

  /// Text data under the route.
  final List<String> texts;

  /// The route name, when the expression reports one.
  final String route;

  /// A machine-readable failure reason.
  final String? error;

  /// Parses a read expression's JSON.
  static ReadSnapshot parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Read did not return a JSON object.');
    }
    final rawTexts = decoded['texts'];
    return ReadSnapshot(
      ok: decoded['ok'] == true,
      field: decoded['field'] as String? ?? '',
      current: decoded['current'] == true,
      texts: rawTexts is List ? rawTexts.whereType<String>().toList() : const [],
      route: decoded['route'] as String? ?? '',
      error: decoded['error'] as String?,
    );
  }
}

/// Builds the Dart expressions the panel evaluates in the app isolate.
///
/// Every expression is a single Dart expression. A local IIFE provides
/// statements; the VM `evaluate` RPC cannot return a statement list.
abstract final class Census {
  /// Maximum number of stateful elements returned for one screen.
  static const int statefulCap = 200;

  static const String _escape = r'''
  String _wEsc(String v) {
    final b = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final c = v.codeUnitAt(i);
      if (c == 34) {
        b.write('\\"');
      } else if (c == 92) {
        b.write('\\\\');
      } else if (c == 10) {
        b.write('\\n');
      } else if (c == 13) {
        b.write('\\r');
      } else if (c == 9) {
        b.write('\\t');
      } else if (c < 32) {
        b.write('\\u' + c.toRadixString(16).padLeft(4, '0'));
      } else {
        b.write(v[i]);
      }
    }
    return b.toString();
  }
''';

  /// The finder prelude: walks the whole element tree and matches [key].
  ///
  /// The walk covers every route, not just the current one, so a write can
  /// land on a page that is currently covered. The key includes the route
  /// name, so a covered page still matches.
  static String _finder(String key) {
    return r'''
  Element? target;
  void _wWalk(Element e, int depth, int sibling) {
    if (target != null) return;
    ModalRoute<dynamic>? route;
    try { route = ModalRoute.of(e); } catch (_) {}
    if (route != null) {
      final widget = e.widget;
      if (widget is StatefulWidget && e is StatefulElement) {
        final state = e.state;
        final routeName = route.settings.name ?? route.runtimeType.toString();
        final key = routeName + '|' + widget.runtimeType.toString() + '|' +
            state.runtimeType.toString() + '|' + depth.toString() + '|' +
            sibling.toString();
        if (key == FINDER_KEY) {
          target = e;
          return;
        }
      }
    }
    var index = 0;
    e.visitChildren((child) {
      _wWalk(child, depth + 1, index);
      index++;
    });
  }
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) _wWalk(root, 0, 0);
'''
        .replaceAll('FINDER_KEY', _dartString(key));
  }

  /// Builds the screen census expression.
  static String screen({int cap = statefulCap}) {
    return r'''
(() {
ESCAPE
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return '{"ok":false,"error":"no-root"}';
  }
  ModalRoute<dynamic>? current;
  void _wFindRoute(Element e) {
    if (current != null) return;
    ModalRoute<dynamic>? route;
    try { route = ModalRoute.of(e); } catch (_) {}
    if (route != null && route.isCurrent) {
      current = route;
      return;
    }
    e.visitChildren(_wFindRoute);
  }
  _wFindRoute(root);
  if (current == null) {
    return '{"ok":false,"error":"no-current-route"}';
  }
  final route = current!;
  final routeName = route.settings.name ?? route.runtimeType.toString();
  final rows = <String>[];
  var statefulCount = 0;
  var capped = false;
  void _wCollect(Element e, int depth, int sibling) {
    ModalRoute<dynamic>? elementRoute;
    try { elementRoute = ModalRoute.of(e); } catch (_) {}
    if (identical(elementRoute, route)) {
      final widget = e.widget;
      if (widget is StatefulWidget && e is StatefulElement) {
        statefulCount++;
        if (statefulCount > CAP) {
          capped = true;
        } else {
          final state = e.state;
          final widgetType = widget.runtimeType.toString();
          final stateType = state.runtimeType.toString();
          final finderKey = routeName + '|' + widgetType + '|' + stateType +
              '|' + depth.toString() + '|' + sibling.toString();
          var preview = '';
          try { preview = state.toString(); } catch (_) {}
          if (preview.length > 80) {
            preview = preview.substring(0, 80);
          }
          rows.add('{"widget":"' + _wEsc(widgetType) +
              '","state":"' + _wEsc(stateType) +
              '","key":"' + _wEsc(finderKey) +
              '","preview":"' + _wEsc(preview) +
              '","route":"' + _wEsc(routeName) +
              '","depth":' + depth.toString() +
              ',"sibling":' + sibling.toString() + '}');
        }
      }
    }
    var index = 0;
    e.visitChildren((child) {
      _wCollect(child, depth + 1, index);
      index++;
    });
  }
  _wCollect(root, 0, 0);
  return '{"ok":true,"route":"' + _wEsc(routeName) +
      '","isDialog":' + (route is PopupRoute ? 'true' : 'false') +
      ',"capped":' + (capped ? 'true' : 'false') +
      ',"count":' + statefulCount.toString() +
      ',"rows":[' + rows.join(',') + ']}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('CAP', cap.toString());
  }

  /// Builds an expression that returns the State matching [finderKey].
  static String findState(String finderKey) {
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) return null;
  return (target as StatefulElement).state;
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey));
  }

  /// Builds an expression that returns the logic object held by [holderField].
  static String findHolder(String finderKey, String holderField) {
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) return null;
  final state = (target as StatefulElement).state;
  try {
    return (state as dynamic).HOLDER;
  } catch (_) {
    return null;
  }
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('HOLDER', holderField);
  }

  /// Builds a State field assignment wrapped in `setState`.
  static String assignStateField({
    required String finderKey,
    required String stateType,
    required String field,
    required String literal,
  }) {
    _requireIdentifier(stateType, 'stateType');
    _requireIdentifier(field, 'field');
    final assignment = 'state.$field = $literal';
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) {
    return '{"ok":false,"error":"not-found"}';
  }
  final state = (target as StatefulElement).state as STATE_TYPE;
  state.setState(() {
    ASSIGNMENT;
  });
  return '{"ok":true}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('STATE_TYPE', stateType)
        .replaceAll('ASSIGNMENT', assignment);
  }

  /// Builds a logic-object field assignment.
  ///
  /// When [wrapInSetState] is true the write runs inside the screen State's
  /// `setState`; notifying objects pass false.
  static String assignLogicField({
    required String finderKey,
    required String stateType,
    required String holderField,
    required String field,
    required String literal,
    required bool wrapInSetState,
  }) {
    _requireIdentifier(stateType, 'stateType');
    _requireIdentifier(holderField, 'holderField');
    _requireIdentifier(field, 'field');
    final assignment = 'state.$holderField.$field = $literal';
    final body = wrapInSetState
        ? 'state.setState(() { $assignment; });'
        : assignment;
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) {
    return '{"ok":false,"error":"not-found"}';
  }
  final state = (target as StatefulElement).state as STATE_TYPE;
  BODY
  return '{"ok":true}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('STATE_TYPE', stateType)
        .replaceAll('BODY', body);
  }

  /// Builds a heap-object field assignment using the VM evaluate `scope`.
  ///
  /// The caller supplies an object id under the name `object`.
  static String assignHeapField({
    required String field,
    required String literal,
  }) {
    _requireIdentifier(field, 'field');
    final assignment = 'object.$field = $literal';
    return r'''
(() {
  ASSIGNMENT;
  return '{"ok":true}';
})()
'''
        .replaceAll('ASSIGNMENT', assignment);
  }

  /// Builds an expression that reads a State field and the Texts under its route.
  static String readStateField({
    required String finderKey,
    required String stateType,
    required String field,
  }) {
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) {
    return '{"ok":false,"error":"not-found"}';
  }
  final state = (target as StatefulElement).state as STATE_TYPE;
  String value = '';
  try {
    value = (state.FIELD).toString();
  } catch (e) {
    value = 'error: ' + e.toString();
  }
  final route = ModalRoute.of(target);
  final current = route?.isCurrent ?? false;
  final texts = <String>[];
  void _wText(Element e) {
    ModalRoute<dynamic>? elementRoute;
    try { elementRoute = ModalRoute.of(e); } catch (_) {}
    if (elementRoute != null && identical(elementRoute, route)) {
      final widget = e.widget;
      if (widget is Text) {
        final data = widget.data;
        if (data != null && data.trim().isNotEmpty) {
          texts.add(data);
        }
      }
    }
    e.visitChildren(_wText);
  }
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) _wText(root);
  return '{"ok":true,"field":"' + _wEsc(value) +
      '","current":' + (current ? 'true' : 'false') +
      ',"texts":[' + texts.map((t) => '"' + _wEsc(t) + '"').join(',') + ']}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('STATE_TYPE', stateType)
        .replaceAll('FIELD', field);
  }

  /// Builds an expression that reads a logic object's field and route Texts.
  static String readLogicField({
    required String finderKey,
    required String stateType,
    required String holderField,
    required String field,
  }) {
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) {
    return '{"ok":false,"error":"not-found"}';
  }
  final state = (target as StatefulElement).state as STATE_TYPE;
  String value = '';
  try {
    value = (state.HOLDER.FIELD).toString();
  } catch (e) {
    value = 'error: ' + e.toString();
  }
  final route = ModalRoute.of(target);
  final current = route?.isCurrent ?? false;
  final texts = <String>[];
  void _wText(Element e) {
    ModalRoute<dynamic>? elementRoute;
    try { elementRoute = ModalRoute.of(e); } catch (_) {}
    if (elementRoute != null && identical(elementRoute, route)) {
      final widget = e.widget;
      if (widget is Text) {
        final data = widget.data;
        if (data != null && data.trim().isNotEmpty) {
          texts.add(data);
        }
      }
    }
    e.visitChildren(_wText);
  }
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) _wText(root);
  return '{"ok":true,"field":"' + _wEsc(value) +
      '","current":' + (current ? 'true' : 'false') +
      ',"texts":[' + texts.map((t) => '"' + _wEsc(t) + '"').join(',') + ']}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('STATE_TYPE', stateType)
        .replaceAll('HOLDER', holderField)
        .replaceAll('FIELD', field);
  }

  /// Builds an expression that reads a heap object's field and route Texts.
  ///
  /// The caller supplies the object id under the name `object`.
  static String readHeapField({required String field}) {
    return r'''
(() {
ESCAPE
  String value = '';
  try {
    value = (object.FIELD).toString();
  } catch (e) {
    value = 'error: ' + e.toString();
  }
  ModalRoute<dynamic>? current;
  void _wFindRoute(Element e) {
    if (current != null) return;
    ModalRoute<dynamic>? route;
    try { route = ModalRoute.of(e); } catch (_) {}
    if (route != null && route.isCurrent) {
      current = route;
      return;
    }
    e.visitChildren(_wFindRoute);
  }
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) _wFindRoute(root);
  final route = current;
  final texts = <String>[];
  void _wText(Element e) {
    ModalRoute<dynamic>? elementRoute;
    try { elementRoute = ModalRoute.of(e); } catch (_) {}
    if (elementRoute != null && identical(elementRoute, route)) {
      final widget = e.widget;
      if (widget is Text) {
        final data = widget.data;
        if (data != null && data.trim().isNotEmpty) {
          texts.add(data);
        }
      }
    }
    e.visitChildren(_wText);
  }
  if (root != null) _wText(root);
  return '{"ok":true,"field":"' + _wEsc(value) +
      '","current":' + ((route?.isCurrent ?? false) ? 'true' : 'false') +
      ',"texts":[' + texts.map((t) => '"' + _wEsc(t) + '"').join(',') + ']}';
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FIELD', field);
  }

  /// Builds an expression that reads the Text widgets under the current route.
  static String readCurrentRouteTexts() {
    return r'''
(() {
ESCAPE
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return '{"ok":false,"error":"no-root"}';
  }
  ModalRoute<dynamic>? current;
  void _wFindRoute(Element e) {
    if (current != null) return;
    ModalRoute<dynamic>? route;
    try { route = ModalRoute.of(e); } catch (_) {}
    if (route != null && route.isCurrent) {
      current = route;
      return;
    }
    e.visitChildren(_wFindRoute);
  }
  _wFindRoute(root);
  if (current == null) {
    return '{"ok":false,"error":"no-current-route"}';
  }
  final route = current!;
  final routeName = route.settings.name ?? route.runtimeType.toString();
  final texts = <String>[];
  void _wText(Element e) {
    ModalRoute<dynamic>? elementRoute;
    try { elementRoute = ModalRoute.of(e); } catch (_) {}
    if (elementRoute != null && identical(elementRoute, route)) {
      final widget = e.widget;
      if (widget is Text) {
        final data = widget.data;
        if (data != null && data.trim().isNotEmpty) {
          texts.add(data);
        }
      }
    }
    e.visitChildren(_wText);
  }
  _wText(root);
  return '{"ok":true,"route":"' + _wEsc(routeName) +
      '","current":true,"texts":[' +
      texts.map((t) => '"' + _wEsc(t) + '"').join(',') + ']}';
})()
'''
        .replaceAll('ESCAPE', _escape);
  }

  /// Builds the debug rebuild expression used by Refresh.
  static String reassemble() {
    return "(() { WidgetsBinding.instance.reassemble(); "
        "return '{\"ok\":true}'; })()";
  }

  /// Builds an expression that reads a getter that has no setter.
  static String readGetter({
    required String finderKey,
    required String stateType,
    required String getter,
  }) {
    return r'''
(() {
ESCAPE
FINDER
  if (target == null) return null;
  final state = (target as StatefulElement).state as STATE_TYPE;
  return (state.GETTER).toString();
})()
'''
        .replaceAll('ESCAPE', _escape)
        .replaceAll('FINDER', _finder(finderKey))
        .replaceAll('STATE_TYPE', stateType)
        .replaceAll('GETTER', getter);
  }

  static final _identifierPattern = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  static void _requireIdentifier(String value, String label) {
    if (!_identifierPattern.hasMatch(value)) {
      throw ArgumentError.value(value, label, 'must be a valid Dart identifier');
    }
  }

  static String _dartString(String value) {
    final buffer = StringBuffer("'");
    for (final codeUnit in value.codeUnits) {
      if (codeUnit == 39) {
        buffer.write(r"\'");
      } else if (codeUnit == 92) {
        buffer.write(r'\\');
      } else if (codeUnit == 10) {
        buffer.write(r'\n');
      } else if (codeUnit == 13) {
        buffer.write(r'\r');
      } else if (codeUnit == 9) {
        buffer.write(r'\t');
      } else if (codeUnit < 32) {
        buffer.write('\\u{${codeUnit.toRadixString(16)}}');
      } else {
        buffer.writeCharCode(codeUnit);
      }
    }
    buffer.write("'");
    return buffer.toString();
  }
}
