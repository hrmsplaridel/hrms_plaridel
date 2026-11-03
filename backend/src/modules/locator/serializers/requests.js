'use strict';
module.exports = function createLocatorComponent({
  normalizeLocatorFieldSchema,
  normalizeRequestType,
  resolveLocatorTypeMetadata,
}) {
  function locatorConflictPayload(result) {
    return {
      error: result.message || 'Locator request conflicts with an existing record.',
      code: result.code || 'locator_conflict',
      conflicts: result.conflicts || {},
    };
  }

  function toDateOnlyString(value) {
    if (!value) return null;
    if (typeof value === 'string') {
      const raw = value.trim();
      if (!raw) return null;
      const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
      return match ? match[1] : null;
    }
    if (value instanceof Date && !Number.isNaN(value.getTime())) {
      const y = value.getFullYear().toString().padStart(4, '0');
      const m = String(value.getMonth() + 1).padStart(2, '0');
      const d = String(value.getDate()).padStart(2, '0');
      return `${y}-${m}-${d}`;
    }
    return null;
  }

  function mapLocatorRow(row) {
    const requestType = normalizeRequestType(row.request_type) || 'locator';
    const typeMetadata = resolveLocatorTypeMetadata(row);
    return {
      id: row.id,
      employee_id: row.employee_id,
      employee_name: row.employee_name || null,
      department_id: row.department_id || null,
      department_name: row.department_name || null,
      assigned_department_head_id: row.assigned_department_head_id || null,
      assigned_department_head_name: row.assigned_department_head_name || null,
      slip_date: toDateOnlyString(row.slip_date_text || row.slip_date),
      am_in: row.am_in === true,
      am_out: row.am_out === true,
      pm_in: row.pm_in === true,
      pm_out: row.pm_out === true,
      request_type: requestType,
      request_type_label: typeMetadata.label,
      request_type_short_label: typeMetadata.shortLabel,
      request_type_location_label: typeMetadata.locationLabel,
      request_type_location_hint: typeMetadata.locationHint,
      request_type_dtr_slot_label: typeMetadata.dtrSlotLabel,
      request_type_dtr_print_label: typeMetadata.dtrPrintLabel,
      request_type_requires_attachment: typeMetadata.requiresAttachment,
      request_type_coverage_mode: typeMetadata.coverageMode,
      request_type_snapshot_at: typeMetadata.capturedAt,
      office: row.office || '',
      employee_detail_schema_snapshot: normalizeLocatorFieldSchema(
        row.employee_detail_schema_snapshot
      ),
      additional_details: row.additional_details || {},
      reason: row.reason || '',
      attachment_name: row.attachment_name || null,
      attachment_path: row.attachment_path || null,
      attachment_mime_type: row.attachment_mime_type || null,
      attachment_uploaded_at: row.attachment_uploaded_at || null,
      status: row.status,
      final_review_route: row.final_review_route || 'hr',
      workflow_snapshot: row.workflow_snapshot || null,
      paper_approval_record: require('../../leave/services/paperSignatures').publicPaperRecord(row.paper_approval_record),
      dept_head_reviewer_id: row.dept_head_reviewer_id || null,
      dept_head_reviewer_name: row.dept_head_reviewer_name || null,
      dept_head_reviewed_at: row.dept_head_reviewed_at || null,
      dept_head_remarks: row.dept_head_remarks || null,
      hr_reviewer_id: row.hr_reviewer_id || null,
      hr_reviewer_name: row.hr_reviewer_name || null,
      hr_reviewed_at: row.hr_reviewed_at || null,
      hr_remarks: row.hr_remarks || null,
      is_retroactive_correction: row.is_retroactive_correction === true,
      retroactive_correction_reason: row.retroactive_correction_reason || null,
      retroactive_corrected_by: row.retroactive_corrected_by || null,
      retroactive_corrector_name: row.retroactive_corrector_name || null,
      retroactive_corrected_at: row.retroactive_corrected_at || null,
      revoked_by: row.revoked_by || null,
      revoked_by_name: row.revoked_by_name || null,
      revoked_at: row.revoked_at || null,
      revocation_reason: row.revocation_reason || null,
      month_end_reconciliation_required: row.month_end_reconciliation_required === true,
      month_end_reconciled_at: row.month_end_reconciled_at || null,
      created_at: row.created_at || null,
      updated_at: row.updated_at || null,
    };
  }
  return { toDateOnlyString, mapLocatorRow, locatorConflictPayload };
};
