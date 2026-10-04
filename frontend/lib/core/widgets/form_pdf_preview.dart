import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

/// PDF bytes regenerated for a different paper size.
class FormPaperRebuild {
  const FormPaperRebuild({required this.bytes, required this.format});

  final Uint8List bytes;
  final PdfPageFormat format;
}

/// Lets the preview switch the paper size by rebuilding the form PDF.
class FormPaperChoice {
  const FormPaperChoice({
    required this.selectedId,
    required this.rebuild,
    this.optionIds,
    this.optionLabel,
    this.detail,
    this.families,
    this.familyOf,
    this.isLandscape,
    this.compose,
    this.familyLabel,
    this.familyDimensions,
    this.readFit,
    this.writeFit,
  });

  final String selectedId;
  final Future<FormPaperRebuild> Function(String paperSizeId) rebuild;
  final List<String>? optionIds;
  final String Function(String id)? optionLabel;
  final String Function(String id)? detail;
  final List<String>? families;
  final String Function(String id)? familyOf;
  final bool Function(String id)? isLandscape;
  final String Function(String family, bool landscape)? compose;
  final String Function(String family)? familyLabel;
  final String Function(String family)? familyDimensions;
  final bool Function()? readFit;
  final void Function(bool fit)? writeFit;
}

/// Opens a PDF preview in a right-side slide panel (or full-screen on narrow
/// viewports), matching the DTR Preview style — themed header with icon, print
/// and share actions enabled.
Future<void> showFormPdfPreview({
  required BuildContext context,
  required Uint8List bytes,
  required String title,
  required String filename,
  PdfPageFormat? format,
  FormPaperChoice? paperChoice,
}) => openResponsiveRightSidePanel<void>(
  context: context,
  barrierLabel: 'Close $title',
  breakpoint: 900,
  minWidth: 680,
  initialWidthFraction: 0.62,
  builder: (_) => _FormPdfPreviewPanel(
    bytes: bytes,
    title: title,
    filename: filename,
    format: format,
    paperChoice: paperChoice,
  ),
);

class _FormPdfPreviewPanel extends StatefulWidget {
  const _FormPdfPreviewPanel({
    required this.bytes,
    required this.title,
    required this.filename,
    this.format,
    this.paperChoice,
  });

  final Uint8List bytes;
  final String title;
  final String filename;
  final PdfPageFormat? format;
  final FormPaperChoice? paperChoice;

  @override
  State<_FormPdfPreviewPanel> createState() => _FormPdfPreviewPanelState();
}

class _FormPdfPreviewPanelState extends State<_FormPdfPreviewPanel> {
  late Uint8List _bytes = widget.bytes;
  late PdfPageFormat? _format = widget.format;
  late String? _paperId = widget.paperChoice?.selectedId;
  var _busy = false;
  var _revision = 0;

