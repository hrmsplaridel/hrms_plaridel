import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/configured_leave_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';

class LeavePrintDraft {
  const LeavePrintDraft({this.layout = 'csc', this.file});
  final String layout;
  final PlatformFile? file;
  bool get hasChanges => layout != 'csc' || file != null;

  Future<void> save(String leaveTypeId, {bool removeBackground = false}) async {
    await ApiClient.instance.post(
      '/api/leave/print/types/$leaveTypeId',
      data: FormData.fromMap({
        'layout': layout,
        'remove_background': removeBackground.toString(),
        if (file != null)
          'file': MultipartFile.fromBytes(
            file!.bytes!,
            filename: file!.name,
            contentType: DioMediaType.parse(
              file!.extension?.toLowerCase() == 'pdf'
                  ? 'application/pdf'
                  : file!.extension?.toLowerCase() == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
            ),
          ),
      }),
    );
  }
}

class LeavePrintSettings extends StatefulWidget {
  const LeavePrintSettings({
    super.key,
    this.leaveTypeId,
    this.onChanged,
    this.onSaved,
    this.initialDraft,
    this.enabled = true,
  });
  final String? leaveTypeId;
  final ValueChanged<LeavePrintDraft>? onChanged;
  final VoidCallback? onSaved;
  final LeavePrintDraft? initialDraft;
  final bool enabled;
  @override
  State<LeavePrintSettings> createState() => _LeavePrintSettingsState();
}

class _LeavePrintSettingsState extends State<LeavePrintSettings> {
  String _layout = 'csc', _savedLayout = 'csc';
  String? _background, _error;
  PlatformFile? _file;
  bool _loading = true, _busy = false, _remove = false;
  LeavePrintDraft? _restoreDraft;
  bool get _disabled => _busy || !widget.enabled;
  void _changed() =>
      widget.onChanged?.call(LeavePrintDraft(layout: _layout, file: _file));
  @override
  void initState() {
    super.initState();
    _restoreDraft = widget.initialDraft;
    _layout = _restoreDraft?.layout ?? 'csc';
    _file = _restoreDraft?.file;
    if (widget.leaveTypeId != null) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/print/types/${widget.leaveTypeId}',
      );
      if (!mounted) return;
      setState(() {
        _savedLayout = r.data!['layout'].toString();
        _layout = _restoreDraft?.layout ?? _savedLayout;
        if (_restoreDraft != null) _file = _restoreDraft!.file;
        _restoreDraft = null;
        _background = r.data!['background_name']?.toString();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load print settings. Please retry.';
        });
      }
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (!mounted || r == null) return;
    if (r.files.single.size > 5242880) {
      setState(() => _error = 'Use a file up to 5 MB.');
      return;
    }
    if (r.files.single.bytes == null) {
      setState(
        () => _error =
            'Could not read the selected file. Please select it again.',
      );
      return;
    }
    setState(() {
      _file = r.files.single;
      _remove = false;
      _error = null;
    });
    _changed();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LeavePrintDraft(
        layout: _layout,
        file: _file,
      ).save(widget.leaveTypeId!, removeBackground: _remove);
      if (!mounted) return;
      setState(() {
        _file = null;
        _remove = false;
        _restoreDraft = null;
      });
      widget.onSaved?.call();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print settings saved. Existing submitted forms retain their template.',
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              (e.response?.data is Map ? e.response?.data['error'] : null)
                  ?.toString() ??
              'Could not save print settings.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save print settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final request = LeaveRequest(
        userId: 'sample',
        employeeName: 'Sample Employee',
        officeDepartment: 'Human Resources',
        leaveType: LeaveType.others,
        dateFiled: DateTime(2026, 10, 10),
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        workingDaysApplied: 1,
        reason: 'Personal wellness and rest.',
      );
      final doc = _savedLayout == 'wellness'
          ? await buildWellnessLeavePdf(
              request: request,
              department: 'Human Resources',
              departmentReviewer: 'Sample Department Head',
              mayorName: 'Sample Municipal Mayor',
            )
          : await LeaveRequestPdf.buildPdf(request: request);
      final r = await ApiClient.instance.post<List<int>>(
        '/api/leave/print/types/${widget.leaveTypeId}/preview',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            await doc.save(),
            filename: 'preview.pdf',
          ),
        }),
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted) {
        await showFormPdfPreview(
          context: context,
          bytes: Uint8List.fromList(r.data!),
          title: 'Printed Form Preview',
          filename: 'Leave_Form_Sample.pdf',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not preview the saved form.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Printed Form',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        DropdownButtonFormField<String>(
          key: ValueKey(_savedLayout),
          initialValue: _layout,
          decoration: const InputDecoration(labelText: 'Form layout'),
          items: const [
            DropdownMenuItem(value: 'csc', child: Text('Standard CSC form')),
            DropdownMenuItem(
              value: 'wellness',
              child: Text('Wellness Leave form'),
            ),
          ],
          onChanged: _disabled
              ? null
              : (v) {
                  setState(() => _layout = v!);
                  _changed();
                },
        ),
        const SizedBox(height: 10),
        Text(
          _remove
              ? 'Background will be removed'
              : _file?.name ?? _background ?? 'No background uploaded',
        ),
        const Text(
          'Portrait A4 letterhead only · PDF, PNG or JPEG · up to 5 MB',
        ),
        const Text(
          'Wellness layout applies to JO/COS employees. Other employment types use the default CSC form. The Mayor’s name is printed with a blank signature area for manual signing.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _disabled ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload background'),
            ),
            if (_background != null || _file != null)
              TextButton(
                onPressed: _disabled
                    ? null
                    : () {
                        setState(() {
                          _remove = widget.leaveTypeId != null;
                          _file = null;
                        });
                        _changed();
                      },
                child: const Text('Remove background'),
              ),
            if (widget.leaveTypeId != null)
              FilledButton(
                onPressed: _disabled ? null : _save,
                child: const Text('Save print settings'),
              ),
            if (widget.leaveTypeId != null)
              TextButton(
                onPressed: _disabled ? null : _preview,
                child: const Text('Preview saved form'),
              ),
            if (_error != null && widget.leaveTypeId != null)
              TextButton(
                onPressed: _disabled ? null : _load,
                child: const Text('Retry'),
              ),
          ],
        ),
        if (widget.leaveTypeId == null)
          const Text(
            'The selected layout and background will be saved when you create the leave type.',
          ),
      ],
    );
  }
}
