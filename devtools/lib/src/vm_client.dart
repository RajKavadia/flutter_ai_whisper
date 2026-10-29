import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:vm_service/vm_service.dart';

/// The VM Service operations the panel needs.
///
/// Kept behind an interface so the controller can be tested without a device.
abstract interface class VmClient {
  /// Whether a debug app is connected and has a main isolate.
  bool get isConnected;

  /// The main isolate id, when connected.
  String? get isolateId;

  /// A short app or isolate name for the header.
  String? get appName;

  /// Evaluates [expression] in [libraryUri] or the root library.
  Future<Response> evaluate(
    String expression, {
    String? libraryUri,
    Map<String, String>? scope,
  });

  /// Reads a VM object by id.
  Future<Obj> getObject(String objectId);

  /// Returns the class list, or `null` when the VM does not support it.
  Future<ClassList?> getClassList();

  /// Returns live instances of [classId], or `null` when unavailable.
  Future<InstanceSet?> getInstances(
    String classId,
    int limit, {
    bool? includeSubclasses,
  });

  /// Returns the root library, or `null` when unavailable.
  Future<Library?> getRootLibrary();

  /// Returns the main isolate, or `null` when disconnected.
  Future<Isolate?> getIsolate();
}

/// A [VmClient] backed by the VM Service connection DevTools already holds.
class DevToolsVmClient implements VmClient {
  @override
  bool get isConnected {
    if (!serviceManager.connectedState.value.connected) return false;
    return serviceManager.service != null &&
        serviceManager.isolateManager.mainIsolate.value?.id != null;
  }

  @override
  String? get isolateId =>
      serviceManager.isolateManager.mainIsolate.value?.id;

  @override
  String? get appName =>
      serviceManager.isolateManager.mainIsolate.value?.name;

  VmService get _service {
    final service = serviceManager.service;
    if (service == null) {
      throw StateError(
        'Open DevTools on a flutter run debug session. There is no VM Service '
        'connection.',
      );
    }
    return service;
  }

  String get _isolateId {
    final id = isolateId;
    if (id == null) {
      throw StateError(
        'No Flutter isolate is selected. Open DevTools on a flutter run debug '
        'session.',
      );
    }
    return id;
  }

  @override
  Future<Response> evaluate(
    String expression, {
    String? libraryUri,
    Map<String, String>? scope,
  }) async {
    final targetId = await _targetIdFor(libraryUri);
    return _service.evaluate(
      _isolateId,
      targetId,
      expression,
      scope: scope,
      disableBreakpoints: true,
    );
  }

  Future<String> _targetIdFor(String? libraryUri) async {
    final isolate = await getIsolate();
    if (isolate == null) {
      throw StateError('No Flutter isolate is available.');
    }
    if (libraryUri == null || libraryUri.isEmpty) {
      final rootId = isolate.rootLib?.id;
      if (rootId == null) {
        throw StateError('The app isolate has no root library.');
      }
      return rootId;
    }
    final libraries = isolate.libraries ?? const <LibraryRef>[];
    for (final library in libraries) {
      if (library.uri == libraryUri) {
        final id = library.id;
        if (id == null) {
          throw StateError('Library $libraryUri has no VM id.');
        }
        return id;
      }
    }
    final available = libraries
        .map((library) => library.uri)
        .whereType<String>()
        .where((uri) => !uri.startsWith('dart:'))
        .toList()
      ..sort();
    throw StateError(
      'No library in the isolate matches "$libraryUri".\n'
      'App libraries: ${available.join(', ')}',
    );
  }

  @override
  Future<Obj> getObject(String objectId) {
    return _service.getObject(_isolateId, objectId);
  }

  @override
  Future<ClassList?> getClassList() async {
    try {
      return await _service.getClassList(_isolateId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<InstanceSet?> getInstances(
    String classId,
    int limit, {
    bool? includeSubclasses,
  }) async {
    try {
      return await _service.getInstances(
        _isolateId,
        classId,
        limit,
        includeSubclasses: includeSubclasses,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Library?> getRootLibrary() async {
    final isolate = await getIsolate();
    final rootId = isolate?.rootLib?.id;
    if (rootId == null) return null;
    final object = await getObject(rootId);
    return object is Library ? object : null;
  }

  @override
  Future<Isolate?> getIsolate() async {
    if (!isConnected) return null;
    return _service.getIsolate(_isolateId);
  }
}
