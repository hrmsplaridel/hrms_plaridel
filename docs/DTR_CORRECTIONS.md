# Employee DTR correction requests — removed

The request workflow was removed at the client's request. HR continues to edit attendance through authorized Time Logs tools.

The frontend no longer includes employee request forms/history, reviewer queues/settings or the access toggle. Request notifications and DocuTracker correction sources were removed. `/api/dtr-corrections` is no longer mounted and returns the API's normal not-found response.

Fresh installs no longer create correction request, attachment or reviewer tables or `corrections_allowed`. Existing databases require `backend/scripts/migrations/dtr/20261007_remove_dtr_correction_requests.sql` after previous migrations. It deletes the three workflow tables, permission column and correction notifications. Direct attendance, biometric records and generic audit history are retained.

Applied locally to `localhost:5433/hrms_plaridel`. Verified backup: `backend/.backups/before-remove-dtr-requests-20261007.dump`. The migration was also tested twice in an isolated schema. Server application is still required if deploying there: update code, apply the cleanup migration with errors stopping execution, then restart the API and rebuild/deploy the frontend.

Earlier migration files remain historical. Do not rerun retired correction migrations after this cleanup.

Regression checks: `node --test test/dtrCorrectionSchemaRemoval.test.js test/dtrAdminAccess.test.js test/dtrDailySummaryAccess.test.js`.
