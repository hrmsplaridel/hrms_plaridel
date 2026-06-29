const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildLeaveActionPayload,
  buildLocatorActionPayload,
  extractLeavePrefill,
} = require('../src/services/dtrAssistant/dtrAssistantActionPrefill');
const {
  clearAssistantMemory,
  DEFAULT_TTL_MS,
  getAssistantMemory,
  setAssistantMemory,
} = require('../src/services/dtrAssistant/dtrAssistantMemoryService');
const {
  __test: assistantServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantService');

test('DTR assistant action prefill: leave and locator payloads include guided context', () => {
  const memory = {
    lastUserMessage: 'help me file sick leave tomorrow for medical checkup in Cebu City',
    topics: {
      leave: {
        text: 'help me file sick leave tomorrow for medical checkup in Cebu City',
        leavePrefill: {
          reason: 'medical checkup',
        },
      },
    },
  };

  const leavePayload = buildLeaveActionPayload({
    text: 'open leave form',
    memory,
    leaveType: 'sick',
    rangePayload: {
      startDate: '2026-06-29',
      endDate: '2026-06-29',
    },
  });
  assert.equal(leavePayload.leaveType, 'sick');
  assert.equal(leavePayload.startDate, '2026-06-29');
  assert.match(leavePayload.reason, /medical checkup/i);
  assert.equal(leavePayload.locationDetails, 'Cebu City');

  const locatorPayload = buildLocatorActionPayload({
    text: 'file WFH tomorrow at Home - Poblacion because approved office arrangement',
    memory: null,
    locatorType: 'work_from_home',
    rangePayload: {
      startDate: '2026-06-29',
      endDate: '2026-06-29',
    },
  });
  assert.equal(locatorPayload.locatorType, 'work_from_home');
  assert.equal(locatorPayload.slipDate, '2026-06-29');
  assert.ok(locatorPayload.reason);
});

test('DTR assistant memory: reset clears server-side conversation context', () => {
  assert.equal(DEFAULT_TTL_MS, 2 * 60 * 60 * 1000);
  setAssistantMemory('user-reset-test', {
    intent: 'leave_balance',
    text: 'pila akong leave balance?',
  });
  assert.ok(getAssistantMemory('user-reset-test'));
  assert.equal(clearAssistantMemory('user-reset-test'), true);
  assert.equal(getAssistantMemory('user-reset-test'), null);
});

test('DTR assistant regression: buildActions includes richer leave and locator prefill', () => {
  const memory = {
    topics: {
      leave: {
        leavePrefill: {
          reason: 'Medical consultation',
          locationDetails: 'Cebu City',
          locationOption: 'within_philippines',
        },
      },
      locator: {
        locatorPrefill: {
          reason: 'Approved WFH arrangement',
          destination: 'Home - Poblacion, Plaridel',
        },
      },
    },
  };

  const leaveActions = assistantServiceTest.buildActions(
    'leave_guided_filing',
    {
      date_range: {
        label: 'tomorrow',
        startDate: '2026-06-29',
        endDate: '2026-06-29',
      },
    },
    'help me file sick leave tomorrow for medical consultation in Cebu City',
    [],
    memory
  );
  assert.equal(leaveActions[0].type, 'open_leave_form');
  assert.match(leaveActions[0].payload.reason, /medical consultation/i);
  assert.equal(leaveActions[0].payload.locationDetails, 'Cebu City');
  assert.equal(leaveActions[0].payload.locationOption, 'within_philippines');

  const locatorActions = assistantServiceTest.buildActions(
    'locator_guided_filing',
    {
      date_range: {
        label: 'tomorrow',
        startDate: '2026-06-29',
        endDate: '2026-06-29',
      },
    },
    'help me file WFH tomorrow at Home - Poblacion, Plaridel',
    [],
    memory
  );
  assert.equal(locatorActions[0].type, 'open_locator_form');
  assert.equal(locatorActions[0].payload.locatorType, 'work_from_home');
  assert.equal(locatorActions[0].payload.slipDate, '2026-06-29');
  assert.equal(
    locatorActions[0].payload.destination,
    'Home - Poblacion, Plaridel'
  );
});

test('DTR assistant action prefill: extractLeavePrefill ignores bare filing phrases', () => {
  const extracted = extractLeavePrefill(
    'help me file sick leave tomorrow',
    null
  );
  assert.equal(extracted.reason, undefined);
});
