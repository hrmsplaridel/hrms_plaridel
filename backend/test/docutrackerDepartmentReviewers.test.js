const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canUserPerformDocumentAction,
  getEffectivePermissionExplanation,
  parseSteps,
  recoverDocumentAssignment,
  resolveStepAssignees,
  transitionDocument,
} = require('../src/services/docutrackerWorkflowService');
const { processEscalationsOnce } = require('../src/services/docutrackerEscalationWorker');

const DEPARTMENT_ID = '00000000-0000-0000-0000-000000000201';
const HEAD_ID = '00000000-0000-0000-0000-000000000301';
const BACKUP_ID = '00000000-0000-0000-0000-000000000302';

test('DocuTracker preserves the department reviewer source in routing JSON', () => {
  const steps = parseSteps([{
    step_order: 1,
    assignee_type: 'user',
    assignee_source: 'department_reviewers',
    department_id: DEPARTMENT_ID,
    user_ids: [],
  }]);
  assert.equal(steps[0].assignee_source, 'department_reviewers');
});

test('DocuTracker resolves the effective Head and backups for an automatic step', async () => {
  let primaryQuery = '';
  const client = {
    async query(sql) {
      const text = String(sql);
      if (text.includes('JOIN position_department_head_periods head_period')) {
        primaryQuery = text;
        return {
          rows: [{ reviewer_id: HEAD_ID, reviewer_name: 'Department Head' }],
        };
      }
      if (text.includes('FROM department_reviewer_backups b')) {
        return {
          rows: [{
            reviewer_id: BACKUP_ID,
            reviewer_name: 'Backup Reviewer',
            backup_rank: 1,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const reviewers = await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig: {
      step_order: 2,
      assignee_type: 'user',
      assignee_source: 'department_reviewers',
      department_id: DEPARTMENT_ID,
    },
    currentHolderId: null,
    documentType: 'memo',
    workflowVersion: 1,
  });

  assert.deepEqual(reviewers, [HEAD_ID, BACKUP_ID]);
  assert.match(primaryQuery, /head_period\.effective_from <= \$2::date/);
  assert.match(primaryQuery, /a\.is_active = true/);
  assert.match(primaryQuery, /p\.is_active = true/);
});

// --- Department reviewer of submitter: primary -> backups, never the submitter ---

const ENGINEERING = { id: 'dept-engineering', name: 'Engineering' };

function reviewerDirectoryHandler({
  primary = 'eng-head',
  backups = ['eng-backup-1', 'eng-backup-2'],
  members = {
    'eng-staff': ENGINEERING,
    'eng-head': ENGINEERING,
    'eng-backup-1': ENGINEERING,
    'eng-backup-2': ENGINEERING,
  },
} = {}) {
  return (sql, params = []) => {
    const text = String(sql);
    if (text.includes('JOIN position_department_head_periods head_period')) {
      const exclude = params[2];
      const rows = primary && params[0] === ENGINEERING.id && primary !== exclude
        ? [{ reviewer_id: primary, reviewer_name: primary }]
        : [];
      return { rowCount: rows.length, rows };
    }
    if (text.includes('FROM department_reviewer_backups b')) {
      const exclude = params[2];
      const rows = params[0] === ENGINEERING.id
        ? backups
            .map((id, index) => ({ reviewer_id: id, reviewer_name: id, backup_rank: index + 1 }))
            .filter((row) => row.reviewer_id !== exclude)
        : [];
      return { rowCount: rows.length, rows };
    }
    if (text.includes('FROM assignments a') && text.includes('LEFT JOIN departments d')) {
      const department = members[params[0]];
      const rows = department
        ? [{ department_id: department.id, department_name: department.name }]
        : [];
      return { rowCount: rows.length, rows };
    }
    if (text.includes('SELECT name FROM departments')) {
      return { rowCount: 1, rows: [{ name: ENGINEERING.name }] };
    }
    if (text.includes('FROM users') && text.includes('is_active')) {
      return { rowCount: 1, rows: [{ id: params[0] }] };
    }
    return null;
  };
}

function directoryClient(options) {
  const handle = reviewerDirectoryHandler(options);
  return {
    async query(sql, params) {
      return handle(sql, params) || { rowCount: 0, rows: [] };
    },
  };
}

const SUBMITTER_STEP = {
  step_order: 1,
  assignee_type: 'user',
  assignee_source: 'submitter_department_reviewers',
};

function resolveForSubmitter(client, submitterUserId, extra = {}) {
  return resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig: SUBMITTER_STEP,
    currentHolderId: null,
    documentType: 'memo',
    workflowVersion: 1,
    submitterUserId,
    ...extra,
  });
}

test('regular employee submission routes to the primary reviewer first, then backups', async () => {
  const reviewers = await resolveForSubmitter(directoryClient(), 'eng-staff');
  assert.deepEqual(reviewers, ['eng-head', 'eng-backup-1', 'eng-backup-2']);
});

test('primary reviewer submission routes to the first eligible backup reviewer', async () => {
  const reviewers = await resolveForSubmitter(directoryClient(), 'eng-head');
  assert.deepEqual(reviewers, ['eng-backup-1', 'eng-backup-2']);
});

test('backup reviewer submission routes to the primary reviewer and skips the submitter', async () => {
  const reviewers = await resolveForSubmitter(directoryClient(), 'eng-backup-1');
  assert.deepEqual(reviewers, ['eng-head', 'eng-backup-2']);
});

test('submitter is excluded from every reviewer list, including fixed-department steps', async () => {
  const client = directoryClient();
  for (const submitter of ['eng-head', 'eng-backup-1', 'eng-backup-2']) {
    const dynamic = await resolveForSubmitter(client, submitter);
    assert.equal(dynamic.includes(submitter), false);
    const fixed = await resolveStepAssignees(client, {
      explicitAssigneeId: null,
      stepConfig: {
        step_order: 1,
        assignee_type: 'user',
        assignee_source: 'department_reviewers',
        department_id: ENGINEERING.id,
      },
      currentHolderId: null,
      documentType: 'memo',
      workflowVersion: 1,
      submitterUserId: submitter,
    });
    assert.equal(fixed.includes(submitter), false);
    assert.ok(fixed.length > 0);
  }
});

test('primary reviewer with no backup is blocked with a clear message', async () => {
  await assert.rejects(
    () => resolveForSubmitter(directoryClient({ backups: [] }), 'eng-head'),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.equal(
        err.message,
        'No eligible reviewer is configured for Engineering. The primary reviewer cannot review their own document. Assign a backup reviewer before submitting.'
      );
      return true;
    }
  );
});

test('sole backup reviewer with no primary is blocked instead of self-reviewing', async () => {
  await assert.rejects(
    () => resolveForSubmitter(directoryClient({ primary: null, backups: ['eng-backup-1'] }), 'eng-backup-1'),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /No eligible reviewer is configured for Engineering/);
      assert.match(err.message, /cannot review their own document/);
      return true;
    }
  );
});

