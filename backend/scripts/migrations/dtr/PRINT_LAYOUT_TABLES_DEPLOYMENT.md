# Printed form tables

The shared locator and leave printed form editor now supports **Insert table**.

No additional table migration is required. The existing `20261013_locator_print_layouts.sql` and `20261013_leave_print_layouts.sql` upgrades store complete layouts as JSON, including tables. Deploy the matching backend and rebuild the Flutter frontend together.

Select the table on the page to change its dimensions, rows, columns, headers, borders, column widths and cell content. Choose **Fixed text** or **Request field** for each cell. Tables support 1-12 rows, 1-6 columns and up to 500 characters per fixed-text cell. Long values continue on another page. Request fields placed in table cells count as placed fields, so short custom answers do not create duplicate continuation pages.

Use **Use layout**, then create/save the type or save its print settings. Saving appends a template version; submitted forms keep their original version. Existing templates do not gain tables automatically.
