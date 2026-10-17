'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {PDFDocument} = require('pdf-lib');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const ids = {
  request: '11111111-1111-4111-8111-111111111111',
  owner: '22222222-2222-4222-8222-222222222222',
  head: '33333333-3333-4333-8333-333333333333',
  primary: '44444444-4444-4444-8444-444444444444',
  backup: '55555555-5555-4555-8555-555555555555',
  stranger: '66666666-6666-4666-8666-666666666666',
};

for (const viewer of ['head', 'primary', 'backup', 'stranger']) {
  test(`workflow ${viewer} preview reads only an authorized request, form credits and template`, async () => {
    const snapshot = {current_step: 1, steps: [
      {label: 'Department Review', assignee_source: 'specific_users', user_ids: [ids.head]},
      {label: 'HR Review', assignee_source: 'specific_users', user_ids: [ids.primary, ids.backup]},
    ], decisions: [{step: 0, action: 'approve', actor_id: ids.head}]};
    const row = {id: ids.request, employee_id: ids.owner, user_id: ids.owner, status: 'pending_hr',
      workflow_snapshot: snapshot, signature_revision: 1, start_date: '2026-10-13', end_date: '2026-10-13',
      leave_type_name: 'eLeave', employee_full_name: 'Applicant', number_of_days: 1};
    let balanceReads = 0;
    async function query(sql, params = []) {
      const s = String(sql).replace(/\s+/g, ' ').trim();
      if (s.startsWith('SELECT id,user_id,employee_id,status,workflow_snapshot FROM leave_requests')) return {rows: [row]};
      if (s.includes('FROM users WHERE id=ANY')) return {rows: params[0].map(id => ({id, name: id, role: 'employee'}))};
      if (s.includes('AS can_view')) return {rows: [{employee_id: ids.owner, can_view: false}]};
      if (s.includes('FROM leave_balances lb')) {
        balanceReads++;
        assert.deepEqual(params, [ids.owner]);
        assert.match(s, /leave_type IN \('vacationLeave', 'sickLeave'\)/);
        return {rows: []};
      }
      if (s.includes('v.id AS version_id')) return {rows: params[4] === true ? [{...row, version_id: 'version', layout: 'csc'}] : []};
      if (s.includes('dhh.department_head_reviewer_id')) return {rows: params[1] === true ? [row] : []};
      return {rows: []};
    }
    const pool = {query, connect: async () => ({query, release() {}})};
    const restores = [withMockedModule('../src/config/db', {pool}),
      withMockedModule('../src/services/docutrackerWorkflowService', {resolveStepAssignees: async (_, {stepConfig}) => stepConfig.user_ids})];
    const modules = ['../src/routes/leaveRoutes', '../src/routes/leavePrintTemplates'];
    modules.forEach(clearModule);
    try {
      const leave = require(modules[0]), print = require(modules[1]);
      const user = {id: ids[viewer], role: 'employee'};
      const pdf = await PDFDocument.create(); pdf.addPage();
      for (const [router, path, method] of [
        [leave, '/:id', 'get'], [leave, '/:id/form-credits', 'get'],
        [print, '/requests/:id', 'get'], [print, '/requests/:id/render', 'post'],
      ]) {
        const res = {code: 200, status(code) {this.code = code; return this;}, json(body) {this.body = body; return this;},
          set() {return this;}, send(body) {this.body = body; return this;}};
        const handler = router.stack.find(s => s.route?.path === path && s.route.methods[method]).route.stack.at(-1).handle;
        await handler({user, params: {id: ids.request}, body: {version_id: 'version'}, file: {buffer: await pdf.save()}}, res);
        assert.equal(res.code, viewer === 'stranger' ? path.endsWith('form-credits') ? 403 : 404 : 200, `${viewer}: ${path} ${JSON.stringify(res.body)}`);
      }
      assert.equal(balanceReads, viewer === 'stranger' ? 0 : 1);
    } finally {modules.forEach(clearModule); restores.reverse().forEach(restore => restore());}
  });
}
