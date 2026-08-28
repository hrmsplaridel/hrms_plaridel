import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class DocuTrackerSignatureChoice {
  const DocuTrackerSignatureChoice.saved(this.signatureAssetId)
    : imageBytes = null,
      mimeType = 'image/png',
      sourceType = 'uploaded',
      saveForReuse = false;

  const DocuTrackerSignatureChoice.image({
    required this.imageBytes,
    required this.mimeType,
    required this.sourceType,
    required this.saveForReuse,
  }) : signatureAssetId = null;

  final String? signatureAssetId;
  final Uint8List? imageBytes;
  final String mimeType;
  final String sourceType;
  final bool saveForReuse;
}

Future<DocuTrackerSignatureChoice?> showDocuTrackerSignatureDialog(
  BuildContext context, {
  required DocuTrackerProvider provider,
}) {
  return showDialog<DocuTrackerSignatureChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SignatureDialog(provider: provider),
  );
}

enum _SignatureMode { draw, upload, saved }

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog({required this.provider});

  final DocuTrackerProvider provider;

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final GlobalKey _drawingKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];
  _SignatureMode _mode = _SignatureMode.draw;
  Uint8List? _uploadedBytes;
  String _uploadedMimeType = 'image/png';
  String? _uploadedName;
  List<DocuTrackerSignatureAsset> _savedAssets = const [];
  String? _selectedAssetId;
  bool _saveForReuse = false;
  bool _loadingSaved = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    setState(() => _loadingSaved = true);
    try {
      final assets = await widget.provider.listSavedSignatures();
      if (!mounted) return;
      setState(() {
        _savedAssets = assets;
        _selectedAssetId = assets.isEmpty ? null : assets.first.id;
        _loadingSaved = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loadingSaved = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['png', 'jpg', 'jpeg'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    if (bytes.length > 2 * 1024 * 1024) {
      setState(() => _error = 'Signature image must be no larger than 2 MB.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    setState(() {
      _uploadedBytes = bytes;
      _uploadedMimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      _uploadedName = file.name;
      _error = null;
    });
  }

  Future<Uint8List?> _captureDrawing() async {
    final boundary =
        _drawingKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || _points.whereType<Offset>().isEmpty) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    switch (_mode) {
      case _SignatureMode.saved:
        final id = _selectedAssetId;
        if (id == null) {
          setState(() {
            _submitting = false;
            _error = 'No saved signature is selected.';
          });
          return;
        }
        Navigator.of(context).pop(DocuTrackerSignatureChoice.saved(id));
        return;
      case _SignatureMode.upload:
        final bytes = _uploadedBytes;
        if (bytes == null) {
          setState(() {
            _submitting = false;
            _error = 'Choose a PNG or JPEG signature image.';
          });
          return;
        }
        Navigator.of(context).pop(
          DocuTrackerSignatureChoice.image(
            imageBytes: bytes,
            mimeType: _uploadedMimeType,
            sourceType: 'uploaded',
            saveForReuse: _saveForReuse,
          ),
        );
        return;
      case _SignatureMode.draw:
        final bytes = await _captureDrawing();
        if (!mounted) return;
        if (bytes == null) {
          setState(() {
            _submitting = false;
            _error = 'Draw your signature before continuing.';
          });
          return;
        }
        Navigator.of(context).pop(
          DocuTrackerSignatureChoice.image(
            imageBytes: bytes,
            mimeType: 'image/png',
            sourceType: 'drawn',
            saveForReuse: _saveForReuse,
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert E-Signature'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_SignatureMode>(
              segments: const <ButtonSegment<_SignatureMode>>[
                ButtonSegment(
                  value: _SignatureMode.draw,
                  icon: Icon(Icons.draw_outlined),
                  label: Text('Draw'),
                ),
                ButtonSegment(
                  value: _SignatureMode.upload,
                  icon: Icon(Icons.upload_file_outlined),
                  label: Text('Upload'),
                ),
                ButtonSegment(
                  value: _SignatureMode.saved,
                  icon: Icon(Icons.bookmark_outline),
                  label: Text('Saved'),
                ),
              ],
              selected: <_SignatureMode>{_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 18),
            if (_mode == _SignatureMode.draw) _buildDrawing(),
            if (_mode == _SignatureMode.upload) _buildUpload(),
            if (_mode == _SignatureMode.saved) _buildSaved(),
            if (_mode != _SignatureMode.saved) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _saveForReuse,
                onChanged: (value) =>
                    setState(() => _saveForReuse = value == true),
                title: const Text('Save this signature for future use'),
                subtitle: const Text(
                  'Only your authenticated account can reuse it.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(_submitting ? 'Preparing…' : 'Use signature'),
        ),
      ],
    );
  }

  Widget _buildDrawing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 190,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: DocuTrackerTokens.borderSubtle),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) =>
                setState(() => _points.add(details.localPosition)),
            onPanUpdate: (details) =>
                setState(() => _points.add(details.localPosition)),
            onPanEnd: (_) => setState(() => _points.add(null)),
            child: RepaintBoundary(
              key: _drawingKey,
              child: CustomPaint(
                painter: _SignaturePainter(_points),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(_points.clear),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Clear'),
          ),
        ),
      ],
    );
  }

  Widget _buildUpload() {
    return OutlinedButton.icon(
      onPressed: _pickImage,
      icon: const Icon(Icons.image_outlined),
      label: Text(_uploadedName ?? 'Choose PNG or JPEG (max 2 MB)'),
    );
  }

  Widget _buildSaved() {
    if (_loadingSaved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_savedAssets.isEmpty) {
      return const Text(
        'You have no saved signatures yet. Draw or upload one and enable “Save for future use”.',
      );
    }
    return SizedBox(
      height: 210,
      child: ListView.separated(
        itemCount: _savedAssets.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final asset = _savedAssets[index];
          final selected = asset.id == _selectedAssetId;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _selectedAssetId = asset.id),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected
                      ? DocuTrackerTokens.brand
                      : DocuTrackerTokens.borderSubtle,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? DocuTrackerTokens.brand
                        : DocuTrackerTokens.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.displayName ?? 'Saved signature'),
                        if (asset.imageBytes.isNotEmpty)
                          SizedBox(
                            height: 52,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Image.memory(
                                asset.imageBytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.4;
    for (var index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
