import 'package:vm_service/vm_service.dart';
import 'vm_bridge.dart';

/// Discovers live state holders inside the connected app isolate.
///
/// Two strategies are used, because neither is available everywhere:
///
///  * Native (VM desktop / mobile): `getClassList` + `getInstances` finds live
///    objects whose class name looks like state. Also scans top-level
///    library variables.
///  * Flutter Web: neither RPC exists (and `dart:mirrors` is unavailable), so
///    enumeration is impossible. Callers must instead *name* the holders and
///    have them probed with [probeExpressions].
class StateDiscoverer {
  final VmBridge _bridge;

  StateDiscoverer(this._bridge);

  static const _namePatterns = [
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

  Future<List<Map<String, dynamic>>> discoverStateHolders() async {
    final holders = <Map<String, dynamic>>[];
    holders.addAll(await _discoverByClassName());
    holders.addAll(await _discoverByLibraryVariables());
    return holders;
  }

  Future<List<Map<String, dynamic>>> _discoverByClassName() async {
    final holders = <Map<String, dynamic>>[];
    final classList = await _bridge.getClassList();
    if (classList == null) return holders;

    final stateClasses =
        (classList.classes ?? [])
            .where((c) => _looksLikeStateHolder(c.name ?? ''))
            .toList();

    for (final classRef in stateClasses) {
      final id = classRef.id;
      if (id == null) continue;
      final instances = await _bridge.getInstances(
        id,
        10,
        includeSubclasses: true,
      );
      for (final instance in instances?.instances ?? const <InstanceRef>[]) {
        holders.add({
          'name': classRef.name,
          'source': 'instance',
          'instanceId': instance.id,
          'value': (instance as InstanceRef).valueAsString,
          'classId': id,
        });
      }
    }
    return holders;
  }

  Future<List<Map<String, dynamic>>> _discoverByLibraryVariables() async {
    final holders = <Map<String, dynamic>>[];
    if (!_bridge.supportsClassList) return holders;

    Library root;
    try {
      root = await _bridge.getRootLibrary();
    } catch (_) {
      return holders;
    }

    // Empty on Flutter Web.
    for (final field in root.variables ?? const <FieldRef>[]) {
      if (_looksLikeStateHolder(field.name ?? '')) {
        holders.add({
          'name': field.name,
          'source': 'library-variable',
          'libraryUri': root.uri,
          'fieldId': field.id,
        });
      }
    }
    return holders;
  }

  /// Probes caller-supplied expressions and reports each value.
  ///
  /// This is the only enumeration strategy available on Flutter Web, where the
  /// agent is expected to derive names from the app's source code.
  Future<List<Map<String, dynamic>>> probeExpressions(
    List<String> expressions, {
    String? libraryUri,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final expr in expressions) {
      try {
        final response = await _bridge.evaluate(expr, libraryUri: libraryUri);
        if (response is ErrorRef) {
          out.add({'expression': expr, 'error': response.message});
        } else {
          final ref = response as InstanceRef;
          out.add({
            'expression': expr,
            'value': ref.valueAsString,
            'id': ref.id,
            'class': ref.classRef?.name,
          });
        }
      } catch (e) {
        out.add({'expression': expr, 'error': e.toString()});
      }
    }
    return out;
  }

  bool _looksLikeStateHolder(String name) =>
      _namePatterns.any((p) => name.contains(p));
}
