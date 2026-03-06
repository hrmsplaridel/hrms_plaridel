# DocuTracker Database Schema

Complete database schema for the DocuTracker module. Run migrations in order.

## Tables Overview

| Table | Purpose |
|-------|---------|
| docutracker_documents | Main document records |
| docutracker_routing_records | Per-step routing tracking |
| docutracker_document_history | Audit trail, overdue/escalation logs |
| docutracker_permissions | Role/user action permissions |
| docutracker_routing_configs | Workflow definitions per document type |
| docutracker_escalation_configs | Escalation rules per type/department |
| docutracker_notifications | User notifications |

## docutracker_documents

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_number | TEXT | Unique (e.g. DOC-2025-0001) |
| document_type | TEXT | memo, purchaseRequest, etc. |
| title | TEXT | Document title |
| description | TEXT | Optional description |
| file_path | TEXT | Storage path |
| file_name | TEXT | Original filename |
| created_by | UUID | Creator user ID |
| created_at | TIMESTAMPTZ | Creation time |
| updated_at | TIMESTAMPTZ | Last update |
| current_step | INT | Workflow step (1-based) |
| status | TEXT | pending, inReview, approved, rejected, returned, forwarded, overdue, escalated |
| sent_time | TIMESTAMPTZ | When sent to current reviewer |
| deadline_time | TIMESTAMPTZ | Review deadline |
| reviewed_time | TIMESTAMPTZ | When reviewed |
| current_holder_id | UUID | Current assignee |
| escalation_level | INT | 0 = none |
| needs_admin_intervention | BOOLEAN | Max escalation reached |

## docutracker_document_history

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_id | UUID | FK to documents |
| action | TEXT | created, assigned, approved, rejected, returned, forwarded, escalated, remark |
| actor_id | UUID | Who performed action |
| actor_name | TEXT | Joined display name |
| from_step | INT | Previous step |
| to_step | INT | New step |
| from_status | TEXT | Previous status |
| to_status | TEXT | New status |
| remarks | TEXT | Comments |
| is_overdue_log | BOOLEAN | Missed deadline log |
| is_escalation_log | BOOLEAN | Escalation event |
| escalation_level | INT | Level when escalated |
| created_at | TIMESTAMPTZ | When logged |

## docutracker_escalation_configs

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_type | TEXT | memo, purchaseRequest |
| department_id | TEXT | Optional department filter |
| escalation_target_role | TEXT | Role to escalate to |
| escalation_delay_minutes | INT | Minutes after deadline |
| max_escalation_level | INT | Max levels before admin flag |
| notify_original_sender | BOOLEAN | Notify creator on escalate |

## docutracker_notifications

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_id | UUID | FK to documents |
| user_id | UUID | Recipient |
| type | TEXT | assigned, deadline_near, overdue, escalated, returned, rejected |
| title | TEXT | Notification title |
| body | TEXT | Notification body |
| read | BOOLEAN | Read status |

## docutracker_permissions

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| role_id | TEXT | Role (admin, hr_staff, etc.) |
| user_id | UUID | Specific user override |
| document_type | TEXT | * or specific type |
| action | TEXT | view, edit, download, delete, returnDoc, forward, approve, reject |
| granted | BOOLEAN | Allow/deny |

## docutracker_routing_configs

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_type | TEXT | memo, purchaseRequest |
| steps | JSONB | Array of {step_order, assignee_type, role_id, department_id, label} |
| review_deadline_hours | INT | Default deadline in hours |
