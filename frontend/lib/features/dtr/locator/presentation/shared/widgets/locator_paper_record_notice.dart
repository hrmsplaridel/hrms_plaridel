import 'package:flutter/material.dart';
import 'package:hrms_plaridel/shared/widgets/form_settings_section.dart';

class LocatorPaperRecordNotice extends StatelessWidget {
  const LocatorPaperRecordNotice({
    super.key,
    required this.record,
    this.reconciliationRequired = false,
  });
  final Map<String, dynamic> record;
  final bool reconciliationRequired;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: FormSettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Approved paper locator record',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Original filing: ${record['original_filing_date']}'),
          Text('Paper approval: ${record['approval_date']}'),
          Text('Approved by: ${record['final_approver']?['name'] ?? ''}'),
          Text('Encoded by: ${record['encoded_by_name'] ?? ''}'),
          const SizedBox(height: 8),
          const Text(
            'The attachment is the signed original. Saved signatures were copied when available. No further approval routing is required.',
          ),
          if (reconciliationRequired)
            const Text(
              'Attendance for this month was already processed. Reconcile the month to update posted attendance deductions.',
            ),
        ],
      ),
    ),
  );
}
