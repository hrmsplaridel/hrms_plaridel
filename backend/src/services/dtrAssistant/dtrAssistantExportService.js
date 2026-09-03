const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const DEFAULT_EXPORT_TTL_MS = 15 * 60 * 1000;
const DEFAULT_MAX_EXPORTS = 500;
const DEFAULT_MAX_EXPORT_BYTES = 100 * 1024 * 1024;
const DEFAULT_MAX_EXPORTS_PER_USER = 10;
const EXPORT_CLEANUP_INTERVAL_MS = 60 * 1000;
const ORPHAN_GRACE_MS = 5 * 60 * 1000;
const TOKEN_PATTERN = /^[a-f0-9]{48}$/;
let exportDirectoryOverride = null;
let exportLimitsOverride = null;

function csvCell(value) {
  const text = String(value ?? '');
  if (/[",\r\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function xmlCell(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function assertCompleteDtrExportContext(context) {
  const completeness = context?.data_completeness;
  const recordsComplete = completeness?.dtr_records?.complete === true;
  const calendarComplete = completeness?.dtr_calendar_days?.complete === true;
  const exportComplete = completeness?.dtr_export?.complete === true;

  if (recordsComplete && calendarComplete && exportComplete) return;

  const error = new Error(
    'The selected DTR data is incomplete. Refresh the records before generating an export.'
  );
  error.statusCode = 409;
  error.code = 'DTR_ASSISTANT_EXPORT_INCOMPLETE';
  throw error;
}

function dtrExportRows(context) {
  assertCompleteDtrExportContext(context);
  const recordsByDate = new Map(
    (context.dtr_records || []).map((record) => [
      String(record.attendance_date).slice(0, 10),
      record,
    ])
  );
  const calendarDays = context.dtr_calendar_days || [];
  const dates =
    calendarDays.length > 0
      ? calendarDays.map((day) => day.attendance_date)
      : [...recordsByDate.keys()].sort();
  const calendarByDate = new Map(
    calendarDays.map((day) => [day.attendance_date, day])
  );
  const header = [
    'Date',
    'Shift',
    'Schedule',
    'Grace Minutes',
    'Holiday',
    'Status',
    'AM In',
    'AM Out',
    'PM In',
    'PM Out',
    'Total Hours',
    'Late Minutes',
    'Undertime Minutes',
    'Overtime Minutes',
    'Leave Type',
    'Source',
    'Remarks',
  ];
  const rows = dates.map((date) => {
    const record = recordsByDate.get(date) || {};
    const day = calendarByDate.get(date) || {};
    return [
      date,
      day.shift_name || '',
      day.start_time || day.end_time
        ? `${day.start_time || ''}-${day.end_time || ''}`
        : '',
      day.grace_period_minutes ?? '',
      day.holiday_name
        ? `${day.holiday_name} (${day.holiday_coverage || 'whole_day'})`
        : record.holiday_name || '',
      record.status || (day.shift_id ? 'no_record' : 'no_schedule'),
      record.time_in || '',
      record.break_out || '',
      record.break_in || '',
      record.time_out || '',
      record.total_hours ?? '',
      record.late_minutes ?? '',
      record.undertime_minutes ?? '',
      record.overtime_minutes ?? '',
      record.leave_type || '',
      record.source || '',
      record.remarks || '',
    ];
  });
  return { header, rows };
}

function buildCsv(context) {
  const { header, rows } = dtrExportRows(context);
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n');
}

function buildExcelXml(context) {
  const { header, rows } = dtrExportRows(context);
  const tableRows = [header, ...rows]
    .map((row, index) => {
      const style = index === 0 ? ' ss:StyleID="header"' : '';
      const cells = row
        .map(
          (value) =>
            `<Cell${style}><Data ss:Type="String">${xmlCell(value)}</Data></Cell>`
        )
        .join('');
      return `<Row>${cells}</Row>`;
    })
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
 <Styles>
  <Style ss:ID="header">
   <Font ss:Bold="1"/>
   <Interior ss:Color="#E8EEF8" ss:Pattern="Solid"/>
  </Style>
 </Styles>
 <Worksheet ss:Name="DTR Export">
  <Table>${tableRows}</Table>
 </Worksheet>
</Workbook>`;
}

function boundedInteger(value, fallback, min, max) {
  const parsed = Number.parseInt(value || '', 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function exportLimits(env = process.env) {
  if (exportLimitsOverride) return exportLimitsOverride;
  return {
    ttlMs: boundedInteger(
      env.DTR_ASSISTANT_EXPORT_TTL_MS,
      DEFAULT_EXPORT_TTL_MS,
      60 * 1000,
      24 * 60 * 60 * 1000
    ),
    maxEntries: boundedInteger(
      env.DTR_ASSISTANT_EXPORT_MAX_ENTRIES,
      DEFAULT_MAX_EXPORTS,
      1,
      5000
    ),
    maxBytes: boundedInteger(
      env.DTR_ASSISTANT_EXPORT_MAX_BYTES,
      DEFAULT_MAX_EXPORT_BYTES,
      1024 * 1024,
      1024 * 1024 * 1024
    ),
    maxPerUser: boundedInteger(
      env.DTR_ASSISTANT_EXPORT_MAX_PER_USER,
      DEFAULT_MAX_EXPORTS_PER_USER,
      1,
      100
    ),
  };
}

function exportDirectory() {
  return (
    exportDirectoryOverride ||
    process.env.DTR_ASSISTANT_EXPORT_DIR ||
    path.join(os.tmpdir(), 'hrms-plaridel-dtr-assistant-exports')
  );
}

function ensureExportDirectory() {
  const directory = exportDirectory();
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  return directory;
}

function exportPaths(token) {
  const safeToken = String(token || '').trim().toLowerCase();
  if (!TOKEN_PATTERN.test(safeToken)) return null;
  const directory = exportDirectory();
  return {
    token: safeToken,
    data: path.join(directory, `${safeToken}.data`),
    metadata: path.join(directory, `${safeToken}.json`),
  };
}

function removeStoredExport(token) {
  const paths = exportPaths(token);
  if (!paths) return;
  for (const filePath of [paths.metadata, paths.data]) {
    try {
      fs.unlinkSync(filePath);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

function readStoredMetadata(token) {
  const paths = exportPaths(token);
  if (!paths) return null;
  try {
    const metadata = JSON.parse(fs.readFileSync(paths.metadata, 'utf8'));
    const stat = fs.statSync(paths.data);
    if (
      metadata.token !== paths.token ||
      !metadata.userId ||
      !metadata.filename ||
      !metadata.mimeType ||
      !Number.isFinite(metadata.createdAt) ||
      !Number.isFinite(metadata.expiresAt) ||
      stat.size !== metadata.size
    ) {
      removeStoredExport(paths.token);
      return null;
    }
    return { ...metadata, paths };
  } catch (error) {
    if (error.code !== 'ENOENT') {
      removeStoredExport(paths.token);
    }
    return null;
  }
}

function listStoredExports() {
  const directory = ensureExportDirectory();
  const items = [];
  for (const filename of fs.readdirSync(directory)) {
    if (!filename.endsWith('.json')) continue;
    const token = filename.slice(0, -5);
    const item = readStoredMetadata(token);
    if (item) items.push(item);
  }
  return items.sort(
    (left, right) =>
      left.createdAt - right.createdAt || left.token.localeCompare(right.token)
  );
}

function pruneStaleOrphans(now = Date.now()) {
  const directory = ensureExportDirectory();
  const filenames = fs.readdirSync(directory);
  const names = new Set(filenames);
  for (const filename of filenames) {
    const isTemporary = filename.endsWith('.tmp');
    const isOrphanedData =
      filename.endsWith('.data') &&
      !names.has(`${filename.slice(0, -5)}.json`);
    if (!isTemporary && !isOrphanedData) continue;
    const filePath = path.join(directory, filename);
    try {
      if (fs.statSync(filePath).mtimeMs <= now - ORPHAN_GRACE_MS) {
        fs.unlinkSync(filePath);
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

function pruneExpiredExports(now = Date.now()) {
  pruneStaleOrphans(now);
  for (const item of listStoredExports()) {
    if (item.expiresAt <= now) removeStoredExport(item.token);
  }
}

function enforceExportLimits() {
  const limits = exportLimits();
  let items = listStoredExports();
  const byUser = new Map();
  for (const item of items) {
    const userItems = byUser.get(item.userId) || [];
    userItems.push(item);
    byUser.set(item.userId, userItems);
  }
  for (const userItems of byUser.values()) {
    while (userItems.length > limits.maxPerUser) {
      removeStoredExport(userItems.shift().token);
    }
  }

  items = listStoredExports();
  let totalBytes = items.reduce((sum, item) => sum + item.size, 0);
  while (
    items.length > limits.maxEntries ||
    totalBytes > limits.maxBytes
  ) {
    const removed = items.shift();
    if (!removed) break;
    removeStoredExport(removed.token);
    totalBytes -= removed.size;
  }
}

function writeStoredExport(item) {
  const paths = exportPaths(item.token);
  if (!paths) throw new Error('Generated export token is invalid.');
  ensureExportDirectory();
  const nonce = crypto.randomBytes(6).toString('hex');
  const temporaryData = `${paths.data}.${process.pid}.${nonce}.tmp`;
  const temporaryMetadata = `${paths.metadata}.${process.pid}.${nonce}.tmp`;
  try {
    fs.writeFileSync(temporaryData, item.buffer, { mode: 0o600 });
    fs.renameSync(temporaryData, paths.data);
    fs.writeFileSync(
      temporaryMetadata,
      JSON.stringify({
        token: item.token,
        userId: item.userId,
        filename: item.filename,
        mimeType: item.mimeType,
        size: item.buffer.length,
        createdAt: item.createdAt,
        expiresAt: item.expiresAt,
      }),
      { mode: 0o600 }
    );
    fs.renameSync(temporaryMetadata, paths.metadata);
  } finally {
    for (const temporaryPath of [temporaryData, temporaryMetadata]) {
      try {
        fs.unlinkSync(temporaryPath);
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
    }
  }
}

function createDtrExportAttachment(context, userId, format = 'xls') {
  pruneExpiredExports();
  const start = context.date_range?.startDate || 'dtr';
  const end = context.date_range?.endDate || start;
  const safeStart = String(start).replace(/[^0-9a-z_-]/gi, '');
  const safeEnd = String(end).replace(/[^0-9a-z_-]/gi, '');
  const isCsv = String(format).toLowerCase() === 'csv';
  const filename = `dtr_export_${safeStart}_${safeEnd}.${isCsv ? 'csv' : 'xls'}`;
  const mimeType = isCsv
    ? 'text/csv'
    : 'application/vnd.ms-excel; charset=utf-8';
  const content = isCsv ? buildCsv(context) : buildExcelXml(context);
  const buffer = Buffer.from(content, 'utf8');
  const limits = exportLimits();
  if (buffer.length > limits.maxBytes) {
    const error = new Error(
      'The generated DTR export exceeds the configured download size limit.'
    );
    error.statusCode = 413;
    error.code = 'DTR_ASSISTANT_EXPORT_TOO_LARGE';
    throw error;
  }
  const token = crypto.randomBytes(24).toString('hex');
  const createdAt = Date.now();
  const expiresAt = createdAt + limits.ttlMs;
  writeStoredExport({
    token,
    userId: String(userId),
    filename,
    mimeType,
    buffer,
    createdAt,
    expiresAt,
  });
  enforceExportLimits();
  return {
    id: token,
    filename,
    mimeType,
    kind: isCsv ? 'csv' : 'excel',
    downloadUrl: `/api/dtr-assistant/exports/${token}`,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

function getDtrExport(token, userId) {
  pruneExpiredExports();
  const item = readStoredMetadata(token);
  if (!item || item.userId !== String(userId)) return null;
  try {
    return {
      userId: item.userId,
      filename: item.filename,
      mimeType: item.mimeType,
      buffer: fs.readFileSync(item.paths.data),
      expiresAt: item.expiresAt,
    };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return null;
  }
}

const cleanupTimer = setInterval(() => {
  try {
    pruneExpiredExports();
    enforceExportLimits();
  } catch (error) {
    console.error('[dtr-assistant exports] cleanup failed:', error);
  }
}, EXPORT_CLEANUP_INTERVAL_MS);
cleanupTimer.unref();

module.exports = {
  createDtrExportAttachment,
  getDtrExport,
  dtrExportRows,
  assertCompleteDtrExportContext,
  __test: {
    enforceExportLimits,
    exportLimits,
    listStoredExports,
    pruneExpiredExports,
    pruneStaleOrphans,
    removeStoredExport,
    setExportStore(options = {}) {
      exportDirectoryOverride = options.directory || null;
      exportLimitsOverride = options.limits || null;
      ensureExportDirectory();
    },
  },
};
