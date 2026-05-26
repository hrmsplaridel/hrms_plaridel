import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_repository.dart';
import '../models/document_action.dart';
import '../models/document.dart';
import '../models/document_notification.dart';
import '../models/document_status.dart';
import '../widgets/docutracker_create_document_dialog.dart';
import '../theme/docutracker_tokens.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_section_header.dart';
import '../widgets/docutracker_status_theme.dart';
import '../docutracker_document_navigation.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_summary_card.dart';
import '../widgets/docutracker_press_scale.dart';

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
  static const double _panelGap = 16;
  static const int _defaultSectionVisibleCount = 4;

  Timer? _pollTimer;
  bool? _canCreateDocuments;
  _AdminQuickFilter _adminFilter = _AdminQuickFilter.all;
  final Map<String, bool> _expandedSections = <String, bool>{};

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
    final showFab = _canCreateDocuments == true;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(bottom: showFab ? 88 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showTitle) ...[
                DocuTrackerModuleHeader(
                  title: widget.isAdmin ? 'Dashboard' : 'My documents',
                  subtitle: widget.isAdmin
                      ? 'Organization-wide routing, SLA risk, and escalations.'
                      : 'Items assigned to you, deadlines, and completed work.',
                ),
                const SizedBox(height: 20),
              ],
              if (provider.error != null) ...[
                DocuTrackerErrorBanner(
                  message: provider.error!,
                  onDismiss: () => provider.clearError(),
                ),
                const SizedBox(height: 16),
              ],
              if (widget.isAdmin) ...[
                _buildOverviewPanel(
                  summary: _buildAdminSummaryCards(
                    provider: provider,
                    total: provider.documents.length,
                    overdue: provider.overdueDocuments.length,
                    escalated: provider.escalatedDocuments.length,
                  ),
                  activity: _buildRecentActivityPreview(provider),
                  equalizeHeights: true,
                ),
                const SizedBox(height: 16),
                _buildAdminDashboard(provider, userId),
              ] else ...[
                _buildEmployeeDashboard(provider, userId),
              ],
            ],
          ),
        ),
        if (showFab)
          Positioned(
            right: 12,
            bottom: 12,
            child: DocuTrackerPressScale(
              pressedScale: 0.94,
              child: FloatingActionButton(
                onPressed: provider.loading
                    ? null
                    : () => showDocuTrackerCreateDocumentDialog(
                        context,
                        auth: auth,
                        provider: provider,
                        onCreated: _load,
                      ),
                backgroundColor: DocuTrackerTokens.terracotta,
                foregroundColor: Colors.white,
                elevation: 4,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmployeeDashboard(DocuTrackerProvider provider, String userId) {
    final myDocs = provider.documents;
    final drafts = provider.myDraftsForUser(userId);
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
    final inReview = myDocs
        .where((d) => d.status == DocumentStatus.inReview)
        .toList();
    final approved = myDocs
        .where((d) => d.status == DocumentStatus.approved)
        .toList();

    final hasAnyDocs =
        drafts.isNotEmpty ||
        overdue.isNotEmpty ||
        nearing.isNotEmpty ||
        incoming.isNotEmpty ||
        returned.isNotEmpty ||
        completed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOverviewPanel(
          summary: _buildSummaryCards(
            drafts: drafts.length,
            pending: pending.length,
            inReview: inReview.length,
            overdue: overdue.length,
            approved: approved.length,
          ),
          activity: _buildRecentActivityPreview(provider),
        ),
        const SizedBox(height: 20),
        if (drafts.isNotEmpty)
          _buildDocSection(
            'My drafts',
            drafts,
            userId: userId,
            sectionKey: 'employee_drafts',
          ),
        if (incoming.isNotEmpty)
          _buildDocSection(
            'Assigned to me',
            incoming,
            userId: userId,
            sectionKey: 'employee_assigned',
          ),
        if (hasAnyDocs) ...[
          if (overdue.isNotEmpty)
            _buildDocSection(
              'Overdue',
              overdue,
              userId: userId,
              highlightOverdue: true,
              sectionKey: 'employee_overdue',
            ),
          if (nearing.isNotEmpty)
            _buildDocSection(
              'Nearing Deadline',
              nearing,
              userId: userId,
              sectionKey: 'employee_nearing',
            ),
          if (returned.isNotEmpty)
            _buildDocSection(
              'Returned',
              returned,
              userId: userId,
              sectionKey: 'employee_returned',
            ),
          if (completed.isNotEmpty)
            _buildDocSection(
              'Completed',
              completed,
              userId: userId,
              sectionKey: 'employee_completed',
            ),
        ] else
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildAdminDashboard(DocuTrackerProvider provider, String userId) {
    final overdue = provider.overdueDocuments.toList();
    final escalated = provider.escalatedDocuments.toList();
    final needsIntervention = provider.documentsNeedingAdminIntervention
        .toList();
    final all = provider.documents;
    final seenDocIds = <String>{
      ...needsIntervention.map((d) => d.id).whereType<String>(),
      ...overdue.map((d) => d.id).whereType<String>(),
      ...escalated.map((d) => d.id).whereType<String>(),
    };
    final allWithoutHighlights = all
        .where((d) => d.id == null || !seenDocIds.contains(d.id))
        .toList();
    final mine = all
        .where((d) => d.createdBy == userId || d.currentHolderId == userId)
        .toList();

    final showNeeds =
        _adminFilter == _AdminQuickFilter.all ||
        _adminFilter == _AdminQuickFilter.needsAction;
    final showOverdue =
        _adminFilter == _AdminQuickFilter.all ||
        _adminFilter == _AdminQuickFilter.needsAction ||
        _adminFilter == _AdminQuickFilter.overdue;
    final showEscalated =
        _adminFilter == _AdminQuickFilter.all ||
        _adminFilter == _AdminQuickFilter.needsAction ||
        _adminFilter == _AdminQuickFilter.escalated;
    final showAll = _adminFilter == _AdminQuickFilter.all;
    final showMine = _adminFilter == _AdminQuickFilter.mine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAdminFilterBar(),
        const SizedBox(height: 14),
        if (showNeeds && needsIntervention.isNotEmpty)
          _buildDocSection(
            'Needs admin intervention',
            needsIntervention,
            userId: '',
            highlightOverdue: true,
            sectionKey: 'admin_needs_intervention',
          ),
        if (showOverdue && overdue.isNotEmpty)
          _buildDocSection(
            'Overdue',
            overdue,
            userId: '',
            highlightOverdue: true,
            sectionKey: 'admin_overdue',
          ),
        if (showEscalated && escalated.isNotEmpty)
          _buildDocSection(
            'Escalated',
            escalated,
            userId: '',
            highlightOverdue: true,
            sectionKey: 'admin_escalated',
          ),
        if (showMine)
          _buildDocSection(
            'My touchpoints',
            mine,
            userId: userId,
            showHolder: true,
            sectionKey: 'admin_mine',
          ),
        if (showAll)
          _buildDocSection(
            'All Documents',
            allWithoutHighlights,
            userId: '',
            showHolder: true,
            sectionKey: 'admin_all_without_highlights',
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
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
    final cards = <Widget>[
      DocuTrackerSummaryCard(
        title: 'Drafts',
        subtitle: 'WIP, not submitted',
        value: '$drafts',
        padValue: true,
        icon: Icons.edit_note_rounded,
        backgroundColor: DocuTrackerTokens.surfaceCream,
        iconColor: DocuTrackerTokens.terracotta,
      ),
      DocuTrackerSummaryCard(
        title: 'Pending',
        subtitle: 'Waiting for action',
        value: '$pending',
        padValue: true,
        icon: Icons.hourglass_top_rounded,
        backgroundColor: DocuTrackerTokens.surface,
        iconColor: DocuTrackerTokens.textSecondary,
      ),
      DocuTrackerSummaryCard(
        title: 'In Review',
        subtitle: 'Currently processing',
        value: '$inReview',
        padValue: true,
        icon: Icons.manage_search_rounded,
        backgroundColor: const Color(0xFFEFF6FF),
        iconColor: DocuTrackerTokens.escalatedBlue,
      ),
      DocuTrackerSummaryCard(
        title: 'Overdue',
        subtitle: 'Past deadline',
        value: '$overdue',
        padValue: true,
        badge: overdue > 0 ? 'Critical' : null,
        badgeColor: DocuTrackerTokens.overdueAccent,
        icon: Icons.warning_amber_rounded,
        backgroundColor: DocuTrackerTokens.overduePink,
        iconColor: DocuTrackerTokens.overdueAccent,
      ),
      DocuTrackerSummaryCard(
        title: 'Approved',
        subtitle: 'Terminal success',
        value: '$approved',
        padValue: true,
        icon: Icons.check_circle_rounded,
        backgroundColor: const Color(0xFFECFDF5),
        iconColor: const Color(0xFF047857),
      ),
    ];

    return _buildSummaryGrid(cards, minCardWidth: 170);
  }

  Widget _buildRecentActivityPreview(DocuTrackerProvider provider) {
    final items = provider.notifications.take(5).toList();
    return _HoverLift(
      child: Container(
        width: double.infinity,
        decoration: DocuTrackerTokens.cardDecoration(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Recent Activity',
                  style: DocuTrackerTokens.titleStyle(context),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF86EFAC).withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF166534),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Text(
                'No recent workflow activity yet.',
                style: DocuTrackerTokens.subtitleStyle(),
              )
            else
              for (final n in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          color: _activityDotColor(n.type),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title?.trim().isNotEmpty == true
                                  ? n.title!
                                  : n.displayType,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: DocuTrackerTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatTimeAgo(n.createdAt),
                              style: DocuTrackerTokens.metaStyle(),
                            ),
                            Text(
                              _notificationSource(n),
                              style: DocuTrackerTokens.metaStyle().copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Audit log export will be available soon.'),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: DocuTrackerTokens.terracotta,
                  side: const BorderSide(color: DocuTrackerTokens.borderStrong),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusSm,
                    ),
                  ),
                ),
                child: const Text('Download Audit Log'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _activityDotColor(String type) {
    return switch (type) {
      DocumentNotification.typeOverdue => DocuTrackerTokens.overdueAccent,
      DocumentNotification.typeEscalated => DocuTrackerTokens.escalatedBlue,
      DocumentNotification.typeDeadlineNear => DocuTrackerTokens.alertOrange,
      _ => DocuTrackerTokens.terracotta,
    };
  }

  String _formatTimeAgo(DateTime? at) {
    if (at == null) return 'Just now';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${at.month}/${at.day}/${at.year}';
  }

  String _notificationSource(DocumentNotification n) {
    final body = n.body?.trim();
    if (body != null && body.isNotEmpty) return body;
    return switch (n.type) {
      DocumentNotification.typeEscalated => 'System',
      DocumentNotification.typeAssigned => 'Routing',
      _ => 'DocuTracker',
    };
  }

  Widget _buildAdminSummaryCards({
    required DocuTrackerProvider provider,
    required int total,
    required int overdue,
    required int escalated,
  }) {
    final today = DateTime.now();
    final createdToday = provider.documents.where((d) {
      final created = d.createdAt;
      if (created == null) return false;
      return created.year == today.year &&
          created.month == today.month &&
          created.day == today.day;
    }).length;

    final cards = <Widget>[
      DocuTrackerSummaryCard(
        title: 'All Documents',
        subtitle: 'Total routed documents across active lifecycles.',
        value: '$total',
        padValue: true,
        badge: createdToday > 0 ? '+$createdToday today' : null,
        badgeColor: DocuTrackerTokens.alertOrange,
        icon: Icons.description_rounded,
        backgroundColor: DocuTrackerTokens.surfaceCream,
        iconColor: DocuTrackerTokens.terracotta,
      ),
      DocuTrackerSummaryCard(
        title: 'Overdue',
        subtitle: 'Documents past their primary SLA deadline.',
        value: '$overdue',
        padValue: true,
        badge: overdue > 0 ? 'Critical' : null,
        badgeColor: DocuTrackerTokens.overdueAccent,
        icon: Icons.warning_amber_rounded,
        backgroundColor: DocuTrackerTokens.overduePink,
        iconColor: DocuTrackerTokens.overdueAccent,
      ),
      DocuTrackerSummaryCard(
        title: 'Escalated',
        subtitle: 'Requires immediate management intervention.',
        value: '$escalated',
        padValue: true,
        icon: Icons.trending_up_rounded,
        backgroundColor: DocuTrackerTokens.surface,
        iconColor: DocuTrackerTokens.escalatedBlue,
      ),
    ];

    return _buildSummaryGrid(cards, minCardWidth: 180, itemHeight: 182);
  }

  Widget _buildOverviewPanel({
    required Widget summary,
    required Widget activity,
    bool equalizeHeights = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        if (!wide) {
          return Column(
            children: [
              summary,
              const SizedBox(height: _panelGap),
              activity,
            ],
          );
        }
        // On wide screens, treat activity as a right rail. When [equalizeHeights]
        // is enabled, cap the rail and summary row to the same height so the
        // metric cards can extend down and avoid a bottom gap.
        final rowHeight = equalizeHeights ? 182.0 : null;
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: summary),
              const SizedBox(width: _panelGap),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  width: double.infinity,
                  height: rowHeight,
                  child: equalizeHeights
                      ? SingleChildScrollView(child: activity)
                      : activity,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryGrid(
    List<Widget> cards, {
    required double minCardWidth,
    double? itemHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / minCardWidth).floor().clamp(1, cards.length);
        final itemWidth = (width - (_panelGap * (columns - 1))) / columns;
        return Wrap(
          spacing: _panelGap,
          runSpacing: _panelGap,
          children: [
            for (final card in cards)
              SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _HoverLift(child: card),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAdminFilterBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _AdminQuickFilter.values)
                _WarmFilterChip(
                  label: filter.label,
                  selected: _adminFilter == filter,
                  onTap: () => setState(() => _adminFilter = filter),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _UtilityIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filter',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Advanced filters coming soon.')),
            );
          },
        ),
        const SizedBox(width: 6),
        _UtilityIconButton(
          icon: Icons.sort_rounded,
          tooltip: 'Sort',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sort options coming soon.')),
            );
          },
        ),
      ],
    );
  }

  (List<DocuTrackerDocument>, bool) _visibleDocsForSection(
    String sectionKey,
    List<DocuTrackerDocument> docs,
  ) {
    final expanded = _expandedSections[sectionKey] ?? false;
    if (expanded || docs.length <= _defaultSectionVisibleCount) {
      return (docs, false);
    }
    return (docs.take(_defaultSectionVisibleCount).toList(), true);
  }

  Widget _buildDocSection(
    String title,
    List<DocuTrackerDocument> docs, {
    required String userId,
    bool highlightOverdue = false,
    bool showHolder = false,
    String? sectionKey,
  }) {
    // Pick icon + accent per section type
    final (IconData icon, Color accent) = switch (title) {
      'Overdue' => (Icons.warning_amber_rounded, const Color(0xFFE53935)),
      'Escalated' => (Icons.trending_up_rounded, const Color(0xFF8E24AA)),
      'Nearing Deadline' => (Icons.schedule_rounded, const Color(0xFFBF360C)),
      'Incoming / Pending' => (Icons.inbox_rounded, const Color(0xFFE85D04)),
      'My drafts' => (Icons.edit_note_rounded, const Color(0xFFD97706)),
      'Returned' => (Icons.reply_rounded, const Color(0xFFFF9800)),
      'Completed' => (Icons.check_circle_rounded, DocuTrackerTokens.brand),
      _ => (Icons.folder_open_rounded, DocuTrackerTokens.brand),
    };

    final key = sectionKey ?? title;
    final (visibleDocs, hasHiddenRows) = _visibleDocsForSection(key, docs);
    final expanded = _expandedSections[key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocuTrackerSectionHeader(
          title: title,
          count: docs.length,
          icon: icon,
          accentColor: accent,
          showDivider: true,
          trailing: hasHiddenRows || expanded
              ? DocuTrackerPressScale(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _expandedSections[key] = !expanded),
                    style: TextButton.styleFrom(
                      foregroundColor: DocuTrackerTokens.terracotta,
                    ),
                    child: Text(expanded ? 'Show less' : 'View all'),
                  ),
                )
              : null,
        ),
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: DocuTrackerTokens.cardDecoration(),
            child: Center(
              child: Text(
                'No documents yet.',
                style: DocuTrackerTokens.subtitleStyle(),
              ),
            ),
          )
        else
          Column(
            children: [
              for (final doc in visibleDocs) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: DocuTrackerTokens.cardDecoration(
                    borderColor: highlightOverdue
                        ? DocuTrackerTokens.overdueAccent.withValues(
                            alpha: 0.35,
                          )
                        : DocuTrackerTokens.borderSubtle,
                  ),
                  child: _DocumentTile(
                    document: doc,
                    highlightOverdue: highlightOverdue,
                    showHolder: showHolder,
                    onTap: () async {
                      await openDocuTrackerDocumentDetail(
                        context,
                        document: doc,
                        isAdmin: widget.isAdmin,
                        userId: userId,
                        onReturned: _load,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _DocumentTile extends StatefulWidget {
  const _DocumentTile({
    required this.document,
    required this.highlightOverdue,
    required this.showHolder,
    required this.onTap,
  });

  final DocuTrackerDocument document;
  final bool highlightOverdue;
  final bool showHolder;
  final Future<void> Function() onTap;

  @override
  State<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<_DocumentTile> {
  bool _opening = false;
  bool _hovering = false;

  Future<void> _handleOpen() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue =
        widget.document.status == DocumentStatus.overdue ||
        (widget.document.deadlineTime != null &&
            DateTime.now().isAfter(widget.document.deadlineTime!));

    final statusForUi = isOverdue
        ? DocumentStatus.overdue
        : widget.document.status;

    final statusLabel = statusForUi.displayName.toUpperCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _hovering
              ? DocuTrackerTokens.surfaceCream.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: DocuTrackerStatusTheme.chipBackground(statusForUi),
                shape: BoxShape.circle,
              ),
              child: Icon(
                DocuTrackerStatusTheme.icon(statusForUi),
                color: DocuTrackerStatusTheme.foreground(statusForUi),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: DocuTrackerTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.document.documentNumber ?? '—',
                    style: DocuTrackerTokens.metaStyle().copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.showHolder && widget.document.assigneeName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Holder: ${widget.document.assigneeName}',
                        style: DocuTrackerTokens.metaStyle(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'CURRENT STATUS:',
                  style: DocuTrackerTokens.metaStyle().copyWith(
                    fontSize: 9,
                    letterSpacing: 0.4,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: DocuTrackerStatusTheme.chipBackground(statusForUi),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerStatusTheme.foreground(statusForUi),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DocuTrackerPressScale(
                      child: FilledButton.icon(
                        onPressed: _opening ? null : _handleOpen,
                        icon: _opening
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.open_in_new_rounded, size: 14),
                        label: const Text('Open'),
                        style: DocuTrackerTokens.terracottaFilledStyle()
                            .copyWith(
                              visualDensity: VisualDensity.compact,
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    DocuTrackerPressScale(
                      child: OutlinedButton.icon(
                        onPressed: widget.document.documentNumber == null
                            ? null
                            : () async {
                                final number = widget.document.documentNumber!;
                                await Clipboard.setData(
                                  ClipboardData(text: number),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Copied document number: $number',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy No.'),
                        style: DocuTrackerTokens.terracottaOutlinedStyle()
                            .copyWith(
                              visualDensity: VisualDensity.compact,
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      color: DocuTrackerTokens.textMuted,
                      onPressed: _opening ? null : _handleOpen,
                      tooltip: 'More actions',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _AdminQuickFilter {
  all('All'),
  needsAction('Needs action'),
  overdue('Overdue'),
  escalated('Escalated'),
  mine('Mine');

  const _AdminQuickFilter(this.label);
  final String label;
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});

  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: _hovering ? 1.012 : 1.0,
        child: widget.child,
      ),
    );
  }
}

class _WarmFilterChip extends StatelessWidget {
  const _WarmFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DocuTrackerPressScale(
      pressedScale: 0.975,
      child: Material(
        color: selected
            ? DocuTrackerTokens.overduePink.withValues(alpha: 0.85)
            : DocuTrackerTokens.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected
                    ? DocuTrackerTokens.terracotta.withValues(alpha: 0.35)
                    : DocuTrackerTokens.borderSubtle,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? DocuTrackerTokens.terracottaDark
                    : DocuTrackerTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UtilityIconButton extends StatelessWidget {
  const _UtilityIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DocuTrackerPressScale(
        pressedScale: 0.96,
        child: Material(
          color: DocuTrackerTokens.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DocuTrackerTokens.borderSubtle),
              ),
              child: Icon(icon, size: 18, color: DocuTrackerTokens.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
