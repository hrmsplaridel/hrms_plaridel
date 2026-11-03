import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_empty_state.dart';

/// Grouped DocuTracker notifications with read/unread styling, taps, paging, and mark-all-read.
class DocuTrackerNotificationPanel extends StatefulWidget {
  const DocuTrackerNotificationPanel({
    super.key,
    required this.notifications,
    required this.unreadCount,
    required this.onNotificationTap,
    this.onMarkAllRead,
    this.onMarkRead,
    this.documentReferenceOf,
    this.initialVisiblePerGroup = 5,
    this.showChrome = true,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
  });

  final List<DocumentNotification> notifications;
  final int unreadCount;
  final Future<void> Function(DocumentNotification n) onNotificationTap;

  /// Marks one notification read without opening the document.
  final Future<void> Function(DocumentNotification n)? onMarkRead;
  final Future<void> Function()? onMarkAllRead;

  /// Optional document number/title lookup by notification.
  final String? Function(DocumentNotification n)? documentReferenceOf;

  final int initialVisiblePerGroup;

  /// When false, omits the outer card header (use when a parent already titles the panel).
  final bool showChrome;

  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  static int typeRank(String type) {
    return switch (type) {
      DocumentNotification.typeOverdue => 0,
      DocumentNotification.typeEscalated => 1,
      DocumentNotification.typeAssigned => 2,
      DocumentNotification.typeDeadlineNear => 3,
      DocumentNotification.typeRejected => 4,
      DocumentNotification.typeReturned => 5,
      DocumentNotification.typeReleased => 6,
      _ => 9,
    };
  }

  static int compare(DocumentNotification a, DocumentNotification b) {
    final ra = typeRank(a.type);
    final rb = typeRank(b.type);
    if (ra != rb) return ra.compareTo(rb);
    if (a.read != b.read) return a.read ? 1 : -1;
    final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  }

  static List<DocumentNotification> sorted(List<DocumentNotification> raw) {
    final copy = [...raw]..sort(compare);
    return copy;
  }

  static List<DocumentNotification> inTypes(
    List<DocumentNotification> list,
    Set<String> types,
  ) => list.where((n) => types.contains(n.type)).toList();

  static IconData iconFor(DocumentNotification n) {
    return switch (n.eventKind) {
      DocumentNotification.eventSubmission => Icons.send_rounded,
      DocumentNotification.eventApproval => Icons.verified_rounded,
      DocumentNotification.eventForwarding => Icons.shortcut_rounded,
      DocumentNotification.eventReturn => Icons.reply_rounded,
      DocumentNotification.eventRejection => Icons.cancel_outlined,
      DocumentNotification.eventSignature => Icons.draw_rounded,
      DocumentNotification.eventRelease => Icons.outbox_rounded,
      DocumentNotification.eventOverdue => Icons.warning_amber_rounded,
      DocumentNotification.eventEscalation => Icons.trending_up_rounded,
      DocumentNotification.eventDeadline => Icons.schedule_rounded,
      DocumentNotification.eventAdminRecovery => Icons.admin_panel_settings_rounded,
      DocumentNotification.eventAssignment => Icons.inbox_rounded,
      _ => Icons.notifications_none_rounded,
    };
  }

  static Color accentFor(
    BuildContext context,
    DocumentNotification n, {
    required bool read,
  }) {
    if (read) {
      return AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.35);
    }
    return DocuTrackerTokens.toneOf(context, switch (n.eventKind) {
      DocumentNotification.eventOverdue => Colors.deepOrange.shade800,
      DocumentNotification.eventEscalation => Colors.red.shade800,
      DocumentNotification.eventRejection => Colors.purple.shade800,
      DocumentNotification.eventReturn => DocuTrackerTokens.brand,
      DocumentNotification.eventDeadline => Colors.amber.shade900,
      DocumentNotification.eventRelease => Colors.green.shade800,
      DocumentNotification.eventApproval => Colors.teal.shade800,
      DocumentNotification.eventSignature => Colors.indigo.shade700,
      DocumentNotification.eventAdminRecovery => Colors.blueGrey.shade800,
      DocumentNotification.eventSubmission => DocuTrackerTokens.brand,
      DocumentNotification.eventForwarding => DocuTrackerTokens.brand,
      DocumentNotification.eventAssignment => DocuTrackerTokens.brand,
      _ => DocuTrackerTokens.brand,
    });
  }

  static String relativeTime(DateTime? t) {
    if (t == null) return '';
    final local = t.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  State<DocuTrackerNotificationPanel> createState() =>
      _DocuTrackerNotificationPanelState();
}

