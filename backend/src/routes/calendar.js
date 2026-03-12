const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/calendar-events?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&employee_id=uuid (optional)
// Returns events for the range: holidays (all), and if employee_id given then shift/rest per day.
router.get('/events', protect, async (req, res) => {
  try {
    const startDate = req.query.start_date;
    const endDate = req.query.end_date;
    const employeeId = req.query.employee_id;

    if (!startDate || !endDate) {
      return res.status(400).json({ error: 'start_date and end_date are required (YYYY-MM-DD)' });
    }
    const start = new Date(startDate);
    const end = new Date(endDate);
    if (isNaN(start.getTime()) || isNaN(end.getTime()) || start > end) {
      return res.status(400).json({ error: 'Invalid start_date or end_date' });
    }

    const events = [];

    // Holidays in range
    const holidaysResult = await pool.query(
      `SELECT holiday_date, name, holiday_type FROM holidays WHERE holiday_date >= $1::date AND holiday_date <= $2::date ORDER BY holiday_date`,
      [startDate, endDate]
    );
    for (const r of holidaysResult.rows) {
      events.push({
        date: r.holiday_date,
        type: 'holiday',
        label: r.name,
        holiday_type: r.holiday_type,
      });
    }

    // For the given employee: assignment-effective shift per day (Schema v2: effective_from / effective_to)
    if (employeeId) {
      const assignmentsResult = await pool.query(
        `SELECT a.effective_from, a.effective_to, a.override_start_time, a.override_end_time,
                s.name AS shift_name, s.start_time AS shift_start, s.end_time AS shift_end
         FROM assignments a
         LEFT JOIN shifts s ON a.shift_id = s.id
         WHERE a.employee_id = $1 AND (a.is_active IS NULL OR a.is_active = true)
           AND a.effective_from <= $2::date AND (a.effective_to IS NULL OR a.effective_to >= $3::date)
         ORDER BY a.effective_from DESC`,
        [employeeId, endDate, startDate]
      );
      const assignments = assignmentsResult.rows;

      const day = new Date(start);
      while (day <= end) {
        const dStr = day.toISOString().slice(0, 10);
        const hasHoliday = events.some((e) => e.date === dStr && e.type === 'holiday');
        if (!hasHoliday) {
          const assignment = assignments.find(
            (a) => a.effective_from <= dStr && (a.effective_to == null || a.effective_to >= dStr)
          );
          if (assignment?.shift_name) {
            const startT = assignment.override_start_time || assignment.shift_start;
            const endT = assignment.override_end_time || assignment.shift_end;
            events.push({
              date: dStr,
              type: 'shift',
              label: assignment.shift_name,
              shift_start: startT,
              shift_end: endT,
              employee_id: employeeId,
            });
          } else {
            events.push({
              date: dStr,
              type: 'rest',
              label: 'Rest day',
              employee_id: employeeId,
            });
          }
        }
        day.setDate(day.getDate() + 1);
      }
    }

    res.json({ events });
  } catch (err) {
    console.error('[calendar/events GET]', err);
    res.status(500).json({ error: 'Failed to fetch calendar events' });
  }
});

module.exports = router;
