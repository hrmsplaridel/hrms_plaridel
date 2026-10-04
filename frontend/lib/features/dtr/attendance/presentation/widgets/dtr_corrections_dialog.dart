import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';

Future<void> _previewEvidence(
  BuildContext context,
  Uint8List bytes,
  String name,
) async {
  if (name.toLowerCase().endsWith('.pdf')) {
    await showFormPdfPreview(
      context: context,
      bytes: bytes,
      title: name,
      filename: name,
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(name),
                  ),
                ),
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Unable to preview this image.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showDtrCorrections(
  BuildContext context, {
  bool review = false,
  String? requestId,
}) => openResponsiveRightSidePanel<void>(
  context: context,
  builder: (_) => DtrCorrectionsDialog(review: review, requestId: requestId),
);

ThemeData _correctionPanelTheme(BuildContext context) {
  final theme = Theme.of(context);
  final background = AppTheme.dashPanelOf(context);
  final foreground = AppTheme.dashTextPrimaryOf(context);
  return theme.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: theme.colorScheme.copyWith(
      surface: background,
      onSurface: foreground,
    ),
    textTheme: theme.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTheme.dashMutedSurfaceOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    ),
  );
}

Future<bool?> showDtrCorrectionReview(BuildContext context, String requestId) =>
    openResponsiveRightSidePanel<bool>(
      context: context,
      builder: (panelContext) => Theme(
        data: _correctionPanelTheme(panelContext),
        child: _CorrectionReviewPanel(requestId: requestId),
      ),
    );

class _CorrectionReviewPanel extends StatefulWidget {
  const _CorrectionReviewPanel({required this.requestId});
  final String requestId;

  @override
  State<_CorrectionReviewPanel> createState() => _CorrectionReviewPanelState();
}

