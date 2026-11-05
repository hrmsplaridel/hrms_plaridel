import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_memo_sheet.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_letterhead.dart';
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
  static const double _paperWidth = DocuTrackerMemoLayout.pageWidthPx;
  static const double _paperHeight = 1123;

  bool _loading = true;
  bool _busy = false;
  bool _remove = false;
  String? _error;
  String? _background;
  LocatorPrintLayout? _printLayout;
  PlatformFile? _file;
  Uint8List? _officialLetterhead;
  String? _officialLetterheadName;
  final TextEditingController _previewTo = TextEditingController();
  final TextEditingController _previewSubject = TextEditingController();
  final TextEditingController _previewDate = TextEditingController();
  final TextEditingController _previewCc = TextEditingController();

  bool get _disabled => !widget.enabled || _busy;

  bool get _builtinMemo => widget.documentType == 'memo';

  bool get _builtinPurchaseRequest => widget.documentType == 'purchaseRequest';

  bool get _hasOfficialTemplate => _builtinMemo || _builtinPurchaseRequest;

  /// What Print and Export PDF use right now.
  String get _activePrintLabel {
    if (_printLayout != null) {
      return _hasOfficialTemplate
          ? 'Saved printed form. Print and Export PDF use this instead of the official template.'
          : 'Saved printed form. Print and Export PDF use this layout.';
    }
    if (_builtinMemo) {
      final name = _officialLetterheadName;
      if (name != null && name.isNotEmpty) {
        return 'Official memorandum template ($name). Print and Export PDF use this letterhead until you save a different form here.';
      }
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
    _previewDate.text = docuTrackerMemoDateText(DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _previewTo.dispose();
    _previewSubject.dispose();
    _previewDate.dispose();
    _previewCc.dispose();
    super.dispose();
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
      final layout = data['print_layout'] is Map
          ? LocatorPrintLayout.fromJson(
              Map<String, dynamic>.from(data['print_layout'] as Map),
            )
          : null;
      final background = data['background_name']?.toString();
      final letterheadName = data['has_official_letterhead'] == true
          ? data['official_letterhead_name']?.toString()
          : null;
      final usingOfficial =
          layout == null && (background == null || background.isEmpty);
      setState(() {
        _background = background;
        _printLayout = layout;
        _officialLetterheadName = usingOfficial ? letterheadName : null;
        _officialLetterhead = null;
        _remove = false;
        _file = null;
        _loading = false;
      });
      if (widget.documentType == 'memo' && usingOfficial) {
        final bytes = await loadDocuTrackerMemoLetterheadPng();
        if (!mounted || bytes == null || bytes.isEmpty) return;
        setState(() {
          _officialLetterhead = bytes;
          _officialLetterheadName =
              (letterheadName != null && letterheadName.isNotEmpty)
              ? letterheadName
              : 'Official HR letterhead';
        });
      }
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
          )
        else if (_letterheadUpload != null)
          'file': _letterheadUpload,
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
      form: docuTrackerPrintLayoutSample(documentTypeLabel: widget.displayName),
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
        )
      else if (_letterheadUpload != null)
        'background': _letterheadUpload,
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
      } else if (!_remove &&
          (_background == null || _background!.isEmpty) &&
          _officialLetterhead != null) {
        image = _officialLetterhead;
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

  MultipartFile? get _letterheadUpload {
    if (_file != null ||
        _remove ||
        _officialLetterhead == null ||
        (_background != null && _background!.isNotEmpty)) {
      return null;
    }
    return MultipartFile.fromBytes(
      _officialLetterhead!,
      filename: 'HR_A4.png',
      contentType: DioMediaType.parse('image/png'),
    );
  }

  bool get _showingOfficialMemo =>
      _builtinMemo &&
      _printLayout == null &&
      _file == null &&
      !_remove &&
      (_background == null || _background!.isEmpty);

  bool get _showingOfficialLetterhead =>
      _showingOfficialMemo && _officialLetterhead != null;

  Future<void> _previewOfficialLetterhead() async {
    final bytes = await docuTrackerLetterheadPagePdf(_officialLetterhead!);
    if (!mounted) return;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${widget.displayName} letterhead',
    );
  }

  Future<void> _preview() async {
    if (_printLayout == null) {
      if (_showingOfficialLetterhead) {
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          await _previewOfficialLetterhead();
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'Could not preview the printed form.');
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
        return;
      }
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
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Text(
              'Form layout',
              style: DocuTrackerTokens.metaStyle(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _activePrintLabel,
              style: TextStyle(color: DocuTrackerTokens.textPrimaryOf(context)),
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
                              _officialLetterheadName ??
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
            if (_showingOfficialMemo) ...[
              const SizedBox(height: 12),
              _OfficialMemoPreview(
                paperWidth: _paperWidth,
                paperHeight: _paperHeight,
                letterheadBytes: _officialLetterhead,
                toController: _previewTo,
                subjectController: _previewSubject,
                dateController: _previewDate,
                ccController: _previewCc,
              ),
            ],
            const SizedBox(height: 8),
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

class _OfficialMemoPreview extends StatelessWidget {
  const _OfficialMemoPreview({
    required this.paperWidth,
    required this.paperHeight,
    required this.letterheadBytes,
    required this.toController,
    required this.subjectController,
    required this.dateController,
    required this.ccController,
  });

  final double paperWidth;
  final double paperHeight;
  final Uint8List? letterheadBytes;
  final TextEditingController toController;
  final TextEditingController subjectController;
  final TextEditingController dateController;
  final TextEditingController ccController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : paperWidth;
        final width = available < paperWidth ? available : paperWidth;
        final scale = width / paperWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: paperWidth * scale,
            height: paperHeight * scale,
            child: FittedBox(
              child: IgnorePointer(
                child: Container(
                  width: paperWidth,
                  height: paperHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 1.1,
                    ),
                  ),
                  child: DocuTrackerMemoSheet(
                    size: Size(paperWidth, paperHeight),
                    toController: toController,
                    subjectController: subjectController,
                    dateController: dateController,
                    ccController: ccController,
                    editable: true,
                    letterheadBytes: letterheadBytes,
                    body: const Text(
                      '[State the purpose and background of this memorandum.]\n\n'
                      '[State the instructions, required action, and deadline, if any.]',
                      style: TextStyle(
                        fontFamily: DocuTrackerMemoLayout.fontFamily,
                        fontSize: DocuTrackerMemoLayout.bodyFontSize,
                        height: DocuTrackerMemoLayout.bodyLineHeight,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
