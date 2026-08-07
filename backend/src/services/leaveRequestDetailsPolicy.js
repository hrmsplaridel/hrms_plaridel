const EMPLOYEE_EDITABLE_LEAVE_DETAIL_KEYS = new Set([
  'custom_leave_type_text',
  'customLeaveTypeText',
  'location_option',
  'locationOption',
  'location_details',
  'locationDetails',
  'sick_leave_nature',
  'sickLeaveNature',
  'sick_illness_details',
  'sickIllnessDetails',
  'illness_details',
  'illnessDetails',
  'maternity_delivery_type',
  'maternityDeliveryType',
  'maternity_delivery',
  'delivery_type',
  'expected_delivery_date',
  'expectedDeliveryDate',
  'maternity_expected_delivery_date',
  'maternityExpectedDeliveryDate',
  'child_delivery_date',
  'childDeliveryDate',
  'delivery_date',
  'deliveryDate',
  'spouse_delivery_date',
  'spouseDeliveryDate',
  'accident_date',
  'accidentDate',
  'calamity_date',
  'calamityDate',
  'calamity_occurrence_date',
  'calamityOccurrenceDate',
  'adoption_parent_role',
  'adoptionParentRole',
  'adoptive_parent_role',
  'adoptiveParentRole',
  'adoption_placement_date',
  'adoptionPlacementDate',
  'adoption_finalization_date',
  'adoptionFinalizationDate',
  'papa_date',
  'papaDate',
  'vawc_support_document_type',
  'vawcSupportDocumentType',
  'vawc_document_type',
  'vawcDocumentType',
  'vawc_case_details',
  'vawcCaseDetails',
  'vawc_protection_order_details',
  'vawcProtectionOrderDetails',
  'protection_order_details',
  'protectionOrderDetails',
  'solo_parent_id_number',
  'soloParentIdNumber',
  'solo_parent_id',
  'soloParentId',
  'solo_parent_id_expiry_date',
  'soloParentIdExpiryDate',
  'solo_parent_id_valid_until',
  'soloParentIdValidUntil',
  'women_illness_details',
  'womenIllnessDetails',
  'study_purpose',
  'studyPurpose',
  'study_purpose_details',
  'studyPurposeDetails',
  'other_purpose',
  'otherPurpose',
  'other_purpose_details',
  'otherPurposeDetails',
  'commutation',
]);

function isPlainObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function isSupportedDetailValue(value) {
  return (
    value == null ||
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  );
}

function sanitizeEmployeeLeaveDetails(value) {
  if (!isPlainObject(value)) return {};
  const sanitized = {};
  for (const [key, detailValue] of Object.entries(value)) {
    if (
      EMPLOYEE_EDITABLE_LEAVE_DETAIL_KEYS.has(key) &&
      isSupportedDetailValue(detailValue)
    ) {
      sanitized[key] = detailValue;
    }
  }
  return sanitized;
}

function employeeLeaveDetailsFromPayload({ details, rest } = {}) {
  const topLevel = isPlainObject(rest) ? rest : {};
  const nested = isPlainObject(details) ? details : {};
  return sanitizeEmployeeLeaveDetails({ ...topLevel, ...nested });
}

function parseNumericSalaryGrade(value) {
  if (value == null) return null;
  const normalized = String(value).trim().replace(/,/g, '');
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeEmployeeOfficialSnapshot(value) {
  const source = isPlainObject(value) ? value : {};
  const textOrNull = (input) => {
    const text = input == null ? '' : String(input).trim();
    return text || null;
  };
  return {
    employee_name: textOrNull(source.employee_name),
    office_department: textOrNull(source.office_department),
    position_title: textOrNull(source.position_title),
    salary:
      source.salary == null ? null : parseNumericSalaryGrade(source.salary),
    date_filed: textOrNull(source.date_filed),
  };
}

async function loadEmployeeOfficialSnapshot(db, employeeUserId, effectiveDate = null) {
  const result = await db.query(
    `SELECT u.full_name,
            u.salary_grade,
            d.name AS department_name,
            p.name AS position_name,
            to_char(
              (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date,
              'YYYY-MM-DD'
            ) AS date_filed
     FROM users u
     LEFT JOIN LATERAL (
       SELECT a.department_id, a.position_id
       FROM assignments a
       WHERE a.employee_id = u.id
         AND (
           a.effective_from IS NULL
           OR a.effective_from <= COALESCE(
             $2::date,
             (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
           )
         )
         AND (
           a.effective_to IS NULL
           OR a.effective_to >= COALESCE(
             $2::date,
             (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
           )
         )
       ORDER BY a.effective_from DESC NULLS LAST,
                a.created_at DESC NULLS LAST,
                a.id DESC
       LIMIT 1
     ) a ON true
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN positions p ON p.id = a.position_id
     WHERE u.id = $1::uuid
     LIMIT 1`,
    [employeeUserId, effectiveDate]
  );
  const row = result.rows[0];
  if (!row) {
    const error = new Error('Employee record not found');
    error.statusCode = 404;
    throw error;
  }
  return normalizeEmployeeOfficialSnapshot({
    employee_name: row.full_name,
    office_department: row.department_name,
    position_title: row.position_name,
    salary: parseNumericSalaryGrade(row.salary_grade),
    date_filed: row.date_filed,
  });
}

module.exports = {
  EMPLOYEE_EDITABLE_LEAVE_DETAIL_KEYS,
  employeeLeaveDetailsFromPayload,
  loadEmployeeOfficialSnapshot,
  normalizeEmployeeOfficialSnapshot,
  parseNumericSalaryGrade,
  sanitizeEmployeeLeaveDetails,
};
