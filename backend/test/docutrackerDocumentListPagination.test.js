const test = require('node:test');
const assert = require('node:assert/strict');

const { listDocuments } = require('../src/services/docutrackerWorkflowService');

const ENG = '00000000-0000-4000-8000-00000000e000';
const FIN = '00000000-0000-4000-8000-00000000f000';
const CREATOR = { id: '00000000-0000-4000-8000-000000000c01', role: 'hr' };
const ENG_EMPLOYEE = { id: '00000000-0000-4000-8000-000000000e01', role: 'employee' };
const ENG_HEAD = { id: '00000000-0000-4000-8000-000000000e02', role: 'supervisor' };
const ENG_DENIED = { id: '00000000-0000-4000-8000-000000000e03', role: 'employee' };
const FIN_EMPLOYEE = { id: '00000000-0000-4000-8000-000000000f01', role: 'employee' };
const ADMIN = { id: '00000000-0000-4000-8000-000000000a01', role: 'admin' };

const DEPARTMENTS = {
  [ENG_EMPLOYEE.id]: [ENG],
  [ENG_HEAD.id]: [ENG],
  [ENG_DENIED.id]: [ENG],
  [FIN_EMPLOYEE.id]: [FIN],
};

// Role-level view denies (as configured on dev) must not hide released documents.
const PERMISSIONS = [
  { user_id: null, role_id: 'employee', document_type: '*', action: 'view', granted: false },
  { user_id: null, role_id: 'supervisor', document_type: '*', action: 'view', granted: false },
  { user_id: null, role_id: 'hr', document_type: '*', action: 'view', granted: false },
  { user_id: null, role_id: 'hr', document_type: 'memo', action: 'release', granted: true },
  { user_id: ENG_DENIED.id, role_id: null, document_type: 'memo', action: 'view', granted: false },
];

let clock = Date.parse('2026-10-09T08:00:00Z');
function doc(id, overrides = {}) {
  clock -= 60_000;
  return {
    id,
    document_type: 'memo',
    title: `Memo ${id}`,
    description: null,
    status: 'approved',
    created_by: CREATOR.id,
    current_holder_id: null,
    current_step: null,
    sent_time: '2026-10-01T00:00:00Z',
    source_module: null,
    originating_department_id: null,
    release_required: true,
    released_at: null,
    released_to_department_id: null,
    released_to_department_name: null,
    created_at: new Date(clock).toISOString(),
    ...overrides,
  };
}

function released(id, departmentId, overrides = {}) {
  return doc(id, {
    released_at: '2026-10-05T07:42:00Z',
    released_to_department_id: departmentId,
    released_to_department_name: departmentId === ENG ? 'Engineering' : 'Finance',
    ...overrides,
  });
}

/** Newest first: 120 documents ENG cannot see, then the ones it can. */
function buildDocuments() {
  clock = Date.parse('2026-10-09T08:00:00Z');
  const documents = [];
  for (let n = 0; n < 120; n += 1) {
    documents.push(
      n % 2 === 0
        ? released(`fin-${n}`, FIN)
        : doc(`awaiting-${n}`)
    );
  }
  documents.push(doc('own-draft', { created_by: ENG_EMPLOYEE.id, status: 'draft', release_required: false }));
  documents.push(released('eng-old-1', ENG, { title: 'Road clearing order' }));
  documents.push(doc('history-1', { release_required: false }));
  documents.push(released('eng-old-2', ENG));
  documents.push(doc('pr-denied-own', {
    document_type: 'purchaseRequest',
    created_by: ENG_DENIED.id,
    release_required: false,
  }));
  documents.push(released('dtr-source', ENG, { source_module: 'dtr', release_required: false }));
  return documents;
}

const HISTORY_ACTORS = { 'history-1': [ENG_EMPLOYEE.id] };

