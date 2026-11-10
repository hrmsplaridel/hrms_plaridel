import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/simplified_workflow_step_editor.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

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
  bool approvalOnly = false,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  final useSheet = width < 720;
  final child = SimplifiedWorkflowStepEditor(
    title: title,
    initial: initial,
    approvalOnly: approvalOnly,
  );

  if (useSheet) {
    return showModalBottomSheet<WorkflowStep>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: DocuTrackerTokens.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx).bottom;
        final h = MediaQuery.sizeOf(ctx).height * 0.94;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SizedBox(height: h, child: child),
        );
      },
    );
  }

  return showDialog<WorkflowStep>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        backgroundColor: DocuTrackerTokens.surfaceOf(ctx),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 840 ? 12 : 20,
          vertical: 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: size.height * 0.9,
          ),
          child: SizedBox(
            width: 680,
            height: size.height * 0.84,
            child: child,
          ),
        ),
      );
    },
  );
}
