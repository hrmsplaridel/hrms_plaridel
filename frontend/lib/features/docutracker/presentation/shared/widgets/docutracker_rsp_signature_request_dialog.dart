import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';

Future<void> showDocuTrackerSourceSignatureRequestDialog(
  BuildContext context, {
  required DocuTrackerRspSignatureRequest request,
  VoidCallback? onChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        _RspSignatureRequestDialog(request: request, onChanged: onChanged),
  );
}

Future<void> showDocuTrackerRspSignatureRequestDialog(
  BuildContext context, {
  required DocuTrackerRspSignatureRequest request,
  VoidCallback? onChanged,
}) => showDocuTrackerSourceSignatureRequestDialog(
  context,
  request: request,
  onChanged: onChanged,
);

class _RspSignatureRequestDialog extends StatefulWidget {
  const _RspSignatureRequestDialog({required this.request, this.onChanged});

  final DocuTrackerRspSignatureRequest request;
  final VoidCallback? onChanged;

  @override
  State<_RspSignatureRequestDialog> createState() =>
      _RspSignatureRequestDialogState();
}

class _RspSignatureRequestDialogState
    extends State<_RspSignatureRequestDialog> {
  late DocuTrackerSourceSignatureBundle _bundle;
  Uint8List? _pdfBytes;
  Object? _pdfError;
  bool _pdfLoading = false;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _bundle = widget.request.signatureBundle;
  }

  Future<Uint8List> _buildPdfBytes() async {
    final record = widget.request.sourceRecord;
    final document = switch ((
      widget.request.sourceModule,
      widget.request.sourceTable,
    )) {
      ('rsp', ApplicantsProfileEntry.tableName) =>
        FormPdf.buildApplicantsProfilePdf(
          ApplicantsProfileEntry.fromJson(record),
          signatures: _bundle,
        ),
      ('rsp', SelectionLineupEntry.tableName) =>
        FormPdf.buildSelectionLineupPdf(
          SelectionLineupEntry.fromJson(record),
          signatures: _bundle,
        ),
      ('rsp', ComputationOfPointsEntry.tableName) =>
        FormPdf.buildComputationOfPointsPdf(
          ComputationOfPointsEntry.fromJson(record),
          signatures: _bundle,
        ),
      ('rsp', WorkExperienceSheetEntry.tableName) =>
        FormPdf.buildWorkExperienceSheetPdf(
          WorkExperienceSheetEntry.fromJson(record),
          signatures: _bundle,
        ),
      ('rsp', TurnAroundTimeEntry.tableName) => FormPdf.buildTurnAroundTimePdf(
        TurnAroundTimeEntry.fromJson(record),
        signatures: _bundle,
      ),
      ('ld', IdpEntry.tableName) => FormPdf.buildIdpPdf(
        IdpEntry.fromJson(record),
        signatures: _bundle,
      ),
      ('ld', ActionBrainstormingEntry.tableName) =>
        FormPdf.buildActionBrainstormingCoachingPdf(
          ActionBrainstormingEntry.fromJson(record),
          signatures: _bundle,
        ),
      _ => throw StateError('This source form cannot be previewed.'),
    };
    return (await document).save();
  }

  Future<void> _loadPreview() async {
    if (_pdfLoading) return;
    setState(() {
      _showPreview = true;
      _pdfLoading = true;
      _pdfError = null;
    });
    try {
      // Yield so the dialog can paint the loading state before heavy work.
      await Future<void>.delayed(Duration.zero);
      final bytes = await _buildPdfBytes();
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _pdfLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pdfError = error;
        _pdfLoading = false;
      });
    }
  }

  void _signatureChanged(DocuTrackerSourceSignatureBundle bundle) {
    setState(() {
      _bundle = bundle;
      // Invalidate cached preview only; do not remount signature cards.
      _pdfBytes = null;
      _pdfError = null;
    });
    widget.onChanged?.call();
  }

  Future<void> _print() async {
    try {
      if (_pdfBytes == null) {
        setState(() {
          _pdfLoading = true;
          _pdfError = null;
        });
        final bytes = await _buildPdfBytes();
        if (!mounted) return;
        setState(() {
          _pdfBytes = bytes;
          _pdfLoading = false;
        });
      }
      final bytes = _pdfBytes;
      if (bytes == null) return;
      await Printing.layoutPdf(
        name: widget.request.formName,
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pdfLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open print preview.')),
      );
    }
  }

  Widget _buildSignaturePanel() {
    final assignedSlots = _bundle.signatures
        .where((signature) => _bundle.canAssign || signature.canSign)
        .toList(growable: false);
    if (assignedSlots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No signature slots available for your account on this form.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: assignedSlots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final signature = assignedSlots[index];
        return DocuTrackerSourceSignatureCard(
          key: ValueKey(
            'request-${widget.request.sourceRecordId}-${signature.slotKey}',
          ),
          sourceModule: widget.request.sourceModule,
          sourceTable: widget.request.sourceTable,
          sourceRecordId: widget.request.sourceRecordId,
          slotKey: signature.slotKey,
          title: '${signature.label} signature',
          unsignedMessage: 'Your signature is required',
          waitingMessage: 'Only the assigned account can sign.',
          savedMessage: '${signature.label} signature saved.',
          initialBundle: _bundle,
          onChanged: _signatureChanged,
        );
      },
    );
  }

  Widget _buildPreviewPane() {
    if (!_showPreview) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 40,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              const Text(
                'Sign first — load the form preview only when you need it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DocuTrackerTokens.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _pdfLoading ? null : _loadPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Load form preview'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pdfLoading && _pdfBytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Preparing form preview…',
              style: TextStyle(color: DocuTrackerTokens.textMuted),
            ),
          ],
        ),
      );
    }
    if (_pdfError != null && _pdfBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              const SizedBox(height: 8),
              const Text(
                'Preview could not be built.\nYou can still sign from the panel.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadPreview, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final bytes = _pdfBytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PdfPreview(
      key: ValueKey('source-preview-${bytes.length}'),
      build: (_) async => bytes,
      initialPageFormat: PdfPageFormat.letter,
      dpi: 60,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      actions: const [],
      maxPageWidth: 640,
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 760;
    final wide = _showPreview && !mobile;

    return Dialog(
      insetPadding: EdgeInsets.all(mobile ? 0 : 24),
      child: SizedBox(
        // Compact by default — expand only when preview is requested.
        width: mobile
            ? size.width
            : wide
            ? 1100
            : 440,
        height: mobile ? size.height : size.height * 0.86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.request.formName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.request.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DocuTrackerTokens.subtitleStyle(context),
                        ),
                      ],
                    ),
                  ),
                  if (!_showPreview)
                    IconButton(
                      tooltip: 'Load form preview',
                      onPressed: _pdfLoading ? null : _loadPreview,
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                  IconButton(
                    tooltip: 'Print',
                    onPressed: _pdfLoading ? null : _print,
                    icon: const Icon(Icons.print_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: mobile
                  ? Column(
                      children: [
                        Expanded(flex: 6, child: _buildSignaturePanel()),
                        if (_showPreview) ...[
                          const Divider(height: 1),
                          Expanded(flex: 5, child: _buildPreviewPane()),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        if (_showPreview) ...[
                          Expanded(child: _buildPreviewPane()),
                          const VerticalDivider(width: 1),
                        ],
                        SizedBox(
                          width: _showPreview ? 360 : 440,
                          child: _buildSignaturePanel(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
