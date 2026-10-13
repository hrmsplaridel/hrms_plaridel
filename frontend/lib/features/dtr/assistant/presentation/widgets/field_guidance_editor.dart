import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

class FieldGuidanceEditor extends StatelessWidget {
  const FieldGuidanceEditor({
    super.key,
    required this.field,
    required this.onChanged,
    this.enabled = true,
  });
  final LeaveCustomFieldDefinition field;
  final bool enabled;
  final void Function(String instruction, String example, String template)
  onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 12),
      TextFormField(
        initialValue: field.instruction,
        enabled: enabled,
        maxLength: 1000,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Field instruction',
          hintText: 'Explain what the employee should enter.',
        ),
        onChanged: (value) =>
            onChanged(value, field.example, field.sentenceTemplate),
      ),
      TextFormField(
        initialValue: field.example,
        enabled: enabled,
        maxLength: 1000,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Example input',
          hintText: 'A sample only, not facts about the employee.',
        ),
        onChanged: (value) =>
            onChanged(field.instruction, value, field.sentenceTemplate),
      ),
      if (field.type == LeaveCustomFieldType.text ||
          field.type == LeaveCustomFieldType.longText)
        TextFormField(
          initialValue: field.sentenceTemplate,
          enabled: enabled,
          maxLength: 1000,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Suggested sentence template',
            hintText:
                'I am requesting permission to visit [office] to [purpose].',
          ),
          onChanged: (value) =>
              onChanged(field.instruction, field.example, value),
        ),
    ],
  );
}
