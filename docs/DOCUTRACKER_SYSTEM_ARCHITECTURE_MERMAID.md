# DocuTracker System Architecture — Mermaid

Use this for markdown docs, Mermaid Live, or draw.io Mermaid import.

```mermaid
flowchart TB
    %% Actors
    subgraph A["Actors"]
        E[Employee]
        R[Reviewer]
        ADM[Administrator]
    end

    %% Client
    subgraph C["Client Layer (Flutter)"]
        UI[DocuTracker App UI]
        ST[Provider State]
        RC[Repository + API Client]
        UI --> ST --> RC
    end

    %% Server
    subgraph S["Server Layer (Node.js + Express)"]
        API[/API Routes: /api/docutracker/]
        WF[Workflow Service]
        ESC[Escalation Worker]
        API --> WF
        ESC --> WF
    end

    %% Data and integrations
    subgraph D["Data and Integrations"]
        DB[(PostgreSQL)]
        FS[Attachment Storage]
        SRC[HRMS Source Modules\nLD / DTR / RSP]
    end

    E -->|Create / Submit| UI
    R -->|Review / Approve| UI
    ADM -->|Configure / Monitor| UI

    RC -->|REST + JWT| API
    WF -->|Read / Write| DB
    WF -->|Store / Fetch Files| FS
    SRC -. Optional source-linked docs .-> WF

    %% Styling
    style UI fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px
    style ST fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px
    style RC fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px

    style API fill:#d5e8d4,stroke:#82b366,stroke-width:1px
    style WF fill:#d5e8d4,stroke:#82b366,stroke-width:1px
    style ESC fill:#d5e8d4,stroke:#82b366,stroke-width:1px

    style DB fill:#fff2cc,stroke:#d6b656,stroke-width:1px
    style FS fill:#f8cecc,stroke:#b85450,stroke-width:1px
    style SRC fill:#e1d5e7,stroke:#9673a6,stroke-width:1px
```

## Caption

**Figure 8.** System architecture of the DocuTracker module showing actor interaction with the Flutter client, Node.js backend services, PostgreSQL database, attachment storage, and optional HRMS source-module integration.

