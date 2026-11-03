const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

async function accessFor(table, rsp, ld) {
  const fields = require('../src/services/moduleAdminAccess');
  const restore = withMockedModule('../src/services/moduleAdminAccess', {
    ...fields,
    rspAdminAccess: { fields: fields.rspAdminAccess.fields, loadAccess: async () => rsp },
  });
  clearModule('../src/middleware/rspAccess');
  try {
    const { requireRspOrLdFormsIfAdmin } = require('../src/middleware/rspAccess');
    const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
    let allowed = false;
    await requireRspOrLdFormsIfAdmin(async () => ld)(
      { user: { id: 'admin', role: 'admin' }, params: { table } }, res,
      () => { allowed = true; },
    );
    return { allowed, ...res };
  } finally { clearModule('../src/middleware/rspAccess'); restore(); }
}

for (const [table, rsp, ld, allowed] of [
  ['bi_form_entries', { form_bi_allowed: true }, {}, true],
  ['training_need_analysis_entries', { form_bi_allowed: true }, {}, false],
  ['bi_form_entries', {}, { form_tna_allowed: true }, false],
  ['training_need_analysis_entries', {}, { form_tna_allowed: true }, true],
  ['idp_entries', {}, { forms_allowed: true, form_tna_allowed: true }, false],
  ['applicants_profile_entries', { forms_allowed: true, form_bi_allowed: true }, {}, false],
]) {
  test(`form permission is scoped to ${table}, expected ${allowed}`, async () => {
    const result = await accessFor(table, rsp, ld);
    assert.equal(result.allowed, allowed);
    assert.equal(result.code, allowed ? 200 : 403);
  });
}

test('saved-form router binds table before its form permission middleware', () => {
  const fs = require('node:fs');
  const source = fs.readFileSync(require.resolve('../src/routes/rspLdSavedEntries'), 'utf8');
  assert.match(source, /router\.use\(\s*['"]\/:table['"]/);
});

for (const [path, granted, allowed] of [
  ['/', { exams_allowed: true }, false],
  ['/', { applications_allowed: true }, true],
  ['/exam-results/:applicationId', { applications_allowed: true }, false],
  ['/exam-results/:applicationId', { exam_results_allowed: true }, true],
  ['/:applicationId/final-interview', { applications_allowed: true }, false],
  ['/:applicationId/final-interview', { scheduling_allowed: true }, true],
  ['/:applicationId/hired-link', { scheduling_allowed: true }, false],
  ['/:applicationId/hired-link', { final_requirements_allowed: true }, true],
  ['/:applicationId/final-requirements/:kind/reject', { applications_allowed: true }, false],
  ['/:applicationId/final-requirements/:kind/reject', { final_requirements_allowed: true }, true],
]) {
  test(`recruitment action ${path} respects its tab permission (${allowed})`, async () => {
    const original = require('../src/services/moduleAdminAccess');
    const restore = withMockedModule('../src/services/moduleAdminAccess', {
      ...original,
      rspAdminAccess: { ...original.rspAdminAccess, loadAccess: async () => granted },
    });
    clearModule('../src/middleware/rspAccess');
    try {
      const middleware = require('../src/middleware/rspAccess').requireRspApplicationAccessIfAdmin;
      assert.equal(typeof middleware, 'function');
      const res = { code: 200, status(n) { this.code = n; return this; }, json() {} };
      let advanced = false;
      await middleware({ user: { id: 'admin', role: 'admin' }, route: { path } }, res, () => { advanced = true; });
      assert.equal(advanced, allowed);
      assert.equal(res.code, allowed ? 200 : 403);
    } finally { clearModule('../src/middleware/rspAccess'); restore(); }
  });
}
