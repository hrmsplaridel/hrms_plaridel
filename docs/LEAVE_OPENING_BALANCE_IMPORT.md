# Opening leave balance import

Open Leave Balance Adjustment, select Opening balances, then Import opening balances.
Download template creates an empty CSV header. Fill it in Excel or a text editor,
save as CSV UTF-8, and upload it. You can also paste the CSV directly.

```csv
employee_number,cutoff_date,sick_leave_days,vacation_leave_days,qualifying_leave_days,reason
3,2026-10-31,25.125,18.500,3,"Verified HR leave card, October 2026"
```

Replace the example with verified employee records. These are opening available
Sick Leave and Vacation Leave credits, not amounts to add to current credits.

| Column | Required value |
| --- | --- |
| employee_number | The system employee number, not the biometric ID or name. Leading zeros are accepted. |
| cutoff_date | YYYY-MM-DD; the last day of a completed month already accounted for. Keep Excel cells as text so the date format is preserved. |
| sick_leave_days | Verified available Sick Leave credits at the cutoff. |
| vacation_leave_days | Verified available Vacation Leave credits at the cutoff. |
| qualifying_leave_days | Verified Vacation/Forced Leave used from January 1 of the cutoff year, or the hire date if later, through the cutoff. This records historical usage for compliance; it does not deduct credits again. Enter 0 only when verified. |
| reason | HR source/reference for the verified balances and usage, up to 500 characters. Quote fields containing commas. |

Use non-negative decimal days with up to three decimal places, a period as the
decimal separator, and no thousands separators or spreadsheet formulas. Both
credit balances and historical usage are required, including explicit zeros.
Do not include extra columns. Maximum: 200 employees and 256 KB per file.

Choose Validate preview. Review each matched employee, cutoff, balances and usage.
Fix every reported error, validate again, then confirm HR verification and choose
Import balances. Changing the CSV clears the preview and confirmation.

The server checks the same rules as manual opening setup: employee eligibility
and active employment, hire date, historical usage period, existing opening setup,
pending reservations/requests, later approved leave, later accruals/month-end
postings, and storage bounds. Repeated employee numbers, including 003 and 3 in the
same file, are rejected. Unknown employee numbers are rejected. Existing opening
setups cannot be overwritten; use Adjust existing balance for corrections.

Preview runs inside a rolled-back database transaction, so it leaves no balance,
ledger or opening setup changes. Import validates again and saves the entire batch
in one transaction, using the existing balance ledger and cutoff handling. If any
row fails, no employee in that batch is imported. Re-uploading a successful batch
is rejected because its opening setups are already recorded.

Deploy the backend changes and rebuild the application frontend to enable import.
This feature needs no additional database migration.
