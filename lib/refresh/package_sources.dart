/// Reads the Dart libraries of a package from disk.
library;

import 'dart:convert';
import 'dart:io';

/// One library file and the URI the running app uses for it.
class LibrarySource {
  /// Creates a library snapshot.
  const LibrarySource({
    required this.path,
    required this.libraryUri,
    required this.contents,
  });

  /// Absolute filesystem path.
  final String path;

  /// `package:` URI when the package config resolves one, otherwise a file URI.
  final String libraryUri;

  /// File contents.
  final String contents;
}

/// Loads `lib/**.dart` for a package root.
class PackageSources {
  /// Reads every Dart library under [packageRoot]`/lib`.
  Future<List<LibrarySource>> read(String packageRoot) async {
    final root = Directory(packageRoot);
    if (!root.existsSync()) {
      throw StateError('Package root does not exist: $packageRoot');
    }
    final packageName = _packageName(root);
    final lib = Directory(_join(root.path, 'lib'));
    if (!lib.existsSync()) return const [];

    final sources = <LibrarySource>[];
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = await entity.readAsString();
      sources.add(
        LibrarySource(
          path: entity.absolute.path,
          libraryUri: _libraryUri(root, entity, packageName),
          contents: contents,
        ),
      );
    }
    sources.sort((a, b) => a.path.compareTo(b.path));
    return sources;
  }
}

String? _packageName(Directory root) {
  final config = File(_join(root.path, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final packages = decoded['packages'];
  if (packages is! List) return null;
  final rootPath = _dirKey(root.absolute.uri);
  for (final package in packages) {
    if (package is! Map) continue;
    final rootUri = package['rootUri'];
    final name = package['name'];
    if (rootUri is! String || name is! String) continue;
    final resolved = config.parent.absolute.uri.resolve(rootUri);
    if (_dirKey(resolved) == rootPath) return name;
  }
  return null;
}

String _libraryUri(Directory root, File file, String? packageName) {
  if (packageName == null) return file.absolute.uri.toString();
  final libPath = _dirKey(Directory(_join(root.path, 'lib')).absolute.uri);
  final full = file.absolute.uri.normalizePath().toString();
  if (!full.startsWith(libPath)) return file.absolute.uri.toString();
  return 'package:$packageName/${full.substring(libPath.length)}';
}

String _dirKey(Uri uri) {
  final text = uri.normalizePath().toString();
  return text.endsWith('/') ? text : '$text/';
}

String _join(String a, String b, [String? c]) {
  final first = a.endsWith(Platform.pathSeparator)
      ? a.substring(0, a.length - 1)
      : a;
  final path = '$first${Platform.pathSeparator}$b';
  if (c == null) return path;
  return '$path${Platform.pathSeparator}$c';
}
