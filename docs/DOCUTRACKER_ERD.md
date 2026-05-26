# DocuTracker ERD — dbdiagram.io files

Import **one file at a time** into [dbdiagram.io](https://dbdiagram.io) for readable diagrams.

| File | Use for | Tables |
|------|---------|--------|
| [`docutracker-erd-00-overview.dbml`](docutracker-erd-00-overview.dbml) | **Manuscript Figure 5** — simplest | 10 entities (key columns only) |
| [`docutracker-erd-01-documents-runtime.dbml`](docutracker-erd-01-documents-runtime.dbml) | Part 1 — document execution | documents, routing, history, notifications, transitions |
| [`docutracker-erd-02-workflow-config.dbml`](docutracker-erd-02-workflow-config.dbml) | Part 2 — admin workflow setup | config versions, steps, step assignees |
| [`docutracker-erd-03-security-policy.dbml`](docutracker-erd-03-security-policy.dbml) | Part 3 — permissions & escalation | roles, permissions, escalation configs |
| [`docutracker-erd.dbml`](docutracker-erd.dbml) | Full ERD (all tables — crowded) | Everything |

## How to import

1. Open [dbdiagram.io](https://dbdiagram.io)
2. **File → New Diagram**
3. **File → Import → Import from DBML** (or paste file contents)
4. Drag tables to tidy layout → **Export PNG**

## Manuscript suggestion

- **Chapter:** Figure 5 = **Part 0 (overview)** only  
- **Appendix:** Parts 1, 2, 3 as separate figures (Figure A.1, A.2, A.3)

## Figure captions

**Overview (Part 0):** Figure 5. Overview entity-relationship diagram of the DocuTracker database.

**Part 1:** Appendix Figure X.1. DocuTracker runtime tables (documents, routing, history, notifications).

**Part 2:** Appendix Figure X.2. DocuTracker workflow configuration tables.

**Part 3:** Appendix Figure X.3. DocuTracker security and escalation policy tables.
