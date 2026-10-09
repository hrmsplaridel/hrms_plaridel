const test = require('node:test');
const assert = require('node:assert/strict');
const {
  canUserPerformDocumentAction,
  canUserPerformTypeAction,
  filterDocumentsViewableByUser,
  getEffectivePermissionExplanation,
  transitionDocument,
  describeViewerReleaseAccess,
} = require('../src/services/docutrackerWorkflowService');
const {
  getReleaseOptions,
  releaseDocument,
} = require('../src/services/docutrackerReleaseService');

const DEPT_HR = '11111111-1111-4111-8111-111111111111';
const DEPT_ENG = '22222222-2222-4222-8222-222222222222';
const DEPT_FIN = '33333333-3333-4333-8333-333333333333';
const DEPT_INACTIVE = '44444444-4444-4444-8444-444444444444';

const USERS = {
  staff: { id: 'a0000000-0000-4000-8000-000000000001', role: 'employee', full_name: 'Mayor Office Staff', dept: DEPT_HR },
  hr: { id: 'a0000000-0000-4000-8000-000000000002', role: 'hr', full_name: 'Maria Santos', dept: DEPT_HR },
  engEmployee: { id: 'a0000000-0000-4000-8000-000000000003', role: 'employee', full_name: 'Eng Employee', dept: DEPT_ENG },
  engHead: { id: 'a0000000-0000-4000-8000-000000000004', role: 'supervisor', full_name: 'Eng Head', dept: DEPT_ENG },
  engBlocked: { id: 'a0000000-0000-4000-8000-000000000005', role: 'employee', full_name: 'Eng Blocked', dept: DEPT_ENG },
  finEmployee: { id: 'a0000000-0000-4000-8000-000000000006', role: 'employee', full_name: 'Fin Employee', dept: DEPT_FIN },
  admin: { id: 'a0000000-0000-4000-8000-000000000007', role: 'admin', full_name: 'Admin', dept: null },
};

const asUser = (u) => ({ id: u.id, role: u.role });

const DEPARTMENTS = {
  [DEPT_HR]: { name: 'Human Resources', is_active: true },
  [DEPT_ENG]: { name: 'Engineering', is_active: true },
  [DEPT_FIN]: { name: 'Finance', is_active: true },
  [DEPT_INACTIVE]: { name: 'Old Office', is_active: false },
};

function basePermissions() {
  return [
    { user_id: null, role_id: 'employee', document_type: '*', action: 'view', granted: true },
    { user_id: null, role_id: 'supervisor', document_type: '*', action: 'view', granted: true },
    { user_id: null, role_id: 'hr', document_type: '*', action: 'view', granted: true },
    { user_id: null, role_id: 'admin', document_type: '*', action: 'view', granted: true },
    { user_id: null, role_id: 'hr', document_type: 'memo', action: 'release', granted: true },
    { user_id: USERS.engBlocked.id, role_id: null, document_type: 'memo', action: 'view', granted: false },
  ];
}

function memoDoc(overrides = {}) {
  return {
    id: 'd0000000-0000-4000-8000-000000000001',
    document_type: 'memo',
    title: 'Office Memo 12',
    status: 'approved',
    current_step: 3,
    workflow_version: 1,
    created_by: USERS.staff.id,
    current_holder_id: null,
    originating_department_id: DEPT_HR,
    source_module: null,
    release_required: true,
    released_at: null,
    released_to_department_id: null,
    released_to_department_name: null,
    released_by: null,
    released_by_name: null,
    release_remarks: null,
    ...overrides,
  };
}

