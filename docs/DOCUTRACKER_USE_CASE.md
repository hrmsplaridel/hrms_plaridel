# DocuTracker — Use Case Diagram

## Source file

- `docs/docutracker-use-case.puml`

## Render

- PlantUML extension in Cursor/VS Code, or
- [PlantUML online server](https://www.plantuml.com/plantuml/uml/)

## Figure caption

**Figure 9.** Use case diagram of the DocuTracker module showing interactions of Employee, Reviewer, and Administrator with document workflow, administration, and monitoring functions.

## Description (paste-ready)

Figure 9 presents the functional interactions of the DocuTracker module across three actor groups: Employee, Reviewer, and Administrator. Employees create draft documents, optionally manage attachments, submit documents into workflow, track status, and view notifications. Reviewers open assigned documents, perform review actions (approve, forward, return, or reject), and add remarks. Administrators configure workflow steps, assign reviewers, manage permissions, monitor overdue or escalated documents, and apply controlled workflow overrides when necessary. Critical operations include the shared use case **Validate Access and Permissions**, ensuring that view and transition actions are authorized before state changes are applied.

