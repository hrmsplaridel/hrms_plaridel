import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _assistantAnimation = 'assets/animations/chatbot_assistant.json';
const _tutorialVersion = 2;

enum EmployeeTutorialSection {
  dashboard,
  attendance,
  leave,
  locator,
  trainingReports,
  trainingRequirements,
  docuTracker,
  profileSettings,
}

class EmployeeTutorialController {
  EmployeeTutorialController._();

  static final ValueNotifier<bool> coachActive = ValueNotifier<bool>(false);

  static String _preferenceKey(
    String? userId,
    EmployeeTutorialSection section,
  ) =>
      'employee_tutorial_v$_tutorialVersion:${userId ?? 'device'}:${section.name}';

  static Future<void> showIfNeeded(
    BuildContext context, {
    required String? userId,
    EmployeeTutorialSection section = EmployeeTutorialSection.dashboard,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_preferenceKey(userId, section)) ?? false) return;
    if (!context.mounted) return;
    await show(context, userId: userId, section: section);
  }

  static Future<void> show(
    BuildContext context, {
    required String? userId,
    EmployeeTutorialSection section = EmployeeTutorialSection.dashboard,
  }) async {
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmployeeTutorialDialog(section: section),
    );
    if (completed != true) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey(userId, section), true);
  }

  static Future<void> showDashboardCoachIfNeeded(
    BuildContext context, {
    required String? userId,
    required List<EmployeeTutorialTarget> targets,
  }) async {
    await showCoachIfNeeded(
      context,
      userId: userId,
      section: EmployeeTutorialSection.dashboard,
      targets: targets,
    );
  }

  static Future<void> showDashboardCoach(
    BuildContext context, {
    required String? userId,
    required List<EmployeeTutorialTarget> targets,
  }) async {
    await showCoach(
      context,
      userId: userId,
      section: EmployeeTutorialSection.dashboard,
      targets: targets,
    );
  }

  static Future<void> showCoachIfNeeded(
    BuildContext context, {
    required String? userId,
    required EmployeeTutorialSection section,
    required List<EmployeeTutorialTarget> targets,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_preferenceKey(userId, section)) ?? false) return;
    if (!context.mounted) return;
    await showCoach(
      context,
      userId: userId,
      section: section,
      targets: targets,
    );
  }

  static Future<void> showCoach(
    BuildContext context, {
    required String? userId,
    required EmployeeTutorialSection section,
    required List<EmployeeTutorialTarget> targets,
  }) async {
    coachActive.value = true;
    bool? completed;
    try {
      completed = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, secondaryAnimation) =>
            _EmployeeDashboardCoach(targets: targets),
        transitionBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );
    } finally {
      coachActive.value = false;
    }
    if (completed != true) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey(userId, section), true);
  }
}

class EmployeeTutorialTarget {
  const EmployeeTutorialTarget({
    required this.key,
    required this.title,
    required this.body,
  });

  final GlobalKey key;
  final String title;
  final String body;
}

class _EmployeeDashboardCoach extends StatefulWidget {
  const _EmployeeDashboardCoach({required this.targets});

  final List<EmployeeTutorialTarget> targets;

  @override
  State<_EmployeeDashboardCoach> createState() =>
      _EmployeeDashboardCoachState();
}

class _EmployeeDashboardCoachState extends State<_EmployeeDashboardCoach> {
  int _index = 0;
  Rect? _targetRect;

