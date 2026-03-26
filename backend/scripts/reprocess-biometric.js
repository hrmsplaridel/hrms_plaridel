/**
 * Reprocess biometric logs into dtr_daily_summary.
 * Usage: node scripts/reprocess-biometric.js [email] [password]
 * Example: node scripts/reprocess-biometric.js admin@example.com yourpassword
 *
 * If email/password omitted, uses ADMIN_EMAIL and ADMIN_PASSWORD from .env (if set).
 */
require('dotenv').config();
const http = require('http');
const https = require('https');

const BASE = process.env.API_BASE_URL || 'http://localhost:3000';
const email = process.argv[2] || process.env.ADMIN_EMAIL;
const password = process.argv[3] || process.env.ADMIN_PASSWORD;

if (!email || !password) {
  console.error('Usage: node scripts/reprocess-biometric.js <email> <password>');
  console.error('Or set ADMIN_EMAIL and ADMIN_PASSWORD in .env');
  process.exit(1);
}

function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const opts = {
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: { 'Content-Type': 'application/json' },
    };
    if (token) opts.headers['Authorization'] = `Bearer ${token}`;
    const lib = url.protocol === 'https:' ? https : http;
    const req = lib.request(opts, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data || '{}') });
        } catch {
          resolve({ status: res.statusCode, data: { raw: data } });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function main() {
  console.log('Logging in...');
  const login = await request('POST', '/auth/login', { email, password });
  if (login.status !== 200 || !login.data.token) {
    console.error('Login failed:', login.data);
    process.exit(1);
  }
  const token = login.data.token;
  console.log('Logged in. Calling reprocess...');
  const proc = await request('POST', '/api/biometric-attendance-logs/process', {}, token);
  if (proc.status >= 400) {
    console.error('Reprocess failed:', proc.data);
    process.exit(1);
  }
  console.log('Result:', proc.data);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
