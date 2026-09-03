import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_field_visual.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_fields_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_pdf_export.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_geometry.dart';

class DocuTrackerDocumentBuilderScreen extends StatefulWidget {
  const DocuTrackerDocumentBuilderScreen({super.key, required this.document});

  final DocuTrackerDocument document;

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

  final EmployeeDirectoryLookup _directory = EmployeeDirectoryLookup();
  final List<_EditorPage> _pages = <_EditorPage>[];
  final List<GlobalKey> _pageKeys = <GlobalKey>[];
  List<DocuTrackerSignatureField> _signatureFields =
      <DocuTrackerSignatureField>[];
  int _revision = 0;
  String _currentUserId = '';
  int _activePage = 0;
  int _localFieldCounter = 0;
  String? _selectedFieldId;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _exporting = false;
  bool _canEditLayout = false;
  bool _dirty = false;
  String? _draggingSignedFieldId;
  double? _signedDragOriginX;
  double? _signedDragOriginY;
  double _zoom = 1;

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
    final results = await Future.wait<dynamic>([
      _provider.loadDocumentBuilder(documentId),
      _directory.load(),
    ]);
    if (!mounted) return;
    final data = results.first as DocuTrackerDocumentBuilderData?;
    if (data == null) {
      setState(() {
        _loading = false;
        _error =
            _provider.builderError ?? 'Could not load the document builder.';
      });
      return;
    }
    _replaceFromServer(data);
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
        if (editorPage.focusNode.hasFocus && mounted) {
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
    if (!_canEditLayout || documentId == null || _saving) return false;
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
    if (!_canEditLayout || _pages.length >= 50) return;
    final controller = quill.QuillController.basic();
    final page = _EditorPage(controller: controller);
    final pageIndex = _pages.length;
    page.focusNode.addListener(() {
      if (page.focusNode.hasFocus && mounted) {
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => page.focusNode.requestFocus(),
    );
  }

  Future<void> _addSignatureField() async {
    if (!_canEditLayout) return;
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
    if (!field.canSign || _saving) return;
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
    if (!_canEditLayout || _currentUserId.isEmpty) return;
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
    _replaceFromServer(signed);
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

  void _deleteSelectedField() {
    if (!_canEditLayout || _selectedFieldId == null) return;
    final field = _signatureFields
        .cast<DocuTrackerSignatureField?>()
        .firstWhere((item) => item?.id == _selectedFieldId, orElse: () => null);
    if (field == null) return;
    _deleteSignatureField(field);
  }

  void _deleteSignatureField(DocuTrackerSignatureField field) {
    if (!_canEditLayout || field.isSigned) return;
    setState(() {
      _signatureFields.removeWhere((item) => item.id == field.id);
      if (_selectedFieldId == field.id) _selectedFieldId = null;
      _dirty = true;
    });
  }

  Future<void> _goToPage(int pageIndex, {String? selectedFieldId}) async {
    if (pageIndex < 0 || pageIndex >= _pages.length) return;
    setState(() {
      _activePage = pageIndex;
      _selectedFieldId = selectedFieldId;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final pageContext = _pageKeys[pageIndex].currentContext;
    if (pageContext == null || !pageContext.mounted) return;
    await Scrollable.ensureVisible(
      pageContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  Future<void> _focusSignatureField(DocuTrackerSignatureField field) =>
      _goToPage(field.pageNumber - 1, selectedFieldId: field.id);

  void _changeZoom(double change) {
    final nextZoom = (_zoom + change).clamp(0.6, 1.0);
    if (nextZoom == _zoom) return;
    setState(() => _zoom = nextZoom);
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
              isBusy: _saving,
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

  Future<Uint8List> _buildPdf() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _exporting = true;
      _selectedFieldId = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    final pageImages = <Uint8List>[];
    for (final key in _pageKeys) {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('A document page is not ready to export.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('A document page could not be rendered.');
      }
      pageImages.add(data.buffer.asUint8List());
    }
    final bytes = await buildDocuTrackerA4Pdf(pageImages);
    if (mounted) setState(() => _exporting = false);
    return bytes;
  }

  Future<void> _printDocument() async {
    try {
      await Printing.layoutPdf(onLayout: (_) => _buildPdf());
    } catch (error) {
      if (mounted) setState(() => _error = 'Print failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildPdf();
      final safeName = widget.document.title
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${safeName.isEmpty ? 'document' : safeName}.pdf',
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'PDF export failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Localizations.override(
      context: context,
      delegates: const <LocalizationsDelegate<dynamic>>[
        quill.FlutterQuillLocalizations.delegate,
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F3F6),
        appBar: AppBar(
          leading: const BackButton(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.document.title, overflow: TextOverflow.ellipsis),
              Text(
                _canEditLayout ? 'A4 document builder' : 'Document preview',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Print',
              onPressed: _exporting ? null : _printDocument,
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'Export PDF',
              onPressed: _exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            if (_canEditLayout)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: _saving || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _dirty
                              ? Icons.save_outlined
                              : Icons.check_circle_outline,
                        ),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : _dirty
                        ? 'Unsaved changes'
                        : 'Saved',
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DocuTrackerErrorBanner(message: _error!),
              ),
            _buildToolbar(),
            Expanded(child: _buildWorkspace()),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidePanel = constraints.maxWidth >= _signaturePanelBreakpoint;
        if (!showSidePanel) return _buildDocumentCanvas();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildDocumentCanvas()),
            SizedBox(
              width: 336,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: DocuTrackerSignatureFieldsPanel(
                  fields: _signatureFields,
                  activePage: _activePage + 1,
                  selectedFieldId: _selectedFieldId,
                  canEditLayout: _canEditLayout,
                  isBusy: _saving,
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
    return Column(
      children: [
        _buildCanvasControls(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fittedScale = ((constraints.maxWidth - 32) / _paperWidth)
                  .clamp(0.42, 1.0);
              final scale = (fittedScale * _zoom).clamp(0.30, 1.0);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                child: Column(
                  children: [
                    for (var index = 0; index < _pages.length; index++) ...[
                      _buildPage(index, scale),
                      if (index != _pages.length - 1)
                        const SizedBox(height: 24),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasControls() {
    final zoomPercent = (_zoom * 100).round();
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _activePage > 0
                      ? () => unawaited(_goToPage(_activePage - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  compact
                      ? '${_activePage + 1}/${_pages.length}'
                      : 'Page ${_activePage + 1} of ${_pages.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _activePage < _pages.length - 1
                      ? () => unawaited(_goToPage(_activePage + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: _zoom > 0.6 ? () => _changeZoom(-0.1) : null,
                  icon: const Icon(Icons.zoom_out),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '$zoomPercent%',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: _zoom < 1 ? () => _changeZoom(0.1) : null,
                  icon: const Icon(Icons.zoom_in),
                ),
                if (!compact)
                  IconButton(
                    tooltip: 'Reset zoom',
                    onPressed: _zoom == 1
                        ? null
                        : () => setState(() => _zoom = 1),
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    final enabled = _canEditLayout && _pages.isNotEmpty;
    final controller = _pages[_activePage].controller;
    final actionableForCurrentUser = _signatureFields
        .where((field) => field.canSign)
        .toList(growable: false);
    final pendingForCurrentUser = actionableForCurrentUser
        .where((field) => !field.isSigned)
        .toList(growable: false);
    final signedForCurrentUser = actionableForCurrentUser
        .where((field) => field.isSigned)
        .toList(growable: false);
    DocuTrackerSignatureField? toolbarField;
    for (final field in pendingForCurrentUser) {
      if (field.pageNumber == _activePage + 1) {
        toolbarField = field;
        break;
      }
    }
    toolbarField ??= pendingForCurrentUser.isEmpty
        ? null
        : pendingForCurrentUser.first;
    if (toolbarField == null) {
      for (final field in signedForCurrentUser) {
        if (field.pageNumber == _activePage + 1) {
          toolbarField = field;
          break;
        }
      }
    }
    toolbarField ??= signedForCurrentUser.isEmpty
        ? null
        : signedForCurrentUser.first;
    final selectedField = _signatureFields
        .cast<DocuTrackerSignatureField?>()
        .firstWhere(
          (field) => field?.id == _selectedFieldId,
          orElse: () => null,
        );
    final canDeleteSelected =
        enabled && selectedField != null && !selectedField.isSigned;
    final showSignatureFieldsButton =
        MediaQuery.sizeOf(context).width < _signaturePanelBreakpoint;
    return Material(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
                    onPressed: () =>
                        _toggle(controller, quill.Attribute.italic),
                  ),
                  _FormatButton(
                    tooltip: 'Underline',
                    icon: Icons.format_underline,
                    enabled: enabled,
                    onPressed: () =>
                        _toggle(controller, quill.Attribute.underline),
                  ),
                  const VerticalDivider(),
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
                  const VerticalDivider(),
                  _FormatButton(
                    tooltip: 'Align left',
                    icon: Icons.format_align_left,
                    enabled: enabled,
                    onPressed: () => controller.formatSelection(
                      const quill.AlignAttribute(null),
                    ),
                  ),
                  _FormatButton(
                    tooltip: 'Align center',
                    icon: Icons.format_align_center,
                    enabled: enabled,
                    onPressed: () => controller.formatSelection(
                      const quill.AlignAttribute('center'),
                    ),
                  ),
                  _FormatButton(
                    tooltip: 'Align right',
                    icon: Icons.format_align_right,
                    enabled: enabled,
                    onPressed: () => controller.formatSelection(
                      const quill.AlignAttribute('right'),
                    ),
                  ),
                  _FormatButton(
                    tooltip: 'Bulleted list',
                    icon: Icons.format_list_bulleted,
                    enabled: enabled,
                    onPressed: () => _toggle(
                      controller,
                      const quill.ListAttribute('bullet'),
                    ),
                  ),
                  _FormatButton(
                    tooltip: 'Numbered list',
                    icon: Icons.format_list_numbered,
                    enabled: enabled,
                    onPressed: () => _toggle(
                      controller,
                      const quill.ListAttribute('ordered'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Text(
              'Document actions',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: DocuTrackerTokens.textMutedOf(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: enabled ? _addPage : null,
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text('Add Page (${_pages.length})'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: DocuTrackerTokens.brandSoft,
                    foregroundColor: DocuTrackerTokens.brandDark,
                  ),
                  onPressed: enabled ? _addSignatureField : null,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add Signature Field'),
                ),
                if (showSignatureFieldsButton)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _showSignatureFieldsSheet,
                    icon: const Icon(Icons.view_sidebar_outlined),
                    label: Text(
                      'Signature Fields (${_signatureFields.length})',
                    ),
                  ),
                FilledButton.icon(
                  style: DocuTrackerTokens.brandFilledStyle(),
                  onPressed: _saving
                      ? null
                      : toolbarField != null
                      ? () => _signField(toolbarField!)
                      : enabled
                      ? _insertOwnSignature
                      : null,
                  icon: const Icon(Icons.gesture_rounded),
                  label: Text(
                    toolbarField?.isSigned == true
                        ? 'Change E-Signature'
                        : 'Insert E-Signature',
                  ),
                ),
                if (canDeleteSelected)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      foregroundColor: const Color(0xFFB91C1C),
                    ),
                    onPressed: _deleteSelectedField,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete Field'),
                  ),
              ],
            ),
          ],
        ),
      ),
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
      children: [
        Text(
          'Page ${index + 1}',
          style: const TextStyle(
            color: DocuTrackerTokens.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: _paperWidth * scale,
          height: _paperHeight * scale,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
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
                    border: Border.all(color: const Color(0xFFD7DCE3)),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            _horizontalMargin,
                            _verticalMargin,
                            _horizontalMargin,
                            _verticalMargin,
                          ),
                          child: quill.QuillEditor.basic(
                            controller: page.controller,
                            focusNode: page.focusNode,
                            scrollController: page.scrollController,
                            config: quill.QuillEditorConfig(
                              scrollable: false,
                              expands: true,
                              padding: EdgeInsets.zero,
                              autoFocus: false,
                              placeholder: _canEditLayout
                                  ? 'Start typing your document…'
                                  : null,
                              enableInteractiveSelection: true,
                            ),
                          ),
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
      ],
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
                      ? Colors.white.withValues(alpha: 0.92)
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
  StreamSubscription<dynamic>? changeSubscription;

  void dispose() {
    changeSubscription?.cancel();
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
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
