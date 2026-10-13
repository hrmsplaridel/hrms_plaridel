import 'package:flutter/material.dart';

/// Ephemeral bindings to mounted form fields. Never restored from chat history.
class ActiveAssistantFieldBinding {
  ActiveAssistantFieldBinding(
    this.id,
    this.module,
    this.type,
    this.fieldKey,
    this.read,
    this.apply,
  );
  final Object id;
  final String token = DateTime.now().microsecondsSinceEpoch.toString();
  final String module, type, fieldKey;
  final String Function() read;
  final void Function(String) apply;
  Map<String, dynamic> get context => {
    'module': module,
    if (module == 'leave') 'leaveType': type,
    if (module == 'locator') 'locatorType': type,
    'fieldKey': fieldKey,
    'task': 'chat',
    'bindingId': token,
    'facts': read(),
  };
}

class ActiveAssistantForm {
  static ActiveAssistantFieldBinding? current;
  static bool apply(
    ActiveAssistantFieldBinding binding,
    Map<String, dynamic> payload,
  ) {
    if (!identical(current, binding) ||
        (payload['module'] ?? 'leave') != binding.module ||
        payload[binding.module == 'leave' ? 'leaveType' : 'locatorType'] !=
            binding.type ||
        payload['fieldKey'] != binding.fieldKey ||
        payload['value'] is! String) {
      return false;
    }
    binding.apply(payload['value'] as String);
    return true;
  }
}

class ActiveAssistantField extends StatefulWidget {
  const ActiveAssistantField({
    super.key,
    required this.module,
    required this.type,
    required this.fieldKey,
    required this.read,
    required this.apply,
    required this.child,
  });
  final String module, type, fieldKey;
  final String Function() read;
  final void Function(String) apply;
  final Widget child;
  @override
  State<ActiveAssistantField> createState() => _ActiveAssistantFieldState();
}

class _ActiveAssistantFieldState extends State<ActiveAssistantField> {
  ActiveAssistantFieldBinding? _binding;
  void _activate() {
    _binding = ActiveAssistantFieldBinding(
      Object(),
      widget.module,
      widget.type,
      widget.fieldKey,
      () => widget.read(),
      (value) {
        if (mounted) widget.apply(value);
      },
    );
    ActiveAssistantForm.current = _binding;
  }

  @override
  void didUpdateWidget(ActiveAssistantField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.fieldKey != widget.fieldKey ||
        oldWidget.module != widget.module) {
      if (identical(ActiveAssistantForm.current, _binding)) {
        ActiveAssistantForm.current = null;
      }
      _binding = null;
    }
  }

  @override
  void dispose() {
    if (identical(ActiveAssistantForm.current, _binding)) {
      ActiveAssistantForm.current = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (focused) _activate();
    },
    child: widget.child,
  );
}
