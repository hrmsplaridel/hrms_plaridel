import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_scheduling_ui.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_final_interview_report_export.dart';
import 'rsp_final_interview_report_preview_screen.dart';
import 'rsp_generate_report_dialog.dart';

/// Admin: applicants who passed the screening exam — schedule deliberation and record results.
class RspFinalInterviewScheduler extends StatefulWidget {
  const RspFinalInterviewScheduler({super.key, this.embedded = false});

  /// When true, hides the page hero (used inside [RspSchedulingSection]).
  final bool embedded;

  @override
  State<RspFinalInterviewScheduler> createState() =>
      _RspFinalInterviewSchedulerState();
}

class _RspFinalInterviewSchedulerState
    extends State<RspFinalInterviewScheduler> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  bool _latestFirst = true;
  bool _loading = true;
  bool _exportingReport = false;
  final Set<String> _savingIds = {};

  /// Any applicant can be collapsed to a compact row until expanded.
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final apps = await RecruitmentRepo.instance.listApplications();
    final exams = await RecruitmentRepo.instance.getExamResultsByApplication();
    if (!mounted) return;
    setState(() {
      _applications = apps;
      _examResults = exams;
      _loading = false;
    });
  }

  /// Sort key = latest relevant deliberation scheduling activity (the
  /// deliberation appointment). Falls back to the application/record
  /// timestamp when no schedule has been set yet.
  DateTime? _schedulingActivityKey(RecruitmentApplication a) =>
      a.finalInterviewAt ?? a.createdAt ?? a.updatedAt;

  int _compareBySchedulingActivity(
    RecruitmentApplication a,
    RecruitmentApplication b,
  ) {
    final ad = _schedulingActivityKey(a);
    final bd = _schedulingActivityKey(b);
    if (ad == null && bd == null) {
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    }
    if (ad == null) return 1;
    if (bd == null) return -1;
    return _latestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
  }

  List<RecruitmentApplication> get _passedApplicants {
    final out = <RecruitmentApplication>[];
    for (final a in _applications) {
      final ex = _examResults[a.id.toLowerCase()];
      if (ex != null && ex.passed) out.add(a);
    }
    out.sort(_compareBySchedulingActivity);
    return out;
  }

  Set<String> get _positionFilterOptions {
    final out = <String>{};
    for (final a in _passedApplicants) {
      final p = (a.positionAppliedFor ?? '').trim();
      if (p.isNotEmpty) out.add(p);
    }
    return out;
  }

  bool _isSameLocalDate(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  bool get _hasActiveFilters =>
      _selectedPositionFilter != null || _selectedAppliedDate != null;

  String _reportFilterSummary() {
    final parts = <String>[];
    if (_selectedPositionFilter != null &&
        _selectedPositionFilter!.trim().isNotEmpty) {
      parts.add('Position: ${_selectedPositionFilter!.trim()}');
    }
    if (_selectedAppliedDate != null) {
      parts.add('Applied date: ${_formatDateShort(_selectedAppliedDate!)}');
    }
    if (parts.isEmpty) {
      return 'Filters: none (all passed-exam applicants)';
    }
    return 'Filters: ${parts.join(' · ')}';
  }

  List<RspFinalInterviewReportRow> _reportRows() {
    return _filteredPassedApplicants
        .map((app) {
          final exam = _examResults[app.id.toLowerCase()];
          if (exam == null) return null;
          return RspFinalInterviewReportRow.fromApplication(
            app: app,
            exam: exam,
          );
        })
        .whereType<RspFinalInterviewReportRow>()
        .toList();
  }

  Future<void> _showGenerateReportDialog() async {
    final apps = _filteredPassedApplicants;
    if (apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No applicants match the current filters. Adjust filters or refresh.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var scheduled = 0;
    var hired = 0;
    for (final app in apps) {
      if (app.finalInterviewAt != null) scheduled++;
      if (_isRegistered(app)) hired++;
    }

    final choice = await RspGenerateReportDialog.showFinalInterview(
      context,
      applicantCount: apps.length,
      filterSummary: _reportFilterSummary(),
      scheduledCount: scheduled,
      hiredCount: hired,
    );
    if (choice == null || !mounted) return;

    final rows = _reportRows();
    final summary = _reportFilterSummary();

    if (choice == RspReportExportChoice.preview) {
      await RspFinalInterviewReportPreviewScreen.open(
        context,
        rows: rows,
        filterSummary: summary,
      );
      return;
    }

    setState(() => _exportingReport = true);
    try {
      switch (choice) {
        case RspReportExportChoice.preview:
          break;
        case RspReportExportChoice.csv:
          await RspFinalInterviewReportExport.shareCsv(
            rows: rows,
            filterSummary: summary,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'CSV report downloaded (${rows.length} applicants).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case RspReportExportChoice.pdf:
          await RspFinalInterviewReportExport.sharePdf(
            rows: rows,
            filterSummary: summary,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF report downloaded (${rows.length} applicants).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case RspReportExportChoice.print:
          await RspFinalInterviewReportExport.printPdf(
            context: context,
            rows: rows,
            filterSummary: summary,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print dialog opened.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingReport = false);
    }
  }

  List<RecruitmentApplication> get _filteredPassedApplicants {
    return _passedApplicants.where((a) {
      final position = (a.positionAppliedFor ?? '').trim();
      if (_selectedPositionFilter != null &&
          _selectedPositionFilter!.isNotEmpty &&
          position != _selectedPositionFilter) {
        return false;
      }
      if (_selectedAppliedDate != null) {
        final createdAt = a.createdAt;
        if (createdAt == null ||
            !_isSameLocalDate(createdAt, _selectedAppliedDate!)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _formatDateShort(DateTime date) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = date.toLocal();
    return '${monthNames[d.month - 1]} ${d.day}, ${d.year}';
  }

  static bool _isRegistered(RecruitmentApplication a) {
    return a.status == 'registered' ||
        (a.hiredUserId != null && a.hiredUserId!.trim().isNotEmpty);
  }

  ({String label, IconData icon, Color fg, Color bg, Color border}) _statusSpec(
    BuildContext context,
    RecruitmentApplication app,
  ) {
    final dark = AppTheme.dashIsDark(context);
    final registered = _isRegistered(app);
    final scheduled = app.finalInterviewAt;
    final outcome = app.finalInterviewPassed;
    final hrDone = app.hrAccountSetupDone == true;

    if (registered) {
      return (
        label: 'Hired · Account linked',
        icon: Icons.verified_rounded,
        fg: dark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
        bg: dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9),
        border: (dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == true && hrDone) {
      return (
        label: 'Passed · Step 8 done',
        icon: Icons.task_alt_rounded,
        fg: dark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
        bg: dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9),
        border: (dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == true) {
      return (
        label: 'Passed · Final requirements',
        icon: Icons.hourglass_bottom_rounded,
        fg: dark ? const Color(0xFF90CAF9) : const Color(0xFF0D47A1),
        bg: dark ? const Color(0xFF1A2940) : const Color(0xFFE3F2FD),
        border: (dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == false) {
      return (
        label: 'Not passed',
        icon: Icons.cancel_rounded,
        fg: dark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C),
        bg: dark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE),
        border: (dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828))
            .withValues(alpha: 0.35),
      );
    }
    if (scheduled != null) {
      return (
        label: 'Scheduled',
        icon: Icons.event_available_rounded,
        fg: dark ? const Color(0xFFFFB74D) : const Color(0xFF7A3E00),
        bg: dark ? const Color(0xFF3A2E1A) : const Color(0xFFFFF3E0),
        border: (dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00))
            .withValues(alpha: 0.35),
      );
    }
    return (
      label: 'Not scheduled',
      icon: Icons.schedule_rounded,
      fg: dark
          ? const Color(0xFFB0BEC5)
          : AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.95),
      bg: dark ? const Color(0xFF2A3140) : const Color(0xFFF5F7FA),
      border: dark
          ? const Color(0xFF4A5568)
          : Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _statusBadge(RecruitmentApplication app) {
    final s = _statusSpec(context, app);
    return RspSchedulingUi.statusBadge(
      label: s.label,
      icon: s.icon,
      fg: s.fg,
      bg: s.bg,
      border: s.border,
    );
  }

  Future<void> _withSaveLock(
    String applicationId,
    Future<void> Function() fn,
  ) async {
    setState(() => _savingIds.add(applicationId));
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingIds.remove(applicationId));
    }
  }

  Future<void> _pickDateTime(RecruitmentApplication app) async {
    final now = DateTime.now();
    final initial =
        app.finalInterviewAt?.toLocal() ?? now.add(const Duration(days: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Deliberation date',
    );
    if (day == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Deliberation time',
    );
    if (time == null || !mounted) return;

    final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewAt(app.id, dt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deliberation schedule saved.')),
        );
      }
    });
  }

  Future<void> _clearSchedule(RecruitmentApplication app) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewAt(app.id, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deliberation schedule cleared.')),
        );
      }
    });
  }

  Future<void> _setOutcome(RecruitmentApplication app, bool? passed) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewPassed(app.id, passed);
      if (mounted) {
        final msg = passed == null
            ? 'Outcome cleared (pending).'
            : passed
            ? 'Marked as passed deliberation.'
            : 'Marked as did not pass deliberation.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
  }

  List<Widget> _outcomeActions(
    RecruitmentApplication app,
    bool? outcome,
    bool registered,
    bool busy,
  ) {
    final accent = RspSchedulingUi.accentOf(context);
    if (registered) return [];
    if (outcome == null) {
      return [
        FilledButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, true),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Mark passed'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, false),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Mark not passed'),
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ];
    }
    if (outcome == true) {
      return [
        TextButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, false),
          icon: Icon(Icons.swap_horiz_rounded, size: 18, color: accent),
          label: Text(
            'Change to not passed',
            style: TextStyle(color: accent, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, null),
          icon: Icon(
            Icons.restart_alt_rounded,
            size: 18,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          label: Text(
            'Clear',
            style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
          ),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: busy ? null : () => _setOutcome(app, true),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Mark passed instead'),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      TextButton.icon(
        onPressed: busy ? null : () => _setOutcome(app, null),
        icon: Icon(
          Icons.restart_alt_rounded,
          size: 18,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
        label: Text(
          'Clear',
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
      ),
    ];
  }

  Widget _toolbar(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final accent = RspSchedulingUi.accentOf(context);
    final filteredCount = _filteredPassedApplicants.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            height: RspSchedulingUi.controlHeight,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPositionFilter,
              isExpanded: true,
              decoration: RspSchedulingUi.filterDecoration(
                context,
                label: 'Position',
                prefixIcon: const Icon(Icons.work_outline_rounded, size: 18),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: null,
                  child: RspSchedulingUi.ddText('All positions'),
                ),
                ...(_positionFilterOptions.toList()..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    ))
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: RspSchedulingUi.ddText(p),
                      ),
                    ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() => _selectedPositionFilter = value);
                    },
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedAppliedDate ?? now,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 1),
                        helpText: 'Filter by applied date',
                      );
                      if (picked == null || !mounted) return;
                      setState(() => _selectedAppliedDate = picked);
                    },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                _selectedAppliedDate == null
                    ? 'Applied date'
                    : _formatDateShort(_selectedAppliedDate!),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: hairline),
                foregroundColor: AppTheme.dashTextPrimaryOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    RspSchedulingUi.inputRadius,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: TextButton.icon(
              onPressed: _loading
                  ? null
                  : () =>
                      setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
          ),
          RspSchedulingUi.sortDropdown(
            context: context,
            latestFirst: _latestFirst,
            enabled: !_loading,
            onChanged: (v) => setState(() => _latestFirst = v),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: TextButton.icon(
              onPressed: (_loading || !_hasActiveFilters)
                  ? null
                  : () {
                      setState(() {
                        _selectedPositionFilter = null;
                        _selectedAppliedDate = null;
                      });
                    },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    RspSchedulingUi.inputRadius,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: OutlinedButton.icon(
              onPressed: (_loading || _exportingReport)
                  ? null
                  : _showGenerateReportDialog,
              icon: _exportingReport
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.summarize_outlined, size: 18),
              label: Text(_exportingReport ? 'Generating…' : 'Generate report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    RspSchedulingUi.inputRadius,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$filteredCount shown',
              style: TextStyle(
                fontFamily: 'NotoSans',
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedCard(BuildContext context, RecruitmentApplication app) {
    final hairline = AppTheme.dashHairlineOf(context);
    final scheduled = app.finalInterviewAt;
    final position = (app.positionAppliedFor ?? '').trim();
    final applicantNo = (app.applicantNumber ?? '').trim();

    return Container(
      decoration: RspSchedulingUi.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expandedIds.add(app.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final infoColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.fullName,
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.1,
                        color: AppTheme.dashTextPrimaryOf(context),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        if (applicantNo.isNotEmpty)
                          Text(
                            applicantNo,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: RspSchedulingUi.accentOf(context),
                            ),
                          ),
                        Text(
                          app.email,
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 12,
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        position,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.dashTextSecondaryOf(
                            context,
                          ).withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                );

                final scheduleBlock = scheduled == null
                    ? null
                    : RspSchedulingUi.dateTimeBlock(context, scheduled);

                final trailing = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusBadge(app),
                    const SizedBox(width: 10),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.dashMutedSurfaceOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: hairline),
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                );

                if (compact) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RspSchedulingUi.initialsAvatar(context, app.fullName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            infoColumn,
                            if (scheduleBlock != null) ...[
                              const SizedBox(height: 8),
                              scheduleBlock,
                            ],
                            const SizedBox(height: 8),
                            trailing,
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RspSchedulingUi.initialsAvatar(context, app.fullName),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: infoColumn),
                    if (scheduleBlock != null)
                      Expanded(flex: 2, child: scheduleBlock)
                    else
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Not scheduled',
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dashTextSecondaryOf(
                              context,
                            ).withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    trailing,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _appointmentPanel(
    BuildContext context,
    RecruitmentApplication app,
    bool busy,
  ) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final accent = RspSchedulingUi.accentOf(context);
    final scheduled = app.finalInterviewAt;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                'Deliberation Appointment',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairline),
            ),
            child: scheduled == null
                ? Row(
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        size: 18,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No deliberation appointment scheduled.',
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.dashTextSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 10),
                      RspSchedulingUi.dateTimeBlock(context, scheduled),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => _pickDateTime(app),
                icon: const Icon(Icons.edit_calendar_rounded, size: 17),
                label: Text(
                  scheduled == null ? 'Set date & time' : 'Change date & time',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (scheduled != null)
                TextButton.icon(
                  onPressed: busy ? null : () => _clearSchedule(app),
                  icon: Icon(
                    Icons.event_busy_rounded,
                    size: 17,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                  label: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultPanel(
    BuildContext context,
    RecruitmentApplication app,
    bool? outcome,
    bool registered,
    bool busy,
  ) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final accent = RspSchedulingUi.accentOf(context);
    final actions = _outcomeActions(app, outcome, registered, busy);

    late Color fg;
    late IconData icon;
    late String headline;
    late String detail;
    switch (outcome) {
      case true:
        fg = AppTheme.dashIsDark(context)
            ? const Color(0xFF81C784)
            : const Color(0xFF1B5E20);
        icon = Icons.check_circle_outline_rounded;
        headline = 'Passed';
        detail = 'Proceeds to Final Requirements.';
      case false:
        fg = AppTheme.dashIsDark(context)
            ? const Color(0xFFEF9A9A)
            : const Color(0xFFB71C1C);
        icon = Icons.cancel_outlined;
        headline = 'Not passed';
        detail = 'No employee account is created from this hiring flow.';
      default:
        fg = AppTheme.dashTextSecondaryOf(context);
        icon = Icons.hourglass_empty_rounded;
        headline = 'Pending';
        detail = 'Record the result after the in-person interview.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                'Deliberation Result',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: fg,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.dashTextPrimaryOf(
                            context,
                          ).withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: actions),
          ],
        ],
      ),
    );
  }

  Widget _expandedCard(BuildContext context, RecruitmentApplication app) {
    final busy = _savingIds.contains(app.id);
    final exam = _examResults[app.id.toLowerCase()];
    final registered = _isRegistered(app);
    final outcome = app.finalInterviewPassed;
    final hairline = AppTheme.dashHairlineOf(context);
    final accent = RspSchedulingUi.accentOf(context);
    final position = (app.positionAppliedFor ?? '').trim();
    final applicantNo = (app.applicantNumber ?? '').trim();

    return Container(
      decoration: RspSchedulingUi.cardDecoration(context, highlighted: true),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RspSchedulingUi.initialsAvatar(context, app.fullName, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        app.fullName,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.2,
                          color: AppTheme.dashTextPrimaryOf(context),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (applicantNo.isNotEmpty)
                            Text(
                              applicantNo,
                              style: TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          Text(
                            app.email,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 12.5,
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (position.isNotEmpty)
                            Text(
                              position,
                              style: TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accent.withValues(alpha: 0.9),
                              ),
                            ),
                          if (exam != null)
                            Text(
                              'Exam: ${exam.scorePercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _statusBadge(app),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _expandedIds.remove(app.id)),
                  icon: const Icon(Icons.unfold_less_rounded, size: 18),
                  label: const Text('Collapse'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: hairline),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (RspSchedulingUi.isDesktopWidth(constraints.maxWidth)) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _appointmentPanel(context, app, busy),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _resultPanel(
                          context,
                          app,
                          outcome,
                          registered,
                          busy,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _appointmentPanel(context, app, busy),
                    const SizedBox(height: 12),
                    _resultPanel(context, app, outcome, registered, busy),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = RspSchedulingUi.accentOf(context);
    final filteredPassedApplicants = _filteredPassedApplicants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  size: 24,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deliberation Scheduling',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Applicants listed here already passed the screening exam.',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _toolbar(context),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_passedApplicants.isEmpty)
          RspSchedulingUi.emptyState(
            context,
            icon: Icons.people_outline_rounded,
            title: 'No applicants have passed the exam yet',
            message:
                'When an applicant completes the screening exam with a passing score, they will show up here automatically.',
          )
        else if (filteredPassedApplicants.isEmpty)
          RspSchedulingUi.emptyState(
            context,
            icon: Icons.filter_alt_off_rounded,
            title: 'No applicants found',
            message: 'Try adjusting your filters or refresh the list.',
            onClearFilters: _hasActiveFilters
                ? () => setState(() {
                    _selectedPositionFilter = null;
                    _selectedAppliedDate = null;
                  })
                : null,
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredPassedApplicants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final app = filteredPassedApplicants[i];
              final expanded = _expandedIds.contains(app.id);
              return expanded
                  ? _expandedCard(context, app)
                  : _collapsedCard(context, app);
            },
          ),
      ],
    );
  }
}
