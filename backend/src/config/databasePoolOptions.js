function getStatementDeadlineMs(env = process.env) {
  const raw = String(env.PG_STATEMENT_TIMEOUT_MS ?? '').trim();
  const value = Number(raw);
  return /^\d+$/.test(raw) && Number.isInteger(value) && value >= 100 && value <= 600000
    ? value : 30000;
}

function buildPoolOptions(env = process.env) {
  const timeoutMs = getStatementDeadlineMs(env);
  const connectionTimeoutMillis = parseInt(env.PG_CONNECTION_TIMEOUT_MS || '10000', 10);
  return {
    connectionString: env.DATABASE_URL,
    max: parseInt(env.PG_POOL_MAX || '20', 10),
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: Number.isFinite(connectionTimeoutMillis) ? connectionTimeoutMillis : 10000,
    // pg-pool waits for verify before handing a new connection to application code.
    // A configuration failure discards the client, rather than running unbounded SQL.
    verify(client, done) {
      client.query({
        text: `SELECT set_config('statement_timeout',
                 CASE WHEN setting::bigint = 0 THEN $1::text
                      ELSE LEAST(setting::bigint, $1::bigint)::text END, false)
                 FROM pg_settings WHERE name = 'statement_timeout'`,
        values: [String(timeoutMs)],
        // Only this initialization query uses a client read deadline. On failure,
        // pg-pool removes the connection; business SQL uses server cancellation.
        query_timeout: 5000,
      }).then(() => done(), done);
    },
  };
}

module.exports = {buildPoolOptions, getStatementDeadlineMs};
