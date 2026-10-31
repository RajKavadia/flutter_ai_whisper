import 'dart:io';

import 'package:flutter_ai_whisper/refresh/analysis_gate.dart';
import 'package:flutter_ai_whisper/refresh/change_refresh.dart';
import 'package:flutter_ai_whisper/refresh/dart_member.dart';
import 'package:flutter_ai_whisper/refresh/package_sources.dart';
import 'package:flutter_ai_whisper/refresh/parse_members.dart';
import 'package:flutter_ai_whisper/refresh/refresh_client.dart';
import 'package:flutter_ai_whisper/refresh/refresh_plan.dart';
import 'package:flutter_ai_whisper/tools/start_change_refresh.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:test/test.dart';

const _source = '''
class HomePage extends StatefulWidget {
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  void increment() { value++; }
  Widget build(context) => const SizedBox();
}

class Counter {
  void setValue() {}
  void setNamed({required int value}) {}
  static void reset() {}
}

void ping() {}
''';

void main() {
  group('parseDartMembers', () {
    test('names the changed class, method, and whether it can be called', () {
      final members = parseDartMembers(
        _source,
        libraryUri: 'package:sample/home.dart',
      );
      final byName = {for (final member in members) member.displayName: member};

      expect(byName['_HomePageState.increment']!.kind, DartMemberKind.state);
      expect(byName['_HomePageState.increment']!.widgetName, 'HomePage');
      expect(byName['_HomePageState.increment']!.callable, isTrue);
      expect(byName['_HomePageState.build']!.callable, isFalse);
      expect(byName['HomePage.createState']!.kind, DartMemberKind.widget);
      expect(byName['HomePage.createState']!.callable, isFalse);
      expect(byName['Counter.setValue']!.callable, isTrue);
      expect(byName['Counter.setNamed']!.callable, isFalse);
      expect(byName['Counter.reset']!.isStatic, isTrue);
      expect(byName['ping']!.kind, DartMemberKind.function);
    });
  });

  group('analysisIsClean', () {
    test('is true when the machine report has no errors', () {
      expect(analysisIsClean(''), isTrue);
      expect(
        analysisIsClean(
          'WARNING|STATIC_WARNING|UNUSED_IMPORT|C:\\a.dart|1|1|8|Unused.',
        ),
        isTrue,
      );
    });

    test('is false when an error is reported', () {
      expect(
        analysisIsClean(
          'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|a.dart|1|8|7|Undefined.',
        ),
        isFalse,
      );
    });
  });

  group('planRefresh', () {
    test('evaluates only the changed class method', () {
      final actions = planRefresh([
        const DartMember(
          libraryUri: 'package:sample/home.dart',
          className: '_HomePageState',
          methodName: 'increment',
          body: 'void increment() { value++; }',
          kind: DartMemberKind.state,
          widgetName: 'HomePage',
          isStatic: false,
          callable: true,
        ),
        const DartMember(
          libraryUri: 'package:sample/counter.dart',
          className: 'Counter',
          methodName: 'setValue',
          body: 'void setValue() {}',
          kind: DartMemberKind.logic,
          isStatic: false,
          callable: true,
        ),
      ]);

      expect(actions, hasLength(2));
      final state = actions.whereType<EvaluateAction>().single;
      expect(state.expression, contains('s.increment();'));
      expect(state.expression, contains('s.setState'));
      expect(state.libraryUri, 'package:sample/home.dart');
      final invoke = actions.whereType<InvokeAction>().single;
      expect(invoke.className, 'Counter');
      expect(invoke.methodName, 'setValue');
    });
  });

  group('ChangeRefreshController', () {
    late FakeClient client;
    late _MemorySources sources;
    late bool clean;
    var analyzeCount = 0;

    setUp(() {
      client = FakeClient();
      sources = _MemorySources({'lib/home.dart': _library(_source)});
      clean = true;
      analyzeCount = 0;
    });

    ChangeRefreshController controller() => ChangeRefreshController(
      readSources: sources.read,
      analyze: (_) async {
        analyzeCount++;
        return AnalysisResult(
          clean: clean,
          detail: clean ? '' : 'ERROR|COMPILE_TIME_ERROR|X|a.dart|1|1|1|bad',
        );
      },
      client: client,
    );

    test('does not call methods until a later edit analyzes clean', () async {
      final refresh = controller();
      await refresh.baseline('/app');
      final first = await refresh.refresh('/app');
      expect(first.unchanged, isTrue);
      expect(analyzeCount, 0);
      expect(client.calls, isEmpty);

      sources.files['lib/home.dart'] = _library(
        _source.replaceAll('value++;', 'value += 2;'),
      );
      clean = false;
      final blocked = await refresh.refresh('/app');
      expect(blocked.analysisClean, isFalse);
      expect(client.calls, isEmpty);

      clean = true;
      final applied = await refresh.refresh('/app');
      expect(
        applied.changed.map((member) => member.displayName),
        contains('_HomePageState.increment'),
      );
      expect(client.calls.first, 'loadLibraries');
      expect(client.calls, isNot(contains('reassemble')));
      expect(client.expressions.single, contains('s.increment();'));
      expect(client.invokes, isEmpty);
    });

    test('does not advance when the class call fails', () async {
      final refresh = controller();
      await refresh.baseline('/app');
      sources.files['lib/home.dart'] = _library(
        _source.replaceAll('void setValue() {}', 'void setValue() { mark(); }'),
      );
      client.invokeOk = false;
      final failed = await refresh.refresh('/app');
      expect(failed.advanced, isFalse);
      expect(client.calls, ['loadLibraries', 'Counter.setValue']);

      client.invokeOk = true;
      final retried = await refresh.refresh('/app');
      expect(retried.advanced, isTrue);
      expect(client.invokes, ['Counter.setValue', 'Counter.setValue']);
    });
  });

  group('change refresh tools', () {
    test('start_change_refresh requires a package root', () async {
      final result = await startChangeRefresh(
        _watch(connected: false),
        const {},
      );
      expect(result.isError, isTrue);
      expect(textOf(result), contains('packageRoot'));
    });

    test('start_change_refresh requires a connected app', () async {
      final result = await startChangeRefresh(_watch(connected: false), {
        'packageRoot': '/app',
      });
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Not connected'));
    });

    test('refresh_changed_members requires a connected app', () async {
      final result = await refreshChangedMembers(_watch(connected: false), {
        'packageRoot': '/app',
      });
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Not connected'));
    });
  });

  test('package sources map lib files to package URIs', () async {
    final root = await Directory.systemTemp.createTemp('whisper_pkg');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}${Platform.pathSeparator}.dart_tool').create();
    await File(
      '${root.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
    ).writeAsString('''
{"configVersion":2,"packages":[{"name":"sample","rootUri":"../","packageUri":"lib/"}]}
''');
    final lib = Directory('${root.path}${Platform.pathSeparator}lib');
    await lib.create();
    await File(
      '${lib.path}${Platform.pathSeparator}home.dart',
    ).writeAsString('class Home {}');

    final sources = await PackageSources().read(root.path);
    expect(sources.single.libraryUri, 'package:sample/home.dart');
  });
}

