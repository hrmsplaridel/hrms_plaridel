# DocuTracker API Endpoints

The Flutter module uses the authenticated HRMS Express API under
`/api/docutracker`.

## Documents

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/documents | List authorized documents with optional filters |
| GET | /api/docutracker/documents/{id} | Get an authorized document bundle |
| POST | /api/docutracker/documents | Create a document |
| POST | /api/docutracker/documents/{id}/transition | Perform a validated workflow action |

Document list items may include `viewer_is_routing_assignee`, a viewer-specific
boolean used by the client to retain documents assigned through the routing
snapshot without exposing other assignees' user IDs.

## Document Builder and E-Signatures

The HRMS Express API stores editor content as Quill Delta JSON per A4 page.
Signature field coordinates and sizes are normalized from `0` to `1`, so the
same geometry can be rendered on different screen sizes and in PDF output.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/docutracker/documents/{id}/builder` | Load A4 pages, signature fields, signed images, revision, and effective capabilities |
| PUT | `/api/docutracker/documents/{id}/builder` | Save page Delta content and the complete unsigned signature-field layout using optimistic revision checking |
| GET | `/api/docutracker/signature-assets` | List saved signatures owned by the authenticated user |
| POST | `/api/docutracker/signature-assets` | Save a drawn or uploaded PNG/JPEG signature owned by the authenticated user |
| PATCH | `/api/docutracker/signature-assets/{assetId}` | Rename a saved signature owned by the authenticated user |
| DELETE | `/api/docutracker/signature-assets/{assetId}` | Remove a signature from the authenticated user's library without changing signed documents |
| GET | `/api/docutracker/sources/{module}/{table}/{recordId}` | Load a server-authorized, read-only L&D training report or RSP recruitment application with short-lived attachment links |
| POST | `/api/docutracker/documents/{id}/signature-fields/{fieldId}/sign` | Sign or replace the signature image in one field assigned to the authenticated user |
| PATCH | `/api/docutracker/documents/{id}/signature-fields/{fieldId}/position` | Move an already-signed field assigned to the authenticated user without changing its size, signer, or image |
| GET | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures` | Load fixed e-signature slots for an authorized linked DTR leave request |
| POST | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures/applicant/sign` | Add or replace the authenticated applicant's signature while the leave request remains active |
| POST | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures/department_head/sign` | Add or replace the assigned department head signature before endorsement |
| POST | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures/hr_approver/sign` | Add or replace the authenticated HR/admin signature before final approval |
| GET | `/api/docutracker/sources/rsp/{table}/{recordId}/signatures` | Load the configured signature fields for an authorized saved RSP form |
| GET | `/api/docutracker/sources/rsp/signature-requests` | List saved RSP forms needing admin signer setup or a signature from the authenticated user, including the protected form preview payload; completed forms are omitted |
| PUT | `/api/docutracker/sources/rsp/{table}/{recordId}/signatures/{slot}/assignment` | Admin-only assignment of an active HRMS user to an RSP signature field |
| POST | `/api/docutracker/sources/rsp/{table}/{recordId}/signatures/{slot}/sign` | Add or replace the authenticated assigned user's RSP form signature |
| GET | `/api/docutracker/sources/ld/{table}/{recordId}/signatures` | Load configured signature fields for an authorized saved L&D form |
| GET | `/api/docutracker/sources/ld/signature-requests` | List L&D forms needing admin signer setup or a signature from the authenticated user |
| PUT | `/api/docutracker/sources/ld/{table}/{recordId}/signatures/{slot}/assignment` | Admin-only assignment of an active HRMS user to an L&D signature field |
| POST | `/api/docutracker/sources/ld/{table}/{recordId}/signatures/{slot}/sign` | Add or replace the authenticated assigned user's L&D form signature |

The RSP and L&D signature-request feeds return `503` when their required source
form or signature tables are not initialized. They do not convert a missing
schema into an empty Required Actions list.

Builder responses include `current_user_id` and a per-field `can_sign`
capability calculated from the authenticated backend user. The Flutter client
uses these server-authoritative values instead of deciding signer identity from
locally passed navigation data.

Drawn or uploaded signatures can be marked `is_saved` and reused through an
owned `signature_asset_id`. The backend verifies asset ownership and requires
the same authenticated department reviewer or HR/admin reviewer to sign the
corresponding fixed slot before approval.

Saved RSP forms use fixed signature slots defined by the official form layout.
Supported records are Applicants Profile (`prepared_by`, `checked_by`),
Selection Line-Up (`prepared_by`), Computation of Points (`prepared_by`), Work
Experience Sheet (`applicant`), and Turn Around Time (`prepared_by`,
`noted_by`). An administrator assigns an active HRMS account to each field.
Only that authenticated account receives `can_sign: true` and may draw, select,
or replace its own saved signature. Assignment changes and signature changes
are transactional and recorded in the DocuTracker governance audit. The BI
Form has no signature field in its current official layout.

Saved L&D forms use the same server-authorized assignment and signing rules.
Supported records are Individual Development Plan (`prepared_by`,
`reviewed_by`, `noted_by`, and `approved_by`) and Action Brainstorming and
Coaching (`certified_by`). Administrators can discover forms with unassigned
fields through the L&D signature-request endpoint. Assigned users see only
their own requests. Training Needs Analysis and Performance Evaluation are not
given artificial signature fields because their current print layouts contain
none.

Builder responses also include `format_version`. New builder content uses
version `2`, which renders the official `assets/forms/a4_letter.pdf` full-page
Municipality/HRMD letterhead background on every A4 page and includes it in
print/PDF output. Existing saved version `1` content keeps its original
plain-page layout.

New purchase-request templates may include a `docutracker-purchase-items` block
inside a page's existing Delta array. Its value is a JSON string containing
`rows` (six string cells per row: item number, unit, description, quantity, unit
cost, total cost) and `total` (an editable string). The Flutter builder renders
and edits this block as a ruled table. It uses the same builder GET/PUT and
revision checks; it does not approve a request or change procurement workflow.

The builder PUT body is:

```json
{
  "pages": [[{"insert": "Document text\n"}]],
  "signature_fields": [
    {
      "id": "optional-existing-uuid",
      "page_number": 1,
      "position_x": 0.58,
      "position_y": 0.72,
      "width": 0.30,
      "height": 0.12,
      "assigned_signer_id": "user-uuid",
      "label": "Sign Here"
    }
  ],
  "revision": 0
}
```

Only an effective document editor can change page content or unsigned field
layout. Signed fields cannot be resized, reassigned, or deleted. Only the
assigned active user can reposition a signed field or replace its signature
image. Repositioning appends a `metadata_updated` history entry, and replacement
appends another `signed` entry; neither operation overwrites prior history. Saved
signature assets are private to their owner.

Linked DTR leave requests remain authoritative in the Leave module. DocuTracker
stores only the applicant signature binding and audit metadata; it does not copy
leave dates, balances, status, attachments, or approval decisions. Source
signature responses expose a backend-calculated `can_sign` capability. Only the
leave applicant can use the applicant signing operation. A replacement appends
a new leave history event rather than overwriting the audit trail.

Source-only DTR leave rows returned by `GET /api/docutracker/documents` may also
contain `source_status`, `source_action`, and `source_action_label`. These are
server-calculated, viewer-specific hints for DocuTracker's Required Actions UI.
An absent `source_action` means the viewer has no current source-module action.
The hints do not authorize or perform a DTR transition; DTR remains responsible
for submission, endorsement, approval, return, rejection, and leave balances.

Linked L&D training reports and RSP recruitment applications also remain
authoritative in their source modules. DocuTracker returns only an allowlisted
read-only view. Employees may load only their own L&D reports and must retain
the L&D view permission; RSP application details remain admin-only. Attachment
links are short-lived and are revalidated by the existing source file policy.
Printing reuses the source module's existing official PDF builder with the
allowlisted `print_data` payload; physical attachment paths are never returned.

**Query params:**
- `document_type=eq.memo` - Filter by type
- `status=eq.pending` - Filter by status
- `current_holder_id=eq.{userId}` - Documents assigned to user
- `created_by=eq.{userId}` - Documents created by user
- `deadline_time=lt.now()` - Overdue documents

## Document History (Audit Trail)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/documents/{id}/history | Get the authorized document audit trail |
| POST | /api/docutracker/documents/{id}/history | Returns 405; history is generated by server-side operations |

Clients cannot supply workflow actions, actor names, steps, or statuses for the
audit trail. Transitions, remarks, signatures, metadata edits, escalation, and
administrative recovery append their own history entries transactionally.

## Document Updates and Recovery

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | /api/docutracker/documents/{id} | Update permitted document metadata only |
| PATCH | /api/docutracker/documents/{id} | Admin-only recovery reassignment for the current step |

The metadata PUT rejects workflow-owned fields such as `status`,
`current_step`, `current_holder_id`, deadlines, and escalation state. The
recovery PATCH accepts `current_holder_id` and required `remarks`; the target
must be an active configured assignee for the current workflow step. Recovery
preserves the document's status and step while updating its holder, routing
record, assignee snapshot, deadline, history, and notification in one
transaction.

## Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_notifications?user_id=eq.{userId} | List user notifications |
| POST | /docutracker_notifications | Create notification |
| PATCH | /docutracker_notifications?id=eq.{id} | Mark as read |

## Permissions

These endpoints remain the system-security layer for administration, document
creation/download, and explicit user overrides. Workflow action authorization
comes from the active step assignment and its allowed actions.

The System Access screen uses the transactional API endpoints below. Both are
admin-only. `GET /api/docutracker/permission-policy` returns role defaults and,
when `user_id` is supplied, the employee's explicit and effective access in one
response. `PUT /api/docutracker/permission-policy` accepts `document_type` and
up to 100 `changes`. Each change targets exactly one `role_id` or `user_id`,
contains one of `view`, `create_draft`, `submit`, or `download`, and uses a
boolean `granted` value. `granted: null` removes an explicit rule so the broader
or role setting applies. The entire batch and its governance-audit entries are
committed or rolled back together.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/permission-policy | Load role defaults and optional employee exceptions/effective access |
| PUT | /api/docutracker/permission-policy | Atomically save role defaults and employee exceptions |
| GET | /api/docutracker/permission-records | Compatibility endpoint for raw permission rows |
| POST | /api/docutracker/permissions | Compatibility endpoint for one validated permission change |
| DELETE | /api/docutracker/permissions | Reset validated explicit rules and create audit entries |

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_permissions | List permissions (filter by role_id, user_id, document_type) |
| POST | /docutracker_permissions | Add permission |
| PATCH | /docutracker_permissions?id=eq.{id} | Update permission |

Permission write endpoints reject ambiguous user-and-role targets, inactive or
unknown employees, unsupported roles/actions, invalid identifiers, and
unconfigured document types. Workflow actions (`approve`, `forward`, `return`,
and `reject`) cannot be granted through these system-access endpoints.

## Routing Configs

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/routing-configs | List workflow configs |
| POST | /api/docutracker/routing-configs | Publish a workflow version with its step assignees and actions |

Each item in `steps` may include `user_ids` ordered as primary then backups and
`allowed_actions`, containing one or more of `approve`, `forward`, `return`, or
`reject`. A user ID cannot appear more than once in the same step. Publishing
creates the normalized step/assignee rows. Older configs
without `allowed_actions` retain their stored assignee actions and otherwise
use the legacy four-action default.

## Workflow Step Assignees

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/workflow-steps | List normalized workflow steps and assignees for an admin |
| PUT | /api/docutracker/workflow-steps/{stepId}/assignees | Replace the complete assignee set for one workflow step |

The PUT endpoint is retained for backward compatibility and advanced repair.
Normal workflow setup edits assignees and allowed actions directly inside each
step. The PUT body is `{"assignees": [...]}`. Sending `{"assignees": []}` leaves
the step unassigned. An assigned step must contain exactly one enabled primary
assignee. Documents cannot transition into an unassigned step until an admin
adds a valid assignee.

At runtime, only the current step's enabled primary or backup assignees may use
that step's allowed actions. This rule is enforced by the API for every actor,
including admins. Creators, reached-step assignees, signature assignees, and
admins retain relationship-based view access; future-step assignment alone does
not grant early access.

## Escalation Configs

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_escalation_configs | List escalation rules |
| POST | /docutracker_escalation_configs | Add rule |
| PATCH | /docutracker_escalation_configs?id=eq.{id} | Update rule |

## Backend Logic (Cron/Edge Function)

For Step 12 automation, implement a scheduled job:

```sql
-- Pseudocode: Run every 5 minutes
-- 1. Find documents where deadline_time < now() AND status NOT IN (approved, rejected)
-- 2. For each: create history entry, update status to escalated, create notification
-- 3. Reassign to escalation target from docutracker_escalation_configs
```

Supabase Edge Functions or external cron can call this logic.
