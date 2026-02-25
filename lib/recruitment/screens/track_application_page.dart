import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';

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
      final app = await RecruitmentRepo.instance.getApplicationByEmail(email);
      RecruitmentExamResult? exam;
      if (app != null) {
        exam = await RecruitmentRepo.instance.getExamResult(app.id);
      }
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
      final app = await RecruitmentRepo.instance.getApplicationByEmail(_application!.email);
      RecruitmentExamResult? exam;
      if (app != null) {
        exam = await RecruitmentRepo.instance.getExamResult(app.id);
      }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the email address you used when you submitted your application. The system will show your current status and what happens next.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'e.g. applicant@email.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.email_outlined),
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 32),
                  _StatusTimeline(application: _application!, examResult: _examResult),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Timeline that auto-detects and displays each step of the applicant process.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.application, this.examResult});

  final RecruitmentApplication application;
  final RecruitmentExamResult? examResult;

  @override
  Widget build(BuildContext context) {
    final status = application.status;
    final hasExamResult = examResult != null;
    final passed = examResult?.passed ?? false;
    final score = examResult?.scorePercent ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded, color: AppTheme.primaryNavy, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(application.fullName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text(application.email, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Status is refreshed every 30 seconds so you see the latest. You can also tap Refresh in the app bar.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _StepTile(
            step: 1,
            title: 'Application submitted',
            subtitle: 'Your basic info and document were received.',
            status: _StepStatus.done,
          ),
          _StepTile(
            step: 2,
            title: 'Document review',
            subtitle: _documentReviewSubtitle(status),
            status: _documentReviewStatus(status),
          ),
          _StepTile(
            step: 3,
            title: 'Exams (BEI, General, Math, General Info)',
            subtitle: _examsSubtitle(status, hasExamResult),
            status: _examsStatus(status, hasExamResult),
          ),
          _StepTile(
            step: 4,
            title: 'Exam result',
            subtitle: hasExamResult ? (passed ? 'Passed (${score.toStringAsFixed(0)}%). You may proceed to registration.' : 'Not passed (${score.toStringAsFixed(0)}%). You may reapply with a new application.') : 'Complete the exams to see your result.',
            status: hasExamResult ? (passed ? _StepStatus.done : _StepStatus.failed) : _StepStatus.pending,
          ),
          _StepTile(
            step: 5,
            title: 'Registration & account',
            subtitle: (status == 'passed' || status == 'registered') ? 'Create your account to access the employee portal (use the same email).' : (passed ? 'Available after passing the exam.' : '—'),
            status: status == 'registered' ? _StepStatus.done : (passed ? _StepStatus.current : _StepStatus.pending),
          ),
          _StepTile(
            step: 6,
            title: 'Interview & final hiring',
            subtitle: 'HR will contact you if you are shortlisted. Final decision will be communicated by the HR office.',
            status: (status == 'registered' || status == 'passed') ? _StepStatus.current : _StepStatus.pending,
          ),
        ],
      ),
    );
  }

  String _documentReviewSubtitle(String status) {
    switch (status) {
      case 'submitted':
        return 'Under review. You will be notified when your documents are approved so you can take the exam.';
      case 'document_approved':
        return 'Approved. You can continue to the exams (use "Start Application" and continue with your email).';
      case 'document_declined':
        return 'Your documents were not approved. You may submit a new application with updated documents.';
      default:
        return '—';
    }
  }

  _StepStatus _documentReviewStatus(String status) {
    if (status == 'document_approved') return _StepStatus.done;
    if (status == 'document_declined') return _StepStatus.failed;
    if (status == 'submitted') return _StepStatus.current;
    return _StepStatus.pending;
  }

  String _examsSubtitle(String status, bool hasExamResult) {
    if (hasExamResult) return 'Completed.';
    if (status == 'document_approved') return 'Ready to take. Use "Start Application" on the recruitment page and continue with your email.';
    if (status == 'submitted' || status == 'document_declined') return 'Available after your documents are approved.';
    return '—';
  }

  _StepStatus _examsStatus(String status, bool hasExamResult) {
    if (hasExamResult) return _StepStatus.done;
    if (status == 'document_approved') return _StepStatus.current;
    return _StepStatus.pending;
  }
}

enum _StepStatus { done, current, pending, failed }

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final int step;
  final String title;
  final String subtitle;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    Color iconColor;
    IconData icon;
    switch (status) {
      case _StepStatus.done:
        iconColor = const Color(0xFFE85D04);
        icon = Icons.check_circle_rounded;
        break;
      case _StepStatus.current:
        iconColor = AppTheme.primaryNavy;
        icon = Icons.pending_rounded;
        break;
      case _StepStatus.failed:
        iconColor = Colors.red.shade700;
        icon = Icons.cancel_rounded;
        break;
      case _StepStatus.pending:
        iconColor = AppTheme.textSecondary;
        icon = Icons.radio_button_unchecked_rounded;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Step $step: $title', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
