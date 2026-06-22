const crypto = require('crypto');

const EXPORT_TTL_MS = 15 * 60 * 1000;
const exportsByToken = new Map();

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

function dtrExportRows(context) {
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

function pruneExpiredExports(now = Date.now()) {
  for (const [token, item] of exportsByToken.entries()) {
    if (item.expiresAt <= now) exportsByToken.delete(token);
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
  const token = crypto.randomBytes(24).toString('hex');
  const expiresAt = Date.now() + EXPORT_TTL_MS;
  exportsByToken.set(token, {
    userId: String(userId),
    filename,
    mimeType,
    buffer: Buffer.from(content, 'utf8'),
    expiresAt,
  });
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
  const item = exportsByToken.get(String(token || ''));
  if (!item || item.userId !== String(userId)) return null;
  return item;
}

module.exports = {
  createDtrExportAttachment,
  getDtrExport,
  dtrExportRows,
};
