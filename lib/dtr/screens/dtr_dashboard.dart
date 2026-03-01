import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../dtr_provider.dart';
import '../widgets/dtr_summary_card.dart';
import '../widgets/dtr_recent_activity.dart';

/// DTR admin dashboard: summary cards + recent activity.
class DtrDashboard extends StatefulWidget {
  const DtrDashboard({super.key});

  @override
  State<DtrDashboard> createState() => _DtrDashboardState();
}

class _DtrDashboardState extends State<DtrDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final dtr = context.read<DtrProvider>();
    await dtr.loadSummary();
    await dtr.loadTimeRecordsForAdmin(limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final dtr = context.watch<DtrProvider>();
    final s = dtr.summary;
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 500;
    final twoRows = w < 800 && !isNarrow;

    final cardPresent = DtrSummaryCard(
      title: 'Present Today',
      subtitle: 'Employees with time-in',
      value: '${s.presentToday}',
      icon: Icons.check_circle_rounded,
      backgroundColor: const Color(0xFFFFF3E0),
      iconColor: const Color(0xFFE85D04),
    );
    final cardLate = DtrSummaryCard(
      title: 'Late Today',
      subtitle: 'Arrived after 8:00 AM',
      value: '${s.lateToday}',
      icon: Icons.schedule_rounded,
      backgroundColor: const Color(0xFFFFECB3),
      iconColor: const Color(0xFFBF360C),
    );
    final cardLeave = DtrSummaryCard(
      title: 'On Leave Today',
      subtitle: 'Approved leave',
      value: s.onLeaveToday != null ? '${s.onLeaveToday}' : '—',
      icon: Icons.event_busy_rounded,
      backgroundColor: const Color(0xFFFFE0B2),
      iconColor: const Color(0xFFFF9800),
    );
    final cardPending = DtrSummaryCard(
      title: 'Pending Approval',
      subtitle: 'Awaiting review',
      value: s.pendingApproval != null ? '${s.pendingApproval}' : '—',
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
        if (dtr.tableMissing) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DTR table not set up yet. Run Query 8 in docs/SUPABASE_AUTH_SETUP.md to create time_records and enable live data.',
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (dtr.error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dtr.error!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
        cards,
        const SizedBox(height: 24),
        DtrRecentActivity(records: dtr.timeRecords, loading: dtr.loading),
      ],
    );
  }
}
