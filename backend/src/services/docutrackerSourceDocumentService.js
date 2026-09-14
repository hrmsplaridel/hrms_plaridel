const jwt = require('jsonwebtoken');

const {
  canUserPerformTypeAction,
} = require('./docutrackerWorkflowService');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function serviceError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function field(label, value) {
  if (value == null || String(value).trim() === '') return null;
  return { label, value: String(value) };
}

function compact(values) {
  return values.filter(Boolean);
}

function signedUrl(payload, path) {
  if (!process.env.JWT_SECRET) return null;
  const token = jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '15m' });
  return `${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`;
}

function attachment(label, name, url) {
  if (!name || !url) return null;
  return { label, name: String(name), url };
}

async function loadTrainingDailyReport(pool, user, sourceRecordId, canViewType) {
  if (user.role !== 'admin') {
    const allowed = await canViewType(pool, {
      user,
      documentType: 'ld',
      action: 'view',
    });
    if (!allowed) {
      throw serviceError('FORBIDDEN', 'You cannot view L&D documents');
    }
  }

  const params = [sourceRecordId];
  const ownerClause = user.role === 'admin' ? '' : 'AND r.employee_id = $2::uuid';
  if (user.role !== 'admin') params.push(user.id);
  const result = await pool.query(
    `SELECT r.id, r.employee_id, u.full_name AS employee_name,
            r.title, r.description, r.submitted_at, r.updated_at, r.status,
            a.id AS attachment_id, a.file_name AS attachment_name
     FROM training_daily_reports r
     JOIN users u ON u.id = r.employee_id
     LEFT JOIN LATERAL (
       SELECT id, file_name
       FROM training_report_attachments
       WHERE report_id = r.id
       ORDER BY created_at DESC
       LIMIT 1
     ) a ON TRUE
     WHERE r.id = $1::uuid ${ownerClause}`,
    params
  );
  const row = result.rows[0];
  if (!row) throw serviceError('NOT_FOUND', 'L&D document not found');

  const attachmentUrl = row.attachment_id
    ? signedUrl(
        { typ: 'training_attachment', attachmentId: String(row.attachment_id) },
        `/api/files/training-report/${encodeURIComponent(row.attachment_id)}`
      )
    : null;
  return {
    source_module: 'ld',
    source_table: 'training_daily_reports',
    source_record_id: String(row.id),
    title: row.title || 'Training Daily Report',
    status: row.status,
    created_at: row.submitted_at,
    updated_at: row.updated_at,
    fields: compact([
      field('Employee', row.employee_name),
      field('Report title', row.title),
      field('Description', row.description || 'No description provided'),
      field('Submitted', row.submitted_at),
      field('Status', row.status),
    ]),
    attachments: compact([
      attachment('Training report attachment', row.attachment_name, attachmentUrl),
    ]),
    print_data: {
      id: String(row.id),
      employee_id: String(row.employee_id),
      employee_name: row.employee_name,
      title: row.title,
      description: row.description,
      submitted_at: row.submitted_at,
      status: row.status,
      attachment_id: row.attachment_id || null,
      attachment_name: row.attachment_name || null,
    },
  };
}

const RSP_ATTACHMENTS = [
  ['Application letter', 'doc_application_letter_name', 'doc_application_letter_path'],
  ['Resume', 'doc_resume_name', 'doc_resume_path'],
  ['Transcript of records', 'doc_tor_name', 'doc_tor_path'],
  ['Eligibility and trainings', 'doc_eligibility_trainings_name', 'doc_eligibility_trainings_path'],
  ['Medical certificate', 'doc_medical_certificate_name', 'doc_medical_certificate_path'],
  ['Drug test result', 'doc_drug_test_name', 'doc_drug_test_path'],
  ['NBI clearance', 'doc_nbi_clearance_name', 'doc_nbi_clearance_path'],
];

