'use strict';
module.exports = function createLeaveComponent({
  SYSTEM_LEAVE_TYPE_NAMES,
  leaveTypeRuleDefaults,
  normalizeEmployeeDetailSchema,
  normalizeEntitlementBasis,
  normalizeLedgerType,
  normalizeSexEligibility,
  systemLeaveTypeDisplayName,
}) {
  function leaveTypeRowToApi(row = {}) {
    const name = (row.name || '').toString();
    const fallback = leaveTypeRuleDefaults(name);
    const displayName = row.display_name || row.description || systemLeaveTypeDisplayName(name);
    return {
      id: row.id,
      name,
      display_name: displayName,
      description: row.description || null,
      is_active: row.is_active !== false,
      is_system: row.is_system === true || SYSTEM_LEAVE_TYPE_NAMES.includes(name),
      employee_can_file:
        row.employee_can_file != null
          ? row.employee_can_file === true
          : fallback.employee_can_file !== false,
      admin_only: row.admin_only != null ? row.admin_only === true : fallback.admin_only === true,
      admin_can_file: row.admin_can_file !== false,
      allow_approved_paper_filing: row.allow_approved_paper_filing === true,
      allows_past_dates:
        row.allows_past_dates != null
          ? row.allows_past_dates === true
          : fallback.allows_past_dates !== false,
      requires_attachment:
        row.requires_attachment != null
          ? row.requires_attachment === true
          : fallback.requires_attachment === true,
      requires_attachment_when_over_days:
        row.requires_attachment_when_over_days != null
          ? parseFloat(row.requires_attachment_when_over_days)
          : (fallback.requires_attachment_when_over_days ?? null),
      max_days: row.max_days != null ? parseFloat(row.max_days) : (fallback.max_days ?? null),
      minimum_advance_days:
        row.minimum_advance_days != null
          ? parseInt(row.minimum_advance_days, 10)
          : (fallback.minimum_advance_days ?? null),
      affects_dtr_normally:
        row.affects_dtr_normally != null
          ? row.affects_dtr_normally === true
          : fallback.affects_dtr_normally !== false,
      balance_ledger_type: normalizeLedgerType(row.balance_ledger_type, name),
      entitlement_basis: normalizeEntitlementBasis(row.entitlement_basis, name),
      sex_eligibility: normalizeSexEligibility(
        row.sex_eligibility ?? fallback.sex_eligibility,
        name,
      ),
      eligible_employment_types: row.eligible_employment_types ?? null,
      minimum_service_months: Number(row.minimum_service_months || 0),
      first_year_allowance: row.first_year_allowance || 'full',
      approval_workflow_id: row.approval_workflow_id || null,
      approval_route: row.approval_route || 'hr',
      mayor_employment_types: row.mayor_employment_types ?? null,
      employee_detail_schema: normalizeEmployeeDetailSchema(row.employee_detail_schema),
      created_at: row.created_at || null,
      updated_at: row.updated_at || null,
    };
  }
  return { leaveTypeRowToApi };
};
