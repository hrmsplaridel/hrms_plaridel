enum BiometricLogFormat {
  tabSeparated('Tab-separated', '\t'),
  commaSeparated('CSV (comma-separated)', ','),
  semicolonSeparated('CSV (semicolon-separated)', ';');

  const BiometricLogFormat(this.label, this.delimiter);

  final String label;
  final String delimiter;
}

/// Detects supported text attendance-log layouts from their contents.
/// The filename extension is intentionally not used for detection.
class BiometricLogFormatDetector {
  const BiometricLogFormatDetector._();

  static BiometricLogFormat? detect(String content) {
    if (_looksBinary(content)) return null;

    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(20)
        .toList();
    if (lines.isEmpty) return null;

    BiometricLogFormat? best;
    var bestScore = 0;
    for (final format in BiometricLogFormat.values) {
      final score = lines
          .where((line) => splitRow(line, format.delimiter).length >= 2)
          .length;
      if (score > bestScore) {
        best = format;
        bestScore = score;
      }
    }
    return bestScore == 0 ? null : best;
  }

  /// Splits delimited text while preserving delimiters inside quoted values.
  static List<String> splitRow(String row, String delimiter) {
    final values = <String>[];
    final current = StringBuffer();
    var quoted = false;

    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        values.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    values.add(current.toString());
    return values;
  }

  static bool _looksBinary(String content) {
    if (content.contains('\u0000')) return true;
    if (content.isEmpty) return false;
    final sample = content.length > 2048 ? content.substring(0, 2048) : content;
    final controlCharacters = sample.codeUnits.where((code) {
      return code < 32 && code != 9 && code != 10 && code != 13;
    }).length;
    return controlCharacters / sample.length > 0.02;
  }
}
