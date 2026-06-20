const s = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const tests = [
  ['how many total hours did I work this month', 'dtr_hours_summary'],
  ['pila oras nagtrabaho this month', 'dtr_hours_summary'],
  ['if i take 3 days sick leave how many days left', 'leave_balance_projection'],
  ['pila mabilin kung mag file ug 2 days vacation leave', 'leave_balance_projection'],
  ['can you write me a poem', null],
  ['hello who are you', null],
];
for (const [message, expectedIntent] of tests) {
  const result = s.scoreEmployeeAssistantIntent(message, null);
  const pass = result.intent === expectedIntent;
  console.log(`[${pass ? 'PASS' : 'FAIL'}] "${message.slice(0, 50)}"`);
  console.log(`       expected: ${expectedIntent}, got: ${result.intent} (confidence: ${result.confidence.toFixed(2)}, source: ${result.source})`);
}
