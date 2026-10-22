import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_history_presentation.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';

/// Compact summary of the latest Return on a native document.
class DocuTrackerReturnedInfoCard extends StatelessWidget {
  const DocuTrackerReturnedInfoCard({
    super.key,
    required this.returnEntry,
    required this.returnedTo,
    required this.currentStep,
    required this.nextAction,
  });

  /// Latest `returned` history event. Null when history has not loaded or
  /// the viewer cannot read it.
  final DocumentHistoryEntry? returnEntry;

  /// Name of the reviewer now responsible, when the document records one.
  final String? returnedTo;
  final String currentStep;
  final String nextAction;

  @override
  Widget build(BuildContext context) {
    final entry = returnEntry;
    final returnedBy = entry == null
        ? docuTrackerReturnNotRecorded
        : docuTrackerHistoryActorName(entry) ?? 'Not recorded';
    final returnedAt = entry?.createdAt == null
        ? docuTrackerReturnNotRecorded
        : docuTrackerHistoryTimestamp(entry!.createdAt!);
    final reason = docuTrackerReturnReasonText(entry);
    final reasonMissing =
        reason == docuTrackerReturnNoReason ||
        reason == docuTrackerReturnNotRecorded;
    final responsible = returnedTo?.trim().isNotEmpty == true
        ? returnedTo!.trim()
        : 'Not assigned';
    final tone = DocuTrackerTokens.toneOf(context, const Color(0xFFB45309));

    return Container(
      key: const ValueKey('docutracker-returned-info-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.isDark(context)
            ? DocuTrackerTokens.insetOf(context)
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.undo_rounded, size: 20, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Returned to previous step',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Returned by', value: returnedBy),
          _InfoRow(label: 'Returned on', value: returnedAt),
          _InfoRow(label: 'Reason', value: reason, muted: reasonMissing),
          _InfoRow(label: 'Returned to', value: responsible),
          _InfoRow(label: 'Current step', value: currentStep),
          const SizedBox(height: 8),
          Text(
            nextAction,
            key: const ValueKey('docutracker-returned-next-action'),
            style: DocuTrackerTokens.subtitleStyle(
              context,
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textMutedOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                color: muted
                    ? DocuTrackerTokens.textMutedOf(context)
                    : DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
