import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/training_daily_report.dart';
import '../employee/widgets/employee_dash_ui.dart';
import '../landingpage/constants/app_theme.dart';
import '../widgets/read_only_saved_entry_dialog.dart';
import '../widgets/rsp_form_header_footer.dart';
import '../widgets/training_daily_report_read_only_view.dart';

class TrainingDailyReportEmployeeScreen extends StatefulWidget {
  const TrainingDailyReportEmployeeScreen({super.key});

  @override
  State<TrainingDailyReportEmployeeScreen> createState() =>
      _TrainingDailyReportEmployeeScreenState();
}

class _TrainingDailyReportEmployeeScreenState
    extends State<TrainingDailyReportEmployeeScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _submitting = false;
  bool _loading = false;
  PlatformFile? _selectedFile;
  List<TrainingDailyReport> _reports = [];
  /// Calendar day (local) to filter by; `null` shows all reports.
  DateTime? _filterByDate;

  static DateTime _toLocalDate(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String _formatDateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  List<DateTime> get _datesWithReports {
    final days = <DateTime>{};
    for (final r in _reports) {
      days.add(_toLocalDate(r.submittedAt));
    }
    return days.toList()..sort((a, b) => b.compareTo(a));
  }

  List<TrainingDailyReport> get _visibleReports {
    final sorted = List<TrainingDailyReport>.from(_reports)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    if (_filterByDate == null) return sorted;
    final day = _filterByDate!;
    return sorted
        .where((r) => _toLocalDate(r.submittedAt) == day)
        .toList();
  }

  static String _formatSubmittedAt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
  }

  static bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  static Color _accent(BuildContext context) =>
      _isDark(context) ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;

  static Color _accentSurface(BuildContext context) =>
      AppTheme.primaryNavy.withValues(alpha: _isDark(context) ? 0.22 : 0.12);

  InputDecoration _inputDecoration(
    BuildContext context, {
    String? label,
    String? hint,
    Widget? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      labelText: label?.trim().isNotEmpty == true ? label : null,
      hintText: hint,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      radius: 14,
    ).copyWith(
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: label?.trim().isNotEmpty == true
          ? FloatingLabelBehavior.auto
          : FloatingLabelBehavior.never,
    );
  }

  void _clearSelectedFile() {
    setState(() => _selectedFile = null);
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final list = await TrainingDailyReportRepo.instance.listMyReports();
      if (mounted) {
        setState(() {
          _reports = list;
          _loading = false;
          if (list.isNotEmpty && _filterByDate == null) {
            final newest = list.reduce(
              (a, b) => a.submittedAt.isAfter(b.submittedAt) ? a : b,
            );
            _filterByDate = _toLocalDate(newest.submittedAt);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickFilterDate() async {
    if (!mounted) return;
    final now = DateTime.now();
    final today = _toLocalDate(now);
    final dates = _datesWithReports;
    // Allow browsing any day in range — not only days that already have reports.
    // (Using oldest report as firstDate locked the calendar to one day when only
    // one report existed.)
    final oneYearAgo = DateTime(today.year - 1, today.month, today.day);
    final DateTime firstDate;
    if (dates.isEmpty) {
      firstDate = oneYearAgo;
    } else {
      final oldestReportDay = dates.last;
      firstDate = oldestReportDay.isBefore(oneYearAgo)
          ? oldestReportDay
          : oneYearAgo;
    }
    var initial = _filterByDate ?? dates.firstOrNull ?? today;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(today)) initial = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: 'Browse reports by date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );
    if (picked != null && mounted) {
      setState(() => _filterByDate = _toLocalDate(picked));
    }
  }

  void _shiftFilterDay(int delta) {
    final base = _filterByDate ?? _toLocalDate(DateTime.now());
    setState(() => _filterByDate = base.add(Duration(days: delta)));
  }

  void _clearDateFilter() {
    if (_filterByDate == null) return;
    setState(() => _filterByDate = null);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.single);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a report title')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      Map<String, dynamic>? attachmentMeta;
      if (_selectedFile != null) {
        attachmentMeta =
            await TrainingDailyReportRepo.instance.uploadAttachment(_selectedFile!);
      }

      await TrainingDailyReportRepo.instance.submitReport(
        title: title,
        description: description.isEmpty ? null : description,
        attachmentMeta: attachmentMeta,
      );

      if (!mounted) return;
      _titleController.clear();
      _descriptionController.clear();
      setState(() {
        _selectedFile = null;
        _filterByDate = _toLocalDate(DateTime.now());
      });
      await _loadReports();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily training report submitted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Widget _buildPageHeader(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(isNarrow ? 20 : 24),
      decoration: EmployeeDashUi.welcomeBanner(context),
      child: EmployeeSectionHeader(
        title: 'Daily Training Reports',
        icon: Icons.edit_note_rounded,
        subtitle:
            'Submit your daily training activities while you are on training.',
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hasFile = _selectedFile != null;
    final dark = _isDark(context);
    final accent = _accent(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: EmployeeDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        AppTheme.primaryNavy.withValues(alpha: 0.18),
                        AppTheme.dashMutedSurfaceOf(context),
                      ]
                    : [
                        AppTheme.primaryNavy.withValues(alpha: 0.06),
                        AppTheme.dashMutedSurfaceOf(context),
                      ],
              ),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accentSurface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.post_add_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New report',
                        style: TextStyle(
                          color: primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Title is required. Add a short description and an optional JPG, PNG, or PDF.',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RspSpacedOutlineField(
                  child: TextField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: _inputDecoration(
                      context,
                      hint: 'Report title',
                      prefixIcon: Icon(
                        Icons.article_outlined,
                        color: accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
                RspSpacedOutlineField(
                  child: TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: _inputDecoration(
                      context,
                      hint: 'Description',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: rspFormFieldVerticalGap),
                Text(
                  'ATTACHMENT',
                  style: EmployeeDashUi.metricLabel(context),
                ),
                const SizedBox(height: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickFile,
                    borderRadius: BorderRadius.circular(EmployeeDashUi.radiusMd),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(EmployeeDashUi.radiusMd),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [
                                  AppTheme.primaryNavy.withValues(alpha: 0.16),
                                  AppTheme.dashPanelOf(context),
                                ]
                              : [
                                  AppTheme.primaryNavy.withValues(alpha: 0.07),
                                  AppTheme.primaryNavyLight
                                      .withValues(alpha: 0.04),
                                ],
                        ),
                        border: Border.all(
                          color: hasFile
                              ? accent.withValues(alpha: 0.55)
                              : accent.withValues(alpha: dark ? 0.35 : 0.22),
                          width: hasFile ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stackBrowse =
                                    constraints.maxWidth < 480;
                                final uploadRow = Row(
                                  crossAxisAlignment: stackBrowse
                                      ? CrossAxisAlignment.start
                                      : CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _accentSurface(context),
                                      ),
                                      child: Icon(
                                        hasFile
                                            ? Icons
                                                .check_circle_outline_rounded
                                            : Icons.cloud_upload_outlined,
                                        size: 26,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            hasFile
                                                ? 'File attached'
                                                : 'Image or PDF',
                                            style: TextStyle(
                                              color: primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'JPG, PNG, or PDF · optional · up to 10 MB',
                                            style: TextStyle(
                                              color: secondary,
                                              fontSize: 12.5,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!stackBrowse)
                                      FilledButton(
                                        onPressed: _pickFile,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppTheme.primaryNavy,
                                          foregroundColor: Colors.white,
                                          padding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 10,
                                          ),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                        ),
                                        child: const Text('Browse'),
                                      ),
                                  ],
                                );
                                if (!stackBrowse) return uploadRow;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    uploadRow,
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton(
                                        onPressed: _pickFile,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.primaryNavy,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                            vertical: 10,
                                          ),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                        ),
                                        child: const Text('Browse'),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (hasFile) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.dashPanelOf(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.dashHairlineOf(context),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file_rounded,
                                      size: 22,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedFile!.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: primary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove file',
                                      onPressed: _clearSelectedFile,
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              Text(
                                'Tap this area or use Browse to attach proof.',
                                style: TextStyle(
                                  color: secondary.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? [
                                AppTheme.primaryNavyLight,
                                AppTheme.primaryNavy,
                                AppTheme.primaryNavyDark,
                              ]
                            : const [
                                Color(0xFFF0671A),
                                AppTheme.primaryNavy,
                                AppTheme.primaryNavyDark,
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryNavy.withValues(
                            alpha: dark ? 0.45 : 0.35,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        _submitting ? 'Submitting…' : 'Submit report',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const Color _datePillAccent = Color(0xFFF0671A);

  /// Tappable date pill — opens the calendar to browse by day.
  Widget _buildSelectableDatePill(BuildContext context) {
    final filtering = _filterByDate != null;
    final label = filtering
        ? _formatDateOnly(_filterByDate!)
        : 'Tap to select date';

    return Semantics(
      button: true,
      label: 'Selected date $label. Double tap to open calendar.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickFilterDate,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                color: AppTheme.dashPanelOf(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _datePillAccent.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: _datePillAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: _datePillAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 22,
                    color: _datePillAccent.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilterBar(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dates = _datesWithReports;
    final filtering = _filterByDate != null;
    final accent = _accent(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: EmployeeDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Browse by date',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (filtering)
                TextButton(
                  onPressed: _clearDateFilter,
                  style: EmployeeDashUi.ghostAction(context),
                  child: const Text('Show all'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the date to open the calendar, or use the arrows to move day by day.',
            style: TextStyle(
              color: secondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shiftFilterDay(-1),
                icon: Icon(Icons.chevron_left_rounded, color: accent),
                style: IconButton.styleFrom(
                  backgroundColor: _accentSurface(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: _buildSelectableDatePill(context),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Next day',
                onPressed: () {
                  final next = (_filterByDate ?? _toLocalDate(DateTime.now()))
                      .add(const Duration(days: 1));
                  if (next.isAfter(_toLocalDate(DateTime.now()))) return;
                  setState(() => _filterByDate = next);
                },
                icon: Icon(Icons.chevron_right_rounded, color: accent),
                style: IconButton.styleFrom(
                  backgroundColor: _accentSurface(context),
                ),
              ),
            ],
          ),
          if (dates.length > 1) ...[
            const SizedBox(height: 14),
            Text(
              'Days with reports',
              style: EmployeeDashUi.metricLabel(context),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: dates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = dates[index];
                  final selected =
                      filtering && _filterByDate == day;
                  final count = _reports
                      .where((r) => _toLocalDate(r.submittedAt) == day)
                      .length;
                  return InputChip(
                    label: Text(
                      '${_formatDateOnly(day)} ($count)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? _datePillAccent : primary,
                      ),
                    ),
                    avatar: Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: selected ? _datePillAccent : accent,
                    ),
                    onPressed: () => setState(() => _filterByDate = day),
                    backgroundColor: selected
                        ? _datePillAccent.withValues(alpha: 0.12)
                        : AppTheme.dashMutedSurfaceOf(context),
                    side: BorderSide(
                      color: selected
                          ? _datePillAccent.withValues(alpha: 0.55)
                          : AppTheme.dashHairlineOf(context),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportsList(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: EmployeeDashUi.elevatedPanel(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final accent = _accent(context);

    if (_reports.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        decoration: EmployeeDashUi.elevatedPanel(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentSurface(context),
              ),
              child: Icon(
                Icons.inbox_outlined,
                color: accent,
                size: 28,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No reports yet',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'When you submit your first daily report, it will show up here.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final visible = _visibleReports;
    if (visible.isEmpty) {
      final dayLabel = _filterByDate != null
          ? _formatDateOnly(_filterByDate!)
          : '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        decoration: EmployeeDashUi.elevatedPanel(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentSurface(context),
              ),
              child: Icon(
                Icons.event_busy_rounded,
                color: accent,
                size: 28,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No reports on $dayLabel',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try another date using the calendar, arrows, or the day chips above.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _clearDateFilter,
                    child: const Text('Show all reports'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: visible
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showReadOnlySavedEntryDialog(
                    context,
                    title: 'Submitted report',
                    subtitle: r.title.trim().isNotEmpty
                        ? r.title
                        : r.submittedAt.toLocal().toString().split('.').first,
                    previewBuilder: () =>
                        TrainingDailyReportReadOnlyView(report: r),
                    contentWidth: 640,
                  ),
                  borderRadius:
                      BorderRadius.circular(EmployeeDashUi.radiusMd),
                  child: Ink(
                    decoration: EmployeeDashUi.summaryCard(
                      context: context,
                      tint: _isDark(context)
                          ? AppTheme.dashPanelOf(context)
                          : const Color(0xFFFFF8F3),
                      accent: AppTheme.primaryNavy,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  r.title,
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _StatusChip(status: r.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (r.description != null &&
                                    r.description!.trim().isNotEmpty)
                                ? r.description!.trim()
                                : 'No description provided.',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 16,
                                color: secondary.withValues(alpha: 0.75),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Submitted ${_formatSubmittedAt(r.submittedAt)}',
                                  style: TextStyle(
                                    color: secondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => showReadOnlySavedEntryDialog(
                                  context,
                                  title: 'Submitted report',
                                  subtitle: r.title.trim().isNotEmpty
                                      ? r.title
                                      : r.submittedAt.toLocal().toString().split('.').first,
                                  previewBuilder: () =>
                                      TrainingDailyReportReadOnlyView(
                                        report: r,
                                      ),
                                  contentWidth: 640,
                                ),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                ),
                                label: const Text('View'),
                                style: EmployeeDashUi.ghostAction(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleCount = _visibleReports.length;
    final totalCount = _reports.length;
    String countLabel = '';
    if (!_loading && totalCount > 0) {
      if (_filterByDate != null) {
        countLabel = ' ($visibleCount of $totalCount)';
      } else {
        countLabel = ' ($totalCount)';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPageHeader(context),
        const SizedBox(height: 22),
        _buildFormCard(context),
        const SizedBox(height: 28),
        EmployeeSectionHeader(
          title: 'My previous reports$countLabel',
          icon: Icons.history_rounded,
          subtitle: _filterByDate != null
              ? 'Showing reports submitted on ${_formatDateOnly(_filterByDate!)}.'
              : 'Pick a date below or open any row to see the full entry you submitted.',
        ),
        if (!_loading && _reports.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildDateFilterBar(context),
        ],
        const SizedBox(height: 14),
        _buildReportsList(context),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  static String _displayLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '—';
    return t[0].toUpperCase() + t.substring(1).replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final raw = status.trim();
    Color color;
    switch (raw.toLowerCase()) {
      case 'seen':
        color = Colors.blueGrey;
        break;
      case 'reviewed':
        color = Colors.indigo;
        break;
      case 'approved':
        color = Colors.green;
        break;
      case 'needs_revision':
      case 'needs-revision':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        _displayLabel(raw),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

