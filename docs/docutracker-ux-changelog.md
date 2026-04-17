# DocuTracker UX Before/After Changelog

## Scope

This changelog summarizes the user experience improvements applied to the DocuTracker module UI.

## Before

- Admin mixed workflow and access controls in one long panel.
- Multiple permission edit entry points created confusion (row edit + side action).
- Filters included redundant controls and unclear flow.
- Permission names used technical/internal wording.
- Access editing lacked bulk actions and clear unsaved-state feedback.
- Empty states were generic and did not react to active filters.
- Detail screen actions lacked clear grouping and no-action guidance.

## After

- Admin now has clear sections:
  - `Access Control`
  - `Workflow Setup`
- Single primary permissions entry path: `Edit User Permissions`.
- Simplified filters with explicit `Clear filters`.
- Permission labels use plain language:
  - View audit trail
  - Route documents
  - Approve documents
  - Edit document details
  - Download files
  - Delete documents
- Access editor upgraded to matrix-style interaction with:
  - `Grant all`
  - `Revoke all`
  - `Reset`
  - sticky save footer and unsaved-change status
- Responsive improvements for narrow screens:
  - wrapping bulk controls
  - stacked footer actions
  - improved tap targets/tooltips
- Documents screen now distinguishes:
  - truly empty state
  - filtered-empty state with `Clear Filters`
- Detail screen now shows:
  - `Available Actions` section
  - explicit message when user has no actionable permissions
  - clearer action/dialog copy (`Add Note`, `No audit history yet`)

## Impact

- Lower cognitive load for admins configuring access.
- Faster permission editing through bulk actions.
- Fewer accidental dead-ends due to clearer empty/filter states.
- More consistent, human-readable language across DocuTracker screens.

## Latest Consistency and Restriction Updates

- Source-backed documents now respect employee-side `view` restrictions by module type.
- Missing source tables no longer crash listing; UI shows clear warning banner while available modules continue to load.
- Added clearer ownership indicators in document rows:
  - `Mine`
  - `Assigned to me`
- Added `My documents only` filter chip to reduce confusion for mixed visibility lists.
- User-facing naming was standardized from `DTR` to `Leave` where context is leave-request tracking.
- Removed redundant controls:
  - duplicate create action in empty state
  - duplicate refresh action (`Refresh now`)
- Permission cards now provide clearer readability:
  - consolidated `All types` label (removed duplicate `All (*)` wording)
  - action chips include document type context
  - summary line explains what a user can do for that type

## Files Updated

- `lib/docutracker/screens/docutracker_admin_screen.dart`
- `lib/docutracker/screens/docutracker_setup_permissions_screen.dart`
- `lib/docutracker/screens/docutracker_documents_screen.dart`
- `lib/docutracker/screens/docutracker_document_detail_screen.dart`
- `lib/docutracker/screens/docutracker_dashboard_screen.dart`
- `backend/src/services/docutrackerWorkflowService.js`
- `backend/src/routes/docutracker.js`
