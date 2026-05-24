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

  static String _formatSubmittedAt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    Widget? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      radius: 14,
    ).copyWith(
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
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
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
      setState(() => _selectedFile = null);
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
                colors: [
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
                    color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.post_add_rounded,
                    color: AppTheme.primaryNavy,
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
                      label: 'Report title',
                      hint: 'e.g. Orientation on HRIS and records filing',
                      prefixIcon: Icon(
                        Icons.article_outlined,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.85),
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
                      label: 'Description',
                      hint: 'Tasks, tools, and what you learned today.',
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
                          colors: [
                            AppTheme.primaryNavy.withValues(alpha: 0.07),
                            AppTheme.primaryNavyLight.withValues(alpha: 0.04),
                          ],
                        ),
                        border: Border.all(
                          color: hasFile
                              ? AppTheme.primaryNavy.withValues(alpha: 0.45)
                              : AppTheme.primaryNavy.withValues(alpha: 0.22),
                          width: hasFile ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.primaryNavy
                                        .withValues(alpha: 0.12),
                                  ),
                                  child: Icon(
                                    hasFile
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.cloud_upload_outlined,
                                    size: 26,
                                    color: AppTheme.primaryNavy,
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
                                FilledButton(
                                  onPressed: _pickFile,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primaryNavy,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 10,
                                    ),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text('Browse'),
                                ),
                              ],
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
                                    const Icon(
                                      Icons.insert_drive_file_rounded,
                                      size: 22,
                                      color: AppTheme.primaryNavy,
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
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF0671A),
                          AppTheme.primaryNavy,
                          AppTheme.primaryNavyDark,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.35),
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
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.inbox_outlined,
                color: AppTheme.primaryNavy.withValues(alpha: 0.7),
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

    return Column(
      children: _reports
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
                      tint: const Color(0xFFFFF8F3),
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
    final countLabel =
        !_loading && _reports.isNotEmpty ? ' (${_reports.length})' : '';

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
          subtitle: 'Open any row to see the full entry you submitted.',
        ),
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

