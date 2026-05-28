import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';
import '../widgets/rsp_application_status_timeline.dart';

/// Screen for applicants to track their application status by email.
/// Auto-detects and displays the current step in the process (document review, exams, result, etc.).
/// Refreshes status periodically so changes (e.g. admin approval) are detected automatically.
class TrackApplicationPage extends StatefulWidget {
  const TrackApplicationPage({super.key});

  @override
  State<TrackApplicationPage> createState() => _TrackApplicationPageState();
}

class _TrackApplicationPageState extends State<TrackApplicationPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _loading = false;
  RecruitmentApplication? _application;
  RecruitmentExamResult? _examResult;
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  late AnimationController _resultAnimController;
  late Animation<double> _resultFade;
  late Animation<Offset> _resultSlide;

  @override
  void initState() {
    super.initState();
    _resultAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _resultFade = CurvedAnimation(
      parent: _resultAnimController,
      curve: Curves.easeOut,
    );
    _resultSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resultAnimController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _emailController.dispose();
    _emailFocusNode.dispose();
    _resultAnimController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _application != null && !_loading) _refresh();
    });
  }

  Future<void> _checkStatus() async {
    final email = _emailController.text.trim();
    _emailFocusNode.unfocus();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the email you used when applying.';
        _application = null;
        _examResult = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
      _application = null;
      _examResult = null;
    });
    _resultAnimController.reset();
    try {
      final lookup =
          await RecruitmentRepo.instance.getApplicationByEmail(email);
      final app = lookup?.application;
      final exam = lookup?.examResult;
      if (mounted) {
        setState(() {
          _application = app;
          _examResult = exam;
          _loading = false;
          _errorMessage =
              app == null ? 'No application found for this email.' : null;
        });
        if (app != null) {
          _resultAnimController.forward();
          _startAutoRefresh();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Could not load status. Please try again.';
          _application = null;
          _examResult = null;
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (_application == null) return;
    setState(() => _loading = true);
    try {
      final lookup = await RecruitmentRepo.instance
          .getApplicationByEmail(_application!.email);
      final app = lookup?.application;
      final exam = lookup?.examResult;
      if (mounted) {
        setState(() {
          _application = app;
          _examResult = exam;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: kIsWeb ? 180 : 160,
            collapsedHeight: kToolbarHeight,
            pinned: true,
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (_application != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: _refresh,
                          tooltip: 'Refresh status',
                        ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeroHeader(isWide: isWide),
              title: const Text(
                'Track Application Status',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: -0.2,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
            ),
          ),
        ],
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 20,
            vertical: 28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 600 : double.infinity),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LookupCard(
                    emailController: _emailController,
                    emailFocusNode: _emailFocusNode,
                    loading: _loading,
                    onCheck: _checkStatus,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 20),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                  if (_application != null && _errorMessage == null) ...[
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _resultFade,
                      child: SlideTransition(
                        position: _resultSlide,
                        child: RspApplicationStatusTimeline(
                          application: _application!,
                          examResult: _examResult,
                          sameAsRecruitmentFlowNote: true,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero header in the SliverAppBar flexible space ──────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.isWide});
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavyDark,
            AppTheme.primaryNavy,
            AppTheme.primaryNavyLight.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 40 : 24,
            kToolbarHeight + 8,
            isWide ? 40 : 24,
            20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track your application',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isWide ? 22 : 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Look up by email · Auto-refreshes every 30 s',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Email lookup card ────────────────────────────────────────────────────────

class _LookupCard extends StatelessWidget {
  const _LookupCard({
    required this.emailController,
    required this.emailFocusNode,
    required this.loading,
    required this.onCheck,
  });

  final TextEditingController emailController;
  final FocusNode emailFocusNode;
  final bool loading;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Accent bar
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavyDark,
                  AppTheme.primaryNavy,
                  AppTheme.primaryNavyLight,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Help text row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryNavy.withValues(alpha: 0.14),
                            AppTheme.primaryNavyLight.withValues(alpha: 0.07),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.mail_outline_rounded,
                        color: AppTheme.primaryNavy,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter your email address',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Use the same email you submitted your application with.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Email field
                TextField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  decoration: InputDecoration(
                    hintText: 'e.g. juan.delacruz@email.com',
                    hintStyle: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.55),
                      fontSize: 14.5,
                    ),
                    prefixIcon: Icon(
                      Icons.alternate_email_rounded,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: emailController,
                      builder: (_, value, __) => value.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: AppTheme.textSecondary
                                    .withValues(alpha: 0.6),
                              ),
                              onPressed: () => emailController.clear(),
                            )
                          : const SizedBox.shrink(),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.lightGray.withValues(alpha: 0.9),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.lightGray.withValues(alpha: 0.9),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryNavy,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 17,
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onCheck(),
                ),
                const SizedBox(height: 16),
                // Check status button — full width
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: loading ? null : onCheck,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primaryNavy.withValues(alpha: 0.55),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: loading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Checking…',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Check Status',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                // Auto-refresh info row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.autorenew_rounded,
                      size: 14,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Status auto-refreshes every 30 seconds once loaded',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withValues(alpha: 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isNotFound = message.contains('No application');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNotFound
            ? const Color(0xFFFFF3E0)
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNotFound
              ? const Color(0xFFFFB74D)
              : Colors.red.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isNotFound
                ? Icons.search_off_rounded
                : Icons.error_outline_rounded,
            color: isNotFound
                ? const Color(0xFFE65100)
                : Colors.red.shade700,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNotFound ? 'No record found' : 'Something went wrong',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isNotFound
                        ? const Color(0xFFBF360C)
                        : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: isNotFound
                        ? const Color(0xFFBF360C).withValues(alpha: 0.85)
                        : Colors.red.shade800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