/** Stateful fake of the tables the release feature touches. Never a real DB. */
function createReleaseDb({ docs = [memoDoc()], permissions = basePermissions() } = {}) {
  const state = {
    docs: new Map(docs.map((d) => [d.id, { ...d }])),
    permissions,
    history: [],
    notifications: [],
    transitionRequests: [],
    calls: [],
  };
  const userList = Object.values(USERS);

  function permissionRows(actions, { documentType = null, userIds = [], roleIds = [] }) {
    return state.permissions
      .filter((row) => actions.includes(row.action))
      .filter((row) => !documentType || row.document_type === documentType || row.document_type === '*')
      .filter((row) => (row.user_id && userIds.includes(row.user_id)) || (row.role_id && roleIds.includes(row.role_id)))
      .map((row) => ({ ...row }));
  }

  async function query(sql, params = []) {
    state.calls.push({ sql, params });
    const text = String(sql);
    if (/^\s*(BEGIN|COMMIT|ROLLBACK)/.test(text)) return { rowCount: 0, rows: [] };

    if (text.includes('FROM docutracker_documents WHERE id = $1')) {
      const doc = state.docs.get(params[0]);
      return doc ? { rowCount: 1, rows: [{ ...doc }] } : { rowCount: 0, rows: [] };
    }
    if (text.includes('FROM docutracker_permissions')) {
      if (text.includes("action = 'view'")) {
        const rows = permissionRows(['view'], { documentType: params[0], userIds: params[1], roleIds: params[2] });
        return { rowCount: rows.length, rows };
      }
      if (text.includes('(document_type = $2 OR document_type')) {
        const rows = permissionRows(params[0], { documentType: params[1], userIds: [params[2]], roleIds: params[3] });
        return { rowCount: rows.length, rows };
      }
      const rows = permissionRows(params[0], { userIds: [params[1]], roleIds: params[2] });
      return { rowCount: rows.length, rows };
    }
    if (text.includes('position_department_head_periods')) return { rowCount: 0, rows: [] };
    if (text.includes('FROM assignments a') && text.includes('JOIN users u')) {
      const rows = userList
        .filter((u) => u.dept === params[0])
        .map((u) => ({ user_id: u.id, role: u.role }));
      return { rowCount: rows.length, rows };
    }
    if (text.includes('FROM assignments a') && text.includes('a.employee_id = $1')) {
      const user = userList.find((u) => u.id === params[0]);
      const rows = user?.dept ? [{ department_id: user.dept }] : [];
      return { rowCount: rows.length, rows };
    }
    if (text.includes('FROM departments d') && text.includes('ORDER BY d.name')) {
      const rows = Object.entries(DEPARTMENTS)
        .filter(([, d]) => d.is_active)
        .map(([id, d]) => ({ id, name: d.name }));
      return { rowCount: rows.length, rows };
    }
    if (text.includes('FROM departments') && text.includes('WHERE id = $1::uuid')) {
      const dept = DEPARTMENTS[params[0]];
      return dept?.is_active
        ? { rowCount: 1, rows: [{ id: params[0], name: dept.name }] }
        : { rowCount: 0, rows: [] };
    }
    if (text.includes('SELECT full_name FROM users')) {
      const user = userList.find((u) => u.id === params[0]);
      return { rowCount: user ? 1 : 0, rows: user ? [{ full_name: user.full_name }] : [] };
    }
    if (text.includes('UPDATE docutracker_documents') && text.includes('released_to_department_id = $2')) {
      const doc = state.docs.get(params[0]);
      if (!doc || doc.released_at || doc.release_required !== true || doc.status !== 'approved') {
        return { rowCount: 0, rows: [] };
      }
      Object.assign(doc, {
        released_to_department_id: params[1],
        released_to_department_name: params[2],
        released_by: params[3],
        released_by_name: params[4],
        released_at: '2026-10-09T07:42:00.000Z',
        release_remarks: params[5],
      });
      return { rowCount: 1, rows: [{ ...doc }] };
    }
    if (text.includes('INSERT INTO docutracker_document_history')) {
      state.history.push({
        document_id: params[0],
        action: 'released',
        actor_id: params[1],
        actor_name: params[2],
        remarks: params[4],
        metadata: JSON.parse(params[5]),
      });
      return { rowCount: 1, rows: [] };
    }
    if (text.includes('INSERT INTO docutracker_notifications')) {
      let inserted = 0;
      for (const userId of params[4]) {
        const exists = state.notifications.some(
          (n) => n.document_id === params[0] && n.user_id === userId && n.type === 'released' && n.event_key === params[1]
        );
        if (exists) continue;
        state.notifications.push({ document_id: params[0], user_id: userId, type: 'released', event_key: params[1], title: params[2], body: params[3] });
        inserted += 1;
      }
      return { rowCount: inserted, rows: [] };
    }
    if (text.includes('FROM docutracker_transition_requests')) {
      const rows = state.transitionRequests.filter(
        (r) => r.document_id === params[0] && r.action === params[1] && r.idempotency_key === params[2]
      );
      return { rowCount: rows.length, rows };
    }
    if (text.includes('INSERT INTO docutracker_transition_requests')) {
      state.transitionRequests.push({
        document_id: params[0],
        action: params[1],
        idempotency_key: params[2],
        actor_id: params[3],
        response_payload: JSON.parse(params[4]),
      });
      return { rowCount: 1, rows: [] };
    }
    return { rowCount: 0, rows: [] };
  }

  const client = { query, release: () => {} };
  return { state, pool: { query, connect: async () => client } };
}

