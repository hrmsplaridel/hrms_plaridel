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

Phase 1 completion was manually verified in the browser after the three UI fixes: the open document survives responsive resizing, the narrow workflow strip scrolls without permanently clipping its steps, and Reject stays disabled until a valid reason is entered. The deferred Admin Recovery dialog check was completed in the Phase 2 browser follow-up on `DOC-2026-000017` (cancel only).

Sign-in succeeded for the creator, department reviewer, backup reviewer, final approver, receiving employee, administrator, and outsider. Passwords are not recorded here.

Desktop means about 1384px, light theme, unless a cell says otherwise. A later pass on the same isolated app checked dark theme on `DOC-2026-000004`, `DOC-2026-000005`, and `DOC-2026-000006`, opened their full maps, and opened workflow dialogs without confirming them. After the Phase 1 fix, shrinking an open document from desktop width to about 390px keeps the same document open, and resizing back to desktop also preserves it.

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
| Step 2 strip | Label `Pending`. No reviewer name. | PASS | PASS | PASS | PASS |
| Full map | Same two rows as the strip. | PASS | BLOCKED | PASS | PASS |
| Activity history | `submitted`, then `assigned`. Assigned actor is E2E Administrator. Remarks `Synthetic recovery`. | PASS | BLOCKED | PASS | PASS |
| Admin attention card | Absent for every role. Recovery already cleared the flag. | PASS | BLOCKED | PASS | PASS |
| Recover Assignment | Not shown. Do not treat this document as proof of the recovery dialog. | PASS | BLOCKED | PASS | PASS |
| Creator | Can open the document. Does not see a recovery action. | PASS | BLOCKED | PASS | PASS |
| Backup reviewer | Is the current holder. Does not see Recover Assignment. | PASS | PASS | PASS | BLOCKED |

### Visual checks on every opened screen

| Check | Expected | Desktop | Narrow | Light | Dark |
| --- | --- | --- | --- | --- | --- |
| Names | Reviewer names are fully readable or end in an ellipsis inside the step column. | PASS | PASS | PASS | PASS |
| Strip | Horizontal scroll is available. Labels are not cut off by the card edge. | PASS | PASS | PASS | PASS |
| Map | No second, conflicting status beside the strip. | PASS | PASS | PASS | PASS |
| Cards | No overflow stripes. | PASS | PASS | PASS | PASS |
| Loading | A short loading state, then the document. Empty history is not shown when rows exist. | PASS | BLOCKED | PASS | PASS |
| Stay on document | The open document remains when the viewport changes. | PASS | PASS | PASS | PASS |

Before the Phase 1 fix, at about 390px, `DOC-2026-000005` showed both workflow steps, but the second step name was clipped to "Final approva" and the strip did not scroll. After the fix, the strip scrolls and the step is accessible. Approve and Continue and Forward Without Approval remain fully visible for the assigned reviewer. No overflow stripes were seen.

Observed UI problems from the pre-fix pass:

- Resolved: shrinking an open document below the 600px employee-shell switch previously replaced the document with the dashboard. Manual browser verification confirms the same document now remains open.
- The admin document list, and the creator's document list, truncate the assignee as "E2E Backup Revie...". The full name "E2E Backup Reviewer" is in the row's accessible name and on the document page. Shorter names such as "E2E Reviewer" and "E2E Final Approver" fit.
- "Available actions for this workflow step" still wraps, including at 390px, as "Available actions for this" and then "workflow step". The actions under it stay readable.
- Resolved: the Reject dialog previously showed an enabled-looking red button while the required reason was empty. Manual browser verification confirms Reject now stays disabled until a valid reason is entered.
- The two earlier dashboard mismatches are fixed. The creator's completed card for `DOC-2026-000006` says Released. The receiver dashboard lists that document under "Released to you".

## 3. Scenarios that need more isolated fixtures

These states are not present in `hrms_plaridel_docutracker_e2e`. Do not create them in `hrms_plaridel`.

| Missing case | Why the current documents cannot cover it |
| --- | --- |
| Awaiting release | `DOC-2026-000006` is already released. No approved, unreleased document remains. |
| Overdue | Later covered by Phase 2 disposable state drift (`011`–`014`, `017` became `overdue`). |
| Escalated | No document has status `escalated`. |
| Recover Assignment dialog | Originally unavailable on `DOC-2026-000005` / `010` after recovery cleared the flag. Later covered on overdue flagged disposable `DOC-2026-000017` (Phase 2 browser follow-up, cancel only). |
| Approve / Forward / Return / Reject dialogs on a fresh step | Covered in Phase 1 where buttons existed, and again in Phase 2 browser follow-up on disposable overdue holders (`011`, `012`) with Cancel only. |

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
| Reject | `DOC-2026-000005` as E2E Backup Reviewer, under More as `Reject and Stop` | PASS after the Phase 1 fix. Confirm stays disabled until a valid reason is entered. |