  Future<void> _changePaper(String id, {bool force = false}) async {
    final choice = widget.paperChoice;
    if (choice == null || _busy || (!force && id == _paperId)) return;
    setState(() => _busy = true);
    try {
      final next = await choice.rebuild(id);
      if (!mounted) return;
      setState(() {
        _bytes = next.bytes;
        _format = next.format;
        _paperId = id;
        _revision++;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to change paper size.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _paperPicker(BuildContext context) {
    final choice = widget.paperChoice;
    if (choice?.families != null &&
        choice?.familyOf != null &&
        choice?.compose != null &&
        choice?.isLandscape != null &&
        choice?.familyLabel != null) {
      final id = _paperId ?? choice!.selectedId;
      final family = choice!.familyOf!(id);
      final landscape = choice.isLandscape!(id);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            value: family,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    _changePaper(choice.compose!(value, landscape));
                  },
            items: [
              for (final item in choice.families!)
                DropdownMenuItem(
                  value: item,
                  child: Text(
                    choice.familyLabel!(item),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Portrait')),
              ButtonSegment(value: true, label: Text('Landscape')),
            ],
            selected: {landscape},
            onSelectionChanged: _busy
                ? null
                : (selected) {
                    _changePaper(choice.compose!(family, selected.first));
                  },
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Paper',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _paperId,
          isDense: true,
          underline: const SizedBox.shrink(),
          onChanged: _busy ? null : (v) => v == null ? null : _changePaper(v),
          items: [
            for (final id
                in widget.paperChoice?.optionIds ??
                    FormPrintCatalog.adjustablePaperIds)
              DropdownMenuItem(
                value: id,
                child: Text(
                  widget.paperChoice?.optionLabel?.call(id) ??
                      FormPrintCatalog.hrPaperLabel(id),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = _format;
    return Material(
      color: AppTheme.dashCanvasOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppTheme.dashPanelOf(context),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.preview_rounded, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.paperChoice != null) ...[
                      _paperPicker(context),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.paperChoice?.writeFit != null ||
                (widget.paperChoice?.detail != null && _paperId != null))
              Container(
                color: AppTheme.dashPanelOf(context),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.paperChoice?.writeFit != null) ...[
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Fit to Printable Area'),
                          ),
                          ButtonSegment(value: false, label: Text('Actual Size')),
                        ],
                        selected: {
                          widget.paperChoice!.readFit?.call() ?? true,
                        },
                        onSelectionChanged: _busy
                            ? null
                            : (selected) async {
                                widget.paperChoice!.writeFit!(selected.first);
                                final id = _paperId;
                                if (id == null) {
                                  setState(() {});
                                  return;
                                }
                                await _changePaper(id, force: true);
                              },
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.paperChoice?.detail != null && _paperId != null)
                      Text(
                        widget.paperChoice!.detail!(_paperId!),
                        style: TextStyle(
                          color: AppTheme.dashTextPrimaryOf(context),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: PdfPreview(
                key: ValueKey(_revision),
                build: (_) async => _bytes,
                pdfFileName: widget.filename,
                initialPageFormat: format,
                pageFormats: format == null
                    ? const {
                        'A4': PdfPageFormat.a4,
                        'Letter': PdfPageFormat.letter,
                      }
                    : {'Official': format},
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                dynamicLayout: format == null,
                canDebug: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paper choice shown before the system print dialog for Applicants Profile.
Future<String?> showApplicantsProfilePrintSetup({
  required BuildContext context,
  String title = 'Applicants Profile',
  required String initialId,
  required List<String> families,
  required String Function(String id) familyOf,
  required bool Function(String id) isLandscape,
  required String Function(String family, bool landscape) compose,
  required String Function(String family) familyLabel,
  required String Function(String family) familyDimensions,
  required bool initialFit,
  required void Function(bool fit) writeFit,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ApplicantsProfilePrintSetup(
      title: title,
      initialId: initialId,
      families: families,
      familyOf: familyOf,
      isLandscape: isLandscape,
      compose: compose,
      familyLabel: familyLabel,
      familyDimensions: familyDimensions,
      initialFit: initialFit,
      writeFit: writeFit,
    ),
  );
}

class _ApplicantsProfilePrintSetup extends StatefulWidget {
  const _ApplicantsProfilePrintSetup({
    required this.title,
    required this.initialId,
    required this.families,
    required this.familyOf,
    required this.isLandscape,
    required this.compose,
    required this.familyLabel,
    required this.familyDimensions,
    required this.initialFit,
    required this.writeFit,
  });

  final String title;
  final String initialId;
  final List<String> families;
  final String Function(String id) familyOf;
  final bool Function(String id) isLandscape;
  final String Function(String family, bool landscape) compose;
  final String Function(String family) familyLabel;
  final String Function(String family) familyDimensions;
  final bool initialFit;
  final void Function(bool fit) writeFit;

  @override
  State<_ApplicantsProfilePrintSetup> createState() =>
      _ApplicantsProfilePrintSetupState();
}

class _ApplicantsProfilePrintSetupState
    extends State<_ApplicantsProfilePrintSetup> {
  late String _id = widget.initialId;
  late bool _fit = widget.initialFit;

  @override
  Widget build(BuildContext context) {
    final family = widget.familyOf(_id);
    final landscape = widget.isLandscape(_id);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Paper Size'),
            DropdownButton<String>(
              isExpanded: true,
              value: family,
              items: [
                for (final item in widget.families)
                  DropdownMenuItem(
                    value: item,
                    child: Text(widget.familyLabel(item)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _id = widget.compose(value, landscape));
              },
            ),
            Text(widget.familyDimensions(family)),
            const SizedBox(height: 12),
            const Text('Orientation'),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Portrait')),
                ButtonSegment(value: true, label: Text('Landscape')),
              ],
              selected: {landscape},
              onSelectionChanged: (selected) {
                setState(() => _id = widget.compose(family, selected.first));
              },
            ),
            const SizedBox(height: 12),
            const Text('Scaling'),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Fit to Printable Area'),
                ),
                ButtonSegment(value: false, label: Text('Actual Size')),
              ],
              selected: {_fit},
              onSelectionChanged: (selected) {
                final fit = selected.first;
                widget.writeFit(fit);
                setState(() => _fit = fit);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_id),
          child: const Text('Print'),
        ),
      ],
    );
  }
}
