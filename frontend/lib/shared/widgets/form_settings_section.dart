import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Shared section frame for related controls in creation and settings forms.
class FormSettingsSection extends StatelessWidget {
  const FormSettingsSection({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.dashMutedSurfaceOf(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
    ),
    child: child,
  );
}
