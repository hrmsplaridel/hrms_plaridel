import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

class LocatorPrintDraft {
  const LocatorPrintDraft({this.file});
  final PlatformFile? file;
  Future<void> save(String typeId, {bool removeBackground = false}) async {
    await ApiClient.instance.post(
      '/api/locator-slips/print/types/$typeId',
      data: FormData.fromMap({
        'remove_background': removeBackground.toString(),
        if (file != null)
          'file': MultipartFile.fromBytes(
            file!.bytes!,
            filename: file!.name,
            contentType: DioMediaType.parse(
              file!.extension?.toLowerCase() == 'pdf'
                  ? 'application/pdf'
                  : file!.extension?.toLowerCase() == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
            ),
          ),
      }),
    );
  }
}

class LocatorPrintSettings extends StatefulWidget {
  const LocatorPrintSettings({
    super.key,
    this.typeId,
    this.initialDraft,
    this.onChanged,
    this.onSaved,
    this.enabled = true,
  });
  final String? typeId;
  final LocatorPrintDraft? initialDraft;
  final ValueChanged<LocatorPrintDraft>? onChanged;
  final VoidCallback? onSaved;
  final bool enabled;
  @override
  State<LocatorPrintSettings> createState() => _LocatorPrintSettingsState();
}

class _LocatorPrintSettingsState extends State<LocatorPrintSettings> {
  PlatformFile? _file;
  String? _background, _error;
  bool _loading = false, _busy = false, _remove = false;
  bool get _disabled => _busy || !widget.enabled;
  @override
  void initState() {
    super.initState();
    _file = widget.initialDraft?.file;
    if (widget.typeId != null) _load();
  }

  void _changed() => widget.onChanged?.call(LocatorPrintDraft(file: _file));
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/print/types/${widget.typeId}',
      );
      if (mounted) {
        setState(() => _background = r.data?['background_name']?.toString());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load print settings. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 5242880 || file.bytes == null) {
        setState(() => _error = 'Select a readable file up to 5 MB.');
        return;
      }
      setState(() {
        _file = file;
        _remove = false;
        _error = null;
      });
      _changed();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the selected file. Please retry.',
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LocatorPrintDraft(
        file: _file,
      ).save(widget.typeId!, removeBackground: _remove);
      if (!mounted) return;
      setState(() {
        _file = null;
        _remove = false;
      });
      widget.onSaved?.call();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print settings saved. Filed locators retain their original template.',
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              (e.response?.data is Map ? e.response?.data['error'] : null)
                  ?.toString() ??
              'Could not save print settings.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save print settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await LocatorSlipPrint.buildPdf(
        id: null,
        employeeName: 'Sample Employee',
        dateText: 'Oct 10, 2026',
        requestTypeLabel: 'Locator / Official Business',
        locationLabel: 'Office / Destination',
        office: 'Municipal Hall',
        remarks: 'Official transaction',
        amIn: true,
        amOut: true,
        pmIn: true,
        pmOut: true,
      );
      final r = await ApiClient.instance.post<List<int>>(
        '/api/locator-slips/print/types/${widget.typeId}/preview',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'preview.pdf'),
        }),
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted) {
        await showFormPdfPreview(
          context: context,
          bytes: Uint8List.fromList(r.data!),
          title: 'Locator Form Preview',
          filename: 'Locator_Form_Sample.pdf',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not preview the saved form.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Printed Form',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        Text(
          _remove
              ? 'Background will be removed'
              : _file?.name ?? _background ?? 'No background uploaded',
        ),
        const Text(
          'A4 letterhead · portrait or landscape · PDF, PNG or JPEG · up to 5 MB',
        ),
        const Text(
          'The locator slip is fitted between the letterhead and footer. Without a background, the current landscape form is used.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _disabled ? null : _pick,
              child: const Text('Upload background'),
            ),
            if (_file != null || _background != null)
              TextButton(
                onPressed: _disabled
                    ? null
                    : () {
                        setState(() {
                          _file = null;
                          _remove = widget.typeId != null;
                        });
                        _changed();
                      },
                child: const Text('Remove background'),
              ),
            if (widget.typeId != null)
              FilledButton(
                onPressed: _disabled ? null : _save,
                child: const Text('Save print settings'),
              ),
            if (widget.typeId != null)
              TextButton(
                onPressed: _disabled ? null : _preview,
                child: const Text('Preview saved form'),
              ),
            if (widget.typeId != null && _error != null)
              TextButton(
                onPressed: _disabled ? null : _load,
                child: const Text('Retry'),
              ),
          ],
        ),
        if (widget.typeId == null)
          const Text(
            'The background will be saved when you create the locator type.',
          ),
      ],
    );
  }
}
