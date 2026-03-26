require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { pool } = require('./config/db');

const authRoutes = require('./routes/auth');
const departmentsRoutes = require('./routes/departments');
const positionsRoutes = require('./routes/positions');
const shiftsRoutes = require('./routes/shifts');
const assignmentsRoutes = require('./routes/assignments');
const employeesRoutes = require('./routes/employees');
const uploadRoutes = require('./routes/upload');
const filesRoutes = require('./routes/files');
const holidaysRoutes = require('./routes/holidays');
const attendancePoliciesRoutes = require('./routes/attendancePolicies');
const dtrCorrectionsRoutes = require('./routes/dtrCorrections');
const biometricDevicesRoutes = require('./routes/biometricDevices');
const biometricAttendanceLogsRoutes = require('./routes/biometricAttendanceLogs');
const overtimeRoutes = require('./routes/overtime');
const calendarRoutes = require('./routes/calendar');
const dtrDailySummaryRoutes = require('./routes/dtrDailySummary');
const docutrackerRoutes = require('./routes/docutracker');
<<<<<<< HEAD
const trainingDailyReportsRoutes = require('./routes/trainingDailyReports');
const rspJobVacanciesRoutes = require('./routes/rspJobVacancies');
const rspExamQuestionsRoutes = require('./routes/rspExamQuestions');
const rspApplicationsRoutes = require('./routes/rspApplications');
const rspStorageRoutes = require('./routes/rspStorage');
=======
const leaveRoutes = require('./routes/leaveRoutes');
>>>>>>> feature/dtr-module

const app = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0'; // 0.0.0.0 = accessible from LAN

if (!process.env.JWT_SECRET) {
  console.warn('[warn] JWT_SECRET not set; auth routes will fail. Add JWT_SECRET to .env');
}

if (
  !process.env.SUPABASE_URL?.trim() ||
  !process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
) {
  console.warn(
    '[warn] Supabase storage not configured. RSP files still work from disk at uploads/rsp-attachments/ (see POST /api/rsp/applications/:id/attachment-file). Set SUPABASE_* for cloud bucket.',
  );
}

// Middleware
app.use(cors());
app.use(express.json());

// --- Routes ---

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, message: 'HRMS API is running' });
});

app.get('/health/db', async (_req, res) => {
  try {
    const result = await pool.query(
      `SELECT
        1 AS ok,
        current_database() AS db,
        inet_server_addr()::text AS server_addr,
        inet_server_port() AS server_port,
        current_user AS db_user`
    );
    res.json({
      ok: true,
      database: result.rows[0].db,
      server_addr: result.rows[0].server_addr,
      server_port: result.rows[0].server_port,
      db_user: result.rows[0].db_user,
      message: 'PostgreSQL connection OK',
    });
  } catch (err) {
    console.error('[health/db]', err.message);
    res.status(503).json({
      ok: false,
      error: err.message,
      message: 'PostgreSQL connection failed',
    });
  }
});

// API routes
app.use('/auth', authRoutes);
app.use('/api/departments', departmentsRoutes);
app.use('/api/positions', positionsRoutes);
app.use('/api/shifts', shiftsRoutes);
app.use('/api/assignments', assignmentsRoutes);
app.use('/api/employees', employeesRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/files', filesRoutes);
app.use('/api/holidays', holidaysRoutes);
app.use('/api/attendance-policies', attendancePoliciesRoutes);
app.use('/api/dtr-corrections', dtrCorrectionsRoutes);
app.use('/api/biometric-devices', biometricDevicesRoutes);
app.use('/api/biometric-attendance-logs', biometricAttendanceLogsRoutes);
app.use('/api/overtime', overtimeRoutes);
app.use('/api/calendar', calendarRoutes);
app.use('/api/dtr-daily-summary', dtrDailySummaryRoutes);
app.use('/api/docutracker', docutrackerRoutes);
<<<<<<< HEAD
app.use('/api/training-daily-reports', trainingDailyReportsRoutes);
app.use('/api/rsp/job-vacancies', rspJobVacanciesRoutes);
app.use('/api/rsp/exam-questions', rspExamQuestionsRoutes);
app.use('/api/rsp/applications', rspApplicationsRoutes);
app.use('/api/rsp/storage', rspStorageRoutes);
=======
app.use('/api/leave', leaveRoutes);
>>>>>>> feature/dtr-module

// --- Start server ---
app.listen(PORT, HOST, () => {
  console.log(`HRMS API listening on http://${HOST}:${PORT}`);
  console.log('  GET  /health           - app health');
  console.log('  GET  /health/db        - database health');
  console.log('  POST /auth/login       - login');
  console.log('  POST /auth/register    - register');
  console.log('  GET  /auth/me          - current user (requires JWT)');
  console.log('  API  /api/departments  /api/positions  /api/shifts');
  console.log('  API  /api/assignments  /api/employees');
  console.log('  POST /api/upload/avatar  GET /api/files/avatar/:userId');
  console.log('  PUT  /api/rsp/job-vacancies  - update landing page hirings');
  console.log('  PUT  /api/rsp/exam-questions/:examType - admin save exam questions');
  console.log('  DELETE /api/rsp/applications/:applicationId - admin delete applicant');
  console.log('  GET  /api/rsp/storage/view-token - admin token for /api/files/recruitment-attachment');
  console.log('  GET  /api/rsp/storage/signed-url - admin signed attachment URL (service role)');
});
