import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Lightweight placeholder while the account form mounts on the next frame.
class ProfileAccountTabSkeleton extends StatelessWidget {
  const ProfileAccountTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.dashHairlineOf(context);
    final fill = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    Widget bar({double height = 48, double? width}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: base),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar(height: 22, width: 140),
        const SizedBox(height: 16),
        bar(),
        const SizedBox(height: 12),
        bar(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: bar()),
            const SizedBox(width: 12),
            Expanded(child: bar()),
          ],
        ),
        const SizedBox(height: 12),
        bar(),
        const SizedBox(height: 12),
        bar(height: 72),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// Defers building a heavy subtree until after the current frame is painted.
class DeferredProfileMount extends StatefulWidget {
  const DeferredProfileMount({
    super.key,
    required this.builder,
    this.placeholder = const ProfileAccountTabSkeleton(),
    this.delayFrames = 1,
  });

  final Widget Function() builder;
  final Widget placeholder;
  final int delayFrames;

  @override
  State<DeferredProfileMount> createState() => _DeferredProfileMountState();
}

class _DeferredProfileMountState extends State<DeferredProfileMount> {
  Widget? _child;
  int _framesLeft = 0;

  @override
  void initState() {
    super.initState();
    _scheduleMount();
  }

  @override
  void didUpdateWidget(DeferredProfileMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _child = null;
      _scheduleMount();
    }
  }

  void _scheduleMount() {
    _framesLeft = widget.delayFrames;
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(_) {
    if (!mounted) return;
    if (_framesLeft > 0) {
      _framesLeft--;
      WidgetsBinding.instance.addPostFrameCallback(_onFrame);
      return;
    }
    setState(() => _child = widget.builder());
  }

  @override
  Widget build(BuildContext context) {
    return _child ?? widget.placeholder;
  }
}
