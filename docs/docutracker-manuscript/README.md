# DocuTracker Manuscript Diagrams

This package contains DocuTracker-only figures based on the implemented Flutter, Express, and PostgreSQL module contracts.

| Figure | Diagram | Editable source | Manuscript caption |
|---:|---|---|---|
| 1 | Entity-Relationship Diagram | `01-erd-database-style.html` | Physical database-style entity-relationship diagram of the principal DocuTracker tables and their relationships. |
| 2 | DFD Level 0 | `02-dfd-level-0.mmd` | Context-level data flow diagram of the DocuTracker module. |
| 3 | DFD Level 1 | `03-dfd-level-1.mmd` | Level 1 data flow diagram showing DocuTracker processes, actors, and data stores. |
| 4 | Flowchart | `04-flowchart.mmd` | Flowchart of document creation, routing, review, escalation, and completion in DocuTracker. |
| 5 | System Diagram | `05-system-diagram.mmd` | System diagram showing DocuTracker users, functions, data, and authorized HRMS integrations. |
| 6 | System Architecture | `06-system-architecture.mmd` | Layered system architecture of the DocuTracker Flutter client, Express backend, and PostgreSQL data layer. |
| 7 | Use Case Diagram | `07-use-case.mmd` | Use case diagram for Employee, Reviewer or Signer, and Administrator interactions with DocuTracker. |
| 8 | User Sequence | `08-user-sequence.mmd` | User sequence for document submission and reviewer action in DocuTracker. |

The `.mmd` files are editable Mermaid sources. The generated `.svg` files are preferred for manuscripts because they remain sharp at any size; `.png` files are provided for editors that do not accept SVG.

Connectors use sharp elbow routing instead of curved lines, including the ERD. The ERD uses database-table boxes and Crow's Foot notation: `||` means exactly one, `o|` means zero or one, and `o{` means zero or many. The system and architecture figures use recognizable Flutter, Node.js, Express, and PostgreSQL marks; formal analysis diagrams retain their standard notation without decorative technology logos.

Important scope notes:

- The ERD is a readable principal-entity view, not every column in every table.
- Reviewer and Signer are workflow capabilities, not invented HRMS roles.
- DTR, RSP, and L&D appear only as authorized source integrations; their business processes remain outside DocuTracker.
- Backend authorization and PostgreSQL transactions are authoritative for workflow, permissions, signatures, and audit history.
