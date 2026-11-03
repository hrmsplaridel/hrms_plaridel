/**
 * Usability-test data setup for DocuTracker.
 * Creates UT-* memos via real create/transition/sign/release services.
 * Does NOT touch DOC-2026-000041.
 */
require('dotenv').config();
const zlib = require('zlib');
const { pool } = require('./src/config/db');
const {
  createDocument,
  transitionDocument,
  canUserPerformTypeAction,
  listDocuments,
} = require('./src/services/docutrackerWorkflowService');
const {
  signDocumentField,
  getDocumentBuilder,
  saveDocumentBuilder,
} = require('./src/services/docutrackerDocumentBuilderService');
const { releaseDocument } = require('./src/services/docutrackerReleaseService');

const HR_OFFICE = 'cc5d5acd-9c95-4138-a1f5-f3fe0913ba27';
const ACCOUNTING = '3b54920b-6096-46a8-9e78-8d783ad196fc';
const PROTECTED = 'DOC-2026-000041';

const IDS = {
  kristoffer: 'a90b0e43-1e94-4e5e-81e1-d01aa6b82c0b',
  dann: 'de7161b5-5411-4c17-bfdd-90bd34cbfd2c',
  tope: 'a4202821-8b77-48a5-9fca-857619e5d9f0',
  emma: '891ff2fb-473c-45a8-aa2f-880a37f413fa',
  mariaEng: '07c59c6e-1e36-4f70-802d-9e59e3bd89ee',
  mayor: '260546b0-acf6-42d0-a564-1a346eec1397',
};

