import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_annual_entitlement_preview.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_entitlement_basis.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';

void main() {
  test('event leave definition is not treated as an annual balance', () {
    final maternity = LeaveTypeDefinition.fromJson({
      'name': 'maternityLeave',
      'display_name': 'Maternity Leave',
      'max_days': 105,
      'balance_ledger_type': 'none',
      'entitlement_basis': 'per_event',
    });

    expect(maternity.entitlementBasis, LeaveEntitlementBasis.perEvent);
    expect(maternity.balanceLedgerType, 'none');
  });

  test('annual entitlement summary is distinct from a credit balance', () {
    final entitlement = LeaveBalance.fromJson({
      'id': 'synth-soloParentLeave-2026',
      'user_id': 'employee-1',
      'leave_type': 'soloParentLeave',
      'record_kind': 'annual_entitlement',
      'entitlement_basis': 'annual',
      'entitlement_year': 2026,
      'earned_days': 7,
      'used_days': 2,
      'pending_days': 1,
    });

    expect(entitlement.isAnnualEntitlement, isTrue);
    expect(entitlement.isCreditBalance, isFalse);
    expect(entitlement.entitlementYear, 2026);
    expect(entitlement.availableDays, 4);
  });

  test('VL remains an accrued credit balance', () {
    final vacation = LeaveBalance.fromJson({
      'id': 'balance-vl',
      'user_id': 'employee-1',
      'leave_type': 'vacationLeave',
      'record_kind': 'credit_balance',
      'entitlement_basis': 'accrual',
      'earned_days': 10,
    });

    expect(vacation.isCreditBalance, isTrue);
    expect(vacation.isAnnualEntitlement, isFalse);
    expect(vacation.entitlementBasis, LeaveEntitlementBasis.accrual);
  });

  test('annual preview preserves shift-aware cross-year server counts', () {
    final preview = LeaveAnnualEntitlementPreview.fromJson({
      'leave_type': 'soloParentLeave',
      'display_name': 'Solo Parent Leave',
      'limit_days': 7,
      'allowed': false,
      'years': [
        {
          'year': 2026,
          'limit_days': 7,
          'approved_days': 4,
          'pending_days': 1,
          'requested_days': 2,
          'requested_counted_dates': ['2026-12-30', '2026-12-31'],
          'remaining_before_request': 2,
          'remaining_after_request': 0,
          'allowed': true,
        },
        {
          'year': 2027,
          'limit_days': 7,
          'approved_days': 6,
          'pending_days': 0,
          'requested_days': 2,
          'requested_counted_dates': ['2027-01-02', '2027-01-03'],
          'remaining_before_request': 1,
          'remaining_after_request': 0,
          'allowed': false,
          'error_message': 'Only 1 day remains for 2027.',
        },
      ],
    });

    expect(preview.years.first.requestedDays, 2);
    expect(preview.years.first.requestedCountedDates, hasLength(2));
    expect(preview.firstRejectedYear?.year, 2027);
    expect(preview.firstRejectedYear?.errorMessage, contains('1 day'));
  });
}