function createListPool(documents) {
  const listQueries = [];
  async function query(sql, params = []) {
    if (sql.includes('FROM docutracker_permissions') && sql.includes('user_id::text AS user_id')) {
      const [actions] = params;
      const [documentType, userId, roleIds] =
        params.length === 4 ? params.slice(1) : [null, ...params.slice(1)];
      return {
        rows: PERMISSIONS.filter(
          (row) =>
            actions.includes(row.action) &&
            (documentType == null || row.document_type === documentType || row.document_type === '*') &&
            (row.user_id === userId || (row.user_id == null && roleIds.includes(row.role_id)))
        ),
      };
    }
    if (sql.includes('FROM assignments a')) {
      return { rows: (DEPARTMENTS[params[0]] || []).map((department_id) => ({ department_id })) };
    }
    if (sql.includes('department_reviewer_backups')) return { rows: [] };
    if (sql.includes('FROM docutracker_documents d') && sql.includes('LIMIT')) {
      listQueries.push({ sql, params });
      return { rows: evaluateListQuery(documents, sql, params) };
    }
    if (sql.includes('FROM docutracker_document_history') && sql.includes('actor_id = $1')) {
      const [uid, ids] = params;
      return {
        rows: ids
          .filter((id) => (HISTORY_ACTORS[id] || []).includes(uid))
          .map((id) => ({ id })),
      };
    }
    if (
      sql.includes('docutracker_routing_record_assignees') ||
      sql.includes('FROM docutracker_signature_fields')
    ) {
      return { rows: [] };
    }
    // Source-backed modules (L&D, DTR, RSP...) contribute nothing here.
    return { rows: [] };
  }
  return { pool: { query }, listQueries };
}

/** Mirrors the SQL the list query sends: filters, visibility predicate, paging. */
function evaluateListQuery(documents, sql, params) {
  const at = (pattern) => {
    const match = sql.match(pattern);
    return match ? params[Number(match[1]) - 1] : undefined;
  };
  const type = at(/d\.document_type = \$(\d+)/);
  const status = at(/d\.status = \$(\d+)/);
  const q = at(/d\.title ILIKE \$(\d+)/);
  const [, limitIndex, offsetIndex] = sql.match(/LIMIT \$(\d+) OFFSET \$(\d+)/);
  const limit = params[Number(limitIndex) - 1];
  const offset = params[Number(offsetIndex) - 1];

  const visibilityStart = sql.match(/d\.created_by = \$(\d+)::uuid/);
  let visible = () => true;
  if (visibilityStart) {
    const [
      uid, explicit, deniedAllowed, deniedUnlisted,
      releaseAllowed, releaseUnlisted, userDepartments, reviewedDepartments,
    ] = params.slice(Number(visibilityStart[1]) - 1);
    const typeIn = (row, allowed, unlisted) =>
      allowed.includes(row.document_type) || (unlisted && !explicit.includes(row.document_type));
    visible = (row) =>
      !typeIn(row, deniedAllowed, deniedUnlisted) &&
      (row.created_by === uid ||
        row.current_holder_id === uid ||
        (HISTORY_ACTORS[row.id] || []).includes(uid) ||
        (row.release_required === true &&
          !row.source_module &&
          row.status === 'approved' &&
          (typeIn(row, releaseAllowed, releaseUnlisted) ||
            (row.released_at != null &&
              userDepartments.includes(row.released_to_department_id)))) ||
        (row.originating_department_id != null &&
          reviewedDepartments.includes(row.originating_department_id) &&
          row.status !== 'draft'));
  }

  return documents
    .filter((row) => type == null || row.document_type === type)
    .filter((row) => status == null || row.status === status)
    .filter((row) => q == null || row.title.toLowerCase().includes(q.replaceAll('%', '').toLowerCase()))
    .filter(visible)
    .sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))
    .slice(offset, offset + limit);
}

async function page(pool, user, filters) {
  const { documents } = await listDocuments(pool, user, filters);
  return documents.map((row) => row.id);
}

