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
| POST | `/api/docutracker/documents/{id}/signature-fields/{fieldId}/sign` | Sign or replace the signature image in one field assigned to the authenticated user |
| PATCH | `/api/docutracker/documents/{id}/signature-fields/{fieldId}/position` | Move an already-signed field assigned to the authenticated user without changing its size, signer, or image |
| GET | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures` | Load fixed e-signature slots for an authorized linked DTR leave request |
| POST | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures/applicant/sign` | Add or replace the authenticated applicant's signature while the leave request remains active |
| POST | `/api/docutracker/sources/dtr/leave_requests/{leaveRequestId}/signatures/department_head/sign` | Add or replace the assigned department head signature before endorsement |

Builder responses include `current_user_id` and a per-field `can_sign`
capability calculated from the authenticated backend user. The Flutter client
uses these server-authoritative values instead of deciding signer identity from
locally passed navigation data.

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

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_permissions | List permissions (filter by role_id, user_id, document_type) |
| POST | /docutracker_permissions | Add permission |
| PATCH | /docutracker_permissions?id=eq.{id} | Update permission |

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
