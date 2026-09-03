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

const CUSTOM_LEAVE_FIELD_TYPES = new Set([
  'text',
  'long_text',
  'date',
  'number',
  'boolean',
  'select',
]);

const RESERVED_CUSTOM_LEAVE_DETAIL_KEYS = new Set([
  ...EMPLOYEE_EDITABLE_LEAVE_DETAIL_KEYS,
  'id',
  'user_id',
  'userId',
  'employee_id',
  'employeeId',
  'employee_name',
  'employeeName',
  'office_department',
  'officeDepartment',
  'position_title',
  'positionTitle',
  'salary',
  'salary_grade',
  'salaryGrade',
  'date_filed',
  'dateFiled',
  'leave_type',
  'leaveType',
  'start_date',
  'startDate',
  'end_date',
  'endDate',
  'reason',
  'status',
  'working_days_applied',
  'workingDaysApplied',
  'total_days',
  'number_of_days',
  'attachment_name',
  'attachment_path',
  'attachment_mime_type',
  'reviewer_id',
  'reviewer_name',
  'reviewer_role',
  'reviewer_title',
  'reviewed_at',
  'hr_remarks',
  'recommendation_remarks',
  'disapproval_reason',
  'approved_days_with_pay',
  'approved_days_without_pay',
  'approved_other_details',
  'approved_by',
  'approved_at',
  'review_department_id',
  'assigned_department_head_id',
  'department_head_reviewer_id',
  'department_head_reviewer_name',
  'department_head_reviewed_at',
  'department_head_remarks',
  'department_head_action',
  'employee_official_snapshot',
  'employee_detail_schema_snapshot',
]);

const MAX_CUSTOM_LEAVE_FIELDS = 20;
const MAX_CUSTOM_FIELD_LABEL_LENGTH = 80;
const MAX_CUSTOM_FIELD_OPTIONS = 20;
const MAX_CUSTOM_FIELD_OPTION_LENGTH = 80;

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

function leaveDetailsPolicyError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function parseJsonValue(value) {
  if (typeof value !== 'string') return value;
  const text = value.trim();
  if (!text) return value;
  try {
    return JSON.parse(text);
  } catch (_) {
    return value;
  }
}

function normalizeEmployeeDetailSchema(value, { strict = false } = {}) {
  const parsed = parseJsonValue(value);
  if (parsed == null) return [];
  if (!Array.isArray(parsed)) {
    if (strict) {
      throw leaveDetailsPolicyError('Custom form fields must be a list.');
    }
    return [];
  }
  if (parsed.length > MAX_CUSTOM_LEAVE_FIELDS) {
    if (strict) {
      throw leaveDetailsPolicyError(
        `A leave type can have at most ${MAX_CUSTOM_LEAVE_FIELDS} custom fields.`
      );
    }
  }

  const normalized = [];
  const seenKeys = new Set();
  for (const item of parsed.slice(0, MAX_CUSTOM_LEAVE_FIELDS)) {
    if (!isPlainObject(item)) {
      if (strict) throw leaveDetailsPolicyError('Each custom field must be an object.');
      continue;
    }

    const key = String(item.key || '').trim();
    const label = String(item.label || '').trim();
    const type = String(item.type || 'text').trim().toLowerCase();
    if (!/^[a-z][a-z0-9_]{0,63}$/.test(key)) {
      if (strict) {
        throw leaveDetailsPolicyError(
          `Custom field key "${key || '(blank)'}" must use lowercase letters, numbers, and underscores.`
        );
      }
      continue;
    }
    if (RESERVED_CUSTOM_LEAVE_DETAIL_KEYS.has(key)) {
      if (strict) {
        throw leaveDetailsPolicyError(`Custom field key "${key}" is reserved.`);
      }
      continue;
    }
    if (seenKeys.has(key)) {
      if (strict) {
        throw leaveDetailsPolicyError(`Custom field key "${key}" is duplicated.`);
      }
      continue;
    }
    if (!label || label.length > MAX_CUSTOM_FIELD_LABEL_LENGTH) {
      if (strict) {
        throw leaveDetailsPolicyError(
          `Custom field "${key}" must have a label up to ${MAX_CUSTOM_FIELD_LABEL_LENGTH} characters.`
        );
      }
      continue;
    }
    if (!CUSTOM_LEAVE_FIELD_TYPES.has(type)) {
      if (strict) {
        throw leaveDetailsPolicyError(`Custom field "${label}" has an unsupported type.`);
      }
      continue;
    }

    const defaultMaxLength = type === 'long_text' ? 2000 : 255;
    const parsedMaxLength = Number.parseInt(
      item.max_length ?? item.maxLength ?? defaultMaxLength,
      10
    );
    if (
      strict &&
      (type === 'text' || type === 'long_text') &&
      (!Number.isFinite(parsedMaxLength) || parsedMaxLength < 1 || parsedMaxLength > 5000)
    ) {
      throw leaveDetailsPolicyError(
        `Custom field "${label}" must allow between 1 and 5000 characters.`
      );
    }
    const maxLength = Number.isFinite(parsedMaxLength)
      ? Math.min(Math.max(parsedMaxLength, 1), 5000)
      : defaultMaxLength;
    const rawOptions = Array.isArray(item.options) ? item.options : [];
    if (strict && rawOptions.length > MAX_CUSTOM_FIELD_OPTIONS) {
      throw leaveDetailsPolicyError(
        `Select field "${label}" can have at most ${MAX_CUSTOM_FIELD_OPTIONS} options.`
      );
    }
    if (
      strict &&
      rawOptions.some(
        (option) => String(option ?? '').trim().length > MAX_CUSTOM_FIELD_OPTION_LENGTH
      )
    ) {
      throw leaveDetailsPolicyError(
        `Options for "${label}" must not exceed ${MAX_CUSTOM_FIELD_OPTION_LENGTH} characters.`
      );
    }
    const options = [...new Set(
      rawOptions
        .map((option) => String(option ?? '').trim())
        .filter(Boolean)
        .map((option) => option.slice(0, MAX_CUSTOM_FIELD_OPTION_LENGTH))
    )].slice(0, MAX_CUSTOM_FIELD_OPTIONS);
    if (type === 'select' && options.length === 0) {
      if (strict) {
        throw leaveDetailsPolicyError(`Select field "${label}" needs at least one option.`);
      }
      continue;
    }

    seenKeys.add(key);
    normalized.push({
      key,
      label,
      type,
      required: item.required === true,
      ...(type === 'text' || type === 'long_text'
        ? { max_length: maxLength }
        : {}),
      ...(type === 'select' ? { options } : {}),
    });
  }
  return normalized;
}

