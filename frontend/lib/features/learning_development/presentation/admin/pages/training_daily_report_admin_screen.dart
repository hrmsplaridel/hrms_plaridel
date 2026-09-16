import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/ld_training_daily_reports_section.dart';

class TrainingDailyReportAdminScreen extends StatelessWidget {
  const TrainingDailyReportAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashPanelOf(context),
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 148,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
            label: const Text(
              'Back to L&D',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
          ),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: LdTrainingDailyReportsSection(),
      ),
    );
  }
}