test('department with no reviewer configured is blocked', async () => {
  await assert.rejects(
    () => resolveForSubmitter(directoryClient({ primary: null, backups: [] }), 'eng-staff'),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.equal(
        err.message,
        'No reviewer is configured for Engineering. Assign a primary reviewer (Department Head) or a backup reviewer before submitting.'
      );
      return true;
    }
  );
});

test('submitter without an active department is blocked', async () => {
  await assert.rejects(
    () => resolveForSubmitter(directoryClient({ members: {} }), 'eng-staff'),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /no active department assignment/);
      return true;
    }
  );
});

test('an explicit assignee override cannot route a department review to the submitter', async () => {
  await assert.rejects(
    () => resolveForSubmitter(directoryClient(), 'eng-head', { explicitAssigneeId: 'eng-head' }),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /cannot review their own document/);
      return true;
    }
  );
});

// --- Action-time enforcement and full transitions ---

const MEMO_ROUTING = {
  document_type: 'memo',
  version: 1,
  review_deadline_hours: 24,
  steps: [
    { ...SUBMITTER_STEP, label: 'Department Review', allowed_actions: ['approve', 'return', 'reject'] },
    {
      step_order: 2,
      assignee_type: 'user',
      assignee_source: 'specific_users',
      user_ids: ['mayor-1'],
      label: 'Mayor',
      allowed_actions: ['approve', 'return', 'reject'],
    },
  ],
};

