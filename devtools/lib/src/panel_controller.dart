import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import 'census.dart';
import 'literal.dart';
import 'logic.dart';
import 'vm_client.dart';

/// The three panel modes.
enum PanelMode {
  /// State objects mounted on the current route.
  screen,

  /// Logic objects reachable from the screen, plus heap rows on native.
  logic,

  /// One Dart expression in one library.
  run,
}

/// A user-facing panel failure.
class PanelException implements Exception {
  const PanelException(this.message);

  /// The message shown in the panel.
  final String message;

  @override
  String toString() => message;
}

enum TargetKind { state, screenLogic, heapLogic }

/// The object currently selected in the field editor.
class InspectTarget {
  const InspectTarget({
    required this.kind,
    required this.title,
    required this.type,
    this.finderKey,
    this.stateType,
    this.holderField,
    this.identityHashCode,
    this.heapObjectId,
    this.classId,
    this.rootVariable,
    this.libraryUri,
  });

  final TargetKind kind;
  final String title;
  final String type;
  final String? finderKey;
  final String? stateType;
  final String? holderField;
  final String? identityHashCode;
  final String? heapObjectId;
  final String? classId;
  final String? rootVariable;
  final String? libraryUri;
}

/// Drives the panel: census, field reads, writes, polling, and Run mode.
class PanelController extends ChangeNotifier {
  PanelController(this.client);

  /// The VM Service client used for every operation.
  final VmClient client;

  PanelMode mode = PanelMode.screen;
  bool busy = false;
  String? error;
  String? notice;
  String search = '';

  ScreenCensus? census;
  List<ScreenRow> screenRows = const [];
  ScreenRow? selectedScreen;

  List<LogicRow> logicRows = const [];
  LogicRow? selectedLogic;
  bool heapUnavailable = false;
  String? logicNotice;

  InspectTarget? target;
  List<FieldRow> fields = const [];
  FieldRow? selectedField;
  String? fieldsLibraryUri;

  String runExpression = '';
  String runLibraryUri = '';
  String? runResult;

  /// Whether the panel can talk to a debug app.
  bool get isConnected => client.isConnected;

  /// The app or isolate name, when connected.
  String? get appName => client.appName;

  /// Screen rows after applying the local search filter.
  List<ScreenRow> get visibleScreenRows =>
      screenRows.where((row) => row.matches(search)).toList();

  /// Logic rows after applying the local search filter.
  List<LogicRow> get visibleLogicRows =>
      logicRows.where((row) => row.matches(search)).toList();

  /// Updates the selected field in the editor.
  void selectField(FieldRow? field) {
    selectedField = field;
    notifyListeners();
  }

  /// Clears connection-specific state.
  void reset() {
    busy = false;
    error = null;
    notice = null;
    census = null;
    screenRows = const [];
    selectedScreen = null;
    logicRows = const [];
    selectedLogic = null;
    heapUnavailable = false;
    logicNotice = null;
    target = null;
    fields = const [];
    selectedField = null;
    fieldsLibraryUri = null;
    runResult = null;
    notifyListeners();
  }

  /// Changes mode and loads the mode's data when connected.
  void setMode(PanelMode value) {
    if (mode == value) return;
    mode = value;
    error = null;
    notice = null;
    notifyListeners();
    if (!isConnected) return;
    if (value == PanelMode.screen && census == null) {
      unawaited(loadScreen());
    } else if (value == PanelMode.logic) {
      unawaited(loadLogic());
    }
  }

  /// Updates the local search filter.
  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  /// Updates the Run expression.
  void setRunExpression(String value) {
    runExpression = value;
    notifyListeners();
  }

  /// Updates the Run library URI.
  void setRunLibraryUri(String value) {
    runLibraryUri = value;
    notifyListeners();
  }

  /// Loads the current screen census.
  Future<void> loadScreen() {
    return _busyRun(_loadScreenInternal);
  }

  /// Loads screen-reachable logic objects and, on native, heap rows.
  Future<void> loadLogic() {
    return _busyRun(_loadLogicInternal);
  }

