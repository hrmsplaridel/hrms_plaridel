# Locator approval routing

Apply `20261013_locator_approval_routing.sql` to the target database after taking a backup, then deploy the backend and restart its existing service. Rebuild and deploy the Flutter web application for the UI changes.

Existing locator types and requests retain normal HR routing. Change a type deliberately to enable one of these routes:

- Department review → Final HR (existing behavior).
- Department approval → manual Mayor signing. Department approval completes the system decision; the employee must obtain the Mayor signature on paper.
- Direct Mayor approval in the app. Requests remain `pending_mayor` until the active Mayor signs and approves or rejects them. The Mayor portal provides Locator approvals.

Mayor routes can be restricted to employment types; other employment types follow normal HR routing. HR auto-approval cannot be combined with either Mayor route. An active Mayor account is required; no account or reviewer assignments are created by this migration.

Request routing is saved at submission. Later type changes do not reroute existing requests. Returned requests are re-evaluated when the employee corrects and resubmits them.

If the Mayor account is replaced, deactivate the previous Mayor before activating the replacement; the single-active-Mayor rule still applies. For an existing pending direct-Mayor request, the current Mayor's valid signing/approval transaction updates the saved final reviewer and printed Mayor identity together and records a `mayor_reassigned` history event. Approval may also use that Mayor's already saved signature on the current request revision. Missing or invalid signatures do not trigger reassignment. Reads/previews and already approved forms retain their saved identities and signatures. This handover behavior uses the existing schema and requires no additional migration; deploy the updated backend and restart its existing service.

Rollback requires checking for any newly submitted Mayor requests before removing the new columns or restoring the old status constraint. Do not roll back code alone while those requests remain pending.