function memoPool({ document, directory = {}, storedAssigneeFor = null, routing = MEMO_ROUTING }) {
  const directoryHandle = reviewerDirectoryHandler(directory);
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      const text = String(sql);
      if (text.includes('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE')) {
        return { rowCount: 1, rows: [{ ...document }] };
      }
      if (text.includes('UPDATE docutracker_documents')) {
        return {
          rowCount: 1,
          rows: [{
            ...document,
            status: params[0],
            current_step: params[1],
            current_holder_id: params[2],
          }],
        };
      }
      if (text.includes('INSERT INTO docutracker_routing_records')) {
        return { rowCount: 1, rows: [{ id: 'routing-1' }] };
      }
      if (text.includes('FROM docutracker_routing_records') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [{ id: 'routing-1' }] };
      }
      if (text.includes('a.allowed_actions') && text.includes('docutracker_workflow_step_assignees')) {
        const stored = storedAssigneeFor && params.includes(storedAssigneeFor)
          ? [{ is_enabled: true, allowed_actions: ['approve'], is_primary: true, backup_rank: null }]
          : [];
        return { rowCount: stored.length, rows: stored };
      }
      if (text.includes('SELECT a.user_id::text AS user_id')) {
        const order = params[2];
        const step = routing.steps.find((s) => s.step_order === order);
        const rows = (step?.user_ids || []).map((id) => ({ user_id: id }));
        return { rowCount: rows.length, rows };
      }
      if (text.includes('routing_config')) {
        return { rowCount: 1, rows: [routing] };
      }
      if (text.includes('FROM docutracker_permissions')) {
        return {
          rowCount: 1,
          rows: [{ user_id: null, role_id: 'employee', document_type: 'memo', granted: true }],
        };
      }
      return directoryHandle(sql, params) || { rowCount: 0, rows: [] };
    },
    release() {},
  };
  return { calls, pool: { connect: async () => client }, client };
}

function documentUpdate(calls) {
  return calls.find((c) => String(c.sql).includes('UPDATE docutracker_documents'));
}

test('submission is blocked and nothing is written when the primary reviewer has no backup', async () => {
  const { pool, calls } = memoPool({
    document: {
      id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'draft',
      current_step: 1, created_by: 'eng-head', current_holder_id: null,
    },
    directory: { backups: [] },
  });
  await assert.rejects(
    () => transitionDocument(pool, { id: 'eng-head', role: 'employee' }, 'doc-memo', 'submit', {}),
    (err) => {
      assert.equal(err.code, 'VALIDATION');
      assert.match(err.message, /The primary reviewer cannot review their own document/);
      return true;
    }
  );
  assert.equal(documentUpdate(calls), undefined);
  assert.equal(calls.some((c) => c.sql === 'ROLLBACK'), true);
});

test('regular employee submission assigns the primary reviewer at the department review step', async () => {
  const { pool, calls } = memoPool({
    document: {
      id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'draft',
      current_step: 1, created_by: 'eng-staff', current_holder_id: null,
    },
  });
  await transitionDocument(pool, { id: 'eng-staff', role: 'employee' }, 'doc-memo', 'submit', {});
  const update = documentUpdate(calls);
  assert.equal(update.params[1], 1);
  assert.equal(update.params[2], 'eng-head');
});

test('approving the department review moves the document to the next workflow step', async () => {
  const { pool, calls } = memoPool({
    document: {
      id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'in_review',
      current_step: 1, created_by: 'eng-staff', current_holder_id: 'eng-head',
    },
  });
  await transitionDocument(pool, { id: 'eng-head', role: 'employee' }, 'doc-memo', 'approve', {});
  const update = documentUpdate(calls);
  assert.equal(update.params[0], 'in_review');
  assert.equal(update.params[1], 2);
  assert.equal(update.params[2], 'mayor-1');
});

