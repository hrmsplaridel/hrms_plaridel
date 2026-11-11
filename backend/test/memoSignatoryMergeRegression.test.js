'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {configureOfficialSignatory} = require('../src/services/officialSignatoryService');
const {assertMemoSignatoryAccountsDistinct, resolveMemoSignatories} = require('../src/services/docutrackerDocumentBuilderService');
const PERSON = '11111111-1111-4111-8111-111111111111';

for (const dates of [
  {effectiveFrom: '2026-11-10', effectiveTo: '2026-11-01'},
  {effectiveFrom: '2026-02-31', effectiveTo: null},
  {effectiveFrom: '0000-01-01', effectiveTo: null},
]) {
  test(`invalid memorandum period is rejected before PostgreSQL: ${JSON.stringify(dates)}`, async () => {
    let queried = false;
    await assert.rejects(() => assertMemoSignatoryAccountsDistinct({query: async () => {
      queried = true;
      const error = new Error('PostgreSQL rejected the date range'); error.code = '22000'; throw error;
    }}, {roleKey: 'memo_noted_by', employeeId: PERSON, ...dates}),
    error => error.status === 400);
    assert.equal(queried, false);
  });
}

test('the same memorandum signer cannot bypass the check with uppercase UUID letters', async () => {
  const employeeId = 'abcdefab-1111-4111-8111-abcdefabcdef';
  const db = {query: async () => ({rows: [{employee_id: employeeId}]})};
  await assert.rejects(() => assertMemoSignatoryAccountsDistinct(db, {
    roleKey: 'memo_noted_by', employeeId: employeeId.toUpperCase(),
    effectiveFrom: '2026-11-10',
  }), /cannot be the same account/);
});

for (const role of ['memo_noted_by', 'memo_approved_by']) {
  test(`${role} checks conflicting accounts inside the save transaction`, async () => {
    const calls = [];
    const client = {release() {}, query: async (sql, params) => {
      calls.push({sql, params});
      if (sql.includes('daterange(') && sql.includes('role_key = $1')) return {rows: [{employee_id: PERSON}], rowCount: 1};
      if (sql.includes('FROM users u')) return {rows: [{id: PERSON, full_name: 'Signatory', is_active: true}], rowCount: 1};
      if (sql.includes('INSERT INTO docutracker_official_signatories')) return {rows: [{id: PERSON}], rowCount: 1};
      return {rows: [], rowCount: 0};
    }};
    await assert.rejects(() => configureOfficialSignatory({connect: async () => client}, {
      roleKey: role, employeeId: PERSON, effectiveFrom: '2026-11-10', actorId: PERSON,
    }), /cannot be the same account/);
    assert.equal(calls[0].sql, 'BEGIN');
    assert.equal(calls.at(-1).sql, 'ROLLBACK');
    assert.equal(calls.some(c => c.sql.includes('INSERT INTO docutracker_official_signatories')), false);
    assert.ok(calls.some(c => c.sql.includes('pg_advisory_xact_lock') && c.params[0] === 'docutracker_official_signatory:memo_approval_pair'));
  });
}

test('an inactive configured memorandum signer falls back instead of creating a dead signature slot', async () => {
  const db = {query: async (sql, params) => {
    if (sql.includes('FROM docutracker_official_signatories')) return {rows: [{employee_id: PERSON, position_title: 'Old official'}]};
    if (sql.includes('u.id = $1::uuid')) return {rows: /u\.is_active\s*=\s*true/.test(sql) ? [] : [{full_name: 'Inactive official', signer_role: 'employee'}]};
    return {rows: []};
  }};
  const result = await resolveMemoSignatories(db, {document_type: 'memo'});
  assert.equal(result.configuration.mode, 'automatic');
  assert.deepEqual(result.configuration.missing, ['Prepared by', 'Noted by', 'Approved by']);
  assert.equal(result.prepared_by, null);
});
