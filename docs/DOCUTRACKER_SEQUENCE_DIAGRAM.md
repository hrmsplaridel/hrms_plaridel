# DocuTracker — Sequence Diagrams (PlantUML)

PlantUML source files for manuscript sequence diagrams, matching the L&D and RSP module style.

## Files

| File | Diagram | Suggested figure |
|------|---------|------------------|
| [`docutracker-user-sequence.puml`](docutracker-user-sequence.puml) | Employee create/submit + Reviewer approve | Figure 6 |
| [`docutracker-administrator-sequence.puml`](docutracker-administrator-sequence.puml) | Admin configure workflow, assignees, permissions | Figure 7 |

## How to render

### Option A — PlantUML online
1. Go to [plantuml.com/plantuml](https://www.plantuml.com/plantuml/uml/)
2. Paste the contents of a `.puml` file
3. Export PNG or SVG

### Option B — VS Code / Cursor extension
1. Install **PlantUML** extension
2. Open `.puml` file → **Preview Current Diagram**
3. Export from preview

### Option C — Command line
```bash
java -jar plantuml.jar docs/docutracker-user-sequence.puml
java -jar plantuml.jar docs/docutracker-administrator-sequence.puml
```

Save exported PNGs alongside other module diagrams:
- `docs/docutracker-user-sequence-diagram.png`
- `docs/docutracker-administrator-sequence-diagram.png`

---

## Figure 6 — User sequence diagram

**Caption:**

> **Figure 6.** Sequence diagram of DocuTracker showing how an employee submits a document and a reviewer approves it.

**Description:**

> Steps 1–8 cover document creation and submission. The employee creates a document (1), the app sends it to the server (2–3), and a draft is saved (4). On submit (5–7), the server assigns a reviewer and sends a notification (8). Steps 9–17 cover review: the reviewer opens the document (9–12), approves it (13–15), and both reviewer and employee see the updated status (16–17).

---

## Figure 7 — Administrator sequence diagram

**Caption:**

> **Figure 7.** Sequence diagram of DocuTracker showing how an administrator configures workflows, permissions, and monitors overdue documents.

**Description:**

> Steps 1–4 load the admin settings. Steps 5–8 save workflow steps and assignees as a new version. Steps 9–12 store permission rules. Steps 13–16 retrieve and display overdue documents.

---

## List of Figures entries

| Figure | Entry |
|--------|--------|
| Figure 6 | Sequence diagram of DocuTracker user interactions |
| Figure 7 | Sequence diagram of DocuTracker administrator interactions |

---

## Simplified participants (if thesis requires fewer lifelines)

Replace detailed layers with:

| Full stack | Simplified |
|------------|------------|
| Flutter UI + Provider + Repository | **DocuTracker Client** |
| API + Workflow Service | **DocuTracker Server** |
| PostgreSQL | **Database** |

See commented simplified versions below if needed.

---

## Related diagrams

| Document | Purpose |
|----------|---------|
| [DOCUTRACKER_DFD.md](DOCUTRACKER_DFD.md) | Data flow diagrams |
| [DOCUTRACKER_ERD.md](DOCUTRACKER_ERD.md) | Entity-relationship diagrams |
| [LD_DFD_LEVEL_0.md](LD_DFD_LEVEL_0.md) | L&D reference style |
