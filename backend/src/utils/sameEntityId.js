/**
 * Compare ids from PostgreSQL (uuid/string) to JWT / request string ids.
 * Avoids strict === failures across node-pg value shapes.
 */
function sameEntityId(a, b) {
  if (a == null || b == null) return false;
  const na = String(a).trim().toLowerCase().replace(/-/g, '');
  const nb = String(b).trim().toLowerCase().replace(/-/g, '');
  return na.length > 0 && na === nb;
}

module.exports = { sameEntityId };