class _DocuTrackerNotificationPanelState
    extends State<DocuTrackerNotificationPanel> {
  late int _urgentCap;
  late int _routingCap;
  late int _outcomesCap;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    final n = widget.initialVisiblePerGroup;
    _urgentCap = n;
    _routingCap = n;
    _outcomesCap = n;
  }

  @override
  void didUpdateWidget(covariant DocuTrackerNotificationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifications.isEmpty != widget.notifications.isEmpty) {
      final n = widget.initialVisiblePerGroup;
      _urgentCap = n;
      _routingCap = n;
      _outcomesCap = n;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.notifications.isEmpty) {
      return _PanelShell(
        showChrome: widget.showChrome,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: DocuTrackerTokens.brand,
              ),
            ),
          ),
        ),
      );
    }

    if (widget.errorMessage != null && widget.notifications.isEmpty) {
      return _PanelShell(
        showChrome: widget.showChrome,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: DocuTrackerTokens.textMutedOf(context),
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load notifications',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: DocuTrackerTokens.textMutedOf(context),
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                  style: TextButton.styleFrom(
                    foregroundColor: DocuTrackerTokens.brand,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (widget.notifications.isEmpty) {
      return _PanelShell(
        showChrome: widget.showChrome,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: DocuTrackerEmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'All caught up',
            message:
                'Workflow updates — submissions, approvals, forwards, returns, and deadlines — will appear here.',
          ),
        ),
      );
    }

    final sorted = DocuTrackerNotificationPanel.sorted(widget.notifications);
    final urgent = DocuTrackerNotificationPanel.inTypes(sorted, {
      DocumentNotification.typeOverdue,
      DocumentNotification.typeEscalated,
    });
    final routing = DocuTrackerNotificationPanel.inTypes(sorted, {
      DocumentNotification.typeAssigned,
      DocumentNotification.typeDeadlineNear,
    });
    final outcomes = DocuTrackerNotificationPanel.inTypes(sorted, {
      DocumentNotification.typeReturned,
      DocumentNotification.typeRejected,
      DocumentNotification.typeReleased,
    });
    // Any unexpected future types still appear rather than vanishing.
    final known = {
      ...urgent.map((n) => n.id),
      ...routing.map((n) => n.id),
      ...outcomes.map((n) => n.id),
    };
    final other = sorted.where((n) => !known.contains(n.id)).toList();

    final urgentShow = _urgentCap.clamp(0, urgent.length);
    final routingShow = _routingCap.clamp(0, routing.length);
    final outcomesShow = _outcomesCap.clamp(0, outcomes.length);
    final urgentRemain = urgent.length - urgentShow;
    final routingRemain = routing.length - routingShow;
    final outcomesRemain = outcomes.length - outcomesShow;

    return _PanelShell(
      showChrome: widget.showChrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showChrome)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DocuTrackerTokens.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: DocuTrackerTokens.brand,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.unreadCount > 0
                              ? '${widget.unreadCount} unread — tap to open the document'
                              : 'All caught up — tap to review a document',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8, top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: DocuTrackerTokens.brand,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.onMarkAllRead != null && widget.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _markingAll
                      ? null
                      : () async {
                          setState(() => _markingAll = true);
                          try {
                            await widget.onMarkAllRead!();
                          } finally {
                            if (mounted) setState(() => _markingAll = false);
                          }
                        },
                  icon: _markingAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(_markingAll ? 'Marking…' : 'Mark all read'),
                  style: TextButton.styleFrom(
                    foregroundColor: DocuTrackerTokens.brand,
                    minimumSize: const Size(44, 40),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ),
            ),
          if (widget.showChrome ||
              (widget.onMarkAllRead != null && widget.unreadCount > 0))
            const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (urgent.isNotEmpty)
                  _NotificationGroup(
                    title: 'Overdue & escalations',
                    subtitle: 'Resolve or reassign as soon as possible.',
                    emphasize: true,
                    items: urgent,
                    unreadCount: urgent.where((n) => !n.read).length,
                    visibleLimit: urgentShow,
                    onShowMore: urgentRemain > 0
                        ? () => setState(() {
                            _urgentCap = (_urgentCap + 10).clamp(
                              0,
                              urgent.length,
                            );
                          })
                        : null,
                    remainingCount: urgentRemain,
                    onTap: widget.onNotificationTap,
                    onMarkRead: widget.onMarkRead,
                    documentReferenceOf: widget.documentReferenceOf,
                  ),
                if (routing.isNotEmpty)
                  _NotificationGroup(
                    title: 'Assignments & deadlines',
                    subtitle:
                        'Submissions, forwards, approvals, and time-sensitive reviews.',
                    emphasize: false,
                    items: routing,
                    unreadCount: routing.where((n) => !n.read).length,
                    visibleLimit: routingShow,
                    onShowMore: routingRemain > 0
                        ? () => setState(() {
                            _routingCap = (_routingCap + 10).clamp(
                              0,
                              routing.length,
                            );
                          })
                        : null,
                    remainingCount: routingRemain,
                    onTap: widget.onNotificationTap,
                    onMarkRead: widget.onMarkRead,
                    documentReferenceOf: widget.documentReferenceOf,
                  ),
                if (outcomes.isNotEmpty)
                  _NotificationGroup(
                    title: 'Returns, rejections & releases',
                    subtitle: 'Outcomes you should be aware of.',
                    emphasize: false,
                    items: outcomes,
                    unreadCount: outcomes.where((n) => !n.read).length,
                    visibleLimit: outcomesShow,
                    onShowMore: outcomesRemain > 0
                        ? () => setState(() {
                            _outcomesCap = (_outcomesCap + 10).clamp(
                              0,
                              outcomes.length,
                            );
                          })
                        : null,
                    remainingCount: outcomesRemain,
                    onTap: widget.onNotificationTap,
                    onMarkRead: widget.onMarkRead,
                    documentReferenceOf: widget.documentReferenceOf,
                  ),
                if (other.isNotEmpty)
                  _NotificationGroup(
                    title: 'Other updates',
                    subtitle: 'Additional DocuTracker notices.',
                    emphasize: false,
                    items: other,
                    unreadCount: other.where((n) => !n.read).length,
                    visibleLimit: other.length,
                    remainingCount: 0,
                    onTap: widget.onNotificationTap,
                    onMarkRead: widget.onMarkRead,
                    documentReferenceOf: widget.documentReferenceOf,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.showChrome, required this.child});

  final bool showChrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showChrome) return child;
    return Container(
      decoration: DocuTrackerStyles.listCardDecoration(context),
      child: child,
    );
  }
}

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({
    required this.title,
    required this.subtitle,
    required this.emphasize,
    required this.items,
    required this.unreadCount,
    required this.visibleLimit,
    required this.remainingCount,
    this.onShowMore,
    required this.onTap,
    this.onMarkRead,
    this.documentReferenceOf,
  });

  final String title;
  final String subtitle;
  final bool emphasize;
  final List<DocumentNotification> items;
  final int unreadCount;
  final int visibleLimit;
  final int remainingCount;
  final VoidCallback? onShowMore;
  final Future<void> Function(DocumentNotification n) onTap;
  final Future<void> Function(DocumentNotification n)? onMarkRead;
  final String? Function(DocumentNotification n)? documentReferenceOf;

  @override
  Widget build(BuildContext context) {
    final accent = emphasize
        ? Colors.deepOrange.shade800
        : DocuTrackerTokens.brand;
    final visible = items.take(visibleLimit).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unreadCount new',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final n in visible)
            _NotificationTile(
              notification: n,
              onTap: onTap,
              onMarkRead: onMarkRead,
              documentReference:
                  documentReferenceOf?.call(n) ?? n.inferredDocumentReference,
            ),
          if (onShowMore != null && remainingCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onShowMore,
                  style: TextButton.styleFrom(
                    foregroundColor: DocuTrackerTokens.brand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    minimumSize: const Size(44, 40),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  child: Text(
                    remainingCount <= 10
                        ? 'Show $remainingCount more'
                        : 'Show 10 more ($remainingCount left)',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onMarkRead,
    this.documentReference,
  });

  final DocumentNotification notification;
  final Future<void> Function(DocumentNotification n) onTap;
  final Future<void> Function(DocumentNotification n)? onMarkRead;
  final String? documentReference;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _opening = false;
  bool _marking = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onTap(widget.notification);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _markReadOnly() async {
    final mark = widget.onMarkRead;
    if (mark == null || widget.notification.read || _marking) return;
    setState(() => _marking = true);
    try {
      await mark(widget.notification);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final read = n.read;
    final accent = DocuTrackerNotificationPanel.accentFor(
      context,
      n,
      read: read,
    );
    final dark = AppTheme.dashIsDark(context);
    final hairline = dark
        ? AppTheme.dashHairlineOf(context)
        : Colors.black.withValues(alpha: 0.06);
    final headline = n.displayTitle;
    final body = n.displayBody;
    final docRef = widget.documentReference?.trim();
    final timeLabel = DocuTrackerNotificationPanel.relativeTime(n.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!_opening) _open();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: _opening
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                if (_hovered || _focused)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: Material(
              color: read
                  ? AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.35)
                  : DocuTrackerTokens.brand.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _opening ? null : _open,
                child: Semantics(
                  button: true,
                  label:
                      '${read ? 'Read' : 'Unread'} ${n.eventLabel} notification: $headline',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _focused
                                    ? accent.withValues(alpha: 0.5)
                                    : hairline,
                                width: _focused ? 1.3 : 1,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: read ? 1 : 3,
                          child: ColoredBox(color: accent),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: read
                                      ? (dark
                                            ? AppTheme.dashMutedSurfaceOf(
                                                context,
                                              )
                                            : AppTheme.lightGray.withValues(
                                                alpha: 0.5,
                                              ))
                                      : accent.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: read
                                        ? Colors.transparent
                                        : accent.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Icon(
                                  DocuTrackerNotificationPanel.iconFor(n),
                                  size: 20,
                                  color: read
                                      ? AppTheme.dashTextSecondaryOf(
                                          context,
                                        ).withValues(alpha: 0.8)
                                      : accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final stackTime =
                                            constraints.maxWidth < 240;
                                        final title = Text(
                                          headline,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: read
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                            fontSize: 14,
                                            color: read
                                                ? AppTheme.dashTextSecondaryOf(
                                                    context,
                                                  )
                                                : AppTheme.dashTextPrimaryOf(
                                                    context,
                                                  ),
                                          ),
                                        );
                                        final time = Text(
                                          timeLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: read
                                                ? AppTheme.dashTextSecondaryOf(
                                                    context,
                                                  ).withValues(alpha: 0.6)
                                                : accent,
                                            fontWeight: read
                                                ? FontWeight.normal
                                                : FontWeight.w600,
                                          ),
                                        );
                                        if (stackTime) {
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              title,
                                              if (timeLabel.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                time,
                                              ],
                                            ],
                                          );
                                        }
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: title),
                                            if (timeLabel.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              time,
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                    if (docRef != null && docRef.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 13,
                                            color:
                                                AppTheme.dashTextSecondaryOf(
                                                  context,
                                                ).withValues(alpha: 0.75),
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              docRef,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppTheme.dashTextSecondaryOf(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (body != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.3,
                                          color: read
                                              ? AppTheme.dashTextSecondaryOf(
                                                  context,
                                                ).withValues(alpha: 0.7)
                                              : AppTheme.dashTextSecondaryOf(
                                                  context,
                                                ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: dark
                                                ? AppTheme.dashMutedSurfaceOf(
                                                    context,
                                                  )
                                                : AppTheme.lightGray,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            n.eventLabel.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                              color:
                                                  AppTheme.dashTextSecondaryOf(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        if (!read)
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: DocuTrackerTokens.brand,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        if (!read && widget.onMarkRead != null)
                                          TextButton(
                                            onPressed: _marking
                                                ? null
                                                : _markReadOnly,
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  DocuTrackerTokens.brand,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: const Size(44, 32),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            child: Text(
                                              _marking
                                                  ? 'Marking…'
                                                  : 'Mark read',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _opening
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accent,
                                        ),
                                      )
                                    : Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ).withValues(alpha: 0.4),
                                        size: 22,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
