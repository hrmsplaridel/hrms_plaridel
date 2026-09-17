import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/applicant_journey.dart';

class RspApplicantJourneyTracker extends StatefulWidget {
  const RspApplicantJourneyTracker({
    super.key,
    required this.current,
    required this.tones,
  });

  final ApplicantJourneyStage current;
  final Map<ApplicantJourneyStage, ApplicantJourneyTone> tones;

  @override
  State<RspApplicantJourneyTracker> createState() =>
      _RspApplicantJourneyTrackerState();
}

class _RspApplicantJourneyTrackerState
    extends State<RspApplicantJourneyTracker> {
  bool _mobileExpanded = false;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    if (wide) return _desktopRow();
    return _mobileCompact();
  }

  Widget _desktopRow() {
    final stages = ApplicantJourneyStage.values;
    return Semantics(
      label:
          'Application journey. Current stage: ${widget.current.label}.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 13, left: 4, right: 4),
                  child: Container(
                    height: 2,
                    color: _toneColor(
                      widget.tones[stages[i - 1]] ??
                          ApplicantJourneyTone.locked,
                    ).withValues(alpha: 0.35),
                  ),
                ),
              ),
            Flexible(child: _stageChip(stages[i], compact: true)),
          ],
        ],
      ),
    );
  }

  Widget _mobileCompact() {
    final tone =
        widget.tones[widget.current] ?? ApplicantJourneyTone.current;
    final n = widget.current.displayNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stage $n of 5',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.current.label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: n / 5,
            minHeight: 8,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
            color: _toneColor(tone),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _mobileExpanded = !_mobileExpanded),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryNavy,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.centerLeft,
          ),
          child: Text(
            _mobileExpanded
                ? 'Hide application journey'
                : 'View application journey',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (_mobileExpanded) ...[
          const SizedBox(height: 4),
          for (final stage in ApplicantJourneyStage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _stageChip(stage, compact: true),
            ),
        ],
      ],
    );
  }

  Widget _stageChip(ApplicantJourneyStage stage, {required bool compact}) {
    final tone = widget.tones[stage] ?? ApplicantJourneyTone.locked;
    final color = _toneColor(tone);
    final icon = _toneIcon(tone);
    final status = _toneLabel(tone);
    return Semantics(
      label: '${stage.label}, $status',
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: tone == ApplicantJourneyTone.locked
                  ? 0.12
                  : 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _toneColor(ApplicantJourneyTone tone) {
    switch (tone) {
      case ApplicantJourneyTone.completed:
        return const Color(0xFF2E7D32);
      case ApplicantJourneyTone.current:
        return AppTheme.primaryNavy;
      case ApplicantJourneyTone.underReview:
        return const Color(0xFF1565C0);
      case ApplicantJourneyTone.rejected:
        return const Color(0xFFC62828);
      case ApplicantJourneyTone.locked:
        return const Color(0xFF6B7280);
    }
  }

  static IconData _toneIcon(ApplicantJourneyTone tone) {
    switch (tone) {
      case ApplicantJourneyTone.completed:
        return Icons.check_rounded;
      case ApplicantJourneyTone.current:
        return Icons.circle;
      case ApplicantJourneyTone.underReview:
        return Icons.hourglass_top_rounded;
      case ApplicantJourneyTone.rejected:
        return Icons.close_rounded;
      case ApplicantJourneyTone.locked:
        return Icons.lock_outline_rounded;
    }
  }

  static String _toneLabel(ApplicantJourneyTone tone) {
    switch (tone) {
      case ApplicantJourneyTone.completed:
        return 'Completed';
      case ApplicantJourneyTone.current:
        return 'Current';
      case ApplicantJourneyTone.underReview:
        return 'Under Review';
      case ApplicantJourneyTone.rejected:
        return 'Needs Attention';
      case ApplicantJourneyTone.locked:
        return 'Upcoming';
    }
  }
}
