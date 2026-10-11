import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/services/foreground_refresh.dart';

void main() {
  testWidgets(
    'polling pauses in background and refreshes immediately on return',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var calls = 0;
      final refresh = ForegroundRefresh(
        interval: () => const Duration(seconds: 30),
        onRefresh: () async {
          calls++;
        },
      );
      await refresh.refresh();
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await refresh.refresh();
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 3);
      refresh.dispose();
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 3);
    },
  );
  testWidgets(
    'slow refreshes share a request and resume queues only one fresh pass',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final first = Completer<void>();
      var calls = 0;
      final refresh = ForegroundRefresh(
        interval: () => const Duration(seconds: 10),
        onRefresh: () async {
          calls++;
          if (calls == 1) await first.future;
        },
      );
      final initial = refresh.refresh();
      refresh.refresh();
      refresh.refresh();
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      refresh.refresh(trailing: true);
      first.complete();
      await initial;
      expect(calls, 2);
      refresh.dispose();
    },
  );
  testWidgets(
    'poll interval follows status changes and errors do not stop polling',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var running = false;
      var calls = 0;
      final refresh = ForegroundRefresh(
        interval: () => Duration(seconds: running ? 10 : 60),
        onRefresh: () async {
          calls++;
          if (calls == 2) throw StateError('temporary failure');
        },
      );
      await refresh.refresh();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      running = true;
      await refresh.refresh();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 3);
      refresh.dispose();
    },
  );
}
