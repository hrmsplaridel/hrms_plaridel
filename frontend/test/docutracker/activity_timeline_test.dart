import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_activity_timeline.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_history_presentation.dart';

DocumentHistoryEntry _entry({
  required String id,
  required String action,
  required DateTime at,
  String? actorName,
  String? remarks,
  DocumentStatus? fromStatus,
  DocumentStatus? toStatus,
  Map<String, dynamic> metadata = const {},
}) {
  return DocumentHistoryEntry(
    id: id,
    documentId: 'doc-1',
    action: action,
    actorName: actorName,
    remarks: remarks,
    fromStatus: fromStatus,
    toStatus: toStatus,
    createdAt: at,
    metadata: metadata,
  );
}

List<DocumentHistoryEntry> _sampleHistory() {
  return [
    _entry(
      id: '1',
      action: 'created',
      at: DateTime.utc(2026, 1, 1, 8),
      actorName: 'Ada',
    ),
    _entry(
      id: '2',
      action: 'signed',
      at: DateTime.utc(2026, 1, 2, 8),
      actorName: 'Bea',
    ),
    _entry(
      id: '3',
      action: 'metadata_updated',
      at: DateTime.utc(2026, 1, 3, 8),
      actorName: 'Ada',
      remarks: 'Moved signed field: Mayor',
    ),
    _entry(
      id: '4',
      action: 'returned',
      at: DateTime.utc(2026, 1, 4, 8),
      actorName: 'Cam',
      fromStatus: DocumentStatus.inReview,
      toStatus: DocumentStatus.returned,
      remarks: 'Please correct the date.',
    ),
    _entry(
      id: '5',
      action: 'released',
      at: DateTime.utc(2026, 1, 5, 8),
      actorName: 'Ada',
      metadata: const {'released_to_department_name': 'Budget'},
    ),
  ];
}