## Blockers

- `DOC-2026-000003` action buttons were not opened again as the department reviewer (covered instead on disposable Phase 2 holders).
- Recover Assignment dialog: resolved in Phase 2 browser follow-up on `DOC-2026-000017`.
- Awaiting-release and escalated dedicated fixtures remain absent. Overdue now exists via Phase 2 disposable state drift; do not create extra fixtures for this pass.

## 4. Phase 2 interactive workflow testing — 2026-10-30

### Environment and evidence boundary

- API: `http://127.0.0.1:3001`
- Flutter: `http://127.0.0.1:5051`
- Confirmed database before writes and during final evidence capture: `hrms_plaridel_docutracker_e2e`
- The isolated API was restarted without shared PM2. Leave accrual cron and startup recovery, refresh-token cleanup, year-end forced leave, backup scheduling, and the DocuTracker escalation worker were disabled only in the isolated process.
- Baseline protected documents `DOC-2026-000002` through `DOC-2026-000006` and `DOC-2026-000010` retained their status, step, holder, and attention flag.
- All Phase 2 workflow actions below were performed through authenticated normal APIs against fresh disposable documents. The browser-control host was unavailable, so browser-only checks and screenshots are `BLOCKED`; they are not recorded as application failures.

| Test | Disposable document | Account / role and action | Expected result | Actual result | Result | History and notification evidence |
| --- | --- | --- | --- | --- | --- | --- |
| A — Submit | `DOC-2026-000011` | E2E Creator created, edited, and submitted | Assign step 1, notify reviewer, make content read-only | API: status was `in_review`, step 1 holder E2E Reviewer; creator edit 403 read-only. Browser 2026-11-02: opened as E2E Reviewer; content read-only; strip/map Current step Overdue · E2E Reviewer, Final approval Pending; history `submitted` by E2E Creator then later `overdue`. Live status drifted to `overdue` + `needs_admin_intervention=true` after the API pass. | API PASS / browser PASS (result UI) | History UI: submitted + overdue. API already proved reviewer notification. Browser notification panel not re-opened this pass. |
| B — Approve | `DOC-2026-000012` | E2E Reviewer approved step 1 | Advance to step 2 and notify final approver | API advanced to step 2 / E2E Final Approver. Browser: opened as approver; strip/map Department review Approved · E2E Reviewer, Final approval Current step Overdue · E2E Final Approver; `Approve and Complete` offered; signature required copy shown; history includes step-1 `approved` then `overdue`. | API PASS / browser PASS (result UI) | History UI matches prior API actors. Live status now overdue + admin attention. |
| C — Forward | `DOC-2026-000013` | E2E Reviewer forwarded without approval | Advance without recording approval; notify next reviewer | API recorded `forwarded` only. Browser: opened as approver; strip/map Department review Forwarded · E2E Reviewer, Final approval Current step Overdue · E2E Final Approver; history `forwarded` by E2E Reviewer then `overdue`. No approval event on this document. | API PASS / browser PASS (result UI) | History UI matches. Live status now overdue + admin attention. |
| D — Return | `DOC-2026-000014` | E2E Final Approver returned step 2 to step 1 | Previous reviewer becomes responsible; preserve reason; content remains read-only | API returned to step 1 / E2E Reviewer. Browser: opened as reviewer; strip/map Current step Overdue · Previous visit: Approved · E2E Reviewer, Final approval Returned · E2E Final Approver; history keeps `approved` then `returned` then `overdue`; content read-only. | API PASS / browser PASS (result UI) | Returned strip labels PASS in browser. Live status now overdue + admin attention. |
| E — Reject | `DOC-2026-000015` | E2E Reviewer rejected with a required reason | Stop workflow and notify creator | API rejected. Browser (creator + reviewer): Status Rejected; strip/map Rejected · E2E Reviewer / Pending; banner rejected cannot move forward; no Approve/Forward/Return/Reject; history `rejected` + `submitted`; dark mode detail PASS. | API PASS / browser PASS | Creator list Completed shows REJECTED. |
| F — Final approval and release | `DOC-2026-000016` | E2E Final Approver attempted approval before signing, signed, then approved; E2E Releaser released | Enforce signature; reach approved-awaiting-release; release; receiving department gets view-only access | API already completed release. Browser: creator + receiver see Released / finalized read-only / workflow complete; strip/map Approved then Approved Released; history released → approved → signed → approved → submitted; receiver banner “Released to your department — view only”; no release/approve actions. Outsider cannot find/open the row. | API PASS / browser PASS | Receiver view-only PASS. Outsider list miss PASS. |
| G — Admin Recovery | `DOC-2026-000017` | E2E Administrator recovered a safely flagged disposable document to E2E Backup Reviewer | Show only eligible candidates; require remarks; reassign; clear flag; prevent admin approval | API recovery PASS earlier. Browser post-state PASS. Recover Assignment dialog cancel-peek 2026-11-02 PASS: eligible `E2E Reviewer (Primary)`, remarks required, Confirm disabled while empty, Cancel only (`shots/phase2-remain2-017-recover.png`). Flag later re-set by overdue drift. | API PASS / browser PASS (post-recovery UI + Recover dialog) | Do not re-confirm recovery. |

