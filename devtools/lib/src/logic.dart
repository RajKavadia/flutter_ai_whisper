import 'package:vm_service/vm_service.dart';

import 'census.dart';

/// One logic object reachable from the screen or found on the heap.
class LogicRow {
  const LogicRow({
    required this.name,
    required this.type,
    required this.source,
    this.finderKey,
    this.stateType,
    this.holderField,
    this.libraryUri,
    this.identityHashCode,
    this.heapObjectId,
    this.classId,
    this.rootVariable,
    this.valuePreview,
  });

  /// Field name on the State, or class name for a heap row.
  final String name;

  /// Runtime type of the logic object.
  final String type;

  /// `screen` for route-reachable objects, `heap` for native enumeration.
  final String source;

  /// Finder key of the screen State that holds this object.
  final String? finderKey;

  /// Runtime type of the screen State.
  final String? stateType;

  /// Field on the State that holds this object.
  final String? holderField;

  /// Declaring library of the object's class.
  final String? libraryUri;

  /// Identity hash used to re-find a heap object after a rebuild.
  final String? identityHashCode;

  /// VM object id captured from heap enumeration.
  final String? heapObjectId;

  /// VM class id used to re-run `getInstances`.
  final String? classId;
  /// Root-library variable name for a discovered library variable.
  final String? rootVariable;

  /// A short value preview.
  final String? valuePreview;

  /// Whether this row came from heap enumeration.
  bool get fromHeap => source == 'heap';

  /// Whether [query] matches the row.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        type.toLowerCase().contains(needle) ||
        (valuePreview ?? '').toLowerCase().contains(needle);
  }
}

/// Type-name heuristics shared with the MCP server's StateDiscoverer.
abstract final class LogicPatterns {
  /// Class-name fragments that look like state holders.
  static const List<String> patterns = [
    'Bloc',
    'Notifier',
    'State',
    'Provider',
    'Cubit',
    'Store',
    'Controller',
    'Manager',
    'Model',
    'ViewModel',
  ];

  /// Whether [type] looks like a state holder.
  static bool matches(String type) {
    return patterns.any(type.contains);
  }

  /// Whether [type] is expected to notify listeners on its own.
  static bool notifies(String type) {
    return type.contains('ValueNotifier') ||
        type.contains('ChangeNotifier') ||
        type.contains('Cubit') ||
        type.contains('Bloc') ||
        type.contains('Rx') ||
        type.contains('GetxController');
  }
}

/// Extracts displayable fields from a VM instance.
abstract final class FieldExtractor {
  /// Builds rows from [instance] and its [clazz].
  ///
  /// [accessibleLibrary] is the library the generated write expression will
  /// be compiled in. A private field is editable only when its declaring
  /// library matches, because Dart privacy is library-scoped.
  static List<FieldRow> fromInstance(
    Instance instance, {
    Class? clazz,
    required String? accessibleLibrary,
    required bool preferPublic,
  }) {
    final rows = <FieldRow>[];
    final functions = clazz?.functions ?? const <FuncRef>[];
    final publicGetters = <String, FuncRef>{};
    final setters = <String>{};
    final methods = <String>[];
    for (final function in functions) {
      final name = function.name ?? '';
      if (name.isEmpty) continue;
      if (function.isStatic == true) continue;
      if (function.isGetter == true) {
        publicGetters[_baseName(name)] = function;
      } else if (function.isSetter == true) {
        setters.add(_baseName(name));
      } else if (!name.startsWith('_') &&
          !name.startsWith('operator ') &&
          name != 'toString' &&
          name != 'noSuchMethod' &&
          name != 'runtimeType' &&
          name != 'hashCode' &&
          name != '==') {
        methods.add(name);
      }
    }

    final instanceNames = <String>{};
    for (final bound in instance.fields ?? const <BoundField>[]) {
      final decl = bound.decl;
      final name = (bound.name is String ? bound.name as String : null) ??
          decl?.name ??
          '';
      if (name.isEmpty) continue;
      if (decl?.isStatic == true) continue;
      final ownerLibrary = _ownerLibrary(decl);
      if (_isFrameworkLibrary(ownerLibrary)) continue;
      final isPrivate = name.startsWith('_');
      final base = _baseName(name);
      if (preferPublic && isPrivate && publicGetters.containsKey(base)) {
        continue;
      }
      final value = bound.value;
      final declared = _declaredType(decl);
      final type = declared ?? _typeOf(value) ?? '';
      final canReach = !isPrivate ||
          (ownerLibrary != null &&
              accessibleLibrary != null &&
              ownerLibrary == accessibleLibrary);
      final editable = decl?.isFinal != true &&
          decl?.isConst != true &&
          canReach;
      rows.add(
        FieldRow(
          name: name,
          type: type,
          value: _preview(value),
          editable: editable,
          readOnlyReason: editable
              ? null
              : _fieldReason(decl, canReach, ownerLibrary),
          suggestedMethod: editable ? null : _firstMethod(methods),
        ),
      );
      instanceNames.add(name);
    }

    for (final entry in publicGetters.entries) {
      final base = entry.key;
      if (instanceNames.contains(base)) continue;
      if (base.startsWith('_') && !preferPublic) continue;
      final hasSetter = setters.contains(base);
      rows.add(
        FieldRow(
          name: base,
          type: '',
          value: '(getter)',
          editable: hasSetter,
          readOnlyReason: hasSetter ? null : 'Getter has no setter.',
          suggestedMethod: hasSetter ? null : _firstMethod(methods),
        ),
      );
    }

    rows.sort((a, b) {
      final aPrivate = a.name.startsWith('_') ? 1 : 0;
      final bPrivate = b.name.startsWith('_') ? 1 : 0;
      if (aPrivate != bPrivate) return aPrivate - bPrivate;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  static String _baseName(String name) {
    if (name.endsWith('=')) return name.substring(0, name.length - 1);
    return name;
  }

  static String? _ownerLibrary(FieldRef? decl) {
    final owner = decl?.owner;
    if (owner is ClassRef) return owner.library?.uri;
    if (owner is LibraryRef) return owner.uri;
    return null;
  }

  static bool _isFrameworkLibrary(String? uri) {
    if (uri == null) return false;
    return uri.startsWith('dart:') || uri.startsWith('package:flutter/');
  }

  static String? _declaredType(FieldRef? decl) {
    final type = decl?.declaredType;
    return type?.classRef?.name ?? type?.valueAsString;
  }

  static String? _typeOf(Object? value) {
    if (value is InstanceRef) {
      final name = value.classRef?.name;
      if (name == 'Null') return null;
      return name ?? value.valueAsString;
    }
    if (value is Sentinel) return null;
    return null;
  }

  static String _preview(Object? value) {
    if (value is InstanceRef) {
      return value.valueAsString ?? value.classRef?.name ?? '(value)';
    }
    if (value is Sentinel) return '(collected)';
    return '(unknown)';
  }

  static String? _fieldReason(
    FieldRef? decl,
    bool canReach,
    String? ownerLibrary,
  ) {
    if (!canReach) {
      return 'Private to ${ownerLibrary ?? 'another library'}; '
          'run the write in that library.';
    }
    if (decl?.isConst == true) return 'Const field.';
    if (decl?.isFinal == true) return 'Final field.';
    return null;
  }

  static String? _firstMethod(List<String> methods) {
    return null;
  }
}
