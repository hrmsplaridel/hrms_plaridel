import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_status_badge.dart';

enum RspAssessmentItemStatus {
  notStarted,
  ready,
  completed,
  waitingForEvaluation,
  passed,
  locked,
}

class RspAssessmentItem {
  const RspAssessmentItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
  });

  final String id;
  final String title;
  final String detail;
  final RspAssessmentItemStatus status;
}

class RspApplicantAssessmentHub extends StatelessWidget {
  const RspApplicantAssessmentHub({
    super.key,
    required this.items,
    required this.onStart,
  });

  final List<RspAssessmentItem> items;
  final void Function(String id) onStart;

  @override
  Widget build(BuildContext context) {
    final done = items
        .where(
          (e) =>
              e.status == RspAssessmentItemStatus.completed ||
              e.status == RspAssessmentItemStatus.waitingForEvaluation ||
              e.status == RspAssessmentItemStatus.passed,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Assessment',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Complete the required assessments below.',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Overall progress  $done of ${items.length} completed',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: items.isEmpty ? 0 : done / items.length,
            minHeight: 8,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
            color: AppTheme.primaryNavy,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 768;
            final cards = items.map(_itemCard).toList();
            if (!twoCol) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    cards[i],
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _itemCard(RspAssessmentItem item) {
    final badge = _badge(item.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              RspApplicantStatusBadge(kind: badge.kind, label: badge.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.detail,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          if (item.status == RspAssessmentItemStatus.ready) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () => onStart(item.id),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
                child: Text('Start ${item.title}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static ({RspApplicantBadgeKind kind, String label}) _badge(
    RspAssessmentItemStatus s,
  ) {
    switch (s) {
      case RspAssessmentItemStatus.notStarted:
        return (kind: RspApplicantBadgeKind.needsAction, label: 'Not Started');
      case RspAssessmentItemStatus.ready:
        return (kind: RspApplicantBadgeKind.ready, label: 'Ready');
      case RspAssessmentItemStatus.completed:
        return (kind: RspApplicantBadgeKind.completed, label: 'Completed');
      case RspAssessmentItemStatus.waitingForEvaluation:
        return (
          kind: RspApplicantBadgeKind.waitingForHr,
          label: 'Waiting for Evaluation',
        );
      case RspAssessmentItemStatus.passed:
        return (kind: RspApplicantBadgeKind.passed, label: 'Passed');
      case RspAssessmentItemStatus.locked:
        return (kind: RspApplicantBadgeKind.locked, label: 'Locked');
    }
  }
}
