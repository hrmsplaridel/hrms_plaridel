# Notifications architecture (Option B)

## Global bell (header + View All)

- **Storage:** PostgreSQL `user_notifications`
- **API:** `GET/PATCH/POST /api/notifications`
- **Flutter:** `NotificationProvider`, `dashboard_notifications_dropdown.dart`
- **Modules today:** leave, locator, recruitment, training daily reports, overtime
- **Not included:** DocuTracker (separate channel until the module is stable)

## DocuTracker (in-module only)

- **Storage:** `docutracker_notifications`
- **API:** `GET/PATCH /api/docutracker/notifications`
- **Flutter:** `DocuTrackerProvider` + `DocuTrackerNotificationsPanel` on the DocuTracker dashboard
- **Do not** insert DocuTracker rows into `user_notifications` without an explicit migration plan.

## Adding a new HRMS module to the bell

1. On the backend, call `insertNotification` / `insertNotificationForUsers` from `notificationService.js`.
2. Use a distinct `category` and `type` (not `docutracker`).
3. Extend `NotificationTapResult` and dashboard `_applyNotificationTapResult` for deep links.
