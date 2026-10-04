const test = require('node:test');
const assert = require('node:assert/strict');
const {
  VALID_STATUSES,
  mapDocumentRow,
  sourceActionForRow,
  mapSourceStatusToDocuTracker,
  ensureValidWorkflowConfig,
  permissionPriority,
  resolvePermissionDecisionFromRows,
  hasPermission,
  canUserPerformDocumentAction,
  filterDocumentsViewableByUser,
  transitionDocument,
  insertNotificationIfNotRecent,
  getEffectivePermissionExplanation,
  recoverDocumentAssignment,
  listDocuments,
  canUserPerformTypeAction,
} = require('../src/services/docutrackerWorkflowService');
const {
  GENERAL_PERMISSION_ACTIONS,
  SYSTEM_ACCESS_ACTIONS,
} = require('../src/services/docutrackerSystemAccessActions');

function permissionRowsClient(rowsByAction) {
  return {
    query: async (sql, params = []) => {
      if (!sql.includes('FROM docutracker_permissions')) return { rowCount: 0, rows: [] };
      const rows = params[0].flatMap((action) => rowsByAction[action] || []);
      return { rowCount: rows.length, rows };
    },
  };
}

test('System Access actions are shared and exclude workflow-step actions', () => {
  assert.deepEqual([...SYSTEM_ACCESS_ACTIONS].sort(), ['create_draft', 'download', 'submit', 'view']);
  assert.equal(GENERAL_PERMISSION_ACTIONS.has('create'), true);
  for (const action of ['approve', 'forward', 'reject', 'return']) {
    assert.equal(GENERAL_PERMISSION_ACTIONS.has(action), false);
  }
});

test('canUserPerformTypeAction honours submit grants like other System Access actions', async () => {
  const user = { id: 'u-pr-clerk', role: 'employee' };
  const roleDenied = permissionRowsClient({
    submit: [{ user_id: null, role_id: 'employee', document_type: 'purchaseRequest', granted: false }],
  });
  assert.equal(
    await canUserPerformTypeAction(roleDenied, { user, documentType: 'purchaseRequest', action: 'submit' }),
    false
  );

  const userOverride = permissionRowsClient({
    submit: [
      { user_id: null, role_id: 'employee', document_type: 'purchaseRequest', granted: false },
      { user_id: 'u-pr-clerk', role_id: null, document_type: 'purchaseRequest', granted: true },
    ],
  });
  assert.equal(
    await canUserPerformTypeAction(userOverride, { user, documentType: 'purchaseRequest', action: 'submit' }),
    true
  );

  assert.equal(
    await canUserPerformTypeAction(permissionRowsClient({}), { user, documentType: 'purchaseRequest', action: 'submit' }),
    false
  );
});

test('canUserPerformTypeAction never grants workflow-step actions from permission rows', async () => {
  const client = permissionRowsClient({
    approve: [{ user_id: 'u-1', role_id: null, document_type: '*', granted: true }],
  });
  assert.equal(
    await canUserPerformTypeAction(client, {
      user: { id: 'u-1', role: 'employee' },
      documentType: 'memo',
      action: 'approve',
    }),
    false
  );
});

test('VALID_STATUSES includes workflow statuses', () => {
  const expected = [
    'pending',
    'in_review',
    'approved',
    'rejected',
    'returned',
    'forwarded',
    'overdue',
    'escalated',
    'cancelled',
  ];
  for (const status of expected) {
    assert.equal(VALID_STATUSES.has(status), true);
  }
});

test('mapDocumentRow normalizes inReview status', () => {
  const row = {
    id: '1',
    document_type: 'memo',
    title: 'Memo',
    status: 'inReview',
    current_step: 1,
  };
  const mapped = mapDocumentRow(row);
  assert.equal(mapped.status, 'in_review');
});

test('sourceActionForRow exposes only the viewer current DTR leave action', () => {
  const base = {
    source_module: 'dtr',
    source_table: 'leave_requests',
    source_owner_id: 'employee-1',
    assigned_department_head_id: 'head-1',
    viewer_is_department_reviewer: false,
  };

  assert.deepEqual(
    sourceActionForRow(
      { ...base, source_status: 'draft' },
      { id: 'employee-1', role: 'employee' }
    ),
    { action: 'complete_in_dtr', label: 'Complete and submit in DTR' }
  );
  assert.deepEqual(
    sourceActionForRow(
      { ...base, source_status: 'pending_department_head' },
      { id: 'head-1', role: 'employee' }
    ),
    {
      action: 'department_review_in_dtr',
      label: 'Sign here, then review in DTR',
    }
  );
  assert.deepEqual(
    sourceActionForRow(
      { ...base, source_status: 'pending_hr' },
      { id: 'hr-1', role: 'hr' }
    ),
    { action: 'hr_review_in_dtr', label: 'Sign here, then review in DTR' }
  );
  assert.equal(
    sourceActionForRow(
      { ...base, source_status: 'pending_department_head' },
      { id: 'previous-reviewer', role: 'employee' }
    ),
    null
  );
  assert.equal(
    sourceActionForRow(
      { ...base, source_status: 'approved' },
      { id: 'admin-1', role: 'admin' }
    ),
    null
  );
});

