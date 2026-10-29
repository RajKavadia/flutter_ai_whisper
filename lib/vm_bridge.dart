/// Connection to one running app over the Dart VM Service.
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Whether [error] means the cached isolate is gone and must be selected again.
///
/// Flutter Web replaces the `main()` isolate on restart. A later
/// `reloadSources` call then fails with a collected sentinel instead of
/// recompiling.
bool staleIsolateError(Object error) {
  final text = error.toString();
  return text.contains('Collected') || text.contains('Unrecognized isolate');
}

/// Flutter Tools registers `reloadSources` as `sN.reloadSources`.
///
/// The raw VM method has no namespace. On the web it does not recompile, so a
/// source edit stays off the screen until something else hot reloads.
String? namespacedReloadService(
  Iterable<({String service, String method})> registrations,
) {
  for (final registration in registrations) {
    if (registration.service == 'reloadSources' &&
        registration.method.contains('.')) {
      return registration.method;
    }
  }
  return null;
}

/// Owns the VM Service WebSocket and evaluates Dart inside the app isolate.
class VmBridge {
  VmService? _vmService;
  String? _isolateId;
  String? _rootLibraryId;
  bool _supportsClassList = true;
  String? _reloadServiceMethod;
  Future<String?>? _reloadServiceLookup;
  StreamSubscription<Event>? _serviceSub;

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
    await _bindMainIsolate();
  }

  /// Selects the current `main()` isolate.
  ///
  /// The id cached at [connect] is stale after a web restart. Reload and
  /// reassemble both call this so they target the isolate that is alive now.
  Future<void> _bindMainIsolate() async {
    final service = _vmService;
    if (service == null) {
      throw StateError(
        'Not connected to a Flutter app. Call the connect_to_app tool with no '
        'arguments.',
      );
    }
    final vm = await service.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      throw StateError('VM Service connected but exposed no isolates.');
    }
    final mainIso = isolates.firstWhere(
      (isolate) => isolate.name == 'main()',
      orElse: () => isolates.first,
    );
    final id = mainIso.id;
    if (id == null) {
      throw StateError('The main isolate has no id.');
    }
    final previous = _isolateId;
    _isolateId = id;
    final isolate = await service.getIsolate(id);
    _rootLibraryId = isolate.rootLib!.id;
    if (previous != id) {
      _supportsClassList = await _detectClassListSupport();
    }
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
    await _serviceSub?.cancel();
    _serviceSub = null;
    try {
      await _vmService?.dispose();
    } catch (_) {}
    _reloadServiceMethod = null;
    _reloadServiceLookup = null;
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
    await _bindMainIsolate();
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

  /// Calls a VM service extension on the connected isolate.
  Future<Response> callServiceExtension(String method) async {
    _ensureConnected();
    await _bindMainIsolate();
    return _vmService!.callServiceExtension(method, isolateId: _isolateId);
  }

  /// Invokes Flutter's registered `reloadSources` service when the tool
  /// registered one, and the VM method otherwise.
  ///
  /// Flutter Tools compiles the updated libraries and hot reloads. That is
  /// what makes the following method calls run the new source. The service
  /// name is `sN.reloadSources`; `getVM` does not list it, so it is read from
  /// the Service stream, which replays registrations to a new subscriber.
  Future<Response> callReloadSources() async {
    _ensureConnected();
    await _bindMainIsolate();
    final method = await _flutterReloadMethod();
    try {
      return await _invokeReload(method);
    } on SentinelException catch (error) {
      if (!staleIsolateError(error)) rethrow;
      await _bindMainIsolate();
      return _invokeReload(method);
    }
  }

  Future<Response> _invokeReload(String method) {
    return _vmService!.callServiceExtension(
      method,
      isolateId: _isolateId,
      args: <String, dynamic>{'force': false, 'pause': false},
    );
  }

  /// The Flutter Tools `reloadSources` method, or the raw VM method.
  Future<String> _flutterReloadMethod() async {
    final cached = _reloadServiceMethod;
    if (cached != null) return cached;
    _reloadServiceLookup ??= _captureReloadService();
    final method = await _reloadServiceLookup;
    return method ?? 'reloadSources';
  }

  Future<String?> _captureReloadService() async {
    final registrations = <({String service, String method})>[];
    final done = Completer<void>();
    _serviceSub = _vmService!.onServiceEvent.listen((event) {
      if (event.kind != EventKind.kServiceRegistered) return;
      final service = event.service;
      final method = event.method;
      if (service == null || method == null) return;
      registrations.add((service: service, method: method));
      final reload = namespacedReloadService(registrations);
      if (reload != null && !done.isCompleted) {
        _reloadServiceMethod = reload;
        done.complete();
      }
    });
    try {
      await _vmService!.streamListen(EventStreams.kService);
    } on RPCError {
      // A second subscriber does not get the registration replay.
    }
    if (!done.isCompleted) {
      await done.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
    return _reloadServiceMethod;
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
