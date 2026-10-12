import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_signature_ink.dart';

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
  String title = 'Insert E-Signature',
  bool allowSavedSelection = true,
  bool forceSaveForReuse = false,
}) {
  return showDialog<DocuTrackerSignatureChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SignatureDialog(
      provider: provider,
      title: title,
      allowSavedSelection: allowSavedSelection,
      forceSaveForReuse: forceSaveForReuse,
    ),
  );
}

enum _SignatureMode { draw, upload, saved }

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog({
    required this.provider,
    required this.title,
    required this.allowSavedSelection,
    required this.forceSaveForReuse,
  });

  final DocuTrackerProvider provider;
  final String title;
  final bool allowSavedSelection;
  final bool forceSaveForReuse;

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final DocuTrackerSignatureStrokeController _strokes =
      DocuTrackerSignatureStrokeController();
  final GlobalKey _inkLayerKey = GlobalKey();
  final GlobalKey _saveOptionKey = GlobalKey();
  final GlobalKey _padToolsKey = GlobalKey();
  final GlobalKey _modeSwitchKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _cancelKey = GlobalKey();
  final GlobalKey _submitKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  _SignatureMode _mode = _SignatureMode.draw;
  Uint8List? _uploadedBytes;
  String _uploadedMimeType = 'image/png';
  String? _uploadedName;
  List<DocuTrackerSignatureAsset> _savedAssets = const [];
  String? _selectedAssetId;
  bool _saveForReuse = false;
  bool _loadingSaved = false;
  bool _submitting = false;
  bool _hasInk = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _strokes.addListener(_onStrokesChanged);
    if (widget.allowSavedSelection) _loadSaved();
  }

  @override
  void dispose() {
    _strokes.removeListener(_onStrokesChanged);
    _strokes.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStrokesChanged() {
    final hasInk = _strokes.hasInk;
    if (hasInk != _hasInk && mounted) {
      setState(() => _hasInk = hasInk);
    }
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

  void _undoLastStroke() {
    if (!_hasInk) return;
    _strokes.undoLastStroke();
    if (_error != null) setState(() => _error = null);
  }

  void _clearDrawing() {
    _strokes.clear();
    if (_error != null) setState(() => _error = null);
  }

  Future<Uint8List?> _captureDrawing() =>
      encodeDocuTrackerSignaturePng(_strokes.points);

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
            saveForReuse: widget.forceSaveForReuse || _saveForReuse,
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
            saveForReuse: widget.forceSaveForReuse || _saveForReuse,
          ),
        );
        return;
    }
  }

  double _drawingPadHeight(Size mediaSize) {
    final isCompact = mediaSize.width < 600;
    if (isCompact) {
      return (mediaSize.height * 0.4).clamp(260.0, 380.0);
    }
    return (mediaSize.height * 0.4).clamp(300.0, 520.0);
  }

  double _dialogWidth(Size mediaSize) {
    if (mediaSize.width < 480) {
      return mediaSize.width - 32;
    }
    return mediaSize.width < 900 ? 720.0 : 860.0;
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = _dialogWidth(mediaSize);

    final dialog = AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            key: _viewportKey,
            controller: _scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_SignatureMode>(
                  key: _modeSwitchKey,
                  segments: <ButtonSegment<_SignatureMode>>[
                    const ButtonSegment(
                      value: _SignatureMode.draw,
                      icon: Icon(Icons.draw_outlined),
                      label: Text('Draw'),
                    ),
                    const ButtonSegment(
                      value: _SignatureMode.upload,
                      icon: Icon(Icons.upload_file_outlined),
                      label: Text('Upload'),
                    ),
                    if (widget.allowSavedSelection)
                      const ButtonSegment(
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
                if (_mode == _SignatureMode.draw) _buildDrawing(mediaSize),
                if (_mode == _SignatureMode.upload) _buildUpload(),
                if (_mode == _SignatureMode.saved) _buildSaved(),
                if (_mode != _SignatureMode.saved &&
                    !widget.forceSaveForReuse) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: _saveOptionKey,
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
                ] else if (widget.forceSaveForReuse) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This signature will be saved in My Signatures for future use.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: _cancelKey,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: _submitKey,
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(_submitting ? 'Preparing…' : 'Use signature'),
        ),
      ],
    );

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _SignaturePanRecognizer:
            GestureRecognizerFactoryWithHandlers<_SignaturePanRecognizer>(
              () => _SignaturePanRecognizer(debugOwner: this),
              (recognizer) {
                recognizer
                  ..canCapture = _canCaptureAt
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = (details) {
                    final point = _inkPoint(details.globalPosition);
                    if (point == null) return;
                    if (_error != null) setState(() => _error = null);
                    _strokes.beginStroke(point);
                  }
                  ..onUpdate = (details) {
                    final point = _inkPoint(details.globalPosition);
                    if (point == null) return;
                    _strokes.appendStroke(point);
                  }
                  ..onEnd = (_) {
                    _strokes.endStroke();
                  }
                  ..onCancel = _strokes.endStroke;
              },
            ),
      },
      child: KeyedSubtree(key: _inkLayerKey, child: dialog),
    );
  }

  static const double _scrollbarGrabWidth = 16;

  Rect? _globalRectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool _canCaptureAt(Offset globalPosition) {
    if (_mode != _SignatureMode.draw || _submitting) return false;
    final viewport = _globalRectOf(_viewportKey);
    if (viewport != null) {
      for (final key in [_modeSwitchKey, _padToolsKey, _saveOptionKey]) {
        final rect = _globalRectOf(key)?.intersect(viewport);
        if (rect != null && !rect.isEmpty && rect.contains(globalPosition)) {
          return false;
        }
      }
      final scrollable =
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0;
      if (scrollable &&
          Rect.fromLTRB(
            viewport.right - _scrollbarGrabWidth,
            viewport.top,
            viewport.right,
            viewport.bottom,
          ).contains(globalPosition)) {
        return false;
      }
    }
    for (final key in [_cancelKey, _submitKey]) {
      if (_globalRectOf(key)?.contains(globalPosition) ?? false) return false;
    }
    return true;
  }

  Offset? _inkPoint(Offset globalPosition) {
    final box = _inkLayerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(globalPosition);
  }

  Widget _buildDrawing(Size mediaSize) {
    final padHeight = _drawingPadHeight(mediaSize);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign anywhere on the screen with your pen tablet, finger, or '
          'mouse — you can start from any spot. Your signature appears in '
          'the preview below, cropped and centered.',
          style: TextStyle(
            color: DocuTrackerTokens.textMutedOf(context),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          key: const Key('docutracker_signature_pad'),
          height: padHeight,
          child: Container(
            key: const Key('docutracker_signature_preview'),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: DocuTrackerTokens.borderSubtleOf(context),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: _hasInk
                ? RepaintBoundary(
                    child: CustomPaint(
                      painter: _SignaturePreviewPainter(_strokes),
                      isComplex: true,
                      willChange: true,
                      child: const SizedBox.expand(),
                    ),
                  )
                : Center(
                    child: Text(
                      'Your signature will appear here',
                      style: TextStyle(
                        color: DocuTrackerTokens.textMutedOf(
                          context,
                        ).withValues(alpha: 0.6),
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: Wrap(
            key: _padToolsKey,
            spacing: 4,
            runSpacing: 0,
            children: [
              TextButton.icon(
                key: const Key('docutracker_signature_undo'),
                onPressed: _hasInk ? _undoLastStroke : null,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Undo Last Stroke'),
              ),
              TextButton.icon(
                key: const Key('docutracker_signature_clear'),
                onPressed: _hasInk ? _clearDrawing : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Clear'),
              ),
            ],
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
                      : DocuTrackerTokens.borderSubtleOf(context),
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
                        : DocuTrackerTokens.textMutedOf(context),
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

/// Claims pointers that land in the signing zone on touch-down so the enclosing
/// dialog scroll view can never win the gesture arena while the user is
/// signing. Pointers outside the zone are ignored and reach buttons normally.
class _SignaturePanRecognizer extends PanGestureRecognizer {
  _SignaturePanRecognizer({super.debugOwner});

  bool Function(Offset globalPosition)? canCapture;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) &&
      (canCapture?.call(event.position) ?? false);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _SignaturePreviewPainter extends CustomPainter {
  _SignaturePreviewPainter(this.controller) : super(repaint: controller);

  final DocuTrackerSignatureStrokeController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = docuTrackerSignatureInkBounds(controller.points);
    if (bounds == null) return;
    final layout = docuTrackerSignatureInkLayout(bounds, size);
    if (layout == null) return;
    paintDocuTrackerSignatureInk(canvas, controller.points, layout: layout);
  }

  @override
  bool shouldRepaint(covariant _SignaturePreviewPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
