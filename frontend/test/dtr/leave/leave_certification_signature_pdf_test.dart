import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '7.A embeds the certification signature without an approval signature',
    () async {
      final signature = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC',
      );
      Future<Uint8List> render({Uint8List? image}) async {
        final document = await LeaveRequestPdf.buildPdf(
          request: LeaveRequest(
            userId: 'employee',
            employeeName: 'Test Employee',
            leaveType: LeaveType.vacationLeave,
            startDate: DateTime(2026, 10, 20),
            endDate: DateTime(2026, 10, 20),
          ),
          balances: const [],
          certificationOfficerName: 'Primary HR',
          certificationOfficerTitle: 'HR Officer',
          certificationOfficerSignatureBytes: image,
        );
        return document.save();
      }

      final unsigned = latin1.decode(await render());
      final signed = latin1.decode(await render(image: signature));
      final images = RegExp(r'/Subtype\s*/Image');
      expect(
        images.allMatches(signed).length,
        greaterThan(images.allMatches(unsigned).length),
      );
    },
  );
}
