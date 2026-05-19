import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/training_daily_report.dart';
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

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    final muted = Colors.black.withValues(alpha: 0.14);
    final focused = AppTheme.primaryNavy;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: AppTheme.sectionAlt.withValues(alpha: 0.35),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: muted, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: muted, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focused, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                Icons.edit_note_rounded,
                color: AppTheme.primaryNavy,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Training Reports',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Submit your daily training activities while you are on training.',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                      fontSize: 14.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: AppTheme.panelShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavyLight,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'New report',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Title is required. Add a short description and an optional JPG, PNG, or PDF.',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.92),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    RspSpacedOutlineField(
                      child: TextField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _inputDecoration(
                          label: 'Report title',
                          hint: 'e.g. Orientation on HRIS and records filing',
                          prefixIcon: const Icon(Icons.article_outlined),
                        ),
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextField(
                        controller: _descriptionController,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _inputDecoration(
                          label: 'Description',
                          hint:
                              'Tasks, tools, and what you learned today.',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: rspFormFieldVerticalGap),
                    Text(
                      'Attachment',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Material(
                      color: AppTheme.sectionAlt.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _pickFile,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.perm_media_outlined,
                                    size: 22,
                                    color: AppTheme.primaryNavy
                                        .withValues(alpha: 0.85),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Image or PDF',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: _pickFile,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('Browse'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'JPG, PNG, or PDF · optional · up to 10 MB',
                                style: TextStyle(
                                  color: AppTheme.textSecondary.withValues(
                                    alpha: 0.9,
                                  ),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                              if (_selectedFile != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file_rounded,
                                        size: 20,
                                        color: AppTheme.primaryNavy,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _selectedFile!.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
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
                                          color: AppTheme.textSecondary
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Tap this area or use Browse to attach proof.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.75,
                                    ),
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
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
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
                          label: Text(_submitting ? 'Submitting…' : 'Submit report'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryNavy,
                            foregroundColor: AppTheme.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'My previous reports',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.25,
              ),
            ),
            if (!_loading && _reports.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                '${_reports.length}',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Open any row to see the full entry you submitted.',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.88),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_reports.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.sectionAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.inbox_outlined,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No reports yet',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'When you submit your first daily report, it will show up here.',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.92),
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: _reports
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.07),
                          ),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.title,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
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
                                  color: AppTheme.textSecondary.withValues(
                                    alpha: 0.95,
                                  ),
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Submitted ${_formatSubmittedAt(r.submittedAt)}',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.88,
                                      ),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => showReadOnlySavedEntryDialog(
                                    context,
                                    title: 'Submitted report',
                                    previewBuilder: () =>
                                        TrainingDailyReportReadOnlyView(
                                          report: r,
                                        ),
                                    contentWidth: 560,
                                  ),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('View full entry'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primaryNavy,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
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
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        _displayLabel(raw),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

