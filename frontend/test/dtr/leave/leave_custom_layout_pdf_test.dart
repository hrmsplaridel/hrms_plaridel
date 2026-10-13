import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/configured_leave_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ApiClient.instance.init());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  final request = LeaveRequest(
    id: 'req',
    userId: 'emp',
    employeeName: 'Maria Employee',
    positionTitle: 'Accountant',
    leaveType: LeaveType.others,
    leaveTypeDisplayName: 'Special Leave',
    workingDaysApplied: 2,
    startDate: DateTime(2026, 10, 13),
    endDate: DateTime(2026, 10, 14),
    customDetails: const {'count': 0, 'urgent': false},
    employeeDetailSchemaSnapshot: const [
      LeaveCustomFieldDefinition(
        key: 'count',
        label: 'Count',
        type: LeaveCustomFieldType.number,
      ),
      LeaveCustomFieldDefinition(
        key: 'urgent',
        label: 'Urgent',
        type: LeaveCustomFieldType.boolean,
      ),
    ],
  );
  test(
    'leave values preserve custom zero/false and display dates, days and employee position',
    () {
      final form = leaveLayoutForm(request);
      expect(form['position'], 'Accountant');
      expect(form['working_days'], 2);
      expect(form['inclusive_dates'], '2026-10-13 - 2026-10-14');
      expect(form['additional_details'], {'count': 0, 'urgent': false});
    },
  );
  test(
    'custom request uses pinned geometry even without background and preserves manual Mayor signing',
    () async {
      final layout = leavePrintLayoutDefaults(
        const LeaveTypeDefinition(
          name: 'specialLeave',
          displayName: 'Special Leave',
        ),
      );
      FormData? sent;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'GET') {
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'id': 'v-custom',
                    'layout': 'custom',
                    'print_layout': layout.toJson(),
                    'has_background': false,
                    'mayor_name': 'Mayor Example',
                  },
                ),
              );
            } else {
              sent = o.data as FormData;
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: Uint8List.fromList([37, 80, 68, 70]),
                ),
              );
            }
          },
        ),
      );
      final doc = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Wrong CSC template')));
      final bytes = await saveConfiguredLeavePdf(
        request: request.copyWith(finalReviewRoute: 'mayor'),
        document: doc,
        finalSignature: Uint8List.fromList([1, 2, 3]),
      );
      expect(bytes, orderedEquals([37, 80, 68, 70]));
      expect(
        sent!.fields.singleWhere((f) => f.key == 'version_id').value,
        'v-custom',
      );
      expect(sent!.files.single.value.length, greaterThan(1000));
    },
  );
  test('custom layout missing from configuration fails visibly', () async {
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.resolve(
          Response(
            requestOptions: o,
            statusCode: 200,
            data: {'layout': 'custom', 'has_background': false},
          ),
        ),
      ),
    );
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('CSC')));
    await expectLater(
      saveConfiguredLeavePdf(request: request, document: doc),
      throwsA(isA<FormatException>()),
    );
  });
  test(
    'custom leave draft transports geometry and background removal',
    () async {
      FormData? sent;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            sent = o.data as FormData;
            h.resolve(Response(requestOptions: o, statusCode: 200, data: {}));
          },
        ),
      );
      final layout = leavePrintLayoutDefaults(
        const LeaveTypeDefinition(
          name: 'specialLeave',
          displayName: 'Special Leave',
        ),
      );
      await LeavePrintDraft(
        layout: 'custom',
        printLayout: layout,
        removeBackground: true,
      ).save('type');
      expect(
        sent!.fields.singleWhere((f) => f.key == 'remove_background').value,
        'true',
      );
      expect(
        jsonDecode(
          sent!.fields.singleWhere((f) => f.key == 'print_layout').value,
        )['orientation'],
        'portrait',
      );
      expect(sent!.files, isEmpty);
    },
  );
  test(
    'default leave layouts fit all supported custom fields in both orientations',
    () {
      final type = LeaveTypeDefinition(
        name: 'customLeave',
        displayName: 'Custom Leave',
        employeeDetailSchema: List.generate(
          20,
          (i) => LeaveCustomFieldDefinition(key: 'field_$i', label: 'Field $i'),
        ),
      );
      for (final orientation in ['portrait', 'landscape']) {
        final layout = leavePrintLayoutDefaults(type, orientation: orientation);
        expect(layout.validate(), isNull);
        expect(
          layout.elements.where((e) => e.source.startsWith('custom:')).length,
          20,
        );
      }
    },
  );
  test(
    'custom form embeds the separately verified certification signature',
    () async {
      final layout = leavePrintLayoutDefaults(
        const LeaveTypeDefinition(
          name: 'specialLeave',
          displayName: 'Special Leave',
        ),
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC',
      );
      Future<Uint8List> render(Uint8List? signature) async {
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) async {
              if (o.method == 'GET') {
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: 200,
                    data: {
                      'id': 'v',
                      'layout': 'custom',
                      'print_layout': layout.toJson(),
                      'has_background': false,
                    },
                  ),
                );
              } else {
                final chunks = <int>[];
                await for (final chunk
                    in (o.data as FormData).files.single.value.finalize()) {
                  chunks.addAll(chunk);
                }
                h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: chunks),
                );
              }
            },
          ),
        );
        return saveConfiguredLeavePdf(
          request: request,
          document: pw.Document(),
          certificationOfficerName: 'Verified HR',
          certificationOfficerTitle: 'HR Officer',
          certificationSignature: signature,
        );
      }

      final unsigned = await render(null), signed = await render(png);
      final images = RegExp(r'/Subtype\s*/Image');
      expect(
        images.allMatches(latin1.decode(signed)).length,
        greaterThan(images.allMatches(latin1.decode(unsigned)).length),
      );
    },
  );
  test(
    'custom leave PDF keeps long and unplaced answers on a continuation',
    () async {
      final layout = leavePrintLayoutDefaults(
        const LeaveTypeDefinition(
          name: 'specialLeave',
          displayName: 'Special Leave',
        ),
      );
      final short = await buildLeaveLayoutPdf(
        layout: layout,
        request: request.copyWith(
          employeeDetailSchemaSnapshot: const [],
          customDetails: const {},
        ),
      );
      final long = await buildLeaveLayoutPdf(
        layout: layout,
        request: request.copyWith(
          reason: List.filled(500, 'Long reason').join(' '),
        ),
      );
      final pages = RegExp(r'/Type\s*/Page\b');
      expect(pages.allMatches(latin1.decode(short)).length, 1);
      expect(pages.allMatches(latin1.decode(long)).length, greaterThan(1));
    },
  );
}
