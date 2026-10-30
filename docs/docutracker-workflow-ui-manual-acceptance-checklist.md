# DocuTracker Workflow UI — Manual Acceptance Checklist

Numbers below exist only in PostgreSQL database `hrms_plaridel_docutracker_e2e`.
The same document numbers in `hrms_plaridel` are different records. Do not open these numbers on the shared API (port 3000).

Document type: `e2eNotice` (requires release). Steps:

1. Department review
2. Final approval (signature required)

Synthetic accounts, password `E2e-Isolated-Only-2026` (valid only for this test database):

| Account | Role on these documents |
| --- | --- |
| `e2e.creator@example.test` | Creator. Can open documents they created. Cannot review, release, or recover. |
| `e2e.reviewer@example.test` | Department primary reviewer. |
| `e2e.backup@example.test` | Department backup. Current holder of `DOC-2026-000005` only. |
| `e2e.approver@example.test` | Final approver. Current holder of `DOC-2026-000002`. |
| `e2e.admin@example.test` | Administrator. No approval authority unless assigned. |
| `e2e.releaser@example.test` | Release permission only. |
| `e2e.receiver@example.test` | Receiving department. View of the released document only. |
| `e2e.outsider@example.test` | No access. |

Live UI result cells are intentionally blank.

## 1. Automated behavior already verified

Verified by the isolated API run against `hrms_plaridel_docutracker_e2e`. Not verified on screen.

- `DOC-2026-000002`: status `in_review`, step 2, holder E2E Final Approver. History actions `created`, `submitted`, `forwarded`. Forward notification title `Document forwarded to you`.
- `DOC-2026-000003`: status `returned`, step 1, holder E2E Reviewer. History actions `created`, `submitted`, `approved`, `returned`. Return notification title `Document returned for your review`.
- `DOC-2026-000006`: status `approved`, `release_required` true, released. History actions `created`, `metadata_updated`, `submitted`, `approved`, `signed`, `approved`, `released`. Receiver can view and cannot edit or release. Outsider receives 403. Creator cannot release.
- `DOC-2026-000004`: status `rejected`.
- `DOC-2026-000005`: status `in_review`, step 1, holder E2E Backup Reviewer. History actions `created`, `submitted`, `assigned`. Employee received 403 on recovery candidates. Administrator could not approve. The admin-attention flag is now false because recovery already completed.

Shared database counts were unchanged during that run (21 documents, 119 history rows, 14 users).

## 2. Live UI verification — Phase 1, 2026-10-28

Isolated app only: API `http://127.0.0.1:3001` on `hrms_plaridel_docutracker_e2e`, Flutter `http://127.0.0.1:5051`, separate Chrome profile. No workflow action was confirmed. Shared `hrms_plaridel` stayed at 21 documents, 119 history rows, and 14 users. PM2 `hrms-backend` stayed pid 8432, restart count 0.

Sign-in succeeded for the creator, department reviewer, backup reviewer, final approver, receiving employee, administrator, and outsider. Passwords are not recorded here.

Desktop means about 1384px, light theme, unless a cell says otherwise. A later pass on the same isolated app checked dark theme on `DOC-2026-000004`, `DOC-2026-000005`, and `DOC-2026-000006`, opened their full maps, and opened workflow dialogs without confirming them. Shrinking an open document from desktop width to about 390px still leaves the document and shows the employee dashboard. Opening the same document again from that narrow dashboard works.

### DOC-2026-000002 — Forwarded, currently in review

