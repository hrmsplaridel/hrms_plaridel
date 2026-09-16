import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/forms/data/form_print_template_repo.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

/// Admin wizard: upload background → pick form → pick paper size → preview → confirm or resubmit.
class FormBackgroundUploadPage extends StatefulWidget {
  const FormBackgroundUploadPage({
    super.key,
    required this.module,
    required this.onBack,
    this.embedded = false,
  });

  /// `rsp` or `ld`
  final String module;
  final VoidCallback onBack;

  /// When true, parent Forms breadcrumb handles Back (no duplicate button).
  final bool embedded;

  @override
  State<FormBackgroundUploadPage> createState() =>
      _FormBackgroundUploadPageState();
}

class _FormBackgroundUploadPageState extends State<FormBackgroundUploadPage> {
  int _step = 0;
  Uint8List? _fileBytes;
  Uint8List? _previewPng;
  String? _fileName;
  String? _formKey;
  String _paperSizeId = 'letter';
  bool _saving = false;
  bool _loadingList = true;
  String? _removingKey;
  String? _error;
  List<FormPrintTemplate> _saved = const [];

  List<FormPrintCatalogItem> get _forms =>
      FormPrintCatalog.formsFor(widget.module);

  String get _moduleLabel => widget.module == 'ld' ? 'L&D' : 'RSP';

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
      final list = await FormPrintTemplateRepo.instance.list(
        module: widget.module,
      );
      if (!mounted) return;
      setState(() {
        _saved = list;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = userFacingApiError(e);
      });
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
    final name = file.name;

    setState(() {
      _error = null;
      _fileBytes = Uint8List.fromList(bytes);
      _fileName = name;
      _previewPng = null;
    });

    try {
      final png = await _bytesToPreviewPng(Uint8List.fromList(bytes), name);
      if (!mounted) return;
      setState(() {
        _previewPng = png;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not read that file. Use PDF, PNG, or JPG.',
      );
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

  void _selectForm(FormPrintCatalogItem item) {
    setState(() {
      _formKey = item.key;
      _paperSizeId = item.defaultPaperSizeId;
      _step = 2;
    });
  }

  void _resubmit() {
    setState(() {
      _step = 0;
      _fileBytes = null;
      _previewPng = null;
      _fileName = null;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    final bytes = _fileBytes;
    final name = _fileName;
    final formKey = _formKey;
    if (bytes == null || name == null || formKey == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FormPrintTemplateRepo.instance.save(
        module: widget.module,
        formKey: formKey,
        paperSize: _paperSizeId,
        bytes: bytes,
        fileName: name,
      );
      FormPdf.invalidateCustomTemplate(widget.module, formKey);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 0;
        _fileBytes = null;
        _previewPng = null;
        _fileName = null;
        _formKey = null;
      });
      await _reloadSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Background saved for ${FormPrintCatalog.titleFor(widget.module, formKey)}. It will be used when printing.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingApiError(e);
      });
    }
  }

