const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateGuidedClarification } = require('../src/services/dtrAssistant/dtrAssistantGuidedClarification');
const { buildFastEmployeeAssistantReply } = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const { parseAssistantDateRange } = require('../src/utils/dateRangeParser');
const { __test: { assistantContextLoadPlan } } = require('../src/services/dtrAssistant/dtrAssistantDataService');

function calendarContext(coverage = 'whole_day') {
  const range = parseAssistantDateRange('tomorrow');
  return {
    date_range: range,
    locator_types: [{ code: 'locator', label: 'Official Business', is_active: true }],
    dtr_calendar_days: [{
      attendance_date: range.startDate,
      shift_id: 'shift', shift_name: 'Day shift',
      start_time: '08:00:00', end_time: '17:00:00',
      working_days: [1, 2, 3, 4, 5, 6, 7], punch_mode: 'four_punch',
      holiday_name: coverage === 'none' ? null : "All Souls' Day",
      holiday_coverage: coverage,
    }],
  };
}

for (const message of [
  'is it okay for me to file locator tomorrow?',
  'pwede ko mag-file ug locator ugma?',
  'puwede ba ako mag-file ng locator bukas?',
]) {
  test(`locator eligibility answers the holiday before asking draft fields: ${message}`, () => {
    const context = calendarContext();
    assert.equal(evaluateGuidedClarification({ intent: 'locator_availability_check', text: message, context, memory: {} }), null);
    const reply = buildFastEmployeeAssistantReply(message, context, 'locator_availability_check');
    assert.match(reply, /All Souls' Day/);
    assert.match(reply, /No locator coverage is required|Dili kinahanglan|Hindi kailangan/);
    assert.doesNotMatch(reply, /What destination|choose from AM|Initial check: you can file/);
  });
}

test('explicit guided filing also checks a whole-day holiday first', () => {
  const message = 'help me file a locator tomorrow';
  const context = calendarContext();
  assert.equal(evaluateGuidedClarification({ intent: 'locator_guided_filing', text: message, context, memory: {} }), null);
  assert.match(buildFastEmployeeAssistantReply(message, context, 'locator_guided_filing'), /All Souls' Day/);
  for (const intent of ['locator_availability_check', 'locator_guided_filing']) {
    assert.equal(assistantContextLoadPlan([intent]).dtrCalendarDays, true);
  }
});

test('an eligibility question with a date does not require destination on a workday', () => {
  const context = calendarContext('none');
  assert.equal(evaluateGuidedClarification({ intent: 'locator_availability_check', text: 'can I file a locator tomorrow?', context, memory: {} }), null);
  assert.doesNotMatch(buildFastEmployeeAssistantReply('can I file locator tomorrow?', context, 'locator_availability_check'), /whole-day holiday/);
});

test('missing calendar data does not claim eligibility or invent a holiday', () => {
  const context = { date_range: parseAssistantDateRange('tomorrow') };
  const reply = buildFastEmployeeAssistantReply('can I file locator tomorrow?', context, 'locator_availability_check');
  assert.match(reply, /cannot confirm eligibility/);
  assert.doesNotMatch(reply, /Initial check: you can file|All Souls/);
});

test('partial holiday preserves eligibility for the remaining working slots', () => {
  const context = calendarContext('am_only');
  const reply = buildFastEmployeeAssistantReply('can I file locator tomorrow?', context, 'locator_availability_check');
  assert.match(reply, /PM in, PM out/);
  assert.doesNotMatch(reply, /No locator coverage is required|whole-day holiday/);
});
