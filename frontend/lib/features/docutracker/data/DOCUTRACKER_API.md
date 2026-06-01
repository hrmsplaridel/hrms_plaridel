# DocuTracker Sample API Endpoints

Sample REST/PostgREST endpoints for DocuTracker. Supabase provides these via PostgREST.

## Documents

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /docutracker_documents | List documents (filter by status, type, created_by, current_holder_id) |
| GET | /docutracker_documents?id=eq.{id} | Get single document |
| POST | /docutracker_documents | Create document |
| PATCH | /docutracker_documents?id=eq.{id} | Update document (status, current_step, etc.) |

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
