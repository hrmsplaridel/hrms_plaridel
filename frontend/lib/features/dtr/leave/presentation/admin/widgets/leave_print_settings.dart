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

class LeavePrintSettings extends StatefulWidget {
  const LeavePrintSettings({super.key, required this.leaveTypeId});
  final String leaveTypeId;
  @override
  State<LeavePrintSettings> createState() => _LeavePrintSettingsState();
}

class _LeavePrintSettingsState extends State<LeavePrintSettings> {
  String _layout = 'csc', _savedLayout = 'csc';
  String? _background, _error;
  PlatformFile? _file;
  bool _loading = true, _busy = false, _remove = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/print/types/${widget.leaveTypeId}',
      );
      if (!mounted) return;
      setState(() {
        _layout = _savedLayout = r.data!['layout'].toString();
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
    setState(() {
      _file = r.files.single;
      _remove = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post(
        '/api/leave/print/types/${widget.leaveTypeId}',
        data: FormData.fromMap({
          'layout': _layout,
          'remove_background': _remove.toString(),
          if (_file != null)
            'file': MultipartFile.fromBytes(
              _file!.bytes!,
              filename: _file!.name,
              contentType: DioMediaType.parse(
                _file!.extension?.toLowerCase() == 'pdf'
                    ? 'application/pdf'
                    : _file!.extension?.toLowerCase() == 'png'
                    ? 'image/png'
                    : 'image/jpeg',
              ),
            ),
        }),
      );
      if (!mounted) return;
      setState(() {
        _file = null;
        _remove = false;
      });
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
          onChanged: _busy ? null : (v) => setState(() => _layout = v!),
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
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload background'),
            ),
            if (_background != null || _file != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _remove = true;
                        _file = null;
                      }),
                child: const Text('Remove background'),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save print settings'),
            ),
            TextButton(
              onPressed: _busy ? null : _preview,
              child: const Text('Preview saved form'),
            ),
            if (_error != null)
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry'),
              ),
          ],
        ),
      ],
    );
  }
}
