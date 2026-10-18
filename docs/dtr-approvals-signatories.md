# Shared approval workflows: Leave, Locator, and DocuTracker

Open **DTR → Approvals & Signatories → Workflows** or **DocuTracker → Admin →
Workflows → Shared approval workflows**. Both entry points use the same workflow
catalog and published versions.

## Configure a workflow

1. Choose **New workflow** and enter a name.
2. Choose **Add approval step**. This opens the existing DocuTracker step editor.
3. Enter the step's name and select its primary and optional backup employee.
   Employee search accepts a name, department, or position. You can instead use
   the applicant's department reviewers, a retained fixed department, configured
   Final HR reviewers, or the currently effective Municipal Mayor.
4. Use each step's menu to edit approvers, move it up/down, or remove it.
5. Publish. The last electronic approval step is the final approval.

Workflows support 1–20 steps. Names and order are configurable; they are not
restricted to Department → HR → Mayor. Each electronic approval requires a
signature. Approve is required; Return and Reject can be enabled per step.
Forward without approval and per-step deadlines remain DocuTracker-specific
settings outside this shared approval editor.

Manual Mayor signing is available as the last step following a system approval.
It completes the system approval at the preceding step and prints a blank Mayor
signature area for signing on paper. Electronic Mayor approval requires an
actual Mayor decision in the approval queue.

Leave and Locator types have an **Approval workflow** dropdown for choosing the
saved workflow. Filing eligibility and availability are configured on the request
type; the workflow defines approval steps and reviewers. **Active workflow**
controls whether the workflow can be selected. New filings follow the selected
workflow without employment-based route substitution. Legacy workflow employment
metadata is retained for history and no longer controls routing.

## Review requests

Custom workflow requests appear in the existing Leave approval queue and Locator
request list alongside the existing requests. There is no separate Workflow
approvals button or approval page. Employee reviewers use the existing Leave
**Approvals** or Locator **Approvals / History** tab. Assigned primary and backup
reviewers can open a row and record their decision there, including ordinary
employees without an HR designation. Notifications open the corresponding module
approvals for employees, HR, administrators, and the Mayor.

The employee Leave **Approvals** tab requires confirmed department/final reviewer
access or assigned workflow requests/review history. An unassigned employee sees
personal requests even when an old navigation link selects Approvals. Pending or
failed access lookups do not grant the tab, and delayed results from a previous
account are ignored.

Electronic Mayor Leave alerts appear in the bell list and unread count when the
request has a saved workflow with an electronic Mayor route. Retired alerts for
manual Mayor signing remain hidden. Tapping either a pending or forwarded Mayor
Leave alert opens the existing Leave approvals screen.

Notifications forwarded between workflow steps include the employee name, leave
type, inclusive dates, and the next review step, just like the initial review
notification. The notification card's muted/accent appearance reflects its
read/unread state. Previously created notification text is not rewritten.

Leave workflow reviewers open the existing responsive Leave side-panel host and
reuse the existing Leave details header and details panel, including its spacing,
attachment tile, history timeline, and scrollable **Actions** section. Preview
and Print use that section alongside the permitted review actions. There is no
separate workflow footer layout. Both ordinary and workflow requests share the
same `LeaveRequestInformation` layout.
Department, HR, specific-person, and Mayor reviewers see official employee
snapshots, leave dates, relevant filing fields, and labeled custom answers.
Additional Context includes only populated fields for the selected leave type
and its saved custom-field schema. It omits empty rows, unrelated legacy values,
and the duplicate custom leave name already shown in Leave Details. The section
is hidden when no contextual values are present; zero and No remain valid answers.
The workflow review panel shows the current review cycle's submitted/decision
timeline and the active reviewer's signature; it does not print raw JSON keys or
unrelated null-valued fields. Its API payload allowlists filing details and
official snapshots; attachment storage paths remain private.

The Leave list requests `GET /api/approval-workflows/inbox?include_history=true`.
It retains requests with the viewer's recorded decision in the current review
cycle after they move to the next reviewer or finish. These rows return
`can_review: false` and no allowed actions unless the viewer is eligible for the
current step. They open as read-only history and do not increase the viewer's
pending count. The default inbox remains pending assignments only. Successful
decisions show a confirmation snackbar (including the next step when returned
by the server); failed decisions keep the details open with inline and snackbar
feedback.

The active signing box belongs to the current workflow step. When a request
advances, Leave and Locator suppress ink left in the shared signing slot by an
earlier approving actor. Completed step signatures remain available as read-only
`workflow_step_N` snapshots for history/printing. A signature already supplied
for the current step remains visible, and finalized forms retain their final ink.