  /// Selects a screen row and reads its fields.
  Future<void> selectScreenRow(ScreenRow row) {
    return _busyRun(() async {
      selectedScreen = row;
      selectedLogic = null;
      fields = const [];
      selectedField = null;
      notifyListeners();
      final resolved = await _resolveState(row);
      if (resolved == null) {
        throw const PanelException(
          'Object left the screen. Refresh the list and try again.',
        );
      }
      target = InspectTarget(
        kind: TargetKind.state,
        title: '${row.stateType} · ${row.route}',
        type: row.stateType,
        finderKey: row.finderKey,
        stateType: row.stateType,
        libraryUri: resolved.libraryUri,
      );
      final libraryUri = resolved.libraryUri;
      if (libraryUri == null) {
        throw const PanelException('Could not resolve the State library.');
      }
      fieldsLibraryUri = libraryUri;
      fields = FieldExtractor.fromInstance(
        resolved.instance,
        clazz: resolved.clazz,
        accessibleLibrary: libraryUri,
        preferPublic: false,
      );
      await _fillGetterValues(
        finderKey: row.finderKey,
        stateType: row.stateType,
        libraryUri: libraryUri,
      );
      selectedField = _firstEditable(fields) ?? _first(fields);
      notifyListeners();
    });
  }

  /// Selects a logic row and reads its fields.
  Future<void> selectLogicRow(LogicRow row) {
    return _busyRun(() async {
      selectedLogic = row;
      selectedScreen = null;
      fields = const [];
      selectedField = null;
      notifyListeners();
      if (row.fromHeap) {
        final resolved = await _resolveHeap(row);
        if (resolved == null) {
          throw const PanelException(
            'Heap object is gone. Refresh the list and try again.',
          );
        }
        target = InspectTarget(
          kind: TargetKind.heapLogic,
          title: '${row.name} · heap',
          type: row.type,
          identityHashCode: row.identityHashCode,
          heapObjectId: row.heapObjectId,
          classId: row.classId,
          rootVariable: row.rootVariable,
          libraryUri: resolved.libraryUri,
        );
        fieldsLibraryUri = resolved.libraryUri;
        fields = FieldExtractor.fromInstance(
          resolved.instance,
          clazz: resolved.clazz,
          accessibleLibrary: resolved.libraryUri,
          preferPublic: true,
        );
      } else {
        final resolved = await _resolveScreenLogic(row);
        if (resolved == null) {
          throw const PanelException(
            'Object left the screen. Refresh the list and try again.',
          );
        }
        target = InspectTarget(
          kind: TargetKind.screenLogic,
          title: '${row.name} · ${row.type}',
          type: row.type,
          finderKey: row.finderKey,
          stateType: row.stateType,
          holderField: row.holderField,
          libraryUri: resolved.libraryUri,
        );
        fieldsLibraryUri = resolved.libraryUri;
        fields = FieldExtractor.fromInstance(
          resolved.instance,
          clazz: resolved.clazz,
          accessibleLibrary: resolved.stateLibraryUri,
          preferPublic: true,
        );
      }
      selectedField = _firstEditable(fields) ?? _first(fields);
      notifyListeners();
    });
  }

  /// Assigns [rawLiteral] to the selected field.
  Future<void> assign(String rawLiteral) {
    return _busyRun(() async {
      final selected = selectedField;
      final active = target;
      if (selected == null || active == null) {
        throw const PanelException('Select a field first.');
      }
      if (!selected.editable) {
        throw PanelException(
          selected.readOnlyReason ?? 'This field is read-only.',
        );
      }
      final EncodedLiteral literal;
      try {
        literal = Literals.parse(rawLiteral, fieldType: selected.type);
      } on LiteralError catch (error) {
        throw PanelException(error.message);
      }
      final before = await _readSnapshot(active);
      if (!before.ok) {
        throw PanelException(
          before.error ?? 'Could not read the field before writing.',
        );
      }
      final expression = await _assignExpression(active, selected, literal);
      final response = await client.evaluate(
        expression,
        libraryUri: active.libraryUri,
        scope: await _scopeFor(active),
      );
      _throwOnError(response, active.libraryUri);
      final after = await _poll(before, () => _readSnapshot(active));
      _reportWrite(active, before, after);
      selectedField = FieldRow(
        name: selected.name,
        type: selected.type,
        value: after.field,
        editable: selected.editable,
        readOnlyReason: selected.readOnlyReason,
        suggestedMethod: selected.suggestedMethod,
      );
      notifyListeners();
    });
  }

