import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/services/foreground_poller.dart';

void main() {
  testWidgets('polling stops while hidden and restarts on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final poller = ForegroundPoller(
      interval: const Duration(seconds: 30),
      onTick: () => calls++,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    poller.cancel();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
  });
}
