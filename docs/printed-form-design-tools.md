# Printed form design tools

The existing **Printed form layout** designer now supports these tools for both **Leave and Locator**. DocuTracker's template editor is separate and is unchanged.

## Use the tools

- **Rectangle**: add an empty section box. Set its border sides, width, color, solid/dashed style, and fill in **Element properties → Borders and fill**. These settings also work on text, fields, signatures, and lines. Tables retain their grid settings; the additional controls apply to the table's outer border and fill.
- **Colors**: choose a swatch or enter a six-digit color such as `#000000`. Leave fill blank, or use **No fill**, for transparency. Thick lines automatically get enough element height to contain the stroke.
- **Select several**: drag with the mouse on an empty part of the white page to draw a selection box. Fully enclosed elements are selected when you release. Hold Ctrl/Command or Shift to add the box selection to the existing selection; Ctrl/Command-click or Shift-click an element to toggle it. Escape cancels an active selection box, and clicking empty page space clears the selection. Grouped elements are selected together, and locks remain respected. On mobile, open **Page and element settings**, scroll to **Layers**, and use the checkboxes. Mouse box selection does not replace touch scrolling or print on the form.
- **Arrange → Align**: align several elements to their selection bounds. A single element or group aligns to the usable page area.
- **Arrange → Space evenly**: distribute at least three elements/groups horizontally or vertically. The available span must fit the elements; the tool does not resize them.
- **Group selection**: select related items and group them. Drag any member to move the group while retaining spacing. Groups align and distribute as units. Ungroup before resizing individual members; nested groups are not created.
- **Bring to front / Bring forward / Send backward / Send to back**: change the saved back-to-front print order. Relative order within the selection is preserved. Select covered elements through **Layers**, which lists frontmost elements first.
- **Lock selection**: prevent accidental moving, resizing, editing, or deletion. Locked items remain selectable through the canvas or layer list. Use **Unlock selection** or the layer lock icon to edit them again.
- **Undo/Redo**: supports appearance changes, group movement, grouping, locking, and layer changes. Existing text-field shortcuts keep their normal behavior.

For section headings, add text, give it a light fill, and enable a bottom border. For a framed section, place a rectangle behind its labels and fields using **Send to back**. Group the related elements afterward.

## Save and print

Preview uses the same decoration renderer as generated Leave and Locator PDFs. Selection outlines, resize handles, locks, and group identifiers do not print. Only configured borders/fills and content print, in the saved layer order.

**Use layout** applies the draft to the calling form. Save the type or print settings to persist it. Opening a designer does not rewrite an existing template. Existing layouts keep their appearance until edited; omitted decoration, lock, and grouping values retain the previous defaults.

No database migration is required. The existing layout JSON stores the new settings; the shared backend validator validates and preserves them. Deploy the backend update along with the rebuilt frontend before saving layouts containing rectangles or decorations.

## Verification

- `cd backend; npm run test:print-layout`: both layout validators, print-template endpoints, and type management regressions.
- Flutter model/PDF tests cover serialization, border validation, layer order, grouping, alignment, distribution, movement bounds, locks, and unchanged page geometry.
- Widget tests cover the controls, pending property validation, thick lines, group dragging, undo, mobile layer selection, and existing field/signature behavior.
- Screenshot tests cover desktop, dark mode, mobile, settings, tables, page sizes, and a decorated form.

## Complete change inventory (20 files)

Backend:

1. `backend/package.json`
2. `backend/src/services/locatorPrintLayout.js`
3. `backend/test/printLayoutDesignTools.test.js`

Shared Leave/Locator designer and PDF output:

4. `frontend/lib/features/dtr/locator/models/locator_print_layout.dart`
5. `frontend/lib/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart`
6. `frontend/lib/features/dtr/locator/presentation/admin/widgets/print_layout_design_controls.dart`
7. `frontend/lib/features/dtr/locator/utils/locator_layout_pdf.dart`
8. `frontend/lib/features/dtr/locator/utils/print_layout_decoration.dart`
9. `frontend/lib/features/dtr/locator/utils/print_layout_editing.dart`

Tests, screenshots, and documentation:

10. `frontend/test/dtr/locator/print_layout_design_tools_test.dart`
11. `frontend/test/dtr/locator/print_layout_design_editor_test.dart`
12. `frontend/test/dtr/locator/locator_print_layout_editor_golden_test.dart`
13. `frontend/test/dtr/locator/goldens/locator_print_editor_boxes.png`
14. `frontend/test/dtr/locator/goldens/locator_print_editor_desktop.png`
15. `frontend/test/dtr/locator/goldens/locator_print_editor_dark.png`
16. `frontend/test/dtr/locator/goldens/locator_print_editor_mobile.png`
17. `frontend/test/dtr/locator/goldens/locator_print_editor_mobile_settings.png`
18. `frontend/test/dtr/locator/goldens/locator_print_editor_page_settings.png`
19. `frontend/test/dtr/locator/goldens/locator_print_editor_table.png`
20. `docs/printed-form-design-tools.md`
