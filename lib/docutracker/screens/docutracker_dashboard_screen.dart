import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../models/document.dart';
import '../models/document_status.dart';
import '../widgets/document_countdown_timer.dart';
import '../widgets/docutracker_summary_card.dart';
import 'docutracker_document_detail_screen.dart';

/// Step 10 & 13: DocuTracker Dashboard.
/// Employee: Incoming, Pending, Nearing deadline, Overdue, Returned, Completed.
/// Admin: All routed, Current holder, Workflow status, Overdue, Escalated, etc.
class DocuTrackerDashboardScreen extends StatefulWidget {
  const DocuTrackerDashboardScreen({
    super.key,
    this.isAdmin = false,
    this.showTitle = true,
  });

  final bool isAdmin;
  final bool showTitle;

  @override
  State<DocuTrackerDashboardScreen> createState() =>
      _DocuTrackerDashboardScreenState();
}

class _DocuTrackerDashboardScreenState extends State<DocuTrackerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<DocuTrackerProvider>();
    await provider.loadRoutingConfigs();
    await provider.checkAndEscalateOverdue();
    await provider.loadDocumentsForUser(
      userId: auth.user?.id ?? '',
      isAdmin: widget.isAdmin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?.id ?? '';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle) ...[
            Text(
              widget.isAdmin ? 'DocuTracker Dashboard' : 'My Documents',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isAdmin
                  ? 'All routed documents, workflow status, overdue, escalated.'
                  : 'Incoming, pending reviews, deadlines, and completed documents.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
          if (widget.isAdmin) _buildAdminDashboard(provider) else _buildEmployeeDashboard(provider, userId),
        ],
      ),
    );
  }

  Widget _buildEmployeeDashboard(DocuTrackerProvider provider, String userId) {
    final incoming = provider.incomingForUser(userId);
    final nearing = provider.nearingDeadlineForUser(userId);
    final overdue = provider.overdueDocuments
        .where((d) => d.currentHolderId == userId)
        .toList();
    final returned = provider.returnedDocuments
        .where((d) => d.createdBy == userId)
        .toList();
    final completed = provider.completedDocuments
        .where((d) => d.createdBy == userId || d.currentHolderId == userId)
        .toList();

    final hasAnyDocs = overdue.isNotEmpty ||
        nearing.isNotEmpty ||
        incoming.isNotEmpty ||
        returned.isNotEmpty ||
        completed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(
          incoming: incoming.length,
          nearing: nearing.length,
          overdue: overdue.length,
          returned: returned.length,
          completed: completed.length,
        ),
        const SizedBox(height: 24),
        if (hasAnyDocs) ...[
          if (overdue.isNotEmpty) _buildDocSection('Overdue', overdue, true),
          if (nearing.isNotEmpty) _buildDocSection('Nearing Deadline', nearing, false),
          if (incoming.isNotEmpty) _buildDocSection('Incoming / Pending', incoming, false),
          if (returned.isNotEmpty) _buildDocSection('Returned', returned, false),
          if (completed.isNotEmpty) _buildDocSection('Completed', completed, false),
        ] else
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildAdminDashboard(DocuTrackerProvider provider) {
    final overdue = provider.overdueDocuments;
    final escalated = provider.escalatedDocuments;
    final all = provider.documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAdminSummaryCards(
          total: all.length,
          overdue: overdue.length,
          escalated: escalated.length,
        ),
        const SizedBox(height: 24),
        if (overdue.isNotEmpty) _buildDocSection('Overdue', overdue, true),
        if (escalated.isNotEmpty) _buildDocSection('Escalated', escalated, true),
        _buildDocSection('All Documents', all, false, true),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Center(
        child: Text(
          'No documents yet.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildSummaryCards({
    required int incoming,
    required int nearing,
    required int overdue,
    required int returned,
    required int completed,
  }) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 500;
    final twoRows = w < 800 && !isNarrow;

    final cardIncoming = DocuTrackerSummaryCard(
      title: 'Incoming',
      subtitle: 'Documents assigned to you',
      value: '$incoming',
      icon: Icons.inbox_rounded,
      backgroundColor: const Color(0xFFFFF3E0),
      iconColor: const Color(0xFFE85D04),
    );
    final cardNearing = DocuTrackerSummaryCard(
      title: 'Nearing Deadline',
      subtitle: 'Due within 24 hours',
      value: '$nearing',
      icon: Icons.schedule_rounded,
      backgroundColor: const Color(0xFFFFECB3),
      iconColor: const Color(0xFFBF360C),
    );
    final cardOverdue = DocuTrackerSummaryCard(
      title: 'Overdue',
      subtitle: 'Past deadline',
      value: '$overdue',
      icon: Icons.warning_amber_rounded,
      backgroundColor: const Color(0xFFFFCDD2),
      iconColor: const Color(0xFFE53935),
    );
    final cardReturned = DocuTrackerSummaryCard(
      title: 'Returned',
      subtitle: 'Sent back for revision',
      value: '$returned',
      icon: Icons.reply_rounded,
      backgroundColor: const Color(0xFFFFE0B2),
      iconColor: const Color(0xFFFF9800),
    );
    final cardCompleted = DocuTrackerSummaryCard(
      title: 'Completed',
      subtitle: 'Approved or rejected',
      value: '$completed',
      icon: Icons.check_circle_rounded,
      backgroundColor: AppTheme.white,
      iconColor: AppTheme.primaryNavy,
    );

    if (isNarrow) {
      return Column(
        children: [
          cardIncoming,
          const SizedBox(height: 16),
          cardNearing,
          const SizedBox(height: 16),
          cardOverdue,
          const SizedBox(height: 16),
          cardReturned,
          const SizedBox(height: 16),
          cardCompleted,
        ],
      );
    }
    if (twoRows) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cardIncoming),
              const SizedBox(width: 16),
              Expanded(child: cardNearing),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: cardOverdue),
              const SizedBox(width: 16),
              Expanded(child: cardReturned),
            ],
          ),
          const SizedBox(height: 16),
          cardCompleted,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: cardIncoming),
        const SizedBox(width: 16),
        Expanded(child: cardNearing),
        const SizedBox(width: 16),
        Expanded(child: cardOverdue),
        const SizedBox(width: 16),
        Expanded(child: cardReturned),
        const SizedBox(width: 16),
        Expanded(child: cardCompleted),
      ],
    );
  }

  Widget _buildAdminSummaryCards({
    required int total,
    required int overdue,
    required int escalated,
  }) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 500;
    final twoRows = w < 700 && !isNarrow;

    final cardAll = DocuTrackerSummaryCard(
      title: 'All Documents',
      subtitle: 'Total routed documents',
      value: '$total',
      icon: Icons.description_rounded,
      backgroundColor: const Color(0xFFFFF3E0),
      iconColor: const Color(0xFFE85D04),
    );
    final cardOverdue = DocuTrackerSummaryCard(
      title: 'Overdue',
      subtitle: 'Past deadline',
      value: '$overdue',
      icon: Icons.warning_amber_rounded,
      backgroundColor: const Color(0xFFFFCDD2),
      iconColor: const Color(0xFFE53935),
    );
    final cardEscalated = DocuTrackerSummaryCard(
      title: 'Escalated',
      subtitle: 'Requires attention',
      value: '$escalated',
      icon: Icons.trending_up_rounded,
      backgroundColor: AppTheme.white,
      iconColor: AppTheme.primaryNavy,
    );

    if (isNarrow) {
      return Column(
        children: [
          cardAll,
          const SizedBox(height: 16),
          cardOverdue,
          const SizedBox(height: 16),
          cardEscalated,
        ],
      );
    }
    if (twoRows) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cardAll),
              const SizedBox(width: 16),
              Expanded(child: cardOverdue),
            ],
          ),
          const SizedBox(height: 16),
          cardEscalated,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: cardAll),
        const SizedBox(width: 16),
        Expanded(child: cardOverdue),
        const SizedBox(width: 16),
        Expanded(child: cardEscalated),
      ],
    );
  }

  Widget _buildDocSection(
    String title,
    List<DocuTrackerDocument> docs, [
    bool highlightOverdue = false,
    bool showHolder = false,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: highlightOverdue
              ? DocuTrackerStyles.listCardDecoration().copyWith(
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                )
              : DocuTrackerStyles.listCardDecoration(),
          child: docs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No documents yet.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.black.withOpacity(0.06)),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    return _DocumentTile(
                      document: doc,
                      highlightOverdue: highlightOverdue,
                      showHolder: showHolder,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DocuTrackerDocumentDetailScreen(
                              document: doc,
                              isAdmin: widget.isAdmin,
                            ),
                          ),
                        );
                        _load();
                      },
                    );
                  },
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.highlightOverdue,
    required this.showHolder,
    required this.onTap,
  });

  final DocuTrackerDocument document;
  final bool highlightOverdue;
  final bool showHolder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOverdue = document.status == DocumentStatus.overdue ||
        (document.deadlineTime != null &&
            DateTime.now().isAfter(document.deadlineTime!));
    final isEscalated = document.status == DocumentStatus.escalated;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (highlightOverdue || isOverdue
                ? Colors.red
                : AppTheme.primaryNavy)
            .withOpacity(0.12),
        child: Icon(
          Icons.description_rounded,
          color: highlightOverdue || isOverdue
              ? Colors.red
              : AppTheme.primaryNavy,
          size: 24,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              document.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isOverdue ? Colors.red.shade800 : AppTheme.textPrimary,
              ),
            ),
          ),
          if (isEscalated)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple),
              ),
              child: Text(
                'Escalated',
                style: TextStyle(
                  color: Colors.purple.shade800,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${document.documentNumber ?? '—'} • ${document.status.displayName}',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          if (showHolder && document.assigneeName != null)
            Text(
              'Holder: ${document.assigneeName}',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 4),
          DocumentCountdownTimer(document: document, compact: true),
        ],
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}
