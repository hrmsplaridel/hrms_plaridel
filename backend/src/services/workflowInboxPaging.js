'use strict';
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const rankSql = "CASE WHEN r.status IN ('pending_hr','pending_mayor') THEN 0 ELSE 1 END";
function bad(message) { return Object.assign(new Error(message), {statusCode: 400}); }
function optionsFor(options) {
  if (!options.paginated) return {paginated: false, kinds: ['leave', 'locator']};
  const limit = Number(options.limit ?? 50);
  if (!/^\d+$/.test(String(options.limit ?? 50)) || !Number.isInteger(limit) || limit < 1 || limit > 200)
    throw bad('limit must be an integer between 1 and 200.');
  if (options.kind != null && !['leave', 'locator'].includes(options.kind)) throw bad('Invalid inbox kind.');
  if (options.requestId != null && (!options.kind || !UUID.test(options.requestId))) throw bad('Invalid inbox request.');
  let cursor = null;
  if (options.cursor != null) {
    try {
      if (typeof options.cursor !== 'string' || options.cursor.length > 1024 || !options.kind) throw Error();
      cursor = JSON.parse(Buffer.from(options.cursor, 'base64url').toString('utf8'));
      if (cursor.v !== 1 || cursor.kind !== options.kind || cursor.history !== !!options.includeHistory ||
          ![0, 1].includes(cursor.rank) || !UUID.test(cursor.id) ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z$/.test(cursor.created_at) ||
          !Number.isFinite(Date.parse(cursor.created_at))) throw Error();
    } catch (_) { throw bad('Invalid inbox cursor. Refresh the queue.'); }
  }
  return {paginated: true, limit, cursor, requestId: options.requestId, kinds: options.kind ? [options.kind] : ['leave', 'locator']};
}
function rowKey(row) {
  return {rank: ['pending_hr', 'pending_mayor'].includes(row.status) ? 0 : 1,
    created_at: row.inbox_created_at || new Date(row.created_at).toISOString(), id: row.id};
}
function cursorFor(row, kind, history) {
  return Buffer.from(JSON.stringify({v: 1, kind, history, ...rowKey(row)})).toString('base64url');
}
// Queries are reused only during this inbox read. No cross-request permission cache.
function memoizedReads(db) {
  const pending = new Map();
  return {query(sql, params = []) {
    const text = typeof sql === 'string' ? sql : sql.text;
    if (!/^\s*SELECT\b/i.test(text) || /FOR\s+(?:NO\s+KEY\s+)?UPDATE|FOR\s+(?:KEY\s+)?SHARE/i.test(text) ||
        /\bFROM\s+(?:leave_requests|locator_slips)\s+r\b/i.test(text)) return db.query(sql, params);
    const key = JSON.stringify([sql, params]);
    if (!pending.has(key)) pending.set(key, Promise.resolve().then(() => db.query(sql, params)));
    return pending.get(key);
  }};
}
async function* candidates(db, sql, userId, paging) {
  if (paging.requestId) {
    yield* (await db.query(`${sql} AND r.id=$2::uuid LIMIT 1`, [userId, paging.requestId])).rows;
    return;
  }
  if (!paging.paginated) {
    yield* (await db.query(`${sql} ORDER BY r.created_at DESC,r.id`, [userId])).rows;
    return;
  }
  let after = paging.cursor;
  while (true) {
    const seek = after ? `AND (${rankSql}>$2::int OR (${rankSql}=$2::int AND
      (r.created_at,r.id)<($3::timestamptz,$4::uuid)))` : '';
    const params = after ? [userId, after.rank, after.created_at, after.id] : [userId];
    const result = await db.query(`${sql} ${seek}
      ORDER BY ${rankSql},r.created_at DESC,r.id DESC LIMIT 100`, params);
    yield* result.rows;
    if (result.rows.length < 100) return;
    after = rowKey(result.rows.at(-1));
  }
}
module.exports = {optionsFor, cursorFor, memoizedReads, candidates};