test('sourceActionForRow points RSP/L&D admins to the owning module step', () => {
  const admin = { id: 'admin-1', role: 'admin' };
  const rsp = { source_module: 'rsp', source_table: 'recruitment_applications' };
  assert.deepEqual(sourceActionForRow({ ...rsp, source_status: 'submitted' }, admin), {
    action: 'review_documents_in_rsp',
    label: 'Review applicant documents in RSP',
  });
  assert.equal(
    sourceActionForRow({ ...rsp, source_status: 'exam_taken' }, admin).action,
    'grade_exam_in_rsp'
  );
  assert.equal(
    sourceActionForRow({ ...rsp, source_status: 'passed' }, admin).action,
    'continue_hiring_in_rsp'
  );
  for (const status of ['document_declined', 'document_approved', 'failed', 'registered']) {
    assert.equal(sourceActionForRow({ ...rsp, source_status: status }, admin), null);
  }
  assert.equal(
    sourceActionForRow({ ...rsp, source_status: 'submitted' }, { id: 'hr-1', role: 'hr' }),
    null
  );

  const ld = { source_module: 'ld', source_table: 'training_daily_reports' };
  assert.deepEqual(sourceActionForRow({ ...ld, source_status: 'submitted' }, admin), {
    action: 'review_report_in_ld',
    label: 'Review training report in L&D',
  });
  assert.equal(sourceActionForRow({ ...ld, source_status: 'seen' }, admin), null);
  assert.equal(
    sourceActionForRow({ ...ld, source_status: 'submitted' }, { id: 'emp-1', role: 'employee' }),
    null
  );
});

test('RSP application statuses map to the hiring pipeline', () => {
  const expected = {
    submitted: 'pending',
    document_approved: 'in_review',
    document_declined: 'returned',
    exam_taken: 'in_review',
    passed: 'in_review',
    failed: 'rejected',
    registered: 'approved',
  };
  for (const [status, mapped] of Object.entries(expected)) {
    assert.equal(mapSourceStatusToDocuTracker('rsp', status), mapped, status);
  }
});

test('L&D daily report statuses map to the report review lifecycle', () => {
  const expected = {
    submitted: 'pending',
    seen: 'approved',
    reviewed: 'approved',
    approved: 'approved',
    needs_revision: 'returned',
  };
  for (const [status, mapped] of Object.entries(expected)) {
    assert.equal(mapSourceStatusToDocuTracker('ld', status), mapped, status);
  }
});