class _CorrectionReviewPanelState extends State<_CorrectionReviewPanel> {
  Map<String, dynamic>? _row;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _row = null;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections/${widget.requestId}',
      );
      if (mounted) {
        setState(() => _row = Map<String, dynamic>.from(response.data as Map));
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_row != null) {
      return _CorrectionDetails(
        row: _row!,
        review: true,
        backTooltip: 'Close request',
        onClose: () => Navigator.of(context).pop(false),
        onReviewed: () => Navigator.of(context).pop(true),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Close request',
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _punches = {
  'time_in': 'Shift In',
  'break_out': 'Break Out',
  'break_in': 'Break In',
  'time_out': 'Shift Out',
};
String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _stamp(dynamic value) {
  if (value == null) return '-';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return '-';
  final d = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
  return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class DtrCorrectionsDialog extends StatefulWidget {
  const DtrCorrectionsDialog({super.key, this.review = false, this.requestId});
  final String? requestId;
  final bool review;
  @override
  State<DtrCorrectionsDialog> createState() => _DtrCorrectionsDialogState();
}

class _DtrCorrectionsDialogState extends State<DtrCorrectionsDialog> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  final List<String?> _cursors = [];
  String? _nextCursor;
  String _statusFilter = 'All';
  bool _creating = false;
  Map<String, dynamic>? _selected;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 0, String? cursor}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.requestId != null) {
        final detail = await ApiClient.instance.dio.get(
          '/api/dtr-corrections/${widget.requestId}',
        );
        if (mounted) {
          setState(
            () => _selected = Map<String, dynamic>.from(detail.data as Map),
          );
        }
        return;
      }
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections',
        queryParameters: {
          'review': widget.review,
          'pagination': 'cursor',
          if (cursor != null) 'cursor': cursor,
          if (_statusFilter != 'All') 'status': _statusFilter.toLowerCase(),
        },
      );
      if (mounted) {
        setState(() {
          final data = response.data;
          _rows = (data is List ? data : data['entries'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          _nextCursor = data is Map ? data['next_cursor'] as String? : null;
          if (page == 0) _cursors.clear();
          final current =
              cursor ?? (data is Map ? data['first_cursor'] as String? : null);
          if (_cursors.length <= page) {
            _cursors.add(current);
          } else {
            _cursors[page] = current;
          }
          _page = page;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setStatusFilter(String status) {
    if (_statusFilter == status) return;
    setState(() {
      _statusFilter = status;
      _page = 0;
      _rows = [];
    });
    _load();
  }

  Future<void> _openRequest(Map<String, dynamic> row) async {
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections/${row['id']}',
      );
      if (mounted) {
        setState(
          () => _selected = Map<String, dynamic>.from(response.data as Map),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    }
  }

  Widget _statusMark(BuildContext context, dynamic raw) {
    final status = (raw ?? 'pending').toString().toLowerCase();
    final color = switch (status) {
      'approved' => Colors.green,
      'rejected' => Theme.of(context).colorScheme.error,
      _ => AppTheme.primaryNavyLight,
    };
    final icon = switch (status) {
      'approved' => Icons.check_circle_outline,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.schedule_outlined,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '${status[0].toUpperCase()}${status.substring(1)}',
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _requestRow(
    BuildContext context,
    Map<String, dynamic> row,
    bool compact,
  ) {
    final date = (row['attendance_date'] ?? '-').toString();
    final reason = (row['reason'] ?? '-').toString();
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return InkWell(
      onTap: () => _openRequest(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          date,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _statusMark(context, row['status']),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                  if (widget.review) ...[
                    const SizedBox(height: 5),
                    Text(
                      (row['employee_name'] ?? '-').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondary),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      date,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widget.review)
                    Expanded(
                      flex: 3,
                      child: Text(
                        (row['employee_name'] ?? '-').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _statusMark(context, row['status']),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Theme(
        data: _correctionPanelTheme(context),
        child: Builder(
          builder: (context) {
            if (_creating) {
              return _CorrectionForm(
                onClose: (saved) {
                  setState(() => _creating = false);
                  if (saved) {
                    _page = 0;
                    _load();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _messengerKey.currentState?.showSnackBar(
                        const SnackBar(
                          content: Text('DTR correction request submitted.'),
                        ),
                      );
                    });
                  }
                },
              );
            }
            if (_selected != null) {
              return _CorrectionDetails(
                row: _selected!,
                review: widget.review,
                backTooltip: widget.requestId == null
                    ? 'Back to corrections'
                    : 'Close request',
                onClose: () {
                  if (widget.requestId != null) {
                    Navigator.of(context).pop();
                    return;
                  }
                  setState(() => _selected = null);
                  _load();
                },
              );
            }
            return _buildList(context);
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final hairline = AppTheme.dashHairlineOf(context);
            final secondary = AppTheme.dashTextSecondaryOf(context);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.review
                              ? 'Review DTR Corrections'
                              : 'My DTR Corrections',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!widget.review) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Request correction'),
                        onPressed: _loading || _error != null
                            ? null
                            : () => setState(() => _creating = true),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final status in const [
                          'All',
                          'Pending',
                          'Approved',
                          'Rejected',
                        ]) ...[
                          ChoiceChip(
                            label: Text(status),
                            selected: _statusFilter == status,
                            onSelected: _loading
                                ? null
                                : (_) => _setStatusFilter(status),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Column(
                      children: [
                        if (!compact &&
                            !_loading &&
                            _error == null &&
                            _rows.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            color: AppTheme.dashMutedSurfaceOf(context),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Date',
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (widget.review)
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Employee',
                                      style: TextStyle(
                                        color: secondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    'Reason',
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Status',
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                              ],
                            ),
                          ),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _load,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                )
                              : _rows.isEmpty
                              ? Center(
                                  child: Text(
                                    _statusFilter == 'All'
                                        ? 'No correction requests'
                                        : 'No ${_statusFilter.toLowerCase()} correction requests',
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, _) =>
                                      Divider(height: 1, color: hairline),
                                  itemBuilder: (context, i) =>
                                      _requestRow(context, _rows[i], compact),
                                ),
                        ),
                      ],
                    ),
                  ),
                  if (_page > 0 || _nextCursor != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _loading || _page == 0
                              ? null
                              : () {
                                  _load(
                                    page: _page - 1,
                                    cursor: _cursors[_page - 1],
                                  );
                                },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page ${_page + 1}'),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: _loading || _nextCursor == null
                              ? null
                              : () {
                                  _load(page: _page + 1, cursor: _nextCursor);
                                },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CorrectionForm extends StatefulWidget {
  const _CorrectionForm({required this.onClose});
  final ValueChanged<bool> onClose;
  @override
  State<_CorrectionForm> createState() => _CorrectionFormState();
}

class _CorrectionFormState extends State<_CorrectionForm> {
  DateTime _day = DateTime.now().toUtc().add(const Duration(hours: 8));
  final _reason = TextEditingController();
  Map<String, dynamic>? _original;
  bool _loadingOriginal = true;
  String? _originalError;
  int _originalVersion = 0;
  @override
  void initState() {
    super.initState();
    _loadOriginal();
  }

  Future<void> _loadOriginal() async {
    final version = ++_originalVersion;
    setState(() {
      _loadingOriginal = true;
      _originalError = null;
      _original = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections/original/${_date(_day)}',
      );
      if (mounted && version == _originalVersion) {
        setState(
          () => _original = response.data == null
              ? null
              : Map<String, dynamic>.from(response.data as Map),
        );
      }
    } catch (e) {
      if (mounted && version == _originalVersion) {
        setState(() => _originalError = userFacingApiError(e));
      }
    } finally {
      if (mounted && version == _originalVersion) {
        setState(() => _loadingOriginal = false);
      }
    }
  }

  Widget _punchEditor(BuildContext context, String key, String label) {
    final raw = _original?[key];
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    final original = parsed == null
        ? null
        : (parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed);
    final originalText = _loadingOriginal
        ? 'Loading...'
        : _originalError != null
        ? 'Unavailable'
        : original == null
        ? (key == 'time_in' && _original?['status'] == 'absent'
              ? '[Absent]'
              : '--:--')
        : '${TimeOfDay.fromDateTime(original).format(context)}${_date(original).compareTo(_date(_day)) > 0 ? ' (+1 day)' : ''}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Divider(height: 16),
          Text('Original: $originalText', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          InkWell(
            onTap: _busy || _loadingOriginal || _originalError != null
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          _times[key] ??
                          (original == null
                              ? const TimeOfDay(hour: 8, minute: 0)
                              : TimeOfDay.fromDateTime(original)),
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        if (_original?['shift_crosses_midnight'] == true &&
                            !_times.containsKey(key) &&
                            original != null &&
                            _date(original).compareTo(_date(_day)) > 0) {
                          _nextDay.add(key);
                        }
                        _times[key] = picked;
                      });
                    }
                  },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'New time',
                isDense: true,
                suffixIcon: Icon(Icons.schedule, size: 18),
              ),
              child: Text(_times[key]?.format(context) ?? 'Unchanged'),
            ),
          ),
          if (_times.containsKey(key) &&
              _original?['shift_crosses_midnight'] == true)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Checkbox(
                  value: _nextDay.contains(key),
                  onChanged: _busy
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _nextDay.add(key);
                          } else {
                            _nextDay.remove(key);
                          }
                        }),
                ),
                const Text('+1 day', style: TextStyle(fontSize: 12)),
                IconButton(
                  tooltip: 'Clear requested time',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _times.remove(key);
                          _nextDay.remove(key);
                        }),
                  icon: const Icon(Icons.clear, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }

  PlatformFile? _attachment;
  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.bytes == null || file.size == 0 || file.size > 5 * 1024 * 1024) {
        setState(
          () => _error = 'Choose a PDF, JPG or PNG between 1 byte and 5 MB.',
        );
        return;
      }
      setState(() {
        _attachment = file;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    }
  }

  final Map<String, TimeOfDay> _times = {};
  final Set<String> _nextDay = {};
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 10 || _times.isEmpty) {
      setState(
        () => _error =
            'Choose at least one punch and enter a reason of at least 10 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'attendance_date': _date(_day),
        'reason': _reason.text.trim(),
      };
      for (final entry in _times.entries) {
        final day = DateTime.utc(_day.year, _day.month, _day.day).add(
          Duration(
            days:
                _original?['shift_crosses_midnight'] == true &&
                    _nextDay.contains(entry.key)
                ? 1
                : 0,
          ),
        );
        data['requested_${entry.key}'] =
            '${_date(day)}T${entry.value.hour.toString().padLeft(2, '0')}:${entry.value.minute.toString().padLeft(2, '0')}:00+08:00';
      }
      if (_attachment != null) {
        data['file'] = MultipartFile.fromBytes(
          _attachment!.bytes!,
          filename: _attachment!.name,
        );
      }
      await ApiClient.instance.dio.post(
        '/api/dtr-corrections',
        data: _attachment == null ? data : FormData.fromMap(data),
      );
      if (mounted) widget.onClose(true);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: _CorrectionSurface(
      title: 'Request DTR Correction',
      onBack: _busy ? null : () => widget.onClose(false),
      body: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().toUtc().add(
                            const Duration(hours: 8),
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _day = picked;
                            _times.clear();
                            _nextDay.clear();
                          });
                          await _loadOriginal();
                        }
                      },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Correction date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(_date(_day)),
                ),
              ),
              const SizedBox(height: 16),
              if (_originalError != null) ...[
                Text(
                  _originalError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton.icon(
                  onPressed: _loadOriginal,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry original attendance'),
                ),
              ],
              if (!_loadingOriginal &&
                  _originalError == null &&
                  _original?['shift_punch_mode'] == null) ...[
                const Text('No shift is assigned for this date.'),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 360 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 20
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  final labels =
                      _original?['shift_punch_mode'] == 'single_session'
                      ? {'time_in': 'Time In', 'time_out': 'Time Out'}
                      : {
                          'time_in': 'AM In',
                          'break_out': 'AM Out',
                          'break_in': 'PM In',
                          'time_out': 'PM Out',
                        };
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in labels.entries)
                        SizedBox(
                          width: width,
                          child: _punchEditor(context, entry.key, entry.value),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Reason / explanation',
                  hintText: 'Provide a detailed reason for this correction.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Supporting document (optional)'),
              const SizedBox(height: 8),
              if (_attachment == null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach PDF / JPG / PNG (max 5 MB)'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _attachment!.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Preview attachment',
                      onPressed: _busy
                          ? null
                          : () => _previewEvidence(
                              context,
                              _attachment!.bytes!,
                              _attachment!.name,
                            ),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove attachment',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _attachment = null),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => widget.onClose(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  _loadingOriginal ||
                  _originalError != null ||
                  _original?['shift_punch_mode'] == null
              ? null
              : _submit,
          child: Text(_busy ? 'Submitting...' : 'Submit request'),
        ),
      ],
    ),
  );
}