test('creator cannot act on their own document at a department review step, even as a stored assignee', async () => {
  const document = {
    id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'in_review',
    current_step: 1, created_by: 'eng-head', current_holder_id: 'eng-head',
  };
  for (const role of ['employee', 'admin']) {
    const { client } = memoPool({ document, storedAssigneeFor: 'eng-head' });
    for (const action of ['approve', 'reject', 'forward', 'return']) {
      assert.equal(
        await canUserPerformDocumentAction(client, {
          user: { id: 'eng-head', role },
          document,
          action,
        }),
        false,
        `${role} creator must not ${action}`
      );
    }
  }
});

test('specific-person steps keep their configured assignee, including the creator', async () => {
  const routing = {
    ...MEMO_ROUTING,
    steps: [{
      step_order: 1,
      assignee_type: 'user',
      assignee_source: 'specific_users',
      user_ids: ['hr-1'],
      allowed_actions: ['approve'],
    }, MEMO_ROUTING.steps[1]],
  };
  const document = {
    id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'in_review',
    current_step: 1, created_by: 'hr-1', current_holder_id: 'hr-1',
  };
  const { client } = memoPool({ document, routing, storedAssigneeFor: 'hr-1' });
  assert.equal(
    await canUserPerformDocumentAction(client, {
      user: { id: 'hr-1', role: 'employee' },
      document,
      action: 'approve',
    }),
    true
  );
  const assignees = await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig: parseSteps(routing.steps)[0],
    currentHolderId: 'hr-1',
    documentType: 'memo',
    workflowVersion: 1,
    submitterUserId: 'hr-1',
  });
  assert.deepEqual(assignees, ['hr-1']);
});

// --- One active department reviewer; backups are fallback candidates ---

function inReviewMemo({ createdBy, holder }) {
  return {
    id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'in_review',
    current_step: 1, created_by: createdBy, current_holder_id: holder, title: 'Memo',
  };
}

async function canApprove(document, userId, options = {}) {
  const { client } = memoPool({ document, ...options });
  return canUserPerformDocumentAction(client, {
    user: { id: userId, role: 'employee' },
    document,
    action: 'approve',
  });
}

test('regular employee submission: only the primary reviewer can act, backups cannot', async () => {
  const document = inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' });
  assert.equal(await canApprove(document, 'eng-head'), true);
  assert.equal(await canApprove(document, 'eng-backup-1'), false);
  assert.equal(await canApprove(document, 'eng-backup-2'), false);
});

test('primary reviewer submission: the first backup can act, the submitting primary cannot', async () => {
  const document = inReviewMemo({ createdBy: 'eng-head', holder: 'eng-backup-1' });
  assert.equal(await canApprove(document, 'eng-backup-1'), true);
  assert.equal(await canApprove(document, 'eng-head'), false);
  assert.equal(await canApprove(document, 'eng-backup-2'), false);
});

test('backup reviewer submission: the primary can act, the submitting backup cannot', async () => {
  const document = inReviewMemo({ createdBy: 'eng-backup-1', holder: 'eng-head' });
  assert.equal(await canApprove(document, 'eng-head'), true);
  assert.equal(await canApprove(document, 'eng-backup-1'), false);
  assert.equal(await canApprove(document, 'eng-backup-2'), false);
});

test('an ineligible holder blocks everyone; authority never moves without a persisted recovery', async () => {
  const document = inReviewMemo({ createdBy: 'eng-staff', holder: 'former-head' });
  for (const userId of ['former-head', 'eng-head', 'eng-backup-1', 'eng-backup-2']) {
    assert.equal(await canApprove(document, userId), false, `${userId} must not act`);
  }
});

test('a holder who becomes ineligible gets a clear Admin Recovery error and nothing is written', async () => {
  for (const actor of ['eng-head', 'eng-backup-1']) {
    const { pool, calls } = memoPool({
      document: inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' }),
      directory: { primary: 'new-head' },
    });
    await assert.rejects(
      () => transitionDocument(pool, { id: actor, role: 'employee' }, 'doc-memo', 'approve', {}),
      (err) => {
        assert.equal(err.code, 'VALIDATION');
        assert.match(err.message, /no longer an eligible reviewer/);
        assert.match(err.message, /Admin Recovery/);
        return true;
      }
    );
    assert.equal(calls.some((c) => String(c.sql).includes('UPDATE docutracker_documents')), false);
    assert.equal(calls.some((c) => String(c.sql).includes('INSERT INTO docutracker_document_history')), false);
    assert.equal(calls.some((c) => c.sql === 'ROLLBACK'), true);
  }
});

