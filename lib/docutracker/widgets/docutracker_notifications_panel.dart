import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_styles.dart';
import '../models/document_notification.dart';

/// Grouped DocuTracker notifications with read/unread styling, taps, paging per group, and mark-all-read.
class DocuTrackerNotificationPanel extends StatefulWidget {
  const DocuTrackerNotificationPanel({
    super.key,
    required this.notifications,
    required this.unreadCount,
    required this.onNotificationTap,
    this.onMarkAllRead,
    this.initialVisiblePerGroup = 5,
  });

  final List<DocumentNotification> notifications;
  final int unreadCount;
  final Future<void> Function(DocumentNotification n) onNotificationTap;
  final Future<void> Function()? onMarkAllRead;
  final int initialVisiblePerGroup;

  static int typeRank(String type) {
    return switch (type) {
      DocumentNotification.typeOverdue => 0,
      DocumentNotification.typeEscalated => 1,
      DocumentNotification.typeAssigned => 2,
      DocumentNotification.typeDeadlineNear => 3,
      DocumentNotification.typeRejected => 4,
      DocumentNotification.typeReturned => 5,
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
  ) =>
      list.where((n) => types.contains(n.type)).toList();

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
    if (widget.notifications.isEmpty) return const SizedBox.shrink();

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
    });

    final urgentShow = _urgentCap.clamp(0, urgent.length);
    final routingShow = _routingCap.clamp(0, routing.length);
    final outcomesShow = _outcomesCap.clamp(0, outcomes.length);
    final urgentRemain = urgent.length - urgentShow;
    final routingRemain = routing.length - routingShow;
    final outcomesRemain = outcomes.length - outcomesShow;

    return Container(
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.primaryNavy,
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
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.unreadCount > 0
                            ? '${widget.unreadCount} unread — tap an item to open the document'
                            : 'All caught up — tap to review a document',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy,
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
                    foregroundColor: AppTheme.primaryNavy,
                  ),
                ),
              ),
            ),
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
                              _urgentCap =
                                  (_urgentCap + 10).clamp(0, urgent.length);
                            })
                        : null,
                    remainingCount: urgentRemain,
                    onTap: widget.onNotificationTap,
                  ),
                if (routing.isNotEmpty)
                  _NotificationGroup(
                    title: 'Assignments & deadlines',
                    subtitle:
                        'New work on your desk or time-sensitive reviews.',
                    emphasize: false,
                    items: routing,
                    unreadCount: routing.where((n) => !n.read).length,
                    visibleLimit: routingShow,
                    onShowMore: routingRemain > 0
                        ? () => setState(() {
                              _routingCap =
                                  (_routingCap + 10).clamp(0, routing.length);
                            })
                        : null,
                    remainingCount: routingRemain,
                    onTap: widget.onNotificationTap,
                  ),
                if (outcomes.isNotEmpty)
                  _NotificationGroup(
                    title: 'Returns & rejections',
                    subtitle: 'Outcomes you should be aware of.',
                    emphasize: false,
                    items: outcomes,
                    unreadCount: outcomes.where((n) => !n.read).length,
                    visibleLimit: outcomesShow,
                    onShowMore: outcomesRemain > 0
                        ? () => setState(() {
                              _outcomesCap =
                                  (_outcomesCap + 10).clamp(0, outcomes.length);
                            })
                        : null,
                    remainingCount: outcomesRemain,
                    onTap: widget.onNotificationTap,
                  ),
              ],
            ),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final accent = emphasize
        ? Colors.deepOrange.shade800
        : AppTheme.primaryNavy;
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
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        color: AppTheme.textSecondary,
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
          for (final n in visible) _NotificationTile(notification: n, onTap: onTap),
          if (onShowMore != null && remainingCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onShowMore,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final DocumentNotification notification;
  final Future<void> Function(DocumentNotification n) onTap;

  static IconData _icon(String type) {
    return switch (type) {
      DocumentNotification.typeAssigned => Icons.inbox_rounded,
      DocumentNotification.typeDeadlineNear => Icons.schedule_rounded,
      DocumentNotification.typeOverdue => Icons.warning_amber_rounded,
      DocumentNotification.typeEscalated => Icons.trending_up_rounded,
      DocumentNotification.typeReturned => Icons.reply_rounded,
      DocumentNotification.typeRejected => Icons.cancel_outlined,
      _ => Icons.notifications_none_rounded,
    };
  }

  static Color _accent(String type, bool read) {
    if (read) return AppTheme.textSecondary.withValues(alpha: 0.35);
    return switch (type) {
      DocumentNotification.typeOverdue => Colors.deepOrange.shade800,
      DocumentNotification.typeEscalated => Colors.red.shade800,
      DocumentNotification.typeRejected => Colors.purple.shade800,
      DocumentNotification.typeReturned => AppTheme.primaryNavy,
      DocumentNotification.typeDeadlineNear => Colors.amber.shade900,
      DocumentNotification.typeAssigned => AppTheme.primaryNavy,
      _ => AppTheme.primaryNavy,
    };
  }

  static String _relativeTime(DateTime? t) {
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
  Widget build(BuildContext context) {
    final n = notification;
    final read = n.read;
    final accent = _accent(n.type, read);
    final headline = (n.title != null && n.title!.trim().isNotEmpty)
        ? n.title!
        : n.displayType;
    final body = (n.body != null && n.body!.trim().isNotEmpty)
        ? n.body!.trim()
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: read
            ? AppTheme.offWhite.withValues(alpha: 0.35)
            : AppTheme.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(n),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: read ? AppTheme.lightGray.withValues(alpha: 0.5) : accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: read ? Colors.transparent : accent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          _icon(n.type),
                          size: 20,
                          color: read ? AppTheme.textSecondary.withValues(alpha: 0.8) : accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    headline,
                                    style: TextStyle(
                                      fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                                      fontSize: 14,
                                      color: read ? AppTheme.textSecondary : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _relativeTime(n.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: read ? AppTheme.textSecondary.withValues(alpha: 0.6) : accent,
                                    fontWeight: read ? FontWeight.normal : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (body != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: read ? AppTheme.textSecondary.withValues(alpha: 0.7) : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.lightGray,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    n.displayType.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                if (!read) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primaryNavy,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.textSecondary.withValues(alpha: 0.4),
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
    );
  }
}
