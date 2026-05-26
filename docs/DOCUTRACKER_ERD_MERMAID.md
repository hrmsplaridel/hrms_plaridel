# DocuTracker ERD — Mermaid (4 parts)

Paste each block into [Mermaid Live](https://mermaid.live) or draw.io (**Arrange → Insert → Advanced → Mermaid**).

---

## Part 0 — Overview (Figure 5)

```mermaid
erDiagram
    users ||--o{ docutracker_documents : "creates"
    users ||--o{ docutracker_documents : "holds"
    users ||--o{ docutracker_routing_records : "assigned"
    users ||--o{ docutracker_document_history : "acts"
    users ||--o{ docutracker_notifications : "receives"
    users ||--o{ docutracker_workflow_step_assignees : "reviewer"
    users ||--o{ docutracker_permissions : "override"

    departments ||--o{ docutracker_escalation_configs : "scopes"

    docutracker_documents ||--|{ docutracker_routing_records : "has"
    docutracker_documents ||--|{ docutracker_document_history : "logs"
    docutracker_documents ||--|{ docutracker_notifications : "generates"

    docutracker_workflow_steps ||--|{ docutracker_workflow_step_assignees : "assigns"

    users {
        uuid id PK
        varchar full_name
        varchar role
    }

    departments {
        uuid id PK
        varchar name
    }

    docutracker_documents {
        uuid id PK
        varchar document_number UK
        varchar document_type
        varchar title
        varchar status
        int current_step
        int workflow_version
        uuid created_by FK
        uuid current_holder_id FK
    }

    docutracker_routing_records {
        uuid id PK
        uuid document_id FK
        int step_order
        uuid assignee_id FK
        varchar status
    }

    docutracker_document_history {
        uuid id PK
        uuid document_id FK
        uuid actor_id FK
        varchar action
    }

    docutracker_notifications {
        uuid id PK
        uuid document_id FK
        uuid user_id FK
        varchar type
    }

    docutracker_workflow_steps {
        uuid id PK
        varchar document_type
        int workflow_version
        int step_order
        varchar label
    }

    docutracker_workflow_step_assignees {
        uuid id PK
        uuid step_id FK
        uuid user_id FK
        boolean is_primary
    }

    docutracker_permissions {
        uuid id PK
        varchar role_id
        uuid user_id FK
        varchar document_type
        varchar action
        boolean granted
    }

    docutracker_escalation_configs {
        uuid id PK
        varchar document_type
        uuid department_id FK
        varchar escalation_target_role
    }
```

---

## Part 1 — Documents and Runtime (Appendix A.1)

```mermaid
erDiagram
    users ||--o{ docutracker_documents : "creates"
    users ||--o{ docutracker_documents : "holds"
    users ||--o{ docutracker_routing_records : "assignee"
    users ||--o{ docutracker_routing_record_assignees : "reviewer"
    users ||--o{ docutracker_document_history : "actor"
    users ||--o{ docutracker_notifications : "recipient"
    users ||--o{ docutracker_transition_requests : "actor"

    docutracker_documents ||--|{ docutracker_routing_records : "has"
    docutracker_documents ||--|{ docutracker_document_history : "logs"
    docutracker_documents ||--|{ docutracker_notifications : "generates"
    docutracker_documents ||--|{ docutracker_transition_requests : "transitions"

    docutracker_routing_records ||--|{ docutracker_routing_record_assignees : "assignees"

    users {
        uuid id PK
        varchar full_name
        varchar role
        varchar email
    }

    docutracker_documents {
        uuid id PK
        varchar document_number UK
        varchar document_type
        varchar title
        varchar status
        int current_step
        int workflow_version
        uuid created_by FK
        uuid current_holder_id FK
        timestamptz deadline_time
        int escalation_level
    }

    docutracker_routing_records {
        uuid id PK
        uuid document_id FK
        int step_order
        uuid assignee_id FK
        varchar status
        timestamptz deadline_time
    }

    docutracker_routing_record_assignees {
        uuid routing_record_id PK_FK
        uuid user_id PK_FK
    }

    docutracker_document_history {
        uuid id PK
        uuid document_id FK
        uuid actor_id FK
        varchar action
        int from_step
        int to_step
    }

    docutracker_notifications {
        uuid id PK
        uuid document_id FK
        uuid user_id FK
        varchar type
        boolean read
    }

    docutracker_transition_requests {
        uuid id PK
        uuid document_id FK
        varchar action
        varchar idempotency_key
        uuid actor_id FK
    }
```

---

## Part 2 — Workflow Configuration (Appendix A.2)

```mermaid
erDiagram
    users ||--o{ docutracker_routing_config_versions : "creates"
    users ||--o{ docutracker_workflow_step_assignees : "assigned"

    departments ||--o{ docutracker_workflow_steps : "scopes"

    docutracker_workflow_steps ||--|{ docutracker_workflow_step_assignees : "assigns"

    users {
        uuid id PK
        varchar full_name
        varchar role
    }

    departments {
        uuid id PK
        varchar name
    }

    docutracker_routing_configs {
        uuid id PK
        varchar document_type UK
        json steps
        int review_deadline_hours
    }

    docutracker_routing_config_versions {
        uuid id PK
        varchar document_type
        int version
        json steps
        uuid created_by FK
    }

    docutracker_workflow_steps {
        uuid id PK
        varchar document_type
        int workflow_version
        int step_order
        uuid department_id FK
        varchar label
        boolean enabled
    }

    docutracker_workflow_step_assignees {
        uuid id PK
        uuid step_id FK
        uuid user_id FK
        boolean is_primary
        int backup_rank
        varchar allowed_actions
    }
```

> **Note:** `routing_config_versions` links to `workflow_steps` logically by `(document_type, workflow_version)` — not a DB foreign key.

---

## Part 3 — Security and Escalation (Appendix A.3)

```mermaid
erDiagram
    docutracker_roles ||--|{ docutracker_role_aliases : "aliases"
    docutracker_roles ||--o{ docutracker_permissions : "role_grants"
    users ||--o{ docutracker_permissions : "user_override"
    departments ||--o{ docutracker_escalation_configs : "scopes"

    docutracker_roles {
        varchar role_id PK
        timestamptz created_at
    }

    docutracker_role_aliases {
        varchar alias PK
        varchar role_id FK
    }

    users {
        uuid id PK
        varchar full_name
        varchar role
    }

    departments {
        uuid id PK
        varchar name
    }

    docutracker_permissions {
        uuid id PK
        varchar role_id FK
        uuid user_id FK
        varchar document_type
        varchar action
        boolean granted
    }

    docutracker_escalation_configs {
        uuid id PK
        varchar document_type
        uuid department_id FK
        varchar escalation_target_role
        int max_escalation_level
    }

    docutracker_document_number_seq {
        int year PK
        bigint last_value
    }
```

> `docutracker_document_number_seq` has no foreign-key relationships.
