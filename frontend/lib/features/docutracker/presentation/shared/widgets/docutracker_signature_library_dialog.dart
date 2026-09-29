import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

Future<void> showDocuTrackerSignatureLibraryDialog(
  BuildContext context, {
  required DocuTrackerProvider provider,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SignatureLibraryDialog(provider: provider),
  );
}

class _SignatureLibraryDialog extends StatefulWidget {
  const _SignatureLibraryDialog({required this.provider});

  final DocuTrackerProvider provider;

  @override
  State<_SignatureLibraryDialog> createState() =>
      _SignatureLibraryDialogState();
}

class _SignatureLibraryDialogState extends State<_SignatureLibraryDialog> {
  List<DocuTrackerSignatureAsset> _assets = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> _load() async {
    try {
      final assets = await widget.provider.listSavedSignatures();
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<String?> _askName({String? initialValue}) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _SignatureNameDialog(
        initialValue: initialValue ?? 'Signature ${_assets.length + 1}',
        isRename: initialValue != null,
      ),
    );
  }

  Future<void> _add() async {
    final choice = await showDocuTrackerSignatureDialog(
      context,
      provider: widget.provider,
      title: 'Create Saved Signature',
      allowSavedSelection: false,
      forceSaveForReuse: true,
    );
    if (!mounted || choice == null || choice.imageBytes == null) return;
    final name = await _askName();
    if (!mounted || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.provider.createSavedSignature(
        imageBytes: choice.imageBytes!,
        mimeType: choice.mimeType,
        sourceType: choice.sourceType,
        displayName: name,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(DocuTrackerSignatureAsset asset) async {
    final name = await _askName(
      initialValue: asset.displayName ?? 'Saved signature',
    );
    if (!mounted || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.provider.renameSavedSignature(
        assetId: asset.id,
        displayName: name,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(DocuTrackerSignatureAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Signature?'),
        content: const Text(
          'It will disappear from My Signatures. Documents already signed with it will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.provider.removeSavedSignature(asset.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('My Signatures'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create signatures once, then choose one when signing or approving.',
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                const SizedBox(height: 12),
              ],
              Flexible(child: _buildContent()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          key: const ValueKey('docutracker-add-saved-signature'),
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Signature'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_assets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Text('No saved signatures yet.'),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _assets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final asset = _assets[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 130,
                height: 62,
                padding: const EdgeInsets.all(6),
                color: Colors.white,
                child: asset.imageBytes.isEmpty
                    ? const Icon(Icons.draw_outlined)
                    : Image.memory(asset.imageBytes, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  asset.displayName ?? 'Saved signature',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: 'Signature actions',
                onSelected: (value) {
                  if (value == 'rename') _rename(asset);
                  if (value == 'remove') _remove(asset);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SignatureNameDialog extends StatefulWidget {
  const _SignatureNameDialog({
    required this.initialValue,
    required this.isRename,
  });

  final String initialValue;
  final bool isRename;

  @override
  State<_SignatureNameDialog> createState() => _SignatureNameDialogState();
}

class _SignatureNameDialogState extends State<_SignatureNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isRename ? 'Rename Signature' : 'Name Signature'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Signature name',
          hintText: 'Example: Official Signature',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
