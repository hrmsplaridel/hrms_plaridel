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
  recoverDocumentAssignment,
  listDocuments,
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
