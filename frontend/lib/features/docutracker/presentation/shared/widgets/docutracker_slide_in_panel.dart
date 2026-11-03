import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

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
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: DocuTrackerTokens.surfaceOf(ctx),
          body: SafeArea(
            child: _DocuTrackerSlideInPanelScaffold(
              title: title,
              headerTrailing: headerTrailing,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  final panelWidth = width.clamp(300.0, viewportWidth * 0.92);

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close $title',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: DocuTrackerTokens.surfaceOf(ctx),
            elevation: 12,
            clipBehavior: Clip.antiAlias,
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
    transitionBuilder: (ctx, animation, _, panelChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: panelChild,
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
            color: DocuTrackerTokens.surfaceOf(context),
            border: Border(
              bottom: BorderSide(
                color: DocuTrackerTokens.borderSubtleOf(context),
              ),
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
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                color: DocuTrackerTokens.textMutedOf(context),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
