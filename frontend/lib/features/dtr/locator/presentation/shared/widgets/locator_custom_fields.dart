import 'package:hrms_plaridel/shared/widgets/profile_modern_ui.dart' show ProfileLabeledField;
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/active_assistant_field.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/field_guidance_editor.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/shared/widgets/form_settings_section.dart';
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';

List<String> locatorAdditionalFieldLines(
  List<LeaveCustomFieldDefinition> fields,
  Map<String, dynamic> values,
) => [
  for (final field in fields)
    if (values[field.key] != null &&
        values[field.key].toString().trim().isNotEmpty)
      '${field.label}: ${values[field.key] is bool ? (values[field.key] == true ? 'Yes' : 'No') : values[field.key]}',
];

class LocatorCustomFieldDetails extends StatelessWidget {
  const LocatorCustomFieldDetails({
    super.key,
    required this.fields,
    required this.values,
  });
  final List<LeaveCustomFieldDefinition> fields;
  final Map<String, dynamic> values;
  @override
  Widget build(BuildContext context) {
    final lines = locatorAdditionalFieldLines(fields, values);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FormSettingsSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Additional details',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }
}

class LocatorCustomFieldInputs extends StatefulWidget {
  const LocatorCustomFieldInputs({
    super.key,
    required this.fields,
    required this.values,
    this.requestType,
  });
  final List<LeaveCustomFieldDefinition> fields;
  final Map<String, dynamic> values;
  final String? requestType;
  @override
  State<LocatorCustomFieldInputs> createState() =>
      _LocatorCustomFieldInputsState();
}

class _LocatorCustomFieldInputsState extends State<LocatorCustomFieldInputs> {
  List<LeaveCustomFieldDefinition> get fields => widget.fields;
  Map<String, dynamic> get values => widget.values;
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return FormSettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Additional details',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.requestType != null)
                    ActiveAssistantField(
                      module: 'locator',
                      type: widget.requestType!,
                      fieldKey: field.key,
                      read: () => values[field.key]?.toString() ?? '',
                      apply: (value) => setState(() {
                        values[field.key] = value;
                        _revision++;
                      }),
                      child: _input(context, field),
                    )
                  else
                    _input(context, field),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _input(BuildContext context, LeaveCustomFieldDefinition field) {
    final decoration = AppTheme.dashInputDecoration(
      context,
    ).copyWith(labelText: '${field.label}${field.required ? ' *' : ''}');
    String? requiredValue(dynamic v) =>
        field.required && (v == null || v.toString().trim().isEmpty)
        ? '${field.label} is required.'
        : null;
    if (field.type == LeaveCustomFieldType.select) {
      return DropdownButtonFormField<String>(
        key: ValueKey(field.key),
        initialValue: field.options.contains(values[field.key])
            ? values[field.key] as String
            : null,
        decoration: decoration,
        isExpanded: true,
        items: [
          for (final option in field.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (v) => values[field.key] = v,
        validator: requiredValue,
      );
    }
    if (field.type == LeaveCustomFieldType.boolean) {
      return DropdownButtonFormField<bool>(
        key: ValueKey(field.key),
        initialValue: values[field.key] as bool?,
        decoration: decoration,
        items: const [
          DropdownMenuItem(value: true, child: Text('Yes')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: (v) => values[field.key] = v,
        validator: requiredValue,
      );
    }
    if (field.type == LeaveCustomFieldType.date) {
      return FormField<String>(
        key: ValueKey(field.key),
        initialValue: values[field.key]?.toString(),
        validator: requiredValue,
        builder: (state) => InkWell(
          onTap: () async {
            final date = await showHrmsDatePicker(
              context: context,
              initialDate:
                  DateTime.tryParse(state.value ?? '') ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (date == null || !context.mounted) return;
            final value =
                '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            values[field.key] = value;
            state.didChange(value);
          },
          child: InputDecorator(
            decoration: decoration.copyWith(
              errorText: state.errorText,
              suffixIcon: IconButton(
                tooltip: 'Clear date',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  values.remove(field.key);
                  state.didChange(null);
                },
              ),
            ),
            child: Text(state.value ?? 'Select date'),
          ),
        ),
      );
    }
    return TextFormField(
      key: ValueKey('${field.key}-$_revision'),
      initialValue: values[field.key]?.toString(),
      decoration: decoration,
      maxLines: field.type == LeaveCustomFieldType.longText ? 4 : 1,
      maxLength: field.type == LeaveCustomFieldType.number
          ? null
          : field.maxLength ??
                (field.type == LeaveCustomFieldType.longText ? 2000 : 255),
      keyboardType: field.type == LeaveCustomFieldType.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      onChanged: (v) => values[field.key] = v.trim(),
      validator: (v) {
        final required = requiredValue(v);
        if (required != null) return required;
        if (field.type == LeaveCustomFieldType.number &&
            (v ?? '').trim().isNotEmpty &&
            !(num.tryParse(v!.trim())?.isFinite ?? false)) {
          return '${field.label} must be a number.';
        }
        return null;
      },
    );
  }
}

class LocatorCustomFieldEditor extends StatelessWidget {
  const LocatorCustomFieldEditor({
    super.key,
    required this.fields,
    required this.onChanged,
    this.enabled = true,
    this.framed = true,
  });
  final List<LeaveCustomFieldDefinition> fields;
  final ValueChanged<List<LeaveCustomFieldDefinition>> onChanged;
  final bool enabled;
  final bool framed;
  void _replace(
    int index, {
    String? label,
    LeaveCustomFieldType? type,
    bool? required,
    List<String>? options,
    String? instruction,
    String? example,
    String? sentenceTemplate,
  }) {
    final field = fields[index];
    final nextType = type ?? field.type;
    final next = List<LeaveCustomFieldDefinition>.from(fields);
    next[index] = LeaveCustomFieldDefinition(
      key: field.key,
      instruction: instruction ?? field.instruction,
      example: example ?? field.example,
      sentenceTemplate: sentenceTemplate ?? field.sentenceTemplate,
      label: label ?? field.label,
      type: nextType,
      required: required ?? field.required,
      maxLength: nextType == field.type
          ? field.maxLength
          : (nextType == LeaveCustomFieldType.longText ? 2000 : 255),
      options: options ?? field.options,
    );
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Additional fields',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: !enabled || fields.length >= 20
                  ? null
                  : () => onChanged([
                      ...fields,
                      LeaveCustomFieldDefinition(
                        key: 'field_${DateTime.now().microsecondsSinceEpoch}',
                        label: '',
                      ),
                    ]),
              icon: const Icon(Icons.add),
              label: const Text('Add field'),
            ),
          ],
        ),
        if (fields.isEmpty)
          const Text('Add fields needed for this locator type.'),
        for (final entry in fields.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              key: ValueKey(entry.value.key),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ProfileLabeledField(
                        label: 'Field label',
                        child: TextFormField(
                          initialValue: entry.value.label,
                          enabled: enabled,
                          maxLength: 100,
                          decoration: AppTheme.dashInputDecoration(
                            context,
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Enter a field label.'
                              : null,
                          onChanged: (v) => _replace(entry.key, label: v),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove field',
                      onPressed: !enabled
                          ? null
                          : () {
                              final next =
                                  List<LeaveCustomFieldDefinition>.from(fields)
                                    ..removeAt(entry.key);
                              onChanged(next);
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                ProfileLabeledField(
                  label: 'Input type',
                  child: DropdownButtonFormField<LeaveCustomFieldType>(
                    initialValue: entry.value.type,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                    ),
                    items: [
                      for (final type in LeaveCustomFieldType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        ),
                    ],
                    onChanged: !enabled
                        ? null
                        : (v) {
                            if (v != null) _replace(entry.key, type: v);
                          },
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Required'),
                    value: entry.value.required,
                    onChanged: !enabled
                        ? null
                        : (v) => _replace(entry.key, required: v),
                  ),
                ),
                if (entry.value.type == LeaveCustomFieldType.select)
                  ProfileLabeledField(
                    label: 'Options (one per line)',
                    child: TextFormField(
                      key: ValueKey('options-${entry.value.key}'),
                      initialValue: entry.value.options.join('\n'),
                      enabled: enabled,
                      maxLines: 3,
                      decoration: AppTheme.dashInputDecoration(
                        context,
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter at least one option.'
                          : null,
                      onChanged: (v) => _replace(
                        entry.key,
                        options: v
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toSet()
                            .toList(),
                      ),
                    ),
                  ),
                FieldGuidanceEditor(
                  field: entry.value,
                  enabled: enabled,
                  onChanged: (instruction, example, template) => _replace(
                    entry.key,
                    instruction: instruction,
                    example: example,
                    sentenceTemplate: template,
                  ),
                ),
                const Divider(),
              ],
            ),
          ),
      ],
    );
    return framed ? FormSettingsSection(child: content) : content;
  }
}
