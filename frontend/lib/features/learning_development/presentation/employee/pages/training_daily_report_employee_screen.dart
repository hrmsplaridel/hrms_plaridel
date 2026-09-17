import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/training_daily_report_read_only_view.dart';

class TrainingDailyReportEmployeeScreen extends StatefulWidget {
  const TrainingDailyReportEmployeeScreen({
    super.key,
    this.tutorialHeaderKey,
    this.tutorialFormKey,
    this.tutorialHistoryKey,
  });

  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialFormKey;
  final GlobalKey? tutorialHistoryKey;

  @override
  State<TrainingDailyReportEmployeeScreen> createState() =>
      _TrainingDailyReportEmployeeScreenState();
}

class _TrainingDailyReportEmployeeScreenState
    extends State<TrainingDailyReportEmployeeScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _titleFocusNode = FocusNode();

  bool _submitting = false;
  bool _loading = false;
  PlatformFile? _selectedFile;
  List<TrainingDailyReport> _reports = [];

  /// Calendar day (local) to filter by; `null` shows all reports.
  DateTime? _filterByDate;

  static const _months = [
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

  static DateTime _toLocalDate(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String _formatDateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _formatListDate(DateTime d) {
    final l = d.toLocal();
    return '${_months[l.month - 1]} ${l.day}, ${l.year}';
  }

  List<DateTime> get _datesWithReports {
    final days = <DateTime>{};
    for (final r in _reports) {
      days.add(_toLocalDate(r.submittedAt));
    }
    return days.toList()..sort((a, b) => b.compareTo(a));
  }

  List<TrainingDailyReport> get _visibleReports {
    var sorted = List<TrainingDailyReport>.from(_reports)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    if (_filterByDate != null) {
      final day = _filterByDate!;
      sorted = sorted
          .where((r) => _toLocalDate(r.submittedAt) == day)
          .toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      sorted = sorted.where((r) {
        final title = r.title.toLowerCase();
        final desc = (r.description ?? '').toLowerCase();
        return title.contains(q) || desc.contains(q);
      }).toList();
    }
    return sorted;
  }

  static String _formatSubmittedAt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
  }

  static String _fileSizeLabel(PlatformFile file) {
    final bytes = file.size;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _fileKindLabel(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : 'FILE';
    return ext;
  }

  static bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  BoxDecoration _cardDecoration(BuildContext context, {double radius = 18}) {
    final dark = _isDark(context);
    return BoxDecoration(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.18 : 0.04),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    String? hint,
    Widget? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 11,
    ).copyWith(
      filled: true,
      fillColor: _isDark(context)
          ? AppTheme.dashMutedSurfaceOf(context)
          : const Color(0xFFF7F8FA),
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
    );
  }

  void _clearSelectedFile() {
    setState(() => _selectedFile = null);
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    setState(() => _selectedFile = null);
  }

  void _focusCreateForm() {
    final ctx = widget.tutorialFormKey?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        alignment: 0.08,
      );
    }
    _titleFocusNode.requestFocus();
  }

  void _openReport(TrainingDailyReport r) {
    showReadOnlySavedEntryDialog(
      context,
      title: 'Submitted report',
      subtitle: r.title.trim().isNotEmpty
          ? r.title
          : r.submittedAt.toLocal().toString().split('.').first,
      previewBuilder: () => TrainingDailyReportReadOnlyView(report: r),
      contentWidth: 640,
    );
  }

  Widget _fieldLabel(
    BuildContext context,
    String text, {
    bool required = false,
    String? hint,
  }) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              text: text,
              style: TextStyle(
                color: primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(
              hint,
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
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
        attachmentMeta = await TrainingDailyReportRepo.instance
            .uploadAttachment(_selectedFile!);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily training report submitted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
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
    _searchController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  Widget _buildHero(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = _isDark(context);
    final compact = MediaQuery.sizeOf(context).width < 768;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 0 : 132),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        compact ? 16 : 22,
        compact ? 16 : 24,
        compact ? 16 : 22,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: dark
              ? [AppTheme.dashPanelOf(context), const Color(0xFF2A241E)]
              : const [Colors.white, Color(0xFFFFF6EE)],
        ),
        border: Border.all(
          color: dark
              ? AppTheme.dashHairlineOf(context)
              : AppTheme.primaryNavy.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 58,
            height: compact ? 48 : 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.assignment_outlined,
              color: AppTheme.primaryNavy,
              size: compact ? 26 : 30,
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'TRAINING REPORTS',
                  style: TextStyle(
                    color: AppTheme.primaryNavy,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily Training Reports',
                  style: TextStyle(
                    color: primary,
                    fontSize: compact ? 22 : 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Record and submit your daily training activities.',
                  style: TextStyle(
                    color: secondary,
                    fontSize: compact ? 13.5 : 15,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 72,
              color: AppTheme.dashHairlineOf(context),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 188,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 22,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Small progress\nbuilds great talent.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: primary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Keep learning. Keep growing.',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, {required bool compact}) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hasFile = _selectedFile != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        compact ? 16 : 22,
        compact ? 16 : 22,
        compact ? 16 : 20,
      ),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.note_add_outlined,
                  size: 20,
                  color: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Daily Report',
                      style: TextStyle(
                        color: primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Record what you accomplished during today's training.",
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _fieldLabel(context, 'Report Title', required: true),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            textCapitalization: TextCapitalization.sentences,
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration(
              context,
              hint: 'e.g. Database Configuration Training',
              prefixIcon: Icon(
                Icons.article_outlined,
                color: secondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel(context, 'Description'),
          TextField(
            controller: _descriptionController,
            minLines: 5,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration(
              context,
              hint:
                  'Briefly describe the activities, tasks, or lessons completed today...',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Icon(Icons.edit_outlined, color: secondary, size: 18),
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel(context, 'Attachment', hint: '(Optional)'),
          CustomPaint(
            painter: _DashedRRectPainter(
              color: hasFile
                  ? AppTheme.primaryNavy.withValues(alpha: 0.55)
                  : AppTheme.dashHairlineOf(context),
              radius: 12,
            ),
            child: Material(
              color: _isDark(context)
                  ? AppTheme.dashMutedSurfaceOf(context)
                  : const Color(0xFFFAFBFC),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _pickFile,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: compact ? 132 : 148,
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 28,
                        color: AppTheme.primaryNavy,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Drag and drop a file here or browse',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'JPG, PNG or PDF • Maximum 10 MB',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _pickFile,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                          side: BorderSide(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.45),
                          ),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Choose file'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasFile) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_rounded,
                    size: 20,
                    color: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        Text(
                          '${_fileKindLabel(_selectedFile!.name)} • ${_fileSizeLabel(_selectedFile!)}',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _clearSelectedFile,
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _submitButton(fullWidth: true),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _submitting ? null : _clearForm,
                  style: _clearButtonStyle(context, primary),
                  child: const Text('Clear'),
                ),
              ],
            )
          else
            Row(
              children: [
                OutlinedButton(
                  onPressed: _submitting ? null : _clearForm,
                  style: _clearButtonStyle(context, primary),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                SizedBox(width: 184, child: _submitButton(fullWidth: false)),
              ],
            ),
        ],
      ),
    );
  }

  ButtonStyle _clearButtonStyle(BuildContext context, Color primary) {
    return OutlinedButton.styleFrom(
      foregroundColor: primary,
      side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      minimumSize: const Size(88, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _submitButton({required bool fullWidth}) {
    return FilledButton.icon(
      onPressed: _submitting ? null : _submit,
      icon: _submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send_rounded, size: 18),
      label: Text(_submitting ? 'Submitting…' : 'Submit Report'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.45),
        minimumSize: Size(fullWidth ? double.infinity : 170, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _dateFilterButton(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final filtering = _filterByDate != null;
    final dateLabel = filtering
        ? _formatDateOnly(_filterByDate!)
        : 'Select date';
    return OutlinedButton.icon(
      onPressed: _pickFilterDate,
      icon: const Icon(Icons.calendar_today_rounded, size: 16),
      label: Text(dateLabel, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
        minimumSize: const Size(double.infinity, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }

  Widget _historyControls(BuildContext context, {required bool compact}) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final searchField = TextField(
      controller: _searchController,
      style: AppTheme.dashFieldTextStyle(context),
      decoration: _inputDecoration(
        context,
        hint: 'Search reports...',
        prefixIcon: Icon(Icons.search_rounded, color: secondary, size: 20),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: 10),
          _dateFilterButton(context),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 6, child: searchField),
        const SizedBox(width: 10),
        Expanded(flex: 4, child: _dateFilterButton(context)),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context, {required bool compact}) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final filtering = _filterByDate != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 16 : 20,
        compact ? 16 : 20,
        compact ? 16 : 18,
      ),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report History',
                      style: TextStyle(
                        color: primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Review your previously submitted daily training reports.',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_loading && _reports.isNotEmpty) ...[
            const SizedBox(height: 14),
            _historyControls(context, compact: compact),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () => _shiftFilterDay(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Next day',
                  onPressed: () => _shiftFilterDay(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (filtering)
                  TextButton(
                    onPressed: _clearDateFilter,
                    child: const Text('Show all'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildReportsList(context),
        ],
      ),
    );
  }

  Widget _buildReminderCard(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.primaryNavy.withValues(alpha: 0.12)
            : const Color(0xFFFFF6EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.28 : 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: AppTheme.primaryNavy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reminder',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Submit your daily training report regularly to keep track of your learning progress and activities.',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.5,
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

  Widget _emptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppTheme.primaryNavy.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  Widget _buildReportsList(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_reports.isEmpty) {
      return _emptyState(
        context: context,
        icon: Icons.description_outlined,
        title: 'No training reports yet',
        body:
            'When you submit your first daily report, it will show up here.',
        action: TextButton(
          onPressed: _focusCreateForm,
          child: const Text('Create your first report'),
        ),
      );
    }

    final visible = _visibleReports;
    if (visible.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return _emptyState(
        context: context,
        icon: Icons.search_off_rounded,
        title: searching ? 'No matching reports' : 'No reports on this date',
        body: searching
            ? 'Try a different search or clear the date filter.'
            : 'Try another date or show all reports.',
        action: TextButton(
          onPressed: () {
            _searchController.clear();
            _clearDateFilter();
          },
          child: const Text('Show all reports'),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          _ReportHistoryRow(
            report: visible[i],
            dateLabel: _formatListDate(visible[i].submittedAt),
            submittedAtLabel: _formatSubmittedAt(visible[i].submittedAt),
            onView: () => _openReport(visible[i]),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 768;

        final form = KeyedSubtree(
          key: widget.tutorialFormKey,
          child: _buildFormCard(context, compact: compact),
        );
        final history = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: widget.tutorialHistoryKey,
              child: _buildHistoryCard(context, compact: compact),
            ),
            const SizedBox(height: 12),
            _buildReminderCard(context),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: widget.tutorialHeaderKey,
              child: _buildHero(context),
            ),
            const SizedBox(height: 16),
            if (twoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 108, child: form),
                  const SizedBox(width: 18),
                  Expanded(flex: 92, child: history),
                ],
              )
            else ...[
              form,
              const SizedBox(height: 16),
              history,
            ],
          ],
        );
      },
    );
  }
}

class _ReportHistoryRow extends StatelessWidget {
  const _ReportHistoryRow({
    required this.report,
    required this.dateLabel,
    required this.submittedAtLabel,
    required this.onView,
  });

  final TrainingDailyReport report;
  final String dateLabel;
  final String submittedAtLabel;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final attachment = (report.attachmentName ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: submittedAtLabel,
                          child: Text(
                            dateLabel,
                            style: TextStyle(color: secondary, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: report.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.isEmpty ? 'No attachment' : attachment,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: onView,
                    child: const Text('View →'),
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
      case 'submitted':
        color = const Color(0xFF546E7A);
        break;
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _displayLabel(raw),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
