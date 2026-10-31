/// Applies refresh actions to a connected app.
library;

import 'package:flutter_ai_whisper/refresh/refresh_plan.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:vm_service/vm_service.dart';

/// Outcome of one refresh call.
class ActionResult {
  /// Creates a result.
  const ActionResult({
    required this.label,
    required this.ok,
    required this.detail,
  });

  /// Step or `Class.method` that ran.
  final String label;

  /// Whether the call was accepted.
  final bool ok;

  /// VM or evaluator detail.
  final String detail;

  @override
  String toString() => '$label: $detail';
}

/// The subset of the VM connection the refresh loop needs.
abstract class RefreshClient {
  /// Whether [VmBridge.connect] has succeeded.
  bool get isConnected;

  /// Compiles the saved libraries into the running isolate.
  ///
  /// [VmService.evaluate] can only run a method that is already loaded. A
  /// widget edit stays invisible until this succeeds.
  Future<ActionResult> loadLibraries();

  /// Evaluates [expression] in [libraryUri].
  Future<ActionResult> evaluate({
    required String label,
    required String libraryUri,
    required String expression,
  });

  /// Invokes [methodName] on live instances of [className].
  Future<ActionResult> invoke({
    required String label,
    required String libraryUri,
    required String className,
    required String methodName,
  });
}

/// [RefreshClient] backed by a [VmBridge].
class VmRefreshClient implements RefreshClient {
  /// Creates a client that evaluates and reloads through [bridge].
  VmRefreshClient(this._bridge);

  final VmBridge _bridge;

  @override
  bool get isConnected => _bridge.isConnected;

  @override
  Future<ActionResult> loadLibraries() async {
    try {
      final response = await _bridge.callReloadSources();
      if (response is ReloadReport && response.success == false) {
        final notice = response.json?['notices'];
        return ActionResult(
          label: 'loadLibraries',
          ok: false,
          detail: notice?.toString() ?? 'reload rejected',
        );
      }
      return _fromResponse('loadLibraries', response);
    } on Object catch (error) {
      return ActionResult(label: 'loadLibraries', ok: false, detail: '$error');
    }
  }

  @override
  Future<ActionResult> evaluate({
    required String label,
    required String libraryUri,
    required String expression,
  }) async {
    try {
      final response = await _bridge.evaluate(
        expression,
        libraryUri: libraryUri,
      );
      return _fromResponse(label, response);
    } on Object catch (error) {
      return ActionResult(label: label, ok: false, detail: '$error');
    }
  }

  @override
  Future<ActionResult> invoke({
    required String label,
    required String libraryUri,
    required String className,
    required String methodName,
  }) async {
    try {
      final classList = await _bridge.getClassList();
      if (classList == null) {
        return ActionResult(
          label: label,
          ok: false,
          detail:
              'Heap enumeration is unavailable on this target, so '
              '$className.$methodName was not called.',
        );
      }
      final classes = classList.classes ?? const <ClassRef>[];
      final byLibrary = classes
          .where(
            (ref) => ref.name == className && ref.library?.uri == libraryUri,
          )
          .toList();
      final matches = byLibrary.isNotEmpty
          ? byLibrary
          : classes.where((ref) => ref.name == className).toList();
      if (matches.isEmpty) {
        return ActionResult(
          label: label,
          ok: false,
          detail: 'No loaded class named $className.',
        );
      }
      if (matches.length != 1) {
        return ActionResult(
          label: label,
          ok: false,
          detail: 'More than one loaded class is named $className.',
        );
      }
      final classId = matches.single.id;
      if (classId == null) {
        return ActionResult(
          label: label,
          ok: false,
          detail: '$className has no VM id.',
        );
      }
      final instances = await _bridge.getInstances(classId, 5);
      final objects = instances?.instances ?? const [];
      if (objects.isEmpty) {
        return ActionResult(
          label: label,
          ok: false,
          detail: 'No live instance of $className.',
        );
      }
      final details = <String>[];
      var ok = false;
      for (final object in objects) {
        final id = object.id;
        if (id == null) continue;
        final response = await _bridge.invoke(id, methodName, const []);
        final result = _fromResponse(label, response);
        details.add(result.detail);
        ok = ok || result.ok;
      }
      return ActionResult(
        label: label,
        ok: ok,
        detail: details.isEmpty ? 'No instance id.' : details.join('; '),
      );
    } on Object catch (error) {
      return ActionResult(label: label, ok: false, detail: '$error');
    }
  }
}

ActionResult _fromResponse(String label, Response response) {
  if (response is ErrorRef) {
    return ActionResult(
      label: label,
      ok: false,
      detail: response.message ?? 'call failed',
    );
  }
  if (response is InstanceRef) {
    return ActionResult(
      label: label,
      ok: true,
      detail: response.valueAsString ?? 'ok',
    );
  }
  return ActionResult(label: label, ok: true, detail: 'ok');
}

/// Runs [actions] in order.
Future<List<ActionResult>> runRefreshActions(
  RefreshClient client,
  List<RefreshAction> actions,
) async {
  final results = <ActionResult>[];
  for (final action in actions) {
    final ActionResult result;
    switch (action) {
      case EvaluateAction(:final label, :final libraryUri, :final expression):
        result = await client.evaluate(
          label: label,
          libraryUri: libraryUri,
          expression: expression,
        );
      case InvokeAction(
        :final label,
        :final libraryUri,
        :final className,
        :final methodName,
      ):
        result = await client.invoke(
          label: label,
          libraryUri: libraryUri,
          className: className,
          methodName: methodName,
        );
    }
    results.add(result);
    if (!result.ok) break;
  }
  return results;
}
