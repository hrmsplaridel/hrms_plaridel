DocuTracker Flutter Module Instructions

Scope

These instructions apply only to:

frontend/lib/docutracker/

This directory contains the Flutter frontend implementation of the DocuTracker or Document Tracker module inside a larger HRMS application.

Technology stack:

Frontend: Flutter and Dart

Backend API: Node.js and Express

Database: PostgreSQL

Do not place Node.js code, Express routes, PostgreSQL migrations, SQL files, or backend business logic inside this directory.

Do not modify unrelated HRMS modules unless the requested DocuTracker feature genuinely requires integration with them.

Before changing a file outside frontend/lib/docutracker/:

Explain why the external change is necessary.

Confirm that no DocuTracker-local solution exists.

Make the smallest possible external change.

List the external files changed.

Primary Objective

Maintain and improve the DocuTracker module while preserving:

Existing document workflows

Document routing history

Document status history

User permissions

Document visibility rules

Attachments

Notifications

Escalation behavior

Admin and employee separation

Mobile, web, and responsive behavior

Existing API contracts

Never invent statuses, roles, permissions, workflow actions, API endpoints, request fields, response fields, or database behavior.

Inspect the existing code and documentation before making assumptions.

Existing Module Structure

Follow the current structure:

docutracker/
├── data/
│   ├── dto/
│   ├── navigation/
│   ├── providers/
│   ├── repositories/
│   ├── routes/
│   └── styles/
├── models/
├── presentation/
│   ├── admin/
│   │   ├── pages/
│   │   └── widgets/
│   ├── employee/
│   │   └── pages/
│   └── shared/
│       ├── pages/
│       └── widgets/
├── security/
├── services/
├── theme/
├── utils/
├── DOCUTRACKER_API.md
└── DOCUTRACKER_SCHEMA.md

Preserve this architecture:

Screen or Widget
    ↓
Provider
    ↓
Service or Repository
    ↓
Backend API

Do not place API requests, permission evaluation, workflow validation, or complex business logic directly inside screens or widgets.

---

## General Coding Rules

* Study the relevant code before making changes.
* Follow existing naming, architecture, styling, and state-management conventions.
* Make the smallest safe change.
* Do not rewrite unrelated files.
* Do not remove existing functionality unless explicitly requested.
* Reuse existing models, widgets, services, providers, repositories, utilities, styles, routes, and theme tokens.
* Search the module before creating a new class or file.
* Do not add a package unless explicitly approved.
* Do not rename public classes, fields, routes, or services without checking all references.
* Preserve backward compatibility where possible.
* Use null safety correctly.
* Prefer `final` for values that do not change.
* Prefer immutable objects where appropriate.
* Use `const` widgets where possible.
* Avoid unnecessary use of `dynamic`.
* Avoid unsafe force unwraps.
* Do not suppress analyzer warnings without a valid reason.
* Keep changes focused and reviewable.
* Do not claim a feature works unless it was tested or verified.

---

## Required Investigation Before Editing

Before implementing a DocuTracker change:

1. Identify the affected screen or widget.
2. Identify the provider managing its state.
3. Identify the repository or service used by that provider.
4. Identify the models involved.
5. Read `DOCUTRACKER_API.md` when API behavior is involved.
6. Read `DOCUTRACKER_SCHEMA.md` when statuses, workflows, permissions, routing, or document structures are involved.
7. Trace the current data flow.
8. Search for an existing reusable implementation.
9. Check all consumers of shared models and services.
10. Identify permission and workflow implications.
11. Make the smallest safe implementation.
12. Run formatting, analysis, and relevant tests.

For large changes, provide a short plan before editing.

---

# Architecture Responsibilities

## `data/dto/`

Primary example:

* `docutracker_api_result.dart`

Use DTOs for API-specific response structures.

Rules:

* Keep raw JSON parsing out of screens and widgets.
* Parse nullable fields safely.
* Preserve backend JSON field names.
* Do not silently rename API fields.
* Do not hide invalid backend data using misleading fallback values.
* Prefer typed values over `dynamic`.
* Keep parsing logic testable.
* Do not place UI logic inside DTOs.

---

## `data/navigation/`

This directory contains DocuTracker-specific navigation behavior.

Rules:

* Reuse the current navigation system.
* Do not introduce another routing package.
* Do not hardcode route strings throughout the module.
* Keep reusable widgets independent of navigation when possible.
* Validate route arguments.
* Do not navigate users to restricted documents or admin screens.
* Handle missing, archived, deleted, or inaccessible documents safely.
* Reuse existing document and notification navigation helpers.

