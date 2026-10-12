# Locator printed backgrounds

For an existing database, deploy the matching backend/frontend code and apply
`20261010_locator_print_templates.sql` once. It requires the existing
`locator_request_types`, `locator_slips`, and `users` tables. It does not require
the leave print-template migration. Back up the database before deployment.
For a fresh installation, the same definitions are included in `init-schema.sql`.
Do not rerun the initializer on an existing database.

The migration adds versioned backgrounds and template pointers. Existing requests
keep a NULL template pointer and the current landscape form, without data updates. New requests
capture their locator type's template when filed. Approval, correction and
resubmission retain that original template. Changing/removing a background
creates a new version for future requests and does not delete old artwork.

In Create/Edit Locator Type, upload a single-page A4 letterhead (portrait or
landscape PDF, PNG or JPEG, up to 5 MB). Creation saves a selected background;
editing uses Save print settings. Preview saved form shows the resulting sample.
Both employee and administrator previews/printing apply the request's saved
background. Upload letterhead artwork only, not a photograph of a completed form.
The locator is fitted between fixed header/footer margins, with its aspect ratio
preserved. There is no draggable field-position editor.

Background files stored locally are not included in this migration; upload the
desired letterhead on each deployment. No background is automatically assigned
to any locator type.

Rollback before any background has been configured: restore the previous code,
drop `trg_snapshot_locator_print_template` on `locator_slips` and
`trg_initialize_locator_print_template` on `locator_request_types`, drop their
functions, drop both `print_template_version_id` columns, then drop
`locator_print_template_versions`. Once backgrounds are in use, keep a database
backup and preserve the version data rather than using this destructive rollback.
