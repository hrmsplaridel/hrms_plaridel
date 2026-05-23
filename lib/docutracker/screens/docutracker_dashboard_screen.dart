import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_action.dart';
import '../models/document.dart';
import '../models/document_notification.dart';
import '../models/document_status.dart';
import '../widgets/document_countdown_timer.dart';
import '../widgets/docutracker_create_document_dialog.dart';
import '../docutracker_notification_navigation.dart';
import '../widgets/docutracker_notifications_panel.dart';
import '../theme/docutracker_tokens.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_responsive_body.dart';
import '../widgets/docutracker_section_header.dart';
import '../widgets/docutracker_status_badge.dart';
import '../widgets/docutracker_status_theme.dart';
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

class _DocuTrackerDashboardScreenState
    extends State<DocuTrackerDashboardScreen> {
  Timer? _pollTimer;
  bool? _canCreateDocuments;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<DocuTrackerProvider>();
    await provider.loadRoutingConfigs();
    await provider.loadDocumentsForUser(
      userId: auth.user?.id ?? '',
      isAdmin: widget.isAdmin,
    );
    await provider.loadNotifications();

    final userId = auth.user?.id ?? '';
    final repo = DocuTrackerRepository.instance;
    final roleId = auth.user?.role;
    final canCreate = await repo.hasPermission(
      userId: userId,
      roleId: roleId,
      documentType: '*',
      action: DocumentAction.createDraft.value,
    );
    if (!mounted) return;
    setState(() => _canCreateDocuments = canCreate);

    // Keep document list in sync with server-side workflow/escalation changes.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = auth.user?.id ?? '';
      await provider.loadDocumentsForUser(
        userId: userId,
        isAdmin: widget.isAdmin,
      );
      await provider.loadNotifications();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?.id ?? '';
    final unreadCount = provider.unreadNotificationsCount;

    return SingleChildScrollView(
      child: DocuTrackerResponsiveBody(
        maxWidth: DocuTrackerTokens.maxContentWidth,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle) ...[
              DocuTrackerModuleHeader(
                title: widget.isAdmin ? 'Dashboard' : 'My documents',
                subtitle: widget.isAdmin
                    ? 'Organization-wide routing, SLA risk, and escalations.'
                    : 'Items assigned to you, deadlines, and completed work.',
                trailing: _canCreateDocuments == true
                    ? FilledButton.icon(
                        onPressed: provider.loading
                            ? null
                            : () => showDocuTrackerCreateDocumentDialog(
                                context,
                                auth: auth,
                                provider: provider,
                                onCreated: _load,
                              ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create Draft'),
                        style: DocuTrackerStyles.primaryButtonStyleNavy(),
                      )
                    : null,
              ),
              const SizedBox(height: 24),
            ],
            if (provider.notifications.isNotEmpty) ...[
              DocuTrackerNotificationPanel(
                notifications: provider.notifications,
                unreadCount: unreadCount,
                onMarkAllRead: () => provider.markAllNotificationsRead(),
                onNotificationTap: (n) => _openNotification(context, n),
              ),
              const SizedBox(height: 20),
            ],
            if (widget.isAdmin)
              _buildAdminDashboard(provider)
            else
              _buildEmployeeDashboard(provider, userId),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    DocumentNotification n,
  ) async {
    await navigateFromDocuTrackerNotification(
      context,
      notification: n,
      isAdmin: widget.isAdmin,
      afterNavigation: _load,
    );
  }

  Widget _buildEmployeeDashboard(DocuTrackerProvider provider, String userId) {
    final myDocs = provider.documents
        .where((d) => d.createdBy == userId || d.currentHolderId == userId)
        .toList();
    final incoming = provider.incomingForUser(userId);
    final pending = provider.pendingReviewsForUser(userId);
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
    final drafts = myDocs.where((d) {
      return d.status == DocumentStatus.pending &&
          (d.sentTime == null || (d.currentStep ?? 0) <= 0);
    }).toList();
    final inReview = myDocs.where((d) => d.status == DocumentStatus.inReview).toList();
    final approved = myDocs.where((d) => d.status == DocumentStatus.approved).toList();

    final hasAnyDocs =
        overdue.isNotEmpty ||
        nearing.isNotEmpty ||
        incoming.isNotEmpty ||
        returned.isNotEmpty ||
        completed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(
          drafts: drafts.length,
          pending: pending.length,
          inReview: inReview.length,
          overdue: overdue.length,
          approved: approved.length,
        ),
        const SizedBox(height: 24),
        _buildDocSection('Assigned to Me', incoming, false),
        _buildRecentActivityPreview(provider),
        const SizedBox(height: 20),
        if (hasAnyDocs) ...[
          if (overdue.isNotEmpty) _buildDocSection('Overdue', overdue, true),
          if (nearing.isNotEmpty)
            _buildDocSection('Nearing Deadline', nearing, false),
          if (incoming.isNotEmpty)
            _buildDocSection('Incoming / Pending', incoming, false),
          if (returned.isNotEmpty)
            _buildDocSection('Returned', returned, false),
          if (completed.isNotEmpty)
            _buildDocSection('Completed', completed, false),
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
        if (escalated.isNotEmpty)
          _buildDocSection('Escalated', escalated, true),
        _buildDocSection('All Documents', all, false, true),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
<<<<<<< HEAD
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      decoration: DocuTrackerTokens.cardDecoration(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No documents yet',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'When documents are routed to you, they will appear here.',
              textAlign: TextAlign.center,
              style: DocuTrackerTokens.subtitleStyle(),
            ),
          ],
=======
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Center(
        child: Text(
          'No documents yet.',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 13,
          ),
>>>>>>> origin/main
        ),
      ),
    );
  }

  Widget _buildSummaryCards({
    required int drafts,
    required int pending,
    required int inReview,
    required int overdue,
    required int approved,
  }) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 500;
    final twoRows = w < 800 && !isNarrow;

    final cardIncoming = DocuTrackerSummaryCard(
      title: 'Drafts',
      subtitle: 'WIP, not submitted',
      value: '$drafts',
      icon: Icons.edit_note_rounded,
      backgroundColor: const Color(0xFFFFFBEB),
      iconColor: const Color(0xFFD97706),
    );
    final cardNearing = DocuTrackerSummaryCard(
      title: 'Pending',
      subtitle: 'Waiting for action',
      value: '$pending',
      icon: Icons.hourglass_top_rounded,
      backgroundColor: const Color(0xFFF3F4F6),
      iconColor: const Color(0xFF4B5563),
    );
    final cardInReview = DocuTrackerSummaryCard(
      title: 'In Review',
      subtitle: 'Currently processing',
      value: '$inReview',
      icon: Icons.manage_search_rounded,
      backgroundColor: const Color(0xFFEFF6FF),
      iconColor: const Color(0xFF1D4ED8),
    );
    final cardOverdue = DocuTrackerSummaryCard(
      title: 'Overdue',
      subtitle: 'Past deadline',
      value: '$overdue',
      icon: Icons.warning_amber_rounded,
      backgroundColor: const Color(0xFFFFCDD2),
      iconColor: const Color(0xFFE53935),
    );
    final cardCompleted = DocuTrackerSummaryCard(
      title: 'Approved',
      subtitle: 'Terminal success',
      value: '$approved',
      icon: Icons.check_circle_rounded,
      backgroundColor: const Color(0xFFECFDF5),
      iconColor: const Color(0xFF047857),
    );

    if (isNarrow) {
      return Column(
        children: [
          cardIncoming,
          const SizedBox(height: 16),
          cardNearing,
          const SizedBox(height: 16),
          cardInReview,
          const SizedBox(height: 16),
          cardOverdue,
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
              Expanded(child: cardInReview),
              const SizedBox(width: 16),
              Expanded(child: cardOverdue),
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
        Expanded(child: cardInReview),
        const SizedBox(width: 16),
        Expanded(child: cardOverdue),
        const SizedBox(width: 16),
        Expanded(child: cardCompleted),
      ],
    );
  }

  Widget _buildRecentActivityPreview(DocuTrackerProvider provider) {
    final items = provider.notifications.take(4).toList();
    return Container(
      width: double.infinity,
      decoration: DocuTrackerTokens.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activity',
            style: DocuTrackerTokens.titleStyle(context),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'No recent workflow activity yet.',
              style: DocuTrackerTokens.subtitleStyle(),
            )
          else
            for (final n in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 8, color: AppTheme.primaryNavy.withValues(alpha: 0.8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n.title?.trim().isNotEmpty == true
                            ? n.title!
                            : n.displayType,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DocuTrackerTokens.subtitleStyle().copyWith(
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
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
    // Pick icon + accent per section type
    final (IconData icon, Color accent) = switch (title) {
      'Overdue'             => (Icons.warning_amber_rounded,  const Color(0xFFE53935)),
      'Escalated'           => (Icons.trending_up_rounded,    const Color(0xFF8E24AA)),
      'Nearing Deadline'    => (Icons.schedule_rounded,       const Color(0xFFBF360C)),
      'Incoming / Pending'  => (Icons.inbox_rounded,          const Color(0xFFE85D04)),
      'Returned'            => (Icons.reply_rounded,          const Color(0xFFFF9800)),
      'Completed'           => (Icons.check_circle_rounded,   AppTheme.primaryNavy),
      _                     => (Icons.folder_open_rounded,    AppTheme.primaryNavy),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocuTrackerSectionHeader(
          title: title,
          count: docs.length,
          icon: icon,
          accentColor: accent,
          showDivider: true,
        ),
        Container(
          decoration: highlightOverdue
<<<<<<< HEAD
              ? DocuTrackerStyles.listCardDecoration().copyWith(
                  border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
=======
              ? DocuTrackerStyles.listCardDecoration(context).copyWith(
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
>>>>>>> origin/main
                )
              : DocuTrackerStyles.listCardDecoration(context),
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
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: DocuTrackerTokens.borderSubtle.withValues(
                      alpha: 0.7,
                    ),
                  ),
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
    final isOverdue =
        document.status == DocumentStatus.overdue ||
        (document.deadlineTime != null &&
            DateTime.now().isAfter(document.deadlineTime!));

    final statusForUi = isOverdue ? DocumentStatus.overdue : document.status;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minVerticalPadding: 12,
      leading: CircleAvatar(
        backgroundColor: DocuTrackerStatusTheme.chipBackground(statusForUi),
        child: Icon(
          DocuTrackerStatusTheme.icon(statusForUi),
          color: DocuTrackerStatusTheme.foreground(statusForUi),
          size: 22,
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
                color: isOverdue
                    ? DocuTrackerStatusTheme.foreground(DocumentStatus.overdue)
                    : AppTheme.textPrimary,
              ),
            ),
          ),
          DocuTrackerStatusBadge(
            status: statusForUi,
            compact: true,
            showIcon: false,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.documentNumber ?? '—',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          if (showHolder && document.assigneeName != null)
            Text(
              'Holder: ${document.assigneeName}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 4),
          DocumentCountdownTimer(document: document, compact: true),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: AppTheme.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