Leave submission explicitly confirms the applicant's selected signature asset
after all filing and routing changes, in the same database transaction. The
confirmation uses the final submitted signature revision, verifies ownership of
both the request and asset, and records a signing history entry. This covers
ordinary submissions, submissions with attachments, and draft/returned request
submissions. Draft saves do not confirm a submitted signature, and API reads do
not copy historical signatures into newer revisions. Existing approved requests
with only an obsolete applicant confirmation are not changed by this fix.

The standard CSC form does not append an automatic **Additional Leave
Information** page. Custom answers remain in the request details and are
available to custom print layouts. The applicant signature belongs on the main
form.

The reviewer can inspect the submitted details and attachment, sign with the
existing DocuTracker signature UI, and approve, return, or reject according to
that step's configured actions. For Leave, the reviewer can specify days with
and without pay. The final system approval applies credits and DTR coverage;
intermediate approvals only record their decision/signature and advance routing.

The applicant cannot approve their own request. An employee who approved an
earlier step cannot approve another step in that review cycle. Filing and
forwarding require a possible assignment of distinct eligible reviewers for all
remaining stages. The first valid primary/backup decision wins; concurrent or
stale decisions are checked again against the locked request and signature
revision, including requests resubmitted after return.

Preview and Print recognize current shared-workflow reviewers and participants
with a recorded decision on that request, including a department reviewer after
forwarding to HR. Request refresh, form-specific VL/SL credits, template metadata,
and PDF rendering use this request-scoped read access. It does not grant access
to an employee's general balances or permission to approve a later step.

Custom steps use existing pending HR/Mayor database statuses for compatibility;
the request list and review dialog identify the actual named step and reviewers. Legacy
requests continue to use their existing review pages and routing rules.
Employee Locator lists, details, and status searches use the saved workflow's
current step as well. A `pending_hr` request at Department Review therefore shows
**Pending Department Review**. Final statuses and legacy requests retain their
existing route-specific labels.

Locator workflow reviews use the existing responsive Locator **Request Details**
panel at Department, HR, and Mayor stages, including labeled filing fields,
signatures, attachments, and history. Approved requests retain Preview and Print.
Pending shared workflows come from the assigned-reviewer inbox; the legacy
management list, counts, and filter options exclude them so `pending_hr` cannot
expose a department-stage request to an unassigned HR reviewer. Prior reviewers
retain read-only workflow history after forwarding. Locator service dates use
the database date text rather than converting midnight to UTC.
The management queue places actionable assigned workflow requests before older
records, including when a realtime update forwards a request to HR.
Completed workflow records opened from management also use this panel when the
viewer has no inbox entry. They show saved workflow history without approval
controls, and retain approved-form Preview/Print, permitted Revoke Approval,
review remarks, and revocation information. The old admin details fallback is
reserved for requests without shared workflow steps.

## Use the same workflow for DocuTracker documents

DocuTracker shows one mirrored card per saved workflow/version, grouping active
Leave and Locator types that select it. The card shows a compact **Used by**
count; **View details → Used by** expands the full type list. Separate workflow
identities or versions remain separate even when their names match.

Local verification on 2026-10-16 reduced 16 active Leave types and five Locator
types to three workflow cards. Grouping checks, reviewer-role regressions, and
related workflow tests passed (66 backend, 18 Flutter); the four changed UI/test
files passed static analysis. The local backend was restarted and application,
database, and authenticated mirror checks passed. This change needs no migration.

In **DocuTracker → Admin → Workflows → Shared approval workflows**, use the link
icon on a workflow and select a document type. This publishes a corresponding
DocuTracker workflow version using the same step definitions, primary/backups,
actions, and signature requirements.

Publishing a shared workflow edit also publishes new versions for linked document
types in the same transaction. Existing documents keep their pinned version.
DocuTracker blocks separate edits to a linked configuration or a shared version's
normalized assignees, so it cannot drift from the shared catalog. Editing a linked
workflow card opens the shared catalog.

Electronic approval workflows can be shared with DocuTracker documents. Manual
Mayor signing remains specific to Leave/Locator; remove manual signing steps
before linking that workflow to a general document type.
Existing independent DocuTracker document workflows remain unchanged until a
shared workflow is selected for their type. DocuTracker's document permissions,
holder/escalation rules, and Admin Recovery continue to apply to documents.

## Reviewers and printed officials

**Workflows** is the single approval configuration entry. Open a workflow and use
the **Configure … reviewers** action beside its Department or HR step, or open
**Edit approvers → Configure reviewers**. The separate Reviewer Assignments tab
has been retired.

Specific-person steps keep their own selected primary and backups. Department
and Final HR steps configure shared reviewer groups directly from the workflow
editor, including effective dates, primary designations and ordered backups. A
shared-group change affects every workflow referencing that group; the dialog
explains this before saving. Route edits still require **Publish workflow**.
Unsaved backup edits must be saved or explicitly discarded before closing.
Current Mayor steps resolve the effective active Mayor.

