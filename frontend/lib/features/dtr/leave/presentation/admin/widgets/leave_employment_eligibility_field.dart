import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employment_type_field.dart';

class LeaveEmploymentEligibilityField extends StatelessWidget {
  const LeaveEmploymentEligibilityField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<String>? value;
  final ValueChanged<List<String>?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Eligible employment types'),
          subtitle: const Text(
            'Off: no employment-type restriction. On: only the selected types can file.',
          ),
          value: value != null,
          onChanged: enabled
              ? (restricted) => onChanged(
                  restricted ? employmentTypeLabels.keys.toList() : null,
                )
              : null,
        ),
      ),
      if (value != null)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: {...employmentTypeLabels, 'regular': 'Regular (legacy)'}
              .entries
              .map(
                (entry) => FilterChip(
                  label: Text(entry.value),
                  selected: value!.contains(entry.key),
                  onSelected: enabled
                      ? (selected) {
                          final next = [...value!];
                          if (selected) {
                            next.add(entry.key);
                          } else {
                            next.remove(entry.key);
                          }
                          onChanged(next);
                        }
                      : null,
                ),
              )
              .toList(),
        ),
      if (value?.isEmpty == true)
        const Text('Select at least one employment type.'),
    ],
  );
}
