const { Pool } = require('pg');

// Optional: raise when API runs on Kamatera/VPS and PostgreSQL is over VPN (Tailscale, etc.)
const connectionTimeoutMillis = parseInt(process.env.PG_CONNECTION_TIMEOUT_MS || '10000', 10);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: parseInt(process.env.PG_POOL_MAX || '20', 10),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: Number.isFinite(connectionTimeoutMillis) ? connectionTimeoutMillis : 10000,
});

// Test connection on first use
pool.on('connect', () => {
  console.log('[db] New client connected to PostgreSQL');
});

pool.on('error', (err) => {
  console.error('[db] Unexpected error on idle client', err);
});

module.exports = { pool };
