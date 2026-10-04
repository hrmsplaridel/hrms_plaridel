import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/system_health_page.dart';

Map<String, dynamic> snapshot({bool stale = false}) => {
  'stale': stale,
  'storageHealthy': true,
  'sampleCount': 1,
  'generatedAt': 1790985600000,
  'bucketMs': 60000,
  'current': {
    'timestamp': 1790985600000,
    'cpuPercent': 25.0,
    'memory': {'percent': 50.0, 'usedBytes': 1024, 'totalBytes': 2048},
    'disk': {
      'percent': 60.0,
      'availableBytes': 1024,
      'usedBytes': 1536,
      'totalBytes': 2560,
    },
    'database': {'online': false, 'latencyMs': null},
    'uptimeSeconds': 120,
    'warnings': ['Database connection failed'],
  },
  'history': [],
  'recentWarnings': [],
};

void main() {
  testWidgets(
    'failed range switch retains readings and chart range until retry succeeds',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <int>[];
      final pending = Completer<Map<String, dynamic>>();
      final data = snapshot();
      data['history'] = [
        {
          'timestamp': data['generatedAt'],
          'cpuPercent': 25,
          'memoryPercent': 50,
          'diskPercent': 60,
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPage(
              load: (hours) async {
                requests.add(hours);
                if (requests.length == 2) return pending.future;
                return data;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 days'));
      await tester.pump();
      expect(find.text('25.0%'), findsOneWidget);
      expect(tester.widget<LineChart>(find.byType(LineChart)).data.maxX, 24);
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('25.0%'), findsOneWidget);
      expect(
        find.textContaining('Could not load 7 days. Still showing 24 hours'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
            .onSelectionChanged,
        isNotNull,
      );
      expect(tester.widget<LineChart>(find.byType(LineChart)).data.maxX, 24);
      await tester.tap(find.byTooltip('Refresh system health'));
      await tester.pumpAndSettle();
      expect(requests, [24, 168, 168]);
      expect(tester.widget<LineChart>(find.byType(LineChart)).data.maxX, 168);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(find.text('Showing 7 days'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('initial failure keeps range controls available for recovery', (
    tester,
  ) async {
    final requests = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SystemHealthPage(
            load: (hours) async {
              requests.add(hours);
              if (requests.length == 1) throw Exception('offline');
              return snapshot();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsOneWidget);
    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();
    expect(requests, [24, 1]);
    expect(find.text('25.0%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history handles unavailable CPU samples and gaps', (
    tester,
  ) async {
    final data = snapshot();
    data['history'] = [
      {
        'timestamp': 1790982000000,
        'cpuPercent': null,
        'memoryPercent': 50,
        'diskPercent': 60,
      },
      {
        'timestamp': 1790985600000,
        'cpuPercent': null,
        'memoryPercent': 55,
        'diskPercent': 60,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SystemHealthPage(load: (_) async => data)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Resource history'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'displays readings and database failure without declaring healthy',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SystemHealthPage(load: (_) async => snapshot())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'stale readings and refresh failures are visible on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemHealthPage(
              load: (_) async {
                if (fail) throw Exception('offline');
                return snapshot(stale: true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Readings are stale'), findsOneWidget);
      fail = true;
      await tester.tap(find.byTooltip('Refresh system health'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to refresh system health'),
        findsOneWidget,
      );
      expect(find.text('25.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
