# DocuTracker Sample API Endpoints

Sample REST/PostgREST endpoints for DocuTracker. Supabase provides these via PostgREST.

## Documents

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_documents | List documents (filter by status, type, created_by, current_holder_id) |
| GET | /docutracker_documents?id=eq.{id} | Get single document |
| POST | /docutracker_documents | Create document |
| PATCH | /docutracker_documents?id=eq.{id} | Update document (status, current_step, etc.) |

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

Builder responses include `current_user_id` and a per-field `can_sign`
capability calculated from the authenticated backend user. The Flutter client
uses these server-authoritative values instead of deciding signer identity from
locally passed navigation data.

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

**Query params:**
- `document_type=eq.memo` - Filter by type
- `status=eq.pending` - Filter by status
- `current_holder_id=eq.{userId}` - Documents assigned to user
- `created_by=eq.{userId}` - Documents created by user
- `deadline_time=lt.now()` - Overdue documents

## Document History (Audit Trail)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_document_history?document_id=eq.{id} | Get audit trail for document |
| POST | /docutracker_document_history | Log action (created, approved, escalated, etc.) |

## Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_notifications?user_id=eq.{userId} | List user notifications |
| POST | /docutracker_notifications | Create notification |
| PATCH | /docutracker_notifications?id=eq.{id} | Mark as read |

## Permissions

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_permissions | List permissions (filter by role_id, user_id, document_type) |
| POST | /docutracker_permissions | Add permission |
| PATCH | /docutracker_permissions?id=eq.{id} | Update permission |

## Routing Configs

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_routing_configs | List workflow configs |
| POST | /docutracker_routing_configs | Add config |
| PATCH | /docutracker_routing_configs?id=eq.{id} | Update config |

## Workflow Step Assignees

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/docutracker/workflow-steps | List normalized workflow steps and assignees for an admin |
| PUT | /api/docutracker/workflow-steps/{stepId}/assignees | Replace the complete assignee set for one workflow step |

The PUT body is `{"assignees": [...]}`. Sending `{"assignees": []}` leaves
the step unassigned. An assigned step must contain exactly one enabled primary
assignee. Documents cannot transition into an unassigned step until an admin
adds a valid assignee.

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