test('permission explanation reports reassignment_required for an ineligible holder', async () => {
  const document = inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' });
  const { client } = memoPool({ document, directory: { primary: 'new-head' } });
  const result = await getEffectivePermissionExplanation(client, {
    user: { id: 'eng-head', role: 'employee' },
    action: 'approve',
    documentType: 'memo',
    document,
  });
  assert.equal(result.final_decision, false);
  assert.equal(result.reason, 'reassignment_required');

  const healthy = memoPool({ document });
  const backup = await getEffectivePermissionExplanation(healthy.client, {
    user: { id: 'eng-backup-1', role: 'employee' },
    action: 'approve',
    documentType: 'memo',
    document,
  });
  assert.equal(backup.final_decision, false);
  assert.equal(backup.reason, 'not_assigned_to_step');
});

test('approval by the active reviewer records history and notifies only the next step', async () => {
  const { pool, calls } = memoPool({
    document: inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' }),
  });
  await transitionDocument(pool, { id: 'eng-head', role: 'employee' }, 'doc-memo', 'approve', {});
  const history = calls.find((c) => String(c.sql).includes('INSERT INTO docutracker_document_history'));
  assert.ok(history, 'history row written');
  assert.equal(history.params.includes('eng-head'), true);
  const notified = calls.filter((c) => String(c.sql).includes('INSERT INTO docutracker_notifications'));
  assert.ok(notified.some((c) => c.params.includes('mayor-1')));
  for (const backup of ['eng-backup-1', 'eng-backup-2']) {
    assert.equal(notified.some((c) => c.params.includes(backup)), false);
  }
});

test('submission snapshots and notifies only the active reviewer, not the backups', async () => {
  const { pool, calls } = memoPool({
    document: {
      id: 'doc-memo', document_type: 'memo', workflow_version: 1, status: 'draft',
      current_step: 1, created_by: 'eng-staff', current_holder_id: null, title: 'Memo',
    },
  });
  await transitionDocument(pool, { id: 'eng-staff', role: 'employee' }, 'doc-memo', 'submit', {});
  const snapshot = calls
    .filter((c) => String(c.sql).includes('INSERT INTO docutracker_routing_record_assignees'))
    .map((c) => c.params[1]);
  assert.deepEqual(snapshot, ['eng-head']);
  const notified = calls.filter((c) => String(c.sql).includes('INSERT INTO docutracker_notifications'));
  assert.ok(notified.length > 0);
  for (const backup of ['eng-backup-1', 'eng-backup-2']) {
    assert.equal(notified.some((c) => c.params.includes(backup)), false);
  }
});

test('admin recovery to a configured backup makes that backup the only active reviewer', async () => {
  const before = inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' });
  const { pool, calls } = memoPool({ document: before });
  await recoverDocumentAssignment(pool, { id: 'admin-1', role: 'admin' }, 'doc-memo', {
    current_holder_id: 'eng-backup-1',
    remarks: 'Primary reviewer unavailable',
  });
  const update = calls.find((c) => String(c.sql).includes('UPDATE docutracker_documents'));
  assert.equal(update.params[0], 'eng-backup-1');
  const snapshot = calls
    .filter((c) => String(c.sql).includes('INSERT INTO docutracker_routing_record_assignees'))
    .map((c) => c.params[1]);
  assert.deepEqual(snapshot, ['eng-backup-1']);
  const history = calls.find((c) => String(c.sql).includes('INSERT INTO docutracker_document_history'));
  assert.ok(history, 'recovery writes a history row');
  assert.equal(history.params.includes('admin-1'), true);
  const notified = calls.filter((c) => String(c.sql).includes('INSERT INTO docutracker_notifications'));
  assert.equal(notified.length, 1);
  assert.equal(notified[0].params.includes('eng-backup-1'), true);
  assert.equal(calls.some((c) => c.sql === 'COMMIT'), true);

  const after = { ...before, current_holder_id: 'eng-backup-1' };
  assert.equal(await canApprove(after, 'eng-backup-1'), true);
  assert.equal(await canApprove(after, 'eng-head'), false);
  assert.equal(await canApprove(after, 'eng-backup-2'), false);
});

