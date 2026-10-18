'use strict';
module.exports = function createLocatorComponent({ normalizeLocatorFieldSchema }) {
  function mapLocatorTypeRow(row) {
    return {
      filing_access: row.filing_access || 'employee',
      auto_approve_admin: row.auto_approve_admin === true,
      approval_workflow_id: row.approval_workflow_id || null,
      approval_route: row.approval_route || 'hr',
      mayor_employment_types: row.mayor_employment_types || null,
      id: row.id,
      code: row.code,
      employee_detail_schema: normalizeLocatorFieldSchema(row.employee_detail_schema),
      label: row.label,
      short_label: row.short_label,
      location_label: row.location_label,
      location_hint: row.location_hint,
      dtr_slot_label: row.dtr_slot_label,
      dtr_print_label: row.dtr_print_label,
      requires_attachment: row.requires_attachment === true,
      coverage_mode: row.coverage_mode || 'manual',
      is_active: row.is_active !== false,
      sort_order: Number(row.sort_order || 0),
      is_system: row.is_system === true,
      created_at: row.created_at || null,
      updated_at: row.updated_at || null,
    };
  }
  return { mapLocatorTypeRow };
};
