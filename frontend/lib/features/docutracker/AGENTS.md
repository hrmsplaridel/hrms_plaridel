# Universal Project Development Instructions

## Scope

These instructions apply to the project or module being edited.

The goal is to make safe, maintainable, secure, and reviewable changes while preserving existing functionality and project conventions.

### Core principles

- Study the relevant code and documentation before making changes.
- Follow the existing architecture, naming, styling, and state-management conventions.
- Make the smallest safe change that solves the requested problem.
- Do not rewrite unrelated files.
- Do not remove existing functionality unless explicitly requested.
- Reuse existing models, components, services, utilities, styles, routes, and shared abstractions before creating new ones.
- Search the project before creating a new class, function, component, service, or file.
- Do not add dependencies unless explicitly approved or clearly required by the project.
- Preserve backward compatibility where practical.
- Do not claim a feature works unless it was actually tested or verified.

---

# Project Architecture

Follow the architecture already established by the project.

A typical layered flow may look like:

```text
UI / Screen / Component
        ↓
State / Controller / Provider
        ↓
Service / Repository
        ↓
API / Database / External Service
```

Do not move business logic into presentation code simply because it is convenient.

### General architecture rules

- Keep UI focused on presentation and user interaction.
- Keep business rules in appropriate services or domain layers.
- Keep API communication in the existing API/client/repository layer.
- Keep data parsing in models, DTOs, serializers, or equivalent layers.
- Keep shared functionality reusable.
- Avoid circular dependencies.
- Avoid duplicating the same business rule in multiple locations.
- Follow the project's existing dependency direction.
- Do not introduce a second architecture or framework without approval.

---

# Required Investigation Before Editing

Before implementing a change:

1. Identify the affected screen, component, feature, or module.
2. Identify the state-management layer involved.
3. Identify the service, repository, API client, or data source involved.
4. Identify the models, DTOs, or data structures involved.
5. Read relevant API documentation when API behavior is involved.
6. Read relevant schema or domain documentation when data, permissions, workflows, or business rules are involved.
7. Trace the current data flow.
8. Search for an existing reusable implementation.
9. Check all consumers of shared models, services, and components.
10. Identify security, permission, workflow, and integration implications.
11. Make the smallest safe implementation.
12. Run formatting, static analysis, tests, and relevant checks when available.

For large changes, provide a short implementation plan before editing.

---

# General Coding Rules

- Use the language's recommended modern practices.
- Prefer immutable values where appropriate.
- Use strong typing instead of unnecessary dynamic or loosely typed values.
- Handle null or missing values safely.
- Avoid unsafe force unwraps or equivalent unsafe operations.
- Do not suppress compiler or analyzer warnings without a valid reason.
- Keep functions and classes focused.
- Avoid unnecessary abstraction.
- Avoid premature optimization.
- Preserve existing public interfaces unless a breaking change is required.
- Keep changes focused and reviewable.
- Add comments only when they explain something that is not obvious from the code.
- Do not add comments that merely restate the code.

---

# Data and Models

Use models or DTOs for structured data.

Rules:

- Keep raw data parsing out of UI code.
- Preserve external API field names unless the existing architecture explicitly maps them.
- Parse nullable and optional fields safely.
- Prefer typed values over generic objects.
- Do not create misleading fallback values that hide invalid data.
- Keep serialization and deserialization predictable.
- Search existing models before creating a new one.
- Extend an existing model when appropriate instead of duplicating it.
- Keep models independent of presentation logic.
- Do not place API requests, navigation, or UI state inside data models.
- Check all consumers before renaming shared fields.

---

# API and Repository Rules

All external API communication should use the project's existing API client, repository, or service abstraction.

- Do not make direct API requests from UI components when an existing abstraction is available.
- Keep endpoint paths out of presentation code.
- Reuse existing authentication and authorization behavior.
- Preserve request and response contracts.
- Do not invent endpoints, request fields, response fields, or backend behavior.
- Handle timeouts, invalid responses, authentication failures, authorization failures, missing records, validation errors, and server errors.
- Convert technical errors into understandable application errors where appropriate.
- Do not expose stack traces, database errors, credentials, tokens, or confidential data.
- Avoid duplicate API methods for the same operation.
- Do not silently change return types or response structures.
- Do not report success until the server confirms success.

---

# State Management

Follow the project's existing state-management approach.

- Do not introduce another state-management framework without approval.
- Keep loading, refreshing, empty, success, and error states clear.
- Prevent duplicate API requests.
- Prevent duplicate submissions caused by repeated taps or clicks.
- Preserve valid existing state when a request fails.
- Notify or rebuild consumers only when state meaningfully changes.
- Dispose resources owned by the state layer correctly.
- Check all screens and components that depend on shared state before changing provider/controller behavior.
- Do not put large business rules directly inside state-management classes.

---

# UI and Components