test('admin recovery cannot target the creator or someone who is not a configured reviewer', async () => {
  for (const [createdBy, target] of [['eng-head', 'eng-head'], ['eng-staff', 'acct-backup']]) {
    const { pool, calls } = memoPool({ document: inReviewMemo({ createdBy, holder: 'eng-backup-1' }) });
    await assert.rejects(
      () => recoverDocumentAssignment(pool, { id: 'admin-1', role: 'admin' }, 'doc-memo', {
        current_holder_id: target,
        remarks: 'Reassign',
      }),
      /not configured for the current workflow step/
    );
    assert.equal(calls.some((c) => String(c.sql).includes('UPDATE docutracker_documents')), false);
  }
});

test('an unrelated user or another department\'s backup cannot act on a department review step', async () => {
  const document = inReviewMemo({ createdBy: 'eng-staff', holder: 'eng-head' });
  assert.equal(await canApprove(document, 'acct-backup'), false);
  assert.equal(await canApprove(document, 'random-user'), false);
});

test('specific-person steps still let every configured assignee act, not only the holder', async () => {
  const routing = {
    ...MEMO_ROUTING,
    steps: [{
      step_order: 1,
      assignee_type: 'user',
      assignee_source: 'specific_users',
      user_ids: ['hr-1', 'hr-2'],
      allowed_actions: ['approve'],
    }, MEMO_ROUTING.steps[1]],
  };
  const document = inReviewMemo({ createdBy: 'staff-1', holder: 'hr-1' });
  assert.equal(await canApprove(document, 'hr-2', { routing, storedAssigneeFor: 'hr-2' }), true);
  assert.equal(await canApprove(document, 'hr-3', { routing }), false);
});

// --- Escalation of overdue department review steps ---

function overdueMemo({ createdBy = 'eng-staff', holder = 'eng-head', ...overrides } = {}) {
  return {
    ...inReviewMemo({ createdBy, holder }),
    deadline_time: new Date(Date.now() - 60 * 1000),
    escalation_level: 0,
    escalation_target_role: 'supervisor',
    escalation_delay_minutes: 60,
    max_escalation_level: 3,
    notify_original_sender: false,
    ...overrides,
  };
}

async function runEscalation(doc, { directory = {}, routing = MEMO_ROUTING, roleUser = 'eng-supervisor' } = {}) {
  const directoryHandle = reviewerDirectoryHandler(directory);
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      const text = String(sql);
      if (text.includes('pg_try_advisory_lock')) return { rowCount: 1, rows: [{ locked: true }] };
      if (text.includes('FOR UPDATE OF d SKIP LOCKED')) return { rowCount: 1, rows: [{ ...doc }] };
      if (text.includes('docutracker_routing_config_versions')) return { rowCount: 1, rows: [routing] };
      if (text.includes('INSERT INTO docutracker_routing_records')) {
        return { rowCount: 1, rows: [{ id: 'routing-1' }] };
      }
      if (text.includes("WHERE role = 'admin'")) return { rowCount: 1, rows: [{ id: 'admin-1' }] };
      if (text.includes('u.role = ANY')) {
        return roleUser ? { rowCount: 1, rows: [{ id: roleUser }] } : { rowCount: 0, rows: [] };
      }
      if (/^\s*SELECT id\s+FROM docutracker_(notifications|document_history)/.test(text)) {
        return { rowCount: 0, rows: [] };
      }
      return directoryHandle(sql, params) || { rowCount: 0, rows: [] };
    },
    release() {},
  };
  await processEscalationsOnce({ db: { connect: async () => client } });
  const matching = (fragment) => calls.filter((c) => String(c.sql).includes(fragment));
  return {
    calls,
    committed: calls.some((c) => c.sql === 'COMMIT'),
    documentUpdate: matching('UPDATE docutracker_documents')[0],
    history: matching('INSERT INTO docutracker_document_history'),
    notifications: matching('INSERT INTO docutracker_notifications'),
    notifiedUsers: matching('INSERT INTO docutracker_notifications').map((c) => c.params[1]),
    routingAssignees: matching('INSERT INTO docutracker_routing_records').map((c) => c.params[2]),
    snapshot: matching('INSERT INTO docutracker_routing_record_assignees').map((c) => c.params[1]),
    roleLookupUsed: calls.some((c) => String(c.sql).includes('u.role = ANY')),
  };
}

