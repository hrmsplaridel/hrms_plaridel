## DTR Module – Current User Flow & Permissions

This document summarizes how the existing DTR (Daily Time Record) module works today, based on the Flutter frontend code and current schema. It focuses on **actual behavior**, not the ideal target workflow.

---

## 1. Roles and Entry Points

- **Roles recognized in the app:**
  - `admin`
  - `employee`
- Determined from `AppUser.role` and used in `main.dart`:
  - `admin` → `AdminDashboard`
  - any other role (or null) → `EmployeeDashboard`
- There is **no separate `supervisor` or `hr` role** in the DTR front‑end logic. HR functionality is effectively bundled into the `admin` dashboard.

---

## 2. Employee Flow

### 2.1 Screens & Navigation

From `EmployeeDashboard` sidebar:

- `Dashboard`
- `My Attendance`
- `My Leave`
- `DocuTracker`
- `Announcements` (placeholder)

### 2.2 Capabilities

- **View own attendance logs**
  - Screen: `_EmployeeAttendanceContent` (`employee_dashboard.dart`)
  - Uses `DtrProvider.loadTimeRecordsForUser(startDate, endDate)` scoped to the logged‑in user ID.
  - Filters: month, year, specific day, “Today”.
  - Behavior: **read‑only** view of the user’s own `time_records`.

- **View monthly DTR / generate PDF**
  - There is **no employee UI** hooked to `DtrExport.generatePdf`.
  - DTR PDF/Excel/Word export is only wired into the **admin** DTR Reports screen.

- **Request attendance corrections**
  - There is an admin screen for reviewing correction requests (`ManageAttendanceAdjustment`), which calls:
    - `GET /api/dtr-corrections?status=...`
    - `PATCH /api/dtr-corrections/{id}/review`
  - The Flutter codebase **does not contain an employee‑side form** to create a correction request (no POST to `/api/dtr-corrections`), so employees cannot initiate corrections from this UI.

- **Request leave**
  - Screen: `LeaveMain(isAdmin: false)` → `EmployeeLeaveScreen` + `LeaveRequestFormScreen`.
  - Employees can:
    - File new leave requests (draft + submit).
    - View their own leave requests and balances.

---

## 3. Admin / HR Flow (DTR & Leave)

In practice, **admin == HR** for the DTR and leave modules.

### 3.1 DTR Hub (AdminDashboard → _DtrContent)

Feature cards available to admin in the DTR hub:

- `Time Logs`
- `Reports`
- `Employees`
- `Assignment`
- `Department`
- `Position`
- `Shift`
- `Leave Management`
- `Holiday Management`
- `Attendance Policy`
- `Attendance Adjustment`

Routing:

- `Time Logs` → `DtrMain(section: timeLogs)` → `DtrTimeLogs`
- `Reports` → `DtrMain(section: reports)` → `DtrReports`
- `Leave Management` → `LeaveMain(isAdmin: true)`
- Other cards go through `_ManageContent` to various manage_* screens.

### 3.2 Capabilities

- **View all employee attendance**
  - Screen: `DtrTimeLogs`
  - Calls `DtrProvider.loadTimeRecordsForAdmin(startDate, endDate, userId?, departmentId?, limit?)`.
  - Filters: employee, department, date range.
  - Admin can see attendance for any employee or department.

- **Edit / adjust attendance records**
  - `DtrTimeLogs` is designed as a CRUD interface for `time_records`:
    - “Manage and correct daily time-in/out records. Add, edit, or delete entries.”
  - Details of the edit dialogs are implemented in `dtr_time_logs.dart` (admin context only).

- **Generate DTR reports**
  - Screen: `DtrReports`.
  - Uses:
    - `DtrExport.generatePdf(...)`
    - `DtrExport.generateExcel(...)`
    - `DtrExport.generateWordHtml(...)`
  - Admin can:
    - Choose period, department, and employee.
    - Export/print DTR forms (two‑per‑page government style).

- **Review attendance corrections**
  - Screen: `ManageAttendanceAdjustment` (“Attendance Adjustment”).
  - Lists `/api/dtr-corrections` by status (`pending`, `approved`, `rejected`, `All`).
  - Admin can approve/reject individual requests with optional review notes:
    - `PATCH /api/dtr-corrections/{id}/review` with `status` and `review_notes`.
  - This is a **single‑stage approval** (no supervisor step).