  Future<void> _removeSaved(FormPrintTemplate t) async {
    final title = FormPrintCatalog.titleFor(t.module, t.formKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this background?'),
        content: Text(
          'Remove the uploaded background for $title? '
          'Printing will use the default letterhead until you upload a new file.',
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

    final key = '${t.module}|${t.formKey}';
    setState(() => _removingKey = key);
    try {
      await FormPrintTemplateRepo.instance.delete(
        module: t.module,
        formKey: t.formKey,
      );
      FormPdf.invalidateCustomTemplate(t.module, t.formKey);
      await _reloadSaved();
      if (!mounted) return;
      setState(() => _removingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Background removed. $title will print with the default letterhead.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingKey = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    }
  }

  void _goToStep(int i) {
    if (i == _step) return;
    if (i == 0) {
      setState(() => _step = 0);
      return;
    }
    if (i == 1 && _fileBytes != null) {
      setState(() => _step = 1);
      return;
    }
    if (i == 2 && _fileBytes != null && _formKey != null) {
      setState(() => _step = 2);
      return;
    }
    if (i == 3 && _fileBytes != null && _formKey != null) {
      setState(() => _step = 3);
    }
  }

  bool _stepReachable(int i) {
    if (i == 0) return true;
    if (i == 1) return _fileBytes != null;
    if (i == 2 || i == 3) return _fileBytes != null && _formKey != null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final line = AppTheme.dashHairlineOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: Text('Back to $_moduleLabel'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.18),
                ),
              ),
              child: const Icon(
                Icons.image_outlined,
                color: AppTheme.primaryNavy,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Print background',
                        style: TextStyle(
                          color: primary,
                          fontSize: widget.embedded ? 18 : 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                    'Upload a letterhead, assign it to a form, then save. Print uses it automatically.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'Saved backgrounds',
              style: TextStyle(
                color: primary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            if (!_loadingList)
              Text(
                _saved.isEmpty ? 'None yet' : '${_saved.length}',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingList)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else if (_saved.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_clear_outlined,
                  color: secondary.withValues(alpha: 0.8),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No letterheads saved. Upload one below and assign it to a form.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ..._saved.map(
            (t) => FormSavedBackgroundTile(
              template: t,
              busy: _removingKey == '${t.module}|${t.formKey}',
              enabled: _removingKey == null,
              onRemove: () => _removeSaved(t),
            ),
          ),
        const SizedBox(height: 20),
        _StepRow(
          current: _step,
          reachable: _stepReachable,
          onSelect: _goToStep,
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: Color(0xFFB91C1C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_step == 0) _buildUpload(),
        if (_step == 1) _buildFormPicker(),
        if (_step == 2) _buildSizePicker(),
        if (_step == 3) _buildPreview(),
      ],
    );
  }

  Widget _buildUpload() {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _pickFile,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.28),
              width: 1.4,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.upload_file_outlined,
                  size: 28,
                  color: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Upload background file',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Official letterhead or blank form layout.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: const [
                  _FileTypeChip(label: 'PDF'),
                  _FileTypeChip(label: 'PNG'),
                  _FileTypeChip(label: 'JPG'),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Choose file'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  minimumSize: const Size(168, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormPicker() {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final savedKeys = {for (final t in _saved) t.formKey};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose the form',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          _fileName == null
              ? 'This background will replace any existing file for the form you pick.'
              : 'File: $_fileName',
          style: TextStyle(color: secondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in _forms)
              _FormChoiceCard(
                title: f.title,
                selected: _formKey == f.key,
                hasSaved: savedKeys.contains(f.key),
                onTap: () => _selectForm(f),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _resubmit,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Choose a different file'),
        ),
      ],
    );
  }

  Widget _buildSizePicker() {
    final formTitle = FormPrintCatalog.titleFor(widget.module, _formKey ?? '');
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paper size for $formTitle',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'Preview uses this size. For 8.5 × 13, choose Print using system dialog.',
          style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in FormPrintCatalog.paperSizes)
              _PaperSizeCard(
                size: s,
                selected: _paperSizeId == s.id,
                onTap: () => setState(() => _paperSizeId = s.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => setState(() => _step = 3),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Preview layout'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            minimumSize: const Size(160, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _resubmit,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Choose a different file'),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final paper = FormPrintCatalog.paperById(_paperSizeId);
    final formTitle = FormPrintCatalog.titleFor(widget.module, _formKey ?? '');
    final ratio = paper?.aspectRatio ?? (8.5 / 11);
    final png = _previewPng;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview — $formTitle',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          '${paper?.label ?? _paperSizeId} · ${paper?.subtitle ?? ''} · ${_fileName ?? ''}',
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: AspectRatio(
              aspectRatio: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD6D0C8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: png == null
                      ? const Center(child: CircularProgressIndicator())
                      : Image.memory(png, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save background'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                minimumSize: const Size(160, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _resubmit,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Choose a different file'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 44),
                foregroundColor: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens print-background settings from the Forms list.
class FormsPrintBackgroundEntry extends StatelessWidget {
  const FormsPrintBackgroundEntry({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final navy = AppTheme.primaryNavy;
    final dark = AppTheme.dashIsDark(context);
    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: navy.withValues(alpha: dark ? 0.4 : 0.28),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: navy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Print background',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upload, preview, or remove a letterhead.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: navy.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FormSavedBackgroundTile extends StatelessWidget {
  const FormSavedBackgroundTile({
    super.key,
    required this.template,
    required this.onRemove,
    this.busy = false,
    this.enabled = true,
  });

  final FormPrintTemplate template;
  final VoidCallback onRemove;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final paper = FormPrintCatalog.paperById(template.paperSize);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.description_outlined,
            size: 20,
            color: AppTheme.primaryNavy,
          ),
        ),
        title: Text(
          FormPrintCatalog.titleFor(template.module, template.formKey),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: primary,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          '${paper?.label ?? template.paperSize} · ${template.originalFilename ?? 'file'}',
          style: TextStyle(color: secondary, fontSize: 12.5),
        ),
        trailing: TextButton.icon(
          onPressed: busy || !enabled ? null : onRemove,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline, size: 20),
          label: Text(busy ? 'Removing…' : 'Remove'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.current,
    required this.reachable,
    required this.onSelect,
  });

  final int current;
  final bool Function(int index) reachable;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Upload', 'Form', 'Size', 'Preview'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                Expanded(
                  child: _StepChip(
                    index: i,
                    label: labels[i],
                    current: current == i,
                    done: i < current,
                    enabled: reachable(i),
                    compact: compact,
                    onTap: () => onSelect(i),
                  ),
                ),
                if (i < labels.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppTheme.dashTextSecondaryOf(
                        context,
                      ).withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.current,
    required this.done,
    required this.enabled,
    required this.compact,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool current;
  final bool done;
  final bool enabled;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? AppTheme.primaryNavy
        : done
        ? const Color(0xFF2E7D32)
        : AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: current
          ? AppTheme.primaryNavy.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: current || done
                      ? color.withValues(alpha: 0.14)
                      : AppTheme.dashMutedSurfaceOf(context),
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: done && !current
                    ? Icon(Icons.check_rounded, size: 13, color: color)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTypeChip extends StatelessWidget {
  const _FileTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
    );
  }
}

class _FormChoiceCard extends StatelessWidget {
  const _FormChoiceCard({
    required this.title,
    required this.selected,
    required this.hasSaved,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final bool hasSaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Material(
      color: selected
          ? AppTheme.primaryNavy.withValues(alpha: 0.08)
          : AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.45)
                  : AppTheme.dashHairlineOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected
                    ? AppTheme.primaryNavy
                    : AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: primary,
                    height: 1.25,
                  ),
                ),
              ),
              if (hasSaved) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Color(0xFF2E7D32),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperSizeCard extends StatelessWidget {
  const _PaperSizeCard({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final FormPrintPaperSize size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: selected
          ? AppTheme.primaryNavy.withValues(alpha: 0.08)
          : AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 148,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.45)
                  : AppTheme.dashHairlineOf(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                size.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? AppTheme.primaryNavy : primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                size.subtitle,
                style: TextStyle(fontSize: 11.5, color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