Opened again as `e2e.approver@example.test`. `Approve and Complete` opened `Approve final step?` and was cancelled. `Forward Without Approval` is not on this step. `More` contains Download Attachment, `Return to Previous Step`, and `Reject and Stop`. The return dialog was opened and cancelled. Status stayed In review.

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Status | In review. Not approved, released, or awaiting release. | PASS | BLOCKED | PASS | PASS |
| Step 1 strip | Name `Department review`. Label `Forwarded`. Reviewer name `E2E Reviewer`. Not `Approved`. | PASS | BLOCKED | PASS | PASS |
| Step 2 strip | Name `Final approval`. Label `Current step`. Detail `In review`. Reviewer name `E2E Final Approver`. | PASS | BLOCKED | PASS | PASS |
| Upcoming | None. This workflow has two steps. | PASS | BLOCKED | PASS | PASS |
| Full map | Same two rows, same labels, same names, in the same order as the strip. | PASS | BLOCKED | PASS | BLOCKED |
| Activity history | `submitted`, then `forwarded`. No `approved` on this document. Forward actor is E2E Reviewer. | PASS | BLOCKED | PASS | PASS |
| Approve dialog | Button may be shown to the final approver. Title `Approve final step?`. Copy says workflow approval finishes and distribution still requires a release. Cancel. | PASS | BLOCKED | PASS | BLOCKED |
| Forward dialog | If shown, title `Forward without approval?`. Copy says the move does not record an approval. Cancel. | Not offered | BLOCKED | Not offered | BLOCKED |
| Return dialog | Title `Return to previous step`. Copy does not say the creator can edit or resubmit. Reason is optional. Cancel. | PASS | BLOCKED | PASS | BLOCKED |
| Admin Recovery card | Absent. This document is not flagged. | PASS | BLOCKED | PASS | PASS |

### DOC-2026-000003 — Returned to the previous reviewer

Opened as `e2e.creator@example.test`, not as the department reviewer. The reviewer account did sign in. Its action buttons on this document were not rechecked. History is newest first: returned, then approved, then submitted. Both the approval and the return stay visible. Return card: reason `Send back`, returned by E2E Final Approver, 2026-10-28 08:56.

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Status | Returned. Current step is Department review. | PASS | BLOCKED | PASS | PASS |
| Step 1 strip | Label `Current step`. Detail `Returned · Previous visit: Approved`. Reviewer name `E2E Reviewer`. | PASS | BLOCKED | PASS | PASS |
| Step 2 strip | Label `Returned`. Reviewer name `E2E Final Approver`. Not Pending, and not the current step. | PASS | BLOCKED | PASS | PASS |
| Full map | Same two rows as the strip. | PASS | BLOCKED | PASS | BLOCKED |
| Activity history | `submitted`, `approved`, `returned`, in that order. Return does not remove the earlier approval. | PASS | BLOCKED | PASS | PASS |
| Return dialog | If a further return is offered, title `Return to previous step`. Copy does not say the creator can edit or resubmit. Cancel. Step 1 may hide Return because there is no earlier step. | BLOCKED | BLOCKED | BLOCKED | BLOCKED |
| Approve dialog | If shown, title `Approve and continue?`. Copy says approval advances to the next step and does not finish the workflow. Cancel. | BLOCKED | BLOCKED | BLOCKED | BLOCKED |
| Admin Recovery card | Absent. | PASS | BLOCKED | PASS | PASS |

### DOC-2026-000006 — Approved and released

Opened as the creator, as E2E Receiver, and again in dark theme as the receiver. The document page shows Released and "This workflow is complete." The full map matches the strip. The earlier dashboard mismatches were fixed: the creator's completed card says Released, and the receiver dashboard has a "Released to you" section. At about 390px the receiver can open this document from that section, and View full map matches the strip.

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Phase | `Released`, detail `Approved and released`. Not `Awaiting release`. | PASS | PASS | PASS | PASS |
| Step 1 strip | Label `Approved`. Reviewer name `E2E Reviewer`. | PASS | PASS | PASS | PASS |
| Step 2 strip | Label `Approved`. Detail `Released`. Reviewer name `E2E Final Approver`. | PASS | PASS | PASS | PASS |
| Full map | Same two rows as the strip. | PASS | PASS | PASS | PASS |
| Content | Read-only. No edit of title or description. | PASS | PASS | PASS | PASS |
| Activity history | Includes `submitted`, `approved`, `signed`, `approved`, `released`. | PASS | BLOCKED | PASS | PASS |
| Receiver | Can view. Cannot release and cannot edit. | PASS | PASS | PASS | PASS |
| Outsider | `e2e.outsider@example.test` cannot open this document. | PASS | BLOCKED | PASS | BLOCKED |
| Workflow actions | Approve, Forward, Return, and Reject are not offered. | PASS | PASS | PASS | PASS |

