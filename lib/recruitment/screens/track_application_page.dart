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

class _TrackApplicationPageState extends State<TrackApplicationPage> {
  final _emailController = TextEditingController();
  bool _loading = false;
  RecruitmentApplication? _application;
  RecruitmentExamResult? _examResult;
  String? _errorMessage;
  Timer? _autoRefreshTimer;

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _emailController.dispose();
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
    try {
      final lookup = await RecruitmentRepo.instance.getApplicationByEmail(email);
      final app = lookup?.application;
      final exam = lookup?.examResult;
      if (mounted) {
        setState(() {
          _application = app;
          _examResult = exam;
          _loading = false;
          _errorMessage = app == null ? 'No application found for this email.' : null;
        });
        if (app != null) _startAutoRefresh();
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
      final lookup =
          await RecruitmentRepo.instance.getApplicationByEmail(_application!.email);
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
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Track Application Status'),
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_application != null)
            IconButton(
              icon: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _refresh,
              tooltip: 'Refresh status (auto-detect latest)',
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final lookupFormInner = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the email address you used when you submitted your application. The system will show your current status and what happens next.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: kIsWeb ? 16 : 14,
                  height: 1.55,
                  fontWeight: kIsWeb ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              SizedBox(height: kIsWeb ? 24 : 20),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  labelStyle: TextStyle(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  floatingLabelStyle: const TextStyle(
                    color: AppTheme.primaryNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  hintText: 'e.g. applicant@email.com',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    fontSize: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppTheme.lightGray.withValues(alpha: 0.95),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryNavy,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: Icon(
                    Icons.alternate_email_rounded,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.55),
                    size: 22,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _checkStatus(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _checkStatus,
                icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search_rounded, size: 22),
                label: Text(_loading ? 'Checking...' : 'Check status'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
          final lookupForm = Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6F1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.lightGray.withValues(alpha: 0.88),
              ),
              boxShadow: AppTheme.panelShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 4,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppTheme.primaryNavyDark,
                        AppTheme.primaryNavy,
                        AppTheme.primaryNavyLight,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(kIsWeb ? 28 : 22),
                  child: lookupFormInner,
                ),
              ],
            ),
          );

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: kIsWeb ? 32 : 24, vertical: kIsWeb ? 32 : 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: kIsWeb ? 440 : 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (kIsWeb) ...[
                        Text(
                          'Track your application',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryNavy,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Status updates automatically every 30 seconds after you look up an application.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 28),
                      ],
                      lookupForm,
                      if (_errorMessage != null) ...[
                        SizedBox(height: kIsWeb ? 24 : 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.red.shade700, size: 24),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900, fontSize: 14))),
                            ],
                          ),
                        ),
                      ],
                      if (_application != null && _errorMessage == null) ...[
                        SizedBox(height: kIsWeb ? 28 : 32),
                        RspApplicationStatusTimeline(
                          application: _application!,
                          examResult: _examResult,
                          sameAsRecruitmentFlowNote: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
