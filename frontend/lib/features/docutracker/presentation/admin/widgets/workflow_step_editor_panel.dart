import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/simplified_workflow_step_editor.dart';

/// Compatibility entry point for callers of the original step panel.
class WorkflowStepEditorPanel extends StatelessWidget {
  const WorkflowStepEditorPanel({
    super.key,
    required this.title,
    required this.initial,
  });
  final String title;
  final WorkflowStep initial;

  @override
  Widget build(BuildContext context) =>
      SimplifiedWorkflowStepEditor(title: title, initial: initial);
}

Future<WorkflowStep?> showWorkflowStepEditor(
  BuildContext context, {
  required String title,
  required WorkflowStep initial,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  final useSheet = width < 720;

  if (useSheet) {
    return showModalBottomSheet<WorkflowStep>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx).bottom;
        final h = MediaQuery.sizeOf(ctx).height * 0.9;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SizedBox(
            height: h,
            child: SimplifiedWorkflowStepEditor(title: title, initial: initial),
          ),
        );
      },
    );
  }

  return showDialog<WorkflowStep>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(ctx).height * 0.78,
        child: SimplifiedWorkflowStepEditor(title: title, initial: initial),
      ),
    ),
  );
}
