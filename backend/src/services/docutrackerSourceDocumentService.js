const jwt = require('jsonwebtoken');

const {
  canUserPerformTypeAction,
} = require('./docutrackerWorkflowService');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function serviceError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function field(label, value) {
  if (value == null || String(value).trim() === '') return null;
  return { label, value: String(value) };
}

function displayDateTime(value) {
  if (value == null || value === '') return null;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString('en-US', {
    timeZone: HRMS_TIMEZONE,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
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
            r.seen_at, seen_by.full_name AS seen_by_name,
            reviewed_by.full_name AS reviewed_by_name,
            a.id AS attachment_id, a.file_name AS attachment_name
     FROM training_daily_reports r
     JOIN users u ON u.id = r.employee_id
     LEFT JOIN users seen_by ON seen_by.id = r.seen_by_admin
     LEFT JOIN users reviewed_by ON reviewed_by.id = r.reviewed_by
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
      field('Submitted', displayDateTime(row.submitted_at)),
      field('Seen by', row.seen_by_name),
      field('Seen on', displayDateTime(row.seen_at)),
      field('Reviewed by', row.reviewed_by_name),
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
  // Recruitment applications are viewed in RSP, not DocuTracker.
  throw serviceError('NOT_FOUND', 'This source document type is not supported');
}

module.exports = {
  getLinkedSourceDocument,
};