---

## `data/providers/`

Primary file:

* `docutracker_provider.dart`

The provider should coordinate frontend state and call services or repositories.

Rules:

* Preserve the current state-management approach.
* Do not add Bloc, Riverpod, GetX, Redux, or another state-management framework.
* Do not perform direct HTTP requests from the provider when repository methods already exist.
* Do not place large workflow or permission rules directly in the provider.
* Use services for business rules.
* Track loading, refreshing, empty, success, and error states clearly.
* Prevent duplicate API calls.
* Prevent duplicate submissions from repeated taps.
* Notify listeners only when state meaningfully changes.
* Preserve valid existing state when a request fails.
* Do not show success until the backend confirms success.
* Dispose provider-owned resources correctly.
* Avoid rebuilding the entire DocuTracker module for small state changes.

When changing provider behavior, check all screens and widgets that listen to it.

---

## `data/repositories/`

Primary file:

* `docutracker_repository.dart`

The repository is responsible for API communication and response conversion.

Rules:

* All DocuTracker API communication should pass through the repository or an existing service abstraction.
* Do not make direct HTTP calls from widgets or screens.
* Keep endpoint paths out of presentation code.
* Reuse the existing API client and authentication behavior.
* Preserve request and response contracts.
* Convert transport-level errors into understandable module errors.
* Handle:

  * Timeouts
  * Invalid responses
  * Unauthorized requests
  * Forbidden requests
  * Missing records
  * Validation errors
  * Server errors
* Do not expose stack traces, SQL errors, tokens, or confidential document content.
* Avoid duplicate repository methods for the same operation.
* Do not silently change return types or response structures.

---

## `data/routes/`

Primary file:

* `docutracker_routes.dart`

Rules:

* Reuse existing route constants.
* Search for an existing route before creating another one.
* Keep naming consistent.
* Avoid multiple routes that open the same screen unnecessarily.
* Validate all route arguments.
* Restrict admin routes appropriately.
* Handle direct navigation safely.
* Do not expose restricted documents through route parameters.

---

## `data/styles/`

Primary file:

* `docutracker_styles.dart`

Rules:

* Reuse existing spacing, typography, colors, borders, and dimensions.
* Do not repeatedly hardcode style values inside widgets.
* Preserve compatibility with the parent HRMS theme.
* Do not redesign screens unless explicitly requested.
* Keep responsive behavior intact.
* Avoid duplicate style constants.

---

# Documentation

Primary documentation:

* `DOCUTRACKER_API.md`
* `DOCUTRACKER_SCHEMA.md`

These files are the local source of truth for the DocuTracker frontend contract.

Rules:

* Read `DOCUTRACKER_API.md` before changing endpoints, request bodies, response parsing, attachments, notifications, or backend operations.
* Read `DOCUTRACKER_SCHEMA.md` before changing document structures, statuses, workflow steps, routing, escalation, or permissions.
* Do not invent API behavior.
* Do not invent database columns.
* Do not invent new statuses or workflow transitions.
* Update documentation only when the implementation and contract genuinely changed.
* Do not document unimplemented features.

---

# Models

Existing model files include:

* `document.dart`
* `document_action.dart`
* `document_history.dart`
* `document_notification.dart`
* `document_permission.dart`
* `document_routing_config.dart`
* `document_routing_record.dart`
* `document_status.dart`
* `document_type.dart`
* `escalation_config.dart`
* `workflow_step.dart`
* `models.dart`

Rules:

* Search existing models before creating a new model.
* Extend an existing model when appropriate instead of duplicating it.
* Keep models independent of presentation code.
* Do not place API requests, navigation, provider state, or widget logic in models.
* Preserve backend field names in JSON serialization and deserialization.
* Parse nullable fields safely.
* Use typed status, permission, and action values where existing model types support them.
* Do not create fallback values that hide invalid backend data.
* Avoid unnecessary `dynamic`.
* Avoid unsafe null assertions.
* Check all consumers before renaming a field.
* Update `models.dart` when a new shared model needs to be exported.
* Keep model serialization behavior backward-compatible.

---

# Presentation Layer

The presentation layer is divided into:

* Admin
* Employee
* Shared

Do not mix these responsibilities.

---

## Admin Pages

Location:

`presentation/admin/pages/`

Existing responsibilities include:

* DocuTracker administration
* Escalation configuration
* Permission editing
* Permission setup
* Workflow step assignees
* Workflow editing

