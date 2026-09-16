import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    barrierDismissible: false,
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
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    _bundle = widget.request.signatureBundle;
  }

  Future<Uint8List> _buildPdf() async {
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

  void _signatureChanged(DocuTrackerSourceSignatureBundle bundle) {
    setState(() {
      _bundle = bundle;
      _previewRevision++;
    });
    widget.onChanged?.call();
  }

  Widget _buildSignaturePanel() {
    final assignedSlots = _bundle.signatures
        .where((signature) => _bundle.canAssign || signature.canSign)
        .toList(growable: false);
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
          onChanged: _signatureChanged,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 760;
    return Dialog(
      insetPadding: EdgeInsets.all(mobile ? 0 : 24),
      child: SizedBox(
        width: mobile ? size.width : 1180,
        height: mobile ? size.height : size.height * 0.9,
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
                        Expanded(flex: 5, child: _buildPreview()),
                        const Divider(height: 1),
                        Expanded(flex: 4, child: _buildSignaturePanel()),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _buildPreview()),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 360, child: _buildSignaturePanel()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return PdfPreview(
      key: ValueKey('source-request-preview-$_previewRevision'),
      build: (_) => _buildPdf(),
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: false,
      maxPageWidth: 900,
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );
  }
}