class _CorrectionDetails extends StatefulWidget {
  const _CorrectionDetails({
    required this.row,
    required this.review,
    required this.onClose,
    this.onReviewed,
    this.backTooltip = 'Back to corrections',
  });
  final VoidCallback onClose;
  final VoidCallback? onReviewed;
  final Map<String, dynamic> row;
  final bool review;
  final String backTooltip;
  @override
  State<_CorrectionDetails> createState() => _CorrectionDetailsState();
}

class _CorrectionDetailsState extends State<_CorrectionDetails> {
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _openingAttachment = false;
  Future<void> _openAttachment() async {
    setState(() => _openingAttachment = true);
    try {
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/api/dtr-corrections/${widget.row['id']}/attachment',
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted) {
        await _previewEvidence(
          context,
          Uint8List.fromList(response.data!),
          widget.row['attachment_name'].toString(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _review(String decision) async {
    if (_notes.text.trim().length < 10) {
      setState(() => _error = 'Enter review notes of at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post(
        '/api/dtr-corrections/${widget.row['id']}/review',
        data: {'decision': decision, 'notes': _notes.text.trim()},
      );
      if (mounted) (widget.onReviewed ?? widget.onClose)();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Widget _punchValue(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      );

  Widget _punchComparison(BuildContext context, Map? original, Map? applied) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final values = [
          for (final field in _punches.entries)
            (
              field.value,
              _stamp(original?[field.key]),
              widget.row['requested_${field.key}'] == null
                  ? 'Unchanged'
                  : _stamp(widget.row['requested_${field.key}']),
              applied == null ? null : _stamp(applied[field.key]),
            ),
        ];
        if (wide) {
          Widget cell(String text, {int flex = 2, bool heading = false}) =>
              Expanded(
                flex: flex,
                child: Text(
                  text,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: heading ? 12 : 14,
                    fontWeight: heading ? FontWeight.w700 : FontWeight.w500,
                    color: heading ? secondary : null,
                  ),
                ),
              );
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                color: AppTheme.dashMutedSurfaceOf(context),
                child: Row(
                  children: [
                    cell('Punch', flex: 1, heading: true),
                    cell('Original', heading: true),
                    cell('Requested', heading: true),
                    if (applied != null) cell('Applied', heading: true),
                  ],
                ),
              ),
              for (final value in values) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      cell(value.$1, flex: 1),
                      cell(value.$2),
                      cell(value.$3),
                      if (value.$4 != null) cell(value.$4!),
                    ],
                  ),
                ),
                Divider(height: 1, color: hairline),
              ],
            ],
          );
        }
        final cellWidth = constraints.maxWidth >= 500
            ? (constraints.maxWidth - 24) / 3
            : (constraints.maxWidth - 12) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final value in values) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.$1,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: cellWidth,
                          child: _punchValue(context, 'Original', value.$2),
                        ),
                        SizedBox(
                          width: cellWidth,
                          child: _punchValue(context, 'Requested', value.$3),
                        ),
                        if (value.$4 != null)
                          SizedBox(
                            width: cellWidth,
                            child: _punchValue(context, 'Applied', value.$4!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: hairline),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final original = row['original_record'] as Map?;
    final applied = row['applied_record'] as Map?;
    final canReview = widget.review && row['status'] == 'pending';
    final status = (row['status'] ?? 'pending').toString().toLowerCase();
    final statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Theme.of(context).colorScheme.error,
      _ => AppTheme.primaryNavyLight,
    };
    final statusIcon = switch (status) {
      'approved' => Icons.check_circle_outline,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.schedule_outlined,
    };
    return PopScope(
      canPop: !_busy,
      child: _CorrectionSurface(
        title: '${row['employee_name']} - ${row['attendance_date']}',
        backTooltip: widget.backTooltip,
        onBack: _busy ? null : widget.onClose,
        body: ListView(
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  '${status[0].toUpperCase()}${status.substring(1)}',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (row['created_at'] != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      _stamp(row['created_at']),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Reason'),
            const SizedBox(height: 8),
            Text((row['reason'] ?? '-').toString()),
            const SizedBox(height: 14),
            if (row['attachment_name'] != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: _openingAttachment ? null : _openAttachment,
                leading: const Icon(Icons.attach_file),
                title: Text(
                  row['attachment_name'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
              )
            else
              Text(
                'No supporting document',
                style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
              ),
            const SizedBox(height: 20),
            Divider(color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Punch comparison'),
            const SizedBox(height: 12),
            _punchComparison(context, original, applied),
            if (row['reviewed_at'] != null || canReview) ...[
              const SizedBox(height: 24),
              _sectionTitle(context, 'Review decision'),
              const SizedBox(height: 12),
            ],
            if (row['reviewed_at'] != null) ...[
              Text(
                '${row['reviewer_name'] ?? '-'}  |  ${_stamp(row['reviewed_at'])}',
                style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
              ),
              if ((row['review_notes'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(row['review_notes'].toString()),
              ],
            ],
            if (canReview)
              TextField(
                controller: _notes,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Review notes',
                  border: OutlineInputBorder(),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onClose,
            child: const Text('Close'),
          ),
          if (canReview) ...[
            TextButton(
              onPressed: _busy ? null : () => _review('rejected'),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _review('approved'),
              child: Text(_busy ? 'Saving...' : 'Approve correction'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CorrectionSurface extends StatelessWidget {
  const _CorrectionSurface({
    required this.title,
    required this.body,
    required this.actions,
    required this.onBack,
    this.backTooltip = 'Back to corrections',
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final String backTooltip;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  tooltip: backTooltip,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(20), child: body),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}