Rules:

* Only authorized users should see admin features.
* Hiding a control in Flutter is not sufficient authorization.
* Backend authorization remains mandatory.
* Reuse existing admin widgets and services.
* Keep workflow-editing logic outside `build()` methods.
* Validate configuration before submitting.
* Prevent duplicate saves.
* Disable or guard buttons while requests are running.
* Do not permanently update local state until the backend confirms success.
* Warn before destructive changes.
* Do not silently remove permissions, assignees, workflow steps, or escalation rules.
* Consider the effect of configuration changes on existing documents.
* Preserve the current admin design unless redesign is requested.

---

## Admin Widgets

Location:

`presentation/admin/widgets/`

Existing widgets include responsibilities such as:

* Admin UI
* Permission management
* Workflow actions
* Workflow step editing

Rules:

* Keep widgets focused and reusable.
* Move business rules into services.
* Do not duplicate permission logic inside multiple widgets.
* Pass data and callbacks through constructors.
* Avoid direct repository calls from widgets.
* Preserve validation and confirmation behavior.

---

## Employee Pages

Location:

`presentation/employee/pages/`

Primary file:

* `mobile_employee_portal.dart`

Rules:

* Employees must only see actions allowed by their permissions.
* Do not expose admin configuration controls.
* Preserve mobile usability.
* Avoid fixed widths that overflow.
* Keep primary document actions accessible on small screens.
* Do not display confidential information belonging to another employee, office, or department.
* Handle restricted, missing, or unavailable documents safely.
* Preserve the current employee navigation and UI style.

---

## Shared Pages

Location:

`presentation/shared/pages/`

Existing pages include responsibilities such as:

* DocuTracker dashboard
* Document listing
* Document details
* Main DocuTracker navigation
* Module entry screens

Rules:

* Shared pages must not assume the user is always an admin or employee.
* Use centralized permission checks.
* Preserve loading, empty, error, and success states.
* Keep pages focused on coordination and layout.
* Move reusable UI into shared widgets.
* Do not make direct HTTP requests from pages.
* Preserve responsive layouts.

---

## Shared Widgets

Location:

`presentation/shared/widgets/`

Existing widgets include responsibilities such as:

* Countdown timers
* Document creation
* Document attachments
* Document detail sections
* Empty states
* Error banners
* Module headers
* Notification panels
* Responsive layouts
* Section headers
* Slide-in panels
* Status badges
* Status timelines
* Summary cards

Rules:

* Reuse an existing widget before creating a new one.
* Keep shared widgets independent of admin-only and employee-only assumptions.
* Pass required data through constructors.
* Keep widgets small and focused.
* Split oversized widgets into smaller reusable pieces.
* Keep business logic out of `build()`.
* Do not perform HTTP requests directly from widgets.
* Use `const` constructors where possible.
* Dispose controllers, streams, subscriptions, focus nodes, and animation controllers.
* Guard asynchronous UI updates using `mounted` where appropriate.
* Preserve loading, empty, refreshing, error, and success states.
* Avoid unnecessary rebuilds.
* Do not create multiple different widgets for the same status or summary unless necessary.

---

# Security and Roles

Primary file:

* `security/docutracker_roles.dart`

Rules:

* Reuse existing role constants.
* Do not hardcode role strings across screens.
* Do not create frontend-only roles or permissions.
* Do not weaken role checks to make a feature easier to access.
* Frontend checks only control the interface.
* Backend authentication and authorization remain authoritative.
* Do not store passwords, secrets, tokens, or confidential document content in source code.
* Do not expose restricted information in logs, notifications, previews, or error messages.
* Prevent direct navigation to restricted admin or document screens.

---

# Service Layer

Existing service responsibilities include:

* Access policy
* Document visibility
* Notifications
* Permission evaluation
* Permission management
* Permission persistence or data access
* Workflow configuration validation
* Workflow operations
* Employee directory lookup

Existing files include names similar to:

* `docutracker_access_policy.dart`
* `docutracker_document_visibility_service.dart`
* `docutracker_notification_service.dart`
* `docutracker_permission_evaluator.dart`
* `docutracker_permission_service.dart`
* `docutracker_permissions_datasource.dart`
* `docutracker_workflow_config_validator.dart`
* `docutracker_workflow_service.dart`
* `employee_directory_lookup.dart`

Rules:

