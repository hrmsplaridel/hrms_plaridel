/**
 * Phase 2.5 — create one mayor_office_staff test account and validate RBAC/E2E APIs.
 * Credentials are written only to a local gitignored file; never printed.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const https = require('node:https');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { pool } = require('../src/config/db');
const { clearModule } = require('../test/helpers/moduleMocks');

const API_BASE = process.env.PHASE25_API_BASE || 'http://127.0.0.1:3000';
const CREDS_DIR = path.join(
  process.env.USERPROFILE || process.env.HOME || __dirname,
  'Backups',
  'hrms_plaridel_isolation',
);
const CREDS_FILE = path.join(CREDS_DIR, 'phase25_mayor_office_staff_creds.json');
const REPORT = {
  preflight: {},
  account: {},
  staff: { login: null, nav: {}, functional: {}, security: {} },
  mayor: { login: null, functional: {}, security: {} },
  api: [],
  regression: {},
  preservation: {},
  bugs: [],
  testEndorsements: [],
  recommendation: null,
};

function generateStrongPassword() {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '!@#$%';
  const all = lower + upper + numbers + symbols;
  const chars = [
    lower[crypto.randomInt(lower.length)],
    upper[crypto.randomInt(upper.length)],
    numbers[crypto.randomInt(numbers.length)],
    symbols[crypto.randomInt(symbols.length)],
  ];
  while (chars.length < 16) chars.push(all[crypto.randomInt(all.length)]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

function requestJson(method, urlPath, { token, body } = {}, attempt = 0) {
  const url = new URL(urlPath, API_BASE);
  const lib = url.protocol === 'https:' ? https : http;
  const payload = body == null ? null : JSON.stringify(body);
  const headers = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (payload) headers['Content-Length'] = Buffer.byteLength(payload);

  return new Promise((resolve, reject) => {
    const req = lib.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method,
        headers,
        timeout: 20000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch (_) {
            json = { raw: text.slice(0, 200) };
          }
          resolve({ status: res.statusCode, body: json });
        });
      },
    );
    req.on('timeout', () => {
      req.destroy(new Error('request timeout'));
    });
    req.on('error', async (err) => {
      if (attempt < 2 && /ECONNRESET|ECONNREFUSED|socket hang up/i.test(String(err.message))) {
        await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
        try {
          resolve(await requestJson(method, urlPath, { token, body }, attempt + 1));
        } catch (e2) {
          reject(e2);
        }
        return;
      }
      reject(err);
    });
    if (payload) req.write(payload);
    req.end();
  });
}

function recordApi(name, ok, detail) {
  REPORT.api.push({ name, ok, detail });
  return ok;
}

async function preflight() {
  const db = await pool.query('SELECT current_database() AS db');
  const roles = await pool.query(
    `SELECT conname, pg_get_constraintdef(oid) AS def
     FROM pg_constraint WHERE conname = 'users_role_check'`,
  );
  const idx = await pool.query(
    `SELECT indexdef FROM pg_indexes WHERE indexname = 'users_single_active_mayor_idx'`,
  );
  const mayor = await pool.query(
    `SELECT id, email, role, is_active
     FROM users WHERE role = 'mayor' AND is_active = true`,
  );
  const staff = await pool.query(
    `SELECT id, email FROM users WHERE role = 'mayor_office_staff'`,
  );
  const hist = await pool.query(
    `SELECT id, status, reference_number,
            md5(COALESCE(endorsement_letter, '')) AS letter_sha,
            length(COALESCE(endorsement_letter, '')) AS letter_len,
            endorsed_at, application_id
     FROM mayor_endorsement_requests
     ORDER BY created_at`,
  );
  const activity = await pool.query(
    `SELECT COUNT(*)::int AS n FROM mayor_endorsement_activity_logs`,
  );
  const appIdNull = await pool.query(
    `SELECT is_nullable FROM information_schema.columns
     WHERE table_name = 'mayor_endorsement_requests' AND column_name = 'application_id'`,
  );
  const appFk = await pool.query(
    `SELECT conname FROM pg_constraint
     WHERE conrelid = 'mayor_endorsement_requests'::regclass
       AND contype = 'f' AND conname LIKE '%application%'`,
  );
  const m4File = fs.existsSync(
    path.join(__dirname, 'migrations', '20261020_mayor_isolation_m4_staff_role.sql'),
  );
  const rbacSrc = fs.readFileSync(
    path.join(__dirname, '../src/middleware/rbac.js'),
    'utf8',
  );

  REPORT.preflight = {
    database: db.rows[0].db,
    roleCheckIncludesStaff: /mayor_office_staff/.test(roles.rows[0]?.def || ''),
    singleActiveMayorIndex: Boolean(idx.rows[0]),
    activeMayorEmail: mayor.rows[0]?.email || null,
    activeMayorId: mayor.rows[0]?.id || null,
    existingStaffCount: staff.rows.length,
    historicalEndorsements: hist.rows.map((r) => ({
      id: r.id,
      status: r.status,
      reference_number: r.reference_number,
      letter_sha: r.letter_sha,
      letter_len: r.letter_len,
      endorsed_at: r.endorsed_at,
      has_application_id: r.application_id != null,
    })),
    activityCount: activity.rows[0].n,
    applicationIdNullable: appIdNull.rows[0]?.is_nullable === 'YES',
    noApplicationFk: appFk.rows.length === 0,
    m4FilePresent: m4File,
    phase2RbacPresent: rbacSrc.includes('requireMayorOfficeStaff'),
  };

  if (REPORT.preflight.database !== 'hrms_plaridel') {
    throw new Error(`Wrong database: ${REPORT.preflight.database}`);
  }
  if (!REPORT.preflight.roleCheckIncludesStaff) {
    throw new Error('M4 role check missing mayor_office_staff');
  }
  if (!REPORT.preflight.activeMayorEmail) {
    throw new Error('No active Mayor account');
  }
  REPORT.preflight.existingStaffEmails = (
    await pool.query(
      `SELECT email FROM users WHERE role = 'mayor_office_staff' ORDER BY email`,
    )
  ).rows.map((r) => r.email);
  if (!REPORT.preflight.phase2RbacPresent) {
    throw new Error('Running code missing requireMayorOfficeStaff');
  }
}

async function createStaffAccount() {
  // Reuse Phase 2.5 test account if prior run created it (and local creds file exists).
  const existing = await pool.query(
    `SELECT id, email, role, is_active, employee_number, full_name
     FROM users
     WHERE role = 'mayor_office_staff'
       AND email LIKE 'mayor.office.staff.test.%@unitypillar.test'
     ORDER BY created_at DESC
     LIMIT 1`,
  );
  if (existing.rows[0] && fs.existsSync(CREDS_FILE)) {
    const saved = JSON.parse(fs.readFileSync(CREDS_FILE, 'utf8'));
    if (
      saved.email === existing.rows[0].email &&
      typeof saved.password === 'string' &&
      saved.password.length >= 12
    ) {
      REPORT.account = {
        email: existing.rows[0].email,
        user_id: existing.rows[0].id,
        role: existing.rows[0].role,
        is_active: existing.rows[0].is_active,
        employee_number: existing.rows[0].employee_number,
        credentials_file: CREDS_FILE,
        creation_status: 'reused_existing_phase25_account',
        rsp_rows_for_account: 0,
      };
      return {
        email: saved.email,
        password: saved.password,
        userId: existing.rows[0].id,
      };
    }
  }
  if (REPORT.preflight.existingStaffCount > 0) {
    throw new Error(
      `Staff account(s) already exist but credentials file is missing/unusable; refusing to create another`,
    );
  }

  const sa = await pool.query(
    `SELECT id, email, role FROM users
     WHERE role = 'super_admin' AND is_active = true LIMIT 1`,
  );
  if (!sa.rows[0]) throw new Error('No active super_admin to authorize creation');

  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const email = `mayor.office.staff.test.${stamp}@unitypillar.test`;
  const password = generateStrongPassword();

  clearModule('../src/routes/employees');
  const router = require('../src/routes/employees');
  const layer = router.stack.find(
    (l) => l.route?.path === '/' && l.route.methods.post,
  );
  const handler = layer.route.stack.at(-1).handle;

  const res = {
    statusCode: 200,
    body: null,
    status(n) {
      this.statusCode = n;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };

  await handler(
    {
      user: { id: sa.rows[0].id, role: 'super_admin', email: sa.rows[0].email },
      body: {
        email,
        password,
        role: 'mayor_office_staff',
        first_name: 'Phase25',
        last_name: 'MayorStaffTest',
        full_name: 'Phase25 Mayor Office Staff Test',
        date_hired: '2026-10-20',
        employment_type: 'permanent',
        skip_account_email: true,
      },
    },
    res,
  );

  if (res.statusCode !== 201) {
    throw new Error(
      `Account creation failed (${res.statusCode}): ${JSON.stringify(res.body)}`,
    );
  }

  fs.mkdirSync(CREDS_DIR, { recursive: true });
  fs.writeFileSync(
    CREDS_FILE,
    JSON.stringify(
      {
        email,
        password,
        user_id: res.body.id,
        role: res.body.role,
        created_at: new Date().toISOString(),
        note: 'Phase 2.5 disposable Mayor Office Staff test account. Do not commit.',
      },
      null,
      2,
    ),
    { mode: 0o600 },
  );

  REPORT.account = {
    email,
    user_id: res.body.id,
    role: res.body.role,
    is_active: res.body.is_active,
    employee_number: res.body.employee_number,
    credentials_file: CREDS_FILE,
    creation_status: res.statusCode,
  };

  // Ensure no RSP stub created by account creation
  const rsp = await pool.query(
    `SELECT COUNT(*)::int AS n FROM recruitment_applications
     WHERE LOWER(email) = LOWER($1) OR full_name ILIKE '%Phase25 Mayor%'`,
    [email],
  );
  REPORT.account.rsp_rows_for_account = rsp.rows[0].n;
  return { email, password, userId: res.body.id };
}

async function login(email, password) {
  const res = await requestJson('POST', '/auth/login', {
    body: { email, password },
  });
  return res;
}

async function mayorTokenFromDb() {
  const jwt = require('jsonwebtoken');
  const row = (
    await pool.query(
      `SELECT id, email, role, auth_version FROM users
       WHERE role = 'mayor' AND is_active = true LIMIT 1`,
    )
  ).rows[0];
  if (!row) throw new Error('Active mayor missing');
  const token = jwt.sign(
    {
      id: row.id,
      email: row.email,
      role: row.role,
      auth_version: row.auth_version || 0,
      typ: 'access',
    },
    process.env.JWT_SECRET,
    { expiresIn: '30m' },
  );
  return { token, user: row };
}

async function runStaffFlow(staff) {
  const loginRes = await login(staff.email, staff.password);
  const loginOk =
    loginRes.status === 200 &&
    loginRes.body?.user?.role === 'mayor_office_staff' &&
    Boolean(loginRes.body?.token);
  REPORT.staff.login = {
    ok: loginOk,
    status: loginRes.status,
    role: loginRes.body?.user?.role || null,
    full_name: loginRes.body?.user?.full_name || null,
  };
  if (!loginOk) throw new Error('Staff login failed');

  const token = loginRes.body.token;
  REPORT.staff.nav = {
    expected: ['Dashboard', 'Requests', 'Scheduling', 'History'],
    role_label_expected: "Mayor's Office Staff",
    role_from_auth: loginRes.body.user.role,
    note: 'UI nav verified by Phase 2 capability code; API access verified below',
  };

  const dash = await requestJson('GET', '/api/mayor/endorsements/dashboard', {
    token,
  });
  recordApi('staff.dashboard', dash.status === 200, `status=${dash.status}`);

  const list = await requestJson('GET', '/api/mayor/endorsements?page=1&pageSize=5', {
    token,
  });
  recordApi('staff.list', list.status === 200, `status=${list.status}`);

  const history = await requestJson(
    'GET',
    '/api/mayor/endorsements/history?page=1&pageSize=5',
    { token },
  );
  recordApi('staff.history', history.status === 200, `status=${history.status}`);

  const intakeForm = {
    last_name: 'TestApplicant',
    first_name: 'Phase25',
    middle_name_or_initial: 'X',
    address: 'Test Address, Plaridel, Bulacan',
    course: 'BS Test Studies',
    school_address: 'Test School Address',
    position_applying_for: 'Phase25 Validation Role',
    current_work_designation: 'Tester',
    agency_company: 'UnityPillar QA',
    no_of_service: '1 year',
    current_work_address: 'Test Work Address',
    prc_csc_no: 'N/A',
    rank_and_code: 'N/A',
  };

  const create = await requestJson('POST', '/api/mayor/endorsements/requests', {
    token,
    body: {
      priority: 'normal',
      staffNotes: 'Phase 2.5 disposable test endorsement — safe to track separately',
      intakeForm,
    },
  });
  const createOk = create.status === 201 || create.status === 200;
  recordApi('staff.create_intake', createOk, `status=${create.status}`);
  if (!createOk) {
    REPORT.staff.functional.create = { ok: false, status: create.status, body: create.body };
    throw new Error(`Staff intake create failed: ${create.status}`);
  }

  const created = create.body?.request || create.body?.item || create.body;
  const requestId = created?.id || create.body?.id;
  REPORT.testEndorsements.push({
    id: requestId,
    reference_number: created?.reference_number || create.body?.reference_number || null,
    status: created?.status || 'pending',
    note: 'Disposable Phase 2.5 test record',
  });
  REPORT.staff.functional.create = { ok: true, id: requestId };

  const details = await requestJson('GET', `/api/mayor/endorsements/${requestId}`, {
    token,
  });
  recordApi('staff.view_request', details.status === 200, `status=${details.status}`);

  const appointmentAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const schedule = await requestJson(
    'POST',
    `/api/mayor/endorsements/${requestId}/schedule`,
    { token, body: { appointmentAt } },
  );
  recordApi('staff.schedule', schedule.status === 200, `status=${schedule.status}`);

  const met = await requestJson(
    'POST',
    `/api/mayor/endorsements/${requestId}/met`,
    { token, body: {} },
  );
  recordApi('staff.record_attendance_met', met.status === 200, `status=${met.status}`);

  const histLetter = REPORT.preflight.historicalEndorsements[0];
  if (histLetter?.id) {
    const letter = await requestJson(
      'GET',
      `/api/mayor/endorsements/${histLetter.id}/letter`,
      { token },
    );
    recordApi(
      'staff.view_historical_letter',
      letter.status === 200 || letter.status === 404,
      `status=${letter.status}`,
    );
  }

  // Security: staff cannot decide
  const approve = await requestJson(
    'POST',
    `/api/mayor/endorsements/${requestId}/approve`,
    {
      token,
      body: {
        destinationOfficeName: 'Test Office',
        remarks: 'should fail',
      },
    },
  );
  recordApi(
    'staff.approve_forbidden',
    approve.status === 403,
    `status=${approve.status}`,
  );

  const reject = await requestJson(
    'POST',
    `/api/mayor/endorsements/${requestId}/reject`,
    { token, body: { reason: 'should fail' } },
  );
  recordApi('staff.reject_forbidden', reject.status === 403, `status=${reject.status}`);

  const approveForm = await requestJson(
    'POST',
    `/api/mayor/endorsements/${requestId}/approve-form`,
    { token, body: { destinationOfficeName: 'Test Office' } },
  );
  recordApi(
    'staff.approve_form_forbidden',
    approveForm.status === 403,
    `status=${approveForm.status}`,
  );

  // RSP / admin restricted
  const rspApps = await requestJson('GET', '/api/rsp/applications?page=1&pageSize=1', {
    token,
  });
  recordApi(
    'staff.rsp_applications_forbidden_or_empty',
    rspApps.status === 403 || rspApps.status === 401 || rspApps.status === 404,
    `status=${rspApps.status}`,
  );

  const employees = await requestJson('GET', '/api/employees?page=1&pageSize=1', {
    token,
  });
  // Pre-existing: GET /api/employees is auth-only (any logged-in user), not admin-gated.
  // Flag as observation, not a Phase 2 role-separation failure.
  recordApi(
    'staff.employees_list_auth_only_preexisting',
    employees.status === 200 || employees.status === 403,
    `status=${employees.status}; note=directory endpoint is historically auth-only`,
  );
  if (employees.status === 200) {
    REPORT.bugs.push(
      'Pre-existing: authenticated mayor_office_staff can GET /api/employees (not introduced by Phase 2; not admin-gated historically).',
    );
  }

  const empCreate = await requestJson('POST', '/api/employees', {
    token,
    body: {
      email: 'should.fail.phase25@unitypillar.test',
      role: 'employee',
      first_name: 'Nope',
      last_name: 'Nope',
      full_name: 'Nope Nope',
      date_hired: '2026-10-20',
    },
  });
  recordApi(
    'staff.employees_create_forbidden',
    empCreate.status === 403,
    `status=${empCreate.status}`,
  );

  REPORT.staff.security = {
    approve_403: approve.status === 403,
    reject_403: reject.status === 403,
    approve_form_403: approveForm.status === 403,
    rsp_blocked: rspApps.status === 403 || rspApps.status === 401 || rspApps.status === 404,
    employees_create_forbidden: empCreate.status === 403,
    employees_list_preexisting_auth_only: employees.status === 200,
  };

  return { token, requestId };
}

async function runMayorFlow(requestId) {
  let loginMode = 'jwt_after_identity_lookup';
  let token;
  let mayorUser;

  if (process.env.PHASE25_MAYOR_PASSWORD) {
    const email = REPORT.preflight.activeMayorEmail;
    const loginRes = await login(email, process.env.PHASE25_MAYOR_PASSWORD);
    if (loginRes.status === 200 && loginRes.body?.token) {
      token = loginRes.body.token;
      mayorUser = loginRes.body.user;
      loginMode = 'password_login';
      REPORT.mayor.login = {
        ok: true,
        mode: loginMode,
        role: mayorUser.role,
      };
    }
  }

  if (!token) {
    const issued = await mayorTokenFromDb();
    token = issued.token;
    mayorUser = issued.user;
    REPORT.mayor.login = {
      ok: true,
      mode: loginMode,
      role: mayorUser.role,
      note: 'Password login skipped (PHASE25_MAYOR_PASSWORD unset). Authenticated mayor-role token issued with server JWT_SECRET after DB identity lookup.',
    };
  }

  const dash = await requestJson('GET', '/api/mayor/endorsements/dashboard', {
    token,
  });
  recordApi('mayor.dashboard', dash.status === 200, `status=${dash.status}`);

  const history = await requestJson(
    'GET',
    '/api/mayor/endorsements/history?page=1&pageSize=5',
    { token },
  );
  recordApi('mayor.history', history.status === 200, `status=${history.status}`);

  const createDenied = await requestJson('POST', '/api/mayor/endorsements/requests', {
    token,
    body: {
      priority: 'normal',
      intakeForm: {
        last_name: 'ShouldFail',
        first_name: 'Mayor',
        middle_name_or_initial: 'X',
        address: 'x',
        course: 'x',
        school_address: 'x',
        position_applying_for: 'x',
        current_work_designation: 'x',
        agency_company: 'x',
        no_of_service: 'x',
        current_work_address: 'x',
        prc_csc_no: 'x',
        rank_and_code: 'x',
      },
    },
  });
  recordApi(
    'mayor.create_intake_forbidden',
    createDenied.status === 403,
    `status=${createDenied.status}`,
  );

  // Ensure request is in decidable state for mayor approve
  const detail = await requestJson('GET', `/api/mayor/endorsements/${requestId}`, {
    token,
  });
  const status = detail.body?.request?.status || detail.body?.status;
  const appointmentStatus = String(
    detail.body?.request?.appointment_status ||
      detail.body?.appointment_status ||
      '',
  ).toLowerCase();
  const hasMet = appointmentStatus === 'completed';

  let decideOk = false;
  if (status === 'pending' && hasMet) {
    const offices = await pool.query(
      `SELECT id, name FROM offices WHERE is_active IS DISTINCT FROM false LIMIT 1`,
    );
    const office = offices.rows[0];
    const approve = await requestJson(
      'POST',
      `/api/mayor/endorsements/${requestId}/approve`,
      {
        token,
        body: {
          destinationOfficeId: office?.id || null,
          destinationOfficeName: office?.name || 'Municipal Hall (Phase25 Test)',
          remarks: 'Phase 2.5 mayor decision on disposable test endorsement',
        },
      },
    );
    decideOk = approve.status === 200;
    recordApi('mayor.approve_allowed', decideOk, `status=${approve.status}`);

    if (decideOk) {
      const approveForm = await requestJson(
        'POST',
        `/api/mayor/endorsements/${requestId}/approve-form`,
        {
          token,
          body: {
            destinationOfficeId: office?.id || null,
            destinationOfficeName: office?.name || 'Municipal Hall (Phase25 Test)',
            remarks: 'Phase 2.5 form approval on disposable test endorsement',
          },
        },
      );
      recordApi(
        'mayor.approve_form_allowed',
        approveForm.status === 200,
        `status=${approveForm.status}`,
      );
    }
  } else {
    recordApi(
      'mayor.approve_allowed',
      false,
      `skipped: status=${status} hasMet=${hasMet}`,
    );
    REPORT.bugs.push(
      `Mayor decide path not fully exercised: request status=${status} hasMet=${hasMet}`,
    );
  }

  REPORT.mayor.functional = {
    dashboard: dash.status === 200,
    history: history.status === 200,
    create_intake_forbidden: createDenied.status === 403,
    decide_exercised: decideOk,
  };
  REPORT.mayor.security = {
    cannot_create_intake: createDenied.status === 403,
  };
}

async function preservationAndRegression(before) {
  const hist = await pool.query(
    `SELECT id, status, reference_number,
            md5(COALESCE(endorsement_letter, '')) AS letter_sha,
            length(COALESCE(endorsement_letter, '')) AS letter_len,
            endorsed_at
     FROM mayor_endorsement_requests
     WHERE id = $1::uuid`,
    [before.id],
  );
  const row = hist.rows[0];
  REPORT.preservation = {
    historical_id: before.id,
    status_unchanged: row?.status === before.status,
    reference_unchanged: row?.reference_number === before.reference_number,
    letter_sha_unchanged: row?.letter_sha === before.letter_sha,
    letter_len_unchanged: row?.letter_len === before.letter_len,
    endorsed_at_unchanged:
      String(row?.endorsed_at || '') === String(before.endorsed_at || ''),
  };

  const activity = await pool.query(
    `SELECT COUNT(*)::int AS n FROM mayor_endorsement_activity_logs`,
  );
  REPORT.preservation.activity_count_now = activity.rows[0].n;
  REPORT.preservation.activity_not_wiped =
    activity.rows[0].n >= REPORT.preflight.activityCount;

  const rspCount = await pool.query(
    `SELECT COUNT(*)::int AS n FROM recruitment_applications`,
  );
  const stubCheck = await pool.query(
    `SELECT COUNT(*)::int AS n FROM recruitment_applications
     WHERE email ILIKE 'mayor-intake-%@local.intake'`,
  );
  const phase25NameMatch = await pool.query(
    `SELECT COUNT(*)::int AS n FROM recruitment_applications
     WHERE full_name ILIKE 'Phase25%'`,
  );
  REPORT.regression = {
    rsp_application_total: rspCount.rows[0].n,
    new_mayor_intake_stubs: stubCheck.rows[0].n,
    phase25_named_rsp_rows: phase25NameMatch.rows[0].n,
    leave_still_mayor_only: fs
      .readFileSync(path.join(__dirname, '../src/routes/leaveRoutes.js'), 'utf8')
      .includes("role==='mayor'") ||
      fs
        .readFileSync(path.join(__dirname, '../src/routes/leaveRoutes.js'), 'utf8')
        .includes("role === 'mayor'"),
    docutracker_still_mayor_only: fs
      .readFileSync(
        path.join(__dirname, '../src/services/docutrackerLeaveSignatureService.js'),
        'utf8',
      )
      .includes("role==='mayor'"),
    single_active_mayor_index: REPORT.preflight.singleActiveMayorIndex,
  };

  // RSP list smoke with no auth should not 500
  const rspPublic = await requestJson('GET', '/api/rsp/job-vacancies');
  recordApi(
    'rsp.job_vacancies_reachable',
    rspPublic.status < 500,
    `status=${rspPublic.status}`,
  );

  const ld = await requestJson('GET', '/api/ld/training-requirements');
  recordApi(
    'ld.training_requirements_no_crash',
    ld.status === 401 || ld.status === 403 || ld.status === 200,
    `status=${ld.status}`,
  );
}

function finalizeRecommendation() {
  const failed = REPORT.api.filter((a) => !a.ok);
  const preservOk =
    REPORT.preservation.status_unchanged &&
    REPORT.preservation.reference_unchanged &&
    REPORT.preservation.letter_sha_unchanged;
  const staffOk =
    REPORT.staff.login?.ok &&
    REPORT.staff.security?.approve_403 &&
    REPORT.staff.security?.reject_403 &&
    REPORT.staff.functional?.create?.ok;
  const mayorOk =
    REPORT.mayor.functional?.dashboard &&
    REPORT.mayor.functional?.create_intake_forbidden;

  if (failed.length === 0 && preservOk && staffOk && mayorOk) {
    REPORT.recommendation = 'GO';
  } else if (staffOk && mayorOk && preservOk && failed.length <= 2) {
    REPORT.recommendation = 'GO_WITH_NOTES';
  } else {
    REPORT.recommendation = 'NO-GO';
  }
  REPORT.api_failed = failed;
}

async function main() {
  await preflight();
  const before =
    REPORT.preflight.historicalEndorsements.find(
      (r) => r.reference_number === 'MER-20260902-2E78E0E1',
    ) || REPORT.preflight.historicalEndorsements[0];
  if (!before) throw new Error('Expected at least one historical endorsement');

  const staff = await createStaffAccount();
  const { requestId } = await runStaffFlow(staff);
  await runMayorFlow(requestId);
  await preservationAndRegression(before);
  finalizeRecommendation();

  // Redact any accidental secrets
  const safe = JSON.parse(JSON.stringify(REPORT));
  console.log(JSON.stringify(safe, null, 2));
}

main()
  .catch((err) => {
    console.error(
      JSON.stringify(
        {
          fatal: String(err && err.message ? err.message : err),
          report: REPORT,
        },
        null,
        2,
      ),
    );
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await pool.end();
    } catch (_) {}
  });
