/**
 * Launch API against .env.acceptance (isolated staging DB / port 3001).
 * Does not modify operational .env or hrms_plaridel.
 */
'use strict';

const path = require('path');
const dotenv = require('dotenv');

const acceptanceEnv = path.join(__dirname, '..', '.env.acceptance');
const loaded = dotenv.config({ path: acceptanceEnv, override: true });
if (loaded.error) {
  console.error('Missing .env.acceptance — generate it before starting.');
  process.exit(1);
}

const dbUrl = process.env.DATABASE_URL || '';
if (!/\/hrms_plaridel_acceptance(\?|$)/.test(dbUrl)) {
  console.error('Refusing to start: DATABASE_URL is not hrms_plaridel_acceptance');
  process.exit(1);
}

process.env.PORT = process.env.PORT || '3001';

// Prevent src/index.js dotenv(override:true on .env) from clobbering staging.
const origConfig = dotenv.config.bind(dotenv);
dotenv.config = (opts = {}) => {
  if (opts && opts.path && String(opts.path).replace(/\\/g, '/').endsWith('/.env')) {
    return origConfig({ path: acceptanceEnv, override: true });
  }
  return origConfig({ ...opts, path: acceptanceEnv, override: true });
};

require('../src/index.js');
