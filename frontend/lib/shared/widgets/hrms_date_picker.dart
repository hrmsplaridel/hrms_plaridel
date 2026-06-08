import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

Future<DateTime?> showHrmsDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    builder: (context, child) {
      final dark = AppTheme.dashIsDark(context);
      final panel = AppTheme.dashPanelOf(context);
      final text = AppTheme.dashTextPrimaryOf(context);
      final muted = AppTheme.dashTextSecondaryOf(context);
      final scheme = Theme.of(context).colorScheme.copyWith(
        primary: AppTheme.primaryNavy,
        onPrimary: Colors.white,
        surface: panel,
        onSurface: text,
        surfaceTint: Colors.transparent,
        secondary: AppTheme.primaryNavyLight,
        onSecondary: Colors.white,
      );

      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: scheme,
          dialogTheme: DialogThemeData(
            backgroundColor: panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: panel,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: panel,
            headerForegroundColor: text,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            dividerColor: AppTheme.dashHairlineOf(context),
            weekdayStyle: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            dayStyle: TextStyle(
              color: text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            yearStyle: TextStyle(
              color: text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            todayForegroundColor: WidgetStatePropertyAll(
              dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
            ),
            todayBorder: BorderSide(
              color: dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: dark
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}
