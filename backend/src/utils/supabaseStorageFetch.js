/**
 * Fetch a private object from Supabase Storage using the service role.
 * Tries common Storage API path layouts.
 */
function encodeObjectPath(objectPath) {
  return String(objectPath)
    .replace(/^\/+/, '')
    .split('/')
    .filter((s) => s.length > 0)
    .map(encodeURIComponent)
    .join('/');
}

async function fetchSupabaseObjectResponse(objectPath) {
  const supabaseUrl = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const bucket =
    process.env.SUPABASE_STORAGE_BUCKET || 'recruitment-attachments';

  if (!supabaseUrl || !serviceKey) {
    const err = new Error('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set');
    err.statusCode = 503;
    throw err;
  }

  const encoded = encodeObjectPath(objectPath);
  const headers = {
    Authorization: `Bearer ${serviceKey}`,
    apikey: serviceKey,
  };

  const candidates = [
    `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${encoded}`,
    `${supabaseUrl}/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${encoded}`,
  ];

  let last;
  for (const url of candidates) {
    last = await fetch(url, { headers });
    if (last.ok) return last;
  }
  return last;
}

module.exports = { fetchSupabaseObjectResponse, encodeObjectPath };
