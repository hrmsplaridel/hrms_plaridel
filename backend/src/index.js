const path = require('path');
require('dotenv').config({
  path: path.resolve(__dirname, '../.env'),
  override: true,
});
const express = require('express');
const cors = require('cors');
const { pool } = require('./config/db');
const { initWebSocket } = require('./websockets/biometricStream');
const { initAppEventsWebSocket } = require('./websockets/appEvents');
const { scheduleLeaveMonthlyAccrualCron } = require('./jobs/leaveMonthlyAccrualScheduler');
const { scheduleYearEndForcedLeaveCron } = require('./jobs/leaveYearEndForcedLeaveScheduler');
const {
  scheduleAuthRefreshTokenCleanupCron,
} = require('./jobs/authRefreshTokenCleanupScheduler');
const { generalApiLimiter } = require('./middleware/rateLimiters');

const authRoutes = require('./routes/auth');
const departmentsRoutes = require('./routes/departments');
const officesRoutes = require('./routes/offices');
const positionsRoutes = require('./routes/positions');
const shiftsRoutes = require('./routes/shifts');
const assignmentsRoutes = require('./routes/assignments');
const employeeOtherPositionsRoutes = require('./routes/employeeOtherPositions');
const employeesRoutes = require('./routes/employees');
const uploadRoutes = require('./routes/upload');
const filesRoutes = require('./routes/files');
const holidaysRoutes = require('./routes/holidays');
const attendancePoliciesRoutes = require('./routes/attendancePolicies');
const policyAssignmentsRoutes = require('./routes/policyAssignments');
const biometricDevicesRoutes = require('./routes/biometricDevices');
const biometricAttendanceLogsRoutes = require('./routes/biometricAttendanceLogs');
const overtimeRoutes = require('./routes/overtime');
const calendarRoutes = require('./routes/calendar');
const dtrDailySummaryRoutes = require('./routes/dtrDailySummary');
const dtrAssistantRoutes = require('./routes/dtrAssistant');
const docutrackerRoutes = require('./routes/docutracker');
const trainingDailyReportsRoutes = require('./routes/trainingDailyReports');
const ldTrainingRequirementsRoutes = require('./routes/ldTrainingRequirements');
const rspJobVacanciesRoutes = require('./routes/rspJobVacancies');
const rspExamQuestionsRoutes = require('./routes/rspExamQuestions');
const rspExamTimeLimitsRoutes = require('./routes/rspExamTimeLimits');
const rspApplicationsRoutes = require('./routes/rspApplications');
const rspEmailVerificationPublicRoutes = require('./routes/rspEmailVerificationPublic');
const rspStorageRoutes = require('./routes/rspStorage');
const rspLdSavedEntriesRoutes = require('./routes/rspLdSavedEntries');
const leaveRoutes = require('./routes/leaveRoutes');
const notificationsRoutes = require('./routes/notifications');
const locatorSlipsRoutes = require('./routes/locatorSlips');
const contactPublicRoutes = require('./routes/contactPublic');
const {
  isEmailJsConfiguredForHireEmail,
  isEmailJsContactConfigured,
} = require('./utils/emailJsMail');
const { isUniSmsConfigured } = require('./utils/uniSmsSms');

const { startDocutrackerEscalationWorker } = require('./services/docutrackerEscalationWorker');

const app = express();

// Behind nginx/Caddy on Kamatera (HTTPS) so req.ip / rate limits see real client IP
if (process.env.TRUST_PROXY === '1' || process.env.TRUST_PROXY === 'true') {
  app.set('trust proxy', 1);
}

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0'; // 0.0.0.0 = accessible from LAN

if (!process.env.JWT_SECRET) {
  console.warn('[warn] JWT_SECRET not set; auth routes will fail. Add JWT_SECRET to .env');
}
if (!process.env.JWT_REFRESH_SECRET) {
  console.warn(
    '[warn] JWT_REFRESH_SECRET not set; login/register/refresh will fail. Add JWT_REFRESH_SECRET to .env',
  );
}