test('RSP source feed excludes Mayor endorsement records', async () => {
  let rspSql = '';
  const pool = {
    query: async (sql) => {
      if (sql.includes('FROM recruitment_applications a')) {
        rspSql = sql;
        return {
          rows: [{
            source_record_id: 'app-1',
            source_module: 'rsp',
            source_table: 'recruitment_applications',
            source_title: 'Administrative Aide',
            created_by: null,
            creator_name: 'Applicant One',
            created_at: '2026-09-01T00:00:00.000Z',
            source_status: 'exam_taken',
          }],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const result = await listDocuments(pool, { id: 'admin-1', role: 'admin' }, { type: 'rsp' });

  assert.match(rspSql, /LIKE '%@local\.intake'/);
  assert.match(rspSql, /a\.status NOT IN \('endorsed', 'rejected'\)/);
  const [row] = result.documents;
  assert.equal(row.status, 'in_review');
  assert.equal(row.source_status, 'exam_taken');
  assert.equal(row.source_action, 'grade_exam_in_rsp');
  assert.equal(row.source_only, true);
});

test('Approved filter keeps approved documents but not reviewed L&D reports', async () => {
  const sourceRow = (module, table, id, status) => ({
    source_record_id: id,
    source_module: module,
    source_table: table,
    source_title: id,
    created_by: null,
    creator_name: 'Someone',
    created_at: '2026-09-01T00:00:00.000Z',
    source_status: status,
  });
  const pool = {
    query: async (sql) => {
      if (sql.includes('FROM docutracker_documents d')) {
        return {
          rows: [{
            id: 'memo-1', document_type: 'memo', title: 'Memo', status: 'approved',
            created_at: '2026-09-02T00:00:00.000Z',
          }],
        };
      }
      if (sql.includes('FROM training_daily_reports r')) {
        return {
          rows: [
            sourceRow('ld', 'training_daily_reports', 'report-seen', 'seen'),
            sourceRow('ld', 'training_daily_reports', 'report-reviewed', 'reviewed'),
            sourceRow('ld', 'training_daily_reports', 'report-approved', 'approved'),
          ],
        };
      }
      if (sql.includes('FROM recruitment_applications a')) {
        return {
          rows: [sourceRow('rsp', 'recruitment_applications', 'app-hired', 'registered')],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };
  const admin = { id: 'admin-1', role: 'admin' };

  const approved = await listDocuments(pool, admin, { status: 'approved' });
  assert.deepEqual(
    approved.documents.map((d) => d.id).sort(),
    ['memo-1', 'source:ld:report-approved', 'source:rsp:app-hired']
  );

  const all = await listDocuments(pool, admin, {});
  const seen = all.documents.find((d) => d.id === 'source:ld:report-seen');
  assert.equal(seen.status, 'approved');
  assert.equal(seen.source_status, 'seen');
});

test('mapDocumentRow preserves server-owned source action metadata', () => {
  const mapped = mapDocumentRow({
    id: 'source:dtr:leave-1',
    document_type: 'dtr',
    title: 'Leave request',
    status: 'in_review',
    source_module: 'dtr',
    source_table: 'leave_requests',
    source_record_id: 'leave-1',
    source_status: 'pending_department_head',
    source_action: 'department_review_in_dtr',
    source_action_label: 'Sign here, then review in DTR',
    source_only: true,
  });

  assert.equal(mapped.source_status, 'pending_department_head');
  assert.equal(mapped.source_action, 'department_review_in_dtr');
  assert.equal(mapped.source_action_label, 'Sign here, then review in DTR');
});

test('ensureValidWorkflowConfig rejects missing config', () => {
  assert.throws(
    () => ensureValidWorkflowConfig(null, 'memo'),
    /Missing workflow config/
  );
});

test('ensureValidWorkflowConfig rejects incorrect step order', () => {
  assert.throws(
    () =>
      ensureValidWorkflowConfig(
        { steps: [{ step_order: 1 }, { step_order: 3 }] },
        'memo'
      ),
    /incorrect step order/
  );
});

test('permissionPriority favors user-specific over role and wildcard', () => {
  const ctx = { userId: 'u1', roleIds: ['hr', 'hr_staff'], documentType: 'memo' };
  const userSpecific = permissionPriority(
    { user_id: 'u1', role_id: null, document_type: 'memo' },
    ctx
  );
  const roleSpecific = permissionPriority(
    { user_id: null, role_id: 'hr', document_type: 'memo' },
    ctx
  );
  const roleWildcard = permissionPriority(
    { user_id: null, role_id: 'hr', document_type: '*' },
    ctx
  );
  assert.equal(userSpecific > roleSpecific, true);
  assert.equal(roleSpecific > roleWildcard, true);
});

test('resolvePermissionDecisionFromRows applies conflict precedence', () => {
  const rows = [
    { user_id: null, role_id: 'hr', document_type: 'memo', granted: true },
    { user_id: 'u1', role_id: null, document_type: 'memo', granted: false },
  ];
  const decision = resolvePermissionDecisionFromRows(rows, {
    userId: 'u1',
    roleIds: ['hr', 'hr_staff'],
    documentType: 'memo',
  });
  assert.equal(decision, false);
});

test('purchase request is denied to unauthorized employees despite wildcard grants', () => {
  const rows = [
    { user_id: null, role_id: 'employee', document_type: '*', granted: true },
    { user_id: null, role_id: 'employee', document_type: 'purchaseRequest', granted: false },
  ];
  const ctx = { userId: 'emp-1', roleIds: ['employee'], documentType: 'purchaseRequest' };
  assert.equal(resolvePermissionDecisionFromRows(rows, ctx), false);
  assert.equal(
    resolvePermissionDecisionFromRows(rows, { ...ctx, documentType: 'travel_order' }),
    true
  );
});

test('admin-authorized user may create and submit purchase requests', () => {
  for (const roleIds of [['employee'], ['supervisor', 'dept_head'], ['hr', 'hr_staff']]) {
    const rows = [
      { user_id: null, role_id: roleIds[0], document_type: '*', granted: true },
      { user_id: null, role_id: roleIds[0], document_type: 'purchaseRequest', granted: false },
      { user_id: 'buyer-1', role_id: null, document_type: 'purchaseRequest', granted: true },
    ];
    assert.equal(
      resolvePermissionDecisionFromRows(rows, {
        userId: 'buyer-1',
        roleIds,
        documentType: 'purchaseRequest',
      }),
      true
    );
    assert.equal(
      resolvePermissionDecisionFromRows(rows, {
        userId: 'someone-else',
        roleIds,
        documentType: 'purchaseRequest',
      }),
      false
    );
  }
});

test('permissionPriority honors role aliases via roleIds', () => {
  const ctx = { userId: 'u9', roleIds: ['hr', 'hr_staff'], documentType: 'memo' };
  const aliasSpecific = permissionPriority(
    { user_id: null, role_id: 'hr_staff', document_type: 'memo' },
    ctx
  );
  assert.equal(aliasSpecific > 0, true);
});

test('hasPermission accepts legacy create rows for create_draft checks', async () => {
  let capturedParams = null;
  const mockClient = {
    query: async (_sql, params) => {
      capturedParams = params;
      return {
        rowCount: 1,
        rows: [
          {
            user_id: null,
            role_id: 'employee',
            document_type: 'memo',
            granted: true,
          },
        ],
      };
    },
  };
  const granted = await hasPermission(mockClient, {
    role: 'employee',
    userId: 'user-1',
    documentType: 'memo',
    action: 'create_draft',
  });
  assert.equal(granted, true);
  assert.deepEqual(capturedParams?.[0], ['create_draft', 'create']);
});

function createMockPool(handler) {
  const calls = [];
  const client = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      return handler(sql, params, calls);
    },
    release: () => {},
  };
  return {
    calls,
    pool: {
      connect: async () => client,
    },
  };
}

test('transitionDocument replays previous response for same idempotency key', async () => {
  const replayPayload = {
    id: 'doc-1',
    status: 'in_review',
    current_step: 1,
  };
  const { pool, calls } = createMockPool((sql) => {
    if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
      return {
        rowCount: 1,
        rows: [
          {
            id: 'doc-1',
            document_type: 'memo',
            status: 'in_review',
            current_step: 1,
            created_by: 'creator-1',
            current_holder_id: 'holder-1',
          },
        ],
      };
    }
    if (sql.includes('FROM docutracker_transition_requests')) {
      return {
        rowCount: 1,
        rows: [{ actor_id: 'admin-1', response_payload: replayPayload }],
      };
    }
    if (sql.includes('FROM docutracker_workflow_steps s') && sql.includes('allowed_actions')) {
      return {
        rowCount: 1,
        rows: [{ is_enabled: true, allowed_actions: ['approve'], is_primary: true }],
      };
    }
    return { rowCount: 0, rows: [] };
  });

  const result = await transitionDocument(
    pool,
    { id: 'admin-1', role: 'admin' },
    'doc-1',
    'approve',
    { idempotency_key: 'idem-001' }
  );

  assert.deepEqual(result, replayPayload);
  assert.equal(
    calls.some((c) => c.sql.includes('UPDATE docutracker_documents')),
    false
  );
});

test('distinct notification event keys are not suppressed by matching content', async () => {
  const calls = [];
  const client = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (sql.includes('event_key = $4')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('INSERT INTO docutracker_notifications')) {
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('created_at >= now()')) {
        throw new Error('Explicit event keys must not use content-based deduplication');
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const inserted = await insertNotificationIfNotRecent(client, {
    document_id: 'doc-returned',
    user_id: 'reviewer-1',
    type: 'assigned',
    event_key: 'assigned:doc:doc-returned:step:2:req:resume-cycle-2',
    title: 'Document requires your review',
    body: 'The document was forwarded and requires your review.',
  });

  assert.equal(inserted, true);
  assert.equal(
    calls.some((call) => call.sql.includes('created_at >= now()')),
    false
  );
  const insert = calls.find((call) =>
    call.sql.includes('INSERT INTO docutracker_notifications')
  );
  assert.equal(insert.params[3], 'assigned:doc:doc-returned:step:2:req:resume-cycle-2');
});

test('transitionDocument enforces invalid action from status', async () => {
  const { pool } = createMockPool((sql) => {
    if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
      return {
        rowCount: 1,
        rows: [
          {
            id: 'doc-2',
            document_type: 'memo',
            status: 'pending',
            current_step: 1,
            created_by: 'creator-2',
            current_holder_id: 'holder-2',
          },
        ],
      };
    }
    return { rowCount: 0, rows: [] };
  });

  await assert.rejects(
    () =>
      transitionDocument(
        pool,
        { id: 'admin-2', role: 'admin' },
        'doc-2',
        'forward',
        {}
      ),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /forward is not allowed while the document is pending/);
      return true;
    }
  );
});

test('getEffectivePermissionExplanation shows explicit deny precedence', async () => {
  const mockClient = {
    query: async () => ({
      rowCount: 2,
      rows: [
        { user_id: null, role_id: 'hr_staff', document_type: 'memo', granted: true },
        { user_id: 'user-1', role_id: null, document_type: 'memo', granted: false },
      ],
    }),
  };

  // Use a general permission action (not approve/forward/etc.); workflow actions
  // bypass the permission table when a document is supplied.
  const result = await getEffectivePermissionExplanation(mockClient, {
    user: { id: 'user-1', role: 'hr_staff' },
    action: 'view',
    documentType: 'memo',
    document: {
      id: 'doc-3',
      document_type: 'memo',
      created_by: 'creator-3',
      current_holder_id: 'user-1',
    },
  });

  assert.equal(result.explicit_decision, false);
  assert.equal(result.fallback_decision, true);
  assert.equal(result.final_decision, false);
  assert.equal(result.reason, 'explicit_permission');
  assert.equal(result.explicit_matches.length > 0, true);
});

test('getEffectivePermissionExplanation denies assigned user when allowed_actions excludes action', async () => {
  const mockClient = {
    query: async (sql) => {
      if (sql.includes('FROM docutracker_routing_records rr') && sql.includes('routing_record_assignees')) {
        return { rowCount: 1, rows: [{ ok: 1 }] };
      }
      if (sql.includes('FROM docutracker_workflow_steps s') && sql.includes('docutracker_workflow_step_assignees')) {
        return {
          rowCount: 1,
          rows: [
            {
              is_enabled: true,
              allowed_actions: ['forward'],
              is_primary: false,
              backup_rank: 1,
            },
          ],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const result = await getEffectivePermissionExplanation(mockClient, {
    user: { id: 'backup-1', role: 'employee' },
    action: 'approve',
    documentType: 'memo',
    document: {
      id: 'doc-77',
      document_type: 'memo',
      status: 'in_review',
      current_step: 1,
      current_holder_id: 'holder-1',
      workflow_version: 2,
      created_by: 'creator-1',
    },
  });

  assert.equal(result.final_decision, false);
  assert.equal(result.reason, 'assigned_but_action_not_allowed');
});

test('transitionDocument blocks non-holder even with explicit approve grant', async () => {
  const actor = { id: 'user-actor', role: 'employee' };
  const { pool } = createMockPool((sql, params = []) => {
    if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
      return {
        rowCount: 1,
        rows: [
          {
            id: 'doc-holder',
            document_type: 'memo',
            status: 'in_review',
            current_step: 1,
            created_by: actor.id,
            current_holder_id: 'actual-holder',
          },
        ],
      };
    }
    if (sql.includes('FROM docutracker_permissions')) {
      const action = params[0];
      if (action === 'view' || action === 'approve') {
        return {
          rowCount: 1,
          rows: [
            {
              user_id: actor.id,
              role_id: null,
              document_type: 'memo',
              granted: true,
            },
          ],
        };
      }
      return { rowCount: 0, rows: [] };
    }
    if (sql.includes('FROM docutracker_routing_configs')) {
      return {
        rowCount: 1,
        rows: [
          {
            document_type: 'memo',
            review_deadline_hours: 24,
            steps: [
              { step_order: 1, user_ids: ['actual-holder'] },
              { step_order: 2, user_ids: ['next-holder'] },
            ],
          },
        ],
      };
    }
    return { rowCount: 0, rows: [] };
  });

  await assert.rejects(
    () => transitionDocument(pool, actor, 'doc-holder', 'approve', {}),
    (err) => {
      assert.equal(err.code, 'FORBIDDEN');
      assert.match(err.message, /You do not have permission to approve this document/);
      return true;
    }
  );
});

test('canUserPerformDocumentAction view denies unrelated employee despite role view *', async () => {
  const mockClient = {
    query: async (sql) => {
      if (sql.includes('FROM docutracker_permissions')) {
        return {
          rowCount: 1,
          rows: [
            {
              user_id: null,
              role_id: 'employee',
              document_type: '*',
              granted: true,
            },
          ],
        };
      }
      if (sql.includes('docutracker_routing_records')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('docutracker_document_history')) {
        return { rowCount: 0, rows: [] };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const allowed = await canUserPerformDocumentAction(mockClient, {
    user: { id: 'employee-a', role: 'employee' },
    document: {
      id: 'doc-other',
      document_type: 'memo',
      status: 'in_review',
      created_by: 'employee-b',
      current_holder_id: 'employee-b',
      current_step: 1,
    },
    action: 'view',
  });

  assert.equal(allowed, false);
});

test('canUserPerformDocumentAction view allows creator on WIP draft', async () => {
  const mockClient = { query: async () => ({ rowCount: 0, rows: [] }) };

  const allowed = await canUserPerformDocumentAction(mockClient, {
    user: { id: 'creator-1', role: 'employee' },
    document: {
      id: 'doc-draft',
      document_type: 'memo',
      status: 'pending',
      created_by: 'creator-1',
      current_holder_id: null,
      current_step: null,
      sent_time: null,
    },
    action: 'view',
  });

  assert.equal(allowed, true);
});

test('filterDocumentsViewableByUser excludes unrelated rows when role view is granted', async () => {
  const rows = [
    {
      id: 'doc-mine',
      document_type: 'memo',
      status: 'pending',
      created_by: 'user-a',
      current_holder_id: null,
      current_step: null,
      sent_time: null,
    },
    {
      id: 'doc-other',
      document_type: 'memo',
      status: 'in_review',
      created_by: 'user-b',
      current_holder_id: 'user-b',
      current_step: 1,
    },
  ];

  const pool = {
    query: async (sql, params) => {
      if (sql.includes('rr.step_order = d.current_step')) {
        return { rows: [] };
      }
      if (sql.includes('FROM docutracker_document_history')) {
        return { rows: [] };
      }
      if (sql.includes('ON rr.document_id = d.id') && !sql.includes('current_step')) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  };

  const filtered = await filterDocumentsViewableByUser(
    pool,
    { id: 'user-a', role: 'employee' },
    rows
  );

  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].id, 'doc-mine');
});

test('listDocuments returns the current holder name', async () => {
  let documentListSql = '';
  const pool = {
    query: async (sql) => {
      if (sql.includes('FROM docutracker_documents d')) {
        documentListSql = sql;
        return {
          rowCount: 1,
          rows: [{
            id: 'doc-holder-name', document_type: 'memo', title: 'Memo',
            status: 'in_review', current_holder_id: 'holder-1',
            creator_name: 'Sender Name', assignee_name: 'Department Head',
          }],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const result = await listDocuments(pool, { id: 'admin-1', role: 'admin' });

  assert.match(documentListSql, /LEFT JOIN users holder ON holder\.id = d\.current_holder_id/);
  assert.equal(result.documents[0].assignee_name, 'Department Head');
});

test('current primary and backup assignees can use a step-enabled action', async () => {
  const mockClient = {
    query: async (sql, params = []) => {
      if (sql.includes('FROM docutracker_workflow_steps s') && sql.includes('allowed_actions')) {
        const userId = params[3];
        if (userId === 'primary-1' || userId === 'backup-1') {
          return {
            rowCount: 1,
            rows: [
              {
                is_enabled: true,
                allowed_actions: ['approve', 'return'],
                is_primary: userId === 'primary-1',
                backup_rank: userId === 'backup-1' ? 1 : null,
              },
            ],
          };
        }
      }
      return { rowCount: 0, rows: [] };
    },
  };
  const document = {
    id: 'doc-current',
    document_type: 'memo',
    workflow_version: 2,
    current_step: 2,
    current_holder_id: 'primary-1',
    created_by: 'creator-1',
    status: 'in_review',
  };

  for (const id of ['primary-1', 'backup-1']) {
    const allowed = await canUserPerformDocumentAction(mockClient, {
      user: { id, role: 'employee' },
      document,
      action: 'approve',
    });
    assert.equal(allowed, true);
  }
});

test('current step assignee can resume a returned document', async () => {
  const client = {
    query: async (sql) => {
      if (sql.includes('FROM docutracker_workflow_steps s') && sql.includes('allowed_actions')) {
        return {
          rowCount: 1,
          rows: [{ is_enabled: true, allowed_actions: ['approve'], is_primary: true }],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  assert.equal(await canUserPerformDocumentAction(client, {
    user: { id: 'step-one-primary', role: 'employee' },
    action: 'approve',
    document: {
      id: 'returned-doc',
      document_type: 'memo',
      workflow_version: 3,
      current_step: 1,
      current_holder_id: 'step-one-primary',
      created_by: 'creator',
      status: 'returned',
    },
  }), true);
});

test('a returned document at step one still cannot be returned further', async () => {
  const client = { query: async () => { throw new Error('must not query'); } };
  assert.equal(await canUserPerformDocumentAction(client, {
    user: { id: 'step-one-primary', role: 'employee' },
    action: 'return',
    document: {
      id: 'returned-doc', document_type: 'memo', workflow_version: 3,
      current_step: 1, current_holder_id: 'step-one-primary',
      created_by: 'creator', status: 'returned',
    },
  }), false);
});

function createRecoveryPool({ failHistory = false } = {}) {
  const calls = [];
  const client = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return {
          rowCount: 1,
          rows: [{
            id: 'doc-recovery', document_type: 'memo', workflow_version: 2,
            current_step: 1, current_holder_id: 'old-holder', created_by: 'creator',
            status: 'returned', title: 'Returned memo',
          }],
        };
      }
      if (sql.includes('FROM users') && sql.includes('is_active')) {
        return { rowCount: 1, rows: [{ id: params[0] }] };
      }
      if (sql.includes('FROM docutracker_routing_config_versions')) {
        return {
          rowCount: 1,
          rows: [{
            document_type: 'memo', version: 2, review_deadline_hours: 24,
            steps: [{
              step_order: 1, assignee_type: 'user', assignee_source: 'specific_users',
              user_ids: ['new-holder', 'backup-holder'], allowed_actions: ['approve'],
              deadline_hours: 12, enabled: true,
            }],
          }],
        };
      }
      if (sql.includes('FROM docutracker_workflow_steps s') && sql.includes('allowed_actions')) {
        return {
          rowCount: 1,
          rows: [{ is_enabled: true, is_primary: true, allowed_actions: ['approve'] }],
        };
      }
      if (sql.includes('SELECT id') && sql.includes('FROM docutracker_routing_records')) {
        return { rowCount: 1, rows: [{ id: 'routing-1' }] };
      }
      if (sql.includes('UPDATE docutracker_documents')) {
        return {
          rowCount: 1,
          rows: [{
            id: 'doc-recovery', document_type: 'memo', workflow_version: 2,
            current_step: 1, current_holder_id: 'new-holder', status: 'returned',
            needs_admin_intervention: false,
          }],
        };
      }
      if (sql.includes('SELECT a.user_id::text AS user_id')) {
        return {
          rowCount: 2,
          rows: [{ user_id: 'new-holder' }, { user_id: 'backup-holder' }],
        };
      }
      if (failHistory && sql.includes('INSERT INTO docutracker_document_history')) {
        const error = new Error('history failed');
        error.code = '23514';
        throw error;
      }
      return { rowCount: 1, rows: [{ id: 'row-1' }] };
    },
    release: () => {},
  };
  return { pool: { connect: async () => client }, calls };
}

test('admin recovery atomically reassigns the current step without changing status', async () => {
  const { pool, calls } = createRecoveryPool();
  const result = await recoverDocumentAssignment(
    pool,
    { id: 'admin-1', role: 'admin' },
    'doc-recovery',
    { current_holder_id: 'new-holder', remarks: 'Recover overdue assignment' }
  );

  assert.equal(result.status, 'returned');
  assert.equal(result.current_holder_id, 'new-holder');
  assert.ok(calls.some((call) => call.sql.includes('UPDATE docutracker_routing_records')));
  assert.equal(
    calls.filter((call) => call.sql.includes('INSERT INTO docutracker_routing_record_assignees')).length,
    2
  );
  assert.ok(calls.some((call) =>
    call.sql.includes('INSERT INTO docutracker_document_history') && call.params[1] === 'assigned'
  ));
  assert.ok(calls.some((call) => call.sql === 'COMMIT'));
});

test('admin recovery rolls back when audit history cannot be written', async () => {
  const { pool, calls } = createRecoveryPool({ failHistory: true });
  await assert.rejects(
    () => recoverDocumentAssignment(
      pool,
      { id: 'admin-1', role: 'admin' },
      'doc-recovery',
      { current_holder_id: 'new-holder', remarks: 'Recover assignment' }
    ),
    (error) => error.code === 'DB_FAILURE'
  );
  assert.ok(calls.some((call) => call.sql === 'ROLLBACK'));
  assert.equal(calls.some((call) => call.sql === 'COMMIT'), false);
});

test('non-admin callers cannot invoke assignment recovery through the service', async () => {
  const { pool, calls } = createRecoveryPool();
  await assert.rejects(
    () => recoverDocumentAssignment(
      pool,
      { id: 'employee-1', role: 'employee' },
      'doc-recovery',
      { current_holder_id: 'new-holder', remarks: 'Unauthorized' }
    ),
    (error) => error.code === 'FORBIDDEN'
  );
  assert.ok(calls.some((call) => call.sql === 'ROLLBACK'));
  assert.equal(calls.some((call) => call.sql.includes('SELECT * FROM docutracker_documents')), false);
});

test('admin cannot perform a workflow action unless assigned to the current step', async () => {
  const mockClient = {
    query: async () => ({ rowCount: 0, rows: [] }),
  };
  const allowed = await canUserPerformDocumentAction(mockClient, {
    user: { id: 'admin-unassigned', role: 'admin' },
    document: {
      id: 'doc-secure',
      document_type: 'memo',
      workflow_version: 1,
      current_step: 2,
      current_holder_id: 'primary-2',
      created_by: 'creator-2',
      status: 'in_review',
    },
    action: 'approve',
  });

  assert.equal(allowed, false);
});

test('permission explanation denies an unassigned admin workflow action', async () => {
  const result = await getEffectivePermissionExplanation(
    { query: async () => ({ rowCount: 0, rows: [] }) },
    {
      user: { id: 'admin', role: 'admin' }, action: 'approve', documentType: 'memo',
      document: { id: 'doc', document_type: 'memo', workflow_version: 1,
        current_step: 2, current_holder_id: 'primary', status: 'in_review' },
    }
  );
  assert.equal(result.final_decision, false);
});

test('removed normalized assignee is not restored from legacy workflow JSON', async () => {
  const client = {
    query: async (sql) => {
      if (sql.includes('SELECT id FROM docutracker_workflow_steps')) {
        return { rowCount: 1, rows: [{ id: 'step' }] };
      }
      if (sql.includes('routing_config')) {
        return { rowCount: 1, rows: [{ version: 1, steps: [
          { step_order: 1, assignee_type: 'user', user_ids: ['removed-user'] },
        ] }] };
      }
      if (sql.includes('FROM users')) throw new Error('Must not validate stale assignment');
      return { rowCount: 0, rows: [] };
    },
  };
  assert.equal(await canUserPerformDocumentAction(client, {
    user: { id: 'removed-user', role: 'employee' }, action: 'approve',
    document: { id: 'doc', document_type: 'memo', workflow_version: 1,
      current_step: 1, current_holder_id: 'primary', status: 'in_review' },
  }), false);
});

test('previous and future assignees cannot act on the current step', async () => {
  for (const userId of ['previous-user', 'future-user']) {
    const client = {
      query: async (sql, params) => {
        if (sql.includes('a.allowed_actions')) {
          assert.equal(params[2], 2);
          assert.equal(params[3], userId);
        }
        return { rowCount: 0, rows: [] };
      },
    };
    assert.equal(await canUserPerformDocumentAction(client, {
      user: { id: userId, role: 'employee' }, action: 'approve',
      document: { id: 'doc', document_type: 'memo', workflow_version: 1,
        current_step: 2, current_holder_id: 'primary', status: 'in_review' },
    }), false);
  }
});

test('filterDocumentsViewableByUser marks a routing assignee for the client', async () => {
  const row = {
    id: 'doc-assigned',
    document_type: 'memo',
    status: 'in_review',
    created_by: 'creator-id',
    current_holder_id: 'primary-id',
    current_step: 1,
  };
  const pool = {
    query: async (sql) => {
      if (sql.includes('docutracker_permissions')) return { rows: [] };
      if (sql.includes('rr.step_order = d.current_step')) {
        return { rows: [{ id: row.id }] };
      }
      return { rows: [] };
    },
  };

  const filtered = await filterDocumentsViewableByUser(
    pool,
    { id: 'backup-id', role: 'employee' },
    [row]
  );

  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].viewer_is_routing_assignee, true);
  assert.equal(mapDocumentRow(filtered[0]).viewer_is_routing_assignee, true);
});

test('filterDocumentsViewableByUser does not expose a future-step assignee', async () => {
  const row = {
    id: 'doc-future',
    document_type: 'memo',
    status: 'in_review',
    created_by: 'creator-id',
    current_holder_id: 'step-one-primary',
    current_step: 1,
  };
  const pool = {
    query: async (sql) => {
      if (sql.includes('docutracker_permissions')) return { rows: [] };
      if (sql.includes('docutracker_document_history')) return { rows: [] };
      if (sql.includes('docutracker_signature_fields')) return { rows: [] };
      return { rows: [] };
    },
  };

  const filtered = await filterDocumentsViewableByUser(
    pool,
    { id: 'step-three-primary', role: 'employee' },
    [row]
  );

  assert.deepEqual(filtered, []);
});

test('filterDocumentsViewableByUser shows department reviewers submitted documents from their department only', async () => {
  const rows = [
    {
      id: 'doc-dept-submitted', document_type: 'memo', status: 'in_review',
      created_by: 'staff-1', current_holder_id: 'hr-reviewer', current_step: 2,
      originating_department_id: 'dept-accounting',
    },
    {
      id: 'doc-dept-draft', document_type: 'memo', status: 'draft',
      created_by: 'staff-1', current_holder_id: null, current_step: null,
      originating_department_id: 'dept-accounting',
    },
    {
      id: 'doc-other-dept', document_type: 'memo', status: 'in_review',
      created_by: 'staff-2', current_holder_id: 'hr-reviewer', current_step: 1,
      originating_department_id: 'dept-engineering',
    },
  ];
  const pool = {
    query: async (sql) => {
      if (sql.includes('FROM department_reviewer_backups b')) {
        return { rows: [{ id: 'dept-accounting', name: 'Accounting' }] };
      }
      return { rows: [] };
    },
  };

  const user = { id: 'accounting-backup', role: 'employee' };
  const filtered = await filterDocumentsViewableByUser(pool, user, rows, {
    includeDepartmentQueue: true,
  });

  assert.deepEqual(filtered.map((r) => r.id), ['doc-dept-submitted']);
  assert.notEqual(filtered[0].viewer_is_routing_assignee, true);
  assert.deepEqual(await filterDocumentsViewableByUser(pool, user, rows), []);
});

test('department queue viewers cannot act on a step they are not assigned to', async () => {
  const document = {
    id: 'doc-dept', document_type: 'memo', status: 'in_review',
    created_by: 'staff-1', current_holder_id: 'hr-reviewer', current_step: 2,
    originating_department_id: 'dept-accounting', workflow_version: 1,
  };
  const client = {
    query: async (sql) => {
      if (sql.includes('FROM department_reviewer_backups b')) {
        return { rowCount: 1, rows: [{ id: 'dept-accounting', name: 'Accounting' }] };
      }
      return { rowCount: 0, rows: [] };
    },
  };
  const user = { id: 'accounting-head', role: 'employee' };

  assert.equal(
    await canUserPerformDocumentAction(client, { user, document, action: 'view' }),
    true
  );
  assert.equal(
    await canUserPerformDocumentAction(client, { user, document, action: 'approve' }),
    false
  );
});

function signatureStepPool({ requiresSignature, signed }) {
  return createMockPool((sql) => {
    if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
      return {
        rowCount: 1,
        rows: [{
          id: 'doc-sign',
          document_type: 'memo',
          workflow_version: 1,
          status: 'in_review',
          current_step: 1,
          created_by: 'creator-1',
          current_holder_id: 'head-1',
        }],
      };
    }
    if (sql.includes('a.allowed_actions')) {
      return {
        rowCount: 1,
        rows: [{ is_enabled: true, allowed_actions: ['approve', 'forward'], is_primary: true }],
      };
    }
    if (sql.includes('routing_config')) {
      return {
        rowCount: 1,
        rows: [{
          document_type: 'memo',
          version: 1,
          review_deadline_hours: 24,
          steps: [
            { step_order: 1, assignee_type: 'user', requires_signature: requiresSignature },
            { step_order: 2, assignee_type: 'user' },
          ],
        }],
      };
    }
    if (sql.includes('FROM docutracker_signature_fields') && sql.includes('signed_by')) {
      return { rowCount: signed ? 1 : 0, rows: signed ? [{ '?column?': 1 }] : [] };
    }
    return { rowCount: 0, rows: [] };
  });
}

test('signature-required step blocks approve and forward until the reviewer signs', async () => {
  for (const action of ['approve', 'forward']) {
    const { pool, calls } = signatureStepPool({ requiresSignature: true, signed: false });
    await assert.rejects(
      () => transitionDocument(pool, { id: 'head-1', role: 'employee' }, 'doc-sign', action, {}),
      (err) => {
        assert.equal(err.code, 'VALIDATION');
        assert.match(err.message, /This step requires your signature/);
        return true;
      }
    );
    assert.equal(calls.some((c) => c.sql.includes('UPDATE docutracker_documents')), false);
  }
});

test('signature gate passes once signed and is skipped for steps that do not require it', async () => {
  for (const scenario of [
    { requiresSignature: true, signed: true },
    { requiresSignature: false, signed: false },
  ]) {
    const { pool, calls } = signatureStepPool(scenario);
    try {
      await transitionDocument(pool, { id: 'head-1', role: 'employee' }, 'doc-sign', 'approve', {});
    } catch (err) {
      assert.doesNotMatch(String(err.message), /requires your signature/);
    }
    const checkedSignature = calls.some(
      (c) => c.sql.includes('FROM docutracker_signature_fields') && c.sql.includes('signed_by')
    );
    assert.equal(checkedSignature, scenario.requiresSignature);
  }
});

function mayorMemoPool({
  documentType = 'memo',
  currentStep = 2,
  signed = true,
  holder = 'assignee-1',
} = {}) {
  return createMockPool((sql) => {
    if (sql.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
      return {
        rowCount: 1,
        rows: [{
          id: 'doc-memo',
          document_type: documentType,
          workflow_version: 1,
          status: 'in_review',
          current_step: currentStep,
          created_by: 'staff-1',
          current_holder_id: holder,
        }],
      };
    }
    if (sql.includes('a.allowed_actions')) {
      return {
        rowCount: 1,
        rows: [{
          is_enabled: true,
          allowed_actions: ['approve', 'forward', 'return', 'reject'],
          is_primary: true,
        }],
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
      return { rowCount: signed ? 1 : 0, rows: signed ? [{ '?column?': 1 }] : [] };
    }
    return { rowCount: 0, rows: [] };
  });
}

function memoDocument(overrides = {}) {
  return {
    id: 'doc-memo',
    document_type: 'memo',
    workflow_version: 1,
    status: 'in_review',
    current_step: 2,
    created_by: 'staff-1',
    current_holder_id: 'assignee-1',
    ...overrides,
  };
}

test('only the active Mayor may give final approval on a Memo', async () => {
  const { pool } = mayorMemoPool();
  const client = await pool.connect();
  const staff = { id: 'staff-2', role: 'employee' };
  const mayor = { id: 'mayor-1', role: 'mayor' };
  const admin = { id: 'admin-1', role: 'admin' };

  for (const user of [staff, admin]) {
    assert.equal(
      await canUserPerformDocumentAction(client, { user, document: memoDocument(), action: 'approve' }),
      false
    );
  }
  assert.equal(
    await canUserPerformDocumentAction(client, { user: mayor, document: memoDocument(), action: 'approve' }),
    true
  );
  for (const action of ['return', 'reject']) {
    assert.equal(
      await canUserPerformDocumentAction(client, { user: staff, document: memoDocument(), action }),
      true
    );
  }
});

test('Mayor rule leaves earlier Memo steps and other document types alone', async () => {
  const { pool } = mayorMemoPool();
  const client = await pool.connect();
  const staff = { id: 'staff-2', role: 'employee' };
  assert.equal(
    await canUserPerformDocumentAction(client, {
      user: staff,
      document: memoDocument({ current_step: 1 }),
      action: 'approve',
    }),
    true
  );
  assert.equal(
    await canUserPerformDocumentAction(client, {
      user: staff,
      document: memoDocument({ document_type: 'purchaseRequest' }),
      action: 'approve',
    }),
    true
  );
});

test('issuing a Memo is refused for staff and requires the Mayor signature', async () => {
  const staffRun = mayorMemoPool();
  await assert.rejects(
    () => transitionDocument(staffRun.pool, { id: 'assignee-1', role: 'employee' }, 'doc-memo', 'approve', {}),
    (err) => {
      assert.equal(err.code, 'FORBIDDEN');
      assert.match(err.message, /Only the Mayor can give final approval/);
      return true;
    }
  );
  assert.equal(staffRun.calls.some((c) => c.sql.includes('UPDATE docutracker_documents')), false);

  const unsignedRun = mayorMemoPool({ signed: false, holder: 'mayor-1' });
  await assert.rejects(
    () => transitionDocument(unsignedRun.pool, { id: 'mayor-1', role: 'mayor' }, 'doc-memo', 'approve', {}),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /Sign the Memo before giving final approval/);
      return true;
    }
  );
  assert.equal(unsignedRun.calls.some((c) => c.sql.includes('UPDATE docutracker_documents')), false);
});

test('return and reject never require a signature', async () => {
  const { pool, calls } = signatureStepPool({ requiresSignature: true, signed: false });
  try {
    await transitionDocument(pool, { id: 'head-1', role: 'employee' }, 'doc-sign', 'reject', {});
  } catch (err) {
    assert.doesNotMatch(String(err.message), /requires your signature/);
  }
  assert.equal(
    calls.some((c) => c.sql.includes('FROM docutracker_signature_fields') && c.sql.includes('signed_by')),
    false
  );
});
