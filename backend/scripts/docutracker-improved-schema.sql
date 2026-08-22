-- ============================================================
-- DOCUTRACKER DATABASE SCHEMA
-- PostgreSQL
--
-- IMPORTANT:
-- 1. This script assumes PostgreSQL with pgcrypto available.
-- 2. User and department foreign keys are intentionally not added
--    because the exact HRMS table names were not provided.
-- 3. Replace UUID user/department columns with foreign keys after
--    confirming your actual HRMS tables, such as:
--       users(id)
--       departments(id)
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- SHARED UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION docutracker_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 1. ROLES
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_roles (
    role_id TEXT PRIMARY KEY,
    display_name TEXT,
    description TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_roles_role_id_not_blank
        CHECK (BTRIM(role_id) <> '')
);

CREATE TRIGGER trg_docutracker_roles_updated_at
BEFORE UPDATE ON docutracker_roles
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 2. ROLE ALIASES
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_role_aliases (
    alias TEXT PRIMARY KEY,
    role_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_role_aliases_alias_not_blank
        CHECK (BTRIM(alias) <> ''),

    CONSTRAINT docutracker_role_aliases_role_fk
        FOREIGN KEY (role_id)
        REFERENCES docutracker_roles(role_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_docutracker_role_aliases_role_id
    ON docutracker_role_aliases(role_id);

-- ============================================================
-- 3. DOCUMENT TYPES
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_document_types (
    document_type TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT,
    number_prefix TEXT,
    default_priority TEXT NOT NULL DEFAULT 'normal',
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_document_types_type_not_blank
        CHECK (BTRIM(document_type) <> ''),

    CONSTRAINT docutracker_document_types_priority_check
        CHECK (default_priority IN ('low', 'normal', 'high', 'urgent'))
);

CREATE TRIGGER trg_docutracker_document_types_updated_at
BEFORE UPDATE ON docutracker_document_types
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 4. WORKFLOWS
-- One active workflow definition per document type.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_type TEXT NOT NULL UNIQUE,
    active_version INT,
    default_review_deadline_hours INT,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_workflows_document_type_fk
        FOREIGN KEY (document_type)
        REFERENCES docutracker_document_types(document_type)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT docutracker_workflows_deadline_check
        CHECK (
            default_review_deadline_hours IS NULL
            OR default_review_deadline_hours > 0
        ),

    CONSTRAINT docutracker_workflows_active_version_check
        CHECK (
            active_version IS NULL
            OR active_version > 0
        )
);

CREATE TRIGGER trg_docutracker_workflows_updated_at
BEFORE UPDATE ON docutracker_workflows
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 5. WORKFLOW VERSIONS
-- Immutable published versions are recommended.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_workflow_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id UUID NOT NULL,
    version INT NOT NULL,
    review_deadline_hours INT,
    status TEXT NOT NULL DEFAULT 'draft',
    notes TEXT,
    snapshot JSONB,
    created_by UUID,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_workflow_versions_workflow_fk
        FOREIGN KEY (workflow_id)
        REFERENCES docutracker_workflows(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_workflow_versions_version_positive
        CHECK (version > 0),

    CONSTRAINT docutracker_workflow_versions_deadline_check
        CHECK (
            review_deadline_hours IS NULL
            OR review_deadline_hours > 0
        ),

    CONSTRAINT docutracker_workflow_versions_status_check
        CHECK (status IN ('draft', 'published', 'retired')),

    CONSTRAINT docutracker_workflow_versions_unique
        UNIQUE (workflow_id, version)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_versions_workflow
    ON docutracker_workflow_versions(workflow_id, version DESC);

-- ============================================================
-- 6. WORKFLOW STEPS
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_workflow_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id UUID NOT NULL,
    step_order INT NOT NULL,
    department_id UUID,
    label TEXT NOT NULL,
    description TEXT,
    approval_mode TEXT NOT NULL DEFAULT 'any',
    minimum_approvals INT,
    review_deadline_hours INT,
    allow_return BOOLEAN NOT NULL DEFAULT TRUE,
    allow_reject BOOLEAN NOT NULL DEFAULT TRUE,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_workflow_steps_version_fk
        FOREIGN KEY (workflow_version_id)
        REFERENCES docutracker_workflow_versions(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_workflow_steps_order_positive
        CHECK (step_order > 0),

    CONSTRAINT docutracker_workflow_steps_label_not_blank
        CHECK (BTRIM(label) <> ''),

    CONSTRAINT docutracker_workflow_steps_approval_mode_check
        CHECK (
            approval_mode IN (
                'any',
                'all',
                'majority',
                'primary_only',
                'sequential'
            )
        ),

    CONSTRAINT docutracker_workflow_steps_minimum_approvals_check
        CHECK (
            minimum_approvals IS NULL
            OR minimum_approvals > 0
        ),

    CONSTRAINT docutracker_workflow_steps_deadline_check
        CHECK (
            review_deadline_hours IS NULL
            OR review_deadline_hours > 0
        ),

    CONSTRAINT docutracker_workflow_steps_unique_order
        UNIQUE (workflow_version_id, step_order)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_version_order
    ON docutracker_workflow_steps(workflow_version_id, step_order);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_department
    ON docutracker_workflow_steps(department_id)
    WHERE department_id IS NOT NULL;

CREATE TRIGGER trg_docutracker_workflow_steps_updated_at
BEFORE UPDATE ON docutracker_workflow_steps
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 7. WORKFLOW STEP ASSIGNMENTS
-- Supports a user, role, department, department head,
-- sender supervisor, or document creator.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_workflow_step_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL,
    assignee_type TEXT NOT NULL,
    user_id UUID,
    role_id TEXT,
    department_id UUID,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    backup_rank INT,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_actions TEXT[] NOT NULL DEFAULT ARRAY[
        'view',
        'approve',
        'reject',
        'return'
    ]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_step_assignments_step_fk
        FOREIGN KEY (step_id)
        REFERENCES docutracker_workflow_steps(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_step_assignments_role_fk
        FOREIGN KEY (role_id)
        REFERENCES docutracker_roles(role_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT docutracker_step_assignments_type_check
        CHECK (
            assignee_type IN (
                'user',
                'role',
                'department',
                'department_head',
                'sender_supervisor',
                'document_creator'
            )
        ),

    CONSTRAINT docutracker_step_assignments_target_check
        CHECK (
            (assignee_type = 'user'
                AND user_id IS NOT NULL
                AND role_id IS NULL
                AND department_id IS NULL)
            OR
            (assignee_type = 'role'
                AND user_id IS NULL
                AND role_id IS NOT NULL
                AND department_id IS NULL)
            OR
            (assignee_type = 'department'
                AND user_id IS NULL
                AND role_id IS NULL
                AND department_id IS NOT NULL)
            OR
            (assignee_type = 'department_head'
                AND user_id IS NULL
                AND role_id IS NULL
                AND department_id IS NOT NULL)
            OR
            (assignee_type IN ('sender_supervisor', 'document_creator')
                AND user_id IS NULL
                AND role_id IS NULL
                AND department_id IS NULL)
        ),

    CONSTRAINT docutracker_step_assignments_backup_rank_check
        CHECK (
            backup_rank IS NULL
            OR backup_rank >= 0
        )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignments_step
    ON docutracker_workflow_step_assignments(step_id);

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignments_user
    ON docutracker_workflow_step_assignments(user_id)
    WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignments_role
    ON docutracker_workflow_step_assignments(role_id)
    WHERE role_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignments_department
    ON docutracker_workflow_step_assignments(department_id)
    WHERE department_id IS NOT NULL;

CREATE TRIGGER trg_docutracker_step_assignments_updated_at
BEFORE UPDATE ON docutracker_workflow_step_assignments
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 8. DOCUMENTS
-- Stores only the current document state.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_number TEXT NOT NULL UNIQUE,
    document_type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,

    source_module TEXT,
    source_table TEXT,
    source_record_id UUID,
    source_title TEXT,

    created_by UUID NOT NULL,
    current_holder_id UUID,
    current_step INT NOT NULL DEFAULT 0,
    workflow_version_id UUID,

    status TEXT NOT NULL DEFAULT 'draft',
    priority TEXT NOT NULL DEFAULT 'normal',
    confidentiality_level TEXT NOT NULL DEFAULT 'internal',

    submitted_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    deadline_at TIMESTAMPTZ,
    last_reviewed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,

    escalation_level INT NOT NULL DEFAULT 0,
    needs_admin_intervention BOOLEAN NOT NULL DEFAULT FALSE,

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT docutracker_documents_document_type_fk
        FOREIGN KEY (document_type)
        REFERENCES docutracker_document_types(document_type)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT docutracker_documents_workflow_version_fk
        FOREIGN KEY (workflow_version_id)
        REFERENCES docutracker_workflow_versions(id)
        ON DELETE RESTRICT,

    CONSTRAINT docutracker_documents_number_not_blank
        CHECK (BTRIM(document_number) <> ''),

    CONSTRAINT docutracker_documents_title_not_blank
        CHECK (BTRIM(title) <> ''),

    CONSTRAINT docutracker_documents_current_step_check
        CHECK (current_step >= 0),

    CONSTRAINT docutracker_documents_status_check
        CHECK (
            status IN (
                'draft',
                'submitted',
                'pending',
                'in_review',
                'approved',
                'rejected',
                'returned',
                'cancelled',
                'completed',
                'archived'
            )
        ),

    CONSTRAINT docutracker_documents_priority_check
        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),

    CONSTRAINT docutracker_documents_confidentiality_check
        CHECK (
            confidentiality_level IN (
                'public',
                'internal',
                'confidential',
                'restricted'
            )
        ),

    CONSTRAINT docutracker_documents_escalation_level_check
        CHECK (escalation_level >= 0),

    CONSTRAINT docutracker_documents_deadline_check
        CHECK (
            deadline_at IS NULL
            OR sent_at IS NULL
            OR deadline_at >= sent_at
        )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_status
    ON docutracker_documents(status);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_type
    ON docutracker_documents(document_type);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_created_by
    ON docutracker_documents(created_by);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_current_holder
    ON docutracker_documents(current_holder_id)
    WHERE current_holder_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_deadline_active
    ON docutracker_documents(deadline_at)
    WHERE status IN ('submitted', 'pending', 'in_review');

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_source_record
    ON docutracker_documents(source_module, source_table, source_record_id)
    WHERE source_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_metadata_gin
    ON docutracker_documents
    USING GIN (metadata);

CREATE TRIGGER trg_docutracker_documents_updated_at
BEFORE UPDATE ON docutracker_documents
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 9. DOCUMENT FILES
-- Supports multiple attachments and file versions.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_document_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    mime_type TEXT,
    file_size BIGINT,
    checksum TEXT,
    version INT NOT NULL DEFAULT 1,
    uploaded_by UUID,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_document_files_document_fk
        FOREIGN KEY (document_id)
        REFERENCES docutracker_documents(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_document_files_name_not_blank
        CHECK (BTRIM(file_name) <> ''),

    CONSTRAINT docutracker_document_files_path_not_blank
        CHECK (BTRIM(file_path) <> ''),

    CONSTRAINT docutracker_document_files_size_check
        CHECK (
            file_size IS NULL
            OR file_size >= 0
        ),

    CONSTRAINT docutracker_document_files_version_check
        CHECK (version > 0),

    CONSTRAINT docutracker_document_files_unique_version
        UNIQUE (document_id, file_name, version)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_document_files_document
    ON docutracker_document_files(document_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_docutracker_document_files_current
    ON docutracker_document_files(document_id, file_name)
    WHERE is_current = TRUE;

-- ============================================================
-- 10. ROUTING RECORDS
-- One record per document workflow step instance.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_routing_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL,
    workflow_step_id UUID,
    step_order INT NOT NULL,
    label TEXT,

    sent_at TIMESTAMPTZ,
    deadline_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    status TEXT NOT NULL DEFAULT 'queued',
    decision TEXT,
    remarks TEXT,

    escalation_level INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_routing_records_document_fk
        FOREIGN KEY (document_id)
        REFERENCES docutracker_documents(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_routing_records_step_fk
        FOREIGN KEY (workflow_step_id)
        REFERENCES docutracker_workflow_steps(id)
        ON DELETE SET NULL,

    CONSTRAINT docutracker_routing_records_step_order_check
        CHECK (step_order > 0),

    CONSTRAINT docutracker_routing_records_status_check
        CHECK (
            status IN (
                'queued',
                'pending',
                'in_review',
                'completed',
                'returned',
                'rejected',
                'skipped',
                'cancelled',
                'expired'
            )
        ),

    CONSTRAINT docutracker_routing_records_decision_check
        CHECK (
            decision IS NULL
            OR decision IN (
                'approved',
                'rejected',
                'returned',
                'acknowledged',
                'skipped'
            )
        ),

    CONSTRAINT docutracker_routing_records_escalation_check
        CHECK (escalation_level >= 0),

    CONSTRAINT docutracker_routing_records_deadline_check
        CHECK (
            deadline_at IS NULL
            OR sent_at IS NULL
            OR deadline_at >= sent_at
        ),

    CONSTRAINT docutracker_routing_records_unique_step
        UNIQUE (document_id, step_order)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_document_step
    ON docutracker_routing_records(document_id, step_order);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_status_deadline
    ON docutracker_routing_records(status, deadline_at)
    WHERE status IN ('pending', 'in_review');

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_metadata_gin
    ON docutracker_routing_records
    USING GIN (metadata);

CREATE TRIGGER trg_docutracker_routing_records_updated_at
BEFORE UPDATE ON docutracker_routing_records
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 11. ROUTING RECORD ASSIGNEES
-- Tracks each assignee's individual state and decision.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_routing_record_assignees (
    routing_record_id UUID NOT NULL,
    user_id UUID NOT NULL,

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    assignment_order INT,
    status TEXT NOT NULL DEFAULT 'assigned',

    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    opened_at TIMESTAMPTZ,
    acted_at TIMESTAMPTZ,

    action TEXT,
    remarks TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (routing_record_id, user_id),

    CONSTRAINT docutracker_routing_assignees_record_fk
        FOREIGN KEY (routing_record_id)
        REFERENCES docutracker_routing_records(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_routing_assignees_order_check
        CHECK (
            assignment_order IS NULL
            OR assignment_order >= 0
        ),

    CONSTRAINT docutracker_routing_assignees_status_check
        CHECK (
            status IN (
                'assigned',
                'unopened',
                'opened',
                'in_review',
                'acted',
                'replaced',
                'cancelled'
            )
        ),

    CONSTRAINT docutracker_routing_assignees_action_check
        CHECK (
            action IS NULL
            OR action IN (
                'approved',
                'rejected',
                'returned',
                'acknowledged',
                'skipped'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_assignees_user_status
    ON docutracker_routing_record_assignees(user_id, status);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_assignees_record
    ON docutracker_routing_record_assignees(routing_record_id);

CREATE TRIGGER trg_docutracker_routing_assignees_updated_at
BEFORE UPDATE ON docutracker_routing_record_assignees
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 12. DOCUMENT HISTORY / AUDIT LOG
-- Application should treat this table as append-only.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_document_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL,
    routing_record_id UUID,

    event_category TEXT NOT NULL DEFAULT 'workflow',
    action TEXT NOT NULL,

    actor_id UUID,
    actor_name TEXT,
    actor_role_id TEXT,
    actor_department_id UUID,

    from_step INT,
    to_step INT,
    from_status TEXT,
    to_status TEXT,

    remarks TEXT,
    escalation_level INT NOT NULL DEFAULT 0,

    ip_address INET,
    user_agent TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_history_document_fk
        FOREIGN KEY (document_id)
        REFERENCES docutracker_documents(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_history_routing_record_fk
        FOREIGN KEY (routing_record_id)
        REFERENCES docutracker_routing_records(id)
        ON DELETE SET NULL,

    CONSTRAINT docutracker_history_actor_role_fk
        FOREIGN KEY (actor_role_id)
        REFERENCES docutracker_roles(role_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT docutracker_history_category_check
        CHECK (
            event_category IN (
                'workflow',
                'system',
                'deadline',
                'escalation',
                'security',
                'administrative',
                'file',
                'notification',
                'ai'
            )
        ),

    CONSTRAINT docutracker_history_action_not_blank
        CHECK (BTRIM(action) <> ''),

    CONSTRAINT docutracker_history_step_check
        CHECK (
            (from_step IS NULL OR from_step >= 0)
            AND
            (to_step IS NULL OR to_step >= 0)
        ),

    CONSTRAINT docutracker_history_escalation_check
        CHECK (escalation_level >= 0)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_created
    ON docutracker_document_history(document_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_history_actor
    ON docutracker_document_history(actor_id, created_at DESC)
    WHERE actor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_history_category
    ON docutracker_document_history(event_category, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_history_metadata_gin
    ON docutracker_document_history
    USING GIN (metadata);

-- ============================================================
-- 13. NOTIFICATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID,
    user_id UUID NOT NULL,

    notification_type TEXT NOT NULL,
    channel TEXT NOT NULL DEFAULT 'in_app',

    title TEXT NOT NULL,
    body TEXT NOT NULL,

    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,

    delivery_status TEXT NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    failure_reason TEXT,

    event_key TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_notifications_document_fk
        FOREIGN KEY (document_id)
        REFERENCES docutracker_documents(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_notifications_type_not_blank
        CHECK (BTRIM(notification_type) <> ''),

    CONSTRAINT docutracker_notifications_channel_check
        CHECK (channel IN ('in_app', 'email', 'sms', 'push')),

    CONSTRAINT docutracker_notifications_title_not_blank
        CHECK (BTRIM(title) <> ''),

    CONSTRAINT docutracker_notifications_body_not_blank
        CHECK (BTRIM(body) <> ''),

    CONSTRAINT docutracker_notifications_delivery_status_check
        CHECK (
            delivery_status IN (
                'pending',
                'sent',
                'delivered',
                'failed',
                'cancelled'
            )
        ),

    CONSTRAINT docutracker_notifications_read_consistency
        CHECK (
            (is_read = FALSE AND read_at IS NULL)
            OR
            (is_read = TRUE)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_docutracker_notifications_user_event
    ON docutracker_notifications(user_id, event_key)
    WHERE event_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_unread
    ON docutracker_notifications(user_id, created_at DESC)
    WHERE is_read = FALSE;

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_document
    ON docutracker_notifications(document_id, created_at DESC)
    WHERE document_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_delivery
    ON docutracker_notifications(delivery_status, created_at)
    WHERE delivery_status IN ('pending', 'failed');

-- ============================================================
-- 14. PERMISSIONS
-- Permission may belong to either a role or a user.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id TEXT,
    user_id UUID,

    document_type TEXT,
    action TEXT NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE,

    scope_type TEXT NOT NULL DEFAULT 'global',
    scope_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_permissions_role_fk
        FOREIGN KEY (role_id)
        REFERENCES docutracker_roles(role_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT docutracker_permissions_document_type_fk
        FOREIGN KEY (document_type)
        REFERENCES docutracker_document_types(document_type)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT docutracker_permissions_principal_check
        CHECK (
            (role_id IS NOT NULL AND user_id IS NULL)
            OR
            (role_id IS NULL AND user_id IS NOT NULL)
        ),

    CONSTRAINT docutracker_permissions_action_not_blank
        CHECK (BTRIM(action) <> ''),

    CONSTRAINT docutracker_permissions_scope_check
        CHECK (
            (scope_type = 'global' AND scope_id IS NULL)
            OR
            (scope_type IN ('department', 'office', 'campus')
                AND scope_id IS NOT NULL)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_docutracker_permissions_role
    ON docutracker_permissions(
        role_id,
        COALESCE(document_type, '*'),
        action,
        scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::UUID)
    )
    WHERE role_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_docutracker_permissions_user
    ON docutracker_permissions(
        user_id,
        COALESCE(document_type, '*'),
        action,
        scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::UUID)
    )
    WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_role
    ON docutracker_permissions(role_id)
    WHERE role_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_user
    ON docutracker_permissions(user_id)
    WHERE user_id IS NOT NULL;

CREATE TRIGGER trg_docutracker_permissions_updated_at
BEFORE UPDATE ON docutracker_permissions
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 15. ESCALATION CONFIGURATION
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_escalation_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_type TEXT NOT NULL,
    department_id UUID,

    escalation_level INT NOT NULL DEFAULT 1,
    target_type TEXT NOT NULL,
    target_user_id UUID,
    target_role_id TEXT,
    target_department_id UUID,

    escalation_delay_minutes INT NOT NULL,
    repeat_interval_minutes INT,
    max_escalation_level INT NOT NULL DEFAULT 1,

    notify_original_sender BOOLEAN NOT NULL DEFAULT TRUE,
    notify_current_assignees BOOLEAN NOT NULL DEFAULT TRUE,
    business_hours_only BOOLEAN NOT NULL DEFAULT FALSE,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_escalation_document_type_fk
        FOREIGN KEY (document_type)
        REFERENCES docutracker_document_types(document_type)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT docutracker_escalation_role_fk
        FOREIGN KEY (target_role_id)
        REFERENCES docutracker_roles(role_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT docutracker_escalation_level_check
        CHECK (escalation_level > 0),

    CONSTRAINT docutracker_escalation_target_type_check
        CHECK (
            target_type IN (
                'user',
                'role',
                'department',
                'department_head',
                'document_creator',
                'sender_supervisor',
                'system_admin'
            )
        ),

    CONSTRAINT docutracker_escalation_target_check
        CHECK (
            (target_type = 'user'
                AND target_user_id IS NOT NULL
                AND target_role_id IS NULL
                AND target_department_id IS NULL)
            OR
            (target_type = 'role'
                AND target_user_id IS NULL
                AND target_role_id IS NOT NULL
                AND target_department_id IS NULL)
            OR
            (target_type IN ('department', 'department_head')
                AND target_user_id IS NULL
                AND target_role_id IS NULL
                AND target_department_id IS NOT NULL)
            OR
            (target_type IN (
                'document_creator',
                'sender_supervisor',
                'system_admin'
            )
                AND target_user_id IS NULL
                AND target_role_id IS NULL
                AND target_department_id IS NULL)
        ),

    CONSTRAINT docutracker_escalation_delay_check
        CHECK (escalation_delay_minutes > 0),

    CONSTRAINT docutracker_escalation_repeat_check
        CHECK (
            repeat_interval_minutes IS NULL
            OR repeat_interval_minutes > 0
        ),

    CONSTRAINT docutracker_escalation_max_level_check
        CHECK (max_escalation_level >= escalation_level),

    CONSTRAINT docutracker_escalation_unique
        UNIQUE (
            document_type,
            department_id,
            escalation_level
        )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_escalation_lookup
    ON docutracker_escalation_configs(
        document_type,
        department_id,
        escalation_level
    )
    WHERE is_enabled = TRUE;

CREATE TRIGGER trg_docutracker_escalation_configs_updated_at
BEFORE UPDATE ON docutracker_escalation_configs
FOR EACH ROW
EXECUTE FUNCTION docutracker_set_updated_at();

-- ============================================================
-- 16. TRANSITION REQUESTS / IDEMPOTENCY
-- Prevents duplicate approve/reject/return operations.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_transition_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL,
    routing_record_id UUID,

    action TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    actor_id UUID NOT NULL,

    request_payload JSONB,
    response_payload JSONB,

    status TEXT NOT NULL DEFAULT 'processing',
    error_message TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    CONSTRAINT docutracker_transition_requests_document_fk
        FOREIGN KEY (document_id)
        REFERENCES docutracker_documents(id)
        ON DELETE CASCADE,

    CONSTRAINT docutracker_transition_requests_routing_fk
        FOREIGN KEY (routing_record_id)
        REFERENCES docutracker_routing_records(id)
        ON DELETE SET NULL,

    CONSTRAINT docutracker_transition_requests_action_not_blank
        CHECK (BTRIM(action) <> ''),

    CONSTRAINT docutracker_transition_requests_key_not_blank
        CHECK (BTRIM(idempotency_key) <> ''),

    CONSTRAINT docutracker_transition_requests_status_check
        CHECK (status IN ('processing', 'completed', 'failed')),

    CONSTRAINT docutracker_transition_requests_completion_check
        CHECK (
            (status = 'processing' AND completed_at IS NULL)
            OR
            (status IN ('completed', 'failed'))
        ),

    CONSTRAINT docutracker_transition_requests_unique
        UNIQUE (document_id, action, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_transition_requests_document
    ON docutracker_transition_requests(document_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_transition_requests_actor
    ON docutracker_transition_requests(actor_id, created_at DESC);

-- ============================================================
-- 17. DOCUMENT NUMBER SEQUENCES
-- Supports separate counters by year, type, and optional scope.
-- ============================================================

CREATE TABLE IF NOT EXISTS docutracker_document_number_sequences (
    year INT NOT NULL,
    document_type TEXT NOT NULL,
    scope_type TEXT NOT NULL DEFAULT 'global',
    scope_id UUID,
    prefix TEXT,
    last_value BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT docutracker_number_sequences_document_type_fk
        FOREIGN KEY (document_type)
        REFERENCES docutracker_document_types(document_type)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT docutracker_number_sequences_year_check
        CHECK (year BETWEEN 2000 AND 9999),

    CONSTRAINT docutracker_number_sequences_last_value_check
        CHECK (last_value >= 0),

    CONSTRAINT docutracker_number_sequences_scope_check
        CHECK (
            (scope_type = 'global' AND scope_id IS NULL)
            OR
            (scope_type IN ('department', 'office', 'campus')
                AND scope_id IS NOT NULL)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_docutracker_number_sequences
    ON docutracker_document_number_sequences(
        year,
        document_type,
        scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::UUID)
    );

-- Atomic function for generating the next document number.
CREATE OR REPLACE FUNCTION docutracker_next_document_number(
    p_document_type TEXT,
    p_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    p_scope_type TEXT DEFAULT 'global',
    p_scope_id UUID DEFAULT NULL,
    p_prefix TEXT DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_next BIGINT;
    v_prefix TEXT;
BEGIN
    IF p_scope_type = 'global' AND p_scope_id IS NOT NULL THEN
        RAISE EXCEPTION 'Global scope must not have scope_id';
    END IF;

    IF p_scope_type <> 'global' AND p_scope_id IS NULL THEN
        RAISE EXCEPTION 'Non-global scope requires scope_id';
    END IF;

    INSERT INTO docutracker_document_number_sequences (
        year,
        document_type,
        scope_type,
        scope_id,
        prefix,
        last_value,
        updated_at
    )
    VALUES (
        p_year,
        p_document_type,
        p_scope_type,
        p_scope_id,
        p_prefix,
        1,
        NOW()
    )
    ON CONFLICT (
        year,
        document_type,
        scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::UUID)
    )
    DO UPDATE SET
        last_value = docutracker_document_number_sequences.last_value + 1,
        prefix = COALESCE(
            EXCLUDED.prefix,
            docutracker_document_number_sequences.prefix
        ),
        updated_at = NOW()
    RETURNING last_value, prefix
    INTO v_next, v_prefix;

    RETURN CONCAT(
        COALESCE(v_prefix, UPPER(p_document_type)),
        '-',
        p_year,
        '-',
        LPAD(v_next::TEXT, 6, '0')
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- OPTIONAL SEED DATA
-- Edit these values to match your HRMS roles and document types.
-- ============================================================

INSERT INTO docutracker_roles (
    role_id,
    display_name,
    description
)
VALUES
    ('admin', 'Administrator', 'Full DocuTracker administration access'),
    ('records_officer', 'Records Officer', 'Manages document records and routing'),
    ('reviewer', 'Reviewer', 'Reviews routed documents'),
    ('approver', 'Approver', 'Approves or rejects documents'),
    ('employee', 'Employee', 'Creates and monitors documents')
ON CONFLICT (role_id) DO NOTHING;

INSERT INTO docutracker_document_types (
    document_type,
    display_name,
    description,
    number_prefix
)
VALUES
    ('memorandum', 'Memorandum', 'Internal memorandum document', 'MEMO'),
    ('letter', 'Letter', 'Official letter document', 'LTR'),
    ('request', 'Request', 'General request document', 'REQ'),
    ('report', 'Report', 'Official report document', 'RPT')
ON CONFLICT (document_type) DO NOTHING;

COMMIT;

-- ============================================================
-- EXAMPLE USAGE
-- ============================================================

-- Generate the next memorandum number:
-- SELECT docutracker_next_document_number('memorandum');
--
-- Example output:
-- MEMO-2026-000001
--
-- Generate a scoped department request number:
-- SELECT docutracker_next_document_number(
--     'request',
--     2026,
--     'department',
--     '00000000-0000-0000-0000-000000000001'::UUID,
--     'REQ-HR'
-- );
--
-- IMPORTANT EXTERNAL FOREIGN KEYS TO ADD LATER:
--
-- ALTER TABLE docutracker_documents
-- ADD CONSTRAINT docutracker_documents_created_by_fk
-- FOREIGN KEY (created_by)
-- REFERENCES your_users_table(id)
-- ON DELETE RESTRICT;
--
-- ALTER TABLE docutracker_documents
-- ADD CONSTRAINT docutracker_documents_current_holder_fk
-- FOREIGN KEY (current_holder_id)
-- REFERENCES your_users_table(id)
-- ON DELETE SET NULL;
--
-- Repeat this for user_id, actor_id, generated_by,
-- department_id, target_user_id, and other HRMS references.
