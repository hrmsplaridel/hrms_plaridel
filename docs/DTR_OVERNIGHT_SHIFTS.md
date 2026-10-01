# Overnight DTR Setup

## Configuration

Create a new shift rather than editing a shift already referenced by attendance
history. Set Start to 8:00 PM and End to 7:00 AM. An end time earlier than the
start means the shift ends on the following day; equal times are invalid.

- Single session: two punches, Time In and Time Out. Auto selects this mode for
  an overnight shift.
- Full day: four punches, Time In, Break Out, Break In and Time Out. Set the
  scheduled break start/end, for example 12:00 AM to 1:00 AM.

Shift Management does not expose paid/unpaid break policies or fixed deductions.
New shifts retain the previous attendance calculation: a two-punch session uses
the elapsed Time In to Time Out interval; a four-punch session excludes the
recorded Break Out to Break In interval. Thus 8 PM to 7 AM is 11 hours with two
punches, or 10 hours with a recorded one-hour break and four punches. No unrecorded
break is automatically deducted.

Paid-break policies and fixed unpaid deductions are not part of attendance
processing. The cleanup migration removes these retired fields and their keys
from schedule snapshots. Stored DTR hours and historical audit events are retained.

Assign the shift using an effective date and the employee's working days. The
capture window is an internal matching setting, defaulting to 120 minutes for
new shifts. It controls how early/late a punch can match the scheduled shift,
not grace or paid overtime, and is not shown in Shift Management. When windows
overlap, the nearer scheduled boundary
wins. A scheduled rest day cannot start a new night shift, but a morning punch
can finish the preceding working day's night shift.

## Processing and Display

Raw timestamps are retained. The attendance date is the date the shift starts.
For example, September 30 at 8 PM and October 1 at 7 AM form one September 30 DTR
row, including across month/year boundaries. Saved summaries include a schedule
snapshot, used when reprocessing and calculating historical reports.

Overnight late/undertime uses chronological timestamps and scheduled break
boundaries. An unfinished night is not treated as a completed absence before
its next-morning scheduled end. Existing attendance-policy conversion rules and
monthly reconciliation remain in force; this change does not introduce overtime
pay or night-differential rules.

Auto, Split and Single session are display modes in Time Logs/My Attendance.
Mobile Auto selects the layout per record. Next-day punches are marked
`(+1 day)`. Official DTR exports retain their four-column form and mark next-day
times rather than changing the official template.

Manual entry supports next-day punches and validates chronological order.
Untyped biometric scans are matched in order; missing break scans require
review/correction, not invented timestamps. Near-duplicate overnight scans within
one minute do not fill an extra punch slot.

Leave and holiday coverage is anchored to the shift's attendance date, not split
automatically between two holiday dates. Partial suspension covers its calendar
AM/PM interval on the start date. Confirm this convention with the client before
using it for special holiday accounting.

## Rollout and Verification

Apply `backend/scripts/migrations/dtr/20261001_overnight_shifts.sql` to existing
databases, followed by `20261001_remove_shift_break_policies.sql` in the same
directory. The second migration cleans up databases that received the earlier
break-policy fields and is also safe to rerun. New databases use the matching
definitions in `init-schema.sql`.
Restart the backend and reload/rebuild the Flutter application. The migration
does not rewrite historical DTR rows or assign night shifts to employees.

Backend coverage includes cross-month grouping, two/four punches, actual recorded
breaks, missing punches, duplicate scans, rest-day transitions, snapshots,
historical report deductions, and retired-policy metadata having no effect.
Flutter checks can be run separately:

```powershell
cd frontend
flutter test --no-pub test/dtr/attendance/ test/dtr/management/ test/dtr/reports/
```
