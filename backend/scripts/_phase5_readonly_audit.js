/**
 * Phase 5 — read-only Mayor module validation against the live DB/API.
 * Does not mutate data, run migrations, or delete records.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const https = require('node:https');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { pool } = require('../src/config/db');
const {
  fetchDashboardMetrics,
  fetchEndorsementReport,
  parseReportPeriod,
  MANILA_TZ,
} = require('../src/services/mayorEndorsementStats');

const API_BASE = process.env.PHASE25_API_BASE || 'http://127.0.0.1:3000';
const CREDS_FILE = path.join(
  process.env.USERPROFILE || process.env.HOME || __dirname,
  'Backups',
  'hrms_plaridel_isolation',
  'phase25_mayor_office_staff_creds.json',
);

const report = {
  database: {},
  migrations: {},
  is_test: {},
  independence: {},
  dashboard: {},
  reports: {},
  api_auth: {},
  employees_endpoint: {},
  e2e: {},
  notes: [],
};

function requestJson(method, urlPath, { token, body } = {}) {
  const url = new URL(urlPath, API_BASE);
  const lib = url.protocol === 'https:' ? https : http;
  const payload = body == null ? null : JSON.stringify(body);
  const headers = { Accept: 'application/json', 'Content-Type': 'application/json' };
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
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          let json = null;
          try {
            json = raw ? JSON.parse(raw) : null;
          } catch {
            json = { _raw: raw.slice(0, 300) };
          }
          resolve({ status: res.statusCode, json });
        });
      },
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('timeout'));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

async function login(email, password) {
  const res = await requestJson('POST', '/auth/login', {
    body: { email, password },
  });
  const token =
    res.json?.token ||
    res.json?.accessToken ||
    res.json?.access_token ||
    res.json?.data?.token;
  return { status: res.status, token, role: res.json?.user?.role || res.json?.role };
}

async function main() {
  const dbInfo = await pool.query(`
    SELECT current_database() AS database,
           current_user AS db_user,
           inet_server_addr()::text AS server_addr,
           version() AS version
  `);
  report.database = {
    ...dbInfo.rows[0],
    env_host: (() => {
      try {
        return new URL(process.env.DATABASE_URL).hostname;
      } catch {
        return null;
      }
    })(),
    timezone_check: MANILA_TZ,
  };

  // Schema / migration fingerprints (read-only)
  const cols = await pool.query(`
    SELECT column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'mayor_endorsement_requests'
    ORDER BY ordinal_position
  `);
  const colSet = new Set(cols.rows.map((r) => r.column_name));
  report.migrations = {
    m1_meeting_columns: {
      meeting_request_status: colSet.has('meeting_request_status'),
      meeting_proposed_at: colSet.has('meeting_proposed_at'),
      meeting_purpose: colSet.has('meeting_purpose'),
      meeting_decision: colSet.has('meeting_decision'),
      meeting_decided_at: colSet.has('meeting_decided_at'),
    },
    m2_isolation_fields: {
      applicant_full_name: colSet.has('applicant_full_name'),
      reference_number: colSet.has('reference_number'),
      intake_form: colSet.has('intake_form'),
    },
    m3_fk_to_recruitment: null,
    m4_staff_role: null,
    is_test_migration: {
      column_present: colSet.has('is_test'),
      column_meta: cols.rows.find((r) => r.column_name === 'is_test') || null,
    },
  };

  const fk = await pool.query(`
    SELECT con.conname, pg_get_constraintdef(con.oid) AS def
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'mayor_endorsement_requests'
      AND con.contype = 'f'
  `);
  report.migrations.m3_fk_to_recruitment = {
    foreign_keys: fk.rows,
    has_fk_to_recruitment_applications: fk.rows.some((r) =>
      /recruitment_applications/i.test(r.def),
    ),
  };

  const roleCheck = await pool.query(`
    SELECT pg_get_constraintdef(con.oid) AS def
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'users'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%role%'
  `);
  report.migrations.m4_staff_role = {
    users_role_allows_mayor_office_staff: roleCheck.rows.some((r) =>
      /mayor_office_staff/i.test(r.def),
    ),
    role_constraints: roleCheck.rows.map((r) => r.def),
  };

  const knownTestIds = [
    'bf301de0-0461-45a6-93ff-f350791856c4',
    'c77aa381-4c9c-494d-8e10-f8e282d4fac4',
    '1dcdeb69-f310-4f01-bfed-c06c2f304855',
  ];
  if (colSet.has('is_test')) {
    const testFlags = await pool.query(
      `
      SELECT id::text, reference_number, status, is_test,
             left(COALESCE(endorsement_letter,''), 40) AS letter_prefix
      FROM mayor_endorsement_requests
      WHERE id = ANY($1::uuid[])
      ORDER BY id
    `,
      [knownTestIds],
    );
    const counts = await pool.query(`
      SELECT
        COUNT(*)::int AS total,
        COUNT(*) FILTER (WHERE COALESCE(is_test,false)=true)::int AS test_rows,
        COUNT(*) FILTER (WHERE COALESCE(is_test,false)=false)::int AS official_rows,
        COUNT(*) FILTER (WHERE status='endorsed')::int AS endorsed_all,
        COUNT(*) FILTER (WHERE status='endorsed' AND COALESCE(is_test,false)=false)::int AS endorsed_official,
        COUNT(*) FILTER (WHERE endorsement_letter IS NOT NULL AND length(endorsement_letter)>0)::int AS letters_present
      FROM mayor_endorsement_requests
    `);
    report.is_test = {
      known_phase25_rows: testFlags.rows,
      all_known_flagged:
        testFlags.rows.length === 3 && testFlags.rows.every((r) => r.is_test === true),
      counts: counts.rows[0],
    };
  } else {
    report.is_test = { column_present: false, note: 'is_test column missing — migration not applied' };
  }

  // Independence from RSP
  const orphan = await pool.query(`
    SELECT
      COUNT(*)::int AS total_mer,
      COUNT(*) FILTER (WHERE application_id IS NULL)::int AS null_application_id,
      COUNT(*) FILTER (
        WHERE application_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM recruitment_applications ra WHERE ra.id = mer.application_id
          )
      )::int AS dangling_application_id
    FROM mayor_endorsement_requests mer
  `);
  report.independence = {
    ...orphan.rows[0],
    fk_to_ra: report.migrations.m3_fk_to_recruitment.has_fk_to_recruitment_applications,
    note:
      'Independence OK if no FK to recruitment_applications; dangling/null application_id expected for staff intake.',
  };

  const legacy = await pool.query(`
    SELECT COUNT(*)::int AS legacy_scheduled_without_meeting_approval
    FROM mayor_endorsement_requests
    WHERE COALESCE(appointment_status,'none') = 'scheduled'
      AND COALESCE(meeting_request_status,'none') = 'none'
  `);
  report.independence.legacy_scheduled_without_meeting_approval =
    legacy.rows[0].legacy_scheduled_without_meeting_approval;

  // Dashboard vs raw SQL cross-check
  const metricsOfficial = await fetchDashboardMetrics(pool, { includeTest: false });
  const metricsWithTest = await fetchDashboardMetrics(pool, { includeTest: true });
  const rawEndorse = await pool.query(`
    SELECT COUNT(*)::int AS c
    FROM mayor_endorsement_requests
    WHERE status = 'endorsed' AND COALESCE(is_test,false) = false
  `);
  const meetingApprovedNotEndorsed = await pool.query(`
    SELECT COUNT(*)::int AS c
    FROM mayor_endorsement_requests
    WHERE meeting_request_status = 'approved'
      AND status <> 'endorsed'
      AND COALESCE(is_test,false) = false
  `);
  report.dashboard = {
    week_boundary: metricsOfficial.week_boundary,
    timezone: metricsOfficial.timezone,
    official_summary: metricsOfficial.summary,
    with_test_endorsed: metricsWithTest.summary.endorsed_count,
    official_endorsed_matches_sql:
      metricsOfficial.summary.endorsed_count === rawEndorse.rows[0].c,
    meeting_approved_but_not_endorsed: meetingApprovedNotEndorsed.rows[0].c,
    note: 'Meeting-approved non-endorsed rows must not inflate endorsed_count.',
  };

  // Reports
  const periods = {};
  for (const period of ['daily', 'weekly', 'monthly']) {
    const r = await fetchEndorsementReport(pool, { period });
    periods[period] = {
      title: r.report_title,
      reporting_period: r.reporting_period,
      totals: r.totals,
      row_count: (r.rows || []).length,
      includes_test_rows: (r.rows || []).some((x) => x.is_test),
    };
  }
  const custom = await fetchEndorsementReport(pool, {
    period: 'custom',
    from_date: '2026-01-01',
    to_date: '2026-12-31',
  });
  periods.custom_2026 = {
    title: custom.report_title,
    reporting_period: custom.reporting_period,
    totals: custom.totals,
    row_count: (custom.rows || []).length,
    includes_test_rows: (custom.rows || []).some((x) => x.is_test),
  };
  const customWithTest = await fetchEndorsementReport(pool, {
    period: 'custom',
    from_date: '2026-01-01',
    to_date: '2026-12-31',
    include_test: '1',
  });
  periods.custom_2026_with_test = {
    totals: customWithTest.totals,
    row_count: (customWithTest.rows || []).length,
    includes_test_rows: (customWithTest.rows || []).some((x) => x.is_test),
  };
  report.reports = {
    parse_custom_error: parseReportPeriod({ period: 'custom' }).error || null,
    periods,
  };

  // Manila Monday week bound sanity
  const bounds = await pool.query(`
    SELECT
      to_char((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date, 'YYYY-MM-DD') AS manila_today,
      to_char(date_trunc('week', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'))::date, 'YYYY-MM-DD') AS week_start,
      extract(dow FROM date_trunc('week', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'))::date)::int AS week_start_dow
  `);
  report.reports.manila_bounds = {
    ...bounds.rows[0],
    monday_expected_dow_is_1: Number(bounds.rows[0].week_start_dow) === 1,
  };

  // API auth matrix using Phase 2.5 creds if present + employee/admin probes
  let staffCreds = null;
  if (fs.existsSync(CREDS_FILE)) {
    staffCreds = JSON.parse(fs.readFileSync(CREDS_FILE, 'utf8'));
  }
  report.api_auth.creds_file_present = !!staffCreds;

  const authMatrix = {};
  if (staffCreds?.email && staffCreds?.password) {
    const staffLogin = await login(staffCreds.email, staffCreds.password);
    authMatrix.staff_login = { status: staffLogin.status, role: staffLogin.role, hasToken: !!staffLogin.token };
    if (staffLogin.token) {
      const t = staffLogin.token;
      authMatrix.staff = {
        dashboard: await requestJson('GET', '/api/mayor/endorsements/dashboard', { token: t }),
        // Incomplete intake must 400 (authorized) without inserting a row.
        create_request_probe: await requestJson('POST', '/api/mayor/endorsements/requests', {
          token: t,
          body: {
            priority: 'normal',
            intakeForm: { first_name: 'Phase5' },
          },
        }),
        meeting_approve: await requestJson(
          'POST',
          '/api/mayor/endorsements/00000000-0000-0000-0000-000000000001/meeting/approve',
          { token: t, body: {} },
        ),
        endorse: await requestJson(
          'POST',
          '/api/mayor/endorsements/00000000-0000-0000-0000-000000000001/endorse',
          { token: t, body: {} },
        ),
        employees: await requestJson('GET', '/api/employees?limit=2', { token: t }),
      };
      // strip large bodies
      for (const k of Object.keys(authMatrix.staff)) {
        const r = authMatrix.staff[k];
        authMatrix.staff[k] = {
          status: r.status,
          error: r.json?.error || null,
          keys: r.json && typeof r.json === 'object' ? Object.keys(r.json).slice(0, 8) : null,
          employee_sample_keys:
            Array.isArray(r.json?.employees)
              ? Object.keys(r.json.employees[0] || {})
              : Array.isArray(r.json)
                ? Object.keys(r.json[0] || {})
                : null,
        };
      }
    }
  } else {
    report.notes.push('Phase 2.5 staff creds file missing — API staff matrix skipped');
  }

  // Mayor login from same file if present
  if (staffCreds?.mayor_email && staffCreds?.mayor_password) {
    const mayorLogin = await login(staffCreds.mayor_email, staffCreds.mayor_password);
    authMatrix.mayor_login = { status: mayorLogin.status, role: mayorLogin.role, hasToken: !!mayorLogin.token };
    if (mayorLogin.token) {
      const t = mayorLogin.token;
      authMatrix.mayor = {
        create_request: await requestJson('POST', '/api/mayor/endorsements/requests', {
          token: t,
          body: { priority: 'normal', intakeForm: { first_name: 'X', last_name: 'Y' } },
        }),
        dashboard: await requestJson('GET', '/api/mayor/endorsements/dashboard', { token: t }),
        meeting_approve_missing: await requestJson(
          'POST',
          '/api/mayor/endorsements/00000000-0000-0000-0000-000000000001/meeting/approve',
          { token: t, body: {} },
        ),
        employees: await requestJson('GET', '/api/employees?limit=2', { token: t }),
      };
      for (const k of Object.keys(authMatrix.mayor)) {
        const r = authMatrix.mayor[k];
        authMatrix.mayor[k] = {
          status: r.status,
          error: r.json?.error || null,
          employee_sample_keys:
            Array.isArray(r.json?.employees)
              ? Object.keys(r.json.employees[0] || {})
              : Array.isArray(r.json)
                ? Object.keys(r.json[0] || {})
                : null,
        };
      }
    }
  } else {
    // try locate a mayor user email only (no password) for inventory
    const mayorUsers = await pool.query(`
      SELECT id::text, email, role, is_active
      FROM users
      WHERE role IN ('mayor','mayor_office_staff')
      ORDER BY role, email
      LIMIT 10
    `);
    authMatrix.mayor_accounts_inventory = mayorUsers.rows.map((r) => ({
      id: r.id,
      email: r.email,
      role: r.role,
      is_active: r.is_active,
    }));
    report.notes.push('Mayor password not in creds file — mayor API matrix limited');
  }

  // Unauthenticated + wrong-role probes
  authMatrix.unauthenticated_dashboard = await requestJson(
    'GET',
    '/api/mayor/endorsements/dashboard',
  );
  authMatrix.unauthenticated_employees = await requestJson('GET', '/api/employees?limit=1');

  // Employee role probe if we can find a non-mayor employee password in env
  if (process.env.PHASE5_EMPLOYEE_EMAIL && process.env.PHASE5_EMPLOYEE_PASSWORD) {
    const emp = await login(
      process.env.PHASE5_EMPLOYEE_EMAIL,
      process.env.PHASE5_EMPLOYEE_PASSWORD,
    );
    authMatrix.employee_login = { status: emp.status, role: emp.role, hasToken: !!emp.token };
    if (emp.token) {
      authMatrix.employee_mayor_dashboard = await requestJson(
        'GET',
        '/api/mayor/endorsements/dashboard',
        { token: emp.token },
      );
      authMatrix.employee_employees = await requestJson('GET', '/api/employees?limit=2', {
        token: emp.token,
      });
      authMatrix.employee_mayor_dashboard = {
        status: authMatrix.employee_mayor_dashboard.status,
        error: authMatrix.employee_mayor_dashboard.json?.error || null,
      };
      const er = authMatrix.employee_employees;
      authMatrix.employee_employees = {
        status: er.status,
        employee_sample_keys: Array.isArray(er.json?.employees)
          ? Object.keys(er.json.employees[0] || {})
          : Array.isArray(er.json)
            ? Object.keys(er.json[0] || {})
            : null,
      };
    }
  }

  report.api_auth.matrix = authMatrix;

  // Letter preservation sample (no content dump)
  const letters = await pool.query(`
    SELECT id::text, reference_number, status,
           length(endorsement_letter) AS letter_len,
           endorsed_at, rejected_at
    FROM mayor_endorsement_requests
    WHERE endorsement_letter IS NOT NULL AND length(endorsement_letter) > 0
    ORDER BY COALESCE(endorsed_at, rejected_at, submitted_at) DESC NULLS LAST
    LIMIT 5
  `);
  report.independence.letter_samples = letters.rows;

  // Status distribution
  const statusDist = await pool.query(`
    SELECT status, COUNT(*)::int AS c
    FROM mayor_endorsement_requests
    WHERE COALESCE(is_test,false)=false
    GROUP BY status
    ORDER BY status
  `);
  report.dashboard.status_distribution_official = statusDist.rows;

  console.log(JSON.stringify(report, null, 2));
}

main()
  .catch((err) => {
    console.error('PHASE5_AUDIT_FAILED', err);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await pool.end();
    } catch {
      /* ignore */
    }
  });
