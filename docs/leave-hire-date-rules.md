# Leave hire-date rules

Configure these in **Create/Edit Leave Type → Filing Requirements**.

**Minimum months of service** is optional (blank or zero disables it). The system
compares the employee's recorded `date_hired` with the first requested leave date.
Six months from April 18 is October 18. An anniversary that falls past month end
uses that month's last day. Employees can file ahead for leave starting on or
after their eligibility date. Drafts can be saved before eligibility is met.
These rules use the employee's current recorded hire date; the system does not
combine previous employers or broken service periods automatically.

**First-year allowance** applies to custom annual entitlements with a positive
maximum and no leave credit ledger:

- **Full annual allowance** preserves the existing calendar-year limit.
- **Prorate by date hired (whole days)** reduces the allowance in the hiring year.

For proration, count all months after the hiring month, plus the fraction of
calendar days employed in the hiring month (including the hiring day). Multiply
that by `annual maximum / 12`, then round **down to whole working days**. For an
October 1 hire and a five-day annual limit, `5 × 3 / 12 = 1.25`, giving **one usable
day**. A late-year hire can have zero usable days. The full annual maximum applies
from January 1 of subsequent years. There is no carryover of unused entitlement.

Minimum service and proration are separate. Meeting minimum service does not
increase a prorated hiring-year allowance. A missing hire date blocks filing when
the configured rule requires it and prompts the employee to contact HR.

My Leave shows the rounded entitlement, pending/approved usage, and service
eligibility messages. Filing previews use the requested calendar year; a request
crossing New Year is checked against both years. Submission and final approval
enforce the same rules on the backend. Existing employee filing locks also prevent
two concurrent requests from consuming the same prorated allowance.

Built-in types retain their protected financial rules; minimum-service eligibility
can be configured alongside employment-type eligibility. Defaults remain **zero
minimum service** and **full annual allowance**. No existing request history is
rewritten when these settings are saved. Changing a rule can affect pending
requests when they are resubmitted or approved, and the displayed current allowance.

For existing databases, apply
`backend/scripts/migrations/dtr/20261018_leave_hire_date_rules.sql` once. New
databases receive the same columns and constraints directly through
`backend/scripts/init-schema.sql`, which remains standalone SQL for pgAdmin.
