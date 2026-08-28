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
| docutracker_workflow_steps | Normalized workflow steps per type and version |
| docutracker_workflow_step_assignees | Selected users assigned to each workflow step |
| docutracker_escalation_configs | Escalation rules per type/department |
| docutracker_notifications | User notifications |
| docutracker_document_contents | Versioned A4 page content stored as Quill Delta JSON |
| docutracker_signature_assets | Private drawn/uploaded signature images owned by users |
| docutracker_signature_fields | Page placement, assigned signer, signed date, and lock state |

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
| status | TEXT | pending, inReview, approved, rejected, returned, overdue, escalated |
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
| action | TEXT | created, assigned, approved, rejected, returned, forwarded, escalated, signed, remark |
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

## docutracker_document_contents

| Column | Type | Description |
|--------|------|-------------|
| document_id | UUID | Primary key and FK to DocuTracker document |
| format_version | INT | Stored builder format version |
| pages | JSONB | Array of A4 pages; each page contains Quill Delta operations |
| page_size | TEXT | Fixed to A4 |
| margins | JSONB | Normalized page margins |
| revision | INT | Optimistic concurrency revision |
| updated_by | UUID | Last authenticated editor |
| created_at | TIMESTAMPTZ | Creation time |
| updated_at | TIMESTAMPTZ | Last confirmed save time |

## docutracker_signature_assets

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| owner_user_id | UUID | User who owns and may reuse the signature |
| image_bytes | BYTEA | Validated PNG or JPEG data, maximum 2 MB |
| mime_type | TEXT | image/png or image/jpeg |
| source_type | TEXT | drawn or uploaded |
| display_name | TEXT | Optional owner-visible label |
| is_saved | BOOLEAN | Whether it appears in the owner's saved signatures |
| created_at | TIMESTAMPTZ | Creation time |
| updated_at | TIMESTAMPTZ | Last update |

## docutracker_signature_fields

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_id | UUID | Document containing the signature field |
| page_number | INT | One-based A4 page number |
| position_x | DOUBLE PRECISION | Normalized horizontal position |
| position_y | DOUBLE PRECISION | Normalized vertical position |
| width | DOUBLE PRECISION | Normalized field width |
| height | DOUBLE PRECISION | Normalized field height |
| assigned_signer_id | UUID | Existing active user assigned to sign |
| label | TEXT | Placeholder label, normally Sign Here |
| signature_asset_id | UUID | Signature image used after signing |
| signed_by | UUID | Authenticated signer |
| signer_name_snapshot | TEXT | Printed signer name retained with the event |
| signed_at | TIMESTAMPTZ | Backend-authoritative signed time |
| locked_at | TIMESTAMPTZ | Non-null when placement and signature are locked |
| created_by | UUID | User who prepared the field |
| created_at | TIMESTAMPTZ | Creation time |
| updated_at | TIMESTAMPTZ | Last update |

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

## docutracker_workflow_steps

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| document_type | TEXT | Workflow document type |
| workflow_version | INT | Published workflow version |
| step_order | INT | One-based workflow position |
| department_id | UUID | Optional department scope |
| label | TEXT | Step display label |
| enabled | BOOLEAN | Whether the step participates in routing |

## docutracker_workflow_step_assignees

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| step_id | UUID | FK to docutracker_workflow_steps |
| user_id | UUID | Selected assignee |
| is_primary | BOOLEAN | Primary reviewer marker |
| backup_rank | INT | Backup order; null for the primary |
| is_enabled | BOOLEAN | Whether this assignment can receive work |
| allowed_actions | TEXT[] | Existing allowed workflow actions |

A workflow step may have zero assignee rows while it is being configured. When
one or more assignees exist, at least one must be enabled and exactly one enabled
assignee must be primary. Runtime routing rejects entry into an unassigned step.
