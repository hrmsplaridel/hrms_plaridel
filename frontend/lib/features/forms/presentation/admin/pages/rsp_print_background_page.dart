import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/forms/data/form_print_template_repo.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

/// Paper families that already exist in [FormPrintCatalog].
/// Landscape is offered only when that catalog has a matching size.
class RspPrintPaperChoice {
  const RspPrintPaperChoice({
    required this.familyId,
    required this.label,
    required this.portraitId,
    this.landscapeId,
  });

  final String familyId;
  final String label;
  final String portraitId;
  final String? landscapeId;

  bool get supportsLandscape => landscapeId != null;
}

const rspPrintPaperChoices = <RspPrintPaperChoice>[
  RspPrintPaperChoice(
    familyId: 'a4',
    label: 'A4',
    portraitId: 'a4',
    landscapeId: 'a4_landscape',
  ),
  RspPrintPaperChoice(
    familyId: 'letter',
    label: 'Short (8.5 × 11)',
    portraitId: 'letter',
    landscapeId: 'letter_landscape',
  ),
  RspPrintPaperChoice(
    familyId: 'long_13',
    label: 'Long (8.5 × 13)',
    portraitId: 'long_13',
    landscapeId: 'long_13_landscape',
  ),
];

const _legacyLongIds = {'long_14': 'long_13', 'long_landscape': 'long_13_landscape'};

RspPrintPaperChoice rspPrintPaperChoiceForId(String paperSizeId) {
  paperSizeId = _legacyLongIds[paperSizeId] ?? paperSizeId;
  for (final choice in rspPrintPaperChoices) {
    if (choice.portraitId == paperSizeId || choice.landscapeId == paperSizeId) {
      return choice;
    }
  }
  return rspPrintPaperChoices[1];
}

String resolveRspPrintPaperId({
  required String familyId,
  required bool landscape,
}) {
  final choice = rspPrintPaperChoices.firstWhere(
    (choice) => choice.familyId == familyId,
    orElse: () => rspPrintPaperChoices[1],
  );
  if (landscape && choice.landscapeId != null) return choice.landscapeId!;
  return choice.portraitId;
}

bool rspPrintPaperIsLandscape(String paperSizeId) {
  paperSizeId = _legacyLongIds[paperSizeId] ?? paperSizeId;
  final choice = rspPrintPaperChoiceForId(paperSizeId);
  return choice.landscapeId == paperSizeId;
}

String rspPrintDimensionLabel(FormPrintPaperSize size) {
  if (size.id == 'a4') return '210 × 297 mm';
  String inches(double points) {
    final value = points / 72;
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(1);
  }

  return '${inches(size.widthPt)} × ${inches(size.heightPt)} in';
}

/// Print background manager for RSP and L&D. Each module keeps its own forms.
class RspPrintBackgroundPage extends StatefulWidget {
  const RspPrintBackgroundPage({
    super.key,
    required this.onBack,
    this.module = 'rsp',
  });

  final VoidCallback onBack;

  /// `rsp` or `ld`.
  final String module;

  @override
  State<RspPrintBackgroundPage> createState() => _RspPrintBackgroundPageState();
}

class _RspPrintBackgroundPageState extends State<RspPrintBackgroundPage> {
  final _composerKey = GlobalKey();
  Uint8List? _fileBytes;
  Uint8List? _previewPng;
  String? _fileName;
  String? _formKey;
  String? _editingOriginalKey;
  String _familyId = 'letter';
  bool _landscape = false;
  bool _saving = false;
  bool _loadingList = true;
  bool _loadingEdit = false;
  String? _removingKey;
  String? _error;
  String? _successTitle;
  String? _successDetail;
  String _search = '';
  bool _fitPreview = true;
  double _zoom = 1;
  List<FormPrintTemplate> _saved = const [];
  final Map<String, Uint8List> _thumbs = {};

  String get _module => widget.module == 'ld' ? 'ld' : 'rsp';

  String get _moduleLabel => _module == 'ld' ? 'L&D' : 'RSP';

  List<FormPrintCatalogItem> get _forms => FormPrintCatalog.formsFor(_module);