* Reuse an existing service before creating a new one.
* Keep each service focused on one responsibility.
* Keep business rules out of widgets.
* Use the permission evaluator for permission decisions.
* Use the access policy and visibility service for document visibility.
* Use the workflow service for workflow operations.
* Use the workflow validator before saving workflow configuration.
* Use the notification service for notification behavior.
* Use employee directory lookup for employee data when available.
* Avoid circular service dependencies.
* Do not make services depend on widgets.
* Handle failures explicitly.
* Do not silently ignore failed workflow, permission, or notification operations.
* Keep services testable.

---

# Theme

Primary file:

* `theme/docutracker_tokens.dart`

Rules:

* Reuse DocuTracker design tokens.
* Do not scatter colors, spacing, radii, icon sizes, and typography throughout widgets.
* Preserve parent HRMS theme compatibility.
* Preserve dark mode behavior when supported.
* Avoid hardcoded colors that harm readability or accessibility.
* Do not create another theme system.

---

# Utilities

Existing utility responsibilities include:

* Opening attachments
* Permission reasoning
* Workflow phase interpretation

Rules:

* Reuse existing utilities.
* Keep utilities stateless where possible.
* Do not place large business rules in generic utility files.
* Preserve platform-specific attachment implementations.
* Do not import web-only packages into mobile implementations.
* Do not import mobile-only packages into web implementations.
* Preserve conditional imports.
* Avoid duplicate utility logic.
* Keep utility names specific and descriptive.

---

# Task-to-File Guidance

Use this section to determine where a change likely belongs.

## Adding or changing an API request

Inspect and modify, when needed:

1. `DOCUTRACKER_API.md`
2. Relevant model or DTO
3. `docutracker_repository.dart`
4. Relevant service
5. `docutracker_provider.dart`
6. Consuming screen or widget

Do not implement the request directly inside a widget.

---

## Changing document status behavior

Inspect:

1. `document_status.dart`
2. `document_action.dart`
3. `workflow_step.dart`
4. `docutracker_workflow_service.dart`
5. `docutracker_workflow_config_validator.dart`
6. `DOCUTRACKER_SCHEMA.md`
7. `DOCUTRACKER_API.md`
8. Provider and consuming UI

Do not invent a status or transition.

---

## Changing document routing

Inspect:

1. `document_routing_config.dart`
2. `document_routing_record.dart`
3. `workflow_step.dart`
4. Workflow service
5. Repository
6. Provider
7. Routing timeline or detail widgets
8. API and schema documentation

Preserve routing history and responsible users or offices.

---

## Changing permissions

Inspect:

1. `document_permission.dart`
2. `docutracker_roles.dart`
3. `docutracker_access_policy.dart`
4. `docutracker_document_visibility_service.dart`
5. `docutracker_permission_evaluator.dart`
6. `docutracker_permission_service.dart`
7. `docutracker_permissions_datasource.dart`
8. Admin permission pages and widgets
9. Employee and shared UI consumers

Keep permission logic centralized.

---

## Changing workflow configuration

Inspect:

1. `document_routing_config.dart`
2. `workflow_step.dart`
3. `docutracker_workflow_service.dart`
4. `docutracker_workflow_config_validator.dart`
5. Admin workflow editor pages
6. Workflow editor widgets
7. Repository and provider
8. API and schema documentation

Validate before saving and prevent invalid workflow definitions.

---

## Changing document visibility

Inspect:

1. `document_permission.dart`
2. `docutracker_roles.dart`
3. `docutracker_access_policy.dart`
4. `docutracker_document_visibility_service.dart`
5. Permission evaluator
6. Dashboard
7. Document list
8. Document detail
9. Notifications
10. Navigation helpers

A restricted document must not appear through another screen or navigation path.

---

## Changing attachments

Inspect:

1. Attachment widgets
2. Attachment-opening utilities
3. Repository upload or download methods
4. Provider state
5. API documentation

Do not place direct attachment HTTP logic inside widgets.

---

## Changing notifications

Inspect:

1. `document_notification.dart`
2. Notification navigation files
3. `docutracker_notification_service.dart`
4. Provider notification state
5. Notification panel or sheet widgets
6. API documentation

Prevent duplicate notifications and restricted document previews.

---

## AI summaries

DocuTracker does not include an AI summary feature.

Do not add AI summary models, widgets, repository methods, API routes, or schema objects unless the feature is explicitly re-approved.

---

## Changing escalation or countdowns

Inspect:

1. `escalation_config.dart`
2. Escalation admin pages
3. Countdown timer widget
4. Workflow service
5. Notification service
6. Provider state
7. API and schema documentation

Treat backend timestamps as authoritative.