### Browser follow-up — 2026-11-02

Environment: Flutter `http://127.0.0.1:5051` → API `http://127.0.0.1:3001` / DB `hrms_plaridel_docutracker_e2e`. Shared PM2 backend and shared HRMS DB were not modified. No irreversible workflow actions were repeated.

Observed after API Phase 2: disposable docs `011`–`014` and `017` later show `overdue` + `needs_admin_intervention=true` (history action `overdue` at 2026-11-02 20:44). Report as state drift; do not invent a re-run of API A–G.

| Check | Result | Notes |
| --- | --- | --- |
| Desktop detail + full map + activity history for A–G result states | PASS | Screenshots under `AppData/Local/Temp/docutracker-e2e/shots/phase2-*` |
| Dark mode on open documents | PASS | Creator/reviewer/approver/admin detail dark shots |
| Employee narrow/mobile stay-on-document | PASS | Fixed 2026-11-02: stable employee page host + content navigator. Recheck on `DOC-2026-000011` / `017` stayed open 1384→390→1384. |
| Intermediate Approve dialog (cancel only) | PASS | Title `Approve and continue?`. Copy: advances to the next step and does not finish the workflow. Cancelled. Evidence: `shots/phase2-remain-011-approve-continue.png` on `DOC-2026-000011` as E2E Reviewer. |
| Forward dialog (cancel only) | PASS | Title `Forward without approval?`. Copy: moves to the next step and does not record an approval. Cancelled. Evidence: `shots/phase2-remain-011-forward.png`. |
| Reject dialog (cancel only) | PASS | Title `Reject document`. Copy: stops the workflow; reason required. Confirm stays disabled while empty. Cancelled. Evidence: `shots/phase2-remain-011-reject.png`. |
| Final Approve dialog (cancel only) | PASS | Title `Approve final step?`. Copy: finishes workflow approval; distribution still requires a release. Cancelled. Evidence: `shots/phase2-remain-012-approve-final.png` on `DOC-2026-000012` as E2E Final Approver. |
| Return dialog (cancel only) | PASS | Title `Return to previous step`. Copy: previous reviewer becomes responsible; content stays read-only; no correction task for the author. Cancelled. Evidence: `shots/phase2-remain2-012-return.png`. |
| Recover Assignment dialog (cancel only) | PASS | Opened as E2E Administrator on `DOC-2026-000017`. Shows current step/reviewer/department; eligible replacement `E2E Reviewer (Primary)`; remarks required; Confirm disabled while empty; Cancelled. Evidence: `shots/phase2-remain2-017-recover.png`. |
| Browser notification contents | PASS (API + dashboard Recent Activity) / BLOCKED (dedicated DocuTracker notification sheet) | API `/api/docutracker/notifications` matches A–G (submitted/assigned, previous-step approved, forwarded, returned, rejected, released, reassigned, overdue/admin intervention). Dashboard DocuTracker Recent Activity UI shows matching titles for reviewer/creator/admin. Automated click of the header bell did not reliably open the dedicated DocuTracker notification sheet this pass. |
| Action visibility by role | PASS | Reviewer `011`: Your turn + Approve/Forward/Reject. Approver `012`: Approve and Complete + Return. Admin `017`: Recover Assignment, not Your turn. Backup `017`: Your turn + Approve/Forward (`shots/phase2-vis-backup-017.*`). Receiver `016`: Released view-only, no approve/forward/recover (`shots/phase2-vis-receiver-016.png`). Outsider: API list empty (0 docs). Creator browser re-open of `011` was flaky this pass; earlier Phase 2 creator result UI already showed no review actions. |
| Document state after cancel-only peeks | PASS | `011`/`012`/`017` remained `overdue` with the same step/holder/admin flag after all Cancel peeks. No accidental submits observed. |
| Confusing overdue UX | PASS (fixed) | UI now uses advisory Admin attention copy when the holder remains eligible (`reassignment_required` false). Blocking copy reserved for true reassignment-required cases. |

### Phase 2 status

API A–G remain PASS. Browser result UIs, dark mode, responsive stay-on-document, overdue/Admin Recovery messaging, and all six workflow confirmation dialogs (Approve continue, Final approve, Forward, Return, Reject, Recover Assignment) are PASS with cancel-only evidence. Notification **data** matches completed workflow actions (API + Recent Activity). The dedicated DocuTracker notification sheet click remains **BLOCKED** for automation only. Phase 2 browser acceptance is **complete for workflow dialogs and role visibility**; residual automation gap is limited to opening the dedicated notification sheet. No irreversible workflow actions were repeated. Do not start another development phase automatically.
