const test = require('node:test');
const assert = require('node:assert/strict');
const {
  VALID_STATUSES,
  mapDocumentRow,
  ensureValidWorkflowConfig,
  permissionPriority,
  resolvePermissionDecisionFromRows,
  hasPermission,
  canUserPerformDocumentAction,
  filterDocumentsViewableByUser,
  transitionDocument,
  getEffectivePermissionExplanation,
} = require('../src/services/docutrackerWorkflowService');

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
      assert.match(err.message, /forward is not valid from status pending/);
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