  /// Reassembles the app, polls the current route, then reloads the list.
  Future<void> refresh() {
    return _busyRun(() async {
      final selectedRoute = selectedScreen?.route ??
          (selectedLogic?.fromHeap == false ? selectedScreen?.route : null);
      final before = await _readCurrentTexts();
      final response = await client.evaluate(Census.reassemble());
      _throwOnError(response, null);
      final after = await _pollTexts(before);
      if (!_sameTexts(before.texts, after.texts)) {
        notice = 'Reassembled; Text under the current route changed.';
      } else {
        notice = 'Reassembled; no Text change detected.';
      }
      await _loadScreenInternal();
      if (selectedRoute != null &&
          census != null &&
          census!.route.isNotEmpty &&
          selectedRoute != census!.route) {
        notice = 'The selected route is covered by "${census!.route}"; '
            'the repaint waits until that route is current.';
      }
      if (mode == PanelMode.logic) {
        await _loadLogicInternal(reloadScreen: false);
      }
    });
  }

  /// Runs one expression in one library, then polls the current route.
  Future<void> run() {
    return _busyRun(() async {
      final expression = runExpression.trim();
      if (expression.isEmpty) {
        throw const PanelException('Enter one Dart expression.');
      }
      final library = runLibraryUri.trim().isEmpty
          ? null
          : runLibraryUri.trim();
      final before = await _readCurrentTexts();
      final response = await client.evaluate(expression, libraryUri: library);
      if (response is ErrorRef) {
        throw PanelException(
          '${response.message ?? 'Evaluate failed.'}\n'
          'Library: ${library ?? 'app root'}',
        );
      }
      final value = response is InstanceRef
          ? (response.valueAsString ?? response.classRef?.name ?? 'ok')
          : response is Sentinel
              ? '(collected)'
              : response.runtimeType.toString();
      runResult = value;
      final after = await _pollTexts(before);
      if (!_sameTexts(before.texts, after.texts)) {
        notice = 'Expression ran; Text under the current route changed.';
      } else {
        notice = 'Expression ran; no Text change detected.';
      }
      notifyListeners();
    });
  }

  Future<void> _loadScreenInternal() async {
    _requireConnection();
    final response = await _evaluateJson(
      Census.screen(),
      libraryUri: null,
      retryOnUndefined: true,
    );
    final parsed = ScreenCensus.parse(response);
    if (!parsed.ok) {
      throw PanelException(_censusError(parsed.error));
    }
    census = parsed;
    screenRows = parsed.rows;
    if (parsed.capped) {
      notice = 'The list is partial: the walk stopped at '
          '${Census.statefulCap} stateful elements. Narrow the search.';
    }
    notifyListeners();
  }

  Future<void> _loadLogicInternal({bool reloadScreen = true}) async {
    _requireConnection();
    if (reloadScreen || census == null) {
      await _loadScreenInternal();
    }
    final rows = <LogicRow>[];
    final seen = <String>{};
    for (final screenRow in census?.rows ?? const <ScreenRow>[]) {
      final resolved = await _resolveState(screenRow);
      if (resolved == null) continue;
      for (final bound in resolved.instance.fields ?? const <BoundField>[]) {
        final value = bound.value;
        if (value is! InstanceRef) continue;
        final type = value.classRef?.name ?? '';
        if (!LogicPatterns.matches(type)) continue;
        final name = bound.name is String ? bound.name as String : '';
        if (name.isEmpty) continue;
        if (!seen.add('${screenRow.finderKey}|$name')) continue;
        rows.add(
          LogicRow(
            name: name,
            type: type,
            source: 'screen',
            finderKey: screenRow.finderKey,
            stateType: screenRow.stateType,
            holderField: name,
            libraryUri: resolved.libraryUri,
            valuePreview: value.valueAsString,
          ),
        );
      }
    }

    heapUnavailable = false;
    logicNotice = null;
    final classList = await client.getClassList();
    if (classList == null) {
      heapUnavailable = true;
    } else {
      final classes = classList.classes ?? const <ClassRef>[];
      for (final classRef in classes) {
        final name = classRef.name ?? '';
        if (!LogicPatterns.matches(name)) continue;
        final library = classRef.library?.uri;
        if (library == null ||
            library.startsWith('dart:') ||
            library.startsWith('package:flutter/')) {
          continue;
        }
        final classId = classRef.id;
        if (classId == null) continue;
        final instances = await client.getInstances(
          classId,
          10,
          includeSubclasses: true,
        );
        for (final reference in instances?.instances ?? const <ObjRef>[]) {
          final objectId = reference.id;
          if (objectId == null || objectId.isEmpty) continue;
          String? preview;
          String? hash;
          if (reference is InstanceRef) {
            hash = reference.identityHashCode?.toString();
            preview = reference.valueAsString;
          }
          rows.add(
            LogicRow(
              name: name,
              type: name,
              source: 'heap',
              libraryUri: library,
              identityHashCode: hash,
              heapObjectId: objectId,
              classId: classId,
              valuePreview: preview,
            ),
          );
        }
      }
      final root = await client.getRootLibrary();
      for (final field in root?.variables ?? const <FieldRef>[]) {
        final name = field.name ?? '';
        if (!LogicPatterns.matches(name)) continue;
        rows.add(
          LogicRow(
            name: name,
            type: 'library variable',
            source: 'heap',
            libraryUri: root?.uri,
            rootVariable: name,
          ),
        );
      }
    }
    logicRows = rows;
    if (rows.isEmpty && heapUnavailable) {
      logicNotice = 'Heap listing is unavailable on Flutter Web. '
          'Screen-reachable logic is listed above; Run can probe a named '
          'expression.';
    } else if (heapUnavailable) {
      logicNotice = 'Heap listing is unavailable on Flutter Web. '
          'Screen-reachable logic is listed.';
    }
    notifyListeners();
  }