---

## Changing UI only

Inspect:

1. Existing shared widgets
2. `docutracker_styles.dart`
3. `docutracker_tokens.dart`
4. Responsive layout widgets
5. Current screen implementation

Reuse existing design patterns and do not duplicate widgets unnecessarily.

---

# Workflow Rules

Before modifying workflow behavior, inspect:

* `document_status.dart`
* `document_action.dart`
* `workflow_step.dart`
* `document_routing_config.dart`
* `document_routing_record.dart`
* `docutracker_workflow_service.dart`
* `docutracker_workflow_config_validator.dart`
* `DOCUTRACKER_API.md`
* `DOCUTRACKER_SCHEMA.md`

Rules:

* Follow only existing statuses and transitions.
* Validate every transition.
* Do not skip required steps.
* Prevent duplicate receiving, forwarding, approval, rejection, returning, completion, or archival actions.
* Preserve routing and history records.
* Preserve timestamps and responsible actors.
* Do not report success until confirmed by the backend.
* Refresh affected screens and state after successful actions.
* Preserve previous valid state after failures.
* Treat the backend as authoritative.
* Never rely solely on Flutter for workflow enforcement.

---

# History and Auditability

Important document actions must remain traceable.

Examples:

* Created
* Edited
* Submitted
* Uploaded
* Forwarded
* Received
* Approved
* Rejected
* Returned
* Completed
* Archived
* Deleted, when deletion is permitted

Rules:

* Never overwrite old history to represent a new action.
* Preserve actor, action, timestamp, document ID, and remarks.
* Do not fabricate history before backend confirmation.
* Keep history ordering consistent.
* Handle missing actor or office data safely.
* Do not expose history to unauthorized users.

---

# Permissions and Visibility Rules

Before changing access behavior, inspect the existing permission and visibility services.

Rules:

* Centralize permission decisions.
* Distinguish document viewing from document actions.
* Check document-level access, not just the user's general role.
* Consider creator, assignee, receiver, office, department, workflow step, and configured permissions where supported.
* Do not expose restricted documents in:

  * Dashboard summaries
  * Search results
  * Document lists
  * Notifications
  * Direct navigation
  * History
  * Attachment links
* A hidden button is not a security control.
* Do not grant permissions locally before backend confirmation.
* Keep denied-access behavior consistent.

---

# Attachment Rules

Rules:

* Handle missing, invalid, expired, deleted, or inaccessible attachments.
* Show upload or download progress when supported.
* Show understandable errors.
* Do not expose physical server paths.
* Preserve original filenames only for display.
* Do not trust file extensions alone.
* Respect backend file type, size, MIME type, and permission rules.
* Preserve mobile and web compatibility.
* Prevent duplicate uploads.
* Do not show upload success until confirmed by the backend.
* Clear temporary upload state after failures.
* Do not log attachment contents or confidential filenames unnecessarily.

---

# Notification Rules

Rules:

* Prevent duplicate notifications.
* Preserve ordering.
* Maintain accurate unread counts.
* Mark notifications read only after the intended operation succeeds.
* Do not open inaccessible documents.
* Handle deleted, archived, missing, or restricted documents safely.
* Refresh notification state after updates.
* Do not expose confidential document details in notification previews.
* Preserve local state if a notification update fails.

---

# Escalation and Countdown Rules

Rules:

* Follow existing escalation configuration.
* Do not invent deadlines or escalation levels.
* Treat backend timestamps as authoritative.
* Handle overdue, due-soon, completed, cancelled, archived, and rejected states correctly.
* Prevent timer resource leaks.
* Avoid rebuilding entire screens every second.
* Prevent duplicate escalation notifications.
* Do not escalate ineligible documents.
* Use timestamp comparisons instead of formatted string comparisons.

---

# Date and Time Rules

* Follow the existing timezone strategy.
* Treat backend timestamps as authoritative.
* Convert timestamps only for display.
* Do not store formatted display strings as authoritative dates.
* Handle nullable timestamps safely.
* Do not assume the device timezone matches the organization's timezone.
* Use timestamp comparisons for deadlines, approvals, routing, receiving, notifications, and escalation.

---

# Error Handling

Every operation should handle:

* Initial loading
* Refreshing
* Empty data
* Network failure
* Timeout
* Offline state
* Validation failure
* Unauthenticated request
* Forbidden action
* Missing document
* Invalid status
* Invalid workflow action
* Duplicate request
* Attachment failure
* Invalid backend response
* Unexpected null values
* Partial data
* Server failure

