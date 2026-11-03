'use strict';
require('dotenv').config();
const http = require('http');

function login(email, password) {
  const body = JSON.stringify({ email, password });
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: 3000,
        path: '/auth/login',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () =>
          resolve({
            status: res.statusCode,
            role: (() => {
              try {
                return JSON.parse(data).user?.role || JSON.parse(data).role;
              } catch {
                return null;
              }
            })(),
            name: (() => {
              try {
                const j = JSON.parse(data);
                return j.user?.full_name || j.full_name || null;
              } catch {
                return null;
              }
            })(),
          }),
        );
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

(async () => {
  const r = await login('dzapitan@gmail.com', 'admin123');
  console.log(JSON.stringify(r));
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
