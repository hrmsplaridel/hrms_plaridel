# Repair Step 4 after an admin exam bypass

An applicant whose assessment changed from `failed` to `passed` through the admin exam bypass could keep `step4_gate_required=false`. The applicant then saw Passed and Waiting for deliberation result, without the Work Experience Sheet / Applicants Profile / Selection Line-Up preparation section.

The backend policy now enables preparation for `failed → passed`, using the same existing initialization as `document_approved → passed` and `exam_taken → passed`. Existing scheduled, decided, hired, registered, already-passed and already-gated applications retain their current behavior. This fixes future transitions; restarting or refreshing alone does not repair records already affected.

## Deploy the backend fix

Commit/push the change and pull the intended backend version onto Ubuntu using your normal deployment procedure. Restart `hrms-api` after the code update and check `/health` and `/health/db`. This change introduces no new dependencies or database columns, and does not require a frontend rebuild when the current Step 4 interface is already deployed.

## Preview one affected application

Use the application's UUID, not its email address. Obtain it through your authorized database connection with a read-only query, replacing the placeholder with the applicant's exact Application ID:

```sql
SELECT id, applicant_number, status, step4_gate_required,
       wes_status, applicants_profile_status, selection_lineup_status,
       final_interview_at, final_interview_passed, hired_user_id
FROM public.recruitment_applications
WHERE applicant_number = 'REPLACE_WITH_EXACT_APPLICANT_NUMBER'
  AND deleted_at IS NULL;
```

On Ubuntu, from the backend folder, replace `REPLACE_WITH_APPLICATION_UUID` before running:

```bash
cd /srv/hrms/repository/backend
node scripts/repair-rsp-bypass-step4.js --application-id=REPLACE_WITH_APPLICATION_UUID --dry-run
```

The script loads the backend environment and reports the actual database name, server address/port, selected application number, current preparation state, and proposed changes. Verify that these identify the intended Ubuntu production database and applicant. Preview runs in a read-only transaction and changes no application records. There is no bulk/all-applicants option.

`would_repair` means this one application is eligible. The script requires all of the following:

- The application is not deleted, is already `passed`, and preparation is still disabled.
- No deliberation schedule or decision, hired account, final requirements approval, HR account setup, or Step 5 gate has advanced.
- A passing exam exists and its General, Math, and General Information sections each contain the admin override marker used by the bypass UI.

`not_eligible` explains why the repair was refused; review it rather than forcing an update. `already_enabled` means the preparation gate is already on and no change is needed. An older exam without these markers needs manual review; this tool deliberately does not guess whether it was bypassed.

## Apply only after the production target and backup are confirmed

Confirm a current database backup, the preview's production target and applicant, and operator approval before this step. Save the preview output privately with the deployment notes. Replace both placeholders with the reviewed UUID and database name:

```bash
node scripts/repair-rsp-bypass-step4.js --application-id=REPLACE_WITH_APPLICATION_UUID --expect-database=REPLACE_WITH_DATABASE_NAME --apply
```

The script verifies the connected database name, locks the application and exam rows, rechecks eligibility, and updates exactly one application in a transaction. It enables the gate and initializes only missing preparation statuses. It preserves existing form progress, exam scores, the passing result, interview fields, and account links. Any failure before commit rolls the repair back. A repeated application is a no-op once the gate is enabled.

The script never resets the failed exam, schedules deliberation, approves a form, or submits an applicant's Work Experience Sheet. Do not restore the faulty state by turning the gate off; use the saved before/after output and your backup procedure if an operator identifies a mistaken repair.

## Verify the applicant flow

1. Confirm the output reports `repaired` and `after.step4_gate_required=true`.
2. Have the applicant check/refresh status. The preparation section should display the Work Experience Sheet plus HR's Applicants Profile and Selection Line-Up progress.
3. HR still assigns the Work Experience Sheet before the applicant can open/edit it. Enabling the gate does not manufacture an assigned form.
4. Deliberation scheduling remains blocked until the Work Experience Sheet is approved and both HR forms are completed.

A data-only repair takes effect immediately; an additional restart is unnecessary. The initial restart is for the backend code fix. No Nginx reload is required.

The screenshot's HTTP 429 is a separate rate-limit condition. This repair does not clear rate-limit counters or disable protection; wait for the specified retry interval. If it repeats, inspect the deployed version, response headers and API logs to identify the limiter.

## Verification for developers

```powershell
cd backend
$env:RSP_BYPASS_DB_TEST = '1'
node --test test/rspPreDeliberationPolicy.test.js test/rspExamTrackingResponse.test.js test/rspBypassStep4Repair.test.js
Remove-Item Env:RSP_BYPASS_DB_TEST
```

The PostgreSQL test refuses non-local hosts, creates an isolated synthetic schema, and removes it after testing. It covers read-only preview, wrong-target rejection, preservation of existing progress, all advancement guards, missing bypass evidence, repeat execution, and the real assessment initialization SQL. It does not repair actual applicant records.