const docId = memoDoc().id;
const viewDoc = (db, user, id = docId) =>
  canUserPerformDocumentAction(db.pool, { user: asUser(user), document: db.state.docs.get(id), action: 'view' });

test('before release only the workflow participants and authorized releasers can view', async () => {
  const db = createReleaseDb();
  assert.equal(await viewDoc(db, USERS.staff), true, 'creator');
  assert.equal(await viewDoc(db, USERS.hr), true, 'authorized releaser');
  assert.equal(await viewDoc(db, USERS.admin), true, 'admin keeps existing access');
  for (const user of [USERS.engEmployee, USERS.engHead, USERS.finEmployee]) {
    assert.equal(await viewDoc(db, user), false, `${user.full_name} must not see it before release`);
  }
  const listed = await filterDocumentsViewableByUser(db.pool, asUser(USERS.engEmployee), [db.state.docs.get(docId)]);
  assert.deepEqual(listed, []);
});

test('release authority comes from the release permission, with no admin bypass', async () => {
  const db = createReleaseDb();
  const doc = db.state.docs.get(docId);
  const can = (user) => canUserPerformDocumentAction(db.pool, { user: asUser(user), document: doc, action: 'release' });
  assert.equal(await can(USERS.hr), true);
  for (const user of [USERS.admin, USERS.staff, USERS.engHead, USERS.engEmployee]) {
    assert.equal(await can(user), false, `${user.full_name} cannot release`);
  }
  assert.equal(
    await canUserPerformTypeAction(db.pool, { user: asUser(USERS.admin), documentType: 'memo', action: 'release' }),
    false
  );
  assert.equal(
    await canUserPerformTypeAction(db.pool, { user: asUser(USERS.hr), documentType: 'purchaseRequest', action: 'release' }),
    false
  );
  const adminExplain = await getEffectivePermissionExplanation(db.pool, {
    user: asUser(USERS.admin),
    action: 'release',
    documentType: 'memo',
    document: doc,
  });
  assert.equal(adminExplain.final_decision, false);
  assert.equal(adminExplain.reason, 'release_permission_required');

  await assert.rejects(
    () => releaseDocument(db.pool, asUser(USERS.admin), docId, { department_id: DEPT_ENG }),
    (err) => err.code === 'FORBIDDEN'
  );
  await assert.rejects(
    () => releaseDocument(db.pool, asUser(USERS.engEmployee), docId, { department_id: DEPT_ENG }),
    (err) => err.code === 'FORBIDDEN'
  );
  assert.equal(db.state.docs.get(docId).released_at, null);
  assert.equal(db.state.history.length, 0);

  const granted = createReleaseDb({
    permissions: [
      ...basePermissions(),
      { user_id: USERS.admin.id, role_id: null, document_type: 'memo', action: 'release', granted: true },
    ],
  });
  assert.equal(
    await canUserPerformDocumentAction(granted.pool, {
      user: asUser(USERS.admin),
      document: granted.state.docs.get(docId),
      action: 'release',
    }),
    true,
    'an explicit employee exception lets an admin release'
  );
});

