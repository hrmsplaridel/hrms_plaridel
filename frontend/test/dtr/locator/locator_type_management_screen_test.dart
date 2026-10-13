import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/locator_type_management_screen.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/shared/widgets/form_settings_section.dart';

void main() {
  final requests = <RequestOptions>[];
  var rejectBackground = false;
  var created = <Map<String, dynamic>>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    FilePicker.platform = _LocatorBackgroundPicker();
  });

  setUp(() {
    requests.clear();
    rejectBackground = false;
    created = [];
    LocatorSlipDataCache.instance.invalidateTypes();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.method == 'GET' &&
              options.path ==
                  '/api/locator-slips/types?include_inactive=true') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: created,
              ),
            );
            return;
          }
          if (options.method == 'POST' &&
              options.path == '/api/locator-slips/types') {
            final data = Map<String, dynamic>.from(options.data as Map);
            created = [
              {
                ...data,
                'id': '11111111-1111-4111-8111-111111111111',
                'is_system': false,
              },
            ];
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 201,
                data: {
                  ...data,
                  'id': '11111111-1111-4111-8111-111111111111',
                  'is_system': false,
                },
              ),
            );
            return;
          }
          if (options.path.startsWith('/api/locator-slips/print/types/')) {
            if (options.method == 'POST' && rejectBackground) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: {'error': 'Invalid background'},
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': 'version',
                    'background_name': null,
                    'has_background': false,
                  },
                ),
              );
            }
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 404,
              ),
            ),
          );
        },
      ),
    );
  });

  tearDown(() {
    LocatorSlipDataCache.instance.invalidateTypes();
    ApiClient.instance.dio.interceptors.clear();
  });

  Finder textField(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

  Finder coverageDropdown() => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Time coverage behavior',
  );

  Future<_FakeRealtimeProvider> mount(
    WidgetTester tester, {
    _FakeRealtimeProvider? realtime,
  }) async {
    final provider = realtime ?? _FakeRealtimeProvider();
    addTearDown(provider.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRealtimeProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: LocatorTypeManagementScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> enterRequiredFields(WidgetTester tester) async {
    await tester.enterText(textField('System code'), 'remote_work');
    await tester.enterText(textField('Request type name'), 'Remote Work');
    await tester.enterText(textField('Short display name'), 'Remote');
    await tester.enterText(textField('DTR display text'), 'Remote');
    await tester.enterText(textField('DTR print text'), 'REMOTE');
  }
  testWidgets('new type saves its designed layout without needing a background upload', (tester)async{
    await mount(tester);await enterRequiredFields(tester);
    final scrollable=find.descendant(of:find.byType(ListView).last,matching:find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Design layout'),250,scrollable:scrollable);
    await tester.tap(find.text('Design layout'));await tester.pumpAndSettle();
    expect(find.text('Printed form layout'),findsOneWidget);
    await tester.tap(find.text('Use layout'));await tester.pumpAndSettle();
    await tester.tap(find.text('Create Type'));await tester.pumpAndSettle();
    final saved=requests.singleWhere((r)=>r.method=='POST' && r.path.startsWith('/api/locator-slips/print/types/'));
    final data=saved.data as FormData;
    expect(data.files,isEmpty);
    final layout=jsonDecode(data.fields.singleWhere((e)=>e.key=='print_layout').value) as Map;
    expect(layout['orientation'],'portrait');
    expect((layout['elements'] as List).first['text'],'REMOTE WORK');
  });
  testWidgets('Save Changes also saves the edited print layout on an existing type', (tester)async{
    await mount(tester);await enterRequiredFields(tester);
    await tester.tap(find.text('Create Type'));await tester.pumpAndSettle();
    ApiClient.instance.dio.interceptors.insert(0,InterceptorsWrapper(onRequest:(o,h){
      if(o.method=='PUT' && o.path.startsWith('/api/locator-slips/types/')){
        requests.add(o);h.resolve(Response(requestOptions:o,statusCode:200,data:o.data));
      }else{h.next(o);}
    }));
    final scrollable=find.descendant(of:find.byType(ListView).last,matching:find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Design layout'),250,scrollable:scrollable);
    await tester.drag(find.byType(ListView).last,const Offset(0,-300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design layout'));await tester.pumpAndSettle();
    await tester.tap(find.text('Use layout'));await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));await tester.pumpAndSettle();
    final print=requests.singleWhere((r)=>r.method=='POST' && r.path.startsWith('/api/locator-slips/print/types/'));
    expect((print.data as FormData).fields.any((f)=>f.key=='print_layout'),true);
    expect(find.text('Locator type updated.'),findsOneWidget);
  });

  testWidgets('custom locator fields are included when creating a type', (tester) async {
    await mount(tester);
    await enterRequiredFields(tester);
    final scrollable=find.descendant(of:find.byType(ListView).last,matching:find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Add field'),250,scrollable:scrollable);
    final section = find.ancestor(
      of:find.text('Form and DTR Wording'),
      matching:find.byType(FormSettingsSection),
    ).first;
    expect(find.descendant(of:section,matching:find.text('Add field')),findsOneWidget);
    expect(find.ancestor(of:find.text('Add field'),matching:find.byType(FormSettingsSection)),findsOneWidget);
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(textField('Field label'));
    await tester.enterText(textField('Field label'),'Contact person');
    await tester.tap(find.text('Create Type'));
    await tester.pumpAndSettle();
    final request=requests.singleWhere((r)=>r.method=='POST' && r.path=='/api/locator-slips/types');
    final schema=(request.data as Map)['employee_detail_schema'] as List;
    expect(schema.single['label'],'Contact person');
    expect(schema.single['type'],'text');
    expect(schema.single['required'],false);
  });

  testWidgets(
    'empty API result stays empty instead of showing local defaults',
    (tester) async {
      await mount(tester);
      await tester.scrollUntilVisible(
        find.text('Approval routing'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Approval routing'), findsOneWidget);

      expect(find.text('0 locator types'), findsOneWidget);
      expect(find.text('No locator types configured'), findsOneWidget);
      expect(find.text('Locator / Official Business'), findsNothing);
      expect(find.text('Pass Slip'), findsNothing);
      expect(find.text('Create Type'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Printed Form'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Upload background'), findsOneWidget);
      Container sectionBox(String title) => tester.widget<Container>(
        find
            .ancestor(
              of: find.text(title),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.padding == const EdgeInsets.all(16) &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(10),
              ),
            )
            .first,
      );
      final filingBox = sectionBox('Filing Requirements');
      final printBox = sectionBox('Printed Form');
      expect(printBox.decoration, filingBox.decoration);
      expect(printBox.padding, filingBox.padding);
    },
  );

  testWidgets('catalog load failure stays visible and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            attempts += 1;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 503,
                    data: const {'error': 'Catalog unavailable'},
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const [],
              ),
            );
          },
        ),
      );

    await mount(tester);

    expect(find.text('Could not load locator types'), findsOneWidget);
    expect(find.text('Catalog unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Could not load locator types'), findsNothing);
    expect(find.text('No locator types configured'), findsOneWidget);
  });

  testWidgets('invalid sort order blocks creation before the API call', (
    tester,
  ) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('Sort order'), '1.5');

    await tester.tap(find.text('Create Type'));
    await tester.pump();

    expect(
      find.text('Sort order must be a whole number from 0 to 2147483647'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'new locator background saves with creation; upload failure=$fails',
      (tester) async {
        final original = FilePicker.platform;
        FilePicker.platform = _LocatorBackgroundPicker();
        addTearDown(() => FilePicker.platform = original);
        rejectBackground = fails;
        await mount(tester);
        await enterRequiredFields(tester);
        await tester.scrollUntilVisible(
          find.text('Upload background'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Upload background')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload background'));
        await tester.pumpAndSettle();
        expect(find.text('locator-letterhead.pdf'), findsOneWidget);
        await tester.tap(find.text('Create Type'));
        await tester.pumpAndSettle();
        final uploads = requests.where(
          (r) => r.method == 'POST' && r.path.contains('/print/types/'),
        );
        expect(uploads, hasLength(1));
        expect(
          (uploads.single.data as FormData).files.single.value.filename,
          'locator-letterhead.pdf',
        );
        if (fails) {
          expect(
            find.textContaining('Locator type created, but its background'),
            findsOneWidget,
          );
          rejectBackground = false;
          await tester.scrollUntilVisible(
            find.text('Save print settings'),
            250,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text('locator-letterhead.pdf'), findsOneWidget);
          await Scrollable.ensureVisible(
            tester.element(find.text('Save print settings')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save print settings'));
          await tester.pumpAndSettle();
          expect(
            requests.where(
              (r) => r.method == 'POST' && r.path.contains('/print/types/'),
            ),
            hasLength(2),
          );
        }
        expect(
          requests.where(
            (r) => r.method == 'POST' && r.path == '/api/locator-slips/types',
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('valid rules are sent without normalization', (tester) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('Sort order'), '30');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == 'Who can file',
          ),
        )
        .onChanged!('admin');
    await tester.pump();
    tester.widget<Switch>(find.byType(Switch).first).onChanged!(true);
    tester
        .widget<DropdownButtonFormField<String>>(coverageDropdown())
        .onChanged!('wfh');
    await tester.pump();

    await tester.tap(find.text('Create Type'));
    await tester.pumpAndSettle();

    final post = requests.singleWhere((request) => request.method == 'POST');
    final data = Map<String, dynamic>.from(post.data as Map);
    expect(data['sort_order'], 30);
    expect(data['coverage_mode'], 'wfh');
    expect(data['filing_access'], 'admin');
    expect(data['auto_approve_admin'], isTrue);
    expect(find.text('Locator type added.'), findsOneWidget);
  });
  testWidgets('direct Mayor routing saves with HR auto approval disabled', (
    tester,
  ) async {
    await mount(tester);
    await enterRequiredFields(tester);
    final route = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Approval route',
    );
    await tester.scrollUntilVisible(
      route,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct Mayor approval').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Type'));
    await tester.pumpAndSettle();
    final data =
        requests
                .firstWhere(
                  (r) =>
                      r.path == '/api/locator-slips/types' &&
                      r.method == 'POST',
                )
                .data
            as Map;
    expect(data['approval_route'], 'mayor_direct');
    expect(data['mayor_employment_types'], [
      'job_order',
      'contract_of_service',
    ]);
    expect(data['auto_approve_admin'], false);
  });

  testWidgets('invalid code and oversized text block creation', (tester) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('System code'), 'a');
    await tester.enterText(
      textField('Request type name'),
      List<String>.filled(101, 'x').join(),
    );

    await tester.tap(find.text('Create Type'));
    await tester.pump();

    expect(
      find.text('Use 2-64 letters, numbers, underscores, or hyphens'),
      findsOneWidget,
    );
    expect(
      find.text('Request type name must be 100 characters or less'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });

  testWidgets('remote locator type event refreshes the visible catalog', (
    tester,
  ) async {
    final realtime = await mount(tester);
    final before = requests
        .where(
          (request) =>
              request.method == 'GET' &&
              request.path == '/api/locator-slips/types?include_inactive=true',
        )
        .length;

    realtime.emit(
      const AppRealtimeEvent(
        name: 'locator_type_updated',
        payload: {'action': 'updated', 'code': 'remote_work'},
      ),
    );
    await tester.pumpAndSettle();

    final after = requests
        .where(
          (request) =>
              request.method == 'GET' &&
              request.path == '/api/locator-slips/types?include_inactive=true',
        )
        .length;
    expect(after, greaterThan(before));
  });
}

class _FakeRealtimeProvider extends AppRealtimeProvider {
  final _events = StreamController<AppRealtimeEvent>.broadcast();

  @override
  Stream<AppRealtimeEvent> get events => _events.stream;

  void emit(AppRealtimeEvent event) => _events.add(event);

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}

class _LocatorBackgroundPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'locator-letterhead.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}