This consolidation changes the configuration UI and reuses the existing reviewer
APIs; it does not migrate routes, rewrite pending request snapshots, or change
approval authorization. Report Signatories remains separate for printed reports.

**Report Signatories** manages effective-dated printed report officials; it does
not grant workflow approval permission.

Every approval stores its actor and current-revision signature. Shared workflows
preserve each step's ink and the actual reviewer's name/title, including a backup
who acted. Standard forms use the first and final signature areas; intermediate
signatures remain in the workflow history/signature bundle. Manual Mayor forms
keep Mayor ink blank. Legacy signature and printed-official rules are preserved.

DocuTracker's read-only Leave/Locator configuration mirrors show the selected
workflow, version, custom labels, and reviewer groups. Linked Leave documents
show saved request steps and actual decisions. This does not create a second
Leave/Locator approval process or add a new Locator document source integration.

## Versions and existing requests

Publishing appends a new version. New filings use it. Existing requests retain
their saved workflow/version and explicit reviewer selections. The same returned
request/type starts a new review cycle with its saved workflow; changing its type
uses that type's current workflow. Old cycle decisions are archived.

Dynamic authority sources continue to resolve eligible active reviewers. A
specific-person primary who becomes inactive must have an eligible configured
backup; editing the workflow affects future filings, not an existing request's
saved version. Historical requests without snapshots keep legacy routing.

## Database and deployment

Required migrations, in order:

1. `backend/scripts/migrations/dtr/20261015_named_approval_workflows.sql`
2. `backend/scripts/migrations/dtr/20261016_shared_workflow_assignments.sql`

The first adds the catalog and request snapshots and converts existing type
routes into equivalent named workflows. The second permits up to 20 steps,
records document-type links and shared document version provenance, and permits
configured HR/Mayor authority sources in DocuTracker steps. The second migration
does not reroute or edit existing requests or documents.

Use the documented migration procedure for the intended database, restart the
backend, and restart/rebuild Flutter. Never run `init-schema.sql` against an
existing database. Production deployment requires the documented backup and
operator approval procedure.

Local verification on 2026-10-16: both migrations are installed on
`localhost:5433/hrms_plaridel`. The shared-assignment migration was applied once;
fingerprints confirmed that 23 Leave requests, 18 Locator requests, eight
DocuTracker documents, and 14 existing document workflow versions were unchanged.
The local PM2 `hrms-backend` process was restarted, and `/health` and `/health/db`
both returned 200. Authenticated catalog, inbox, document-type links, routing
configuration, and mirror endpoints also returned 200. No production migration
or deployment was performed.

## Verification

Coverage includes workflow publication, reviewer selection/eligibility, backup
and self-approval separation, four-step routing in isolated PostgreSQL, inbox
access and stale decisions, signature revision/history preservation, manual
Mayor printing, source-module final-only accounting, and immutable linked
DocuTracker versions. Widget tests cover the shared editor, selecting employees,
the integrated approval queues, notifications, type settings, and relevant existing screens.

The broad runs passed 677 backend tests (including eight PostgreSQL integration
files) and 335 Flutter tests. Subsequent focused checks passed 35 backend and
35 Flutter tests for the final integration changes. Static analysis found no
errors or warnings and one pre-existing Mayor-page style suggestion. The running
browser was not manually exercised; restart Flutter to load the updated screens.

Queue integration verification on 2026-10-16: 341 Flutter regression tests passed;
12 final focused tests also passed, covering filtering, named step labels, ordinary
employee/HR backup reviews, and My Leave access without a department designation.
Thirty backend tests and one isolated PostgreSQL integration test passed. The
local backend was restarted and both health endpoints returned 200; authenticated
assignment lookups returned 200 for admin, employee, and Mayor accounts. No new
migration was required. Browser interaction was not manually verified.

The single configuration entry was verified with 44 approval/DocuTracker widget
regressions and 18 final focused checks, including the additional fixed-department
scope guard, save-in-progress protection, primary/backups, retry, mobile navigation,
and report signatories. No backend restart or database migration is required for
this UI consolidation; browser interaction was not manually verified.

## Routing, signature, and access audit (2026-10-17)

Leave and Locator now apply the same pending shared-workflow access rule to
details, signature images, attachments, history, and request-bound print data:
the applicant, currently eligible reviewers, and recorded review participants
may read. A global HR/admin/Mayor role alone does not grant early access to a
pending shared request. Only current eligible reviewers may decide; the
applicant and prior approving actors remain excluded from later decisions.

Both management queues exclude pending shared requests from their legacy query
and merge the assigned workflow inbox first, before completed history. This
removes duplicate pending entries and prevents a future HR stage from appearing
as an actionable request. Existing Leave and Locator details panels remain the
presentation for every shared route. Compatibility paths remain for historical
records without object workflow snapshots.