  String get _paperSizeId =>
      resolveRspPrintPaperId(familyId: _familyId, landscape: _landscape);

  FormPrintPaperSize? get _paper => FormPrintCatalog.paperById(_paperSizeId);

  RspPrintPaperChoice get _choice => rspPrintPaperChoices.firstWhere(
    (choice) => choice.familyId == _familyId,
    orElse: () => rspPrintPaperChoices[1],
  );

  @override
  void initState() {
    super.initState();
    _reloadSaved();
  }

  Future<void> _reloadSaved() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final list = await FormPrintTemplateRepo.instance.list(module: _module);
      if (!mounted) return;
      setState(() {
        _saved = list;
        _loadingList = false;
      });
      _loadThumbs(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = userFacingApiError(e);
      });
    }
  }

  Future<void> _loadThumbs(List<FormPrintTemplate> list) async {
    for (final template in list) {
      final key = '${template.module}|${template.formKey}';
      if (_thumbs.containsKey(key)) continue;
      try {
        final bytes = await FormPrintTemplateRepo.instance.fetchFileBytes(
          module: template.module,
          formKey: template.formKey,
        );
        if (!mounted) return;
        if (bytes == null) continue;
        final png = await _bytesToPreviewPng(
          bytes,
          template.originalFilename ?? 'background.pdf',
        );
        if (!mounted) return;
        setState(() => _thumbs[key] = png);
      } catch (_) {}
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    await _useFile(Uint8List.fromList(bytes), file.name);
  }

  Future<void> _useFile(Uint8List bytes, String name) async {
    setState(() {
      _error = null;
      _successTitle = null;
      _successDetail = null;
      _fileBytes = bytes;
      _fileName = name;
      _previewPng = null;
      _fitPreview = true;
      _zoom = 1;
    });
    try {
      final png = await _bytesToPreviewPng(bytes, name);
      if (!mounted) return;
      setState(() => _previewPng = png);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fileBytes = null;
        _fileName = null;
        _error = 'Could not read that file. Use PDF, PNG, or JPG.';
      });
    }
  }

  Future<Uint8List> _bytesToPreviewPng(Uint8List bytes, String name) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg')) {
      return bytes;
    }
    await for (final page in Printing.raster(
      bytes,
      pages: const [0],
      dpi: 72,
    )) {
      return page.toPng();
    }
    throw StateError('empty pdf');
  }

  void _applyPaperId(String paperSizeId) {
    final choice = rspPrintPaperChoiceForId(paperSizeId);
    _familyId = choice.familyId;
    _landscape = rspPrintPaperIsLandscape(paperSizeId);
  }

  void _startNew() {
    setState(() {
      _fileBytes = null;
      _previewPng = null;
      _fileName = null;
      _formKey = null;
      _editingOriginalKey = null;
      _error = null;
      _successTitle = null;
      _successDetail = null;
      _fitPreview = true;
      _zoom = 1;
      _applyPaperId('letter');
    });
    final context = _composerKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  Future<void> _edit(FormPrintTemplate template) async {
    setState(() {
      _loadingEdit = true;
      _error = null;
      _successTitle = null;
      _successDetail = null;
    });
    try {
      final bytes = await FormPrintTemplateRepo.instance.fetchFileBytes(
        module: template.module,
        formKey: template.formKey,
      );
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _loadingEdit = false;
          _error = 'Saved background file is missing. Upload it again.';
        });
        return;
      }
      final name = template.originalFilename ?? 'background.pdf';
      final png = await _bytesToPreviewPng(bytes, name);
      if (!mounted) return;
      setState(() {
        _loadingEdit = false;
        _fileBytes = bytes;
        _fileName = name;
        _previewPng = png;
        _formKey = template.formKey;
        _editingOriginalKey = template.formKey;
        _applyPaperId(template.paperSize);
        _fitPreview = true;
        _zoom = 1;
      });
      final target = _composerKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.05,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEdit = false;
        _error = userFacingApiError(e);
      });
    }
  }

  Future<void> _confirm() async {
    final bytes = _fileBytes;
    final name = _fileName;
    final formKey = _formKey;
    if (bytes == null || name == null || formKey == null) return;
    final previousKey = _editingOriginalKey;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FormPrintTemplateRepo.instance.save(
        module: _module,
        formKey: formKey,
        paperSize: _paperSizeId,
        bytes: bytes,
        fileName: name,
      );
      FormPdf.invalidateCustomTemplate(_module, formKey);
      if (previousKey != null && previousKey != formKey) {
        await FormPrintTemplateRepo.instance.delete(
          module: _module,
          formKey: previousKey,
        );
        FormPdf.invalidateCustomTemplate(_module, previousKey);
        _thumbs.remove('$_module|$previousKey');
      }
      _thumbs['$_module|$formKey'] = _previewPng ?? bytes;
      if (!mounted) return;
      final title = FormPrintCatalog.titleFor(_module, formKey);
      setState(() {
        _saving = false;
        _fileBytes = null;
        _previewPng = null;
        _fileName = null;
        _formKey = null;
        _editingOriginalKey = null;
        _successTitle = 'Background saved successfully';
        _successDetail =
            '$title will automatically use this background when printing.';
      });
      await _reloadSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingApiError(e);
      });
    }
  }

  Future<void> _removeSaved(FormPrintTemplate template) async {
    final title = FormPrintCatalog.titleFor(template.module, template.formKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove print background?'),
        content: const Text(
          'This background will no longer be automatically applied to the assigned form.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = '${template.module}|${template.formKey}';
    setState(() => _removingKey = key);
    try {
      await FormPrintTemplateRepo.instance.delete(
        module: template.module,
        formKey: template.formKey,
      );
      FormPdf.invalidateCustomTemplate(template.module, template.formKey);
      _thumbs.remove(key);
      if (_editingOriginalKey == template.formKey) {
        _fileBytes = null;
        _previewPng = null;
        _fileName = null;
        _formKey = null;
        _editingOriginalKey = null;
      }
      await _reloadSaved();
      if (!mounted) return;
      setState(() => _removingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Background removed for $title.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingKey = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    }
  }

  Future<void> _previewSaved(FormPrintTemplate template) async {
    final key = '${template.module}|${template.formKey}';
    var png = _thumbs[key];
    if (png == null) {
      final bytes = await FormPrintTemplateRepo.instance.fetchFileBytes(
        module: template.module,
        formKey: template.formKey,
      );
      if (bytes == null || !mounted) return;
      png = await _bytesToPreviewPng(
        bytes,
        template.originalFilename ?? 'background.pdf',
      );
      if (!mounted) return;
      setState(() => _thumbs[key] = png!);
    }
    if (!mounted) return;
    final paper = FormPrintCatalog.paperById(template.paperSize);
    final title = FormPrintCatalog.titleFor(template.module, template.formKey);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Preview — $title',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(child: _PageFrame(png: png, paper: paper, fit: true)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _activeStep {
    if (_fileBytes == null) return 0;
    if (_formKey == null) return 1;
    return 3;
  }

  bool _stepDone(int index) {
    if (index == 0) return _fileBytes != null;
    if (index == 1 || index == 2) return _formKey != null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final query = _search.trim().toLowerCase();
    final visible = query.isEmpty
        ? _saved
        : _saved.where((template) {
            final title = FormPrintCatalog.titleFor(
              template.module,
              template.formKey,
            ).toLowerCase();
            final file = (template.originalFilename ?? '').toLowerCase();
            return title.contains(query) || file.contains(query);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Print Backgrounds',
                        style: TextStyle(
                          color: primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _moduleLabel,
                          style: const TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage and assign reusable print backgrounds for $_moduleLabel forms.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loadingList || _saving ? null : () {
                _thumbs.clear();
                _reloadSaved();
              },
              icon: _loadingList
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: primary,
                minimumSize: const Size(0, 42),
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _saving || _loadingEdit ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Background'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        if (_successTitle != null) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF166534),
            background: const Color(0xFFF0FDF4),
            border: const Color(0xFFBBF7D0),
            title: _successTitle!,
            detail: _successDetail,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFB91C1C),
            background: const Color(0xFFFEF2F2),
            border: const Color(0xFFFECACA),
            title: _error!,
          ),
        ],
        const SizedBox(height: 14),
        _savedSection(visible),
        const SizedBox(height: 14),
        KeyedSubtree(key: _composerKey, child: _composer()),
      ],
    );
  }

  Widget _savedSection(List<FormPrintTemplate> visible) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final countLabel = _saved.length == 1
        ? '1 Template'
        : '${_saved.length} Templates';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Saved Backgrounds',
                  style: TextStyle(
                    color: primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!_loadingList)
                Text(
                  countLabel,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (_saved.length >= 4) ...[
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => setState(() => _search = value),
              style: AppTheme.dashFieldTextStyle(context).copyWith(fontSize: 14),
              decoration: AppTheme.dashInputDecoration(
                context,
                hintText: 'Search saved backgrounds...',
                radius: 10,
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_loadingList)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else if (_saved.isEmpty)
            Text(
              'No backgrounds saved yet. Add one to assign it to a $_moduleLabel form.',
              style: TextStyle(color: secondary, fontSize: 13, height: 1.35),
            )
          else if (visible.isEmpty)
            Text(
              'No backgrounds match that search.',
              style: TextStyle(color: secondary, fontSize: 13),
            )
          else
            for (final template in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SavedBackgroundCard(
                  template: template,
                  thumbnail: _thumbs['${template.module}|${template.formKey}'],
                  busy: _removingKey == '${template.module}|${template.formKey}',
                  enabled: _removingKey == null && !_saving,
                  onPreview: () => _previewSaved(template),
                  onEdit: () => _edit(template),
                  onRemove: () => _removeSaved(template),
                ),
              ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _Stepper(active: _activeStep, done: _stepDone),
          ),
          const SizedBox(height: 14),
          if (_loadingEdit)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else if (_fileBytes == null)
            _dropZone()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumn = constraints.maxWidth >= 900;
                final settings = _settings(includeActions: twoColumn);
                final preview = _livePreview();
                if (!twoColumn) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      settings,
                      const SizedBox(height: 16),
                      preview,
                      const SizedBox(height: 12),
                      _actions(expand: true),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 38, child: settings),
                    const SizedBox(width: 16),
                    Expanded(flex: 62, child: preview),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _dropZone() {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: AppTheme.dashMutedSurfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _pickFile,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 240,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.upload_file_outlined,
                size: 32,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(height: 8),
              Text(
                'Upload background',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a PDF, PNG, or JPG letterhead.',
                style: TextStyle(color: secondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Choose File'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(148, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Supported: PDF • PNG • JPG',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'Use an official letterhead or blank form background.',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settings({required bool includeActions}) {
    final savedKeys = {for (final template in _saved) template.formKey};
    final paper = _paper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Background Settings',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _fileCard(),
        const SizedBox(height: 14),
        Text(
          'Assign to $_moduleLabel Form',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('rsp-form-$_formKey'),
          isExpanded: true,
          initialValue: _formKey,
          hint: const Text('Select a form'),
          decoration: AppTheme.dashInputDecoration(
            context,
            radius: 10,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: [
            for (final form in _forms)
              DropdownMenuItem(
                value: form.key,
                child: Text(
                  savedKeys.contains(form.key)
                      ? '${form.title}    ✓ Assigned'
                      : '${form.title}    Not assigned',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  final form = _forms.firstWhere((item) => item.key == value);
                  setState(() {
                    _formKey = form.key;
                    _applyPaperId(form.defaultPaperSizeId);
                  });
                },
        ),
        const SizedBox(height: 14),
        Text(
          'Page Setup',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Paper size',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('rsp-paper-$_familyId'),
          isExpanded: true,
          initialValue: _familyId,
          decoration: AppTheme.dashInputDecoration(
            context,
            radius: 10,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: [
            for (final choice in rspPrintPaperChoices)
              DropdownMenuItem(
                value: choice.familyId,
                child: Text(choice.label),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _familyId = value;
                    final choice = rspPrintPaperChoices.firstWhere(
                      (item) => item.familyId == value,
                    );
                    if (!choice.supportsLandscape) _landscape = false;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(
          'Orientation',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _OrientationButton(
              label: 'Portrait',
              selected: !_landscape,
              onTap: _saving ? null : () => setState(() => _landscape = false),
            ),
            const SizedBox(width: 8),
            _OrientationButton(
              label: 'Landscape',
              selected: _landscape,
              enabled: _choice.supportsLandscape,
              onTap: _saving || !_choice.supportsLandscape
                  ? null
                  : () => setState(() => _landscape = true),
            ),
          ],
        ),
        if (paper != null) ...[
          const SizedBox(height: 8),
          Text(
            rspPrintDimensionLabel(paper),
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (includeActions) ...[
          const SizedBox(height: 16),
          _actions(expand: false),
        ],
      ],
    );
  }

  Widget _fileCard() {
    final name = _fileName ?? 'Background';
    final lower = name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final kind = isPdf
        ? 'PDF'
        : (lower.endsWith('.png') ? 'PNG' : 'JPG');
    final bytes = _fileBytes;
    final pages = bytes == null || !isPdf ? null : _pdfPageCount(bytes);
    final meta = pages == null
        ? '$kind • ${_formatBytes(bytes?.length ?? 0)}'
        : '$kind • $pages page${pages == 1 ? '' : 's'} • ${_formatBytes(bytes?.length ?? 0)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            color: AppTheme.primaryNavy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _pickFile,
            child: const Text('Replace File'),
          ),
        ],
      ),
    );
  }

  Widget _actions({required bool expand}) {
    final save = FilledButton(
      onPressed: _saving || _formKey == null || _fileBytes == null
          ? null
          : _confirm,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        minimumSize: Size(expand ? double.infinity : 0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Save Background'),
    );
    final cancel = TextButton(
      onPressed: _saving ? null : _startNew,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.dashTextSecondaryOf(context),
        minimumSize: const Size(44, 44),
      ),
      child: const Text('Cancel'),
    );
    if (expand) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          save,
          Align(alignment: Alignment.centerLeft, child: cancel),
        ],
      );
    }
    return Row(
      children: [
        cancel,
        const Spacer(),
        save,
      ],
    );
  }

  Widget _livePreview() {
    final formTitle = _formKey == null
        ? null
        : FormPrintCatalog.titleFor(_module, _formKey!);
    final paper = _paper;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final orientation = _landscape ? 'Landscape' : 'Portrait';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formTitle == null ? 'Live Preview' : 'Preview — $formTitle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _ZoomChip(
              label: 'Fit',
              selected: _fitPreview,
              onTap: () => setState(() {
                _fitPreview = true;
                _zoom = 1;
              }),
            ),
            const SizedBox(width: 6),
            _ZoomChip(
              label: '−',
              selected: false,
              onTap: _fitPreview
                  ? null
                  : () => setState(() => _zoom = (_zoom - 0.25).clamp(0.5, 2)),
            ),
            const SizedBox(width: 6),
            _ZoomChip(
              label: _fitPreview ? '100%' : '${(_zoom * 100).round()}%',
              selected: !_fitPreview,
              onTap: () => setState(() {
                _fitPreview = false;
                _zoom = 1;
              }),
            ),
            const SizedBox(width: 6),
            _ZoomChip(
              label: '+',
              selected: false,
              onTap: _fitPreview
                  ? null
                  : () => setState(() => _zoom = (_zoom + 0.25).clamp(0.5, 2)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 460,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: _previewPng == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : _PageFrame(
                  png: _previewPng,
                  paper: paper,
                  fit: _fitPreview,
                  zoom: _zoom,
                ),
        ),
        const SizedBox(height: 10),
        Text(
          formTitle ?? 'No form selected',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Background: ${_fileName ?? '—'}',
          style: TextStyle(color: secondary, fontSize: 12.5),
        ),
        Text(
          'Page: ${_choice.label} • $orientation • ${paper == null ? '—' : rspPrintDimensionLabel(paper)}',
          style: TextStyle(color: secondary, fontSize: 12.5),
        ),
        Text(
          _formKey == null ? 'Status: Select a form' : 'Status: Ready to save',
          style: TextStyle(
            color: _formKey == null
                ? secondary
                : const Color(0xFF166534),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SavedBackgroundCard extends StatelessWidget {
  const _SavedBackgroundCard({
    required this.template,
    required this.thumbnail,
    required this.busy,
    required this.enabled,
    required this.onPreview,
    required this.onEdit,
    required this.onRemove,
  });

  final FormPrintTemplate template;
  final Uint8List? thumbnail;
  final bool busy;
  final bool enabled;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final landscape = rspPrintPaperIsLandscape(template.paperSize);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final title = FormPrintCatalog.titleFor(template.module, template.formKey);
    final choice = rspPrintPaperChoiceForId(template.paperSize);

    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: thumbnail == null
                ? const Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: AppTheme.primaryNavy,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      thumbnail!,
                      width: 56,
                      height: 68,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  template.originalFilename ?? 'file',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
                Text(
                  '${choice.label} • ${landscape ? 'Landscape' : 'Portrait'}',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
                const Text(
                  'Status: Active',
                  style: TextStyle(
                    color: Color(0xFF166534),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 720) ...[
            TextButton(
              onPressed: enabled ? onPreview : null,
              child: const Text('Preview'),
            ),
            TextButton(
              onPressed: enabled ? onEdit : null,
              child: const Text('Edit'),
            ),
          ],
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            PopupMenuButton<String>(
              enabled: enabled,
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'preview') onPreview();
                if (value == 'edit') onEdit();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'preview', child: Text('Preview')),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit / Replace'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove Background',
                    style: TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_vert_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.png,
    required this.paper,
    required this.fit,
    this.zoom = 1,
  });

  final Uint8List? png;
  final FormPrintPaperSize? paper;
  final bool fit;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final image = png;
    if (image == null) return const SizedBox.shrink();
    final widthPt = paper?.widthPt ?? 612;
    final heightPt = paper?.heightPt ?? 792;

    Widget page(double width, double height) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFD6D0C8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.memory(
              image,
              width: width,
              height: height,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }

    if (!fit) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: page(widthPt * zoom, heightPt * zoom),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = widthPt / heightPt;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 720.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 420.0;
        var width = maxWidth;
        var height = width / ratio;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * ratio;
        }
        return Align(alignment: Alignment.center, child: page(width, height));
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.active, required this.done});

  final int active;
  final bool Function(int index) done;

  @override
  Widget build(BuildContext context) {
    const labels = ['Upload', 'Assign Form', 'Page Setup', 'Preview'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          _StepMark(
            index: i,
            label: labels[i],
            current: active == i,
            complete: done(i) && active != i,
          ),
          if (i < labels.length - 1)
            Container(
              width: 18,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: AppTheme.dashHairlineOf(context),
            ),
        ],
      ],
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({
    required this.index,
    required this.label,
    required this.current,
    required this.complete,
  });

  final int index;
  final String label;
  final bool current;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? AppTheme.primaryNavy
        : complete
        ? const Color(0xFF166534)
        : AppTheme.dashTextSecondaryOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: current || complete
                ? color.withValues(alpha: 0.12)
                : AppTheme.dashMutedSurfaceOf(context),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: complete
              ? Icon(Icons.check_rounded, size: 14, color: color)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OrientationButton extends StatelessWidget {
  const _OrientationButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.45)
        : selected
        ? AppTheme.primaryNavy
        : AppTheme.dashTextPrimaryOf(context);
    return Expanded(
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(0, 42),
          side: BorderSide(
            color: selected
                ? AppTheme.primaryNavy
                : AppTheme.dashHairlineOf(context),
          ),
          backgroundColor: selected
              ? AppTheme.primaryNavy.withValues(alpha: 0.08)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryNavy.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppTheme.primaryNavy.withValues(alpha: 0.4)
                : AppTheme.dashHairlineOf(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: onTap == null && !selected
                ? AppTheme.dashTextSecondaryOf(context)
                : AppTheme.dashTextPrimaryOf(context),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: TextStyle(color: color, fontSize: 13, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

int _pdfPageCount(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final count = RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
  return count == 0 ? 1 : count;
}