### DOC-2026-000004 — Rejected

Opened as the creator in light theme, then again in dark theme. Banner: "This document was rejected and cannot move forward." Current step: "Stopped at Step 1", detail Rejected. The full map matches the strip. History includes submitted and rejected, with the rejection by E2E Reviewer.

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Phase | Closed. Detail `Rejected — workflow finished`. | PASS | BLOCKED | PASS | PASS |
| Step 1 strip | Label `Rejected`. Reviewer name `E2E Reviewer`. | PASS | BLOCKED | PASS | PASS |
| Step 2 strip | Label `Pending`. No reviewer name. | PASS | BLOCKED | PASS | PASS |
| Full map | Same two rows as the strip. | PASS | BLOCKED | PASS | PASS |
| Activity history | Includes `submitted` and `rejected`. | PASS | BLOCKED | PASS | PASS |
| Workflow actions | No further Approve, Forward, Return, or Reject. | PASS | BLOCKED | PASS | PASS |
| Admin Recovery card | Absent. | PASS | BLOCKED | PASS | PASS |

### DOC-2026-000005 — Admin Recovery already completed

Opened as the creator in dark theme, as E2E Backup Reviewer, and as E2E Administrator. The creator can open it and does not see a recovery action. Expanded history shows Step 1, remarks `Synthetic recovery`, recorded action `assigned`, actor E2E Administrator, 2026-10-28 08:56. The administrator's More menu is Download Attachment only. The backup reviewer opened Approve, Forward, and Reject and cancelled each one. Return is not offered on this step. Status stayed In review.

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Status | In review. Current step is Department review. | PASS | PASS | PASS | PASS |
| Step 1 strip | Label `Current step`. Detail `In review`. Reviewer name `E2E Backup Reviewer`. | PASS | PASS | PASS | PASS |
| Step 2 strip | Label `Pending`. No reviewer name. | PASS | FAIL | PASS | PASS |
| Full map | Same two rows as the strip. | PASS | BLOCKED | PASS | PASS |
| Activity history | `submitted`, then `assigned`. Assigned actor is E2E Administrator. Remarks `Synthetic recovery`. | PASS | BLOCKED | PASS | PASS |
| Admin attention card | Absent for every role. Recovery already cleared the flag. | PASS | BLOCKED | PASS | PASS |
| Recover Assignment | Not shown. Do not treat this document as proof of the recovery dialog. | PASS | BLOCKED | PASS | PASS |
| Creator | Can open the document. Does not see a recovery action. | PASS | BLOCKED | PASS | PASS |
| Backup reviewer | Is the current holder. Does not see Recover Assignment. | PASS | PASS | PASS | BLOCKED |

### Visual checks on every opened screen

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Names | Reviewer names are fully readable or end in an ellipsis inside the step column. | PASS | FAIL | PASS | PASS |
| Strip | Horizontal scroll is available. Labels are not cut off by the card edge. | PASS | FAIL | PASS | PASS |
| Map | No second, conflicting status beside the strip. | PASS | PASS | PASS | PASS |
| Cards | No overflow stripes. | PASS | PASS | PASS | PASS |
| Loading | A short loading state, then the document. Empty history is not shown when rows exist. | PASS | BLOCKED | PASS | PASS |
| Stay on document | The open document remains when the viewport changes. | PASS | FAIL | PASS | PASS |

At about 390px, `DOC-2026-000005` shows both workflow steps, but the second step name is clipped to "Final approva". Dragging that strip did not scroll it. Approve and Continue and Forward Without Approval remain fully visible for the assigned reviewer. No overflow stripes were seen.

Observed UI problems:

