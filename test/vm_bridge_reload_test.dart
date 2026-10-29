import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('a collected isolate is treated as stale', () {
    final error = SentinelException.parse('reloadSources', {
      'type': 'Sentinel',
      'kind': 'Collected',
      'valueAsString': 'Unrecognized isolateId: 1',
    });

    expect(staleIsolateError(error), isTrue);
    expect(staleIsolateError(StateError('not connected')), isFalse);
  });

  test('reload uses the Flutter Tools service, not the raw VM method', () {
    final method = namespacedReloadService(const [
      (service: 'hotRestart', method: 's1.hotRestart'),
      (service: 'reloadSources', method: 'reloadSources'),
      (service: 'reloadSources', method: 's2.reloadSources'),
    ]);

    expect(method, 's2.reloadSources');
    expect(namespacedReloadService(const []), isNull);
  });
}
