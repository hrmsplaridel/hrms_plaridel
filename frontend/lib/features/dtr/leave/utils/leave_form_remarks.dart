import '../models/leave_request.dart';

String _firstRemark(List<String?> values) => values
    .map((value) => value?.trim() ?? '')
    .firstWhere((value) => value.isNotEmpty, orElse: () => '');

/// Department recommendations belong in 7.B, separately from HR decisions.
String leaveFormRecommendationRemarks(LeaveRequest request) => _firstRemark([
  request.departmentHeadRemarks,
  request.recommendationRemarks,
  if (request.status == LeaveRequestStatus.rejectedByDepartmentHead)
    request.hrRemarks, // Immediate rejection response before history is loaded.
]);

String leaveFormDisapprovalReason(LeaveRequest request) =>
    request.status == LeaveRequestStatus.rejectedByHr ||
        request.status == LeaveRequestStatus.rejected
    ? _firstRemark([request.disapprovalReason, request.hrRemarks])
    : '';

typedef LeaveRemarkMeasure = double Function(String text, double fontSize);

/// Fits the complete remark to the form's three ruled lines using font metrics.
({List<String> lines, double fontSize}) layoutLeaveFormRemarks(
  String text, {
  required double width,
  required double fontSize,
  required LeaveRemarkMeasure measure,
}) {
  assert(width > 0 && width.isFinite && fontSize > 0);
  var paragraphs = text.trim().split(RegExp(r'\r?\n'));
  // More explicit paragraphs than available lines must share the ruled area.
  if (paragraphs.length > 3) paragraphs = [paragraphs.join(' ')];
  if (text.trim().isEmpty) return (lines: [], fontSize: fontSize);

  List<String> wrap(double size) {
    final lines = <String>[];
    for (final paragraph in paragraphs) {
      var line = '';
      for (final word in paragraph.trim().split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final candidate = line.isEmpty ? word : '$line $word';
        if (measure(candidate, size) <= width) {
          line = candidate;
          continue;
        }
        if (line.isNotEmpty) lines.add(line);
        line = '';
        // Long tokens (IDs/URLs) also wrap without dropping characters.
        for (final rune in word.runes) {
          final character = String.fromCharCode(rune);
          if (line.isNotEmpty && measure('$line$character', size) > width) {
            lines.add(line);
            line = '';
          }
          line += character;
        }
      }
      lines.add(line);
    }
    return lines;
  }

  var size = fontSize;
  var lines = wrap(size);
  while (lines.length > 3 || lines.any((line) => measure(line, size) > width)) {
    size *= 0.9;
    lines = wrap(size);
  }
  return (lines: lines, fontSize: size);
}
