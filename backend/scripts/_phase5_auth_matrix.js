/** Phase 5 read-only auth matrix via minted JWTs (no new endorsement rows). */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const jwt = require('jsonwebtoken');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { pool } = require('../src/config/db');

const CREDS = path.join(
  process.env.USERPROFILE || process.env.HOME || __dirname,
  'Backups',
  'hrms_plaridel_isolation',
  'phase25_mayor_office_staff_creds.json',
);

function request(method, urlPath, token, body) {
  const data = body == null ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: 3000,
        path: urlPath,
        method,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
        },
        timeout: 15000,
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          let j = null;
          try {
            j = JSON.parse(raw || 'null');
          } catch {
            j = { raw: raw.slice(0, 200) };
          }
          resolve({ status: res.statusCode, j });
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function mint(row) {
  return jwt.sign(
    {
      id: row.id,
      email: row.email,
      role: row.role,
      auth_version: row.auth_version || 0,
      typ: 'access',
    },
    process.env.JWT_SECRET,
    { expiresIn: '15m' },
  );
}

function summarize(v) {
  if (!v) return null;
  return {
    status: v.status,
    error: v.j?.error || null,
    total: v.j?.pagination?.total ?? v.j?.totals?.total_requests ?? null,
    endorsed: v.j?.summary?.endorsed_count ?? v.j?.totals?.total_endorsed ?? null,
    employee_keys: Array.isArray(v.j?.employees)
      ? Object.keys(v.j.employees[0] || {})
      : Array.isArray(v.j)
        ? Object.keys(v.j[0] || {})
        : null,
  };
}

async function main() {
  const staffCreds = JSON.parse(fs.readFileSync(CREDS, 'utf8'));
  const staffLogin = await request('POST', '/auth/login', null, {
    email: staffCreds.email,
    password: staffCreds.password,
  });
  const staffTok = staffLogin.j?.token;

  const mayor = (
    await pool.query(
      `SELECT id, email, role, auth_version FROM users
       WHERE role = 'mayor' AND is_active = true LIMIT 1`,
    )
  ).rows[0];
  const employee = (
    await pool.query(
      `SELECT id, email, role, auth_version FROM users
       WHERE role = 'employee' AND is_active = true LIMIT 1`,
    )
  ).rows[0];
  const admin = (
    await pool.query(
      `SELECT id, email, role, auth_version FROM users
       WHERE role = 'admin' AND is_active = true LIMIT 1`,
    )
  ).rows[0];

  const mayorTok = mint(mayor);
  const empTok = employee ? mint(employee) : null;
  const adminTok = admin ? mint(admin) : null;

  const checks = {
    mayor_create_intake: await request('POST', '/api/mayor/endorsements/requests', mayorTok, {
      priority: 'normal',
      intakeForm: { first_name: 'X' },
    }),
    mayor_dashboard: await request('GET', '/api/mayor/endorsements/dashboard', mayorTok),
    mayor_meeting_approve_missing: await request(
      'POST',
      '/api/mayor/endorsements/00000000-0000-0000-0000-000000000001/meeting/approve',
      mayorTok,
      {},
    ),
    mayor_endorse_missing: await request(
      'POST',
      '/api/mayor/endorsements/00000000-0000-0000-0000-000000000001/endorse',
      mayorTok,
      {},
    ),
    mayor_employees: await request('GET', '/api/employees?limit=1', mayorTok),
    employee_mayor_dashboard: empTok
      ? await request('GET', '/api/mayor/endorsements/dashboard', empTok)
      : null,
    employee_employees: empTok
      ? await request('GET', '/api/employees?limit=1', empTok)
      : null,
    admin_mayor_dashboard: adminTok
      ? await request('GET', '/api/mayor/endorsements/dashboard', adminTok)
      : null,
    staff_history: await request(
      'GET',
      '/api/mayor/endorsements/history?page=1&page_size=5',
      staffTok,
    ),
    staff_history_include_test: await request(
      'GET',
      '/api/mayor/endorsements/history?include_test=1&page=1&page_size=10',
      staffTok,
    ),
    staff_reports_monthly: await request(
      'GET',
      '/api/mayor/endorsements/reports?period=monthly',
      staffTok,
    ),
  };

  const summary = {};
  for (const [k, v] of Object.entries(checks)) summary[k] = summarize(v);

  console.log(
    JSON.stringify(
      {
        mayor_email: mayor.email,
        employee_email: employee?.email || null,
        staff_login_status: staffLogin.status,
        summary,
      },
      null,
      2,
    ),
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
