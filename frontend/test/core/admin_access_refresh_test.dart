import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/core/services/admin_access_refresh.dart';

class _Realtime extends AppRealtimeProvider {
  final stream = StreamController<AppRealtimeEvent>.broadcast(sync: true);
  bool online = false;
  @override
  Stream<AppRealtimeEvent> get events => stream.stream;
  @override
  bool get connected => online;
  void connect() {
    online = true;
    notifyListeners();
  }

  void disconnect() {
    online = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stream.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'access events pause while hidden and resume with one authoritative refresh',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final realtime = _Realtime();
      var calls = 0;
      final binding = AdminAccessRefresh(
        realtime: realtime,
        onRefresh: () async {
          calls++;
        },
      );
      await binding.refresh();
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      realtime.stream.add(const AppRealtimeEvent(name: 'admin_access_changed'));
      realtime.connect();
      await binding.refresh();
      await tester.pump();
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 2);
      binding.dispose();
      realtime.dispose();
    },
  );
  test(
    'access event and reconnect refresh; unrelated events and disposed listeners do not',
    () async {
      final realtime = _Realtime();
      var calls = 0;
      final binding = AdminAccessRefresh(
        realtime: realtime,
        onRefresh: () async {
          calls++;
        },
      );
      realtime.stream.add(const AppRealtimeEvent(name: 'leave_updated'));
      expect(calls, 0);
      realtime.stream.add(const AppRealtimeEvent(name: 'admin_access_changed'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      realtime.connect();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      realtime.notifyListeners();
      expect(calls, 2);
      realtime.disconnect();
      realtime.connect();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
      binding.dispose();
      realtime.stream.add(const AppRealtimeEvent(name: 'admin_access_changed'));
      expect(calls, 3);
      realtime.dispose();
    },
  );
  test(
    'events during refresh queue a follow-up instead of overlapping',
    () async {
      final realtime = _Realtime();
      final first = Completer<void>();
      var calls = 0;
      final binding = AdminAccessRefresh(
        realtime: realtime,
        onRefresh: () async {
          calls++;
          if (calls == 1) await first.future;
        },
      );
      realtime.stream.add(const AppRealtimeEvent(name: 'admin_access_changed'));
      realtime.stream.add(const AppRealtimeEvent(name: 'admin_access_changed'));
      expect(calls, 1);
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      binding.dispose();
      realtime.dispose();
    },
  );
}
