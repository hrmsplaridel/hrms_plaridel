import 'package:flutter/material.dart';

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
    required this.sourceTable,
    required this.sourceRecordId,
    required this.slots,
  });

  final String sourceTable;
  final String sourceRecordId;
  final List<DocuTrackerRspSignatureSlot> slots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Required signatures',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Assign each field to the person who must sign. Only that account can add or replace its signature.',
            style: DocuTrackerTokens.subtitleStyle(context),
          ),
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
                            'rsp-signature-$sourceTable-$sourceRecordId-${slot.key}',
                          ),
                          sourceModule: 'rsp',
                          sourceTable: sourceTable,
                          sourceRecordId: sourceRecordId,
                          slotKey: slot.key,
                          title: '${slot.label} signature',
                          unsignedMessage: 'No signature yet',
                          waitingMessage: 'Assign the person who must sign.',
                          savedMessage: '${slot.label} signature saved.',
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
