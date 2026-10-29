/// Decides whether the analyzer reported a clean package.
library;

import 'dart:io';

/// Analyzer outcome for one package.
class AnalysisResult {
  /// Creates a result. [clean] is the "analysis returned true" signal.
  const AnalysisResult({required this.clean, required this.detail});

  /// True when the report contains no error diagnostics.
  final bool clean;

  /// Short explanation, empty when [clean] and the output was empty.
  final String detail;
}

/// True when [output] is `dart analyze --format machine` output with no errors.
///
/// Warnings and infos do not block a refresh. A human-format `error -` line
/// counts as a failure too, in case the machine format is unavailable.
bool analysisIsClean(String output) {
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('ERROR|') || line.startsWith('error -')) return false;
  }
  return true;
}

/// Runs `dart analyze` for a package on disk.
class DartAnalyzeGate {
  /// Analyzes [packageRoot] with the current Dart SDK.
  Future<AnalysisResult> analyze(String packageRoot) async {
    final ProcessResult result;
    try {
      result = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--format',
        'machine',
        packageRoot,
      ]);
    } on Object catch (error) {
      return AnalysisResult(clean: false, detail: '$error');
    }
    final output = '${result.stdout}\n${result.stderr}';
    if (!analysisIsClean(output)) {
      final errors = output
          .split('\n')
          .map((line) => line.trim())
          .where(
            (line) => line.startsWith('ERROR|') || line.startsWith('error -'),
          )
          .join('\n');
      return AnalysisResult(clean: false, detail: errors);
    }
    return const AnalysisResult(clean: true, detail: '');
  }
}
