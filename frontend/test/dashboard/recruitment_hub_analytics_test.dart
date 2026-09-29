import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/admin_dashboard_desktop.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_hub_analytics.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_monitoring_stats.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

void main() {
  testWidgets('RSP overview shows KPIs, pipeline, and applicant stage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apps = [
      RecruitmentApplication(
        id: '1',
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        status: 'submitted',
        positionAppliedFor: 'Documenter',
        createdAt: DateTime(2026, 9, 6),
      ),
    ];
    final stats = RecruitmentMonitoringStats.fromApps(apps);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecruitmentHubAnalyticsPanel(
              stats: stats,
              activeApplications: apps,
              dateLabel: (_) => 'Sep 6, 2026',
              hiringOpen: true,
              listedPositionCount: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Total Applicants'), findsOneWidget);
    expect(find.text('Pending Review'), findsWidgets);
    expect(find.text('Active Recruitment'), findsOneWidget);
    expect(find.text('Job Vacancies'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Recruitment Pipeline'), findsOneWidget);
    expect(find.text('Application Trend'), findsOneWidget);
    expect(find.text('Status Breakdown'), findsOneWidget);
    expect(find.text('Active Applications'), findsOneWidget);
    expect(find.text('Jane Doe'), findsWidgets);
    expect(find.text('Documenter'), findsWidgets);
    expect(find.text('Requires Attention'), findsOneWidget);
    expect(find.text('Pending document review'), findsOneWidget);
  });

  testWidgets('overview does not wait for optional vacancy request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vacancyRequest = Completer<JobVacancyAnnouncement>();
    addTearDown(() {
      if (!vacancyRequest.isCompleted) {
        vacancyRequest.complete(
          const JobVacancyAnnouncement(hasVacancies: false),
        );
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecruitmentOverviewCard(
              loadApplications: () async => const [],
              loadAnnouncement: () => vacancyRequest.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recruitment Overview'), findsOneWidget);
    expect(find.text('Total Applicants'), findsOneWidget);
    expect(find.byType(RecruitmentHubAnalyticsPanel), findsOneWidget);
  });
}