Rules:

* Show understandable user-facing messages.
* Do not show stack traces, SQL errors, or raw exceptions.
* Do not silently ignore failures.
* Preserve previous valid state when an operation fails.
* Do not report success before backend confirmation.
* Avoid infinite retry loops.
* Log enough information for debugging without exposing secrets or confidential content.
* Reuse the existing DocuTracker error banner and empty-state components.

---

# Responsive Design

* Reuse existing responsive body and layout components.
* Test narrow mobile widths and wider desktop or web layouts.
* Avoid fixed widths that overflow.
* Avoid deeply nested scrolling widgets.
* Keep dialogs, tables, panels, forms, and lists usable on small screens.
* Keep touch targets large enough.
* Prevent clipping of document titles, statuses, employee names, office names, and department names.
* Use wrapping, ellipsis, and adaptive layouts appropriately.
* Keep important actions reachable on mobile.
* Preserve accessibility and readability.

---

# Flutter Lifecycle Rules

* Keep asynchronous work out of `build()`.
* Dispose controllers, focus nodes, streams, subscriptions, and animation controllers.
* Check `mounted` before updating UI state after asynchronous work when needed.
* Avoid starting repeated requests during rebuilds.
* Avoid unnecessary `setState`.
* Preserve current state-management conventions.
* Do not create memory leaks through timers or listeners.

---

# Backend and Database Awareness

The backend uses Node.js and Express. The database uses PostgreSQL.

This directory is frontend-only.

Rules:

* Do not place backend code inside the Flutter DocuTracker directory.
* Do not create SQL migrations here.
* Do not fake backend functionality using frontend-only state.
* Do not store authoritative workflow, routing, permission, or audit data only on the client.
* Clearly state when a requested feature also requires backend or database changes.
* Keep Flutter requests aligned with the actual backend contract.
* Treat backend responses as the final source of truth.

---

# Testing Priorities

Add or update tests when the project has an existing testing setup.

Prioritize testing:

* Model JSON parsing
* DTO parsing
* Provider state transitions
* Repository error handling
* Permission evaluation
* Document visibility
* Workflow validation
* Valid and invalid transitions
* Duplicate actions
* Notifications
* Attachments
* Escalation and countdown logic
* Loading, empty, success, and error states
* Responsive layouts
* Admin and employee access differences

Do not delete or weaken tests to make changes pass.

When automated tests are unavailable, provide exact manual testing steps.

---

# Required Checks

After making changes, run when available:

```bash
dart format frontend/lib/docutracker
flutter analyze
flutter test

If the project already has unrelated analyzer or test failures, separate those clearly from failures introduced by the DocuTracker changes.

Do not claim that formatting, analysis, or tests passed unless they were actually run.

---

# Debugging Procedure

When fixing a DocuTracker bug:

1. Reproduce or trace the issue.
2. Identify the affected layer.
3. Find the root cause.
4. Explain why it happens.
5. Check related workflow and permission behavior.
6. Fix the cause instead of hiding the symptom.
7. Avoid speculative changes.
8. Test success and failure paths.
9. Test mobile and web behavior when relevant.
10. Review the final diff for unrelated changes.
11. Report remaining assumptions or risks.

---

# Git Safety

* Do not force-push.
* Do not reset, discard, overwrite, or delete uncommitted work without explicit approval.
* Do not run destructive Git commands unless explicitly requested.
* Do not modify unrelated files.
* Do not commit secrets, generated builds, dependency folders, or editor files.
* Review the diff before completing a task.
* Do not automatically commit changes unless requested.
* Do not rewrite branch history.

---

# Changes Outside the Module

Do not modify files outside:

`frontend/lib/docutracker/`

unless integration with the main HRMS application is required.

Acceptable examples may include:

* Registering a DocuTracker route
* Adding DocuTracker to the parent navigation
* Connecting an existing authentication provider
* Updating a shared API client
* Updating a shared employee model
* Adding an approved dependency

Before making an external change:

1. Explain why it is necessary.
2. Confirm that no local solution exists.
3. Make the smallest external change.
4. Avoid changing unrelated HRMS behavior.
5. List every external file changed.

---

# Final Response Format

After completing a DocuTracker task, report:

1. Root cause or requested feature
2. Files changed
3. What was implemented
4. API impact
5. Backend or database impact
6. Permission and security impact
7. Formatting, analysis, and tests performed
8. Manual testing steps
9. Remaining assumptions, risks, or limitations

Keep the explanation focused only on DocuTracker.
