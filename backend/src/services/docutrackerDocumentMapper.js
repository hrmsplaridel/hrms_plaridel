const { coalesceDocumentTitle } = require('../utils/docutrackerDisplayTitle');

function normalizeStatus(value) {
  if (!value) return 'pending';
  const s = String(value).toLowerCase().trim().replaceAll(' ', '_');
  if (s === 'inreview') return 'in_review';
  // Backward-compatibility: treat legacy 'forwarded' as active in_review.
  if (s === 'forwarded') return 'in_review';
  return s;
}

/** Single document response DTO shared by the workflow service and routes. */
function mapDocumentRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    document_number: row.document_number,
    document_type: row.document_type,
    title: coalesceDocumentTitle(row),
    description: row.description,
    source_module: row.source_module,
    source_table: row.source_table,
    source_record_id: row.source_record_id,
    source_title: row.source_title,
    source_status: row.source_status ?? null,
    source_action: row.source_action ?? null,
    source_action_label: row.source_action_label ?? null,
    file_path: row.file_path,
    file_name: row.file_name,
    created_by: row.created_by,
    originating_department_id: row.originating_department_id ?? null,
    creator_name: row.creator_name ?? null,
    assignee_name: row.assignee_name ?? null,
    current_holder_id: row.current_holder_id,
    current_step: row.current_step,
    status: normalizeStatus(row.status),
    sent_time: row.sent_time,
    deadline_time: row.deadline_time,
    reviewed_time: row.reviewed_time,
    workflow_version: row.workflow_version,
    escalation_level: row.escalation_level,
    needs_admin_intervention: row.needs_admin_intervention,
    signature_signer_ids: Array.isArray(row.signature_signer_ids)
      ? row.signature_signer_ids.map(String)
      : [],
    release_required: row.release_required === true,
    released_at: row.released_at ?? null,
    released_to_department_id: row.released_to_department_id ?? null,
    released_to_department_name: row.released_to_department_name ?? null,
    released_by: row.released_by ?? null,
    released_by_name: row.released_by_name ?? null,
    release_remarks: row.release_remarks ?? null,
    viewer_release_access: row.viewer_release_access === true,
    viewer_can_release: row.viewer_can_release === true,
    viewer_is_routing_assignee: row.viewer_is_routing_assignee === true,
    viewer_participated_in_source: row.viewer_participated_in_source === true,
    source_only: row.source_only === true,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

module.exports = {
  normalizeStatus,
  mapDocumentRow,
};
