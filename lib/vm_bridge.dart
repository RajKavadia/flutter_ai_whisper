/// Connection to one running app over the Dart VM Service.
library;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Owns the VM Service WebSocket and evaluates Dart inside the app isolate.
class VmBridge {
  VmService? _vmService;
  String? _isolateId;
  String? _rootLibraryId;
  bool _supportsClassList = true;

  /// Whether a VM Service session and an isolate are both selected.
  bool get isConnected => _vmService != null && _isolateId != null;

  /// Whether this isolate implements `getClassList`.
  ///
  /// Flutter Web does not, so heap enumeration is unavailable there.
  bool get supportsClassList => _supportsClassList;

  /// WebSocket URI of the current session, or `null` when disconnected.
  String? get connectedUri => _wsUri;
  String? _wsUri;

  /// Opens [wsUri], selects the `main()` isolate, and caches its root library.
  ///
  /// Throws a [StateError] when the VM exposes no isolates.
  Future<void> connect(String wsUri) async {
    await disconnect();
    _vmService = await vmServiceConnectUri(wsUri);
    _wsUri = wsUri;

    final vm = await _vmService!.getVM();
    final isolates = vm.isolates ?? [];
    if (isolates.isEmpty) {
      throw StateError('VM Service connected but exposed no isolates.');
    }

    // Prefer the isolate backed by the app's main() entrypoint.
    final mainIso = isolates.firstWhere(
      (i) => i.name == 'main()',
      orElse: () => isolates.first,
    );
    _isolateId = mainIso.id;

    final isolate = await _vmService!.getIsolate(_isolateId!);
    _rootLibraryId = isolate.rootLib!.id;

    // Flutter Web (dart2js/DDC) does not implement getClassList.
    _supportsClassList = await _detectClassListSupport();
  }

  Future<bool> _detectClassListSupport() async {
    try {
      await _vmService!.getClassList(_isolateId!);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Closes the current session and clears cached isolate state.
  Future<void> disconnect() async {
    try {
      await _vmService?.dispose();
    } catch (_) {}
    _vmService = null;
    _isolateId = null;
    _rootLibraryId = null;
    _wsUri = null;
  }

  /// Evaluates [expression] in one library scope.
  ///
  /// [libraryUri] selects that library. When it is omitted, evaluation uses
  /// the app's root library, where private names from other libraries do not
  /// compile.
  ///
  /// Throws a [StateError] when no app is connected.
  Future<Response> evaluate(String expression, {String? libraryUri}) async {
    _ensureConnected();
    return _vmService!.evaluate(
      _isolateId!,
      await targetIdFor(libraryUri),
      expression,
    );
  }

  /// Resolves a library URI to a VM object id, defaulting to the app's root
  /// library.
  ///
  /// Evaluating in a *specific* library's scope is what makes private
  /// members reachable: `_localCounter` is private to `pages/home_page.dart`,
  /// so it is invisible when evaluating against the root library, but visible
  /// when evaluating against its own library.
  Future<String> targetIdFor(String? libraryUri) async {
    _ensureConnected();
    if (libraryUri == null || libraryUri.isEmpty) return _rootLibraryId!;

    final isolate = await getIsolate();
    for (final lib in isolate.libraries ?? const <LibraryRef>[]) {
      if (lib.uri == libraryUri) {
        if (lib.id == null) {
          throw StateError('Library $libraryUri has no id.');
        }
        return lib.id!;
      }
    }
    final available = (isolate.libraries ?? const <LibraryRef>[])
        .map((l) => l.uri)
        .whereType<String>()
        .where((u) => !u.startsWith('dart:'))
        .toList();
    throw StateError(
      'No library in the isolate matches "$libraryUri".\n'
      'App libraries: ${available.join(", ")}',
    );
  }

  /// Evaluates [expression] and returns its value as a string,
  /// or null when the expression is not a value expression.
  Future<String?> probe(String expression) async {
    final result = await evaluate(expression);
    if (result is ErrorRef) return null;
    return (result as InstanceRef).valueAsString;
  }

  /// Returns the isolate's class list, or `null` when the VM does not
  /// implement `getClassList`.
  Future<ClassList?> getClassList() async {
    _ensureConnected();
    if (!_supportsClassList) return null;
    try {
      return await _vmService!.getClassList(_isolateId!);
    } catch (_) {
      _supportsClassList = false;
      return null;
    }
  }

  /// Returns up to [limit] live instances of [classId].
  ///
  /// Returns `null` when heap enumeration is unavailable or the call fails.
  /// [includeSubclasses] includes instances of subclasses when the VM
  /// supports it.
  Future<InstanceSet?> getInstances(
    String classId,
    int limit, {
    bool? includeSubclasses,
  }) async {
    _ensureConnected();
    if (!_supportsClassList) return null;
    try {
      return await _vmService!.getInstances(
        _isolateId!,
        classId,
        limit,
        includeSubclasses: includeSubclasses,
      );
    } catch (_) {
      return null;
    }
  }

  /// Invokes [selector] on [targetId] with [argumentIds].
  Future<Response> invoke(
    String targetId,
    String selector,
    List<String> argumentIds,
  ) async {
    _ensureConnected();
    return _vmService!.invoke(_isolateId!, targetId, selector, argumentIds);
  }

  /// Returns the connected isolate.
  Future<Isolate> getIsolate() async {
    _ensureConnected();
    return _vmService!.getIsolate(_isolateId!);
  }

  /// Returns the app's root library.
  Future<Library> getRootLibrary() async {
    _ensureConnected();
    final isolate = await getIsolate();
    return await _vmService!.getObject(_isolateId!, isolate.rootLib!.id!)
        as Library;
  }

  /// Returns the VM object identified by [objectId].
  Future<Obj> getObject(String objectId) async {
    _ensureConnected();
    return _vmService!.getObject(_isolateId!, objectId);
  }

  /// VM object id of the app's root library.
  String get rootLibraryId {
    _ensureConnected();
    return _rootLibraryId!;
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError(
        'Not connected to a Flutter app. Call the connect_to_app tool with no '
        'arguments: it discovers the running app automatically via the Dart '
        'Tooling Daemon. Do not copy the URI printed by `flutter run` — its '
        'path segment is a per-run auth code that goes stale on every '
        'relaunch.',
      );
    }
  }
}
