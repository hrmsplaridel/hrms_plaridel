import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_printable_page_frame.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_field_visual.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_fields_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_pdf_export.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_printable_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_geometry.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_draft_text.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_purchase_items_table.dart';

class DocuTrackerDocumentBuilderScreen extends StatefulWidget {
  const DocuTrackerDocumentBuilderScreen({
    super.key,
    required this.document,
    this.prefillNewDraft = false,
  });

  final DocuTrackerDocument document;
  final bool prefillNewDraft;

  @override
  State<DocuTrackerDocumentBuilderScreen> createState() =>
      _DocuTrackerDocumentBuilderScreenState();
}

class _DocuTrackerDocumentBuilderScreenState
    extends State<DocuTrackerDocumentBuilderScreen> {
  static const double _paperWidth = 794;
  static const double _paperHeight = 1123;
  static const double _horizontalMargin = 68;
  static const double _verticalMargin = 72;
  static const double _signaturePanelBreakpoint = 1180;
  static const int _letterheadFormatVersion = 2;
  static const String _letterheadLogoAsset = 'assets/images/Plaridel Logo.jpg';

  final EmployeeDirectoryLookup _directory = EmployeeDirectoryLookup();
  final List<_EditorPage> _pages = <_EditorPage>[];
  final List<GlobalKey> _pageKeys = <GlobalKey>[];
  List<DocuTrackerSignatureField> _signatureFields =
      <DocuTrackerSignatureField>[];
  Uint8List? _letterheadBackgroundBytes;
  int _revision = 0;
  int _formatVersion = 1;
  String _currentUserId = '';
  int _activePage = 0;
  int _localFieldCounter = 0;
  String? _selectedFieldId;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _loadingDirectory = false;
  bool _exporting = false;
  bool _canEditLayout = false;
  bool _dirty = false;
  String? _draggingSignedFieldId;
  double? _signedDragOriginX;
  double? _signedDragOriginY;
  double _zoom = 1;
  bool _fitWidth = false;
  bool _signaturePanelOpen = false;
  int? _capturePage;
  double _renderScale = 1;
  TextSelection? _formatSelection;
  bool get _busy => _saving || _exporting || _loadingDirectory;

  DocuTrackerProvider get _provider => context.read<DocuTrackerProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final documentId = widget.document.id;
    if (documentId == null || documentId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Save the draft before opening the document builder.';
      });
      return;
    }
    final data = await _provider.loadDocumentBuilder(documentId);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _error =
            _provider.builderError ?? 'Could not load the document builder.';
      });
      return;
    }
    if (data.formatVersion >= _letterheadFormatVersion) {
      final background =
          await DocuTrackerPrintableTemplate.loadA4LetterheadPng();
      if (!mounted) return;
      if (background != null) {
        await precacheImage(MemoryImage(background), context);
      } else {
        await precacheImage(const AssetImage(_letterheadLogoAsset), context);
      }
      if (!mounted) return;
      _letterheadBackgroundBytes = background;
    }
    _replaceFromServer(data);
    if (widget.prefillNewDraft && DocuTrackerDraftText.canPrefill(data)) {
      _pages.first.controller.replaceText(
        0,
        0,
        quill.Document.fromJson(
          DocuTrackerDraftText.composePage(widget.document).delta,
        ).toDelta(),
        const TextSelection.collapsed(offset: 0),
      );
      setState(() => _dirty = true);
    }
  }

  void _replaceFromServer(DocuTrackerDocumentBuilderData data) {
    for (final page in _pages) {
      page.dispose();
    }
    _pages.clear();
    _pageKeys.clear();
    for (var index = 0; index < data.pages.length; index++) {
      final page = data.pages[index];
      final controller = quill.QuillController(
        document: quill.Document.fromJson(page.delta),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: !data.canEditLayout,
      );
      final editorPage = _EditorPage(controller: controller);
      final pageIndex = index;
      editorPage.focusNode.addListener(() {
        if (editorPage.focusNode.hasFocus && mounted && !_exporting) {
          setState(() => _activePage = pageIndex);
        }
      });
      editorPage.changeSubscription = controller.document.changes.listen((_) {
        if (mounted && !_dirty) setState(() => _dirty = true);
      });
      _pages.add(editorPage);
      _pageKeys.add(GlobalKey());
    }
    setState(() {
      _signatureFields = List<DocuTrackerSignatureField>.from(
        data.signatureFields,
      );
      _revision = data.revision;
      _formatVersion = data.formatVersion;
      _currentUserId = data.currentUserId;
      _canEditLayout = data.canEditLayout;
      _activePage = _activePage.clamp(0, _pages.length - 1);
      _loading = false;
      _saving = false;
      _error = null;
      _dirty = false;
    });
  }

  List<DocuTrackerDocumentPage> _serializePages() => _pages
      .map(
        (page) => DocuTrackerDocumentPage(
          delta: page.controller.document
              .toDelta()
              .toJson()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
        ),
      )
      .toList(growable: false);

  Future<bool> _save() async {
    final documentId = widget.document.id;
    if (!_canEditLayout || documentId == null || _busy) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await _provider.saveDocumentBuilder(
      documentId: documentId,
      pages: _serializePages(),
      signatureFields: _signatureFields,
      revision: _revision,
    );
    if (!mounted) return false;
    if (saved == null) {
      setState(() {
        _saving = false;
        _error =
            _provider.builderError ?? 'Could not save the document layout.';
      });
      return false;
    }
    _replaceFromServer(saved);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Document layout saved.')));
    return true;
  }

  void _addPage() {
    if (!_canEditLayout || _busy || _pages.length >= 50) return;
    final controller = quill.QuillController.basic();
    final page = _EditorPage(controller: controller);
    final pageIndex = _pages.length;
    page.focusNode.addListener(() {
      if (page.focusNode.hasFocus && mounted && !_exporting) {
        setState(() => _activePage = pageIndex);
      }
    });
    page.changeSubscription = controller.document.changes.listen((_) {
      if (mounted && !_dirty) setState(() => _dirty = true);
    });
    setState(() {
      _pages.add(page);
      _pageKeys.add(GlobalKey());
      _activePage = pageIndex;
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_exporting) page.focusNode.requestFocus();
    });
  }

  Future<void> _addSignatureField() async {
    if (!_canEditLayout || _busy) return;
    if (!_directory.isLoaded) {
      setState(() => _loadingDirectory = true);
      try {
        await _directory.load();
      } finally {
        if (mounted) setState(() => _loadingDirectory = false);
      }
    }
    if (!mounted || _busy) return;
    if (!_directory.isLoaded || _directory.entries.isEmpty) {
      setState(() => _error = 'Active employee directory is unavailable.');
      return;
    }
    final labelController = TextEditingController(text: 'Sign Here');
    var signerId = _directory.entries.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add signature placeholder'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: signerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assigned signer',
                    border: OutlineInputBorder(),
                  ),
                  items: _directory.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.id,
                          child: Text(
                            entry.nameAndDepartment,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => signerId = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: labelController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Placeholder label',
                    hintText: 'Sign Here',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Place field'),
            ),
          ],
        ),
      ),
    );
    final label = labelController.text.trim();
    labelController.dispose();
    if (accepted != true || label.isEmpty || !mounted) return;
    final signer = _directory[signerId];
    final placement = _nextSignaturePlacement();
    final id =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localFieldCounter++}';
    setState(() {
      _signatureFields.add(
        DocuTrackerSignatureField(
          id: id,
          pageNumber: _activePage + 1,
          x: placement.x,
          y: placement.y,
          width: 0.3,
          height: 0.12,
          assignedSignerId: signerId,
          assignedSignerName: signer?.fullName,
          label: label,
        ),
      );
      _selectedFieldId = id;
      _dirty = true;
    });
  }

  Future<void> _signField(DocuTrackerSignatureField field) async {
    if (!field.canSign || _busy) return;
    if (field.id.startsWith('local-')) {
      setState(
        () => _error = 'Save the document before signing this placeholder.',
      );
      return;
    }
    if (field.isSigned) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace signature?'),
          content: const Text(
            'Your current signature will be replaced in this field. '
            'The replacement will be recorded in document history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final choice = await showDocuTrackerSignatureDialog(
      context,
      provider: _provider,
    );
    if (choice == null || !mounted) return;
    await _applySignatureChoice(field, choice);
  }

  Future<void> _insertOwnSignature() async {
    if (!_canEditLayout || _currentUserId.isEmpty || _busy) return;
    final choice = await showDocuTrackerSignatureDialog(
      context,
      provider: _provider,
    );
    if (choice == null || !mounted) return;
    final pageNumber = _activePage + 1;
    final placement = _nextSignaturePlacement();
    final localId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localFieldCounter++}';
    final signer = _directory[_currentUserId];
    setState(() {
      _signatureFields.add(
        DocuTrackerSignatureField(
          id: localId,
          pageNumber: pageNumber,
          x: placement.x,
          y: placement.y,
          width: 0.3,
          height: 0.12,
          assignedSignerId: _currentUserId,
          assignedSignerName: signer?.fullName,
          label: 'Signature',
        ),
      );
      _selectedFieldId = localId;
      _dirty = true;
    });
    if (!await _save() || !mounted) return;
    final savedFields = _signatureFields
        .where(
          (field) =>
              !field.isSigned &&
              field.pageNumber == pageNumber &&
              field.assignedSignerId == _currentUserId &&
              field.label == 'Signature',
        )
        .toList(growable: false);
    if (savedFields.isEmpty) {
      setState(() => _error = 'The signature field could not be prepared.');
      return;
    }
    await _applySignatureChoice(savedFields.last, choice);
  }

  Future<void> _applySignatureChoice(
    DocuTrackerSignatureField field,
    DocuTrackerSignatureChoice choice,
  ) async {
    setState(() => _saving = true);
    final signed = await _provider.signDocumentField(
      documentId: widget.document.id!,
      fieldId: field.id,
      signatureAssetId: choice.signatureAssetId,
      imageBytes: choice.imageBytes,
      mimeType: choice.mimeType,
      sourceType: choice.sourceType,
      saveForReuse: choice.saveForReuse,
    );
    if (!mounted) return;
    if (signed == null) {
      setState(() {
        _saving = false;
        _error = _provider.builderError ?? 'Could not sign this field.';
      });
      return;
    }
    final signedField = signed.signatureFields
        .where((item) => item.id == field.id)
        .firstOrNull;
    var previewFailed = false;
    final imageBytes = signedField?.signatureImageBytes;
    if (imageBytes != null) {
      try {
        await _precacheDocumentImage(imageBytes);
      } catch (_) {
        // Signing succeeded on the server even if its preview cannot decode.
        previewFailed = true;
      }
    }
    if (!mounted) return;
    _replaceFromServer(signed);
    if (signedField != null) await _focusSignatureField(signedField);
    if (!mounted) return;
    if (previewFailed) {
      setState(() {
        _error =
            'Signature saved, but its image could not be displayed. '
            'Reload the document to try again.';
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          field.isSigned
              ? 'Signature replaced. The change was recorded in history.'
              : 'Signature added and locked.',
        ),
      ),
    );
  }

  void _updateField(
    DocuTrackerSignatureField field, {
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    final canMoveSigned = field.isSigned && field.canSign;
    if (!canMoveSigned && (!_canEditLayout || field.isSigned)) return;
    final index = _signatureFields.indexWhere((item) => item.id == field.id);
    if (index < 0) return;
    final nextWidth = (width ?? field.width).clamp(0.08, 1.0);
    final nextHeight = (height ?? field.height).clamp(0.05, 1.0);
    final nextX = (x ?? field.x).clamp(0.0, 1 - nextWidth);
    final nextY = (y ?? field.y).clamp(0.0, 1 - nextHeight);
    setState(() {
      _signatureFields[index] = field.copyWith(
        x: nextX,
        y: nextY,
        width: nextWidth,
        height: nextHeight,
      );
      _selectedFieldId = field.id;
      if (!canMoveSigned) _dirty = true;
    });
  }

  void _moveFieldBy(DocuTrackerSignatureField field, Offset delta) {
    final index = _signatureFields.indexWhere((item) => item.id == field.id);
    if (index < 0) return;
    final current = _signatureFields[index];
    _updateField(
      current,
      x: current.x + delta.dx / _paperWidth,
      y: current.y + delta.dy / _paperHeight,
    );
  }

  void _startSignedFieldDrag(DocuTrackerSignatureField field) {
    if (!field.isSigned || !field.canSign || _saving) return;
    final current = _signatureFields.firstWhere((item) => item.id == field.id);
    setState(() {
      _draggingSignedFieldId = field.id;
      _signedDragOriginX = current.x;
      _signedDragOriginY = current.y;
      _selectedFieldId = field.id;
      _error = null;
    });
  }

  Future<void> _finishSignedFieldDrag(String fieldId) async {
    if (_draggingSignedFieldId != fieldId) return;
    final originX = _signedDragOriginX;
    final originY = _signedDragOriginY;
    _draggingSignedFieldId = null;
    _signedDragOriginX = null;
    _signedDragOriginY = null;
    final index = _signatureFields.indexWhere((item) => item.id == fieldId);
    if (index < 0 || originX == null || originY == null) return;
    final field = _signatureFields[index];
    if (field.x == originX && field.y == originY) return;

    setState(() => _saving = true);
    final moved = await _provider.moveSignedDocumentField(
      documentId: widget.document.id!,
      fieldId: fieldId,
      x: field.x,
      y: field.y,
    );
    if (!mounted) return;
    if (moved == null) {
      final restoreIndex = _signatureFields.indexWhere(
        (item) => item.id == fieldId,
      );
      setState(() {
        if (restoreIndex >= 0) {
          _signatureFields[restoreIndex] = _signatureFields[restoreIndex]
              .copyWith(x: originX, y: originY);
        }
        _saving = false;
        _error =
            _provider.builderError ?? 'Could not save the signature position.';
      });
      return;
    }
    _replaceFromServer(moved);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signature position saved.')));
  }

  void _cancelSignedFieldDrag(String fieldId) {
    if (_draggingSignedFieldId != fieldId) return;
    final originX = _signedDragOriginX;
    final originY = _signedDragOriginY;
    _draggingSignedFieldId = null;
    _signedDragOriginX = null;
    _signedDragOriginY = null;
    final index = _signatureFields.indexWhere((item) => item.id == fieldId);
    if (index < 0 || originX == null || originY == null) return;
    setState(() {
      _signatureFields[index] = _signatureFields[index].copyWith(
        x: originX,
        y: originY,
      );
    });
  }

  ({double x, double y}) _nextSignaturePlacement() {
    const width = 0.30;
    const height = 0.12;
    const candidates = <({double x, double y})>[
      (x: 0.58, y: 0.72),
      (x: 0.18, y: 0.72),
      (x: 0.58, y: 0.54),
      (x: 0.18, y: 0.54),
      (x: 0.58, y: 0.36),
      (x: 0.18, y: 0.36),
      (x: 0.58, y: 0.18),
      (x: 0.18, y: 0.18),
    ];
    final pageFields = _signatureFields.where(
      (field) => field.pageNumber == _activePage + 1,
    );
    for (final candidate in candidates) {
      final overlaps = pageFields.any(
        (field) =>
            candidate.x < field.x + field.width &&
            candidate.x + width > field.x &&
            candidate.y < field.y + field.height &&
            candidate.y + height > field.y,
      );
      if (!overlaps) return candidate;
    }
    return (x: 0.35, y: 0.04);
  }

  void _deleteSignatureField(DocuTrackerSignatureField field) {
    if (!_canEditLayout || field.isSigned || _busy) return;
    setState(() {
      _signatureFields.removeWhere((item) => item.id == field.id);
      if (_selectedFieldId == field.id) _selectedFieldId = null;
      _dirty = true;
    });
  }

  Future<void> _goToPage(int pageIndex, {String? selectedFieldId}) async {
    if (_busy || pageIndex < 0 || pageIndex >= _pages.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activePage = pageIndex;
      _selectedFieldId = selectedFieldId;
    });
  }

  Future<void> _focusSignatureField(DocuTrackerSignatureField field) async {
    await _goToPage(field.pageNumber - 1, selectedFieldId: field.id);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _busy) return;
    final page = _pages[_activePage];
    if (page.canvasScroll.hasClients) {
      final target = field.y * _paperHeight * _renderScale - 48;
      page.canvasScroll.jumpTo(
        target.clamp(0.0, page.canvasScroll.position.maxScrollExtent),
      );
    }
    if (page.horizontalScroll.hasClients) {
      final target = field.x * _paperWidth * _renderScale - 24;
      page.horizontalScroll.jumpTo(
        target.clamp(0.0, page.horizontalScroll.position.maxScrollExtent),
      );
    }
  }

  void _toggleSignatures() {
    if (_busy) return;
    if (MediaQuery.sizeOf(context).width >= _signaturePanelBreakpoint) {
      setState(() => _signaturePanelOpen = !_signaturePanelOpen);
    } else {
      unawaited(_showSignatureFieldsSheet());
    }
  }

  Future<void> _showSignatureFieldsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) action();
          });
        }

        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DocuTrackerSignatureFieldsPanel(
              fields: _signatureFields,
              activePage: _activePage + 1,
              selectedFieldId: _selectedFieldId,
              canEditLayout: _canEditLayout,
              isBusy: _busy,
              onAddField: _canEditLayout
                  ? () => closeThen(() => unawaited(_addSignatureField()))
                  : null,
              onInsertOwn: _canEditLayout
                  ? () => closeThen(() => unawaited(_insertOwnSignature()))
                  : null,
              onClose: () => Navigator.of(sheetContext).pop(),
              onSelect: (field) =>
                  closeThen(() => unawaited(_focusSignatureField(field))),
              onSign: (field) => closeThen(() => unawaited(_signField(field))),
              onDelete: (field) =>
                  closeThen(() => _deleteSignatureField(field)),
            ),
          ),
        );
      },
    );
  }

  Future<void> _precacheDocumentImage(Uint8List bytes) async {
    Object? imageError;
    await precacheImage(
      MemoryImage(bytes),
      context,
      onError: (error, _) => imageError = error,
    );
    if (imageError != null) throw StateError('An image could not be rendered.');
  }

  Future<Uint8List> _buildPdf() async {
    if (_busy || _pages.isEmpty) throw StateError('Document is busy.');
    final selectedField = _selectedFieldId;
    final selections = _pages.map((page) => page.controller.selection).toList();
    final readOnly = _pages.map((page) => page.controller.readOnly).toList();
    final focusedPage = _pages.indexWhere((page) => page.focusNode.hasFocus);
    final offsets = _pages
        .map(
          (page) => (
            x: page.horizontalScroll.hasClients
                ? page.horizontalScroll.offset
                : 0.0,
            y: page.canvasScroll.hasClients ? page.canvasScroll.offset : 0.0,
          ),
        )
        .toList();
    setState(() {
      _exporting = true;
      _selectedFieldId = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      for (final page in _pages) {
        page.controller.readOnly = true;
      }
      if (_formatVersion >= _letterheadFormatVersion) {
        final background =
            _letterheadBackgroundBytes ??
            await DocuTrackerPrintableTemplate.loadA4LetterheadPng();
        if (!mounted) throw StateError('Document was closed.');
        if (background != null) {
          await _precacheDocumentImage(background);
          _letterheadBackgroundBytes = background;
        }
      }
      if (!mounted) throw StateError('Document was closed.');
      for (final field in _signatureFields) {
        final bytes = field.signatureImageBytes;
        if (bytes != null && bytes.isNotEmpty) {
          await _precacheDocumentImage(bytes);
          if (!mounted) throw StateError('Document was closed.');
        }
      }
      final pageImages = <Uint8List>[];
      for (var index = 0; index < _pages.length; index++) {
        if (!mounted) throw StateError('Document was closed.');
        setState(() => _capturePage = index);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) throw StateError('Document was closed.');
        final boundary =
            _pageKeys[index].currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('Page is not ready.');
        final captured = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await captured.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) throw StateError('Page could not be rendered.');
          pageImages.add(data.buffer.asUint8List());
        } finally {
          captured.dispose();
        }
      }
      return await buildDocuTrackerA4Pdf(pageImages);
    } finally {
      if (mounted) {
        for (var i = 0; i < _pages.length; i++) {
          _pages[i].controller.readOnly = readOnly[i];
          _pages[i].controller.updateSelection(
            selections[i],
            quill.ChangeSource.local,
          );
        }
        setState(() {
          _capturePage = null;
          _selectedFieldId = selectedField;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          final page = _pages[_activePage];
          if (page.canvasScroll.hasClients) {
            page.canvasScroll.jumpTo(
              offsets[_activePage].y.clamp(
                0.0,
                page.canvasScroll.position.maxScrollExtent,
              ),
            );
          }
          if (page.horizontalScroll.hasClients) {
            page.horizontalScroll.jumpTo(
              offsets[_activePage].x.clamp(
                0.0,
                page.horizontalScroll.position.maxScrollExtent,
              ),
            );
          }
          setState(() => _exporting = false);
          if (focusedPage >= 0) _pages[focusedPage].focusNode.requestFocus();
        }
      }
    }
  }

  Future<void> _printDocument() async {
    if (_busy) return;
    try {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not print the document. Please try again.',
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_busy) return;
    try {
      final bytes = await _buildPdf();
      final safeName = widget.document.title
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${safeName.isEmpty ? 'document' : safeName}.pdf',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not export the PDF. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Document'),
        ),
        body: DocuTrackerErrorBanner(
          message: _error ?? 'Document is unavailable.',
        ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    final status = _saving
        ? 'Saving...'
        : _dirty
        ? 'Unsaved changes'
        : 'Saved';
    return Localizations.override(
      context: context,
      delegates: const <LocalizationsDelegate<dynamic>>[
        quill.FlutterQuillLocalizations.delegate,
      ],
      child: PopScope(
        canPop: !_exporting,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _exporting,
              child: Scaffold(
                backgroundColor: DocuTrackerTokens.canvasOf(context),
                appBar: AppBar(
                  leading: BackButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.maybePop(context),
                  ),
                  titleSpacing: 0,
                  title: Tooltip(
                    message: widget.document.title,
                    child: Text(
                      widget.document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  actions: [
                    if (_canEditLayout) ...[
                      if (!compact)
                        Text(
                          status,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      SizedBox(
                        width: compact ? 56 : 48,
                        child: Tooltip(
                          message: 'Save — $status',
                          child: InkWell(
                            onTap: _busy || !_dirty ? null : _save,
                            child: Semantics(
                              button: true,
                              enabled: !_busy && _dirty,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_saving)
                                    const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    Icon(
                                      _dirty
                                          ? Icons.save_outlined
                                          : Icons.check_circle_outline,
                                    ),
                                  if (compact)
                                    Text(
                                      _saving
                                          ? 'Saving'
                                          : _dirty
                                          ? 'Unsaved'
                                          : 'Saved',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Signatures',
                      onPressed: _busy ? null : _toggleSignatures,
                      isSelected: _signaturePanelOpen,
                      icon: const Icon(Icons.draw_outlined),
                    ),
                    IconButton(
                      tooltip: 'Print',
                      onPressed: _busy ? null : _printDocument,
                      icon: const Icon(Icons.print_outlined),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      enabled: !_busy,
                      onOpened: () => _formatSelection =
                          _pages[_activePage].controller.selection,
                      onSelected: _handleMoreAction,
                      itemBuilder: (_) => [
                        if (_canEditLayout)
                          const PopupMenuItem(
                            value: 'format',
                            child: Text('Format'),
                          ),
                        if (_canEditLayout && _pages.length < 50)
                          const PopupMenuItem(
                            value: 'add',
                            child: Text('Add Page'),
                          ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('Export PDF'),
                        ),
                        const PopupMenuItem(value: 'zoom', child: Text('Zoom')),
                      ],
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: DocuTrackerErrorBanner(message: _error!),
                      ),
                    Expanded(child: _buildWorkspace()),
                    _buildCanvasControls(),
                  ],
                ),
              ),
            ),
            if (_exporting) ...[
              const Positioned.fill(
                child: ModalBarrier(
                  key: ValueKey('builder-export-barrier'),
                  dismissible: false,
                  color: Color(0x88000000),
                ),
              ),
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _capturePage == null
                              ? 'Preparing PDF...'
                              : 'Preparing page ${_capturePage! + 1} of ${_pages.length}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleMoreAction(String action) {
    switch (action) {
      case 'format':
        unawaited(_showFormatTools());
      case 'add':
        _addPage();
      case 'export':
        unawaited(_exportPdf());
      case 'zoom':
        unawaited(_showZoomTools());
    }
  }

  Future<void> _showToolSurface(Widget child) async {
    if (MediaQuery.sizeOf(context).width < 600) {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => Dialog(
          alignment: Alignment.topRight,
          insetPadding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showFormatTools() async {
    final controller = _pages[_activePage].controller;
    final selection = _formatSelection ?? controller.selection;
    controller.updateSelection(selection, quill.ChangeSource.local);
    await _showToolSurface(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolHeading('Format'),
          const SizedBox(height: 8),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _toolHeading(String title) => Builder(
    // Resolve the navigator inside the tool route, not the builder's navigator.
    builder: (toolContext) => Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: 'Close $title',
          onPressed: () => Navigator.of(toolContext).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Future<void> _showZoomTools() async {
    await _showToolSurface(
      StatefulBuilder(
        builder: (context, updateTools) {
          void update(VoidCallback change) {
            setState(change);
            updateTools(() {});
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toolHeading('Zoom'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => update(() {
                      _fitWidth = false;
                      _zoom = 1;
                    }),
                    child: const Text('Fit page'),
                  ),
                  TextButton(
                    onPressed: () => update(() {
                      _fitWidth = true;
                      _zoom = 1;
                    }),
                    child: const Text('Fit width'),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: _zoom <= 0.5
                        ? null
                        : () => update(
                            () => _zoom = (_zoom - 0.1).clamp(0.5, 3.0),
                          ),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  Expanded(
                    child: Text(
                      '${(_zoom * 100).round()}% of ${_fitWidth ? 'page width' : 'page fit'}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: _zoom >= 3
                        ? null
                        : () => update(
                            () => _zoom = (_zoom + 0.1).clamp(0.5, 3.0),
                          ),
                    icon: const Icon(Icons.zoom_in),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPanel =
            _signaturePanelOpen &&
            constraints.maxWidth >= _signaturePanelBreakpoint;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildDocumentCanvas()),
            if (showPanel)
              SizedBox(
                width: 336,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: DocuTrackerSignatureFieldsPanel(
                    fields: _signatureFields,
                    activePage: _activePage + 1,
                    selectedFieldId: _selectedFieldId,
                    canEditLayout: _canEditLayout,
                    isBusy: _busy,
                    onClose: () => setState(() => _signaturePanelOpen = false),
                    onAddField: _canEditLayout
                        ? () => unawaited(_addSignatureField())
                        : null,
                    onInsertOwn: _canEditLayout
                        ? () => unawaited(_insertOwnSignature())
                        : null,
                    onSelect: (field) => unawaited(_focusSignatureField(field)),
                    onSign: (field) => unawaited(_signField(field)),
                    onDelete: _deleteSignatureField,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDocumentCanvas() {
    final index = _capturePage ?? _activePage;
    final page = _pages[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthFit = math.max(
          0.01,
          (constraints.maxWidth - 24) / _paperWidth,
        );
        final heightFit = math.max(
          0.01,
          (constraints.maxHeight - 24) / _paperHeight,
        );
        final scale =
            (_fitWidth ? widthFit : math.min(widthFit, heightFit)) * _zoom;
        _renderScale = scale;
        return SingleChildScrollView(
          key: ValueKey('canvas-$index'),
          controller: page.canvasScroll,
          child: SingleChildScrollView(
            controller: page.horizontalScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: constraints.maxHeight,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildPage(index, scale),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCanvasControls() {
    return SafeArea(
      top: false,
      child: Material(
        color: DocuTrackerTokens.surfaceOf(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: !_busy && _activePage > 0
                  ? () => _goToPage(_activePage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            PopupMenuButton<int>(
              tooltip: 'Choose page',
              enabled: !_busy,
              onSelected: (index) => unawaited(_goToPage(index)),
              itemBuilder: (_) => List.generate(
                _pages.length,
                (index) => PopupMenuItem(
                  value: index,
                  child: Text('Page ${index + 1}'),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text('Page ${_activePage + 1} of ${_pages.length}'),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: !_busy && _activePage < _pages.length - 1
                  ? () => _goToPage(_activePage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final enabled = _canEditLayout && !_busy;
    final controller = _pages[_activePage].controller;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _FormatButton(
          tooltip: 'Bold',
          icon: Icons.format_bold,
          enabled: enabled,
          onPressed: () => _toggle(controller, quill.Attribute.bold),
        ),
        _FormatButton(
          tooltip: 'Italic',
          icon: Icons.format_italic,
          enabled: enabled,
          onPressed: () => _toggle(controller, quill.Attribute.italic),
        ),
        _FormatButton(
          tooltip: 'Underline',
          icon: Icons.format_underline,
          enabled: enabled,
          onPressed: () => _toggle(controller, quill.Attribute.underline),
        ),
        const SizedBox(width: 8),
        _PopupFormat<int>(
          tooltip: 'Heading',
          icon: Icons.title,
          enabled: enabled,
          items: const <PopupMenuEntry<int>>[
            PopupMenuItem(value: 0, child: Text('Normal text')),
            PopupMenuItem(value: 1, child: Text('Heading 1')),
            PopupMenuItem(value: 2, child: Text('Heading 2')),
            PopupMenuItem(value: 3, child: Text('Heading 3')),
          ],
          onSelected: (level) => controller.formatSelection(
            quill.HeaderAttribute(level: level == 0 ? null : level),
          ),
        ),
        _PopupFormat<String>(
          tooltip: 'Font size',
          icon: Icons.format_size,
          enabled: enabled,
          items: const <PopupMenuEntry<String>>[
            PopupMenuItem(value: '12', child: Text('12 pt')),
            PopupMenuItem(value: '14', child: Text('14 pt')),
            PopupMenuItem(value: '16', child: Text('16 pt')),
            PopupMenuItem(value: '18', child: Text('18 pt')),
            PopupMenuItem(value: '24', child: Text('24 pt')),
          ],
          onSelected: (size) =>
              controller.formatSelection(quill.SizeAttribute(size)),
        ),
        const SizedBox(width: 8),
        _FormatButton(
          tooltip: 'Align left',
          icon: Icons.format_align_left,
          enabled: enabled,
          onPressed: () =>
              controller.formatSelection(const quill.AlignAttribute(null)),
        ),
        _FormatButton(
          tooltip: 'Align center',
          icon: Icons.format_align_center,
          enabled: enabled,
          onPressed: () =>
              controller.formatSelection(const quill.AlignAttribute('center')),
        ),
        _FormatButton(
          tooltip: 'Align right',
          icon: Icons.format_align_right,
          enabled: enabled,
          onPressed: () =>
              controller.formatSelection(const quill.AlignAttribute('right')),
        ),
        _FormatButton(
          tooltip: 'Bulleted list',
          icon: Icons.format_list_bulleted,
          enabled: enabled,
          onPressed: () =>
              _toggle(controller, const quill.ListAttribute('bullet')),
        ),
        _FormatButton(
          tooltip: 'Numbered list',
          icon: Icons.format_list_numbered,
          enabled: enabled,
          onPressed: () =>
              _toggle(controller, const quill.ListAttribute('ordered')),
        ),
      ],
    );
  }

  void _toggle(quill.QuillController controller, quill.Attribute attribute) {
    final current = controller.getSelectionStyle().attributes[attribute.key];
    controller.formatSelection(
      current == null ? attribute : quill.Attribute.clone(attribute, null),
    );
    setState(() {});
  }

  Widget _buildPage(int index, double scale) {
    final page = _pages[index];
    final fields = _signatureFields
        .where((field) => field.pageNumber == index + 1)
        .toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _paperWidth * scale,
          height: _paperHeight * scale,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _paperWidth,
              height: _paperHeight,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: RepaintBoundary(
                  key: _pageKeys[index],
                  child: Container(
                    width: _paperWidth,
                    height: _paperHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: _exporting
                          ? null
                          : Border.all(color: const Color(0xFFD7DCE3)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: _formatVersion >= _letterheadFormatVersion
                              ? DocuTrackerPrintablePageFrame(
                                  documentTitle: widget.document.title,
                                  letterheadImageBytes:
                                      _letterheadBackgroundBytes,
                                  child: _buildPageEditor(page),
                                )
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    _horizontalMargin,
                                    _verticalMargin,
                                    _horizontalMargin,
                                    _verticalMargin,
                                  ),
                                  child: _buildPageEditor(page),
                                ),
                        ),
                        for (final field in fields) _buildSignatureField(field),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageEditor(_EditorPage page) {
    return quill.QuillEditor.basic(
      key: ObjectKey(page),
      controller: page.controller,
      focusNode: page.focusNode,
      scrollController: page.scrollController,
      config: quill.QuillEditorConfig(
        embedBuilders: [
          DocuTrackerPurchaseItemsEmbedBuilder(
            editable: _canEditLayout && !_busy,
          ),
        ],
        scrollable: false,
        expands: true,
        padding: EdgeInsets.zero,
        autoFocus: false,
        placeholder: _canEditLayout && !_exporting
            ? 'Start typing your document…'
            : null,
        enableInteractiveSelection: true,
      ),
    );
  }

  Widget _buildSignatureField(DocuTrackerSignatureField field) {
    final selected = _selectedFieldId == field.id;
    final editable = !_exporting && _canEditLayout && !field.isSigned;
    final canMoveSigned = !_exporting && field.isSigned && field.canSign;
    final movable = !_saving && (editable || canMoveSigned);
    final signable = !_exporting && !_saving && field.canSign;
    final rect = docuTrackerSignatureRect(
      field,
      const Size(_paperWidth, _paperHeight),
    );
    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (signable) {
            _signField(field);
          } else if (editable) {
            setState(() => _selectedFieldId = field.id);
          }
        },
        onPanStart: canMoveSigned ? (_) => _startSignedFieldDrag(field) : null,
        onPanUpdate: movable
            ? (details) => _moveFieldBy(field, details.delta)
            : null,
        onPanEnd: canMoveSigned
            ? (_) => unawaited(_finishSignedFieldDrag(field.id))
            : null,
        onPanCancel: canMoveSigned
            ? () => _cancelSignedFieldDrag(field.id)
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: field.isSigned
                      // A signed field overlays the document like ink, not a
                      // white card that obscures its name/designation lines.
                      ? Colors.transparent
                      : const Color(0xFFFFF7ED).withValues(alpha: 0.94),
                  border: Border.all(
                    color: _exporting && field.isSigned
                        ? Colors.transparent
                        : selected
                        ? DocuTrackerTokens.brand
                        : field.isSigned
                        ? const Color(0xFF15803D)
                        : const Color(0xFFF59E0B),
                    width: selected ? 2 : 1.2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DocuTrackerSignatureFieldVisual(
                  field: field,
                  signable: signable,
                  exportMode: _exporting,
                ),
              ),
            ),
            if (editable && selected)
              Positioned(
                right: -8,
                bottom: -8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => _updateField(
                    field,
                    width: field.width + details.delta.dx / _paperWidth,
                    height: field.height + details.delta.dy / _paperHeight,
                  ),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: DocuTrackerTokens.brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      size: 11,
                      color: Colors.white,
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

class _EditorPage {
  _EditorPage({required this.controller});

  final quill.QuillController controller;
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();
  final ScrollController canvasScroll = ScrollController();
  final ScrollController horizontalScroll = ScrollController();
  StreamSubscription<dynamic>? changeSubscription;

  void dispose() {
    changeSubscription?.cancel();
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
    canvasScroll.dispose();
    horizontalScroll.dispose();
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}

class _PopupFormat<T> extends StatelessWidget {
  const _PopupFormat({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.items,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled,
      itemBuilder: (_) => items,
      onSelected: onSelected,
      icon: Icon(icon),
    );
  }
}
