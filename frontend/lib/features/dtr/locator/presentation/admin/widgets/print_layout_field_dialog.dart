import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

class PrintLayoutFieldDialog extends StatefulWidget {
  const PrintLayoutFieldDialog({super.key, required this.existingFields});
  final List<LeaveCustomFieldDefinition> existingFields;

  @override
  State<PrintLayoutFieldDialog> createState() => _PrintLayoutFieldDialogState();
}

class _PrintLayoutFieldDialogState extends State<PrintLayoutFieldDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(), _options = TextEditingController();
  LeaveCustomFieldType _type = LeaveCustomFieldType.text;
  bool _required = false;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  List<String> get _choices => _options.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  void _create() {
    if (!_formKey.currentState!.validate()) return;
    if (widget.existingFields.length >= 20) return;
    var sequence = DateTime.now().microsecondsSinceEpoch;
    var key = 'custom_field_$sequence';
    while (widget.existingFields.any((f) => f.key == key)) {
      key = 'custom_field_${++sequence}';
    }
    Navigator.of(context).pop(
      LeaveCustomFieldDefinition(
        key: key,
        label: _label.text.trim(),
        type: _type,
        required: _required,
        maxLength: _type == LeaveCustomFieldType.longText ? 2000 : 255,
        options: _type == LeaveCustomFieldType.select ? _choices : const [],
      ),
    );
  }

  InputDecoration _decoration(String label) =>
      AppTheme.dashInputDecoration(context, labelText: label, radius: 8);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create new field'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add a field to the filing form and place it on this printed page.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                autofocus: true,
                maxLength: 80,
                decoration: _decoration('Field label'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a field label.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LeaveCustomFieldType>(
                initialValue: _type,
                isExpanded: true,
                decoration: _decoration('Input type'),
                items: [
                  for (final type in LeaveCustomFieldType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required'),
                value: _required,
                onChanged: (v) => setState(() => _required = v ?? false),
              ),
              if (_type == LeaveCustomFieldType.select)
                TextFormField(
                  controller: _options,
                  minLines: 3,
                  maxLines: 5,
                  decoration: _decoration('Options (one per line)'),
                  validator: (_) {
                    if (_choices.isEmpty) return 'Enter at least one option.';
                    if (_choices.length > 20) return 'Use at most 20 options.';
                    if (_choices.any((s) => s.length > 80)) {
                      return 'Each option must be 80 characters or less.';
                    }
                    return null;
                  },
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _create, child: const Text('Create field')),
    ],
  );
}