test('a document cannot be released before final approval', async () => {
  const db = createReleaseDb({
    docs: [memoDoc({ status: 'in_review', created_by: USERS.hr.id, current_holder_id: USERS.staff.id })],
  });
  await assert.rejects(
    () => releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG }),
    (err) => err.code === 'CONFLICT' && /after final approval/.test(err.message)
  );
  assert.equal(db.state.history.length, 0);
});

test('releasing stores the recipient, history and notifications atomically', async () => {
  const db = createReleaseDb();
  const result = await releaseDocument(db.pool, asUser(USERS.hr), docId, {
    department_id: DEPT_ENG,
    remarks: '  For posting on the bulletin board.  ',
  });
  assert.equal(result.already_released, false);
  assert.equal(result.document.status, 'approved');
  assert.equal(result.document.released_to_department_id, DEPT_ENG);
  assert.equal(result.document.released_to_department_name, 'Engineering');
  assert.equal(result.document.released_by, USERS.hr.id);
  assert.equal(result.document.released_by_name, 'Maria Santos');
  assert.equal(result.document.release_remarks, 'For posting on the bulletin board.');
  assert.ok(result.document.released_at);

  assert.equal(db.state.history.length, 1);
  assert.deepEqual(db.state.history[0], {
    document_id: docId,
    action: 'released',
    actor_id: USERS.hr.id,
    actor_name: 'Maria Santos',
    remarks: 'For posting on the bulletin board.',
    metadata: { released_to_department_id: DEPT_ENG, released_to_department_name: 'Engineering' },
  });

  const notified = db.state.notifications.map((n) => n.user_id).sort();
  assert.deepEqual(notified, [USERS.engEmployee.id, USERS.engHead.id].sort());
  assert.ok(db.state.notifications.every((n) => n.type === 'released' && n.event_key === `released:doc:${docId}`));
  assert.match(db.state.notifications[0].body, /released to Engineering/);
});

test('after release the whole receiving department can view, nobody else gains access', async () => {
  const db = createReleaseDb();
  await releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG });

  assert.equal(await viewDoc(db, USERS.engEmployee), true, 'regular employee');
  assert.equal(await viewDoc(db, USERS.engHead), true, 'department head');
  assert.equal(await viewDoc(db, USERS.finEmployee), false, 'unrelated department');
  assert.equal(await viewDoc(db, USERS.engBlocked), false, 'user-specific deny wins');

  const doc = db.state.docs.get(docId);
  for (const action of ['approve', 'reject', 'return', 'forward', 'edit', 'delete', 'release']) {
    assert.equal(
      await canUserPerformDocumentAction(db.pool, { user: asUser(USERS.engHead), document: doc, action }),
      false,
      `recipient must not gain ${action}`
    );
  }

  const listed = await filterDocumentsViewableByUser(db.pool, asUser(USERS.engEmployee), [doc]);
  assert.equal(listed.length, 1);
  assert.equal(listed[0].viewer_release_access, true);
  assert.deepEqual(await filterDocumentsViewableByUser(db.pool, asUser(USERS.finEmployee), [doc]), []);
  assert.deepEqual(await filterDocumentsViewableByUser(db.pool, asUser(USERS.engBlocked), [doc]), []);

  const explanation = await getEffectivePermissionExplanation(db.pool, {
    user: asUser(USERS.engEmployee),
    action: 'view',
    documentType: 'memo',
    document: doc,
  });
  assert.equal(explanation.final_decision, true);
  assert.equal(explanation.reason, 'release_recipient');

  assert.deepEqual(
    await describeViewerReleaseAccess(db.pool, { user: asUser(USERS.engEmployee), document: doc }),
    { viewer_release_access: true, viewer_can_release: false }
  );
});

