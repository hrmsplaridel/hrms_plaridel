import 'package:flutter/material.dart';

const employmentTypeLabels = <String, String>{
  'permanent': 'Permanent',
  'temporary': 'Temporary',
  'casual': 'Casual',
  'contractual': 'Contractual appointment',
  'coterminous': 'Coterminous',
  'job_order': 'Job Order (JO)',
  'contract_of_service': 'Contract of Service (COS)',
};

/// Shared choices for account creation and employee editing.
class EmploymentTypeField extends StatelessWidget {
  const EmploymentTypeField({
    super.key,
    required this.value,
    required this.decoration,
    required this.onChanged,
    this.hint,
    this.allowUnspecified = true,
  });
  final String? value;
  final InputDecoration decoration;
  final ValueChanged<String?> onChanged;
  final Widget? hint;
  final bool allowUnspecified;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: decoration,
    hint: hint,
    items: [
      if (allowUnspecified)
        const DropdownMenuItem(value: '', child: Text('Not specified')),
      if (value == 'regular')
        const DropdownMenuItem(
          value: 'regular',
          child: Text('Regular (legacy)'),
        ),
      ...employmentTypeLabels.entries.map(
        (entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ),
    ],
    onChanged: (selected) => onChanged(selected == '' ? null : selected),
  );
}