test('escalation moves an overdue department review to the next eligible reviewer', async () => {
  const result = await runEscalation(overdueMemo({ holder: 'eng-head' }));
  assert.equal(result.committed, true);
  assert.equal(result.roleLookupUsed, false, 'role-based recipient lookup is not used');
  assert.match(String(result.documentUpdate.sql), /status = 'escalated'/);
  assert.equal(result.documentUpdate.params[3], 'eng-backup-1');
  assert.match(String(result.documentUpdate.sql), /needs_admin_intervention = false/);
  assert.deepEqual(result.routingAssignees, ['eng-backup-1']);
  assert.deepEqual(result.snapshot, ['eng-backup-1']);
  assert.equal(result.history.length, 1);
  assert.equal(result.history[0].params[1], 'escalated');
  assert.match(result.history[0].params[6], /next eligible backup reviewer #1/);
  assert.deepEqual(result.notifiedUsers, ['eng-backup-1']);

  const escalated = { ...overdueMemo(), status: 'escalated', current_holder_id: 'eng-backup-1' };
  assert.equal(await canApprove(escalated, 'eng-backup-1'), true);
  assert.equal(await canApprove(escalated, 'eng-head'), false);
  assert.equal(await canApprove(escalated, 'eng-backup-2'), false);
});

test('escalation never assigns the role-based recipient or any non-reviewer', async () => {
  for (const doc of [
    overdueMemo({ holder: 'eng-head' }),
    overdueMemo({ holder: 'eng-backup-2' }),
    overdueMemo({ holder: 'former-head' }),
  ]) {
    const result = await runEscalation(doc, { roleUser: 'eng-supervisor' });
    assert.equal(result.committed, true);
    const written = result.calls.flatMap((c) => c.params || []);
    assert.equal(written.includes('eng-supervisor'), false, 'role user never written');
    for (const assignee of result.routingAssignees) {
      assert.ok(['eng-head', 'eng-backup-1', 'eng-backup-2', 'former-head'].includes(assignee));
    }
  }
});

test('escalation with no other eligible reviewer flags Admin Recovery and keeps the holder', async () => {
  const result = await runEscalation(overdueMemo({ holder: 'eng-backup-2' }));
  assert.equal(result.committed, true);
  assert.match(String(result.documentUpdate.sql), /status = 'overdue'/);
  assert.match(String(result.documentUpdate.sql), /needs_admin_intervention = true/);
  assert.doesNotMatch(String(result.documentUpdate.sql), /current_holder_id/);
  assert.deepEqual(result.routingAssignees, ['eng-backup-2']);
  assert.deepEqual(result.snapshot, []);
  assert.equal(result.history[0].params[1], 'overdue');
  assert.match(result.history[0].params[6], /no other eligible department reviewer/);
  assert.match(result.history[0].params[6], /Admin Recovery/);
  assert.deepEqual(result.notifiedUsers.sort(), ['admin-1', 'eng-backup-2']);
  const adminNotice = result.notifications.find((c) => c.params[1] === 'admin-1');
  assert.match(adminNotice.params[5], /Admin Recovery/);
});

test('escalation with an ineligible holder flags Admin Recovery without notifying or reassigning', async () => {
  const result = await runEscalation(overdueMemo({ holder: 'eng-head' }), {
    directory: { primary: 'new-head' },
  });
  assert.equal(result.committed, true);
  assert.match(String(result.documentUpdate.sql), /needs_admin_intervention = true/);
  assert.doesNotMatch(String(result.documentUpdate.sql), /current_holder_id/);
  assert.match(result.history[0].params[6], /no longer an eligible department reviewer/);
  assert.deepEqual(result.notifiedUsers, ['admin-1']);
  assert.deepEqual(result.snapshot, []);
});

test('a document flagged by escalation requires Admin Recovery, which makes the backup the sole reviewer', async () => {
  const flagged = {
    ...overdueMemo({ holder: 'eng-head' }),
    status: 'overdue',
    needs_admin_intervention: true,
    deadline_time: null,
  };
  const directory = { primary: 'new-head' };
  for (const userId of ['eng-head', 'new-head', 'eng-backup-1']) {
    assert.equal(await canApprove(flagged, userId, { directory }), false, `${userId} must not act`);
  }
  const blocked = memoPool({ document: flagged, directory });
  await assert.rejects(
    () => transitionDocument(blocked.pool, { id: 'eng-head', role: 'employee' }, 'doc-memo', 'approve', {}),
    /Admin Recovery/
  );

  const { pool, calls } = memoPool({ document: flagged, directory });
  await recoverDocumentAssignment(pool, { id: 'admin-1', role: 'admin' }, 'doc-memo', {
    current_holder_id: 'eng-backup-1',
    remarks: 'Overdue; primary reviewer changed',
  });
  const update = calls.find((c) => String(c.sql).includes('UPDATE docutracker_documents'));
  assert.equal(update.params[0], 'eng-backup-1');
  assert.match(String(update.sql), /needs_admin_intervention = false/);
  const recovered = { ...flagged, current_holder_id: 'eng-backup-1', needs_admin_intervention: false };
  assert.equal(await canApprove(recovered, 'eng-backup-1', { directory }), true);
  assert.equal(await canApprove(recovered, 'new-head', { directory }), false);
  assert.equal(await canApprove(recovered, 'eng-backup-2', { directory }), false);
});

test('escalation never makes the creator the reviewer', async () => {
  const skip = await runEscalation(overdueMemo({ createdBy: 'eng-backup-1', holder: 'eng-head' }));
  assert.equal(skip.documentUpdate.params[3], 'eng-backup-2');
  assert.deepEqual(skip.notifiedUsers, ['eng-backup-2']);

  const exhausted = await runEscalation(
    overdueMemo({ createdBy: 'eng-backup-2', holder: 'eng-backup-1' }),
    { roleUser: 'eng-backup-2' }
  );
  assert.match(String(exhausted.documentUpdate.sql), /needs_admin_intervention = true/);
  const written = exhausted.calls
    .filter((c) => /UPDATE docutracker_documents|INSERT INTO docutracker_routing/.test(String(c.sql)))
    .flatMap((c) => c.params || []);
  assert.equal(written.includes('eng-backup-2'), false);
});

test('specific-person steps keep role-based escalation unchanged', async () => {
  const routing = {
    ...MEMO_ROUTING,
    steps: [{
      step_order: 1,
      assignee_type: 'user',
      assignee_source: 'specific_users',
      user_ids: ['hr-1'],
      allowed_actions: ['approve'],
    }, MEMO_ROUTING.steps[1]],
  };
  const result = await runEscalation(
    overdueMemo({ createdBy: 'staff-1', holder: 'hr-1' }),
    { routing, roleUser: 'hr-supervisor' }
  );
  assert.equal(result.committed, true);
  assert.equal(result.roleLookupUsed, true);
  assert.equal(result.documentUpdate.params[3], 'hr-supervisor');
  assert.deepEqual(result.routingAssignees, ['hr-supervisor']);
  assert.deepEqual(result.snapshot, []);
  assert.equal(result.history[0].params[1], 'escalated');
  assert.deepEqual(result.notifiedUsers, ['hr-supervisor']);
});

test('escalation notifies the creator only when configured, and never the backups', async () => {
  const result = await runEscalation(overdueMemo({ holder: 'eng-head', notify_original_sender: true }));
  assert.deepEqual(result.notifiedUsers.sort(), ['eng-backup-1', 'eng-staff']);
  const creatorNotice = result.notifications.find((c) => c.params[1] === 'eng-staff');
  assert.equal(creatorNotice.params[2], 'escalated');
  assert.equal(result.notifiedUsers.includes('eng-backup-2'), false);
});
