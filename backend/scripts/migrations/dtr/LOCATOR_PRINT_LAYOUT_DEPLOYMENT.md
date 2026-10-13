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

Each save appends a template version. Filed requests retain their original
layout and background during approval, correction, and resubmission. Saving
a layout does not redesign already filed forms.

Local migration applied to `localhost:5433/hrms_plaridel` after a validated
PostgreSQL backup. Five types, 17 requests, and six prior template versions
were preserved. Backup:
`.backups/20261013-locator-print-layout-1791881528297/before-migration.dump`.
Production deployment has not been performed.