async function loadRecruitmentApplication(pool, user, sourceRecordId) {
  if (user.role !== 'admin') {
    throw serviceError('FORBIDDEN', 'Only authorized RSP administrators can view applications');
  }
  const result = await pool.query(
    `SELECT id, applicant_number, full_name, first_name, middle_name,
            last_name, suffix, sex, course, address, age,
            civil_status, email, phone, resume_notes, position_applied_for,
            status, final_interview_at, final_interview_passed,
            final_requirements_approved, orientation_at, orientation_attended,
            hr_account_setup_done, created_at, updated_at,
            attachment_path, attachment_name,
            doc_application_letter_path, doc_application_letter_name,
            doc_resume_path, doc_resume_name, doc_tor_path, doc_tor_name,
            doc_eligibility_trainings_path, doc_eligibility_trainings_name,
            doc_medical_certificate_path, doc_medical_certificate_name,
            doc_drug_test_path, doc_drug_test_name,
            doc_nbi_clearance_path, doc_nbi_clearance_name
     FROM recruitment_applications
     WHERE id = $1::uuid`,
    [sourceRecordId]
  );
  const row = result.rows[0];
  if (!row) throw serviceError('NOT_FOUND', 'RSP application not found');

  const attachmentRows = RSP_ATTACHMENTS.map(([label, nameKey, pathKey]) => {
    const objectPath = row[pathKey];
    const name = row[nameKey];
    if (!objectPath || !name) return null;
    return attachment(
      label,
      name,
      signedUrl(
        { typ: 'rsp_attachment', path: String(objectPath), fn: String(name) },
        '/api/files/recruitment-attachment'
      )
    );
  });
  if (row.attachment_path && row.attachment_name) {
    attachmentRows.unshift(
      attachment(
        'Primary attachment',
        row.attachment_name,
        signedUrl(
          {
            typ: 'rsp_attachment',
            path: String(row.attachment_path),
            fn: String(row.attachment_name),
          },
          '/api/files/recruitment-attachment'
        )
      )
    );
  }

  return {
    source_module: 'rsp',
    source_table: 'recruitment_applications',
    source_record_id: String(row.id),
    title: row.position_applied_for || row.full_name || 'Recruitment Application',
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    fields: compact([
      field('Applicant number', row.applicant_number),
      field('Applicant', row.full_name),
      field('Position applied for', row.position_applied_for),
      field('Email', row.email),
      field('Phone', row.phone),
      field('Course', row.course),
      field('Sex', row.sex),
      field('Age', row.age),
      field('Civil status', row.civil_status),
      field('Address', row.address),
      field('Application notes', row.resume_notes),
      field('Status', row.status),
      field('Final interview', row.final_interview_at),
      field(
        'Final interview result',
        row.final_interview_passed == null
          ? null
          : row.final_interview_passed
            ? 'Passed'
            : 'Not passed'
      ),
      field(
        'Final requirements',
        row.final_requirements_approved ? 'Approved' : 'Not yet approved'
      ),
      field('Orientation schedule', row.orientation_at),
      field(
        'Orientation attendance',
        row.orientation_attended == null
          ? null
          : row.orientation_attended
            ? 'Attended'
            : 'Did not attend'
      ),
      field(
        'Employee account setup',
        row.hr_account_setup_done ? 'Completed' : 'Not yet completed'
      ),
    ]),
    attachments: compact(attachmentRows),
    print_data: {
      id: String(row.id),
      applicant_number: row.applicant_number,
      full_name: row.full_name,
      first_name: row.first_name,
      middle_name: row.middle_name,
      last_name: row.last_name,
      suffix: row.suffix,
      sex: row.sex,
      course: row.course,
      address: row.address,
      age: row.age,
      civil_status: row.civil_status,
      email: row.email,
      phone: row.phone,
      resume_notes: row.resume_notes,
      position_applied_for: row.position_applied_for,
      status: row.status,
      final_interview_at: row.final_interview_at,
      final_interview_passed: row.final_interview_passed,
      final_requirements_approved: row.final_requirements_approved,
      orientation_at: row.orientation_at,
      orientation_attended: row.orientation_attended,
      hr_account_setup_done: row.hr_account_setup_done,
      created_at: row.created_at,
      updated_at: row.updated_at,
      attachment_path: row.attachment_path ? 'linked' : null,
      attachment_name: row.attachment_name,
      doc_application_letter_path: row.doc_application_letter_path ? 'linked' : null,
      doc_application_letter_name: row.doc_application_letter_name,
      doc_resume_path: row.doc_resume_path ? 'linked' : null,
      doc_resume_name: row.doc_resume_name,
      doc_tor_path: row.doc_tor_path ? 'linked' : null,
      doc_tor_name: row.doc_tor_name,
      doc_eligibility_trainings_path: row.doc_eligibility_trainings_path
        ? 'linked'
        : null,
      doc_eligibility_trainings_name: row.doc_eligibility_trainings_name,
      doc_medical_certificate_path: row.doc_medical_certificate_path ? 'linked' : null,
      doc_medical_certificate_name: row.doc_medical_certificate_name,
      doc_drug_test_path: row.doc_drug_test_path ? 'linked' : null,
      doc_drug_test_name: row.doc_drug_test_name,
      doc_nbi_clearance_path: row.doc_nbi_clearance_path ? 'linked' : null,
      doc_nbi_clearance_name: row.doc_nbi_clearance_name,
    },
  };
}

async function getLinkedSourceDocument(
  pool,
  user,
  sourceModule,
  sourceTable,
  sourceRecordId,
  { canViewType = canUserPerformTypeAction } = {}
) {
  const moduleName = String(sourceModule || '').trim().toLowerCase();
  const tableName = String(sourceTable || '').trim().toLowerCase();
  if (!UUID_RE.test(String(sourceRecordId || '').trim())) {
    throw serviceError('NOT_FOUND', 'Source document not found');
  }
  if (moduleName === 'ld' && tableName === 'training_daily_reports') {
    return loadTrainingDailyReport(pool, user, sourceRecordId, canViewType);
  }
  if (moduleName === 'rsp' && tableName === 'recruitment_applications') {
    return loadRecruitmentApplication(pool, user, sourceRecordId);
  }
  throw serviceError('NOT_FOUND', 'This source document type is not supported');
}

module.exports = {
  getLinkedSourceDocument,
};
