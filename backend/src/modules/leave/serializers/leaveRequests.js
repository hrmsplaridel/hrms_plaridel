'use strict';
const {publicPaperRecord}=require('../services/paperSignatures');
module.exports = function createLeaveComponent({
  customLeaveDetailValues,
  normalizeEmployeeDetailSchema,
  normalizeEmployeeOfficialSnapshot,
  sanitizeEmployeeLeaveDetails,
  systemLeaveTypeDisplayName,
  toIsoDateStr,
}) {
  function mapLeaveRowToApi(row) {
    // Employee details are whitelisted again on output so legacy untrusted keys
    // cannot appear as official or review fields before the cleanup migration runs.
    const customFieldSchema = normalizeEmployeeDetailSchema(row.employee_detail_schema_snapshot);
    const details = sanitizeEmployeeLeaveDetails(row.details, customFieldSchema);
    const official = normalizeEmployeeOfficialSnapshot(row.employee_official_snapshot);
    const employeeName =
      official.employee_name ||
      row.employee_name ||
      row.full_name ||
      row.employee_full_name ||
      null;
    return {
      ...details,
      details,
      custom_details: customLeaveDetailValues(details, customFieldSchema),
      employee_detail_schema_snapshot: customFieldSchema,
      id: row.id,
      user_id: row.user_id || row.employee_id,
      employee_name: employeeName,
      start_date: toIsoDateStr(row.start_date),
      end_date: toIsoDateStr(row.end_date),
      working_days_applied:
        row.number_of_days != null
          ? parseFloat(row.number_of_days)
          : row.total_days != null
            ? parseFloat(row.total_days)
            : null,
      reason: row.reason || null,
      status: row.status,
      reviewer_id: row.reviewer_id || row.approved_by || null,
      reviewer_name: row.reviewer_name || row.reviewer_full_name || null,
      reviewer_role: row.reviewer_role || null,
      reviewer_title: row.reviewer_title || null,
      review_department_id: row.review_department_id || null,
      assigned_department_head_id: row.assigned_department_head_id || null,
      department_head_reviewer_id: row.department_head_reviewer_id || null,
      department_head_reviewer_name: row.department_head_reviewer_name || null,
      department_head_reviewed_at: row.department_head_reviewed_at || null,
      department_head_remarks: row.department_head_remarks || null,
      department_head_action: row.department_head_action || null,
      hr_remarks: row.reviewer_remarks || null,
      recommendation_remarks: row.recommendation_remarks || null,
      disapproval_reason: row.disapproval_reason || null,
      approved_days_with_pay:
        row.approved_days_with_pay != null ? parseFloat(row.approved_days_with_pay) : null,
      approved_days_without_pay:
        row.approved_days_without_pay != null ? parseFloat(row.approved_days_without_pay) : null,
      reserved_credit_days:
        row.reserved_credit_days != null ? parseFloat(row.reserved_credit_days) : null,
      approved_other_details: row.approved_other_details || null,
      reviewed_at: row.reviewed_at || row.approved_at || null,
      approved_at: row.approved_at || null,
      created_at: row.created_at || null,
      updated_at: row.updated_at || null,
      leave_type: row.leave_type_name || row.leave_type || null,
      leave_type_display_name:
        row.leave_type_display_name ||
        details.leave_type_display_name ||
        details.leaveTypeDisplayName ||
        row.leave_type_description ||
        details.custom_leave_type_text ||
        details.customLeaveTypeText ||
        systemLeaveTypeDisplayName(row.leave_type_name || row.leave_type),
      workflow_snapshot: row.workflow_snapshot || null,
      paper_approval_record: publicPaperRecord(row.paper_approval_record),
      final_review_route: row.final_review_route || 'hr',
      final_reviewer_user_id: row.final_reviewer_user_id || null,
      attachment_name: row.attachment_name || null,
      attachment_path: row.attachment_path || null,
      attachment_mime_type: row.attachment_mime_type || null,
      attachment_uploaded_at: row.attachment_uploaded_at || null,
      office_department: official.office_department || row.assignment_department_name || null,
      position_title: official.position_title || null,
      salary: official.salary,
      date_filed: official.date_filed || toIsoDateStr(row.created_at),
    };
  }
  return { mapLeaveRowToApi };
};
