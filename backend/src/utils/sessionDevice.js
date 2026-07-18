/**
 * Friendly labels for auth refresh-token sessions (device + network location).
 */

function parseUserAgent(ua) {
  if (!ua || !String(ua).trim()) {
    return { label: 'Unknown device', type: 'unknown', model: null };
  }
  const s = String(ua);

  if (s.includes('Dart/') || s.includes('Flutter')) {
    if (/android/i.test(s)) {
      return { label: 'HRMS app on Android', type: 'mobile', model: 'Android' };
    }
    if (/iphone|ipad|ios/i.test(s)) {
      const model = /ipad/i.test(s) ? 'iPad' : 'iPhone';
      return {
        label: `HRMS app on ${model}`,
        type: /ipad/i.test(s) ? 'tablet' : 'mobile',
        model,
      };
    }
    if (/windows/i.test(s)) {
      return { label: 'HRMS app on Windows', type: 'desktop', model: 'Windows PC' };
    }
    if (/macintosh|mac os/i.test(s)) {
      return { label: 'HRMS app on macOS', type: 'desktop', model: 'Mac' };
    }
    if (/linux/i.test(s)) {
      return { label: 'HRMS app on Linux', type: 'desktop', model: 'Linux PC' };
    }
    return { label: 'HRMS mobile or desktop app', type: 'unknown', model: null };
  }

  let browser = 'Browser';
  if (/Edg\//.test(s)) browser = 'Microsoft Edge';
  else if (/OPR\/|Opera/.test(s)) browser = 'Opera';
  else if (/Chrome\//.test(s) && !/Edg\//.test(s)) browser = 'Chrome';
  else if (/Firefox\//.test(s)) browser = 'Firefox';
  else if (/Safari\//.test(s) && !/Chrome\//.test(s)) browser = 'Safari';

  let os = '';
  let model = null;
  if (/Windows NT 10|Windows NT 11|Windows/.test(s)) {
    os = 'Windows';
    model = 'Windows PC';
  } else if (/Mac OS X|Macintosh/.test(s)) {
    os = 'macOS';
    model = 'Mac';
  } else if (/Android/.test(s)) {
    os = 'Android';
    model = 'Android phone or tablet';
  } else if (/iPad/.test(s)) {
    os = 'iPadOS';
    model = 'iPad';
  } else if (/iPhone/.test(s)) {
    os = 'iOS';
    model = 'iPhone';
  } else if (/Linux/.test(s)) {
    os = 'Linux';
    model = 'Linux PC';
  }

  const mobile = /Mobile|Android|iPhone/i.test(s);
  const tablet = /iPad|Tablet/i.test(s);
  const type = tablet ? 'tablet' : mobile ? 'mobile' : 'desktop';
  const label = os ? `${browser} on ${os}` : browser;
  return { label, type, model };
}

function ipToLocationLabel(ip) {
  if (ip == null || String(ip).trim() === '') {
    return 'Location unknown';
  }
  let normalized = String(ip).trim();
  if (normalized.startsWith('::ffff:')) {
    normalized = normalized.slice('::ffff:'.length);
  }

  if (normalized === '127.0.0.1' || normalized === '::1') {
    return 'This device (local)';
  }
  if (
    /^10\./.test(normalized) ||
    /^192\.168\./.test(normalized) ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(normalized) ||
    /^169\.254\./.test(normalized)
  ) {
    return `Local network · ${normalized}`;
  }
  return `Network · ${normalized}`;
}

/**
 * @param {string|null} ua
 * @param {string|null} clientHint - X-HRMS-Device from Flutter/web client
 */
function buildDeviceInfoPayload(ua, clientHint) {
  const parsed = parseUserAgent(ua);
  const client = clientHint && String(clientHint).trim() ? String(clientHint).trim() : null;
  const label = client || parsed.label;
  const model = parsed.model || (client ? client.split('·')[0].trim() : null);
  return {
    ua: ua || null,
    label,
    type: parsed.type,
    model,
    client,
  };
}

/**
 * Returns true when the request came from the native mobile app or a mobile
 * browser. The explicit Flutter device hint takes precedence because Dio's
 * user-agent is not consistent across Android/iOS versions.
 */
function isMobileClient(ua, clientHint) {
  const hint = clientHint ? String(clientHint).trim() : '';
  if (/^(Android device|iPhone or iPad)\b/i.test(hint)) return true;
  return ['mobile', 'tablet'].includes(parseUserAgent(ua).type);
}

/**
 * @param {string|null} deviceInfo - JSON blob or legacy raw User-Agent
 */
function resolveSessionDevice(deviceInfo) {
  if (!deviceInfo) {
    return parseUserAgent(null);
  }
  const raw = String(deviceInfo);
  if (raw.startsWith('{')) {
    try {
      const j = JSON.parse(raw);
      if (j && typeof j === 'object') {
        const parsed = j.ua ? parseUserAgent(j.ua) : parseUserAgent(null);
        return {
          label: j.label || j.client || parsed.label,
          type: j.type || parsed.type,
          model: j.model || j.client || parsed.model,
          client: j.client || null,
        };
      }
    } catch (_) {
      // fall through — treat as UA string
    }
  }
  return parseUserAgent(raw);
}

function enrichSessionRow(row) {
  const dev = resolveSessionDevice(row.device_info);
  return {
    id: row.id,
    device_info: row.device_info,
    device_label: dev.label,
    device_model: dev.model,
    device_type: dev.type,
    client_unit: dev.client,
    ip_address: row.ip_address,
    location_label: ipToLocationLabel(row.ip_address),
    created_at: row.created_at,
    expires_at: row.expires_at,
  };
}

module.exports = {
  parseUserAgent,
  ipToLocationLabel,
  buildDeviceInfoPayload,
  isMobileClient,
  resolveSessionDevice,
  enrichSessionRow,
};
