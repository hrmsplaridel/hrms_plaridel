import '../../../utils/leave_design_capture.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/configured_leave_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import '../../../models/leave_type_definition.dart';
import '../../../utils/leave_layout_pdf.dart';
import '../../../../locator/models/locator_print_layout.dart';
import '../../../../locator/models/locator_request_type.dart';
import '../../../../locator/utils/locator_form_signatories.dart';
import '../../../../locator/presentation/admin/widgets/locator_print_layout_editor.dart';

class LeavePrintDraft {
  const LeavePrintDraft({
    this.layout = 'csc',
    this.file,
    this.printLayout,
    this.removeBackground = false,
    this.dirty = false,
  });
  final String layout;
  final PlatformFile? file;
  final LocatorPrintLayout? printLayout;
  final bool removeBackground, dirty;
  bool get hasChanges =>
      dirty ||
      layout != 'csc' ||
      file != null ||
      printLayout != null ||
      removeBackground;

  Future<void> save(String leaveTypeId, {bool? removeBackground}) async {
    await ApiClient.instance.post(
      '/api/leave/print/types/$leaveTypeId',
      data: FormData.fromMap({
        'layout': layout,
        'remove_background': (removeBackground ?? this.removeBackground)
            .toString(),
        'print_layout': jsonEncode(
          layout == 'custom' ? printLayout?.toJson() : null,
        ),
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
    this.readLeaveType,
    this.onCustomFieldsChanged,
  });
  final String? leaveTypeId;
  final ValueChanged<LeavePrintDraft>? onChanged;
  final VoidCallback? onSaved;
  final LeavePrintDraft? initialDraft;
  final bool enabled;
  final LeaveTypeDefinition Function()? readLeaveType;
  final ValueChanged<List<LeaveCustomFieldDefinition>>? onCustomFieldsChanged;
  @override
  State<LeavePrintSettings> createState() => _LeavePrintSettingsState();
}

class _LeavePrintSettingsState extends State<LeavePrintSettings> {
  String _layout = 'csc', _savedLayout = 'csc';
  LocatorPrintLayout? _printLayout;
  String? _background, _error;
  PlatformFile? _file;
  bool _loading = true,
      _busy = false,
      _remove = false,
      _schemaNeedsSave = false;
  bool _settingsLoaded = false;
  LeavePrintDraft? _restoreDraft;
  bool get _disabled => _busy || !widget.enabled || !_settingsLoaded;
  void _changed() => widget.onChanged?.call(
    LeavePrintDraft(
      layout: _layout,
      file: _file,
      printLayout: _printLayout,
      removeBackground: _remove,
      dirty: true,
    ),
  );
  @override
  void initState() {
    super.initState();
    _restoreDraft = widget.initialDraft;
    _layout = _restoreDraft?.layout ?? 'csc';
    _file = _restoreDraft?.file;
    _printLayout = _restoreDraft?.printLayout;
    _remove = _restoreDraft?.removeBackground ?? false;
    if (widget.leaveTypeId != null) {
      _load();
    } else {
      _loading = false;
      _settingsLoaded = true;
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
        _printLayout =
            _restoreDraft?.printLayout ??
            (r.data!['print_layout'] is Map
                ? LocatorPrintLayout.fromJson(
                    Map<String, dynamic>.from(r.data!['print_layout'] as Map),
                  )
                : null);
        if (_restoreDraft != null) {
          _file = _restoreDraft!.file;
          _remove = _restoreDraft!.removeBackground;
        }
        _restoreDraft = null;
        _background = r.data!['background_name']?.toString();
        _loading = false;
        _settingsLoaded = true;
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
    if (_schemaNeedsSave) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LeavePrintDraft(
        layout: _layout,
        file: _file,
        printLayout: _printLayout,
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

  LeaveTypeDefinition get _type =>
      widget.readLeaveType?.call() ??
      const LeaveTypeDefinition(
        name: 'leave',
        displayName: 'Application for Leave',
      );
  DioMediaType _fileType(PlatformFile file) => DioMediaType.parse(
    file.extension?.toLowerCase() == 'pdf'
        ? 'application/pdf'
        : file.extension?.toLowerCase() == 'png'
        ? 'image/png'
        : 'image/jpeg',
  );
  Future<void> _previewDraft(
    LocatorPrintLayout? custom, {
    List<LeaveCustomFieldDefinition>? customFields,
  }) async {
    final request = leaveLayoutSampleRequest(
      customFields == null
          ? _type
          : _type.copyWith(employeeDetailSchema: customFields),
    );
    final bytes = custom != null
        ? await buildLeaveLayoutPdf(
            layout: custom,
            request: request,
            signatories: LocatorFormSignatories(
              applicant: leaveLayoutSampleSignatory('applicant'),
              departmentHead: leaveLayoutSampleSignatory('department_head'),
              finalApprover: leaveLayoutSampleSignatory('hr_approver'),
            ),
            certificationOfficer: leaveLayoutSampleSignatory(
              'certification_officer',
            ),
          )
        : await (_layout == 'wellness'
                  ? await buildWellnessLeavePdf(
                      request: request,
                      department: 'Human Resources',
                      departmentReviewer: 'Sample Department Head',
                      mayorName: 'Sample Municipal Mayor',
                    )
                  : await LeaveRequestPdf.buildPdf(request: request))
              .save();
    final response = await ApiClient.instance.post<List<int>>(
      '/api/leave/print/preview',
      data: FormData.fromMap({
        if (widget.leaveTypeId != null) 'type_id': widget.leaveTypeId,
        'layout': custom != null ? 'custom' : _layout,
        'print_layout': jsonEncode(custom?.toJson()),
        'remove_background': _remove.toString(),
        'file': MultipartFile.fromBytes(bytes, filename: 'preview.pdf'),
        if (_file != null)
          'background': MultipartFile.fromBytes(
            _file!.bytes!,
            filename: _file!.name,
            contentType: _fileType(_file!),
          ),
      }),
      options: Options(responseType: ResponseType.bytes),
    );
    if (mounted) {
      await showFormPdfPreview(
        context: context,
        bytes: Uint8List.fromList(response.data!),
        title: 'Leave Form Preview',
        filename: 'Leave_Form_Sample.pdf',
      );
    }
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _previewDraft(_layout == 'custom' ? _printLayout : null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not preview the form. Check the layout and background orientation.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editLayout() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? pdf, image;
      if (_file != null) {
        if (_file!.extension?.toLowerCase() == 'pdf') {
          pdf = _file!.bytes;
        } else {
          image = _file!.bytes;
        }
      } else if (!_remove &&
          _background != null &&
          widget.leaveTypeId != null) {
        final response = await ApiClient.instance.get<List<int>>(
          '/api/leave/print/types/${widget.leaveTypeId}/background',
          options: Options(responseType: ResponseType.bytes),
        );
        pdf = Uint8List.fromList(response.data!);
      }
      final type = _type;
      var initial = _layout == 'custom' ? _printLayout : null;
      final nativeForm =
          initial?.baseForm ??
          (widget.leaveTypeId != null && initial == null ? _layout : null);
      if (nativeForm == 'csc' || nativeForm == 'wellness') {
        if (initial == null) {
          final imported = await importLeaveNativeLayout(
            type,
            nativeForm!,
            letterhead: pdf != null || image != null,
          );
          initial = imported.layout;
          final native = imported.background;
          if (pdf == null && image == null) {
            pdf = native;
          } else {
            final response = await ApiClient.instance.post<List<int>>(
              '/api/leave/print/preview',
              data: FormData.fromMap({
                'layout': nativeForm,
                'file': MultipartFile.fromBytes(
                  native,
                  filename: 'native-preview.pdf',
                ),
                if (widget.leaveTypeId != null && _file == null)
                  'type_id': widget.leaveTypeId,
                if (_file != null)
                  'background': MultipartFile.fromBytes(
                    _file!.bytes!,
                    filename: _file!.name,
                    contentType: _fileType(_file!),
                  ),
              }),
              options: Options(responseType: ResponseType.bytes),
            );
            pdf = Uint8List.fromList(response.data!);
            image = null;
          }
        } else {
          final capture = LeaveDesignCapture(
            fields: leaveLayoutFields(type),
            renderingLayout: initial,
          );
          final request = leaveLayoutSampleRequest(type);
          final doc = nativeForm == 'wellness'
              ? await buildWellnessLeavePdf(
                  request: request,
                  department: request.officeDepartment ?? '',
                  designCapture: capture,
                )
              : await LeaveRequestPdf.buildPdf(
                  request: request,
                  designCapture: capture,
                );
          final native = await doc.save();
          if (pdf == null && image == null) {
            pdf = native;
          } else {
            final response = await ApiClient.instance.post<List<int>>(
              '/api/leave/print/preview',
              data: FormData.fromMap({
                'layout': 'custom',
                'print_layout': jsonEncode(initial.toJson()),
                'file': MultipartFile.fromBytes(
                  native,
                  filename: 'native-preview.pdf',
                ),
                if (widget.leaveTypeId != null && _file == null)
                  'type_id': widget.leaveTypeId,
                if (_file != null)
                  'background': MultipartFile.fromBytes(
                    _file!.bytes!,
                    filename: _file!.name,
                    contentType: _fileType(_file!),
                  ),
              }),
              options: Options(responseType: ResponseType.bytes),
            );
            pdf = Uint8List.fromList(response.data!);
            image = null;
          }
        }
      }
      if (!mounted) return;
      final result = await showDialog<LocatorPrintLayout>(
        context: context,
        builder: (_) => LocatorPrintLayoutEditor(
          requestType: LocatorRequestType.locator.copyWith(
            label: type.displayName,
            employeeDetailSchema: type.employeeDetailSchema,
          ),
          initialLayout: initial,
          backgroundPdf: pdf,
          backgroundImage: image,
          bindings: PrintLayoutEditorBindings(
            fields: leaveLayoutFields(type),
            signatures: leaveLayoutSignatures(initial?.baseForm ?? _layout),
            sample: leaveLayoutForm(leaveLayoutSampleRequest(type)),
            defaultLayout: (orientation) =>
                leavePrintLayoutDefaults(type, orientation: orientation),
            sampleSignatory: leaveLayoutSampleSignatory,
          ),
          onPreview: _previewDraft,
          onPreviewWithFields: (layout, fields) =>
              _previewDraft(layout, customFields: fields),
          onCustomFieldsChanged: widget.onCustomFieldsChanged == null
              ? null
              : (fields) {
                  widget.onCustomFieldsChanged!(fields);
                  setState(() => _schemaNeedsSave = true);
                },
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _printLayout = result;
          _layout = 'custom';
        });
        _changed();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open the layout editor. Please retry.',
        );
      }
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
          key: ValueKey(_layout),
          initialValue: _layout,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Form layout'),
          items: [
            if (_printLayout != null)
              const DropdownMenuItem(
                value: 'custom',
                child: Text('Custom designed form'),
              ),
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
        Row(
          children: [
            Expanded(
              child: Text(
                _remove
                    ? 'Background will be removed'
                    : _file?.name ?? _background ?? 'No background uploaded',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_remove && (_background != null || _file != null))
              IconButton(
                tooltip: 'Remove background',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _disabled
                    ? null
                    : () {
                        setState(() {
                          _remove = widget.leaveTypeId != null;
                          _file = null;
                        });
                        _changed();
                      },
              ),
          ],
        ),
        Text(
          _layout == 'custom'
              ? 'A4, Letter, Long Bond or Legal · portrait or landscape · PDF, PNG or JPEG · Max 5 MB'
              : 'A4 portrait · PDF, PNG or JPEG · Max 5 MB',
        ),
        if (_layout == 'wellness') ...[
          const SizedBox(height: 8),
          const Text(
            'JO/COS: Wellness form with manual Mayor signing. Others: CSC form.',
          ),
        ],
        if (_schemaNeedsSave)
          const Text(
            'Save the type changes to keep the new fields and layout.',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _disabled ? null : _editLayout,
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: Text(
                _printLayout == null ? 'Design layout' : 'Edit layout',
              ),
            ),
            TextButton(
              onPressed: _disabled ? null : _pick,
              child: const Text('Upload background'),
            ),
            TextButton(
              onPressed: _disabled ? null : _preview,
              child: const Text('Preview'),
            ),
            if (widget.leaveTypeId != null)
              FilledButton(
                onPressed: _disabled || _schemaNeedsSave ? null : _save,
                child: const Text('Save print settings'),
              ),
            if (_error != null && widget.leaveTypeId != null)
              TextButton(
                onPressed: _busy || !widget.enabled ? null : _load,
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
