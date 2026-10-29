/// The kind of a primitive literal accepted by the panel.
enum LiteralKind { nullValue, boolean, integer, doubleValue, string }

/// A parsed and safely encoded primitive literal.
class EncodedLiteral {
  const EncodedLiteral({
    required this.kind,
    required this.dart,
    this.value,
  });

  /// The kind of literal.
  final LiteralKind kind;

  /// The Dart source for the literal, produced by the encoder.
  final String dart;

  /// The parsed value, when there is one.
  final Object? value;

  /// Whether this literal can be assigned to a field of [type].
  bool matchesType(String? type) {
    final raw = (type ?? '').trim();
    if (raw.isEmpty) return true;
    final nullable = raw.endsWith('?');
    final base = nullable ? raw.substring(0, raw.length - 1).trim() : raw;
    if (kind == LiteralKind.nullValue) return nullable || base == 'Null';
    if (base == 'dynamic' || base == 'Object' || base == 'Object?') return true;
    if (base == 'num') {
      return kind == LiteralKind.integer || kind == LiteralKind.doubleValue;
    }
    return switch (base) {
      'int' => kind == LiteralKind.integer,
      'double' => kind == LiteralKind.doubleValue,
      'bool' => kind == LiteralKind.boolean,
      'String' => kind == LiteralKind.string,
      _ => false,
    };
  }
}

/// A parse failure with a message suitable for the panel.
class LiteralError implements Exception {
  const LiteralError(this.message);

  /// The reason the literal was rejected.
  final String message;

  @override
  String toString() => message;
}

/// Parses and re-encodes a user-entered primitive literal.
///
/// The panel never concatenates raw user text into Dart. It parses one of
/// `null`, `true`, `false`, an integer, a double, or a quoted string, then
/// produces the source with [encodeString] or the numeric parser.
abstract final class Literals {
  /// Parses [raw] and verifies it can be assigned to [fieldType].
  static EncodedLiteral parse(String raw, {String? fieldType}) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const LiteralError('Enter a literal: 42, 3.14, true, "text", null.');
    }
    final literal = _parseLiteral(text);
    if (!literal.matchesType(fieldType)) {
      throw LiteralError(
        '${_describe(literal.kind)} does not match ${fieldType ?? 'the field'}.',
      );
    }
    return literal;
  }

  static EncodedLiteral _parseLiteral(String text) {
    if (text == 'null') {
      return const EncodedLiteral(kind: LiteralKind.nullValue, dart: 'null');
    }
    if (text == 'true' || text == 'false') {
      return EncodedLiteral(
        kind: LiteralKind.boolean,
        dart: text,
        value: text == 'true',
      );
    }
    if (text.startsWith('"') || text.startsWith("'")) {
      final value = _parseString(text);
      return EncodedLiteral(
        kind: LiteralKind.string,
        dart: encodeString(value),
        value: value,
      );
    }
    if (RegExp(r'^-?[0-9]+$').hasMatch(text)) {
      final value = int.tryParse(text);
      if (value == null) {
        throw const LiteralError('Integer literal is out of range.');
      }
      return EncodedLiteral(
        kind: LiteralKind.integer,
        dart: value.toString(),
        value: value,
      );
    }
    if (RegExp(r'^-?(?:[0-9]+\.[0-9]+(?:[eE][+-]?[0-9]+)?|[0-9]+[eE][+-]?[0-9]+)$')
        .hasMatch(text)) {
      final value = double.tryParse(text);
      if (value == null || !value.isFinite) {
        throw const LiteralError('Double literal is out of range.');
      }
      return EncodedLiteral(
        kind: LiteralKind.doubleValue,
        dart: value.toString(),
        value: value,
      );
    }
    throw const LiteralError(
      'Only null, true, false, an integer, a double, or a quoted string are '
      'accepted. Objects, lists, maps, and expressions are not.',
    );
  }

  static String _parseString(String text) {
    final quote = text[0];
    final buffer = StringBuffer();
    var index = 1;
    var closed = false;
    while (index < text.length) {
      final char = text[index];
      if (char == quote) {
        closed = true;
        index++;
        break;
      }
      if (char != r'\') {
        buffer.write(char);
        index++;
        continue;
      }
      index++;
      if (index >= text.length) {
        throw const LiteralError('String ends with a dangling escape.');
      }
      final escape = text[index];
      index++;
      if (escape == 'n') {
        buffer.write('\n');
      } else if (escape == 'r') {
        buffer.write('\r');
      } else if (escape == 't') {
        buffer.write('\t');
      } else if (escape == 'b') {
        buffer.write('\b');
      } else if (escape == 'f') {
        buffer.write('\f');
      } else if (escape == r'\') {
        buffer.write(r'\');
      } else if (escape == "'") {
        buffer.write("'");
      } else if (escape == '"') {
        buffer.write('"');
      } else if (escape == r'$') {
        buffer.write(r'$');
      } else if (escape == 'u') {
        final (value, next) = _parseUnicodeEscape(text, index);
        buffer.writeCharCode(value);
        index = next;
      } else {
        throw LiteralError('Unsupported escape "\\$escape".');
      }
    }
    if (!closed) {
      throw const LiteralError('String literal is missing its closing quote.');
    }
    if (index != text.length) {
      throw const LiteralError('Unexpected text after the string literal.');
    }
    return buffer.toString();
  }

  static (int, int) _parseUnicodeEscape(String text, int index) {
    if (index < text.length && text[index] == '{') {
      final end = text.indexOf('}', index);
      if (end < 0) {
        throw const LiteralError('Unterminated \\u{...} escape.');
      }
      final value = int.tryParse(text.substring(index + 1, end), radix: 16);
      if (value == null) {
        throw const LiteralError('Invalid \\u{...} escape.');
      }
      return (value, end + 1);
    }
    if (index + 4 > text.length) {
      throw const LiteralError('Invalid \\uXXXX escape.');
    }
    final value = int.tryParse(text.substring(index, index + 4), radix: 16);
    if (value == null) {
      throw const LiteralError('Invalid \\uXXXX escape.');
    }
    return (value, index + 4);
  }

  /// Encodes [value] as a Dart double-quoted string literal.
  ///
  /// Quotes, backslashes, dollar signs and control characters are escaped by
  /// the encoder. Raw user text is never concatenated into an expression.
  static String encodeString(String value) {
    final buffer = StringBuffer('"');
    for (final rune in value.runes) {
      switch (rune) {
        case 0x22:
          buffer.write(r'\"');
        case 0x5c:
          buffer.write(r'\\');
        case 0x24:
          buffer.write(r'\$');
        case 0x0a:
          buffer.write(r'\n');
        case 0x0d:
          buffer.write(r'\r');
        case 0x09:
          buffer.write(r'\t');
        default:
          if (rune < 0x20) {
            buffer.write('\\u{${rune.toRadixString(16)}}');
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  static String _describe(LiteralKind kind) => switch (kind) {
        LiteralKind.nullValue => 'null',
        LiteralKind.boolean => 'A boolean',
        LiteralKind.integer => 'An integer',
        LiteralKind.doubleValue => 'A double',
        LiteralKind.string => 'A string',
      };
}