test('older released documents are listed even behind many invisible newer ones', async () => {
  const { pool, listQueries } = createListPool(buildDocuments());

  const first = await page(pool, ENG_EMPLOYEE, { limit: 2, offset: 0 });
  const second = await page(pool, ENG_EMPLOYEE, { limit: 2, offset: 2 });
  const third = await page(pool, ENG_EMPLOYEE, { limit: 2, offset: 4 });

  assert.deepEqual(first, ['own-draft', 'eng-old-1']);
  assert.deepEqual(second, ['history-1', 'eng-old-2']);
  assert.deepEqual(third, []);
  assert.equal(new Set([...first, ...second]).size, 4, 'no duplicates across pages');
  // Visibility is applied in SQL, so the page window is never consumed by invisible rows.
  assert.match(listQueries[0].sql, /d\.released_to_department_id::text = ANY/);
});

test('recipients see release flags; unrelated departments and sources stay hidden', async () => {
  const { pool } = createListPool(buildDocuments());

  const { documents } = await listDocuments(pool, ENG_HEAD, { limit: 50 });
  assert.deepEqual(documents.map((row) => row.id), ['eng-old-1', 'eng-old-2']);
  assert.ok(documents.every((row) => row.viewer_release_access === true));
  assert.ok(documents.every((row) => row.released_to_department_name === 'Engineering'));

  const finance = await page(pool, FIN_EMPLOYEE, { limit: 200 });
  assert.equal(finance.length, 60);
  assert.ok(finance.every((id) => id.startsWith('fin-')));
});

test('a user-specific view deny still wins over department release visibility', async () => {
  const { pool } = createListPool(buildDocuments());
  assert.deepEqual(await page(pool, ENG_DENIED, { limit: 50 }), ['pr-denied-own']);
});

test('search, status and type filters page over the visible result set', async () => {
  const { pool } = createListPool(buildDocuments());

  assert.deepEqual(await page(pool, ENG_EMPLOYEE, { q: 'road clearing', limit: 1 }), ['eng-old-1']);
  assert.deepEqual(
    await page(pool, ENG_EMPLOYEE, { status: 'approved', limit: 1, offset: 1 }),
    ['history-1']
  );
  assert.deepEqual(await page(pool, ENG_EMPLOYEE, { type: 'purchaseRequest', limit: 10 }), []);
});

test('authorized releasers keep seeing awaiting-release documents across pages', async () => {
  const { pool } = createListPool(buildDocuments());
  const first = await page(pool, CREATOR, { limit: 100, offset: 0 });
  const second = await page(pool, CREATOR, { limit: 100, offset: 100 });
  // 120 + 4 documents created by this HR user, who may also release memos.
  assert.equal(first.length, 100);
  assert.equal(second.length, 24);
  assert.equal(new Set([...first, ...second]).size, 124);
  assert.ok(second.includes('eng-old-2'));
});

test('admin pages are contiguous (no double offset when merging sources)', async () => {
  const documents = buildDocuments();
  const { pool, listQueries } = createListPool(documents);
  const second = await page(pool, ADMIN, { limit: 5, offset: 5 });
  const expected = [...documents]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .slice(5, 10)
    .map((row) => row.id);
  assert.deepEqual(second, expected);
  assert.doesNotMatch(listQueries[0].sql, /d\.created_by = \$/);
});

test('offsets beyond the supported range are rejected, not clamped', async () => {
  const { pool, listQueries } = createListPool(buildDocuments());
  await assert.rejects(
    listDocuments(pool, ENG_EMPLOYEE, { limit: 200, offset: 10_001 }),
    (error) => error.code === 'VALIDATION' && /offset must be at most 10000/.test(error.message)
  );
  assert.equal(listQueries.length, 0);

  await listDocuments(pool, ENG_EMPLOYEE, { limit: 200, offset: 10_000 });
  const { sql, params } = listQueries[0];
  const [, limitIndex] = sql.match(/LIMIT \$(\d+)/);
  assert.equal(params[Number(limitIndex) - 1], 10_200);
});
