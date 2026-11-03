const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

for (const [module, serviceName, parent, child] of [
  ['rsp', 'rspAdminAccess', 'forms_allowed', 'form_bi_allowed'],
  ['ld', 'ldAdminAccess', 'forms_allowed', 'form_tna_allowed'],
]) {
  for (const existing of [false, true]) {
    test(`${module}: reading access ${existing ? 'preserves saved child denials' : 'does not grant a new admin permissions'}`, async () => {
      let fields;
      let access;
      const mutations = [];
      const restore = withMockedModule('../src/config/db', { pool: {
        async query(sql) {
          if (/^\s*INSERT INTO/.test(sql)) {
            mutations.push(sql);
            if (!access) access = Object.fromEntries(fields.map(field => [field, true]));
          }
          if (/^\s*UPDATE/.test(sql)) {
            mutations.push(sql);
            if (access?.[parent]) access[child] = true;
          }
          return { rows: [/^\s*SELECT/.test(sql) ? access || Object.fromEntries(fields.map(field => [field, false])) : {}] };
        },
      } });
      clearModule('../src/services/moduleAdminAccess');
      try {
        const service = require('../src/services/moduleAdminAccess')[serviceName];
        fields = service.fields;
        if (existing) access = { ...service.falseDefaults, [parent]: true };
        const result = await service.loadAccess('10000000-0000-4000-8000-000000000001');
        assert.equal(result[child], false);
        if (!existing) assert.equal(service.anyAllowed(result), false);
        assert.equal(mutations.length, 0, 'Reading permissions must not seed or backfill grants');
      } finally { clearModule('../src/services/moduleAdminAccess'); restore(); }
    });
  }
}