test('role-level view denies do not block recipients; user-specific denies do', async () => {
  const db = createReleaseDb({
    permissions: [
      { user_id: null, role_id: 'employee', document_type: '*', action: 'view', granted: false },
      { user_id: null, role_id: 'supervisor', document_type: '*', action: 'view', granted: false },
      { user_id: null, role_id: 'hr', document_type: '*', action: 'view', granted: false },
      { user_id: null, role_id: 'hr', document_type: 'memo', action: 'release', granted: true },
      { user_id: USERS.engBlocked.id, role_id: null, document_type: 'memo', action: 'view', granted: false },
    ],
  });
  await releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG });
  assert.equal(await viewDoc(db, USERS.engEmployee), true);
  assert.equal(await viewDoc(db, USERS.engHead), true);
  assert.equal(await viewDoc(db, USERS.engBlocked), false);
  assert.equal(await viewDoc(db, USERS.finEmployee), false);
  assert.deepEqual(
    db.state.notifications.map((n) => n.user_id).sort(),
    [USERS.engEmployee.id, USERS.engHead.id].sort()
  );
});

test('a repeated release is safe and the recipient can never be changed', async () => {
  const db = createReleaseDb();
  await releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG });
  const historyCount = db.state.history.length;
  const notificationCount = db.state.notifications.length;

  const repeat = await releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG });
  assert.equal(repeat.already_released, true);
  assert.equal(repeat.document.released_to_department_id, DEPT_ENG);

  await assert.rejects(
    () => releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_FIN }),
    (err) => err.code === 'CONFLICT' && /already released to Engineering/.test(err.message)
  );
  assert.equal(db.state.docs.get(docId).released_to_department_id, DEPT_ENG);
  assert.equal(db.state.history.length, historyCount);
  assert.equal(db.state.notifications.length, notificationCount);
});

test('an idempotency key replays the original release response', async () => {
  const db = createReleaseDb();
  const first = await releaseDocument(db.pool, asUser(USERS.hr), docId, {
    department_id: DEPT_ENG,
    idempotency_key: 'release-1',
  });
  const replay = await releaseDocument(db.pool, asUser(USERS.hr), docId, {
    department_id: DEPT_ENG,
    idempotency_key: 'release-1',
  });
  assert.deepEqual(replay, JSON.parse(JSON.stringify(first)));
  assert.equal(db.state.history.length, 1);
  assert.equal(db.state.notifications.length, 2);
});

test('release input is validated before anything is written', async () => {
  const db = createReleaseDb();
  for (const payload of [{}, { department_id: 'not-a-uuid' }, { department_id: DEPT_ENG, remarks: 'x'.repeat(2001) }]) {
    await assert.rejects(
      () => releaseDocument(db.pool, asUser(USERS.hr), docId, payload),
      (err) => err.code === 'VALIDATION'
    );
  }
  await assert.rejects(
    () => releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_INACTIVE }),
    (err) => err.code === 'VALIDATION' && /active department/.test(err.message)
  );
  assert.equal(db.state.docs.get(docId).released_at, null);
  assert.equal(db.state.history.length, 0);
});

test('types without release and source-module records are unchanged', async () => {
  const purchaseRequest = memoDoc({
    id: 'd0000000-0000-4000-8000-000000000002',
    document_type: 'purchaseRequest',
    release_required: false,
    created_by: USERS.hr.id,
  });
  const dtrSource = memoDoc({
    id: 'd0000000-0000-4000-8000-000000000003',
    source_module: 'dtr',
    source_table: 'leave_requests',
    release_required: false,
    created_by: USERS.hr.id,
  });
  const db = createReleaseDb({ docs: [purchaseRequest, dtrSource] });
  for (const doc of [purchaseRequest, dtrSource]) {
    await assert.rejects(
      () => releaseDocument(db.pool, asUser(USERS.hr), doc.id, { department_id: DEPT_ENG }),
      (err) => err.code === 'VALIDATION' && /does not require a release/.test(err.message)
    );
    assert.equal(await viewDoc(db, USERS.engEmployee, doc.id), false);
  }
  assert.deepEqual(
    await describeViewerReleaseAccess(db.pool, { user: asUser(USERS.hr), document: purchaseRequest }),
    { viewer_release_access: false, viewer_can_release: false }
  );
  assert.equal(db.state.history.length, 0);
});

