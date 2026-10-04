const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { resolveDtrReportSignatories } = require('../services/officialSignatoryService');

const router = express.Router();

// Employees also need the current printed officials for their own DTR exports.
router.get('/', authMiddleware, async (req, res) => {
  try {
    const effectiveDate = todayInHrmsTimezone();
    const roles = await resolveDtrReportSignatories(pool, effectiveDate);
    return res.json({ effective_date: effectiveDate, roles });
  } catch (error) {
    console.error('[DTR report signatories]', error);
    return res.status(500).json({ error: 'Report signatories could not be loaded.' });
  }
});

module.exports = router;