  Future<void> _fillGetterValues({
    required String finderKey,
    required String stateType,
    required String libraryUri,
  }) async {
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      if (field.value != '(getter)' || field.name.startsWith('_')) continue;
      try {
        final response = await client.evaluate(
          Census.readGetter(
            finderKey: finderKey,
            stateType: stateType,
            getter: field.name,
          ),
          libraryUri: libraryUri,
        );
        if (response is InstanceRef && response.valueAsString != null) {
          fields[index] = FieldRow(
            name: field.name,
            type: field.type,
            value: response.valueAsString!,
            editable: field.editable,
            readOnlyReason: field.readOnlyReason,
            suggestedMethod: field.suggestedMethod,
          );
        }
      } catch (_) {
        // A getter that throws stays visible without a value.
      }
    }
  }

  Future<String> _assignExpression(
    InspectTarget active,
    FieldRow field,
    EncodedLiteral literal,
  ) async {
    switch (active.kind) {
      case TargetKind.state:
        return Census.assignStateField(
          finderKey: active.finderKey!,
          stateType: active.stateType!,
          field: field.name,
          literal: literal.dart,
        );
      case TargetKind.screenLogic:
        return Census.assignLogicField(
          finderKey: active.finderKey!,
          stateType: active.stateType!,
          holderField: active.holderField!,
          field: field.name,
          literal: literal.dart,
          wrapInSetState: !LogicPatterns.notifies(active.type),
        );
      case TargetKind.heapLogic:
        return Census.assignHeapField(
          field: field.name,
          literal: literal.dart,
        );
    }
  }

  Future<Map<String, String>?> _scopeFor(InspectTarget active) async {
    if (active.kind != TargetKind.heapLogic) return null;
    final resolved = await _resolveHeapTarget(active);
    if (resolved == null) {
      throw const PanelException(
        'Heap object is gone. Refresh the list and try again.',
      );
    }
    return {'object': resolved.id};
  }

  Future<ReadSnapshot> _readSnapshot(InspectTarget active) async {
    switch (active.kind) {
      case TargetKind.state:
        return ReadSnapshot.parse(
          await _evaluateJson(
            Census.readStateField(
              finderKey: active.finderKey!,
              stateType: active.stateType!,
              field: selectedField?.name ?? '',
            ),
            libraryUri: active.libraryUri,
          ),
        );
      case TargetKind.screenLogic:
        return ReadSnapshot.parse(
          await _evaluateJson(
            Census.readLogicField(
              finderKey: active.finderKey!,
              stateType: active.stateType!,
              holderField: active.holderField!,
              field: selectedField?.name ?? '',
            ),
            libraryUri: active.libraryUri,
          ),
        );
      case TargetKind.heapLogic:
        final resolved = await _resolveHeapTarget(active);
        if (resolved == null) {
          return const ReadSnapshot(
            ok: false,
            field: '',
            current: false,
            texts: [],
            error: 'not-found',
          );
        }
        return ReadSnapshot.parse(
          await _evaluateJson(
            Census.readHeapField(field: selectedField?.name ?? ''),
            libraryUri: active.libraryUri,
            scope: {'object': resolved.id},
          ),
        );
    }
  }

  Future<ReadSnapshot> _readCurrentTexts() async {
    return ReadSnapshot.parse(
      await _evaluateJson(Census.readCurrentRouteTexts(), libraryUri: null),
    );
  }

  Future<ReadSnapshot> _poll(
    ReadSnapshot before,
    Future<ReadSnapshot> Function() read,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    var last = before;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        last = await read();
      } catch (_) {
        continue;
      }
      if (last.field != before.field || !_sameTexts(last.texts, before.texts)) {
        return last;
      }
    }
    return last;
  }

  Future<ReadSnapshot> _pollTexts(ReadSnapshot before) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    var last = before;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        last = await _readCurrentTexts();
      } catch (_) {
        continue;
      }
      if (!_sameTexts(last.texts, before.texts)) return last;
    }
    return last;
  }

  void _reportWrite(
    InspectTarget active,
    ReadSnapshot before,
    ReadSnapshot after,
  ) {
    if (after.field == before.field) {
      throw const PanelException(
        'The write did not land; the field value did not change.',
      );
    }
    if (!after.current) {
      notice = 'Write landed. The route is covered; the repaint waits until '
          'that route is current.';
      return;
    }
    if (!_sameTexts(before.texts, after.texts)) {
      notice = 'Write landed; the Text under the route changed.';
    } else {
      notice = 'Write landed, but no Text under the route changed '
          '(the field may not be displayed).';
    }
  }

  Future<({String stateId, Instance instance, Class? clazz, String? libraryUri})?>
      _resolveState(ScreenRow row) async {
    final response = await client.evaluate(Census.findState(row.finderKey));
    if (response is ErrorRef) {
      throw PanelException(response.message ?? 'Could not find the State.');
    }
    if (response is! InstanceRef ||
        response.kind == 'Null' ||
        response.id == null) {
      return null;
    }
    final object = await client.getObject(response.id!);
    if (object is! Instance) return null;
    final (clazz, libraryUri) = await _classInfo(object);
    return (
      stateId: response.id!,
      instance: object,
      clazz: clazz,
      libraryUri: libraryUri,
    );
  }

  Future<({Instance instance, Class? clazz, String? libraryUri, String? stateLibraryUri})?>
      _resolveScreenLogic(LogicRow row) async {
    final state = await _resolveState(
      ScreenRow(
        widgetType: '',
        stateType: row.stateType ?? '',
        finderKey: row.finderKey ?? '',
        preview: '',
        route: '',
        depth: 0,
        siblingIndex: 0,
      ),
    );
    if (state == null) return null;
    final response = await client.evaluate(
      Census.findHolder(row.finderKey!, row.holderField!),
      libraryUri: state.libraryUri,
    );
    if (response is ErrorRef) {
      throw PanelException(response.message ?? 'Could not find the object.');
    }
    if (response is! InstanceRef ||
        response.kind == 'Null' ||
        response.id == null) {
      return null;
    }
    final object = await client.getObject(response.id!);
    if (object is! Instance) return null;
    final (clazz, libraryUri) = await _classInfo(object);
    return (
      instance: object,
      clazz: clazz,
      libraryUri: libraryUri,
      stateLibraryUri: state.libraryUri,
    );
  }

  Future<({Instance instance, Class? clazz, String? libraryUri})?>
      _resolveHeap(LogicRow row) async {
    if (row.rootVariable != null) {
      final response = await client.evaluate(row.rootVariable!);
      if (response is! InstanceRef ||
          response.kind == 'Null' ||
          response.id == null) {
        return null;
      }
      final object = await client.getObject(response.id!);
      if (object is! Instance) return null;
      final (clazz, libraryUri) = await _classInfo(object);
      return (instance: object, clazz: clazz, libraryUri: libraryUri);
    }
    if (row.classId == null && row.heapObjectId == null) return null;
    if (row.heapObjectId != null) {
      final object = await client.getObject(row.heapObjectId!);
      if (object is! Instance) return null;
      final (clazz, libraryUri) = await _classInfo(object);
      return (instance: object, clazz: clazz, libraryUri: libraryUri);
    }
    if (row.classId == null || row.identityHashCode == null) return null;
    final instances = await client.getInstances(
      row.classId!,
      100,
      includeSubclasses: true,
    );
    for (final reference in instances?.instances ?? const <ObjRef>[]) {
      if (reference is! InstanceRef) continue;
      if (reference.identityHashCode?.toString() != row.identityHashCode) {
        continue;
      }
      final id = reference.id;
      if (id == null) continue;
      final object = await client.getObject(id);
      if (object is! Instance) continue;
      final (clazz, libraryUri) = await _classInfo(object);
      return (instance: object, clazz: clazz, libraryUri: libraryUri);
    }
    return null;
  }

  Future<({String id})?> _resolveHeapTarget(InspectTarget active) async {
    if (active.rootVariable != null) {
      final response = await client.evaluate(active.rootVariable!);
      if (response is InstanceRef &&
          response.kind != 'Null' &&
          response.id != null) {
        return (id: response.id!);
      }
      return null;
    }
    if (active.heapObjectId != null) {
      return (id: active.heapObjectId!);
    }
    if (active.classId == null || active.identityHashCode == null) return null;
    final instances = await client.getInstances(
      active.classId!,
      100,
      includeSubclasses: true,
    );
    for (final reference in instances?.instances ?? const <ObjRef>[]) {
      if (reference is! InstanceRef) continue;
      if (reference.identityHashCode?.toString() == active.identityHashCode &&
          reference.id != null) {
        return (id: reference.id!);
      }
    }
    return null;
  }

  Future<(Class?, String?)> _classInfo(Instance instance) async {
    final classRef = instance.classRef;
    String? libraryUri = classRef?.library?.uri;
    Class? clazz;
    final classId = classRef?.id;
    if (classId != null) {
      try {
        final object = await client.getObject(classId);
        if (object is Class) {
          clazz = object;
          libraryUri ??= object.library?.uri;
        }
      } catch (_) {
        // The instance is still usable for its field values.
      }
    }
    return (clazz, libraryUri);
  }

  Future<String> _evaluateJson(
    String expression, {
    String? libraryUri,
    Map<String, String>? scope,
    bool retryOnUndefined = false,
  }) async {
    var usedLibrary = libraryUri;
    var response = await client.evaluate(
      expression,
      libraryUri: usedLibrary,
      scope: scope,
    );
    if (retryOnUndefined &&
        response is ErrorRef &&
        (response.message ?? '').contains('Undefined name')) {
      final fallback = await _fallbackFlutterLibrary();
      if (fallback != null && fallback != usedLibrary) {
        usedLibrary = fallback;
        response = await client.evaluate(
          expression,
          libraryUri: fallback,
          scope: scope,
        );
      }
    }
    if (response is ErrorRef) {
      throw PanelException(
        '${response.message ?? 'Evaluate failed.'}\n'
        'Library: ${usedLibrary ?? 'app root'}',
      );
    }
    if (response is Sentinel) {
      throw const PanelException('The object was collected.');
    }
    if (response is InstanceRef && response.valueAsString != null) {
      return response.valueAsString!;
    }
    throw PanelException(
      'Evaluate returned ${response.runtimeType}, not a JSON string.',
    );
  }

  Future<String?> _fallbackFlutterLibrary() async {
    final isolate = await client.getIsolate();
    final uris = (isolate?.libraries ?? const <LibraryRef>[])
        .map((library) => library.uri)
        .whereType<String>()
        .toList();
    for (final preferred in const [
      'package:flutter/material.dart',
      'package:flutter/widgets.dart',
      'package:flutter/src/widgets/binding.dart',
    ]) {
      if (uris.contains(preferred)) return preferred;
    }
    return null;
  }

  void _throwOnError(Response response, String? libraryUri) {
    if (response is ErrorRef) {
      throw PanelException(
        '${response.message ?? 'Evaluate failed.'}\n'
        'Library: ${libraryUri ?? 'app root'}',
      );
    }
    if (response is Sentinel) {
      throw const PanelException('The object was collected.');
    }
  }

  void _requireConnection() {
    if (!isConnected) {
      throw const PanelException(
        'Open DevTools on a flutter run debug session. No Flutter isolate is '
        'connected.',
      );
    }
  }

  String _censusError(String? error) {
    return switch (error) {
      'no-root' => 'The app has no root element yet.',
      'no-current-route' => 'No current route is visible.',
      _ => 'Could not read the current screen: ${error ?? 'unknown error'}.',
    };
  }

  Future<void> _busyRun(Future<void> Function() body) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await body();
    } on PanelException catch (failure) {
      error = failure.message;
    } on StateError catch (failure) {
      error = failure.message;
    } catch (failure) {
      error = failure.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static bool _sameTexts(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static FieldRow? _firstEditable(List<FieldRow> rows) {
    for (final row in rows) {
      if (row.editable) return row;
    }
    return null;
  }

  static FieldRow? _first(List<FieldRow> rows) {
    return rows.isEmpty ? null : rows.first;
  }
}