test('release options list departments only for users who may release', async () => {
  const db = createReleaseDb();
  const forHr = await getReleaseOptions(db.pool, asUser(USERS.hr), docId);
  assert.equal(forHr.can_release, true);
  assert.equal(forHr.suggested_department_id, null);
  assert.deepEqual(
    forHr.departments.map((d) => d.name),
    ['Human Resources', 'Engineering', 'Finance']
  );

  await assert.rejects(
    () => getReleaseOptions(db.pool, asUser(USERS.engEmployee), docId),
    (err) => err.code === 'FORBIDDEN'
  );
  await releaseDocument(db.pool, asUser(USERS.hr), docId, { department_id: DEPT_ENG });
  const forRecipient = await getReleaseOptions(db.pool, asUser(USERS.engEmployee), docId);
  assert.equal(forRecipient.released, true);
  assert.equal(forRecipient.can_release, false);
  assert.deepEqual(forRecipient.departments, []);
});

function finalApprovalPool({ documentType, requiresRelease, sourceModule = null }) {
  const calls = [];
  const doc = {
    id: 'doc-final',
    title: 'Final notice',
    document_type: documentType,
    workflow_version: 1,
    status: 'in_review',
    current_step: 2,
    created_by: 'staff-1',
    current_holder_id: 'mayor-1',
    source_module: sourceModule,
    release_required: false,
  };
  const client = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
        return { rowCount: 1, rows: [{ ...doc }] };
      }
      if (sql.includes('a.allowed_actions')) {
        return {
          rowCount: 1,
          rows: [{ is_enabled: true, allowed_actions: ['approve', 'forward', 'return', 'reject'], is_primary: true }],
        };
      }
      if (sql.includes('routing_config')) {
        return {
          rowCount: 1,
          rows: [{
            document_type: documentType,
            version: 1,
            review_deadline_hours: 24,
            steps: [
              { step_order: 1, assignee_type: 'user' },
              { step_order: 2, assignee_type: 'user' },
            ],
          }],
        };
      }
      if (sql.includes("LOWER(COALESCE(u.role, '')) = 'mayor'")) {
        return { rowCount: 1, rows: [{ employee_id: 'mayor-1', name: 'Mayor' }] };
      }
      if (sql.includes('FROM docutracker_signature_fields') && sql.includes('signed_by')) {
        return { rowCount: 1, rows: [{ '?column?': 1 }] };
      }
      if (sql.includes('FROM docutracker_document_types')) {
        return { rowCount: 1, rows: [{ requires_release: requiresRelease }] };
      }
      if (sql.includes('SET release_required = true')) {
        return { rowCount: 1, rows: [{ ...doc, status: 'approved', current_holder_id: null, release_required: true }] };
      }
      if (sql.includes('UPDATE docutracker_documents')) {
        return { rowCount: 1, rows: [{ ...doc, status: 'approved', current_holder_id: null }] };
      }
      return { rowCount: 0, rows: [] };
    },
    release: () => {},
  };
  return { calls, pool: { connect: async () => client } };
}

test('final approval snapshots release_required from the document type policy', async () => {
  const mayor = { id: 'mayor-1', role: 'mayor' };

  const memoRun = finalApprovalPool({ documentType: 'memo', requiresRelease: true });
  const memo = await transitionDocument(memoRun.pool, mayor, 'doc-final', 'approve', {});
  assert.equal(memo.status, 'approved');
  assert.equal(memo.release_required, true);
  assert.equal(memo.released_at, null);

  const prRun = finalApprovalPool({ documentType: 'purchaseRequest', requiresRelease: false });
  const pr = await transitionDocument(prRun.pool, mayor, 'doc-final', 'approve', {});
  assert.equal(pr.status, 'approved');
  assert.equal(pr.release_required, false);
  assert.equal(prRun.calls.some((c) => c.sql.includes('SET release_required = true')), false);

  const sourceRun = finalApprovalPool({ documentType: 'memo', requiresRelease: true, sourceModule: 'rsp' });
  const source = await transitionDocument(sourceRun.pool, mayor, 'doc-final', 'approve', {});
  assert.equal(source.release_required, false);
  assert.equal(sourceRun.calls.some((c) => c.sql.includes('FROM docutracker_document_types')), false);
});
