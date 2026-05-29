import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';

/// Opens [child] as a right-side slide-in panel (full-screen route on narrow viewports).
Future<T?> showDocuTrackerSlideInPanel<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  double width = 420,
  Widget? headerTrailing,
}) async {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  const breakpoint = 600.0;

  if (viewportWidth < breakpoint) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (ctx) => _DocuTrackerSlideInPanelScaffold(
          title: title,
          headerTrailing: headerTrailing,
          child: child,
        ),
      ),
    );
  }

  final panelWidth = width.clamp(300.0, viewportWidth * 0.92);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close $title',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: DocuTrackerTokens.surface,
            elevation: 12,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: _DocuTrackerSlideInPanelScaffold(
                title: title,
                headerTrailing: headerTrailing,
                child: child,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _DocuTrackerSlideInPanelScaffold extends StatelessWidget {
  const _DocuTrackerSlideInPanelScaffold({
    required this.title,
    required this.child,
    this.headerTrailing,
  });

  final String title;
  final Widget child;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.surface,
            border: Border(
              bottom: BorderSide(color: DocuTrackerTokens.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                headerTrailing!,
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: DocuTrackerTokens.textMuted,
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