LibrarySource _library(String contents) => LibrarySource(
  path: 'lib/home.dart',
  libraryUri: 'package:sample/home.dart',
  contents: contents,
);

ChangeRefreshWatch _watch({required bool connected}) {
  final client = FakeClient()..connected = connected;
  return ChangeRefreshWatch(
    controller: ChangeRefreshController(
      readSources: (_) async => const [],
      analyze: (_) async => const AnalysisResult(clean: true, detail: ''),
      client: client,
    ),
    onReport: (message, {required bool isError}) {},
  );
}

String textOf(dynamic result) {
  final content = result.content as List<Object?>;
  return content
      .map((item) => item is TextContent ? item.text : item.toString())
      .join('\n');
}

class _MemorySources {
  _MemorySources(this.files);

  final Map<String, LibrarySource> files;

  Future<List<LibrarySource>> read(String packageRoot) async =>
      files.values.toList();
}

class FakeClient implements RefreshClient {
  var connected = true;
  var invokeOk = true;
  var loadOk = true;
  final calls = <String>[];
  final expressions = <String>[];
  final invokes = <String>[];

  @override
  bool get isConnected => connected;

  @override
  Future<ActionResult> loadLibraries() async {
    calls.add('loadLibraries');
    return ActionResult(
      label: 'loadLibraries',
      ok: loadOk,
      detail: loadOk ? 'ok' : 'reload rejected',
    );
  }

  @override
  Future<ActionResult> evaluate({
    required String label,
    required String libraryUri,
    required String expression,
  }) async {
    calls.add(label);
    expressions.add(expression);
    return ActionResult(label: label, ok: true, detail: 'ok');
  }

  @override
  Future<ActionResult> invoke({
    required String label,
    required String libraryUri,
    required String className,
    required String methodName,
  }) async {
    calls.add(label);
    invokes.add('$className.$methodName');
    return ActionResult(label: label, ok: invokeOk, detail: invokeOk ? 'ok' : 'call failed');
  }
}
