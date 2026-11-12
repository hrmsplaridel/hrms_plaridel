import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
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
  bool _pending = false;
  String? _error;
  String? _background;
  LocatorPrintLayout? _printLayout;
  PlatformFile? _file;
  Uint8List? _previewPdf;
  Uint8List? _previewImage;
  Uint8List? _officialLetterhead;
  String? _officialLetterheadName;
  final TextEditingController _previewTo = TextEditingController();
  final TextEditingController _previewSubject = TextEditingController();
  final TextEditingController _previewDate = TextEditingController();
  final TextEditingController _previewCc = TextEditingController();

  bool get _disabled => !widget.enabled || _busy;

  bool get _builtinMemo =>
      DocumentType.fromValue(widget.documentType) == DocumentType.memo;

  bool get _builtinPurchaseRequest =>
      DocumentType.fromValue(widget.documentType) ==
      DocumentType.purchaseRequest;

  bool get _hasOfficialTemplate =>
      DocumentType.fromValue(widget.documentType).printsOfficialForm;

  /// Active Form layout dropdown value.
  String get _formLayoutValue {
    if (_printLayout != null) return 'custom';
    if (_hasOfficialTemplate) return 'official';
    return 'editor';
  }

  String get _officialLayoutLabel {
    if (_builtinPurchaseRequest) return 'Official purchase request';
    if (_builtinMemo) {
      final name = _officialLetterheadName;
      if (name != null && name.isNotEmpty) {
        return 'Official memorandum ($name)';
      }
      return 'Official memorandum';
    }
    return 'Official form';
  }

  /// Explains whether a save on this page changes Print and Export PDF.
  String get _intro {
    if (_pending) {
      return 'These changes are not saved yet. Save print settings to apply them '
          'to this document type.';
    }
    if (_printLayout != null) {
      return 'A custom printed form is active. Employees fill this designed page '
          '(not the built-in Memo/PR sheet). Print and Export PDF use this layout. '
          'Switch Form layout back to official to restore the built-in template.';
    }
    if (_hasOfficialTemplate) {
      return 'Default is the official form. Design layout saves automatically when '
          'you leave the designer—then create or open a draft document to fill it.';
    }
    return 'Choose a form layout, upload a background, and design the fields—like Leave type Printed Form setup.';
  }

  /// Inline thumbnail only after the admin expands it (keeps workflow usable).
  bool _showInlinePreview = false;

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
        _pending = false;
        _loading = false;
      });
      if (!_hasOfficialTemplate) await _refreshPreview();
      if (widget.documentType == 'memo') {
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
      _pending = true;
      _error = null;
    });
    await _refreshPreview();
  }

  String _apiMessage(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        final message = (data['error'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    }
    return fallback;
  }

  Future<void> _refreshPreview() async {
    if (_remove) {
      if (mounted) {
        setState(() {
          _previewPdf = null;
          _previewImage = null;
        });
      }
      return;
    }
    final picked = _file?.bytes;
    if (picked != null) {
      final extension = _file!.extension?.toLowerCase();
      if (extension == 'png' || extension == 'jpg' || extension == 'jpeg') {
        if (mounted) {
          setState(() {
            _previewImage = picked;
            _previewPdf = null;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _previewPdf = picked;
          _previewImage = null;
        });
      }
      return;
    }
    if (_background == null || _background!.isEmpty) {
      if (mounted) {
        setState(() {
          _previewPdf = null;
          _previewImage = null;
        });
      }
      return;
    }
    try {
      final response = await ApiClient.instance.get<List<int>>(
        '/api/docutracker/print/types/${Uri.encodeComponent(widget.documentType)}/background',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (!mounted || bytes == null || bytes.isEmpty) return;
      setState(() {
        _previewPdf = Uint8List.fromList(bytes);
        _previewImage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewPdf = null;
        _previewImage = null;
      });
    }
  }

  /// Persists the current layout/background to the document type. Caller owns
  /// busy-state and success messaging.
  Future<bool> _persistPrintSettings() async {
    if (_printLayout == null) {
      setState(() => _error = 'Design a layout before saving.');
      return false;
    }
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
      if (!mounted) return false;
      await _load();
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _apiMessage(
            error,
            'Could not save printed form settings.',
          ),
        );
      }
      return false;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await _persistPrintSettings();
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printed form settings saved.')),
        );
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
        documentType: widget.documentType,
      ),
      signatories: LocatorFormSignatories(
        applicant: docuTrackerPrintSampleSignatory('applicant'),
        departmentHead: docuTrackerPrintSampleSignatory('noted_by'),
        finalApprover: docuTrackerPrintSampleSignatory('approved_by'),
      ),
      extraSignatories: {
        for (final source in docuTrackerPrintLayoutSignatures(
          documentType: widget.documentType,
        ).keys)
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
              fields: docuTrackerPrintLayoutFields(
                documentType: widget.documentType,
              ),
              signatures: docuTrackerPrintLayoutSignatures(
                documentType: widget.documentType,
              ),
              sample: docuTrackerPrintLayoutSample(
                documentTypeLabel: widget.displayName,
                documentType: widget.documentType,
              ),
              defaultLayout: (orientation) => docuTrackerPrintLayoutDefaults(
                orientation: orientation,
                documentType: widget.documentType,
              ),
              sampleSignatory: docuTrackerPrintSampleSignatory,
            ),
            onPreview: _previewDraft,
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _printLayout = result;
          _pending = true;
          _error = null;
        });
        // Designing alone used to leave the type pointer null — employees still
        // saw the official Memo/PR page. Persist immediately when the editor
        // returns a layout (same as clicking Save print settings).
        final ok = await _persistPrintSettings();
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Printed form saved. New and draft documents use this layout.',
              ),
            ),
          );
        }
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

  bool get _showingOfficialMemo => _builtinMemo;

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

  Future<void> _restoreOfficial() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post(
        '/api/docutracker/print/types/${Uri.encodeComponent(widget.documentType)}/use-official',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored official printed form.')),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _apiMessage(
            error,
            'Could not restore the official printed form.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onFormLayoutChanged(String? value) async {
    if (value == null || value == _formLayoutValue) return;
    if (value == 'custom') {
      if (_printLayout == null) await _editLayout();
      return;
    }
    if (value == 'official' || value == 'editor') {
      if (_printLayout != null || _background != null || _file != null) {
        await _restoreOfficial();
      }
    }
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
        () => _error =
            'Design a layout before previewing, or preview the official form.',
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
    // Match Leave Printed Form: plain column (parent supplies card chrome).
    final layoutValue = _formLayoutValue;
    return Column(
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
        Text(_intro, style: DocuTrackerTokens.metaStyle(context)),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(layoutValue),
          initialValue: layoutValue,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Form layout'),
          items: [
            if (_hasOfficialTemplate)
              DropdownMenuItem(
                value: 'official',
                child: Text(_officialLayoutLabel),
              ),
            if (_printLayout != null)
              const DropdownMenuItem(
                value: 'custom',
                child: Text('Custom designed form'),
              ),
            if (!_hasOfficialTemplate)
              const DropdownMenuItem(
                value: 'editor',
                child: Text('Document editor page'),
              ),
          ],
          onChanged: _disabled
              ? null
              : (value) => unawaited(_onFormLayoutChanged(value)),
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
                          (_hasOfficialTemplate && _printLayout == null
                              ? (_officialLetterheadName ??
                                    'Official letterhead (default)')
                              : 'No background uploaded'),
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
                        _pending = true;
                        _previewPdf = null;
                        _previewImage = null;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 4),
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
            TextButton(
              onPressed: () =>
                  setState(() => _showInlinePreview = !_showInlinePreview),
              child: Text(
                _showInlinePreview ? 'Hide thumbnail' : 'Show thumbnail',
              ),
            ),
            FilledButton(
              onPressed: _disabled || _printLayout == null ? null : _save,
              child: const Text('Save print settings'),
            ),
            if (_hasOfficialTemplate && _printLayout != null)
              TextButton(
                onPressed: _disabled ? null : _restoreOfficial,
                child: const Text('Use official form'),
              ),
          ],
        ),
        if (_showInlinePreview) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _previewImage != null
                    ? Image.memory(_previewImage!, fit: BoxFit.contain)
                    : _previewPdf != null
                    ? PdfPreview(
                        build: (_) async => _previewPdf!,
                        maxPageWidth: 280,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        allowPrinting: false,
                        allowSharing: false,
                      )
                    : _builtinMemo
                    ? _OfficialMemoPreview(
                        paperWidth: _paperWidth,
                        paperHeight: _paperHeight,
                        letterheadBytes: _officialLetterhead,
                        toController: _previewTo,
                        subjectController: _previewSubject,
                        dateController: _previewDate,
                        ccController: _previewCc,
                      )
                    : Center(
                        child: Text(
                          'No thumbnail yet. Use Preview for a full-page view.',
                          style: DocuTrackerTokens.metaStyle(context),
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _hasOfficialTemplate
              ? 'Official stays the default until you save a custom layout. '
                    'Then Print / Export PDF use the custom page. Switch back anytime. '
                    'Preview opens full page; thumbnail stays small on this screen.'
              : 'The selected layout and background are used when employees '
                    'fill this document type, and for Print / Export PDF. '
                    'Preview opens full page; use Show thumbnail for a small peek.',
          style: DocuTrackerTokens.metaStyle(context),
        ),
      ],
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
