import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/leave_field_assistant.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

class _FieldApi extends DtrAssistantApi {
  final calls = <Map<String, dynamic>>[];

  @override
  Future<DtrAssistantMessage> sendMessage(
    String message, {
    String? intent,
    String? modelProfile,
    String? conversationId,
    String? externalConsentVersion,
    Map<String, dynamic>? formContext,
    Map<String, dynamic>? requestReference,
    CancelToken? cancelToken,
  }) async {
    calls.add(formContext!);
    return DtrAssistantMessage.fromJson({
      'role': 'assistant',
      'content': formContext['task'] == 'draft'
          ? 'Suggested sentence'
          : 'Field explanation',
      'actions': ifDraft(formContext),
    });
  }

  List<Map<String, dynamic>> ifDraft(Map<String, dynamic> form) =>
      form['task'] == 'draft'
      ? [
          {
            'id': 'use_field_suggestion',
            'type': 'apply_field_suggestion',
            'label': 'Use this suggestion',
            'payload': {
              'module': form['module'],
              if (form['module'] == 'locator') 'locatorType': 'newLeave',
              if (form['module'] == 'leave') 'leaveType': 'newLeave',
              'fieldKey': 'activity',
              'value': 'My reviewed sentence.',
            },
          },
        ]
      : [];
}

void main() {
  test('custom field guidance survives save and reload', () {
    final field = LeaveCustomFieldDefinition.fromJson({
      'key': 'activity',
      'label': 'Activity',
      'type': 'long_text',
      'instruction': 'Explain the purpose.',
      'example': 'A sample activity.',
      'sentence_template': 'I will [activity].',
    });
    final saved = LeaveCustomFieldDefinition.fromJson(field.toJson());
    expect(saved.instruction, field.instruction);
    expect(saved.example, field.example);
    expect(saved.sentenceTemplate, field.sentenceTemplate);
  });
  for (final module in ['leave', 'locator']) {
    testWidgets(
      '$module field suggestion stays unapplied until explicitly accepted',
      (tester) async {
        final api = _FieldApi();
        String? applied;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    applied = await showDialog<String>(
                      context: context,
                      builder: (_) => LeaveFieldAssistant(
                        module: module,
                        leaveType: 'newLeave',
                        fieldKey: 'activity',
                        label: 'Activity',
                        api: api,
                      ),
                    );
                  },
                  child: const Text('Help'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Help'));
        await tester.pumpAndSettle();
        expect(find.text('Field explanation'), findsOneWidget);
        expect(api.calls.single['fieldKey'], 'activity');
        expect(api.calls.single['module'], module);
        expect(
          api.calls.single[module == 'locator' ? 'locatorType' : 'leaveType'],
          'newLeave',
        );
        await tester.enterText(find.byType(TextField), 'My actual activity');
        await tester.tap(find.text('Draft a sentence'));
        await tester.pumpAndSettle();
        expect(api.calls.last['facts'], 'My actual activity');
        expect(applied, isNull);
        expect(find.text('Use this suggestion'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Changed facts');
        await tester.pump();
        expect(find.text('Use this suggestion'), findsNothing);
        await tester.tap(find.text('Draft a sentence'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this suggestion'));
        await tester.pumpAndSettle();
        expect(applied, 'My reviewed sentence.');
      },
    );
  }
}
