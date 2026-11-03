import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_notification_sheet.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// DocuTracker-only notification bell. Opens the in-module slide-in panel.
///
/// Keeps the global HRMS header bell unchanged; this is for DocuTracker screens.
class DocuTrackerNotificationBellButton extends StatefulWidget {
  const DocuTrackerNotificationBellButton({
    super.key,
    required this.isAdmin,
    this.compact = false,
    this.tooltip = 'DocuTracker notifications',
  });

  final bool isAdmin;
  final bool compact;
  final String tooltip;

  @override
  State<DocuTrackerNotificationBellButton> createState() =>
      _DocuTrackerNotificationBellButtonState();
}

class _DocuTrackerNotificationBellButtonState
    extends State<DocuTrackerNotificationBellButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await showDocuTrackerNotificationPanel(
        context,
        isAdmin: widget.isAdmin,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select<DocuTrackerProvider, int>(
      (p) => p.unreadNotificationsCount,
    );
    final dark = DocuTrackerTokens.isDark(context);
    final iconSize = widget.compact ? 20.0 : 22.0;
    final pad = widget.compact ? 8.0 : 10.0;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: unread > 0
            ? 'DocuTracker notifications, $unread unread'
            : 'DocuTracker notifications',
        child: Material(
          color: dark
              ? DocuTrackerTokens.surfaceDark
              : DocuTrackerTokens.surfaceCream,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _opening ? null : _open,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: _opening
                      ? SizedBox(
                          width: iconSize,
                          height: iconSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DocuTrackerTokens.brand,
                          ),
                        )
                      : Icon(
                          Icons.notifications_outlined,
                          color: DocuTrackerTokens.brand,
                          size: iconSize,
                        ),
                ),
                if (unread > 0 && !_opening)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        color: DocuTrackerTokens.overdueAccent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dark
                              ? DocuTrackerTokens.surfaceDark
                              : Colors.white,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