function serializeEmployeeDetailSchema(value, options = {}) {
  return JSON.stringify(normalizeEmployeeDetailSchema(value, options));
}

function isIsoDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return (
    parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day
  );
}

function customLeaveDetailValues(details, schema, { validate = false } = {}) {
  const source = isPlainObject(details) ? details : {};
  const fields = normalizeEmployeeDetailSchema(schema);
  const output = {};

  for (const field of fields) {
    const raw = source[field.key];
    const blank = raw == null || (typeof raw === 'string' && raw.trim() === '');
    if (blank) {
      if (validate && field.required) {
        throw leaveDetailsPolicyError(`${field.label} is required.`);
      }
      continue;
    }

    if (field.type === 'text' || field.type === 'long_text') {
      if (typeof raw !== 'string') {
        if (validate) throw leaveDetailsPolicyError(`${field.label} must be text.`);
        continue;
      }
      const value = raw.trim();
      if (value.length > field.max_length) {
        if (validate) {
          throw leaveDetailsPolicyError(
            `${field.label} must not exceed ${field.max_length} characters.`
          );
        }
        continue;
      }
      output[field.key] = value;
      continue;
    }

    if (field.type === 'date') {
      const value = String(raw).trim();
      if (!isIsoDate(value)) {
        if (validate) throw leaveDetailsPolicyError(`${field.label} must be a valid date.`);
        continue;
      }
      output[field.key] = value;
      continue;
    }

    if (field.type === 'number') {
      const value = typeof raw === 'number' ? raw : Number(String(raw).trim());
      if (!Number.isFinite(value)) {
        if (validate) throw leaveDetailsPolicyError(`${field.label} must be a number.`);
        continue;
      }
      output[field.key] = value;
      continue;
    }

    if (field.type === 'boolean') {
      let value = raw;
      if (typeof raw === 'string' && ['true', 'false'].includes(raw.toLowerCase())) {
        value = raw.toLowerCase() === 'true';
      }
      if (typeof value !== 'boolean') {
        if (validate) throw leaveDetailsPolicyError(`${field.label} must be Yes or No.`);
        continue;
      }
      output[field.key] = value;
      continue;
    }

    if (field.type === 'select') {
      const value = String(raw).trim();
      if (!field.options.includes(value)) {
        if (validate) throw leaveDetailsPolicyError(`${field.label} has an invalid option.`);
        continue;
      }
      output[field.key] = value;
    }
  }
  return output;
}

function sanitizeEmployeeLeaveDetails(value, customFieldSchema = []) {
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
  return {
    ...sanitized,
    ...customLeaveDetailValues(value, customFieldSchema),
  };
}

function employeeLeaveDetailsFromPayload({ details, rest, customFieldSchema } = {}) {
  const topLevel = isPlainObject(rest) ? rest : {};
  const nested = isPlainObject(details) ? details : {};
  const merged = { ...topLevel, ...nested };
  return {
    ...sanitizeEmployeeLeaveDetails(merged),
    ...customLeaveDetailValues(merged, customFieldSchema, { validate: true }),
  };
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
  CUSTOM_LEAVE_FIELD_TYPES,
  EMPLOYEE_EDITABLE_LEAVE_DETAIL_KEYS,
  RESERVED_CUSTOM_LEAVE_DETAIL_KEYS,
  customLeaveDetailValues,
  employeeLeaveDetailsFromPayload,
  loadEmployeeOfficialSnapshot,
  normalizeEmployeeDetailSchema,
  normalizeEmployeeOfficialSnapshot,
  parseNumericSalaryGrade,
  sanitizeEmployeeLeaveDetails,
  serializeEmployeeDetailSchema,
};