- **Leave approvals**
  - From the DTR hub, `Leave Management` opens `LeaveMain(isAdmin: true)`.
  - `LeaveMain` routes to `AdminLeaveScreen` when `isAdmin == true`.
  - Admin can review and approve/reject leave requests.

- **Manage shifts, holidays, and related data**
  - `Assignment` → `ManageAssignment` (assign employees to departments, positions, shifts with effective dates).
  - `Department`, `Position`, `Shift` → manage reference data via their respective manage_* screens.
  - `Holiday Management` → `ManageHoliday` (configure holidays used by DTR and payroll).
  - `Attendance Policy` → `ManageAttendancePolicy` (grace period, late/absent/undertime rules, etc.).
  - `Employees` → `ManageEmployee` (employee profiles, roles: admin vs employee).

---

## 4. Supervisor Flow (Current State)

- There is **no distinct `supervisor` role** or supervisor-specific UI in the DTR module.
- The only roles that drive navigation are:
  - `admin` (full DTR + HR capabilities)
  - `employee` (personal dashboard only)
- Some descriptions mention “supervisors” (e.g., in overtime text), but there is **no front‑end logic** that:
  - Limits views to “my direct reports”.
  - Implements a supervisor approval step separate from admin.

Any real‑world supervisor actions (approving time/leave for a team) would currently need to be done by users who are marked as `admin` in this system.

---

## 5. Data Relationships (Who Belongs to Whom)

- DTR/admin features rely on **departments, positions, and shifts**, managed via:
  - `ManageAssignment`
  - `ManageDepartment`
  - `ManagePosition`
  - `ManageShift`
- `ManageAssignment` links employees to:
  - `department_id`
  - `position_id`
  - `shift_id`
  - effective date ranges and override times.
- There is **no `supervisor_id` or “immediate head” mapping** used in the DTR code.
- `DtrProvider` filters attendance by:
  - `userId` (specific employee)
  - `departmentId` (department‑wide view)

Team membership for approvals is thus **department-based**, not supervisor-based, and the supervisor concept does not appear in the DTR front‑end.

---

## 6. DTR Approval / Verification Status

- `DtrSummary` has a `pendingApproval` field, but it is currently filled with `null` and treated as a placeholder; no real approval counts are surfaced.
- The **attendance correction** flow has a simple status:
  - `status`: `pending` → `approved` or `rejected` (managed via `ManageAttendanceAdjustment`).
- The **DTR PDF export** (`DtrExport.generatePdf`) does **not** depend on any approval status:
  - It renders directly from `time_records` plus some computed remarks and undertime values.
  - There is no `supervisor_verified` or `hr_verified` flag in the front‑end.

Result: the system currently supports **correction approvals**, but **not a multi‑level DTR approval chain**. The generated DTR is implicitly considered official once the underlying `time_records` are correct.

---

## 7. Comparison to Ideal Government Workflow

Target workflow: **Employee → Supervisor → HR**

| Step                    | Ideal Workflow                                              | Current Implementation                                                   |
|-------------------------|------------------------------------------------------------|---------------------------------------------------------------------------|
| Employee attendance     | Employee views logs and requests corrections/leave        | Employee views own logs; can file **leave**, but **no DTR correction UI** |
| Supervisor review       | Supervisor reviews and approves employee corrections/leave | **Not implemented** as a distinct role or UI                              |
| HR/Personnel review     | HR verifies final records, manages shifts/holidays         | Admin (HR) can edit logs, approve corrections, manage shifts/holidays     |
| DTR approval status     | DTR may carry supervisor/HR verification indicators        | DTR PDF has no explicit approval states; uses current `time_records` only |

In short:

- The current system implements a **centralized HR/admin‑driven process** for DTR and leave.
- It **does not yet implement a separated Employee → Supervisor → HR chain**:
  - No supervisor role.
  - No employee DTR correction form.
  - No per‑team supervisor dashboards or staged approvals.
  - No explicit approval flags on DTR exports.

This is important context for planning future enhancements toward a more formal, government‑style DTR workflow.

