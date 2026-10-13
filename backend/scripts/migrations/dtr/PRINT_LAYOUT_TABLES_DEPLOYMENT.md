# Printed form tables

The shared locator and leave printed form editor now supports **Insert table**.

No additional table migration is required. The existing `20261013_locator_print_layouts.sql` and `20261013_leave_print_layouts.sql` upgrades store complete layouts as JSON, including tables. Deploy the matching backend and rebuild the Flutter frontend together.

Select the table on the page to change its dimensions, rows, columns, headers, borders, column widths and cell content. Choose **Fixed text** or **Request field** for each cell. Tables support 1-12 rows, 1-6 columns and up to 500 characters per fixed-text cell. Long values continue on another page. Request fields placed in table cells count as placed fields, so short custom answers do not create duplicate continuation pages.

Use **Use layout**, then create/save the type or save its print settings. Saving appends a template version; submitted forms keep their original version. Existing templates do not gain tables automatically.

## Create a field in the designer

For editable locator and leave types, choose **Insert field → Create new field**. Set its label, input type and whether it is required; select fields also need choices. Creating it places the field on the page and adds it to the insertion menu, including table cell bindings. Drag it to the desired position.

Choose **Use layout** to carry the field back to the type's additional/custom form fields, then **Create Type**, **Create Leave Type**, or **Save Changes**. The type's field definition is saved before its print layout so employees can fill in the new field. Standalone **Save print settings** is disabled while a designer-created field still needs its type saved. If the layout save fails after the type succeeds, retry saving the print settings without creating another field.

Cancelling the designer discards fields created in that session. Preview uses the staged fields without saving the type. The existing limits apply: 20 additional fields, six input types, labels up to 80 characters, and up to 20 select choices of 80 characters each. Existing request snapshots and templates stay unchanged. No additional migration is required.

## Paper, margins and fonts

The same page settings are available in locator and leave custom layouts:

- A4 (210 × 297 mm), Letter (8.5 × 11 in), Long Bond (8.5 × 13 in), and Legal (8.5 × 14 in), in portrait or landscape.
- Separate top, right, bottom and left margins, entered in millimetres. The margin guides constrain field placement; changing the page or margins fits existing elements into the usable area. Guides do not print.
- Default font family and a 6–72 point default size for new elements. Select an element to override its font family or size. Noto Sans, Noto Serif and Noto Sans Mono are bundled with regular and bold faces, so printing does not need a font download.

The background must have the same paper size and orientation as the layout. Standard CSC and Wellness leave layouts still require portrait A4. Large answers continue on the selected paper; historic templates without page settings retain their existing rendering.

These settings use the existing JSON layout columns; no further migration is needed. Deploy the backend and rebuild the Flutter frontend together. Restart the Flutter development app after the asset/font manifest changes.
