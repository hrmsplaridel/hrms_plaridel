const test = require('node:test');
const assert = require('node:assert/strict');
const { canAccessLdTrainingRequirement } = require('../src/utils/ldTrainingRequirementPolicy');

for (const [role, owner, access, allowed] of [
  ['employee', 'me', false, true],
  ['admin', 'me', false, true],
  ['employee', 'other', true, false],
  ['admin', 'other', false, false],
  ['admin', 'other', true, true],
  ['super_admin', 'other', false, true],
]) {
  test(`${role} requirement attachment owner=${owner} permission=${access}`, async () => {
    assert.equal(typeof canAccessLdTrainingRequirement, 'function');
    const allowedResult = await canAccessLdTrainingRequirement(
      { id: 'me', role }, owner, async () => ({ requirements_allowed: access }),
    );
    assert.equal(allowedResult, allowed);
  });
}
