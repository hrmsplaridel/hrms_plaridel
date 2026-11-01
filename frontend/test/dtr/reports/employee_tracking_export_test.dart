import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_display.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('untracked history is not shown as an absence or deducted in exports',(){
  final date=DateTime(2026,10,30);
  final row=TimeRecord(userId:'employee',recordDate:date,status:'not_tracked');
  expect(getAttendanceRemark(row),'Not tracked');expect(isCompletedAttendanceRecord(row),false);
  final totals=DtrExport.calculateOfficialTotals(year:2026,month:10,start:date,end:date,recordsByDate:{date:row},reportableThrough:date);
  expect(totals.totalUndertimeMinutes,0);
  final html=DtrExport.generateWordHtmlSync(employeeName:'Employee',year:2026,month:10,start:date,end:date,recordsByDate:{date:row},reportableThrough:date);
  expect(html,contains('NOT TRACKED'));expect(html,isNot(contains('ABSENT')));
 });
 test('partial locator metadata does not count an untracked day as present',(){
  final row=TimeRecord(userId:'employee',recordDate:DateTime(2026,10,30),status:'not_tracked',locatorSlipId:'partial-locator',undertimeMinutes:0);
  expect(isCompletedAttendanceRecord(row),false);
 });
}
