import 'package:flutter_ai_whisper_devtools/src/census.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke tests for expressions the panel evaluates in the app isolate.
void main() {
  test('screen census expression is one evaluate() string', () {
    final expr = Census.screen();
    expect(expr.trim(), startsWith('(() {'));
    expect(expr.trim(), endsWith('})()'));
    expect(expr, isNot(contains('\n;')));
  });

  test('assignStateField uses setState and real field name', () {
    final expr = Census.assignStateField(
      finderKey: '/|HomePage|_HomePageState|0|0',
      stateType: '_HomePageState',
      field: '_localCounter',
      literal: '12',
    );
    expect(expr, contains('setState'));
    expect(expr, contains('state._localCounter = 12'));
    expect(expr, isNot(contains('FIELD')));
  });

  test('readCurrentRouteTexts returns JSON shape', () {
    final expr = Census.readCurrentRouteTexts();
    expect(expr, contains('"texts"'));
    expect(expr, contains('"current"'));
  });
}