void main() {
  test('history labels use recorded facts and skip unchanged status', () {
    final moved = _sampleHistory()[2];
    expect(docuTrackerHistoryTitle(moved), 'Signature field moved');
    expect(
      docuTrackerHistoryTitle(
        _entry(
          id: 'm',
          action: 'metadata_updated',
          at: DateTime.utc(2026, 1, 1),
        ),
      ),
      'Document details updated',
    );
    expect(
      docuTrackerHistoryTitle(
        _entry(id: 'c', action: 'created', at: DateTime.utc(2026, 1, 1)),
      ),
      'Document created',
    );
    expect(
      docuTrackerHistoryTitle(
        _entry(id: 's', action: 'signed', at: DateTime.utc(2026, 1, 1)),
      ),
      'Signature added',
    );
    expect(
      docuTrackerHistoryTitle(
        _entry(
          id: 'r',
          action: 'released',
          at: DateTime.utc(2026, 1, 1),
          metadata: const {'released_to_department_name': 'Budget'},
        ),
      ),
      'Released to Budget',
    );
    expect(
      docuTrackerHistoryTitle(
        _entry(id: 'u', action: 'custom_export', at: DateTime.utc(2026, 1, 1)),
      ),
      'custom_export',
    );
    expect(
      docuTrackerHistoryActorName(
        _entry(id: 'n', action: 'created', at: DateTime.utc(2026, 1, 1)),
      ),
      isNull,
    );

    final same = DocumentHistoryEntry.fromJson({
      'id': 'same',
      'document_id': 'doc-1',
      'action': 'remark',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    expect(docuTrackerHistoryStatusTransition(same), isNull);

    final changed = _sampleHistory()[3];
    expect(docuTrackerHistoryStatusTransition(changed), 'In Review → Returned');

    final newest = docuTrackerHistoryNewestFirst(_sampleHistory());
    expect(newest.map((entry) => entry.id).toList(), ['5', '4', '3', '2', '1']);
  });

  testWidgets('preview shows the latest three events and opens the full list', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DocuTrackerActivityPreview(
            entries: _sampleHistory(),
            onViewAll: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Released to Budget'), findsOneWidget);
    expect(find.text('Document returned'), findsOneWidget);
    expect(find.text('Signature field moved'), findsOneWidget);
    expect(find.text('Signature added'), findsNothing);
    expect(find.text('Document created'), findsNothing);
    expect(find.textContaining('Ada'), findsWidgets);
    expect(find.textContaining('Employee'), findsNothing);

    await tester.tap(find.byKey(const Key('docutracker-activity-view-all')));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('a preview row expands and collapses its recorded details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerActivityPreview(
            entries: _sampleHistory(),
            onViewAll: () {},
          ),
        ),
      ),
    );

    expect(find.text('Recorded action: returned'), findsNothing);
    await tester.tap(find.text('Document returned'));
    await tester.pump();
    expect(find.text('Status: In Review → Returned'), findsOneWidget);
    expect(find.text('Please correct the date.'), findsOneWidget);
    expect(find.text('Recorded action: returned'), findsOneWidget);

    await tester.tap(find.text('Document returned'));
    await tester.pump();
    expect(find.text('Recorded action: returned'), findsNothing);
  });

  testWidgets('empty history stays empty in the full panel', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DocuTrackerActivityHistoryPanel(localEntries: [])),
      ),
    );

    expect(find.text('No history yet.'), findsOneWidget);
    expect(find.text('0 events'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('docutracker-activity-next')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('full history paginates, filters, and keeps newest first', (
    tester,
  ) async {
    final calls = <(int, String?)>[];
    final entries = [
      for (var i = 0; i < 12; i++)
        _entry(
          id: '$i',
          action: i.isEven ? 'signed' : 'created',
          at: DateTime.utc(2026, 1, i + 1),
          actorName: 'Person $i',
        ),
    ].reversed.toList();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerActivityHistoryPanel(
            loadPage:
                ({required limit, required offset, String? action}) async {
                  calls.add((offset, action));
                  final filtered = entries
                      .where(
                        (entry) => action == null || entry.action == action,
                      )
                      .toList();
                  return DocumentHistoryPage(
                    items: filtered.skip(offset).take(limit).toList(),
                    total: filtered.length,
                    limit: limit,
                    offset: offset,
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls.first, (0, null));
    expect(find.textContaining('Person 11 ·'), findsOneWidget);
    expect(find.textContaining('Person 1 ·'), findsNothing);
    expect(find.textContaining('of 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('docutracker-activity-next')));
    await tester.pumpAndSettle();
    expect(calls.last, (10, null));
    expect(find.textContaining('Person 1 ·'), findsOneWidget);
    expect(find.textContaining('Person 11 ·'), findsNothing);

    await tester.tap(find.byKey(const Key('docutracker-activity-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signature added').last);
    await tester.pumpAndSettle();
    expect(calls.last, (0, 'signed'));
    expect(find.text('Document created'), findsNothing);
    expect(find.text('No activity matches this filter.'), findsNothing);
  });

  testWidgets('internal note starts collapsed and posts through the caller', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? posted;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DocuTrackerInternalNoteComposer(
            controller: controller,
            busy: false,
            onPost: () async {
              posted = controller.text;
              return controller.text.trim().isNotEmpty;
            },
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const Key('docutracker-detail-add-note')));
    await tester.pump();
    expect(
      find.byKey(const Key('docutracker-detail-note-composer')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Check the annex.');
    await tester.tap(find.byKey(const Key('docutracker-detail-post-note')));
    await tester.pumpAndSettle();
    expect(posted, 'Check the annex.');
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('docutracker-detail-add-note')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'discard me');
    await tester.tap(find.byKey(const Key('docutracker-detail-cancel-note')));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('activity rows render in light and dark themes', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          darkTheme: theme,
          themeAnimationDuration: Duration.zero,
          themeMode: theme.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Builder(
            builder: (context) {
              return Scaffold(
                backgroundColor: DocuTrackerTokens.canvasOf(context),
                body: DocuTrackerActivityPreview(
                  entries: _sampleHistory().take(1).toList(),
                  onViewAll: () {},
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('Document created'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text('Document created'));
      final color = title.style?.color;
      expect(color, isNotNull);
      if (theme.brightness == Brightness.dark) {
        expect(color!.computeLuminance(), greaterThan(0.4));
      } else {
        expect(color!.computeLuminance(), lessThan(0.4));
      }
    }
  });

  test('history page reads the live array and the paginated object', () {
    final array = _liveHistoryJson();
    final page = documentHistoryPageFromResponse(array, limit: 10, offset: 0);
    expect(page.total, 10);
    expect(page.items, hasLength(10));
    expect(page.items.map((entry) => entry.action).toList(), [
      'remark',
      'overdue',
      'approved',
      'overdue',
      'submitted',
      'metadata_updated',
      'metadata_updated',
      'metadata_updated',
      'signed',
      'created',
    ]);
    expect(page.items.map((entry) => entry.id).toSet(), hasLength(10));

    final first = documentHistoryPageFromResponse(array, limit: 4, offset: 0);
    final second = documentHistoryPageFromResponse(array, limit: 4, offset: 4);
    final third = documentHistoryPageFromResponse(array, limit: 4, offset: 8);
    expect(
      [
        ...first.items,
        ...second.items,
        ...third.items,
      ].map((e) => e.id).toSet(),
      hasLength(10),
    );

    final created = documentHistoryPageFromResponse(
      array,
      limit: 10,
      offset: 0,
      action: 'created',
    );
    expect(created.total, 1);
    expect(created.items.single.action, 'created');

    final notes = documentHistoryPageFromResponse(
      array,
      limit: 10,
      offset: 0,
      action: 'metadata_updated',
    );
    expect(notes.total, 3);

    final empty = documentHistoryPageFromResponse(
      const <dynamic>[],
      limit: 10,
      offset: 0,
    );
    expect(empty.total, 0);
    expect(empty.items, isEmpty);

    final serverPage = documentHistoryPageFromResponse(
      {'items': array.take(2).toList(), 'total': 10, 'limit': 2, 'offset': 0},
      limit: 2,
      offset: 0,
      action: 'created',
    );
    expect(serverPage.total, 10);
    expect(serverPage.items, hasLength(2));
    expect(serverPage.items.first.action, 'remark');

    final emptyPage = documentHistoryPageFromResponse(
      {'items': <dynamic>[], 'total': 0, 'limit': 10, 'offset': 0},
      limit: 10,
      offset: 0,
    );
    expect(emptyPage.items, isEmpty);
    expect(emptyPage.total, 0);

    expect(
      () => documentHistoryPageFromResponse(
        {'unexpected': true},
        limit: 10,
        offset: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => documentHistoryPageFromResponse(
        <dynamic>['not-an-event'],
        limit: 10,
        offset: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => documentHistoryPageFromResponse(null, limit: 10, offset: 0),
      throwsFormatException,
    );
    expect(
      () => documentHistoryPageFromResponse(
        {'error': 'Failed to fetch history'},
        limit: 10,
        offset: 0,
      ),
      throwsA(
        predicate(
          (error) =>
              error is FormatException &&
              error.message == 'Failed to fetch history',
        ),
      ),
    );
  });

  test('repository loads a JSON array history response', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    final saved = List<Interceptor>.of(ApiClient.instance.dio.interceptors);
    final requests = <RequestOptions>[];
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final action = options.queryParameters['action'];
          if (action == 'timeout') {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
                message:
                    'The request connection took longer than 0:00:20.000000 and it was aborted.',
              ),
            );
            return;
          }
          if (action == 'http-error') {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 500,
                  data: {'error': 'Failed to fetch history'},
                ),
              ),
            );
            return;
          }
          final payload = action == 'created'
              ? {
                  'items': _liveHistoryJson()
                      .where((event) => event['action'] == 'created')
                      .toList(),
                  'total': 1,
                  'limit': options.queryParameters['limit'],
                  'offset': options.queryParameters['offset'],
                }
              : action == 'malformed'
              ? {'unexpected': true}
              : action == 'server-error'
              ? {'error': 'Failed to fetch history'}
              : _liveHistoryJson();
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: payload,
            ),
          );
        },
      ),
    );
    addTearDown(() {
      ApiClient.instance.dio.interceptors
        ..clear()
        ..addAll(saved);
    });

    final page = await DocuTrackerRepository.instance.listDocumentHistoryPage(
      'doc-10',
      limit: 10,
      offset: 0,
    );
    expect(page.total, 10);
    expect(page.items.first.action, 'remark');
    expect(page.items.last.action, 'created');
    expect(requests.single.queryParameters['limit'], 10);
    expect(requests.single.queryParameters['offset'], 0);

    final filtered = await DocuTrackerRepository.instance
        .listDocumentHistoryPage(
          'doc-10',
          limit: 10,
          offset: 0,
          action: 'created',
        );
    expect(filtered.total, 1);
    expect(filtered.items.single.action, 'created');

    await expectLater(
      DocuTrackerRepository.instance.listDocumentHistoryPage(
        'doc-10',
        limit: 10,
        offset: 0,
        action: 'malformed',
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString() == 'Activity history could not be loaded.',
        ),
      ),
    );
    await expectLater(
      DocuTrackerRepository.instance.listDocumentHistoryPage(
        'doc-10',
        limit: 10,
        offset: 0,
        action: 'server-error',
      ),
      throwsA(
        predicate((error) => error.toString() == 'Failed to fetch history'),
      ),
    );
    await expectLater(
      DocuTrackerRepository.instance.listDocumentHistoryPage(
        'doc-10',
        limit: 10,
        offset: 0,
        action: 'timeout',
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString() == 'Activity history could not be loaded.',
        ),
      ),
    );
    await expectLater(
      DocuTrackerRepository.instance.listDocumentHistoryPage(
        'doc-10',
        limit: 10,
        offset: 0,
        action: 'http-error',
      ),
      throwsA(
        predicate((error) => error.toString() == 'Failed to fetch history'),
      ),
    );
  });

  testWidgets('history panel loads the live payload, filters, and expands', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerActivityHistoryPanel(
            loadPage: ({required limit, required offset, String? action}) {
              return Future.value(
                documentHistoryPageFromResponse(
                  _liveHistoryJson(),
                  limit: limit,
                  offset: offset,
                  action: action,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1–10 of 10'), findsOneWidget);
    expect(find.text('Internal note added'), findsOneWidget);
    expect(find.text('Document created'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);

    await tester.tap(find.byKey(const Key('docutracker-activity-row-h2')));
    await tester.pumpAndSettle();
    expect(find.text('Status: In Review → Overdue'), findsWidgets);
    expect(find.text('Review the recorded dates.'), findsOneWidget);
    expect(find.text('Recorded action: overdue'), findsWidgets);

    await tester.tap(find.byKey(const Key('docutracker-activity-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document created').last);
    await tester.pumpAndSettle();
    expect(find.text('1–1 of 1'), findsOneWidget);
    expect(find.text('Internal note added'), findsNothing);
  });

  testWidgets('retry loads history after a failed request', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerActivityHistoryPanel(
            loadPage:
                ({required limit, required offset, String? action}) async {
                  attempts += 1;
                  if (attempts == 1) {
                    throw DioException(
                      requestOptions: RequestOptions(path: '/history'),
                      type: DioExceptionType.unknown,
                      message: null,
                      error: TypeError(),
                    );
                  }
                  return documentHistoryPageFromResponse(
                    _liveHistoryJson(),
                    limit: limit,
                    offset: offset,
                    action: action,
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activity history could not be loaded.'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Internal note added'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('1–10 of 10'), findsOneWidget);
    expect(find.text('Activity history could not be loaded.'), findsNothing);
  });
}

/// Shape returned by GET /documents/:id/history on the running API:
/// a JSON array, newest first, including when `limit` is present.
List<Map<String, dynamic>> _liveHistoryJson() {
  const events = <(String, String, String?, String?, String)>[
    ('h1', 'remark', 'overdue', 'overdue', '2026-10-22T00:19:13.631Z'),
    ('h2', 'overdue', 'in_review', 'overdue', '2026-09-22T16:00:19.027Z'),
    ('h3', 'approved', 'overdue', 'in_review', '2026-09-21T08:13:40.891Z'),
    ('h4', 'overdue', 'in_review', 'overdue', '2026-09-08T13:30:52.594Z'),
    ('h5', 'submitted', 'pending', 'in_review', '2026-09-03T03:14:19.040Z'),
    ('h6', 'metadata_updated', null, null, '2026-09-03T03:14:04.958Z'),
    ('h7', 'metadata_updated', null, null, '2026-09-03T03:13:56.387Z'),
    ('h8', 'metadata_updated', null, null, '2026-09-03T03:13:52.471Z'),
    ('h9', 'signed', null, null, '2026-09-03T03:13:44.784Z'),
    ('h10', 'created', null, 'pending', '2026-09-03T03:11:24.380Z'),
  ];
  return [
    for (final event in events)
      {
        'id': event.$1,
        'document_id': 'doc-10',
        'action': event.$2,
        'actor_id': null,
        'actor_name': null,
        'from_step': null,
        'to_step': null,
        'from_status': event.$3,
        'to_status': event.$4,
        'remarks': event.$2 == 'overdue' ? 'Review the recorded dates.' : null,
        'created_at': event.$5,
        'metadata': <String, dynamic>{},
      },
  ];
}
