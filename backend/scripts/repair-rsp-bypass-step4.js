// Repair one previously bypassed applicant. Preview is the default; see
// docs/RSP_ADMIN_BYPASS_STEP4_REPAIR.md before using --apply on a live database.
const {canonicalApplicationId} = require('../src/services/rspPreDeliberationPolicy');

function parseArgs(argv) {
  const options = {apply:false};
  const seen = new Set();
  for (const arg of argv) {
    const key = arg.split('=')[0];
    if (seen.has(key)) throw new Error(`Duplicate option: ${key}`);
    seen.add(key);
    if (arg === '--apply') options.apply = true;
    else if (arg === '--dry-run') continue;
    else if (arg.startsWith('--application-id=')) options.applicationId = arg.slice('--application-id='.length);
    else if (arg.startsWith('--expect-database=')) options.expectedDatabase = arg.slice('--expect-database='.length);
    else throw new Error(`Unknown option: ${key}`);
  }
  if (!options.applicationId) throw new Error('Specify --application-id=UUID for exactly one application.');
  options.applicationId = canonicalApplicationId(options.applicationId);
  if (!options.applicationId) throw new Error('application-id must be a valid UUID.');
  if (options.apply && seen.has('--dry-run')) throw new Error('Do not supply both --apply and --dry-run.');
  if (options.apply && !options.expectedDatabase?.trim()) throw new Error('--apply requires --expect-database=NAME from the preview.');
  return options;
}

function repairBlockReason(application, exam) {
  if (!application) return 'Application not found.';
  if (application.deleted_at) return 'Application is deleted.';
  if (application.step4_gate_required === true) return 'already_enabled';
  if (application.status !== 'passed') return 'Application must already be passed.';
  if (application.final_interview_at || application.final_interview_passed != null || application.hired_user_id ||
      application.final_requirements_approved || application.hr_account_setup_done || application.step5_gate_required) {
    return 'Deliberation, final hiring or account setup has already advanced; manual review is required.';
  }
  if (exam?.passed !== true) return 'No passing exam result is recorded.';
  // Both perfect-score and custom-score bypasses mark each MCQ section.
  if (!['general','math','general_info'].every(section => exam.answers_json?.[section]?.admin_override === true)) {
    return 'The exam does not contain the complete admin-bypass markers; manual review is required.';
  }
  return null;
}

function preparationState(application) {
  return {
    step4_gate_required:application.step4_gate_required,
    wes_status:application.wes_status,
    applicants_profile_status:application.applicants_profile_status,
    selection_lineup_status:application.selection_lineup_status,
  };
}

async function repairStep4ForApplication(pool, {applicationId,apply=false,expectedDatabase}) {
  if (!canonicalApplicationId(applicationId)) throw new Error('application-id must be a valid UUID.');
  if (apply && !expectedDatabase?.trim()) throw new Error('Specify the expected database before applying.');
  const client = await pool.connect();
  try {
    await client.query(apply ? 'BEGIN' : 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await client.query("SET LOCAL lock_timeout = '5s'");
    await client.query("SET LOCAL statement_timeout = '10s'");
    const target = (await client.query(`SELECT current_database() AS database,
      inet_server_addr()::text AS server_address, inet_server_port() AS server_port`)).rows[0];
    if (expectedDatabase && target.database !== expectedDatabase) throw new Error('Connected database does not match --expect-database. Nothing was changed.');
    const application = (await client.query(`SELECT id, applicant_number, status, deleted_at,
      step4_gate_required, final_interview_at, final_interview_passed, hired_user_id,
      final_requirements_approved, hr_account_setup_done, step5_gate_required,
      wes_status, applicants_profile_status, selection_lineup_status
      FROM public.recruitment_applications WHERE id=$1 ${apply ? 'FOR UPDATE' : ''}`, [applicationId])).rows[0];
    const exam = application ? (await client.query(`SELECT passed, answers_json
      FROM public.recruitment_exam_results WHERE application_id=$1 ${apply ? 'FOR UPDATE' : ''}`, [applicationId])).rows[0] : null;
    const reason = repairBlockReason(application,exam);
    const result = {target,applicationId,applicantNumber:application?.applicant_number,
      outcome:reason === 'already_enabled' ? 'already_enabled' : reason ? 'not_eligible' : apply ? 'repaired' : 'would_repair',
      ...(reason ? {reason} : {}),before:application ? preparationState(application) : null};
    if (!reason) {
      if (apply) {
        const updated = await client.query(`UPDATE public.recruitment_applications
          SET step4_gate_required=TRUE,
            wes_status=COALESCE(wes_status,'waiting_for_work_experience_sheet'),
            applicants_profile_status=COALESCE(applicants_profile_status,'waiting'),
            selection_lineup_status=COALESCE(selection_lineup_status,'waiting'),
            updated_at=now()
          WHERE id=$1
          RETURNING step4_gate_required,wes_status,applicants_profile_status,selection_lineup_status`,[applicationId]);
        if (updated.rowCount !== 1) throw new Error('Expected exactly one application update.');
        result.after = preparationState(updated.rows[0]);
      } else {
        result.proposed = {
          step4_gate_required:true,
          wes_status:application.wes_status ?? 'waiting_for_work_experience_sheet',
          applicants_profile_status:application.applicants_profile_status ?? 'waiting',
          selection_lineup_status:application.selection_lineup_status ?? 'waiting',
        };
      }
    }
    await client.query(apply ? 'COMMIT' : 'ROLLBACK');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  require('dotenv').config({path:require('node:path').join(__dirname,'../.env')});
  const {pool} = require('../src/config/db');
  try {
    const result = await repairStep4ForApplication(pool,options);
    console.log(JSON.stringify(result,null,2));
    if (result.outcome === 'not_eligible') process.exitCode = 2;
  } finally {
    await pool.end();
  }
}

if (require.main === module) main().catch(error => {
  // Database error details may contain record values or connection information.
  console.error(error.code ? `Repair failed (${error.code}). No repair was committed.` : error.message);
  process.exitCode = 1;
});

module.exports = {parseArgs,repairStep4ForApplication};
