import 'dart:math' as math;
import '../../../locator/models/locator_print_layout.dart';

/// Keep the existing first/final bindings so self-filing print policies and
/// previously filed forms keep their meaning. Middle steps have distinct slots.
Map<String, String> workflowPrintSignatures(List<dynamic>? steps) {
  if (steps == null || steps.isEmpty) return const {};
  final result = <String, String>{'applicant': 'Employee signature'};
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final source = step is Map ? step['assignee_source'] : step;
    final departmentOnly =
        steps.length == 1 &&
        const [
          'department',
          'department_reviewers',
          'submitter_department_reviewers',
        ].contains(source);
    final slot = departmentOnly
        ? 'department_head'
        : i == steps.length - 1
        ? 'hr_approver'
        : i == 0
        ? 'department_head'
        : 'workflow_step_${i + 1}';
    final label = step is Map
        ? step['label']?.toString().trim()
        : const {
            'department': 'Department Review',
            'hr': 'HR Review',
            'mayor': 'Mayor Approval',
            'manual_mayor': 'Manual Mayor Signing',
          }[step];
    result[slot] =
        '${label == null || label.isEmpty ? 'Approval step ${i + 1}' : label} signature';
  }
  return result;
}

String? workflowPrintCaption(List<dynamic>? steps, String source) {
  final label = workflowPrintSignatures(steps)[source];
  if (source == 'applicant' || label == null) return null;
  return label.substring(0, label.length - ' signature'.length);
}

/// Only called when creating/resetting a default layout, never on a saved draft.
LocatorPrintLayout workflowPrintLayoutDefaults(
  LocatorPrintLayout layout,
  List<dynamic>? steps,
) {
  final signatures = workflowPrintSignatures(steps);
  if (signatures.isEmpty || layout.baseForm != null) return layout;
  var fields = layout.elements.where((e) => e.kind != 'signature').toList();
  var y =
      fields.fold<double>(0, (bottom, e) => math.max(bottom, e.y + e.height)) +
      22;
  final left = math.max(40.0, layout.margins.left);
  final width = layout.pageWidth - left - math.max(40.0, layout.margins.right);
  final columns = math.min(signatures.length, ((width + 14) / 114).floor());
  final rows = (signatures.length / columns).ceil();
  var available = layout.pageHeight - math.max(30.0, layout.margins.bottom) - y;
  final minimumSignatureHeight = rows * 60 + (rows - 1) * 8;
  if (available < minimumSignatureHeight) {
    // Dense new templates may need more field columns. This never runs on a
    // saved layout and keeps all answers and approval steps on the page.
    final answers = fields.where((e) => e.kind == 'field').toList();
    if (answers.isNotEmpty) {
      final top = answers.map((e) => e.y).reduce(math.min);
      final room =
          layout.pageHeight -
          math.max(30.0, layout.margins.bottom) -
          minimumSignatureHeight -
          22 -
          top;
      for (var count = 2; count <= ((width + 14) / 114).floor(); count++) {
        final fieldRows = (answers.length / count).ceil();
        final rowHeight = math.min(28.0, room / fieldRows);
        if (rowHeight < 24) continue;
        final fieldWidth = (width - (count - 1) * 14) / count;
        fields = [
          ...fields.where((e) => e.kind != 'field'),
          for (final entry in answers.indexed)
            entry.$2.copyWith(
              x: left + (entry.$1 % count) * (fieldWidth + 14),
              y: top + (entry.$1 ~/ count) * rowHeight,
              width: fieldWidth,
              height: rowHeight - 2,
            ),
        ];
        y = top + fieldRows * rowHeight + 22;
        available =
            layout.pageHeight - math.max(30.0, layout.margins.bottom) - y;
        break;
      }
    }
  }
  final height = math.min(75.0, (available - (rows - 1) * 8) / rows);
  if (height < 60) {
    throw const FormatException(
      'The workflow signature blocks need more space. Reduce the default fields or choose a larger page.',
    );
  }
  final signatureWidth = (width - (columns - 1) * 14) / columns;
  return layout.copyWith(
    elements: [
      ...fields,
      for (final entry in signatures.keys.indexed)
        LocatorPrintElement(
          id: 'signature_${entry.$2}',
          kind: 'signature',
          source: entry.$2,
          x: left + (entry.$1 % columns) * (signatureWidth + 14),
          y: y + (entry.$1 ~/ columns) * (height + 8),
          width: signatureWidth,
          height: height,
          fontSize: 10,
          align: 'center',
        ),
    ],
  );
}
