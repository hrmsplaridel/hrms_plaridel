import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_privacy_consent_storage.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PrivacyAuthProvider extends AuthProvider {
  @override
  AppUser? get user => const AppUser(
    id: 'employee-privacy-test',
    email: 'employee@test.local',
    role: 'employee',
  );
}

class _PrivacyAssistantApi extends DtrAssistantApi {
  @override
  Future<({String defaultModelProfile, List<DtrAssistantModelProfile> models})>
  fetchModels() async {
    return (
      defaultModelProfile: 'tools_ollama',
      models: const [
        DtrAssistantModelProfile(
          id: 'tools_ollama',
          label: 'Qwen + HRMS tools',
          engine: 'tools',
          provider: 'ollama',
          model: 'test-local',
        ),
        DtrAssistantModelProfile(
          id: 'tools_groq',
          label: 'Groq + HRMS tools',
          engine: 'tools',
          provider: 'groq',
          model: 'test-cloud',
          external: true,
          requiresConsent: true,
          consentVersion: '2026-09-02-v1',
          dataDisclosure:
              'Your question and minimum required HRMS data are processed by Groq.',
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('model profile parses external processing metadata', () {
    final profile = DtrAssistantModelProfile.fromJson({
      'id': 'tools_groq',
      'label': 'Groq',
      'engine': 'tools',
      'provider': 'groq',
      'model': 'test',
      'external': true,
      'requiresConsent': true,
      'consentVersion': 'privacy-v1',
      'dataDisclosure': 'Minimum HRMS data is processed in the cloud.',
    });

    expect(profile.external, isTrue);
    expect(profile.requiresConsent, isTrue);
    expect(profile.consentVersion, 'privacy-v1');
    expect(profile.dataDisclosure, contains('cloud'));
  });

  test(
    'external AI consent is employee, provider, and version specific',
    () async {
      expect(
        await DtrAssistantPrivacyConsentStorage.hasConsent(
          userId: 'employee-1',
          provider: 'groq',
          version: 'v1',
        ),
        isFalse,
      );

      await DtrAssistantPrivacyConsentStorage.grantConsent(
        userId: 'employee-1',
        provider: 'groq',
        version: 'v1',
      );

      expect(
        await DtrAssistantPrivacyConsentStorage.hasConsent(
          userId: 'employee-1',
          provider: 'groq',
          version: 'v1',
        ),
        isTrue,
      );
      expect(
        await DtrAssistantPrivacyConsentStorage.hasConsent(
          userId: 'employee-2',
          provider: 'groq',
          version: 'v1',
        ),
        isFalse,
      );
      expect(
        await DtrAssistantPrivacyConsentStorage.hasConsent(
          userId: 'employee-1',
          provider: 'groq',
          version: 'v2',
        ),
        isFalse,
      );
    },
  );

  testWidgets('cloud model selection requires explicit employee consent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _PrivacyAuthProvider(),
        child: MaterialApp(
          home: EmployeeDtrAssistantPage(api: _PrivacyAssistantApi()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('AI model'));
    await tester.pump();
    await tester.tap(find.text('Groq + HRMS tools'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('dtr-assistant-external-ai-consent-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('processed by Groq'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Qwen'), findsOneWidget);

    await tester.tap(find.byTooltip('AI model'));
    await tester.pump();
    await tester.tap(find.text('Groq + HRMS tools'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('dtr-assistant-external-ai-consent-accept')),
    );
    await tester.pump();

    expect(find.text('Groq'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
