/**
 * Builds per-province address JSON for Flutter (city/municipality → barangays).
 * Data source: jgngo/psgc-data (PSA PSGC, CC0-style open data).
 *
 * Usage: node backend/scripts/build-ph-psgc-assets.js
 * Output: assets/data/ph_psgc/index.json
 *         assets/data/ph_psgc/provinces/<slug>.json
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.join(__dirname, '../..');
const OUT_DIR = path.join(ROOT, 'assets/data/ph_psgc');
const PROVINCES_DIR = path.join(OUT_DIR, 'provinces');

const URLS = {
  province: 'https://raw.githubusercontent.com/jgngo/psgc-data/master/json/province.json',
  muncity: 'https://raw.githubusercontent.com/jgngo/psgc-data/master/json/muncity.json',
  barangay: 'https://raw.githubusercontent.com/jgngo/psgc-data/master/json/barangay.json',
};

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${url}`));
          res.resume();
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

function slugify(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
}

/** Display-friendly city/municipality name. */
function cleanMuncityName(desc) {
  return String(desc || '')
    .replace(/\s*\([^)]*\)\s*$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function provinceCodePrefix(code) {
  const s = String(code);
  if (s.length >= 4) return s.slice(0, 4);
  return s;
}

async function main() {
  console.log('Downloading PSGC JSON…');
  const [provinces, muncities, barangays] = await Promise.all([
    fetchJson(URLS.province),
    fetchJson(URLS.muncity),
    fetchJson(URLS.barangay),
  ]);

  console.log(
    `Loaded ${provinces.length} provinces, ${muncities.length} cities, ${barangays.length} barangays`,
  );

  const muncityById = new Map();
  for (const m of muncities) {
    muncityById.set(m.muncity_id, m);
  }

  const barangaysByMuncity = new Map();
  for (const b of barangays) {
    const id = b.muncity_id;
    if (!barangaysByMuncity.has(id)) barangaysByMuncity.set(id, []);
    const name = String(b.description || '').trim();
    if (name) barangaysByMuncity.get(id).push(name);
  }

  fs.mkdirSync(PROVINCES_DIR, { recursive: true });

  const index = {};
  let totalCities = 0;

  for (const prov of provinces) {
    const provName = String(prov.description || '').trim();
    if (!provName) continue;

    const prefix = provinceCodePrefix(prov.code);
    const citiesInProv = muncities.filter((m) =>
      String(m.code).startsWith(prefix),
    );

    const map = {};
    for (const m of citiesInProv) {
      const cityName = cleanMuncityName(m.description);
      if (!cityName) continue;

      let list = barangaysByMuncity.get(m.muncity_id) || [];
      list = [...list].sort((a, b) => a.localeCompare(b, 'en'));
      if (list.length === 0) continue;

      if (!map[cityName]) {
        map[cityName] = list;
      } else {
        map[cityName] = [...new Set([...map[cityName], ...list])].sort((a, b) =>
          a.localeCompare(b, 'en'),
        );
      }
    }

    const cityNames = Object.keys(map).sort((a, b) => a.localeCompare(b, 'en'));
    if (cityNames.length === 0) continue;

    const slug = slugify(provName);
    index[provName] = { slug, cities: cityNames };
    totalCities += cityNames.length;

    const outPath = path.join(PROVINCES_DIR, `${slug}.json`);
    fs.writeFileSync(outPath, JSON.stringify(map));
  }

  fs.writeFileSync(
    path.join(OUT_DIR, 'index.json'),
    JSON.stringify(index),
  );

  const indexSize = fs.statSync(path.join(OUT_DIR, 'index.json')).size;
  console.log(
    `Wrote ${Object.keys(index).length} province files (${totalCities} cities total).`,
  );
  console.log(`Index: ${(indexSize / 1024).toFixed(1)} KB → ${OUT_DIR}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
