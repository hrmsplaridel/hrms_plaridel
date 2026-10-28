import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_progress.dart';

/// Horizontal workflow progress. Scrolls instead of clipping step names.
class DocuTrackerWorkflowStepStrip extends StatelessWidget {
  const DocuTrackerWorkflowStepStrip({super.key, required this.progress});

  final List<DocuTrackerStepProgress> progress;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('docutracker-workflow-step-strip'),
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < progress.length; i++) ...[
              DocuTrackerWorkflowStepNode(step: progress[i]),
              if (i < progress.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 22, left: 4, right: 4),
                  width: 28,
                  height: 2,
                  color: progress[i].indicator.isCompleted
                      ? DocuTrackerTokens.brand
                      : DocuTrackerTokens.borderStrongOf(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The same progress as the strip, listed vertically for the full map.
class DocuTrackerWorkflowMapList extends StatelessWidget {
  const DocuTrackerWorkflowMapList({super.key, required this.progress});

  final List<DocuTrackerStepProgress> progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('docutracker-workflow-map'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < progress.length; i++) ...[
          DocuTrackerWorkflowMapRow(step: progress[i]),
          if (i < progress.length - 1)
            Container(
              margin: const EdgeInsets.only(left: 15),
              width: 2,
              height: 12,
              color: progress[i].indicator.isCompleted
                  ? DocuTrackerTokens.brand
                  : DocuTrackerTokens.borderStrongOf(context),
            ),
        ],
      ],
    );
  }
}

class DocuTrackerWorkflowStepNode extends StatelessWidget {
  const DocuTrackerWorkflowStepNode({super.key, required this.step});

  final DocuTrackerStepProgress step;

  @override
  Widget build(BuildContext context) {
    final indicator = step.indicator;
    final color = _stepColor(context, indicator.kind);
    return SizedBox(
      width: 148,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepMark(order: step.order, indicator: indicator, color: color),
          const SizedBox(height: 8),
          Text(
            step.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: DocuTrackerTokens.textPrimaryOf(context),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          _StateLine(indicator: indicator, color: color),
          if (indicator.detail != null) ...[
            const SizedBox(height: 2),
            Text(
              indicator.detail!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: DocuTrackerTokens.textSecondaryOf(context),
              ),
            ),
          ],
          if (step.personName != null) ...[
            const SizedBox(height: 2),
            Text(
              step.personName!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DocuTrackerWorkflowMapRow extends StatelessWidget {
  const DocuTrackerWorkflowMapRow({super.key, required this.step});

  final DocuTrackerStepProgress step;

  @override
  Widget build(BuildContext context) {
    final indicator = step.indicator;
    final color = _stepColor(context, indicator.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepMark(
          order: step.order,
          indicator: indicator,
          color: color,
          compact: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              _StateLine(indicator: indicator, color: color, alignStart: true),
              if (indicator.detail != null)
                Text(
                  indicator.detail!,
                  style: TextStyle(
                    fontSize: 12,
                    color: DocuTrackerTokens.textSecondaryOf(context),
                  ),
                ),
              if (step.personName != null)
                Text(
                  step.personName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({
    required this.order,
    required this.indicator,
    required this.color,
    this.compact = false,
  });

  final int order;
  final DocuTrackerStepIndicator indicator;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 36.0;
    final done = indicator.isCompleted;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: done || indicator.kind == DocuTrackerStepIndicatorKind.current
            ? color
            : DocuTrackerTokens.insetOf(context),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(
        _stepIcon(indicator.kind),
        size: compact ? 16 : 18,
        color: done || indicator.kind == DocuTrackerStepIndicatorKind.current
            ? Colors.white
            : color,
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({
    required this.indicator,
    required this.color,
    this.alignStart = false,
  });

  final DocuTrackerStepIndicator indicator;
  final Color color;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignStart
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_stepIcon(indicator.kind), size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            indicator.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _stepIcon(DocuTrackerStepIndicatorKind kind) {
  return switch (kind) {
    DocuTrackerStepIndicatorKind.approved => Icons.check_rounded,
    DocuTrackerStepIndicatorKind.forwarded => Icons.arrow_forward_rounded,
    DocuTrackerStepIndicatorKind.completed => Icons.check_rounded,
    DocuTrackerStepIndicatorKind.current => Icons.flag_rounded,
    DocuTrackerStepIndicatorKind.upcoming => Icons.schedule_rounded,
    DocuTrackerStepIndicatorKind.returned => Icons.undo_rounded,
    DocuTrackerStepIndicatorKind.rejected => Icons.cancel_rounded,
    DocuTrackerStepIndicatorKind.overdue => Icons.alarm_rounded,
    DocuTrackerStepIndicatorKind.escalated => Icons.trending_up_rounded,
    DocuTrackerStepIndicatorKind.cancelled => Icons.block_rounded,
    DocuTrackerStepIndicatorKind.unrecorded => Icons.help_outline_rounded,
  };
}

Color _stepColor(BuildContext context, DocuTrackerStepIndicatorKind kind) {
  final color = switch (kind) {
    DocuTrackerStepIndicatorKind.approved => const Color(0xFF047857),
    DocuTrackerStepIndicatorKind.forwarded => DocuTrackerTokens.brand,
    DocuTrackerStepIndicatorKind.returned => const Color(0xFFB45309),
    DocuTrackerStepIndicatorKind.rejected => const Color(0xFFB91C1C),
    DocuTrackerStepIndicatorKind.overdue => const Color(0xFFDC2626),
    DocuTrackerStepIndicatorKind.escalated => const Color(0xFF7C3AED),
    DocuTrackerStepIndicatorKind.current => DocuTrackerTokens.brand,
    _ => DocuTrackerTokens.textMutedOf(context),
  };
  return DocuTrackerTokens.toneOf(context, color);
}
