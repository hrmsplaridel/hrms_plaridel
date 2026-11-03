# Opening leave balances at deployment

Use **DTR → Leave Management → ⋮ → Manual balance adjustment → Opening balances** for each employee.

1. Select an active employee eligible for leave credits.
2. Select the last completed month that HR has fully accounted for. Selecting a date uses that month's final day.
3. Enter the employee's **final available Sick Leave and Vacation Leave days**, not the amounts to add. For example, enter SL `25` and VL `30` even if the system already contains some credits.
4. Enter **Vacation / Forced Leave already taken in the cutoff year**: qualifying days from January 1 through the cutoff, including any approved applications already in this system. Enter `0` when verified that none were taken. This usage does not deduct credits again.
5. Enter the HR leave-card or verification reference and confirm the balances and qualifying usage through the cutoff.
6. Save. The balances, qualifying usage, verification identity/reference, and credit audit entries are committed together.

The setup is recorded once per employee. For later corrections, choose **Adjust existing balance** in the same panel. Switching modes preserves draft values. Setup rejects pending credit leave/reservations, processing after the chosen cutoff, and employees hired after that cutoff. It preserves earned/used history and records the difference in the adjustment bucket.

The cutoff protects SL/VL accrual, accrual reconciliation, attendance deductions, and completed year-end deductions already included in the opening balances. New credit-backed leave approvals overlapping the cutoff are rejected to prevent another deduction. Following periods continue through the normal scheduler.

For forced-leave compliance in the cutoff year, the employee summary and year-end assessment combine the verified historical usage with qualifying approved requests **after** the cutoff. Requests that cross the cutoff or year boundary are clipped and counted using the employee's working days and holidays. This avoids counting pre-cutoff applications twice. Later years count their own approved applications normally. This does not import individual historical applications or usage for other annual leave types.

Existing opening records have unknown historical usage until HR verifies it. In **Opening balances**, select that employee, enter qualifying days and the verification reference, confirm, and select **Save verified usage**. This changes only historical usage, not credit balances. Unverified cutoff-year usage is marked **Needs history review** in year-end assessment, and automatic/bulk/manual year-end deductions are blocked for that employee and year. The employee summary shows an unverified remaining requirement. Existing deductions are not automatically reversed. The first verification is recorded once; later corrections require an audited reconciliation.

## Database deployment

Apply `backend/scripts/migrations/dtr/20261101_leave_opening_balances.sql`, then `backend/scripts/migrations/dtr/20261101_leave_opening_usage.sql` before restarting the updated backend. If the first migration was already applied, run only the second. The fresh initializer includes both. The usage migration adds nullable verification fields so existing openings require review, without changing credit balances.

On the Ubuntu server, use the existing migration procedure with `ON_ERROR_STOP`, then restart `hrms-api` after deploying the backend. Rebuild/redeploy the Flutter app for the updated adjustment panel. Setting only an as-of date in **Adjust existing balance** does not establish this processing cutoff.

For initial onboarding, keep automated processing paused while HR enters all existing employees: use the existing `LEAVE_ACCRUAL_CRON_ENABLED=false` and `YEAR_END_FORCED_LEAVE_CRON_ENABLED=false` settings, then restart the backend. Do not run Month End manually during this entry period. After all verified openings are saved, restore the intended scheduler settings and restart again. This avoids processing employees whose opening setup has not yet been entered; the cutoff protects each employee after their setup is saved. No environment settings are changed automatically by the setup screen.

The UI intentionally accepts completed month-end opening snapshots. A mid-month transfer requires separate reconciliation rather than treating a partial month as fully accounted for.

## Verification

Run `npm run test:leave-management` in `backend` and `flutter test test/dtr/leave/leave_opening_balances_test.dart` in `frontend`. The optional PostgreSQL test runs when `LEAVE_OPENING_BALANCE_DB_TEST=1`; it creates temporary test records inside one transaction and rolls them back.

## Files changed for historical usage support

This update touches 23 files; other pending workspace changes predate it.

| File | Change |
| --- | --- |
| [backend/package.json](../backend/package.json) | Include historical-usage regressions in the leave suite. |
| [Initializer](../backend/scripts/init-schema.sql) | Include usage verification columns and constraints in fresh databases. |
| [Usage migration](../backend/scripts/migrations/dtr/20261101_leave_opening_usage.sql) | Upgrade existing openings without changing balances. |
| [Opening balance service](../backend/src/services/leaveOpeningBalances.js) | Save new usage and complete legacy verification under transaction locks. |
| [Usage calculation](../backend/src/services/leaveOpeningUsage.js) | Combine historical and later approved days using one cutoff/year rule. |
| [Year-end service](../backend/src/services/leaveYearEndForcedLeave.js) | Review gates and locked rechecks before deductions. |
| [Opening controller](../backend/src/modules/leave/controllers/openingBalances.controller.js) | Expose verification details and the protected verification action. |
| [Balance controller](../backend/src/modules/leave/controllers/balances.controller.js) | Include imported usage in the employee compliance summary. |
| [Administration controller](../backend/src/modules/leave/controllers/administration.controller.js) | Block manual year-end deductions for unverified history. |
| [Router](../backend/src/modules/leave/leave.router.js) | Register the staff-only usage-verification endpoint. |
| [Route contract](../backend/test/fixtures/leave-route-contract.json) | Preserve routing and authorization coverage. |
| [Opening tests](../backend/test/leaveOpeningBalances.test.js) | Require and validate historical usage on new openings. |
| [Usage tests](../backend/test/leaveOpeningUsage.test.js) | Boundaries, unknown history, validation, and deduction concurrency. |
| [Summary tests](../backend/test/leaveUsageSummary.test.js) | Combined usage and verification status. |
| [PostgreSQL integration](../backend/test/leaveOpeningBalancesPostgres.integration.test.js) | Real SQL, no double counting, unchanged credit balances; test data rolls back. |
| [Opening form](../frontend/lib/features/dtr/leave/presentation/admin/widgets/admin_leave_opening_balances_form.dart) | New usage field and legacy verification form. |
| [Year-end UI](../frontend/lib/features/dtr/leave/presentation/admin/widgets/admin_year_end_forced_leave_dialog.dart) | History-review badge and filter. |
| [Balance model](../frontend/lib/features/dtr/leave/models/leave_balance.dart) | Retain the unknown-history flag. |
| [Usage card](../frontend/lib/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart) | Display unverified requirements without claiming compliance. |
| [Desktop employee summary](../frontend/lib/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart) | Show an unknown requirement until historical usage is verified. |
| [Opening UI tests](../frontend/test/dtr/leave/leave_opening_balances_test.dart) | New and legacy usage submission. |
| [Summary UI tests](../frontend/test/dtr/leave/leave_usage_summary_test.dart) | Unknown-history display. |
| [This guide](leave-opening-balances.md) | Operating steps, deployment, and complete file inventory. |
