const { Pool } = require('pg');
const {buildPoolOptions} = require('./databasePoolOptions');

const pool = new Pool(buildPoolOptions());

// Test connection on first use
pool.on('connect', () => {
  console.log('[db] New client connected to PostgreSQL');
});

pool.on('error', (err) => {
  console.error('[db] Unexpected error on idle client', err);
});

module.exports = { pool };
