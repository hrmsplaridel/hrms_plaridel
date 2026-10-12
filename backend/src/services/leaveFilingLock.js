// One employee's filing decisions must use a committed view of earlier filings.
// PostgreSQL releases this lock automatically on transaction commit/rollback.
async function lockEmployeeLeaveFiling(client, userId) {
  await client.query(
    'SELECT pg_advisory_xact_lock(743021, hashtext($1::text))',
    [String(userId)]
  );
}

module.exports = { lockEmployeeLeaveFiling };
