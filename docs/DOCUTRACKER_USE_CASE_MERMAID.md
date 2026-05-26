# DocuTracker Use Case Diagram — Mermaid

```mermaid
flowchart LR
    %% Left actors
    REV[Reviewer]
    ADM[Administrator]

    %% System boundary
    subgraph SYS["DocuTracker System"]
        direction LR

        subgraph LEFT["Reviewer / Admin Functions"]
            UC6([Open Assigned Document])
            UC7([Approve Document])
            UC8([Forward Document])
            UC9([Return Document])
            UC10([Reject Document])
            UC11([Add Remarks])
            UC12([Configure Workflow Steps])
            UC13([Manage Step Assignees])
            UC14([Manage Permissions])
            UC15([View Overdue / Escalated])
            UC16([Admin Override Document])
        end

        UC5([View Notifications])
        UC17([Validate Access and Permissions])

        subgraph RIGHT["Employee Functions"]
            UC1([Create Draft Document])
            UC2([Manage Attachments])
            UC3([Submit Document])
            UC4([Track Document Status])
        end
    end

    %% Right actor
    EMP[Employee]

    %% Actor associations
    REV --> UC5
    REV --> UC6
    REV --> UC7
    REV --> UC8
    REV --> UC9
    REV --> UC10
    REV --> UC11

    ADM --> UC5
    ADM --> UC12
    ADM --> UC13
    ADM --> UC14
    ADM --> UC15
    ADM --> UC16

    EMP --> UC1
    EMP --> UC2
    EMP --> UC3
    EMP --> UC4
    EMP --> UC5

    %% include / extend semantics
    UC3 -. <<include>> .-> UC17
    UC6 -. <<include>> .-> UC17
    UC7 -. <<include>> .-> UC17
    UC8 -. <<include>> .-> UC17
    UC9 -. <<include>> .-> UC17
    UC10 -. <<include>> .-> UC17
    UC16 -. <<include>> .-> UC17

    UC2 -. <<extend>> .-> UC1
    UC11 -. <<extend>> .-> UC6

    %% Styling
    style SYS fill:#f8fbff,stroke:#666,stroke-width:1px
    style LEFT fill:#ffffff,stroke:#cccccc
    style RIGHT fill:#ffffff,stroke:#cccccc
```

## Caption

**Figure 9.** DocuTracker use case diagram showing Employee (right), Reviewer (left), and Administrator (left) interactions with document workflow and administration functions.

