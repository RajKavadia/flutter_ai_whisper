import 'package:flutter_ai_whisper_devtools/src/census.dart';
import 'package:flutter_ai_whisper_devtools/src/literal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Literals', () {
    test('rejects non-finite doubles', () {
      expect(
        () => Literals.parse('1e309', fieldType: 'double'),
        throwsA(isA<LiteralError>()),
      );
    });

    test('allows null for nullable int', () {
      final literal = Literals.parse('null', fieldType: 'int?');
      expect(literal.dart, 'null');
    });
  });

  group('Census.assignLogicField', () {
    test('embeds holder field and literal in body', () {
      final code = Census.assignLogicField(
        finderKey: '/|Home|_Home|0|0',
        stateType: '_HomeState',
        holderField: 'counterCubit',
        field: 'count',
        literal: '42',
        wrapInSetState: true,
      );
      expect(code, contains('state.counterCubit.count = 42'));
      expect(code, isNot(contains('HOLDER')));
      expect(code, isNot(contains('LITERAL')));
    });
  });
}
