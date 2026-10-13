import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/active_assistant_field.dart';

void main() {
  testWidgets(
    'active context clears on type change and disposal; stale actions are rejected',
    (tester) async {
      final controller = TextEditingController(text: 'my facts');
      Widget form(String type) => MaterialApp(
        home: Scaffold(
          body: ActiveAssistantField(
            module: 'leave',
            type: type,
            fieldKey: 'reason',
            read: () => controller.text,
            apply: (text) => controller.text = text,
            child: TextField(controller: controller),
          ),
        ),
      );
      await tester.pumpWidget(form('vacationLeave'));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final old = ActiveAssistantForm.current!;
      expect(old.context['facts'], 'my facts');
      final payload = {
        'module': 'leave',
        'leaveType': 'vacationLeave',
        'fieldKey': 'reason',
        'value': 'reviewed',
      };
      expect(
        ActiveAssistantForm.apply(old, {...payload, 'fieldKey': 'other'}),
        false,
      );
      expect(ActiveAssistantForm.apply(old, payload), true);
      expect(controller.text, 'reviewed');
      await tester.pumpWidget(form('sickLeave'));
      expect(ActiveAssistantForm.current, isNull);
      expect(ActiveAssistantForm.apply(old, payload), false);
      await tester.pumpWidget(const SizedBox());
      expect(ActiveAssistantForm.current, isNull);
      controller.dispose();
    },
  );
}
