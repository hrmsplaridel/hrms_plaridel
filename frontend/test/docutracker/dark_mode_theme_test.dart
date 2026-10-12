import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:provider/provider.dart';

/// Anything brighter than this on a dark surface reads as a white flash.
const double _maxDarkLuminance = 0.12;

Future<BuildContext> _themedContext(
  WidgetTester tester,
  ThemeData theme,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

DocuTrackerDocument _dtr(int i) => DocuTrackerDocument.fromJson({
  'id': 'source:dtr:leave-$i',
  'document_type': 'dtr',
  'title': 'Leave $i',
  'status': 'pending',
  'source_module': 'dtr',
  'source_table': 'leave_requests',
  'source_record_id': 'leave-$i',
  'source_status': 'draft',
  'source_action': 'complete_in_dtr',
  'source_action_label': 'Complete and submit in DTR',
  'source_only': true,
});

void main() {
  const lightPale = Color(0xFFF0F5FF);
  const accent = Color(0xFF8B5CF6);

  testWidgets('token helpers keep light-mode colors unchanged', (tester) async {
    final context = await _themedContext(tester, AppTheme.lightTheme);

    expect(
      DocuTrackerTokens.tintOf(context, light: lightPale, accent: accent),
      lightPale,
    );
    expect(DocuTrackerTokens.raisedOf(context, light: lightPale), lightPale);
    expect(
      DocuTrackerTokens.hoverSurfaceOf(context, light: lightPale),
      lightPale,
    );
    expect(
      DocuTrackerTokens.hoverBorderOf(context, light: lightPale),
      lightPale,
    );
    expect(
      DocuTrackerTokens.accentTextOf(context, light: accent, dark: lightPale),
      accent,
    );
  });

  testWidgets('dark-mode hover and tinted surfaces never turn pale', (
    tester,
  ) async {
    final context = await _themedContext(tester, AppTheme.darkTheme);

    final surfaces = <String, Color>{
      'hover': DocuTrackerTokens.hoverSurfaceOf(context, light: lightPale),
      'tint': DocuTrackerTokens.tintOf(
        context,
        light: lightPale,
        accent: accent,
        darkAlpha: 0.28,
      ),
      'raised': DocuTrackerTokens.raisedOf(context, light: lightPale),
      'inset': DocuTrackerTokens.insetOf(context),
      'peach': DocuTrackerTokens.highlightPeachOf(context),
      'surface': DocuTrackerTokens.surfaceOf(context),
    };
    for (final entry in surfaces.entries) {
      expect(
        entry.value.computeLuminance(),
        lessThan(_maxDarkLuminance),
        reason: '${entry.key} surface is too bright in dark mode',
      );
    }
    expect(
      DocuTrackerTokens.hoverSurfaceOf(context, light: lightPale),
      isNot(DocuTrackerTokens.surfaceOf(context)),
      reason: 'hover must still be distinguishable from the resting card',
    );
  });

  test('dark color scheme containers stay dark', () {
    final scheme = AppTheme.darkTheme.colorScheme;
    final containers = <String, Color>{
      'primaryContainer': scheme.primaryContainer,
      'secondaryContainer': scheme.secondaryContainer,
      'errorContainer': scheme.errorContainer,
      'surfaceContainerLow': scheme.surfaceContainerLow,
      'surfaceContainer': scheme.surfaceContainer,
      'surfaceContainerHigh': scheme.surfaceContainerHigh,
      'surfaceContainerHighest': scheme.surfaceContainerHighest,
      'outlineVariant': scheme.outlineVariant,
    };
    for (final entry in containers.entries) {
      expect(
        entry.value.computeLuminance(),
        lessThan(_maxDarkLuminance),
        reason: '${entry.key} falls back to a saturated or pale color',
      );
    }
  });

  testWidgets('required action cards paint hover ink above their fill', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 2000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<DocuTrackerProvider>.value(
        value: DocuTrackerProvider(),
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocuTrackerRequiredActionsPanel(
                documents: [_dtr(1)],
                sourceRequests: const [],
                loading: false,
                hasPartialError: false,
                onRefreshSignatures: () async {},
                onDocumentTap: (_) async => false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('Leave 1');
    final inkWell = find.ancestor(of: title, matching: find.byType(InkWell));
    expect(inkWell, findsWidgets);

    // The card fill must be an Ink decoration inside the InkWell, otherwise
    // the hover overlay is painted underneath an opaque container.
    expect(
      find.descendant(of: inkWell.first, matching: find.byType(Ink)),
      findsWidgets,
    );
    final hostMaterial = tester.widget<Material>(
      find.ancestor(of: inkWell.first, matching: find.byType(Material)).first,
    );
    expect(hostMaterial.type, MaterialType.transparency);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(title));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
