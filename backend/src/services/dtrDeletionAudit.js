function toDateKey(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  return String(value).slice(0, 10);
}

function dtrDeletionKey(employeeId, attendanceDate) {
  return `${String(employeeId || '')}:${toDateKey(attendanceDate)}`;
}

async function getDeletedDtrDateKeys(db, employeeIds, dateFrom, dateTo) {
  if (!db || !Array.isArray(employeeIds) || employeeIds.length === 0 || !dateFrom || !dateTo) {
    return new Set();
  }

  const result = await db.query(
    `SELECT employee_id, attendance_date::text AS attendance_date
     FROM dtr_daily_summary_deletions
     WHERE employee_id = ANY($1::uuid[])
       AND attendance_date >= $2::date
       AND attendance_date <= $3::date
       AND restored_at IS NULL`,
    [employeeIds, dateFrom, dateTo]
  );

  return new Set(
    result.rows.map((row) => dtrDeletionKey(row.employee_id, row.attendance_date))
  );
}

module.exports = {
  dtrDeletionKey,
  getDeletedDtrDateKeys,
};
