const express = require('express');
const {
  sendContactUsEmailJs,
  isEmailJsContactConfigured,
} = require('../utils/emailJsMail');

const router = express.Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** POST /api/contact — public; sends EmailJS "Contact Us" template to HR inbox. */
router.post('/', async (req, res) => {
  try {
    if (!isEmailJsContactConfigured()) {
      return res.status(503).json({
        error: 'Contact form is not available',
        details:
          'Set EMAILJS_SERVICE_ID, EMAILJS_PUBLIC_KEY, and EMAILJS_TEMPLATE_CONTACT_US_ID on the server.',
      });
    }

    const { title, name, email, message } = req.body || {};
    const t = typeof title === 'string' ? title.trim() : '';
    const n = typeof name === 'string' ? name.trim() : '';
    const e = typeof email === 'string' ? email.trim().toLowerCase() : '';
    const m = typeof message === 'string' ? message.trim() : '';

    if (!t || t.length > 200) {
      return res.status(400).json({ error: 'Subject is required (max 200 characters)' });
    }
    if (!n || n.length > 120) {
      return res.status(400).json({ error: 'Name is required (max 120 characters)' });
    }
    if (!e || !EMAIL_RE.test(e) || e.length > 254) {
      return res.status(400).json({ error: 'A valid email address is required' });
    }
    if (!m || m.length > 8000) {
      return res.status(400).json({
        error: 'Message is required (max 8000 characters)',
      });
    }

    await sendContactUsEmailJs({
      title: t,
      name: n,
      email: e,
      message: m,
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error('[contact POST]', err);
    const msg = err?.message ? String(err.message) : String(err);
    return res.status(500).json({
      error: 'Failed to send message',
      details: msg,
    });
  }
});

module.exports = router;
