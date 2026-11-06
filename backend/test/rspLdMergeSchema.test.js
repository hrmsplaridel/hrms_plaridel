const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const tables = [
  'bi_form_entries', 'performance_evaluation_entries', 'training_need_analysis_entries',
  'action_brainstorming_coaching_entries', 'turn_around_time_entries', 'idp_entries',
  'learning_application_plan_entries', 'ojt_work_immersion_evaluation_entries',
  'selection_lineup_entries', 'computation_of_points_entries', 'work_experience_sheet_entries',
  'applicants_profile_entries', 'comparative_assessment_entries',
  'promotion_certification_entries', 'training_daily_reports',
];

test('fresh initializer and upgrade migration include every recycled RSP/L&D table', () => {
  const init = fs.readFileSync(path.join(__dirname, '../scripts/init-schema.sql'), 'utf8');
  for (const table of tables) {
    const definition = init.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${table} \\(([\\s\\S]*?)\\n\\);`));
    assert.ok(definition, table);
    assert.match(definition[1], /deleted_at\s+TIMESTAMPTZ/i, `${table} must support recycling on a fresh database`);
  }
  const upgrade = fs.readFileSync(path.join(__dirname, '../scripts/migrations/20261103_rsp_ld_recycle_bin.sql'), 'utf8');
  for (const table of tables) {
    assert.match(upgrade, new RegExp(`ALTER TABLE public\\.${table}\\s+ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`, 'i'));
  }
});
