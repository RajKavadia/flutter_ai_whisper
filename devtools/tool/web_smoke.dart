import 'dart:io';

import 'package:flutter_ai_whisper/discovery.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:flutter_ai_whisper_devtools/src/census.dart';
import 'package:vm_service/vm_service.dart';

/// Panel-style VM smoke test for Flutter Web. Run while
/// `flutter run -d chrome` is active in `example/`.
///
/// Optional: `dart run tool/web_smoke.dart ws://127.0.0.1:PORT/AUTH=/ws`
Future<void> main(List<String> args) async {
  final bridge = VmBridge();
  try {
    final uri = args.isNotEmpty
        ? args.first
        : await _discoverUri();
    if (uri == null) {
      stderr.writeln(
        'No debug app found. Run: cd example && flutter run -d chrome',
      );
      exit(1);
    }
    stderr.writeln('Connecting to $uri');
    await bridge.connect(uri);

    final census = ScreenCensus.parse(
      await _evaluateJson(bridge, Census.screen()),
    );
    if (!census.ok) {
      throw StateError('Census failed: ${census.error}');
    }
    stderr.writeln('Route: ${census.route}, rows: ${census.rows.length}');

    ScreenRow? home;
    for (final row in census.rows) {
      if (row.stateType.contains('HomePageState')) {
        home = row;
        break;
      }
    }
    home ??= census.rows.isEmpty ? null : census.rows.first;
    if (home == null) {
      throw StateError('No StatefulWidget on current route');
    }
    stderr.writeln('Target ${home.stateType}');

    final beforeTexts = ReadSnapshot.parse(
      await _evaluateJson(bridge, Census.readCurrentRouteTexts()),
    );
    final assignResult = await bridge.evaluate(
      Census.assignStateField(
        finderKey: home.finderKey,
        stateType: home.stateType,
        field: '_localCounter',
        literal: '99',
      ),
      libraryUri: 'package:flutter_ai_whisper_example/main.dart',
    );
    if (assignResult is ErrorRef) {
      throw StateError('Assign failed: ${assignResult.message}');
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
    final afterTexts = ReadSnapshot.parse(
      await _evaluateJson(bridge, Census.readCurrentRouteTexts()),
    );
    if (!afterTexts.texts.any((t) => t.contains('local: 99'))) {
      stderr.writeln('Before: ${beforeTexts.texts}');
      stderr.writeln('After: ${afterTexts.texts}');
      throw StateError('Text did not update to local: 99');
    }
    stdout.writeln('OK web smoke: Screen census, assign, Text on Chrome');
  } finally {
    await bridge.disconnect();
  }
}

Future<String?> _discoverUri() async {
  final apps = await VmServiceDiscovery.discoverApps(
    workspaceFilter: r'flutter_ai_whisper\example',
  );
  if (apps.isEmpty) {
    final any = await VmServiceDiscovery.discoverApps();
    if (any.length == 1) return any.first.vmServiceUri;
    return null;
  }
  return apps.first.vmServiceUri;
}

Future<String> _evaluateJson(VmBridge bridge, String expression) async {
  final response = await bridge.evaluate(expression);
  if (response is ErrorRef) {
    throw StateError(response.message ?? 'evaluate failed');
  }
  if (response is! InstanceRef || response.valueAsString == null) {
    throw StateError('Expected JSON string, got $response');
  }
  return response.valueAsString!;
}
