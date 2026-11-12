# Custom leave credit balances

In Leave Type Management, select **Use own separate balance**. Eligible employees
see a credit card for that leave even before the first credit award. Vacation and
Sick Leave remain separate. Annual entitlement summaries remain separate from
credit wallets.

Monthly earning is **off by default**. HR can grant or correct credits through
the existing audited balance-adjustment dialog, selecting the custom leave.

To earn monthly, enable **Earn credits monthly**, enter a positive rate (for
example `1.250`), and enter the first service month as `YYYY-MM`. The entitlement
basis becomes **Credit balance**. A completed month is posted by the existing
month-end job; saving a type does not immediately grant credits.

The optional annual cap limits **earned accrual per calendar year**, not the
remaining balance. Spending credits or adding a manual adjustment does not
replenish the annual accrual allowance. A new year's earning allowance starts in
January. This custom rule does not change the built-in VL/SL calculation.

Accrual honors the configured start month, recorded hire/service requirements,
employment and sex restrictions, assignments, credit eligibility, and separation.
JO/COS employees do not accrue these credits. Partial qualifying months are
prorated. Catch-up obeys the existing month-end catch-up limit. Repeating a run
does not duplicate awards. Editing or disabling a custom rule preserves posted
awards; use an audited adjustment for historical corrections.

Filing reserves this leave's available credits. Approval moves reserved paid days
to used credits; cancellation releases reservations. These operations do not
charge VL/SL for a leave configured to use its own balance.

## Existing-server deployment

1. Confirm the intended database and a current backup using the usual deployment
   procedure. Run **only**
   `backend/scripts/migrations/dtr/20261112_custom_leave_balances.sql` against that
   database before deploying the updated backend. Do not run the fresh installer.
2. The migration adds `leave_types.accrual_start_date`, validates custom accrual
   settings, and removes the built-in-only balance CHECK. The foreign key to
   registered `leave_types(name)` remains enforced. No credits are granted or
   removed by this migration. Existing custom accrual configured directly in SQL
   must satisfy the new rule (explicit start date, own balance, credit basis).
3. Deploy the updated backend and restart the production service:

   ```bash
   sudo systemctl restart hrms-api
   sudo systemctl status hrms-api --no-pager
   ```

4. Rebuild and deploy the employee/admin frontend. Mobile installations need an
   updated build to show the custom credit cards.
5. Verify the API/database health, create a type with monthly earning **off**, and
   confirm its zero card and the custom choice in HR's adjustment dialog. Preview
   month-end accrual before intentionally posting any historical months.

The additive schema can remain when rolling back application code. Reinstating
the former built-in-only CHECK would fail once custom wallets exist; do not delete
credit records to make an old constraint pass.

## Verification

`CUSTOM_LEAVE_DB_TEST=1 node --test test/customLeaveAccrualPostgres.test.js` from
`backend` runs the migration and credit lifecycle in an isolated local PostgreSQL
schema, with all test records and schema changes rolled back.