- Shrinking an open document below the 600px employee-shell switch replaces the document with the dashboard. This is the app layout, not a browser navigation. Opening the document again after the narrow shell is already active works.
- The admin document list, and the creator's document list, truncate the assignee as "E2E Backup Revie...". The full name "E2E Backup Reviewer" is in the row's accessible name and on the document page. Shorter names such as "E2E Reviewer" and "E2E Final Approver" fit.
- "Available actions for this workflow step" still wraps, including at 390px, as "Available actions for this" and then "workflow step". The actions under it stay readable.
- The Reject dialog's Reject button is solid red while the required reason is empty. It is not disabled. The dialog was cancelled without entering a reason and without clicking Reject.
- The two earlier dashboard mismatches are fixed. The creator's completed card for `DOC-2026-000006` says Released. The receiver dashboard lists that document under "Released to you".

## 3. Scenarios that need more isolated fixtures

These states are not present in `hrms_plaridel_docutracker_e2e`. Do not create them in `hrms_plaridel`.

| Missing case | Why the current documents cannot cover it |
| --- | --- |
| Awaiting release | `DOC-2026-000006` is already released. No approved, unreleased document remains. |
| Overdue | No document has status `overdue`. |
| Escalated | No document has status `escalated`. |
| Recover Assignment dialog | `DOC-2026-000005` and `DOC-2026-000010` were recovered. `needs_admin_intervention` is false, so the card and dialog stay hidden. |
| Approve / Forward / Return / Reject dialogs on a fresh step | Opened and cancelled where the button exists. See the dialog results below. `DOC-2026-000003` was not opened again as the department reviewer, so its own buttons stay unchecked. |

Dialog copy to compare when a future isolated fixture still has the button:

| Action | Title | Required point |
| --- | --- | --- |
| Intermediate approve | `Approve and continue?` | Advances to the next step and does not finish the workflow. |
| Final approve on `e2eNotice` | `Approve final step?` | Finishes workflow approval. Distribution still requires a release. |
| Forward | `Forward without approval?` | Moves the document and does not record an approval. |
| Return | `Return to previous step` | Does not say the creator can edit or resubmit. |
| Reject | `Reject document` | Says the workflow stops. A reason is required. Confirm stays disabled until a reason is entered. Cancel. |

Dialog results from this pass. None of these actions were confirmed, and the documents stayed in their previous status.

| Action | Where opened | Result |
| --- | --- | --- |
| Intermediate approve | `DOC-2026-000005` as E2E Backup Reviewer | PASS. Title `Approve and continue?`. Copy says approval advances to the next step and does not finish the workflow. Cancelled. |
| Final approve | `DOC-2026-000002` as E2E Final Approver | PASS. Title `Approve final step?`. Copy says workflow approval finishes and distribution still requires a release. Confirm label is `Approve`. Cancelled. |
| Forward | `DOC-2026-000005` as E2E Backup Reviewer | PASS. Title `Forward without approval?`. Copy says the move does not record an approval. Confirm label is `Forward`. Cancelled. Not offered on `DOC-2026-000002`. |
| Return | `DOC-2026-000002` as E2E Final Approver, step 2 | PASS. Title `Return to previous step`. Copy says the previous reviewer becomes responsible, content stays read-only, and no correction task is created for the author. Reason is optional. Cancelled. Not offered to the backup reviewer on step 1 of `DOC-2026-000005`. |
| Reject | `DOC-2026-000005` as E2E Backup Reviewer, under More as `Reject and Stop` | FAIL. Title `Reject document`. Copy says the workflow stops and a reason is required. The Reject button stays visually enabled before a reason is entered. Cancelled without typing a reason. |

## Blockers

- Shrinking an open document below 600px drops it and shows the employee dashboard. At about 390px the second workflow step name is clipped and the strip did not scroll horizontally.
- The Reject confirm button is not disabled while its required reason is empty.
- `DOC-2026-000003` action buttons were not opened again as the department reviewer.
- Recover Assignment dialog is still pending. `DOC-2026-000005` and `DOC-2026-000010` are already recovered, and `needs_admin_intervention` is false.
- Awaiting release, overdue, and escalated fixtures are still absent. Do not create them for this pass.
