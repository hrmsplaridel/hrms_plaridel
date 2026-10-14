# Locator printed form designer

Apply `20261013_locator_print_layouts.sql` before deploying the updated API.
Deploy the updated Flutter build too. Do not run the schema initializer on an
existing database.

In Locator Types → Printed Form, use **Design layout** or **Edit layout**.
Upload a PDF, PNG, or JPEG background if needed. Drag fields, additional
details, text, lines, and signature blocks onto the A4 page. Select an element
to change its label, position, width, height, font, bold style, or alignment.
Dimensions use PDF points. Use the same orientation as the background.

**Preview layout** shows sample answers without saving or creating a type.
**Use layout** keeps the draft. **Create Type**, **Save Changes**, or
**Save print settings** persists it. For an existing type, **Use default
layout** returns future requests to the original fixed Locator Slip layout.

Short answers appear in the placed boxes. Answers that exceed their boxes,
and custom answers without a placed field, appear on continuation pages.
Signature images remain request-bound and use the existing signing rules.
Placement affects printing only, not approval routing or DTR coverage.

The shared Locator/Leave designer includes **Undo** (`Ctrl+Z`), **Redo**
(`Ctrl+Y` or `Ctrl+Shift+Z`), and **Delete** for the selected page element.
Text inputs retain their normal text-editing shortcuts. History keeps up to
100 edits during the current editor session, including new fields and their
placement. Each completed move or resize is one step. Drag a selected box's
corner or edge handles to resize it within the page margins; numeric dimensions
remain available in Element properties. The zoom slider spans 25–200%, and
**Fit page** restores automatic fitting. Zoom does not change printed dimensions.
Over the page workspace, turn the mouse wheel up to zoom in or down to zoom out.
Wheel zoom preserves the point under the cursor where scroll limits allow.
Scrolling over the settings panel still scrolls that panel normally.
Zoom uses a cached page with a canvas transform. Only the workspace, rulers,
zoom controls, and selected resize handles react to zoom changes; the inspector
and page text/field widgets remain intact until the design changes.

Each save appends a template version. Filed requests retain their original
layout and background during approval, correction, and resubmission. Saving
a layout does not redesign already filed forms.

Local migration applied to `localhost:5433/hrms_plaridel` after a validated
PostgreSQL backup. Five types, 17 requests, and six prior template versions
were preserved. Backup:
`.backups/20261013-locator-print-layout-1791881528297/before-migration.dump`.
Production deployment has not been performed.