- Reuse existing components before creating new ones.
- Keep components focused and reusable.
- Pass required data and callbacks through clear interfaces.
- Keep business logic out of rendering/build methods.
- Avoid direct API calls from UI components.
- Preserve loading, empty, error, refreshing, and success states.
- Avoid unnecessary rebuilds or rerenders.
- Dispose controllers, streams, subscriptions, focus objects, timers, and animation resources when required.
- Guard asynchronous UI updates against disposed/unmounted components where appropriate.
- Preserve the existing design system unless a redesign is requested.

---

# Navigation and Routing

- Reuse the project's existing routing system.
- Search for an existing route before creating a new one.
- Avoid duplicate routes that open the same destination.
- Validate route arguments.
- Handle missing, deleted, archived, or inaccessible resources safely.
- Do not allow navigation to restricted screens or resources.
- Do not rely on route parameters as a security mechanism.
- Authorization must still be enforced by the backend or authoritative security layer.

---

# Security and Permissions

Security must not depend only on the frontend.

- Reuse existing role and permission definitions.
- Do not hardcode role or permission strings throughout the UI.
- Do not create frontend-only permissions that imply real authorization.
- Centralize permission decisions where the project architecture supports it.
- Distinguish between viewing a resource and performing an action.
- Check resource-level access, not only general user roles.
- Do not expose restricted information through lists, search results, dashboards, notifications, previews, navigation, URLs, logs, or error messages.
- Hiding a button is not authorization.
- Never store passwords, secrets, access tokens, or private keys in source code.
- Do not log confidential information unnecessarily.
- Backend authentication and authorization remain authoritative.

---

# Business Rules and Workflows

Before changing a workflow or business rule, inspect:

- Existing status definitions
- Existing action definitions
- Workflow/domain models
- Workflow services
- Validation logic
- API documentation
- Database/schema documentation
- All UI consumers

Rules:

- Follow only existing statuses, actions, and transitions unless the feature explicitly requires a new one.
- Do not invent business states or transitions.
- Validate every transition.
- Do not skip required steps.
- Prevent duplicate actions.
- Preserve history and audit information.
- Preserve timestamps and responsible actors.
- Do not report success before authoritative confirmation.
- Refresh affected state after successful operations.
- Preserve the previous valid state after failures.
- Keep authoritative business rules on the backend when applicable.

---

# History and Auditability

Important actions should remain traceable when the application requires auditability.

- Never overwrite historical records to represent a new action.
- Preserve actor, action, timestamp, resource identifier, and relevant remarks when supported.
- Do not fabricate history before authoritative confirmation.
- Keep history ordering consistent.
- Handle missing actor or related data safely.
- Do not expose audit information to unauthorized users.

---

# Resource Visibility

When a resource is restricted, make sure the restriction applies consistently.

A restricted resource must not accidentally appear through:

- Dashboards
- Search results
- Lists
- Notifications
- Direct navigation
- History
- Attachments
- Previews
- Related or summary screens

Do not assume that hiding one UI element makes the resource secure.

---

# File and Attachment Handling

When the project handles uploaded or downloadable files:

- Handle missing, invalid, expired, deleted, or inaccessible files.
- Show progress when supported.
- Show understandable errors.
- Do not expose physical server paths.
- Do not trust file extensions alone.
- Respect backend file type, size, MIME type, and permission rules.
- Preserve compatibility across supported platforms.
- Prevent duplicate uploads where appropriate.
- Do not report upload success until the backend confirms it.
- Clear temporary upload state after failures.
- Do not log file contents or confidential filenames unnecessarily.

---

# Notifications

- Prevent duplicate notifications.
- Preserve notification ordering when meaningful.
- Maintain accurate unread/read state.
- Mark notifications as read only after the intended operation succeeds.
- Do not open inaccessible resources from notifications.
- Handle deleted, archived, missing, or restricted resources safely.
- Refresh notification state after successful updates.
- Do not expose confidential information in notification previews.
- Preserve local state when notification updates fail.

---

# Dates, Times, Deadlines, and Timers

- Follow the project's existing timezone strategy.
- Treat authoritative backend timestamps as the source of truth when applicable.
- Convert timestamps only for display.
- Do not store formatted display strings as authoritative dates.
- Handle nullable timestamps safely.
- Do not assume the device timezone matches the organization's timezone.
- Use timestamp comparisons for deadlines and time-based logic.
- Avoid comparing formatted date strings.
- Dispose timers and listeners correctly.
- Avoid rebuilding entire screens unnecessarily for every timer tick.
- Do not invent deadlines or escalation rules.

---

# Error Handling

Every operation should consider applicable states such as:

- Initial loading
- Refreshing
- Empty data
- Network failure
- Timeout
- Offline state
- Validation failure
- Unauthenticated request
- Forbidden action
- Missing resource
- Invalid status
- Invalid action
- Duplicate request
- File/attachment failure
- Invalid backend response
- Unexpected null values
- Partial data
- Server failure

Rules:

