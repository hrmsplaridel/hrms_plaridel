# Position & DTR Reference (HRMS)

Quick reference for **Position** functionalities and **DTR (Daily Time Record)** inputs used in the HRMS.

---

## Position – Functionality & Inputs

**Screen:** Admin → DTR Manage → **Position** (`lib/dtr/manage/manage_position.dart`)

**Table:** `positions` (Supabase) / backend `positions` (Node API)

### Functionality

| Action         | Description                                                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **List**       | View positions with search (name, description, department), filter by **Department** and **Status** (Active / Inactive / All). |
| **Add**        | Create a new position with required **Position Title** and optional Department and Description.                                |
| **Update**     | Select a position from the list, edit Title / Department / Description, then Update.                                           |
| **Deactivate** | Soft-deactivate a position (sets `is_active = false`); it no longer appears in active lists.                                   |

### Required & Optional Inputs

| Field                            | Required | Type                    | Notes                                         |
| -------------------------------- | -------- | ----------------------- | --------------------------------------------- |
| **Position Title** (`name`)      | Yes      | Text                    | Display name of the position.                 |
| **Department** (`department_id`) | No       | UUID (FK → departments) | Optional link to a department.                |
| **Description** (`description`)  | No       | Text                    | Optional notes.                               |
| **Is Active** (`is_active`)      | No       | Boolean                 | Default `true`; set to `false` on Deactivate. |

---

## DTR – Inputs Needed for an HRMS

DTR in this app uses **Supabase `time_records`** (and optionally the backend schema’s `dtr_logs` / `dtr_daily_summary`). Below are the inputs that matter for a typical HRMS DTR flow.

### 1. Per-record inputs (Supabase `time_records` / app `TimeRecord`)

Used when recording or editing a single day’s attendance:

| Field           | Required | Type      | Notes                                                   |
| --------------- | -------- | --------- | ------------------------------------------------------- |
| **user_id**     | Yes      | UUID      | Employee (references `profiles.id` in Supabase).        |
| **record_date** | Yes      | Date      | Day of the DTR entry.                                   |
| **time_in**     | No       | Timestamp | Clock-in time.                                          |
| **time_out**    | No       | Timestamp | Clock-out time.                                         |
| **total_hours** | No       | Numeric   | Rendered hours (can be computed from time_in/time_out). |
| **status**      | No       | Text      | `present` \| `late` \| `absent` \| `on_leave`.          |
| **remarks**     | No       | Text      | Free-text notes.                                        |

### 2. Master data that DTR depends on (HRMS setup)

These are needed so DTR can be assigned, reported, and validated correctly:

| Entity                         | Purpose for DTR                                                                                       |
| ------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **Employees (users/profiles)** | Who is clocking in; whose records to show.                                                            |
| **Departments**                | Filter/report DTR by department (via assignment).                                                     |
| **Positions**                  | Filter/report by position; shown in DTR/leave forms (e.g. position title).                            |
| **Shifts**                     | Expected start/end and grace period; used to compute late/undertime (in backend `dtr_daily_summary`). |
| **Assignments**                | Links employee ↔ department, position, shift; defines which shift/position applies on a date.         |

### Assignment – Start Time & End Time

On **Manage Assignment**, **Start Time** and **End Time** define the **exact work window** for that assignment:

- **Purpose:** They record the scheduled start and end of the work period for this employee for this assignment. They are used for:
  - **DTR and payroll:** Knowing expected hours and comparing with actual clock-in/out to compute late, undertime, or overtime.
  - **Overrides:** Even when a **Shift** is selected (e.g. “Morning Shift”), you can set different times for this specific assignment (e.g. 9:00–18:00 instead of the shift’s default 8:00–17:00).
- **With Shift:** The **Shift** dropdown gives the shift name and its default times; Start/End Time on the assignment can match that shift or override it for this assignment only.

### 3. Backend schema (optional / future): `dtr_logs`, `dtr_daily_summary`, `dtr_corrections`

- **dtr_logs:** Raw logs (e.g. biometric/manual) – `employee_id`, `log_time`, `log_type` (`time_in`/`time_out`/`break_in`/`break_out`), `source`, etc.
- **dtr_daily_summary:** One row per employee per day – `employee_id`, `attendance_date`, `shift_id`, `time_in`, `time_out`, `break_in`, `break_out`, `late_minutes`, `undertime_minutes`, `total_hours`, `status`, `remarks`.
- **dtr_corrections:** Correction requests – `employee_id`, `attendance_date`, requested times, `reason`, `status` (pending/approved/rejected).

For the **current Flutter app**, the main DTR inputs you work with are: **Employee (user_id)**, **Date**, **Time In**, **Time Out**, **Status**, and **Remarks**; Position and Department come from assignments/master data for display and filtering.
