import 'package:flutter/material.dart';
import 'dtr_routes.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/pages/dtr_time_logs.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/dtr_reports.dart';

/// Shows one DTR screen (Time Logs or DTR Report). Navigation between them is
/// handled by the admin DTR area (see `DtrPage`).
class DtrMain extends StatelessWidget {
  const DtrMain({super.key, required this.section});

  final DtrSection section;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    // Column kept so the screens get the same (unbounded height) layout as before.
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 200),
          child: switch (section) {
            DtrSection.timeLogs => const DtrTimeLogs(),
            DtrSection.reports => const DtrReports(),
          },
        ),
      ],
    ),
  );
}
