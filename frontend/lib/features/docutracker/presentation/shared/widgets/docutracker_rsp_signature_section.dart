import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class DocuTrackerRspSignatureSlot {
  const DocuTrackerRspSignatureSlot(this.key, this.label);

  final String key;
  final String label;
}

class DocuTrackerRspSignatureSection extends StatelessWidget {
  const DocuTrackerRspSignatureSection({
    super.key,
    this.sourceModule = 'rsp',
    required this.sourceTable,
    required this.sourceRecordId,
    required this.slots,
    this.helperText =
        'Prepared by is assigned to the form creator. Other fields are assigned to the person who must sign.',
    this.signatureStatus,
    this.onChanged,
    this.showLockedIndicator = false,
  });

  final String sourceModule;
  final String sourceTable;
  final String sourceRecordId;
  final List<DocuTrackerRspSignatureSlot> slots;
  final String helperText;
  final String? signatureStatus;
  final ValueChanged<DocuTrackerSourceSignatureBundle>? onChanged;
  final bool showLockedIndicator;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Required signatures',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_signatureStatusLabel(signatureStatus) != null)
                _SignatureStatusChip(
                  label: _signatureStatusLabel(signatureStatus)!,
                ),
              if (showLockedIndicator && signatureStatus == 'completed')
                const _SignatureStatusChip(label: 'Locked'),
            ],
          ),
          const SizedBox(height: 4),
          Text(helperText, style: DocuTrackerTokens.subtitleStyle(context)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: slots
                    .map(
                      (slot) => SizedBox(
                        width: width,
                        child: DocuTrackerSourceSignatureCard(
                          key: ValueKey(
                            'rsp-signature-$sourceModule-$sourceTable-$sourceRecordId-${slot.key}',
                          ),
                          sourceModule: sourceModule,
                          sourceTable: sourceTable,
                          sourceRecordId: sourceRecordId,
                          slotKey: slot.key,
                          title: '${slot.label} signature',
                          unsignedMessage: 'No signature yet',
                          waitingMessage: 'Assign the person who must sign.',
                          savedMessage: '${slot.label} signature saved.',
                          onChanged: onChanged,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

String? _signatureStatusLabel(String? status) {
  switch (status) {
    case 'needs_setup':
      return 'Needs Setup';
    case 'awaiting_signatures':
      return 'Awaiting Signatures';
    case 'completed':
      return 'Completed';
    default:
      return null;
  }
}

class _SignatureStatusChip extends StatelessWidget {
  const _SignatureStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
