import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';

class LocatorSignatureSection extends StatelessWidget {
  const LocatorSignatureSection({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final slot in const {
        'applicant': 'Applicant',
        'department_head': 'Head of Office',
        'hr_approver': 'Noted / Final Approver',
      }.entries)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DocuTrackerSourceSignatureCard(
            key: ValueKey('$requestId-${slot.key}'),
            sourceModule: 'dtr',
            sourceTable: 'locator_slips',
            sourceRecordId: requestId,
            slotKey: slot.key,
            title: slot.value,
            unsignedMessage: 'No signature recorded',
            waitingMessage: 'Awaiting the named signer.',
          ),
        ),
    ],
  );
}
