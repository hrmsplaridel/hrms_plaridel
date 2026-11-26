import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against showing raw exception text (e.g. "DioException [bad
/// response]: ...") to users in the DTR feature. Use `userFacingApiError(e)`
/// for anything shown on screen and `debugPrint` for the technical detail.
void main() {
  // `'...: $e'` style messages built from a caught error.
  final interpolated = RegExp(
    r'''(['"])[^'"\n]*\$(?:e|err|error|\{e\}|\{err\}|\{error\})\1''',
  );
  // `_error = e.toString()` style error state.
  final assigned = RegExp(
    r'''\b\w*[Ee]rror\w*\s*=\s*(?:e|err|error)\.toString\(\)''',
  );
  final ignoredLine = RegExp(
    r'debugPrint|print\(|log\(|throw |Exception\(|StateError\(',
  );

  /// Matches that are not caught errors. Key: path suffix, value: line text.
  const allowed = {
    // Form validation text, not an exception.
    'assistant/presentation/widgets/application_review.dart':
        r"'${label!.trim()}: $error'",
    // Shift time range ("start–end"), `$e` is the end time.
    'schedules/presentation/pages/schedule_calendar.dart': r"$s",
  };

  test('DTR screens never show raw exception text', () {
    final offenders = <String>[];
    final files = Directory('lib/features/dtr')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().startsWith('//') || ignoredLine.hasMatch(line)) {
          continue;
        }
        if (!interpolated.hasMatch(line) && !assigned.hasMatch(line)) continue;
        final allowedEntry = allowed.entries.where(
          (e) => path.endsWith(e.key) && line.contains(e.value),
        );
        if (allowedEntry.isNotEmpty) continue;
        offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use userFacingApiError(e) for user-visible errors:\n'
          '${offenders.join('\n')}',
    );
  });
}
