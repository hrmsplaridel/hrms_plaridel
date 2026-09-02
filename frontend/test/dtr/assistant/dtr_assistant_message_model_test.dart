import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';

void main() {
  test('session round trip keeps safe controls and expires exports', () {
    final message = DtrAssistantMessage(
      id: 'message-1',
      role: 'assistant',
      content: 'Your export is ready.',
      createdAt: DateTime.utc(2026, 9, 3),
      suggestions: const [
        DtrAssistantSuggestion(
          text: 'Show my leave balance',
          intent: 'leave_balance',
        ),
      ],
      attachments: [
        DtrAssistantAttachment(
          id: 'private-download-token',
          filename: 'dtr_export_2026-08-01_2026-08-31.pdf',
          mimeType: 'application/pdf',
          downloadUrl: '/api/dtr/assistant/exports/private-download-token',
          contentBase64: 'private-file-content',
          expiresAt: DateTime.utc(2026, 9, 3, 1),
        ),
      ],
      actions: const [
        DtrAssistantAction(
          id: 'download_dtr_export',
          label: 'Download DTR export',
          type: 'download_attachment',
          payload: {'attachmentId': 'private-download-token'},
        ),
        DtrAssistantAction(
          id: 'open_leave_page',
          label: 'Open My Leave',
          type: 'open_leave_page',
          autoExecute: true,
        ),
      ],
    );

    final encoded = jsonEncode(message.toJson());
    final restored = DtrAssistantMessage.fromJson(
      Map<String, dynamic>.from(jsonDecode(encoded) as Map),
    );

    expect(encoded, isNot(contains('private-download-token')));
    expect(encoded, isNot(contains('private-file-content')));
    expect(restored.suggestions.single.text, 'Show my leave balance');
    expect(restored.attachments.single.isExpired, isTrue);
    expect(restored.attachments.single.id, isNull);
    expect(restored.attachments.single.downloadUrl, isEmpty);
    expect(restored.attachments.single.contentBase64, isEmpty);
    expect(
      restored.actions.any((item) => item.type == 'download_attachment'),
      isFalse,
    );
    expect(
      restored.actions
          .singleWhere((item) => item.id == 'open_leave_page')
          .autoExecute,
      isFalse,
    );
    expect(
      restored.actions
          .singleWhere((item) => item.id == 'regenerate_dtr_export')
          .prompt,
      'Generate my DTR export from 2026-08-01 to 2026-08-31.',
    );
  });
}