// Middleware (large limit: RSP/L&D forms e.g. turn-around tables with many JSON rows)
const corsOrigins = process.env.CORS_ORIGINS?.split(',').map((s) => s.trim()).filter(Boolean);
if (corsOrigins && corsOrigins.length > 0) {
  app.use(cors({ origin: corsOrigins }));
} else {
  app.use(cors());
}
app.use(express.json({ limit: '15mb' }));

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
app.use('/api', generalApiLimiter);
app.use('/auth', authRoutes);
app.use('/api/departments', departmentsRoutes);
app.use('/api/offices', officesRoutes);
app.use('/api/positions', positionsRoutes);
app.use('/api/shifts', shiftsRoutes);
app.use('/api/assignments', assignmentsRoutes);
app.use('/api/employee-other-positions', employeeOtherPositionsRoutes);
app.use('/api/employees', employeesRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/files', filesRoutes);
app.use('/api/holidays', holidaysRoutes);
app.use('/api/attendance-policies', attendancePoliciesRoutes);
app.use('/api/policy-assignments', policyAssignmentsRoutes);
app.use('/api/biometric-devices', biometricDevicesRoutes);
app.use('/api/biometric-attendance-logs', biometricAttendanceLogsRoutes);
app.use('/api/overtime', overtimeRoutes);
app.use('/api/calendar', calendarRoutes);
app.use('/api/dtr-daily-summary', dtrDailySummaryRoutes);
app.use('/api/dtr-assistant', dtrAssistantRoutes);
app.use('/api/docutracker', docutrackerRoutes);
app.use('/api/training-daily-reports', trainingDailyReportsRoutes);
app.use('/api/ld/training-requirements', ldTrainingRequirementsRoutes);
app.use('/api/rsp/job-vacancies', rspJobVacanciesRoutes);
app.use('/api/rsp/exam-questions', rspExamQuestionsRoutes);
app.use('/api/rsp/exam-time-limits', rspExamTimeLimitsRoutes);
app.use('/api/rsp/applications', rspApplicationsRoutes);
app.use('/api/rsp/email-verification', rspEmailVerificationPublicRoutes);
app.use('/api/rsp/storage', rspStorageRoutes);
app.use('/api/rsp-ld-saved-entries', rspLdSavedEntriesRoutes);
app.use('/api/leave', leaveRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/locator-slips', locatorSlipsRoutes);
app.use('/api/contact', contactPublicRoutes);

// --- Start server ---
const server = app.listen(PORT, HOST, () => {
  console.log(`HRMS API listening on http://${HOST}:${PORT}`);
  console.log('  GET  /health           - app health');
  console.log('  GET  /health/db        - database health');
  if (isEmailJsConfiguredForHireEmail()) {
    console.log('  EmailJS hire email     - enabled (POST …/send-hire-email)');
  } else {
    console.log(
      '  EmailJS hire email     - off (set EMAILJS_SERVICE_ID, EMAILJS_PUBLIC_KEY, EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID; else SMTP)',
    );
  }
  if (isEmailJsContactConfigured()) {
    console.log('  EmailJS contact form   - enabled (POST /api/contact)');
  }
  if (isUniSmsConfigured()) {
    console.log('  UniSMS OTP             - enabled (POST /auth/forgot-password)');
  } else {
    console.log('  UniSMS OTP             - off (set UNISMS_API_SECRET_KEY for forgot-password)');
  }
  if (rspEmailVerificationPublicRoutes.rspEmailOtpEnrollmentActive?.()) {
    console.log(
      '  RSP email OTP          - enabled (GET/POST /api/rsp/email-verification/*)',
    );
    console.log(
      '  EmailJS OTP mail       - requires non-browser API + Private Key in EmailJS Security',
    );
  }
  if (isEmailJsConfiguredForHireEmail() || isEmailJsContactConfigured()) {
    console.log(
      '  EmailJS security      - allow non-browser API: https://dashboard.emailjs.com/admin/account/security',
    );
    console.log(
      '  EmailJS strict mode   - set EMAILJS_PRIVATE_KEY if dashboard requires Private Key (403)',
    );
  }
  console.log('  POST /auth/login       - login');
  console.log('  POST /auth/register    - register');
  console.log('  POST /auth/refresh     - new access token (refresh token body)');
  console.log('  POST /auth/logout      - revoke refresh token');
  console.log('  GET  /auth/me          - current user (requires JWT)');
  console.log('  API  /api/departments  /api/positions  /api/shifts');
  console.log('  API  /api/assignments  /api/employees');
  console.log('  POST /api/upload/avatar  GET /api/files/avatar/:userId');
  console.log('  PUT   /api/rsp/job-vacancies  - update landing page vacancy entries');
  console.log('  PATCH /api/rsp/job-vacancies/accepting - hiring on/off (auto-save)');
  console.log('  PUT  /api/rsp/exam-questions/:examType - admin save exam questions');
  console.log('  GET  /api/rsp/exam-time-limits - public exam countdown limits');
  console.log('  PUT  /api/rsp/exam-time-limits - admin set per-exam time limits (seconds)');
  console.log('  DELETE /api/rsp/applications/:applicationId - admin delete applicant');
  console.log('  GET  /api/rsp/storage/view-token - admin token for /api/files/recruitment-attachment');
  console.log('  GET  /api/rsp/storage/signed-url - admin signed attachment URL (service role)');
  console.log('  API  /api/rsp-ld-saved-entries/:table - RSP/L&D saved forms (admin JWT, PostgreSQL)');
  scheduleLeaveMonthlyAccrualCron(pool);
  scheduleYearEndForcedLeaveCron(pool);
  scheduleAuthRefreshTokenCleanupCron(pool);
  // DocuTracker: server-side escalation worker (workflow control).
  try {
    startDocutrackerEscalationWorker();
  } catch (e) {
    console.error('[docutracker escalation worker] failed to start', e);
  }
});

// Initialize WebSocket servers and route upgrade requests by path.
const biometricWss = initWebSocket();
const appEventsWss = initAppEventsWebSocket();

server.on('upgrade', (req, socket, head) => {
  let pathname;
  try {
    pathname = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
      .pathname;
  } catch (_) {
    socket.destroy();
    return;
  }

  const targetWss =
    pathname === '/ws/biometrics'
      ? biometricWss
      : pathname === '/ws/app'
        ? appEventsWss
        : null;

  if (!targetWss) {
    socket.destroy();
    return;
  }

  targetWss.handleUpgrade(req, socket, head, (ws) => {
    targetWss.emit('connection', ws, req);
  });
});