  EmployeeTutorialTarget get _target => widget.targets[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTarget());
  }

  Future<void> _focusTarget([int attempt = 0]) async {
    final targetContext = _target.key.currentContext;
    if (targetContext == null) {
      if (attempt < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (mounted) await _focusTarget(attempt + 1);
        return;
      }
      _advance();
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      alignment: 0.35,
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || !targetContext.mounted) return;
    final box = targetContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() {
      _targetRect = box.localToGlobal(Offset.zero) & box.size;
    });
  }

  void _advance() {
    if (_index >= widget.targets.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index++;
      _targetRect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTarget());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final rect = _targetRect;
    final bubbleWidth = compact ? size.width - 32 : 390.0;
    final placeBelow = rect == null || rect.center.dy < size.height * 0.48;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TutorialSpotlightPainter(target: rect),
            ),
          ),
          if (rect != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOutCubic,
              left: (rect.left - 6).clamp(8, size.width - 16),
              top: (rect.top - 6).clamp(8, size.height - 16),
              width: (rect.width + 12).clamp(0, size.width - 16),
              height: (rect.height + 12).clamp(0, size.height - 16),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: .45),
                        blurRadius: 18,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 18,
            right: 18,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Skip tour'),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
            left: compact ? 16 : null,
            right: 16,
            top: placeBelow ? null : 30,
            bottom: placeBelow ? (compact ? 24 : 30) : null,
            width: compact ? null : bubbleWidth,
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: compact ? 82 : 110,
                    height: compact ? 100 : 130,
                    child: Lottie.asset(
                      _assistantAnimation,
                      animate: !reduceMotion,
                      repeat: !reduceMotion,
                      fit: BoxFit.contain,
                      renderCache: RenderCache.raster,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TutorialSpeechBubble(
                      title: _target.title,
                      body: _target.body,
                      current: _index + 1,
                      total: widget.targets.length,
                      onNext: _advance,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialSpeechBubble extends StatelessWidget {
  const _TutorialSpeechBubble({
    required this.title,
    required this.body,
    required this.current,
    required this.total,
    required this.onNext,
  });

  final String title;
  final String body;
  final int current;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('$current of $total', style: theme.textTheme.labelMedium),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                child: Text(current == total ? 'Finish' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TutorialSpotlightPainter extends CustomPainter {
  const _TutorialSpotlightPainter({required this.target});

  final Rect? target;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (target != null) {
      overlay.addRRect(
        RRect.fromRectAndRadius(target!.inflate(6), const Radius.circular(18)),
      );
      overlay.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: .68),
    );
  }

  @override
  bool shouldRepaint(covariant _TutorialSpotlightPainter oldDelegate) =>
      oldDelegate.target != target;
}

class EmployeeTutorialButton extends StatelessWidget {
  const EmployeeTutorialButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Help for this page',
      onPressed: onPressed,
      icon: const Icon(Icons.help_outline_rounded),
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

const _sectionSteps = <EmployeeTutorialSection, List<_TutorialStep>>{
  EmployeeTutorialSection.profileSettings: [
    _TutorialStep(
      icon: Icons.person_outline_rounded,
      title: 'Keep your profile current',
      body:
          'Review your account and employee information and update the fields that your account permits.',
    ),
    _TutorialStep(
      icon: Icons.lock_outline_rounded,
      title: 'Protect your account',
      body:
          'Use password and security settings to maintain secure sign-in details.',
    ),
    _TutorialStep(
      icon: Icons.tune_rounded,
      title: 'Adjust app preferences',
      body:
          'Choose appearance and other available preferences. Use the back action to return to the dashboard.',
    ),
  ],
};

class _EmployeeTutorialDialog extends StatefulWidget {
  const _EmployeeTutorialDialog({required this.section});

  final EmployeeTutorialSection section;

  @override
  State<_EmployeeTutorialDialog> createState() =>
      _EmployeeTutorialDialogState();
}

class _EmployeeTutorialDialogState extends State<_EmployeeTutorialDialog> {
  final _controller = PageController();
  int _index = 0;
  List<_TutorialStep> get _steps => _sectionSteps[widget.section]!;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _steps.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 40,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 20 : 30,
            18,
            compact ? 20 : 30,
            22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Skip'),
                ),
              ),
              SizedBox(
                height: compact ? 105 : 125,
                child: ClipRect(
                  child: Transform.scale(
                    scale: 1.35,
                    child: Lottie.asset(
                      _assistantAnimation,
                      animate: !reduceMotion,
                      repeat: !reduceMotion,
                      fit: BoxFit.contain,
                      renderCache: RenderCache.raster,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: compact ? 210 : 190,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    final item = _steps[index];
                    return Semantics(
                      label: '${item.title}. ${item.body}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            size: 34,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            item.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(
                      _index == _steps.length - 1
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(
                      _index == _steps.length - 1 ? 'Get started' : 'Next',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
