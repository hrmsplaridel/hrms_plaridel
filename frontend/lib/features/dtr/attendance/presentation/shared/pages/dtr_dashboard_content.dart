import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_attendance_analytics_section.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_summary_card.dart';

/// DTR admin dashboard: summary cards.
class DtrDashboardContent extends StatefulWidget {
  const DtrDashboardContent({super.key});

  @override
  State<DtrDashboardContent> createState() => _DtrDashboardState();
}

class _DtrDashboardState extends State<DtrDashboardContent> {
  StreamSubscription<DtrUpdateEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (!mounted) return;
      _wsSub = context.read<DtrProvider>().onDtrEvent.listen((_) {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    if (dtr.loading) return;
    await dtr.loadSummary();
    if (!mounted) return;
    if (!dtr.dashboardAnalyticsLoading) {
      await dtr.loadTimeRecordsForAdmin(forDashboardAnalytics: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final s = dtr.summary;
    final summaryError = dtr.summaryError;
    // While the summary is failing, show a dash instead of a misleading 0.
    String count(int value) => summaryError != null ? '—' : '$value';
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 500;
    final twoRows = w < 800 && !isNarrow;

    final cardPresent = DtrSummaryCard(
      title: 'Present Today',
      subtitle: 'Employees with time-in',
      value: count(s.presentToday),
      icon: Icons.check_circle_rounded,
      backgroundColor: const Color(0xFFFFF3E0),
      iconColor: const Color(0xFFE85D04),
    );
    final cardLate = DtrSummaryCard(
      title: 'Late Today',
      subtitle: 'Arrived after 8:00 AM',
      value: count(s.lateToday),
      icon: Icons.schedule_rounded,
      backgroundColor: const Color(0xFFFFECB3),
      iconColor: const Color(0xFFBF360C),
    );
    final cardLeave = DtrSummaryCard(
      title: 'On Leave Today',
      subtitle: 'Approved leave',
      value: count(s.onLeaveToday),
      icon: Icons.event_busy_rounded,
      backgroundColor: const Color(0xFFFFE0B2),
      iconColor: const Color(0xFFFF9800),
    );
    final cardPending = DtrSummaryCard(
      title: 'Pending Approval',
      subtitle: 'Awaiting review',
      value: count(s.pendingApproval),
      icon: Icons.pending_actions_rounded,
      backgroundColor: AppTheme.white,
      iconColor: AppTheme.primaryNavy,
    );

    Widget cards;
    if (isNarrow) {
      cards = Column(
        children: [
          cardPresent,
          const SizedBox(height: 16),
          cardLate,
          const SizedBox(height: 16),
          cardLeave,
          const SizedBox(height: 16),
          cardPending,
        ],
      );
    } else if (twoRows) {
      cards = Column(
        children: [
          Row(
            children: [
              Expanded(child: cardPresent),
              const SizedBox(width: 16),
              Expanded(child: cardLate),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: cardLeave),
              const SizedBox(width: 16),
              Expanded(child: cardPending),
            ],
          ),
        ],
      );
    } else {
      cards = Row(
        children: [
          Expanded(child: cardPresent),
          const SizedBox(width: 16),
          Expanded(child: cardLate),
          const SizedBox(width: 16),
          Expanded(child: cardLeave),
          const SizedBox(width: 16),
          Expanded(child: cardPending),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summaryError != null) ...[
          _SummaryErrorBanner(
            message: summaryError,
            onRetry: () => dtr.loadSummary(forceRefresh: true),
          ),
          const SizedBox(height: 16),
        ],
        cards,
        const DtrAttendanceAnalyticsSection(),
      ],
    );
  }
}

class _SummaryErrorBanner extends StatelessWidget {
  const _SummaryErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  static String _sentence(String text) {
    final t = text.trim();
    return t.endsWith('.') || t.endsWith('!') || t.endsWith('?') ? t : '$t.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onErrorContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, color: fg, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Attendance data couldn't be loaded.",
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_sentence(message)} If this keeps happening, contact your system administrator.',
                    style: TextStyle(color: fg, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: fg,
                minimumSize: const Size(0, 40),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
