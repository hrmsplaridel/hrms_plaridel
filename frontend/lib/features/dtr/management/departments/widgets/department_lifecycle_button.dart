import 'package:flutter/material.dart';

class DepartmentLifecycleButton extends StatelessWidget {
  const DepartmentLifecycleButton({
    super.key,
    required this.isActive,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final bool isActive;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.red : Colors.green;
    return OutlinedButton.icon(
      onPressed: isActive ? onDeactivate : onReactivate,
      icon: Icon(
        isActive ? Icons.person_off_rounded : Icons.restore_rounded,
        size: 18,
      ),
      label: Text(isActive ? 'Deactivate' : 'Reactivate'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
    );
  }
}
