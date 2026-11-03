import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';

/// Leave-style Printed Form controls for a DocuTracker document type.
class DocuTrackerPrintSettings extends StatefulWidget {
  const DocuTrackerPrintSettings({
    super.key,
    required this.documentType,
    required this.displayName,
    this.enabled = true,
  });

  final String documentType;
  final String displayName;
  final bool enabled;

  @override
  State<DocuTrackerPrintSettings> createState() =>
      _DocuTrackerPrintSettingsState();
}

class _DocuTrackerPrintSettingsState extends State<DocuTrackerPrintSettings> {
  bool _loading = true;
  bool _busy = false;
  bool _remove = false;
  String? _error;
  String? _background;
  LocatorPrintLayout? _printLayout;
  PlatformFile? _file;

  bool get _disabled => !widget.enabled || _busy;

  bool get _builtinMemo => widget.documentType == 'memo';

  bool get _builtinPurchaseRequest =>
      widget.documentType == 'purchaseRequest';

  bool get _hasOfficialTemplate => _builtinMemo || _builtinPurchaseRequest;

  /// What Print and Export PDF use right now.
  String get _activePrintLabel {
    if (_printLayout != null) {
      return _hasOfficialTemplate
          ? 'Saved printed form. Print and Export PDF use this instead of the official template.'
          : 'Saved printed form. Print and Export PDF use this layout.';
    }
    if (_builtinMemo) {
      return 'Official memorandum template. Print and Export PDF use it until you save a different form here.';
    }
    if (_builtinPurchaseRequest) {
      return 'Official purchase-request draft. Print and Export PDF use it until you save a different form here.';
    }
    return 'The document editor page. Print and Export PDF use it until you save a printed form here.';
  }

  DioMediaType _fileType(PlatformFile file) => DioMediaType.parse(
    file.extension?.toLowerCase() == 'png'
        ? 'image/png'
        : file.extension?.toLowerCase() == 'jpg' ||
              file.extension?.toLowerCase() == 'jpeg'
        ? 'image/jpeg'
        : 'application/pdf',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get(
        '/api/docutracker/print/types/${Uri.encodeComponent(widget.documentType)}',
      );
      final data = Map<String, dynamic>.from(response.data as Map? ?? {});
      if (!mounted) return;
      setState(() {
        _background = data['background_name']?.toString();
        _printLayout = data['print_layout'] is Map
            ? LocatorPrintLayout.fromJson(
                Map<String, dynamic>.from(data['print_layout'] as Map),
              )
            : null;
        _remove = false;
        _file = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load printed form settings.';
      });
    }
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _file = file;
      _remove = false;
    });
  }

  Future<void> _save() async {
    if (_printLayout == null) {
      setState(() => _error = 'Design a layout before saving.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        'display_name': widget.displayName,
        'print_layout': jsonEncode(_printLayout!.toJson()),
        'remove_background': _remove.toString(),
        if (_file != null)
          'file': MultipartFile.fromBytes(
            _file!.bytes!,
            filename: _file!.name,
            contentType: _fileType(_file!),
          ),
      });
      await ApiClient.instance.post(
        '/api/docutracker/print/types/${Uri.encodeComponent(widget.documentType)}',
        data: form,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed form settings saved.')),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save printed form settings.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewDraft(LocatorPrintLayout layout) async {
    final overlay = await buildLocatorLayoutPdf(
      layout: layout,
      form: docuTrackerPrintLayoutSample(
        documentTypeLabel: widget.displayName,
      ),
      signatories: LocatorFormSignatories(
        applicant: docuTrackerPrintSampleSignatory('applicant'),
        departmentHead: docuTrackerPrintSampleSignatory('department_head'),
        finalApprover: docuTrackerPrintSampleSignatory('approved_by'),
      ),
      extraSignatories: {
        for (final source in docuTrackerPrintLayoutSignatures().keys)
          source: docuTrackerPrintSampleSignatory(source),
      },
    );
    final form = FormData.fromMap({
      'document_type': widget.documentType,
      'print_layout': jsonEncode(layout.toJson()),
      'remove_background': _remove.toString(),
      'file': MultipartFile.fromBytes(
        overlay,
        filename: 'docutracker-preview.pdf',
      ),
      if (_file != null)
        'background': MultipartFile.fromBytes(
          _file!.bytes!,
          filename: _file!.name,
          contentType: _fileType(_file!),
        ),
    });
    final response = await ApiClient.instance.post<List<int>>(
      '/api/docutracker/print/preview',
      data: form,
      options: Options(responseType: ResponseType.bytes),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(response.data!),
      name: '${widget.displayName} printed form',
    );
  }

  Future<void> _editLayout() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? pdf;
      Uint8List? image;
      if (_file?.bytes != null) {
        if (_file!.extension?.toLowerCase() == 'pdf') {
          pdf = _file!.bytes;
        } else {
          image = _file!.bytes;
        }
      } else if (!_remove && _background != null) {
        final response = await ApiClient.instance.get<List<int>>(
          '/api/docutracker/print/types/${Uri.encodeComponent(widget.documentType)}/background',
          options: Options(responseType: ResponseType.bytes),
        );
        pdf = Uint8List.fromList(response.data!);
      }
      if (!mounted) return;
      final result = await Navigator.of(context).push<LocatorPrintLayout>(
        MaterialPageRoute(
          builder: (_) => LocatorPrintLayoutEditor(
            requestType: LocatorRequestType.locator.copyWith(
              label: widget.displayName,
            ),
            initialLayout: _printLayout,
            backgroundPdf: pdf,
            backgroundImage: image,
            bindings: PrintLayoutEditorBindings(
              fields: docuTrackerPrintLayoutFields(),
              signatures: docuTrackerPrintLayoutSignatures(),
              sample: docuTrackerPrintLayoutSample(
                documentTypeLabel: widget.displayName,
              ),
              defaultLayout: (orientation) =>
                  docuTrackerPrintLayoutDefaults(orientation: orientation),
              sampleSignatory: docuTrackerPrintSampleSignatory,
            ),
            onPreview: _previewDraft,
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() => _printLayout = result);
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

  Future<void> _preview() async {
    if (_printLayout == null) {
      setState(
        () => _error = _hasOfficialTemplate
            ? 'The official template is already what prints. Design a layout only when you want to replace it.'
            : 'Design a layout before previewing a replacement.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _previewDraft(_printLayout!);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not preview the printed form.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return Card(
      color: DocuTrackerTokens.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Printed Form',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hasOfficialTemplate
                  ? 'The official template stays in use. Upload a background and design a layout only when Print and Export PDF should use that instead.'
                  : 'Upload a letterhead and place fields on it when Print and Export PDF should use a designed form instead of the editor page.',
              style: DocuTrackerTokens.metaStyle(context),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Text(
              'Form layout',
              style: DocuTrackerTokens.metaStyle(context).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _activePrintLabel,
              style: TextStyle(
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _remove
                        ? 'Background will be removed when you save'
                        : _file?.name ??
                              _background ??
                              (_hasOfficialTemplate
                                  ? 'Official template background'
                                  : 'No replacement background'),
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
                        : () => setState(() {
                            _remove = true;
                            _file = null;
                          }),
                  ),
              ],
            ),
            Text(
              'A4, Letter, Long Bond or Legal · portrait or landscape · '
              'PDF, PNG or JPEG · Max 5 MB',
              style: DocuTrackerTokens.metaStyle(context),
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
                    _printLayout == null
                        ? 'Design a replacement'
                        : 'Edit layout',
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
                FilledButton(
                  onPressed: _disabled || _printLayout == null ? null : _save,
                  child: const Text('Save print settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