function crc32(buf) {
  let c;
  let crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function signaturePng() {
  const w = 200;
  const h = 60;
  const px = Buffer.alloc(w * h * 4);
  for (let x = 8; x < w - 8; x++) {
    const y0 = Math.round(30 + 18 * Math.sin(x / 18));
    for (let dy = -2; dy <= 2; dy++) {
      const y = y0 + dy;
      if (y < 0 || y >= h) continue;
      const i = (y * w + x) * 4;
      px[i] = 20;
      px[i + 1] = 30;
      px[i + 2] = 70;
      px[i + 3] = 255;
    }
  }
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    px.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

async function loadUser(id) {
  const r = await pool.query(
    `SELECT id, email, role, full_name, auth_version, is_active FROM users WHERE id = $1`,
    [id]
  );
  if (!r.rowCount) throw new Error(`user ${id} missing`);
  return r.rows[0];
}

async function ensurePrimaryReviewerTable() {
  await pool.query(`CREATE EXTENSION IF NOT EXISTS btree_gist`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS primary_reviewer_designations (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      scope_key TEXT NOT NULL,
      department_id UUID REFERENCES departments(id) ON DELETE RESTRICT,
      employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
      position_id UUID REFERENCES positions(id) ON DELETE SET NULL,
      position_title_snapshot TEXT,
      effective_from DATE NOT NULL,
      effective_to DATE,
      is_active BOOLEAN NOT NULL DEFAULT true,
      created_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (effective_to IS NULL OR effective_to >= effective_from),
      CHECK ((scope_key = 'final_hr' AND department_id IS NULL)
        OR (department_id IS NOT NULL AND scope_key = 'department:' || department_id::text))
    )
  `);
  // Prefer named constraint if missing; ignore if gist exclusion already exists under another name.
  await pool.query(`
    DO $$ BEGIN
      ALTER TABLE primary_reviewer_designations
        ADD CONSTRAINT primary_reviewer_no_overlap EXCLUDE USING gist (
          scope_key WITH =, daterange(effective_from, effective_to, '[]') WITH &&
        ) WHERE (is_active = true);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$
  `);
}

async function ensureDannPrimaryForHrOffice(created) {
  const existing = await pool.query(
    `SELECT id, employee_id, is_active FROM primary_reviewer_designations
     WHERE department_id = $1::uuid AND is_active = true
       AND effective_from <= CURRENT_DATE
       AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)`,
    [HR_OFFICE]
  );
  if (existing.rowCount) {
    created.notes.push(
      `primary_reviewer_designations already had active row for HR Office: ${existing.rows[0].id}`
    );
    return existing.rows[0];
  }
  const ins = await pool.query(
    `INSERT INTO primary_reviewer_designations
       (scope_key, department_id, employee_id, position_title_snapshot,
        effective_from, effective_to, is_active)
     VALUES ($1, $2::uuid, $3::uuid, 'Department Head', CURRENT_DATE, NULL, true)
     RETURNING id, employee_id`,
    [`department:${HR_OFFICE}`, HR_OFFICE, IDS.dann]
  );
  created.primary_reviewer_designations.push(ins.rows[0].id);
  return ins.rows[0];
}

async function ensureKristofferReleasePerm(created) {
  const existing = await pool.query(
    `SELECT id, granted FROM docutracker_permissions
     WHERE user_id = $1::uuid AND document_type = 'memo' AND action = 'release'`,
    [IDS.kristoffer]
  );
  if (existing.rowCount) {
    if (existing.rows[0].granted !== true) {
      await pool.query(
        `UPDATE docutracker_permissions SET granted = true, updated_at = now() WHERE id = $1`,
        [existing.rows[0].id]
      );
      created.permission_updates.push({
        id: existing.rows[0].id,
        note: 'flipped granted false→true for Kristoffer memo release',
      });
    } else {
      created.notes.push('Kristoffer already had memo release permission');
    }
    return existing.rows[0].id;
  }
  const ins = await pool.query(
    `INSERT INTO docutracker_permissions
       (role_id, user_id, document_type, action, granted)
     VALUES (NULL, $1::uuid, 'memo', 'release', true)
     RETURNING id`,
    [IDS.kristoffer]
  );
  created.permissions.push(ins.rows[0].id);
  return ins.rows[0].id;
}

async function assertProtectedUntouched() {
  const r = await pool.query(
    `SELECT document_number, status, updated_at,
            (SELECT COUNT(*) FROM docutracker_signature_fields f
             WHERE f.document_id = d.id) AS field_count
     FROM docutracker_documents d WHERE document_number = $1`,
    [PROTECTED]
  );
  return r.rows[0] || null;
}

async function createMemo(user, title) {
  return createDocument(pool, user, {
    document_type: 'memo',
    title,
    description: 'Usability test record — safe to delete after sessions.',
  });
}

async function submit(user, docId) {
  return transitionDocument(pool, user, docId, 'submit', {
    remarks: 'UT setup submit',
  });
}

async function approve(user, docId, remarks) {
  return transitionDocument(pool, user, docId, 'approve', {
    remarks: remarks || 'UT setup approve',
  });
}

async function ensureMayorSigned(mayor, docId) {
  // Open/save builder so official Prepared/Approved fields exist when applicable.
  try {
    await getDocumentBuilder(pool, mayor, docId);
  } catch (_) {}
  try {
    await saveDocumentBuilder(pool, mayor, docId, { pages: [{ blocks: [] }] });
  } catch (_) {}

  let fields = (
    await pool.query(
      `SELECT id, label, assigned_signer_id, signed_at
       FROM docutracker_signature_fields WHERE document_id = $1`,
      [docId]
    )
  ).rows;

  let approved = fields.find(
    (f) =>
      String(f.assigned_signer_id) === IDS.mayor &&
      /approved/i.test(String(f.label || ''))
  );
  if (!approved) {
    approved = fields.find((f) => String(f.assigned_signer_id) === IDS.mayor);
  }
  if (!approved) {
    const ins = await pool.query(
      `INSERT INTO docutracker_signature_fields
         (document_id, page_number, position_x, position_y, width, height,
          assigned_signer_id, label, created_by)
       VALUES ($1, 1, 0.5, 0.70, 0.35, 0.09, $2::uuid, 'Approved by', $2::uuid)
       RETURNING id, label, assigned_signer_id, signed_at`,
      [docId, IDS.mayor]
    );
    approved = ins.rows[0];
  }
  if (approved.signed_at) return approved.id;

  await signDocumentField(pool, mayor, docId, approved.id, {
    image_base64: signaturePng().toString('base64'),
    mime_type: 'image/png',
    source_type: 'drawn',
  });
  return approved.id;
}

async function docState(docId) {
  const d = (
    await pool.query(
      `SELECT id, document_number, title, status, current_step, current_holder_id,
              release_required, released_at, released_to_department_id,
              released_to_department_name, originating_department_id,
              created_by, workflow_version
       FROM docutracker_documents WHERE id = $1`,
      [docId]
    )
  ).rows[0];
  const holder = d.current_holder_id
    ? (
        await pool.query(`SELECT full_name FROM users WHERE id = $1`, [
          d.current_holder_id,
        ])
      ).rows[0]?.full_name
    : null;
  const routing = (
    await pool.query(
      `SELECT rr.id, rr.step_order, rr.assignee_id, rr.status, u.full_name AS assignee_name
       FROM docutracker_routing_records rr
       LEFT JOIN users u ON u.id = rr.assignee_id
       WHERE rr.document_id = $1
       ORDER BY rr.step_order, rr.created_at`,
      [docId]
    ).catch(() => ({ rows: [] }))
  ).rows;
  const history = (
    await pool.query(
      `SELECT id, action, actor_name, remarks, created_at
       FROM docutracker_document_history
       WHERE document_id = $1 ORDER BY created_at`,
      [docId]
    )
  ).rows;
  const notifs = (
    await pool.query(
      `SELECT id, user_id, type, title FROM docutracker_notifications
       WHERE document_id = $1`,
      [docId]
    )
  ).rows;
  return { ...d, holder_name: holder, routing, history, notifications: notifs };
}

async function userCanView(user, docId) {
  const { canUserPerformDocumentAction } = require('./src/services/docutrackerWorkflowService');
  try {
    const doc = (
      await pool.query(`SELECT * FROM docutracker_documents WHERE id = $1`, [docId])
    ).rows[0];
    if (!doc) return false;
    const ok = await canUserPerformDocumentAction(pool, {
      user,
      document: doc,
      action: 'view',
    });
    return ok === true;
  } catch (e) {
    return `ERR:${e.message}`;
  }
}

async function viewerCanRelease(user, docId) {
  try {
    const { getReleaseOptions } = require('./src/services/docutrackerReleaseService');
    const opts = await getReleaseOptions(pool, user, docId);
    return { can_release: opts?.can_release === true, released: opts?.released };
  } catch (e) {
    return { can_release: false, error: e.message };
  }
}

(async () => {
  const created = {
    documents: [],
    primary_reviewer_designations: [],
    permissions: [],
    permission_updates: [],
    signature_fields: [],
    notes: [],
    protected_before: null,
    protected_after: null,
  };

  created.protected_before = await assertProtectedUntouched();

  // Prerequisite: table already defined in init-schema / DTR migration but missing here.
  await ensurePrimaryReviewerTable();
  created.notes.push(
    'Created primary_reviewer_designations IF NOT EXISTS (matches init-schema; no migration file added).'
  );
  await ensureDannPrimaryForHrOffice(created);
  await ensureKristofferReleasePerm(created);

  const tope = await loadUser(IDS.tope);
  const dann = await loadUser(IDS.dann);
  const mayor = await loadUser(IDS.mayor);
  const kristoffer = await loadUser(IDS.kristoffer);
  const emma = await loadUser(IDS.emma);
  const maria = await loadUser(IDS.mariaEng);

  // Confirm Tope can create
  if (!(await canUserPerformTypeAction(pool, { user: tope, documentType: 'memo', action: 'create_draft' }))) {
    throw new Error('Tope cannot create_draft memo');
  }
  if (!(await canUserPerformTypeAction(pool, { user: kristoffer, documentType: 'memo', action: 'release' }))) {
    throw new Error('Kristoffer still cannot release after permission insert');
  }

  // 1) UT-REV-QUEUE-DEMO — stop at department review (Dann)
  const rev = await createMemo(tope, 'UT-REV-QUEUE-DEMO');
  created.documents.push({ title: 'UT-REV-QUEUE-DEMO', id: rev.id, number: rev.document_number });
  await submit(tope, rev.id);
  const revState = await docState(rev.id);
  if (String(revState.current_holder_id) !== IDS.dann) {
    throw new Error(
      `UT-REV holder expected Dann, got ${revState.holder_name} (${revState.current_holder_id})`
    );
  }

  // 2) UT-HR-AWAITING-RELEASE — approve through Mayor, do not release
  const hrDoc = await createMemo(tope, 'UT-HR-AWAITING-RELEASE');
  created.documents.push({
    title: 'UT-HR-AWAITING-RELEASE',
    id: hrDoc.id,
    number: hrDoc.document_number,
  });
  await submit(tope, hrDoc.id);
  await approve(dann, hrDoc.id, 'UT setup department approve');
  const mayorFieldHr = await ensureMayorSigned(mayor, hrDoc.id);
  created.signature_fields.push({ document_id: hrDoc.id, field_id: mayorFieldHr });
  await approve(mayor, hrDoc.id, 'UT setup mayor final approve');
  const hrState = await docState(hrDoc.id);
  if (hrState.status !== 'approved' || hrState.release_required !== true || hrState.released_at) {
    throw new Error(`UT-HR bad state: ${JSON.stringify(hrState)}`);
  }

  // 3) UT-EMP-RELEASED-DEMO — full path + release to Accounting
  const empDoc = await createMemo(tope, 'UT-EMP-RELEASED-DEMO');
  created.documents.push({
    title: 'UT-EMP-RELEASED-DEMO',
    id: empDoc.id,
    number: empDoc.document_number,
  });
  await submit(tope, empDoc.id);
  await approve(dann, empDoc.id, 'UT setup department approve');
  const mayorFieldEmp = await ensureMayorSigned(mayor, empDoc.id);
  created.signature_fields.push({ document_id: empDoc.id, field_id: mayorFieldEmp });
  await approve(mayor, empDoc.id, 'UT setup mayor final approve');
  await releaseDocument(pool, kristoffer, empDoc.id, {
    department_id: ACCOUNTING,
    remarks: 'UT setup release to Accounting for employee visibility demo',
    idempotency_key: `ut-emp-release-${empDoc.id}`,
  });
  const empState = await docState(empDoc.id);

  // Verifications
  const verifications = {
    emma_sees_released: await userCanView(emma, empDoc.id),
    maria_sees_released: await userCanView(maria, empDoc.id),
    dann_sees_rev: await userCanView(dann, rev.id),
    dann_is_rev_holder: String(revState.current_holder_id) === IDS.dann,
    kristoffer_can_release_hr: await viewerCanRelease(kristoffer, hrDoc.id),
    emma_can_release_hr: await viewerCanRelease(emma, hrDoc.id),
    dann_can_release_hr: await viewerCanRelease(dann, hrDoc.id),
  };

  // Required Actions UI uses holder / actionable docs; verify via holder filter + approve capability.
  let dannRequired = null;
  try {
    const listed = await listDocuments(pool, dann, {
      limit: 200,
      holderId: IDS.dann,
    });
    const arr = listed?.documents || [];
    dannRequired = arr.some((d) => String(d.id) === String(rev.id));
  } catch (e) {
    dannRequired = `ERR:${e.message}`;
  }
  verifications.dann_queue_contains_rev = dannRequired;
  verifications.dann_is_only_active_holder =
    String(revState.current_holder_id) === IDS.dann &&
    Number(revState.current_step) === 1;

  const revRouting = (
    await pool.query(
      `SELECT step_order, assignee_id::text, status, u.full_name
       FROM docutracker_routing_records rr
       LEFT JOIN users u ON u.id = rr.assignee_id
       WHERE rr.document_id = $1
       ORDER BY step_order`,
      [rev.id]
    )
  ).rows;
  verifications.rev_routing_records = revRouting;

  created.protected_after = await assertProtectedUntouched();

  const report = {
    testers: {
      employee: { ...emma, department: 'Accounting' },
      unrelated_employee: { ...maria, department: 'Engineering' },
      reviewer: { ...dann, department: 'HR Office', role_note: 'primary reviewer designation + backup' },
      creator_submitter: { ...tope, department: 'HR Office' },
      hr_admin: { ...kristoffer, role: 'admin', release: 'user-specific memo release grant (temp)' },
      mayor: { ...mayor },
    },
    documents: {
      rev: await docState(rev.id),
      hr: await docState(hrDoc.id),
      emp: await docState(empDoc.id),
    },
    verifications,
    created,
  };
  console.log(JSON.stringify(report, null, 2));
  await pool.end();
})().catch(async (e) => {
  console.error('SETUP FAILED', e);
  await pool.end();
  process.exit(1);
});