The approval panel shows only the active reviewer's signature card using one
source-signature fetch. Applicant and previous reviewer signature cards are
hidden, and read-only details do not fetch or display signature controls.
Their saved ink remains available to form preview and printing. The active card
and approval guard use the current actor and signature revision. Missing
historical applicant ink is not copied from an unconfirmed personal asset.

Shared-workflow notifications use the committed request and the same reviewer
resolver as the inbox, including the saved type name, applicant, dates, and
current step. Decision transactions close the preceding step's alerts even
when both steps use `pending_hr`. Notification reads reconcile delayed alerts
by saved step, workflow version, and signature revision. Applicant outcome
notifications remain separate.

Regression coverage includes `workflowReadAuthorization.test.js`,
`workflowNotificationParity.test.js`, `workflowRoutingAuditPostgres.integration.test.js`,
`workflowNoticeLifecyclePostgres.integration.test.js`, and
`workflow_signature_details_test.dart`. The PostgreSQL route matrix executes
16 combinations across Leave/Locator, primary/backup actors, specific people,
department and Final HR groups, electronic Mayor, and manual signing. Temporary
tables/isolated schemas and rollback preserve application records.

Authenticated, read-only checks against the restarted local backend verified
the actual pending Locator HR stage: three configured reviewers receive the
request in their inboxes, five authorized participants can load signatures,
and two users outside the current stage are denied. Additional checks verified
saved applicant and approver image bytes on two approved Leave requests and
the pending Locator request. One older approved Leave has no saved applicant
signature for its revision; this audit did not manufacture one. No pending
shared Leave was available for a live stage test; isolated database tests
exercise those transitions. No requests, workflows, or decisions were changed
by the live audit, and no migration was needed. Both health endpoints passed.
Browser interaction was not manually verified.

Final audit checks passed: 200 backend tests, 11 checks in the isolated database
suite, and 115 Flutter regression tests. The unit run skipped one database-only
case, which passed when explicitly enabled in the database suite. Static
analysis of the eight changed workflow UI/test files found no issues; syntax
checks passed for 13 backend modules. Restart Flutter to load the updated UI.

## Printed signatories when a primary reviewer files (2026-10-18)

Workflow creation and editing include **When a primary reviewer files their own
request**. The print-only rule has three choices:

| Choice | Result in the applicant's own official block |
| --- | --- |
| Replace with Mayor (`mayor`, default) | Print the Mayor; use only their confirmed electronic approval signature. Manual Mayor signing stays unsigned. |
| Leave blank (`blank`) | Leave the official name, position, and signature blank for manual completion. |
| Show actual approving reviewer (`actual_reviewer`) | Print the authorized actor who approved that step, using the saved decision and matching signature. Before approval the block stays blank. |

This applies to Leave certification (7.A) and recommendation (7.B), and Locator
department-head and final-HR blocks. A separate final Mayor approval block keeps
its normal identity and signature. Applicant signatures, other employees' forms,
approval order, eligibility, and reviewer permissions are unchanged.

The rule lives on `approval_workflow_versions.self_filing_signatory_policy` and
is copied into `workflow_snapshot` at filing. Publishing a new workflow version
does not alter filed forms. Resubmitting with the same type keeps the saved rule;
old request snapshots without the field retain Mayor replacement. New decisions
using the actual-reviewer option save the approver's name and position, including
legacy string-step workflows. Previewing/printing does not update requests.

Migration: `backend/scripts/migrations/dtr/20261018_workflow_self_filing_signatories.sql`.
The standalone `init-schema.sql` includes the same column and constraint. Local
application on 2026-10-18 targeted `localhost:5433/hrms_plaridel1`; all six existing
versions received the Mayor default. Before/after checks verified that existing
workflow data (apart from the new default column), Leave requests, and Locator
requests were unchanged. The migration also passed an isolated upgrade test,
including repeat execution and rejection of invalid values. No production
database was changed. A code rollback can retain this additive column safely.

## Revoke approved shared Leave requests (2026-10-18)

Shared Leave details connect **Revoke Approval** to the existing confirmation
and revocation API. The read-only inbox/source response includes
`can_revoke_approval`, based on the final workflow assignment, account role,
current Mayor identity, and administrator Leave access. Department-stage actors,
unrelated backups, and applicants do not receive the action. Expired or missing
approval dates show a reason instead. The deadline is three days after
`approved_at`, falling back to `reviewed_at` for older records.

Opening the confirmation refreshes the source record. The API still locks and
rechecks the request before returning it to the employee, restoring stored paid
credits, removing its Leave coverage, and recording the audit event. The Mayor
route guard now permits this specific revoke operation after workflow completion;
other decision endpoints retain their pending-stage restrictions. No migration
is required. Verification uses mocked revocations; no application requests were
revoked as part of testing.