- Show understandable user-facing messages.
- Do not show stack traces, SQL errors, raw exceptions, credentials, or internal paths.
- Do not silently ignore failures.
- Preserve previous valid state when an operation fails.
- Do not report success before confirmation.
- Avoid infinite retry loops.
- Log enough information for debugging without exposing secrets or confidential content.
- Reuse existing error UI components where available.

---

# Responsive Design and Accessibility

- Reuse existing responsive layout components.
- Test supported screen sizes.
- Avoid fixed widths that can overflow.
- Avoid deeply nested scrolling areas.
- Keep dialogs, tables, forms, lists, and panels usable on smaller screens.
- Keep touch targets sufficiently usable.
- Prevent clipping of important names, titles, statuses, and actions.
- Use wrapping, truncation, and adaptive layouts appropriately.
- Keep important actions accessible.
- Preserve readability and accessibility.
- Do not sacrifice usability for visual decoration.

---

# Platform Compatibility

When the project supports multiple platforms:

- Preserve platform-specific implementations.
- Do not import platform-specific packages into incompatible targets.
- Preserve conditional imports where used.
- Test relevant platforms when making platform-sensitive changes.
- Do not assume behavior is identical across mobile, desktop, and web.

---

# Backend and Database Awareness

If the feature depends on backend or database behavior:

- Clearly identify when backend or database changes are required.
- Do not fake authoritative backend behavior using client-only state.
- Do not store authoritative permissions, workflows, routing, or audit data only on the client.
- Do not invent database tables or columns.
- Keep frontend requests aligned with the actual backend contract.
- Treat authoritative backend responses as the final source of truth.

Do not place backend code, migrations, or database logic in a frontend-only directory unless the project explicitly combines them there.

---

# Testing Priorities

Add or update tests when the project has an existing testing setup.

Prioritize:

- Model serialization and parsing
- API/DTO parsing
- State transitions
- Repository error handling
- Permission evaluation
- Resource visibility
- Business-rule validation
- Valid and invalid transitions
- Duplicate actions
- Notifications
- File handling
- Deadline and timer logic
- Loading, empty, success, and error states
- Responsive layouts
- Role-based access differences

Do not delete or weaken tests just to make a change pass.

When automated tests are unavailable, provide exact manual testing steps.

---

# Required Checks

After making changes, run the project's available checks, such as:

```text
Formatter
Static analysis / lint
Unit tests
Integration tests
Build
Relevant platform checks
```

Do not claim that a check passed unless it was actually run.

If unrelated existing failures are present, clearly separate them from failures introduced by the change.

---

# Debugging Procedure

When fixing a bug:

1. Reproduce or trace the issue.
2. Identify the affected layer.
3. Find the root cause.
4. Explain why the issue occurs.
5. Check related security, permission, workflow, and data behavior.
6. Fix the cause instead of hiding the symptom.
7. Avoid speculative changes.
8. Test both success and failure paths.
9. Test relevant platforms and screen sizes.
10. Review the final diff for unrelated changes.
11. Report remaining assumptions, risks, or limitations.

---

# Dependency Rules

- Do not add a dependency when an existing project dependency can solve the problem.
- Do not replace frameworks or libraries without approval.
- Check compatibility before adding or upgrading dependencies.
- Keep dependency changes minimal.
- Do not add packages solely for a small convenience when the functionality can reasonably be implemented with existing tools.

---

# Git Safety

- Do not force-push.
- Do not reset, discard, overwrite, or delete uncommitted work without explicit approval.
- Do not run destructive Git commands unless explicitly requested.
- Do not modify unrelated files.
- Do not commit secrets, generated builds, dependency folders, or editor-specific files unless the project explicitly requires them.
- Review the diff before completing a task.
- Do not automatically commit changes unless requested.
- Do not rewrite branch history.

---

# Changes Outside the Current Module

Do not modify unrelated modules or directories unless integration genuinely requires it.

Before making an external change:

1. Explain why it is necessary.
2. Confirm that no local solution exists.
3. Make the smallest external change.
4. Avoid changing unrelated behavior.
5. List every external file changed.

---

# Final Response Format

After completing a development task, report:

1. **Root cause or requested feature**
2. **Files changed**
3. **What was implemented**
4. **API impact**
5. **Backend or database impact**
6. **Permission and security impact**
7. **Formatting, analysis, and tests performed**
8. **Manual testing steps**
9. **Remaining assumptions, risks, or limitations**

Keep the final explanation focused on the requested task.

---

# Important Rules for AI Coding Agents

- Do not guess when the repository already contains the answer.
- Inspect existing code before creating new patterns.
- Do not invent APIs, schemas, roles, permissions, workflows, statuses, or business behavior.
- Ask for clarification when a required requirement cannot be determined safely from the project.
- Prefer a small correct change over a large rewrite.
- Preserve existing behavior unless the request explicitly changes it.
- Never hide errors just to make the UI appear successful.
- Never weaken security to make a feature easier to access.
- Never claim tests or commands were run when they were not.
- Always review the final changes for accidental unrelated modifications.
