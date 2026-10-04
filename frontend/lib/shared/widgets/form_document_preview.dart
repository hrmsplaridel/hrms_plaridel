import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/forms/data/form_paper_preference.dart';

/// Opens the official printable form in the same side panel used by DTR forms.
///
/// [buildDocument] must return the same PDF used for printing. Nothing is saved.
Future<void> openFormDocumentPreview({
  required BuildContext context,
  required String title,
  required String filename,
  required Future<pw.Document> Function() buildDocument,
  PdfPageFormat? format,
  String? printModule,
  String? printFormKey,
}) async {
  try {
    final prepared = await FormPdf.captureFormPdf(
      buildDocument: buildDocument,
      format: format,
      printModule: printModule,
      printFormKey: printFormKey,
    );
    if (!context.mounted) return;
    final note = prepared.bindError;
    if (note != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
    final module = printModule;
    final formKey = printFormKey;
    FormPaperChoice? paperChoice;
    final isApplicants = module == 'rsp' && formKey == 'applicants_profile';
    final isOjt = module == 'rsp' && formKey == 'ojt_work_immersion';
    final usesFixedPaper = isApplicants || isOjt;
    final initialId = usesFixedPaper
        ? prepared.paperSizeId
        : FormPdf.paperChoiceIdFor(prepared.format);
    if (module != null &&
        formKey != null &&
        initialId != null &&
        FormPdf.supportsPaperChoice(module, formKey)) {
      paperChoice = FormPaperChoice(
        selectedId: initialId,
        optionIds: usesFixedPaper ? FormPdf.applicantsProfilePaperIds : null,
        families: usesFixedPaper ? FormPdf.applicantsProfileFamilies : null,
        familyOf: usesFixedPaper ? FormPdf.applicantsProfileFamily : null,
        isLandscape: usesFixedPaper
            ? FormPdf.applicantsProfileIsLandscape
            : null,
        compose: usesFixedPaper ? FormPdf.applicantsProfileCompose : null,
        familyLabel: isOjt
            ? FormPdf.ojtFamilyLabel
            : isApplicants
            ? FormPdf.applicantsProfileFamilyLabel
            : null,
        familyDimensions: usesFixedPaper
            ? FormPdf.applicantsProfileFamilyDimensions
            : null,
        readFit: () => FormPdf.fitToPrintableArea,
        writeFit: (fit) => FormPdf.fitToPrintableArea = fit,
        optionLabel: usesFixedPaper
            ? FormPdf.applicantsProfilePaperLabel
            : null,
        rebuild: (id) async {
          await FormPaperPreference.save(module, formKey, id);
          final next = await FormPdf.captureFormPdf(
            buildDocument: buildDocument,
            format: format,
            printModule: module,
            printFormKey: formKey,
            paperSizeId: id,
          );
          return FormPaperRebuild(bytes: next.bytes, format: next.format);
        },
      );
    }
    await showFormPdfPreview(
      context: context,
      bytes: prepared.bytes,
      title: title,
      filename: filename,
      format: prepared.format,
      paperChoice: paperChoice,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to load form preview. Please try again.'),
      ),
    );
  }
}

/// Preview Form and Print Form actions. Wraps onto two lines on a narrow row.
///
/// Shows a preparing animation until the preview or print future finishes.
class FormPreviewPrintButtons extends StatefulWidget {
  const FormPreviewPrintButtons({
    super.key,
    required this.onPreview,
    required this.onPrint,
    this.fullLabels = true,
  });

  final FutureOr<void> Function() onPreview;
  final FutureOr<void> Function() onPrint;
  final bool fullLabels;

  @override
  State<FormPreviewPrintButtons> createState() =>
      _FormPreviewPrintButtonsState();
}

class _FormPreviewPrintButtonsState extends State<FormPreviewPrintButtons> {
  _RspFormAction? _busy;

  Future<void> _run(
    _RspFormAction action,
    FutureOr<void> Function() callback,
  ) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      final result = callback();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth > 0 && constraints.maxWidth < 320;
        final previewLabel = widget.fullLabels && !tight
            ? 'Preview Form'
            : 'Preview';
        final printLabel = widget.fullLabels && !tight ? 'Print Form' : 'Print';
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RspFormActionButton(
              icon: Icons.visibility_outlined,
              label: previewLabel,
              busyLabel: 'Opening preview…',
              busy: _busy == _RspFormAction.preview,
              enabled: _busy == null,
              onPressed: () => _run(_RspFormAction.preview, widget.onPreview),
            ),
            _RspFormActionButton(
              icon: Icons.print_rounded,
              label: printLabel,
              busyLabel: 'Preparing print…',
              busy: _busy == _RspFormAction.print,
              enabled: _busy == null,
              onPressed: () => _run(_RspFormAction.print, widget.onPrint),
            ),
          ],
        );
      },
    );
  }
}

enum _RspFormAction { preview, print }

class _RspFormActionButton extends StatelessWidget {
  const _RspFormActionButton({
    required this.icon,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String busyLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: busy ? const _RspFormActionSpinner() : Icon(icon, size: 18),
      label: Text(busy ? busyLabel : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        side: BorderSide(
          color: AppTheme.primaryNavy.withValues(alpha: busy ? 0.7 : 0.35),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Outlined Preview / Print button that shows a preparing animation.
class RspLdBusyOutlinedButton extends StatefulWidget {
  const RspLdBusyOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busyLabel = 'Preparing…',
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final String busyLabel;
  final FutureOr<void> Function() onPressed;
  final bool expand;

  @override
  State<RspLdBusyOutlinedButton> createState() =>
      _RspLdBusyOutlinedButtonState();
}

class _RspLdBusyOutlinedButtonState extends State<RspLdBusyOutlinedButton> {
  var _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = widget.onPressed();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy ? const _RspFormActionSpinner() : Icon(widget.icon, size: 18),
      label: Text(_busy ? widget.busyLabel : widget.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        minimumSize: Size(widget.expand ? double.infinity : 44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: BorderSide(
          color: AppTheme.primaryNavy.withValues(alpha: _busy ? 0.7 : 0.35),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Icon-only print/preview control used by RSP and L&D record rows.
class RspLdBusyIconButton extends StatefulWidget {
  const RspLdBusyIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 20,
    this.busyTooltip = 'Preparing…',
  });

  final String tooltip;
  final IconData icon;
  final FutureOr<void> Function() onPressed;
  final double iconSize;
  final String busyTooltip;

  @override
  State<RspLdBusyIconButton> createState() => _RspLdBusyIconButtonState();
}

class _RspLdBusyIconButtonState extends State<RspLdBusyIconButton> {
  var _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = widget.onPressed();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navy = AppTheme.primaryNavy;
    return IconButton(
      tooltip: _busy ? widget.busyTooltip : widget.tooltip,
      onPressed: _busy ? null : _run,
      style: IconButton.styleFrom(
        foregroundColor: navy,
        backgroundColor: navy.withValues(alpha: _busy ? 0.18 : 0.1),
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(8),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: _busy
          ? const _RspFormActionSpinner()
          : Icon(widget.icon, size: widget.iconSize),
    );
  }
}

class _RspFormActionSpinner extends StatefulWidget {
  const _RspFormActionSpinner();

  @override
  State<_RspFormActionSpinner> createState() => _RspFormActionSpinnerState();
}

class _RspFormActionSpinnerState extends State<_RspFormActionSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.primaryNavy,
        ),
      ),
    );
  }
}
